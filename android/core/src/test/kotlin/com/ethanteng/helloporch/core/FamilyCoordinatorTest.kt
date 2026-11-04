package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.FakeTransport.Companion.failure
import com.ethanteng.helloporch.core.FakeTransport.Companion.ok
import com.ethanteng.helloporch.core.TestFamilies.call
import com.ethanteng.helloporch.core.TestFamilies.family
import com.ethanteng.helloporch.core.TestFamilies.snapshot
import java.io.IOException
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

@OptIn(ExperimentalCoroutinesApi::class)
class FamilyCoordinatorTest {
    private fun FamilyHarness.answerPolls(snapshot: (FakeTransport.Request) -> Map<String, Any?> = { snapshot(it.deviceID!!) }) {
        transport.reply = { if (it.action == "poll") ok(mapOf("state" to snapshot(it))) else ok() }
    }
    private fun FamilyHarness.pollTimes(available: Boolean = true) =
        transport.requests("poll").filter { it["available"] == JsonPrimitive(available) }.map { it.time }

    @Test fun aFamilyPhoneChecksInEveryThreeSecondsAndTheBedsideEveryTwo() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1))
        phone.answerPolls()
        phone.coordinator.start()
        advanceTimeBy(9_500)
        assertEquals(listOf(0L, 3_000, 6_000, 9_000), phone.pollTimes())

        val tablet = FamilyHarness(this, canBeBedside = true)
        tablet.device.save(TestFamilies.bedside(2))
        tablet.answerPolls { snapshot(it.deviceID!!, role = "bedside") }
        tablet.coordinator.start()
        advanceTimeBy(6_500)
        assertEquals(listOf(9_500L, 11_500, 13_500, 15_500), tablet.pollTimes())
        assertTrue(tablet.transport.requests.all { it.deviceID == TestFamilies.bedside(2).deviceID })
    }

    /** And with no backoff: a server that's down is asked again just as often. */
    @Test fun whileACallIsntEndedItChecksInEverySecond() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1))
        var polls = 0
        phone.answerPolls {
            polls += 1
            snapshot(it.deviceID!!, call = call(state = if (polls < 3) "accepted" else "ended"))
        }
        phone.coordinator.start()
        advanceTimeBy(5_500)
        assertEquals(listOf(0L, 1_000, 2_000, 5_000), phone.pollTimes())

        phone.transport.requests.clear()
        phone.transport.reply = { throw IOException("offline") }
        advanceTimeBy(9_000)
        assertEquals(listOf(8_000L, 11_000, 14_000), phone.pollTimes(), "the ended call is still the last state")
    }

    @Test fun everyPollSaysWhetherThisDeviceCanRingAndIsNumbered() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1))
        phone.answerPolls()
        phone.coordinator.start()
        runCurrent()
        phone.receiving = false
        advanceTimeBy(3_500)
        val (first, second) = phone.transport.requests("poll")
        assertEquals(listOf(JsonPrimitive(true), JsonPrimitive(false)), listOf(first["available"], second["available"]))
        assertEquals(first["launch"], second["launch"])
        assertEquals(listOf(1L, 2L), listOf(first, second).map { it["sequence"]!!.jsonPrimitive.content.toLong() })
        assertNull(first["attendedSeconds"], "only the bedside says when someone was there")
    }

    /** A family's household is noted as it checks in, so a call that rings before the next check-in can say which
     * family it's from. */
    @Test fun eachCheckInIsPublishedAndItsHouseholdNoted() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1))
        phone.answerPolls { snapshot(it.deviceID!!, householdID = "lee", householdName = "Lee family") }
        phone.coordinator.start()
        runCurrent()
        val links = phone.coordinator.links.value
        assertEquals("Lee family", links.state?.householdName)
        assertEquals(family(1), links.credential)
        assertEquals(family(1).deviceID, links.currentID)
        assertEquals(links, phone.changes.last(), "afterChange sees what's published")
        assertEquals("lee", phone.device.householdID(family(1)))
        assertSame(phone.coordinator.state, links.state)
    }

    @Test fun anErrorKeepsTheLastStateAndSaysWhy() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1))
        phone.answerPolls { snapshot(it.deviceID!!, householdName = "Lee family") }
        phone.coordinator.start()
        runCurrent()
        val known = phone.coordinator.links.value.state
        phone.transport.reply = { failure(500, "Porch is down for a moment.") }
        advanceTimeBy(3_500)
        with(phone.coordinator.links.value) {
            assertEquals(known, state); assertEquals("Porch is down for a moment.", error); assertFalse(accessRemoved)
        }
        phone.transport.reply = { throw IOException("offline") }
        advanceTimeBy(3_000)
        assertEquals(known, phone.coordinator.state)
        assertEquals(FamilyService.unreachable, phone.coordinator.error)
        phone.answerPolls { snapshot(it.deviceID!!, householdName = "Lee family") }
        advanceTimeBy(3_000)
        assertNull(phone.coordinator.error)
    }

    /** A dropped connection isn't the family putting the phone back: only a later successful check-in clears it. */
    @Test fun a401MeansAccessWasRemovedUntilACheckInSucceeds() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1))
        phone.transport.reply = { failure(401, "This phone was removed.") }
        phone.coordinator.start()
        runCurrent()
        assertTrue(phone.coordinator.accessRemoved)
        assertEquals("This phone was removed.", phone.coordinator.links.value.error)
        phone.transport.reply = { throw IOException("offline") }
        advanceTimeBy(3_000)
        assertTrue(phone.coordinator.links.value.accessRemoved)
        phone.answerPolls()
        advanceTimeBy(3_000)
        assertFalse(phone.coordinator.links.value.accessRemoved)
    }

    /** Each family is told this phone can't ring now, numbered after any check-in still on its way. */
    @Test fun pauseStopsCheckingInAndTellsEachFamily() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1)); phone.device.save(family(2))
        phone.transport.reply = { delay(500); ok(mapOf("state" to snapshot(it.deviceID!!))) }
        phone.coordinator.start()
        runCurrent()
        val inFlight = phone.transport.requests("poll").toList()
        assertEquals(listOf(family(1).deviceID, family(2).deviceID), inFlight.map { it.deviceID })
        phone.coordinator.pause()
        assertFalse(phone.coordinator.isActive)
        advanceTimeBy(20_000)
        val paused = phone.transport.requests("poll").drop(2)
        assertEquals(listOf(family(1).deviceID, family(2).deviceID), paused.map { it.deviceID })
        assertTrue(paused.all { it["available"] == JsonPrimitive(false) })
        val sequence = { request: FakeTransport.Request -> request["sequence"]!!.jsonPrimitive.content.toLong() }
        assertTrue(paused.minOf(sequence) > inFlight.maxOf(sequence))
        assertNull(phone.coordinator.state, "a check-in cut off by pausing isn't applied")
    }

    @Test fun theBedsideSaysHowLongAgoSomeoneWasThereWhileSharingIsOn() = runTest {
        val tablet = FamilyHarness(this, canBeBedside = true)
        tablet.device.save(TestFamilies.bedside(1))
        var sharing = true
        tablet.answerPolls { snapshot(it.deviceID!!, role = "bedside", extra = mapOf("shareAttendance" to sharing)) }
        tablet.attendance.noticed()
        tablet.coordinator.start()
        runCurrent()
        sharing = false
        advanceTimeBy(2_500)
        advanceTimeBy(2_000)
        assertNull(tablet.attendance.secondsSince, "nothing is kept while sharing is off")
        tablet.attendance.noticed()
        sharing = true
        advanceTimeBy(4_000)
        tablet.attendance.noticed()
        advanceTimeBy(2_000)
        val reported = tablet.transport.requests("poll").map { it["attendedSeconds"]?.jsonPrimitive?.content?.toInt() }
        // Not before the first check-in says it's on. Then nothing while it's off, nor for anyone noticed meanwhile.
        assertEquals(listOf(null, 2, null, null, null, 1), reported)
    }

    @Test fun updateGoesToTheFamilyThatKnowsThisDeviceByItsID() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1)); phone.device.save(family(2))
        phone.transport.reply = { awaitCancellation() }
        phone.coordinator.start()
        runCurrent()
        phone.coordinator.update(ModelFixtures.decoded(mapOf("state" to snapshot(family(2).deviceID, householdName = "Lee family"))))
        val links = phone.coordinator.links.value
        assertEquals("Lee family", links.state(family(2))?.householdName)
        assertNull(links.state(family(1)))
        assertNull(links.state, "the screens still show the first family")
        phone.coordinator.update(ModelFixtures.decoded(mapOf("state" to snapshot(family(3).deviceID))))
        phone.coordinator.update(FamilyResponse())
        assertSame(links, phone.coordinator.links.value)
    }

    @Test fun selectingAFamilyShowsItAndEndsCaregiverMode() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1)); phone.device.save(family(2))
        phone.transport.reply = { awaitCancellation() }
        phone.coordinator.start()
        phone.caregiver.begin("123456")
        phone.coordinator.select(family(1))
        assertTrue(phone.caregiver.isActive, "already showing")
        phone.coordinator.select(family(2))
        assertEquals(family(2), phone.coordinator.credential)
        assertEquals(family(2).deviceID, phone.coordinator.links.value.currentID)
        assertEquals(family(2), phone.device.currentFamily)
        assertFalse(phone.caregiver.isActive)
        phone.coordinator.select(TestFamilies.bedside(3))
        assertEquals(family(2), phone.coordinator.credential)
    }

    @Test fun leavingAFamilyKeepsTheOthersRinging() = runTest {
        val phone = FamilyHarness(this)
        phone.device.save(family(1)); phone.device.save(family(2))
        phone.answerPolls()
        phone.coordinator.start()
        runCurrent()
        phone.transport.reply = { if (it.action == "leaveHousehold") failure(500, "Try again.") else ok(mapOf("state" to snapshot(it.deviceID!!))) }
        assertEquals(500, assertFailsWith<FamilyServiceException> { phone.coordinator.leave(family(1)) }.status)
        assertEquals(listOf(family(1), family(2)), phone.device.families)

        // Already removed, or its household is gone: nothing is left to leave.
        phone.transport.reply = { if (it.action == "leaveHousehold") failure(404, "No such household.") else ok(mapOf("state" to snapshot(it.deviceID!!))) }
        phone.coordinator.leave(family(1))
        assertEquals(listOf(family(2)), phone.device.families)
        phone.transport.requests.clear()
        advanceTimeBy(3_500)
        assertEquals(setOf(family(2).deviceID), phone.transport.requests("poll").filter { it["available"] == JsonPrimitive(true) }.map { it.deviceID }.toSet())
        assertEquals(listOf(family(2)), phone.coordinator.links.value.links.map { it.credential })

        phone.coordinator.pause()
        phone.coordinator.forget(family(2))
        assertEquals(emptyList(), phone.coordinator.links.value.links)
        assertEquals(emptyList(), phone.device.families)
    }

    @Test fun startingACallUsesTheHouseholdsWait() = runTest {
        val phone = FamilyHarness(this)
        assertEquals("Pair this device first.", assertFailsWith<FamilyServiceException> {
            phone.coordinator.startCall(null, "Mom", NativeCall.Mode.VIDEO, dropIn = false)
        }.message)
        phone.device.save(family(1))
        var kind = "call"
        phone.transport.reply = {
            when (it.action) {
                "poll" -> awaitCancellation()
                "startCall" -> ok(mapOf("state" to snapshot(family(1).deviceID, call = call(kind = kind, from = family(1).deviceID), extra = mapOf("ringSeconds" to 30))))
                else -> ok()
            }
        }
        phone.coordinator.start()
        val person = ModelFixtures.decoded<FamilyPerson>(ModelFixtures.person("bedside-1", "Mom"))
        val session = phone.coordinator.startCall(person, NativeCall.Mode.VIDEO, dropIn = false)
        val request = phone.transport.requests("startCall").single()
        assertEquals(ModelFixtures.json(mapOf("action" to "startCall", "mode" to "video", "kind" to "call", "waitSeconds" to 45, "targetID" to "bedside-1")), request.body)
        assertEquals(30, session.waitSeconds)
        assertEquals("Mom", session.peerName)
        assertEquals("b", session.peerID)
        assertEquals("call-1", phone.coordinator.state?.call?.id, "the call's snapshot is applied")

        // The server decides whether an ordinary call drops in, from this phone's caregiver setting.
        kind = "dropIn"
        val dropIn = phone.coordinator.startCall(null, "Mom", NativeCall.Mode.VOICE, dropIn = false, waitSeconds = 20)
        assertEquals(CallPreferences.dropInWaitSeconds, dropIn.waitSeconds)
        val unlinked = phone.transport.requests("startCall").last()
        assertEquals(JsonPrimitive(true), unlinked["unlinked"]); assertNull(unlinked["targetID"])
        assertEquals(JsonPrimitive("voice"), unlinked["mode"]); assertEquals(JsonPrimitive(20), unlinked["waitSeconds"])

        phone.transport.reply = { if (it.action == "startCall") ok(mapOf("state" to snapshot(family(1).deviceID))) else awaitCancellation() }
        val refused = assertFailsWith<FamilyServiceException> { phone.coordinator.startCall(person, NativeCall.Mode.VIDEO, dropIn = true) }
        assertEquals("Couldn't start the call.", refused.message); assertEquals(503, refused.status)
    }

    @Test fun theBedsideRingsForAsLongAsItWasAsked() = runTest {
        val tablet = FamilyHarness(this, canBeBedside = true)
        tablet.device.save(TestFamilies.bedside(1))
        tablet.transport.reply = {
            if (it.action == "poll") awaitCancellation()
            else ok(mapOf("state" to snapshot(it.deviceID!!, role = "bedside", call = call(kind = "dropIn"), extra = mapOf("ringSeconds" to 30))))
        }
        tablet.coordinator.start()
        assertEquals(60, tablet.coordinator.startCall("family-1", "Ethan", NativeCall.Mode.VIDEO, dropIn = true, waitSeconds = 60).waitSeconds)
    }

    /** A newer call replaced this one, and the server has already released it. */
    @Test fun endingACallThatsGoneCountsAsEnded() = runTest {
        val transport = FakeTransport { failure(404, "No such call.") }
        val record = ModelFixtures.decoded<FamilyCallRecord>(call(from = family(1).deviceID, to = "bedside"))
        val session = FamilyCallSession(family(1), record, "Mom", FamilyService(family(1), transport))
        assertEquals("bedside", session.peerID)
        session.endConfirmed()
        assertEquals(ModelFixtures.json(mapOf("action" to "endCall", "callID" to "call-1")), transport.requests.single().body)
        transport.reply = { failure(500, "Try again.") }
        assertEquals(500, assertFailsWith<FamilyServiceException> { session.endConfirmed() }.status)
        session.end()
        transport.reply = { throw IOException("offline") }
        session.end()
        assertEquals(4, transport.requests.size)
    }

    @Test fun caregiverModeEndsAfterTenIdleMinutes() {
        var now = Instant.parse("2026-11-03T12:00:00Z")
        val session = RemoteCaregiverSession { now }
        assertNull(session.activePIN)
        session.begin("123456")
        now = now.plusSeconds(599)
        assertEquals("123456", session.activePIN, "using it counts as activity")
        now = now.plusSeconds(599)
        assertTrue(session.isActive)
        now = now.plusSeconds(1)
        assertFalse(session.isActive)
        assertNull(session.activePIN)
        session.begin("654321"); session.end()
        assertNull(session.activePIN)
    }
}
