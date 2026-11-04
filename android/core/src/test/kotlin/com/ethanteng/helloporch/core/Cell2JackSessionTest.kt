package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.Cell2JackDigitEvent.Kind
import com.ethanteng.helloporch.core.FakeCell2JackLink.Companion.bytes
import com.ethanteng.helloporch.core.FakeCell2JackLink.Control
import com.ethanteng.helloporch.core.FakeCell2JackLink.Read
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

@OptIn(ExperimentalCoroutinesApi::class)
class Cell2JackSessionTest {
    private class Harness(val scope: TestScope, chipVersion: Int = 0x31, packetSize: Int = 32) {
        val link = FakeCell2JackLink({ scope.testScheduler.currentTime }, packetSize, chipVersion)
        val diagnostics = Cell2JackDiagnostics()
        val updates = mutableListOf<Cell2JackUpdate>()
        private val session = Cell2JackSession(link, diagnostics) { scope.testScheduler.currentTime }
        lateinit var job: Job

        fun start() = apply { job = scope.launch { session.run { updates += it } } }
        val finished get() = updates.filterIsInstance<Cell2JackUpdate.Finished>().map { it.message }
        val events get() = updates.filterIsInstance<Cell2JackUpdate.Keys>().flatMap { it.events }
        fun records(kind: String) = diagnostics.records().filter { it["kind"]?.toString() == "\"$kind\"" }
    }

    /**
     * ReadVersion in PorchCell2JackDriver.cpp, request by request, copied from the driver rather than from the
     * session: bmRequestType, bRequest, wValue, wIndex, wLength, and 500 ms each. The plan's init table says the same.
     */
    private fun driverInit(baudIndex: Int) = listOf(
        Control(0xC0, 0x5F, 0x0000, 0x0000, 2, 500), // chip version
        Control(0x40, 0xA1, 0x0000, 0x0000, 0, 500), // serial init
        Control(0x40, 0x9A, 0x1312, baudIndex, 0, 500), // 2 Mbaud
        Control(0x40, 0x9A, 0x2518, 0x00C3, 0, 500), // 8N1, RX and TX on
        Control(0x40, 0x9A, 0x2727, 0x0000, 0, 500), // hardware flow control off
        Control(0x40, 0xA4, 0xFFFF, 0x0000, 0, 500), // DTR and RTS inactive
    )

    @Test fun anOldAndANewChipGetTheDriversInitAndShortPacketBaud() = runTest {
        // 0x30 is the oldest chip the driver accepts. Every accepted chip is past 0x27, so each gets bit 7 (0xFD83);
        // 0xFD03 is only reachable through baudRegister, which Cell2JackProtocolTest checks.
        for (chip in listOf(0x30, 0x31, 0x40)) {
            val harness = Harness(this, chipVersion = chip).start()
            advanceTimeBy(600)
            assertEquals(driverInit(0xFD83), harness.link.controls, "chip 0x%02x".format(chip))
            assertEquals(listOf("/v", "/d"), harness.link.commands)
            harness.job.cancel()
        }
    }

    @Test fun aChipOlderThan0x30IsRejectedAfterOnlyTheVersionRequest() = runTest {
        val harness = Harness(this, chipVersion = 0x27).start()
        advanceTimeBy(5_000)
        assertEquals(driverInit(0xFD03).take(1), harness.link.controls)
        assertEquals(emptyList(), harness.link.commands, "Nothing goes to the serial side, not even /q")
        assertEquals(listOf("Phone keypad unavailable: CH340 version 0x27 isn't supported"), harness.finished)
        assertTrue(harness.link.closed)
        assertTrue(harness.job.isCompleted)
    }

    @Test fun slashVThenAHalfSecondThenSlashDAndSlashQWhenItStops() = runTest {
        val harness = Harness(this).start()
        advanceTimeBy(1_000)
        val (version, logs) = harness.link.writes
        assertEquals(FakeCell2JackLink.Write("/v", 0, 500), version)
        assertEquals(FakeCell2JackLink.Write("/d", 500, 500), logs)
        // The 35-byte version line comes in two 32-byte packets; then the logs are read 250 ms at a time.
        assertEquals(listOf(500, 500, 250, 250), harness.link.readTimeouts.take(4))
        assertEquals("a06", harness.records("usbVersion").single()["version"]?.toString()?.trim('"'))

        harness.job.cancel()
        runCurrent()
        assertEquals(listOf("/v", "/d", "/q"), harness.link.commands)
        assertEquals(listOf("Phone keypad stopped · /q sent"), harness.finished)
        assertTrue(harness.link.closed)
    }

    @Test fun theReplyToSlashVIsReadUpToSixTimesUntilANewline() = runTest {
        // A reply without a newline is kept after six reads, as the driver keeps partial timeout data.
        val partial = Harness(this)
        partial.link.versionReply = listOf(bytes("CJ Version = a06"))
        partial.start()
        advanceTimeBy(3_100)
        assertEquals(listOf(500, 500, 500, 500, 500, 500), partial.link.readTimeouts.take(6))
        assertEquals(FakeCell2JackLink.Write("/d", 3_000, 500), partial.link.writes.last())
        partial.job.cancel()

        val silent = Harness(this)
        silent.link.versionReply = emptyList()
        silent.start()
        advanceTimeBy(5_000)
        assertEquals(6, silent.link.readTimeouts.size)
        assertEquals(listOf("/v"), silent.link.commands, "No reply means no session, so no /q")
        assertEquals(listOf("Phone keypad unavailable: USB stage reply to /v failed: no reply"), silent.finished)
    }

    @Test fun withNoLogsWithinTwoSecondsItStartsAgainUpToThreeTimes() = runTest {
        val harness = Harness(this).start()
        advanceTimeBy(20_000)
        assertEquals(listOf("/v", "/d", "/q", "/v", "/d", "/q", "/v", "/d", "/q"), harness.link.commands)
        assertEquals(driverInit(0xFD83) + driverInit(0xFD83) + driverInit(0xFD83), harness.link.controls, "Each try starts from the init")
        val times = harness.link.writes.map { it.time }
        for (attempt in 0 until 3) {
            val waited = times[attempt * 3 + 2] - times[attempt * 3 + 1]
            assertTrue(waited in 2_000 until 2_300, "/q $waited ms after /d")
        }
        assertEquals(listOf("Phone keypad stopped: No device logs after three attempts. Unplug the Cell2Jack and plug it back in. · /q sent"), harness.finished)
        assertTrue(harness.link.closed)
    }

    @Test fun logsWithinTwoSecondsKeepTheFirstTry() = runTest {
        val harness = Harness(this)
        harness.link.logs = listOf(bytes(" ON_HOOK \r\n Set ON-hook 121\r\n"))
        harness.start()
        advanceTimeBy(30_000)
        assertEquals(listOf("/v", "/d"), harness.link.commands)
        assertEquals(listOf(Cell2JackUpdate.Ready), harness.updates.filter { it == Cell2JackUpdate.Ready })
        assertEquals(emptyList(), harness.link.clears, "Idle reads aren't stalls")
        harness.job.cancel()
    }

    @Test fun parsedKeysAndHangUpsFlowOutWithTheRawBytesKept() = runTest {
        val harness = Harness(this)
        val first = " DTMF 1 :0 20: 2\r\n DTM"
        val second = "F # :0 20: 2\r\nH1H2 ON_HOOK \r\n"
        harness.link.logs = listOf(bytes(first), bytes(second))
        harness.start()
        advanceTimeBy(6_000)
        assertEquals(Cell2JackUpdate.Ready, harness.updates.first { it !is Cell2JackUpdate.Health })
        assertEquals(listOf(Kind.DIGIT to "1", Kind.DIGIT to "#", Kind.HANG_UP to ""), harness.events.map { it.kind to it.digit })
        assertEquals(500L, harness.updates.filterIsInstance<Cell2JackUpdate.Keys>().first().receivedAt)
        assertContentEquals((first + second).toByteArray(), harness.diagnostics.rawTail())
        // Health at the first read and every five seconds after, with the session's counts.
        val health = harness.updates.filterIsInstance<Cell2JackUpdate.Health>()
        assertEquals(2, health.size)
        assertEquals(Cell2JackUpdate.Health(bytes = (first + second).length.toLong(), packets = 2, primaryDigits = 2), health.last())
        harness.job.cancel()
    }

    @Test fun aStalledReadIsClearedOnceAndRetriedOnce() = runTest {
        val recovered = Harness(this)
        recovered.link.logs = listOf(Read.Stall, bytes(" DTMF 7 :0 20: 2\r\n"))
        recovered.start()
        advanceTimeBy(1_000)
        assertEquals(listOf("in"), recovered.link.clears)
        assertEquals(listOf("7"), recovered.events.map { it.digit })
        assertEquals(emptyList(), recovered.finished)
        recovered.job.cancel()

        // A second stall is surfaced to the reconnect loop, never spun on.
        val twice = Harness(this)
        twice.link.logs = listOf(Read.Stall, Read.Stall, bytes(" DTMF 7 :0 20: 2\r\n"))
        twice.start()
        advanceTimeBy(1_000)
        assertEquals(listOf("in"), twice.link.clears)
        assertEquals(listOf("Phone keypad stopped: USB stage log read failed · /q sent"), twice.finished)
        assertEquals(1, twice.link.reads.size, "The record after the second stall is never read")

        val uncleared = Harness(this)
        uncleared.link.clearResult = -1
        uncleared.link.logs = listOf(Read.Stall, bytes(" DTMF 7 :0 20: 2\r\n"))
        uncleared.start()
        advanceTimeBy(1_000)
        assertEquals(listOf("in"), uncleared.link.clears)
        assertEquals(1, uncleared.link.reads.size, "A halt that won't clear isn't retried")
        assertEquals(listOf("Phone keypad stopped: USB stage log read failed · /q sent"), uncleared.finished)
    }

    @Test fun aStalledWriteIsClearedOnceAndRetriedOnce() = runTest {
        val recovered = Harness(this)
        recovered.link.stalledWrites = 1
        recovered.start()
        advanceTimeBy(1_000)
        assertEquals(listOf("out"), recovered.link.clears)
        assertEquals(listOf("/v", "/d"), recovered.link.commands)
        recovered.job.cancel()

        val twice = Harness(this)
        twice.link.stalledWrites = 2
        twice.start()
        advanceTimeBy(1_000)
        assertEquals(listOf("out"), twice.link.clears)
        assertEquals(emptyList(), twice.link.commands)
        assertEquals(listOf("Phone keypad unavailable: USB stage /v failed"), twice.finished)
        assertEquals(listOf("out"), twice.records("usbStall").map { it["endpoint"].toString().trim('"') })
    }

    @Test fun unpluggingEndsTheSessionWithoutSpinning() = runTest {
        val harness = Harness(this)
        harness.link.logs = listOf(bytes(" ON_HOOK \r\n"))
        harness.start()
        advanceTimeBy(1_000)
        harness.link.unplugged = true
        advanceTimeBy(1_000)
        assertEquals(listOf("Phone keypad stopped: USB stage log read failed · /q unconfirmed; unplug Cell2Jack if logging persists"), harness.finished)
        assertTrue(harness.link.closed && harness.job.isCompleted)
    }

    @Test fun packetSizesOf0AndOver256AreRejected() = runTest {
        for (size in listOf(0, 257)) {
            val harness = Harness(this, packetSize = size).start()
            advanceTimeBy(1_000)
            assertEquals(listOf("Phone keypad unavailable: Unsupported USB packet size $size"), harness.finished)
            assertEquals(emptyList(), harness.link.controls)
            assertTrue(harness.link.closed)
        }
        for (size in listOf(1, 256)) {
            val harness = Harness(this, packetSize = size)
            harness.link.logs = listOf(bytes(" DTMF 3 :0 20: 2\r\n"))
            harness.start()
            advanceTimeBy(4_000)
            assertEquals(listOf("/v", "/d"), harness.link.commands, "packet size $size")
            assertEquals(listOf("3"), harness.events.map { it.digit })
            harness.job.cancel()
        }
    }
}
