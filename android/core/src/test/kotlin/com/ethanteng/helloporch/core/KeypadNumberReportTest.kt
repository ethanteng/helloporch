package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.FakeTransport.Companion.failure
import com.ethanteng.helloporch.core.FakeTransport.Companion.ok
import com.ethanteng.helloporch.core.TestFamilies.snapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

@OptIn(ExperimentalCoroutinesApi::class)
class KeypadNumberReportTest {
    private val david = "+14155550200"

    /** A bedside whose keypad has David's number, checking in with a server that has `heard` as its copy. Each
     * snapshot reports, as the app's `afterChange` does. */
    private class Bedside(scope: TestScope, var pin: String? = "246810") {
        val harness = FamilyHarness(scope, canBeBedside = true)
        val slots = CallSlots().apply { setContact(CallContact("David", NativeCall("david", NativeCall.Mode.VOICE), phoneNumber = "+14155550200"), 1) }
        var heard: List<String>? = emptyList()
        var answerReport: suspend (FakeTransport.Request) -> TransportResponse = { request ->
            heard = (request["numbers"] as JsonArray).map { (it as JsonPrimitive).content }
            ok(mapOf("state" to state(request)))
        }
        val report = KeypadNumberReport(scope.backgroundScope, harness.serviceFor, { pin }, { scope.testScheduler.currentTime })
        val reports get() = harness.transport.requests("setKeypadNumbers")

        fun state(request: FakeTransport.Request) = snapshot(request.deviceID!!, role = "bedside",
            extra = mapOf("callScreening" to mapOf("enabled" to true, "keypadNumbers" to heard, "allowed" to emptyList<Any>(), "blocked" to emptyList<Any>())))

        init {
            harness.device.save(TestFamilies.bedside(1))
            harness.transport.reply = { if (it.action == "setKeypadNumbers") answerReport(it) else ok(mapOf("state" to state(it))) }
            harness.onChange = { report.report(slots, harness.coordinator) }
        }
    }

    @Test fun theKeypadsNumbersAreReportedWithThePINUntilTheServerHasThem() = runTest {
        val bedside = Bedside(this)
        bedside.harness.coordinator.start()
        advanceTimeBy(6_500)
        val (report) = bedside.reports
        assertEquals(JsonArray(listOf(JsonPrimitive(david))), report["numbers"])
        assertEquals("246810", report.headers["X-Porch-Setup-Code"])
        assertEquals(listOf(david), bedside.harness.coordinator.state?.callScreening?.keypadNumbers, "the reply's snapshot is shown")
    }

    @Test fun withoutThePINNothingIsReportedUntilItCanBeRead() = runTest {
        val bedside = Bedside(this, pin = null)
        bedside.harness.coordinator.start()
        advanceTimeBy(4_500)
        assertTrue(bedside.reports.isEmpty())
        bedside.pin = "246810"
        advanceTimeBy(2_000)
        assertEquals(1, bedside.reports.size)
    }

    @Test fun aFailedReportWaitsThirtySecondsAndAWrongPINTenMinutes() = runTest {
        val bedside = Bedside(this)
        bedside.answerReport = { failure(500, "Down") }
        bedside.harness.coordinator.start()
        advanceTimeBy(29_500)
        assertEquals(listOf(0L), bedside.reports.map { it.time }, "every two-second snapshot waits")
        advanceTimeBy(2_000)
        assertEquals(listOf(0L, 30_000), bedside.reports.map { it.time })

        bedside.answerReport = { failure(403, "That PIN isn't right.") }
        advanceTimeBy(628_000)
        assertEquals(listOf(0L, 30_000, 60_000), bedside.reports.map { it.time })
        advanceTimeBy(2_000)
        assertEquals(listOf(0L, 30_000, 60_000, 660_000), bedside.reports.map { it.time })
    }

    /** One report at a time. Pausing ends it: its reply doesn't replace the next session's snapshot, and that session
     * reports for itself. */
    @Test fun aReportInFlightBelongsToItsSession() = runTest {
        val bedside = Bedside(this)
        val first = CompletableDeferred<TransportResponse>()
        bedside.answerReport = { first.await() }
        bedside.harness.coordinator.start()
        advanceTimeBy(4_500)
        assertEquals(1, bedside.reports.size, "later snapshots wait for the one in flight")

        bedside.harness.coordinator.pause()
        bedside.answerReport = { request -> bedside.heard = listOf(david); ok(mapOf("state" to bedside.state(request))) }
        bedside.harness.coordinator.start()
        runCurrent()
        assertEquals(2, bedside.reports.size)
        assertEquals(listOf(david), bedside.harness.coordinator.state?.callScreening?.keypadNumbers)

        first.complete(ok(mapOf("state" to snapshot(TestFamilies.bedside(1).deviceID, role = "bedside"))))
        runCurrent()
        assertEquals(listOf(david), bedside.harness.coordinator.state?.callScreening?.keypadNumbers, "the old reply isn't shown")
    }
}
