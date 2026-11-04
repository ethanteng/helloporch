package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.FakeCell2JackLink.Companion.bytes
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

@OptIn(ExperimentalCoroutinesApi::class)
class Cell2JackConnectorTest {
    /** A connector whose `open` gives the `n`th try (from 1) the link `links(n)` makes, or fails as an unplugged
     * Cell2Jack does when that's null. */
    private class Harness(val scope: TestScope, val links: (Int) -> FakeCell2JackLink? = { null }) {
        val updates = mutableListOf<Pair<Long, Cell2JackUpdate>>()
        val diagnostics = Cell2JackDiagnostics()
        var opens = 0
        private val now = { scope.testScheduler.currentTime }
        val job = scope.launch {
            Cell2JackConnector({ opens += 1; links(opens) ?: throw Cell2JackException("No Cell2Jack is plugged in") }, diagnostics, now)
                .run { updates += now() to it }
        }
        val connectTimes get() = updates.filter { it.second == Cell2JackUpdate.Connecting }.map { it.first }
        val delays get() = updates.mapNotNull { (it.second as? Cell2JackUpdate.Retrying)?.delaySeconds }
    }

    /** A Cell2Jack that answers and sends a line of logs, then stays idle and healthy. */
    private fun TestScope.answering() = FakeCell2JackLink({ testScheduler.currentTime }).apply { logs = listOf(bytes(" ON_HOOK \r\n")) }

    @Test fun theBackoffDoublesFromOneSecondToFifteen() {
        val backoff = Cell2JackBackoff()
        assertEquals(listOf(1, 2, 4, 8, 15, 15, 15), List(7) { backoff.next() })
        backoff.reset()
        assertEquals(listOf(1, 2), List(2) { backoff.next() })
    }

    @Test fun aMissingCell2JackIsTriedAgainAfter1_2_4_8ThenEvery15Seconds() = runTest {
        val harness = Harness(this)
        advanceTimeBy(50_000)
        assertEquals(listOf(0L, 1_000, 3_000, 7_000, 15_000, 30_000, 45_000), harness.connectTimes)
        assertEquals(listOf(1, 2, 4, 8, 15, 15, 15), harness.delays)
        val finished = harness.updates.mapNotNull { (it.second as? Cell2JackUpdate.Finished)?.message }.distinct()
        assertEquals(listOf("Phone keypad unavailable: No Cell2Jack is plugged in"), finished)
        harness.job.cancel()
    }

    @Test fun thirtyHealthySecondsResetTheWait() = runTest {
        // Three misses grow the wait to 8 s. The fourth try connects at 7 s and stays healthy past 30 s.
        lateinit var connected: FakeCell2JackLink
        val harness = Harness(this) { n -> if (n == 4) answering().also { connected = it } else null }
        advanceTimeBy(43_000)
        connected.unplugged = true
        advanceTimeBy(3_000)
        assertEquals(listOf(1, 2, 4, 1, 2), harness.delays, "Unplugged after 36 healthy seconds, it tries again a second later")
        harness.job.cancel()
    }

    @Test fun aConnectionThatDropsWithinThirtySecondsKeepsBackingOff() = runTest {
        lateinit var connected: FakeCell2JackLink
        val harness = Harness(this) { n -> if (n == 4) answering().also { connected = it } else null }
        advanceTimeBy(27_000)
        connected.unplugged = true
        advanceTimeBy(1_000)
        assertEquals(listOf(1, 2, 4, 8), harness.delays, "A briefly responsive but faulty adapter must not reset the backoff")
        harness.job.cancel()
    }

    @Test fun cancellingEndsTheSessionWithSlashQAndNoRetry() = runTest {
        lateinit var connected: FakeCell2JackLink
        val harness = Harness(this) { answering().also { connected = it } }
        advanceTimeBy(2_000)
        assertTrue(harness.updates.any { it.second == Cell2JackUpdate.Ready })
        harness.job.cancel()
        runCurrent()
        assertEquals(listOf("/v", "/d", "/q"), connected.commands)
        assertTrue(connected.closed)
        assertEquals(Cell2JackUpdate.Finished("Phone keypad stopped · /q sent"), harness.updates.last().second)
        val kinds = harness.diagnostics.records().map { it["kind"].toString().trim('"') }
        assertEquals(listOf("usbStartRequested", "usbChipVersion", "usbVersion", "usbReady", "usbHealth", "usbStopped"), kinds)
    }

    @Test fun diagnosticsKeepTheLast200ActionsAndTheLast64KiB() {
        var changes = 0
        val diagnostics = Cell2JackDiagnostics(now = { Instant.parse("2026-11-04T10:15:30.250Z") }, onChange = { changes += 1 })
        for (n in 0 until 250) diagnostics.record("digit", "n" to n)
        val records = diagnostics.records()
        assertEquals(200, records.size)
        assertEquals(JsonPrimitive(50), records.first()["n"])
        assertEquals(JsonPrimitive(249), records.last()["n"])
        assertEquals(JsonPrimitive("2026-11-04T10:15:30Z"), records.last()["utc"])
        assertEquals(250, changes)

        // Health's counts are cumulative, so only the latest one in a row is kept.
        diagnostics.record("usbHealth", "bytes" to 10)
        diagnostics.record("usbHealth", "bytes" to 20)
        assertEquals(listOf(JsonPrimitive(249), JsonPrimitive(20)), diagnostics.records().takeLast(2).map { it["n"] ?: it["bytes"] })
        assertEquals(200, (Json.parseToJsonElement(diagnostics.json()) as JsonArray).size)

        assertNull(diagnostics.rawTailIfChanged())
        val sent = ByteArray(70_000) { (it % 251).toByte() }
        for (start in sent.indices step 32) diagnostics.appendRaw(sent.copyOfRange(start, minOf(start + 32, sent.size)))
        assertContentEquals(sent.copyOfRange(sent.size - 65_536, sent.size), diagnostics.rawTailIfChanged())
        assertNull(diagnostics.rawTailIfChanged(), "Nothing new to save")
    }
}
