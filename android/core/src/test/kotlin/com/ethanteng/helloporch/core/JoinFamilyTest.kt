package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.FakeTransport.Companion.failure
import com.ethanteng.helloporch.core.FakeTransport.Companion.ok
import com.ethanteng.helloporch.core.TestFamilies.family
import com.ethanteng.helloporch.core.TestFamilies.snapshot
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

@OptIn(ExperimentalCoroutinesApi::class)
class JoinFamilyTest {
    private val invitation = FamilyInvitation("porch://pair?server=https://porch.example&code=${"c".repeat(64)}")
    private val another = FamilyInvitation("porch://pair?server=https://porch.example&code=${"d".repeat(64)}")

    /** A server with households, which knows each device by its ID. An invitation's code says which household it's
     * for; `leave` answers `leaveHousehold`. */
    private class Server(val phone: FamilyHarness) {
        val households = mutableMapOf<String, Pair<String, String>>()
        val invitations = mutableMapOf<String, Pair<String, String>>()
        var claim: suspend (FakeTransport.Request) -> TransportResponse? = { null }
        var leave: suspend (FakeTransport.Request) -> TransportResponse = { ok() }

        init {
            phone.transport.reply = { request ->
                when (request.action) {
                    "claimInvite" -> claim(request) ?: run {
                        val deviceID = request["deviceID"]!!.jsonPrimitive.content
                        val household = invitations.getValue(request["code"]!!.jsonPrimitive.content)
                        households[deviceID] = household
                        ok(mapOf("credential" to "$deviceID.${request["deviceSecret"]!!.jsonPrimitive.content}", "role" to "family",
                            "state" to snapshot(deviceID, householdID = household.first, householdName = household.second)))
                    }
                    "poll" -> households[request.deviceID]?.let { ok(mapOf("state" to snapshot(request.deviceID!!, householdID = it.first, householdName = it.second))) }
                        ?: failure(401, "This phone was removed.")
                    "leaveHousehold" -> leave(request).also { if (it.status == 200) households.remove(request.deviceID) }
                    else -> ok()
                }
            }
        }

        /** A family this phone is already in. */
        fun joined(credential: FamilyCredential, householdID: String, name: String, noted: Boolean = true) {
            phone.device.save(credential)
            households[credential.deviceID] = householdID to name
            if (noted) phone.device.noteHousehold(TestFamilies.state(snapshot(credential.deviceID, householdID = householdID, householdName = name)), credential)
        }
    }

    private suspend fun FamilyHarness.join(invitation: FamilyInvitation, nickname: String? = null) =
        joinFamily(invitation, nickname, device, coordinator, serviceFor, serviceAt)

    private fun TestScope.server(): Server = Server(FamilyHarness(this)).apply {
        invitations["c".repeat(64)] = "home" to "Lee family"
        invitations["d".repeat(64)] = "home" to "Lee family"
    }

    @Test fun aFirstJoinPairsSelectsAndStartsCheckingIn() = runTest {
        val server = server()
        val phone = server.phone
        val joined = phone.join(invitation)
        val claim = phone.transport.requests("claimInvite").single()
        assertNull(claim.headers["Authorization"])
        assertEquals(setOf("action", "deviceID", "deviceSecret", "code", "platform"), claim.body.keys)
        assertEquals(JsonPrimitive("c".repeat(64)), claim["code"])
        assertEquals(JsonPrimitive("android"), claim["platform"])
        assertEquals("${claim["deviceID"]!!.jsonPrimitive.content}.${claim["deviceSecret"]!!.jsonPrimitive.content}", joined.credential.credential)
        assertEquals(TestFamilies.origin, joined.credential.origin)
        assertEquals(JoinedFamily(joined.credential), joined, "nothing else here is called Lee family")
        assertEquals(listOf(joined.credential), phone.device.families)
        assertEquals(joined.credential, phone.device.currentFamily)
        assertEquals("home", phone.device.householdID(joined.credential))
        assertNull(phone.device.nickname(joined.credential))
        assertTrue(phone.coordinator.isActive)
        runCurrent()
        assertEquals("Lee family", phone.coordinator.state?.householdName)
    }

    @Test fun anInvitationTheServerDoesntAcceptSaysSo() = runTest {
        val server = server()
        server.claim = { failure(410, "This invitation has expired. Ask for a new one.") }
        assertEquals(410, assertFailsWith<FamilyServiceException> { server.phone.join(invitation) }.status)
        server.claim = { ok() }
        assertEquals(FamilyInvitation.invalid, assertFailsWith<ValidationException> { server.phone.join(invitation) }.message)
        assertEquals(emptyList(), server.phone.device.families)
    }

    /** Reopening an invitation this phone already used returns the same identity, which doesn't add one. */
    @Test fun rejoiningWithTheSameInvitationOffersTheSameIdentity() = runTest {
        val server = server()
        val phone = server.phone
        server.claim = { throw IOException("offline") }
        assertEquals(0, assertFailsWith<FamilyServiceException> { phone.join(invitation) }.status)
        server.claim = { null }
        val joined = phone.join(invitation)
        val again = phone.join(invitation)
        val identities = phone.transport.requests("claimInvite").map { it["deviceID"] to it["deviceSecret"] }
        assertEquals(1, identities.toSet().size)
        assertEquals(joined, again)
        assertEquals(listOf(joined.credential), phone.device.families)
    }

    /** Claiming an invitation for a fifth family would use it up, so it's turned away first, even one from one of the
     * four. One this phone already used still works. */
    @Test fun aPhoneIsInAtMostFourFamilies() = runTest {
        val server = server()
        val phone = server.phone
        for (number in 1..3) server.joined(family(number), "house-$number", "Family $number")
        val joined = phone.join(invitation)
        assertEquals(4, phone.device.families.size)
        assertEquals(joined, phone.join(invitation))
        phone.transport.requests.clear()
        val refused = assertFailsWith<FamilyServiceException> { phone.join(another) }
        assertEquals(409, refused.status)
        assertEquals("This phone is in 4 families, the most Porch allows. To join another, or to join one of these again with a new invitation, leave one in Settings first.", refused.message)
        assertTrue(phone.transport.requests("claimInvite").isEmpty())
        assertEquals(4, phone.device.families.size)
    }

    /** A new invitation from a family this phone is already in replaces its old pairing there, keeping what the phone
     * called it. It leaves only once the family has accepted this phone again. */
    @Test fun aNewInvitationFromTheSameHouseholdReplacesTheOldPairing() = runTest {
        val server = server()
        val phone = server.phone
        server.joined(family(1), "home", "Lee family")
        server.joined(family(2), "other", "Mom")
        phone.device.setNickname("Grandma", family(1))
        val joined = phone.join(invitation)
        val leave = phone.transport.requests("leaveHousehold").single()
        assertEquals(family(1).deviceID, leave.deviceID)
        assertTrue(phone.transport.requests.indexOf(leave) > phone.transport.requests.indexOf(phone.transport.requests("claimInvite").single()))
        assertEquals(listOf(family(2), joined.credential), phone.device.families)
        assertEquals("Grandma", phone.device.nickname(joined.credential))
        assertNull(phone.device.nickname(family(1)))
        assertNull(phone.device.householdID(family(1)))
        assertEquals(joined.credential, phone.device.currentFamily)
    }

    /** The old pairing is kept so Join can retry; reclaiming the invitation returns the same identity. */
    @Test fun aFailedLeaveKeepsTheOldPairingForARetry() = runTest {
        val server = server()
        val phone = server.phone
        server.joined(family(1), "home", "Lee family")
        server.leave = { failure(500, "Try again.") }
        val failed = assertFailsWith<FamilyServiceException> { phone.join(invitation) }
        assertEquals("Couldn't switch families. Check your internet and tap Join family again.", failed.message)
        assertEquals(503, failed.status)
        assertEquals(listOf(family(1)), phone.device.families)
        server.leave = { throw IOException("offline") }
        assertEquals(503, assertFailsWith<FamilyServiceException> { phone.join(invitation) }.status)
        assertEquals(listOf(family(1)), phone.device.families)

        // Already removed, or its household is gone: nothing is left to leave.
        server.leave = { failure(404, "No such household.") }
        val joined = phone.join(invitation)
        assertEquals(listOf(joined.credential), phone.device.families)
        assertEquals(1, phone.transport.requests("claimInvite").map { it["deviceID"] }.toSet().size)
    }

    /** A pairing that hasn't said which household it's in is asked once, so a new invitation from that family still
     * replaces it. One on another server can't be the same family. */
    @Test fun aFamilyWhoseHouseholdIsUnknownIsAskedOnce() = runTest {
        val server = server()
        val phone = server.phone
        server.joined(family(1), "home", "Lee family", noted = false)
        server.joined(family(2, origin = "https://other.example"), "home", "Lee family", noted = false)
        val joined = phone.join(invitation)
        val polls = phone.transport.requests("poll")
        assertEquals(listOf(family(1).deviceID), polls.map { it.deviceID })
        assertEquals(JsonPrimitive(true), polls.single()["available"])
        assertEquals(JsonPrimitive(1L), polls.single()["sequence"])
        assertEquals(listOf(family(1).deviceID), phone.transport.requests("leaveHousehold").map { it.deviceID })
        assertEquals(listOf(family(2, origin = "https://other.example"), joined.credential), phone.device.families)
    }

    @Test fun theNicknameTypedWinsOverTheOneKept() = runTest {
        val server = server()
        val phone = server.phone
        server.joined(family(1), "home", "Lee family")
        phone.device.setNickname("Grandma", family(1))
        val joined = phone.join(invitation, nickname = "  Sarah's parents ")
        assertEquals("Sarah's parents", phone.device.nickname(joined.credential))
        val rejoined = phone.join(another, nickname = "   ")
        assertEquals("Sarah's parents", phone.device.nickname(rejoined.credential), "a blank one keeps the old name")
    }

    /** Two sets of parents are often both "Mom". Left unnamed, the new one is numbered, so the phone asks. */
    @Test fun joiningASecondMomAsksWhatToCallIt() = runTest {
        val server = server()
        val phone = server.phone
        server.joined(family(1), "moms-house", "Mom")
        server.invitations["c".repeat(64)] = "other-moms-house" to "Mom"
        val joined = phone.join(invitation)
        assertEquals(JoinedFamily(joined.credential, sharedName = "Mom", numberedName = "Mom 2"), joined)
        assertEquals(listOf(family(1), joined.credential), phone.device.families)
        assertTrue(phone.transport.requests("leaveHousehold").isEmpty())

        server.invitations["d".repeat(64)] = "third" to "Mom"
        val named = phone.join(another, nickname = "Dad's mom")
        assertEquals(JoinedFamily(named.credential), named, "a family named as it joins isn't asked about")
    }
}
