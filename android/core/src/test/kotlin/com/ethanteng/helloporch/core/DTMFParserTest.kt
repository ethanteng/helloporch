package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.Cell2JackDigitEvent.Kind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DTMFParserTest {
    private fun bytes(text: String) = text.toByteArray(Charsets.UTF_8)

    /** Every way of splitting `text` into two reads gives the same events. */
    private fun everySplit(text: String, check: (List<Cell2JackDigitEvent>) -> Unit) {
        val bytes = bytes(text)
        for (split in 0..bytes.size) {
            val parser = Cell2JackDTMFParser()
            check(parser.append(bytes.copyOfRange(0, split)) + parser.append(bytes.copyOfRange(split, bytes.size)))
        }
    }

    @Test fun observedCaptureSurvivesEverySplitAndBytewiseFraming() {
        val observed = " DTMF 1 :0 20: 2\r\n DTMF 2 :1 20: 2\r\n DTMF 3 :2 20: 2\r\n DTMF 0 :3 20: 2\r\n DTMF * :4 20: 2\r\n DTMF # :0 20: 2\r\n"
        everySplit(observed) { result ->
            assertEquals("1230*#", result.joinToString("") { it.digit })
            assertTrue(result.all { it.kind == Kind.DIGIT })
        }
        val fragmented = Cell2JackDTMFParser()
        val digits = mutableListOf<Cell2JackDigitEvent>()
        for (byte in bytes(observed)) digits += fragmented.append(byteArrayOf(byte))
        assertEquals("1230*#", digits.joinToString("") { it.digit })
    }

    @Test fun repeatsConfigOverflowAndBinaryLines() {
        val parser = Cell2JackDTMFParser()
        val repeatEvents = parser.append(bytes("DTMF 5 :0\nDTMF 5 :1\nDouble DTMF 5\rRX Double DTMF 5\n"))
        assertEquals("5555", repeatEvents.joinToString("") { it.digit })
        assertEquals(listOf(Kind.DIGIT, Kind.DIGIT, Kind.DOUBLE_REPORT, Kind.DOUBLE_REPORT), repeatEvents.map { it.kind })
        val config = "DTMF=1, DTMFO=2\nUnknown DTMF key 1\nDTMFIS=0\nCJ Version = a06\nDTMF 12\nDTMF X\nnot DTMF 1\n"
        assertTrue(parser.append(bytes(config)).isEmpty())
        val keys = "0123456789*#ABCD"
        assertEquals(keys, parser.append(bytes(keys.map { "DTMF $it\r" }.joinToString(""))).joinToString("") { it.digit })
        assertTrue(parser.append(bytes("DTMF 9")).isEmpty())
        parser.resetPartialLine()
        assertTrue(parser.append(bytes(" :0\n")).isEmpty())
        val oversized = ByteArray(4097) { 32 } + bytes("DTMF 8\nDTMF 7\r\n")
        assertEquals(listOf("7"), parser.append(oversized).map { it.digit })
        assertTrue(parser.append(byteArrayOf(0xff.toByte()) + bytes("DTMF 1\n")).isEmpty())
        assertEquals(listOf("4"), parser.append(bytes("DTMF 4\r")).map { it.digit })
        assertTrue(parser.append(bytes("\n")).isEmpty())
        val diagnostic = parser.append(bytes(" Cal RX Double DTMF 1 :0 20: 2\n"))
        assertTrue(diagnostic.size == 1 && diagnostic[0].kind == Kind.DOUBLE_REPORT)
        assertTrue(parser.append(bytes("status mentions DTMF 1\nUnknown DTMF key 1\nstatus DTMF 12 :0 20: 2\n")).isEmpty())
    }

    @Test fun aRecordJoinedToAStatusFragmentIsRecovered() {
        everySplit(" Cal DTMF 1 :0 20: 2\r\n") { recovered ->
            assertEquals(listOf("1"), recovered.map { it.digit })
            assertTrue(recovered[0].embeddedInLine)
        }
    }

    @Test fun pickupPulsesAreIgnoredAndHangUpsFollowAPickup() {
        // Captured from the bedside's picture phone: the first pickup after reconnecting
        // Cell2Jack broke the line once, which it counted as a pulse-dialed 1. The next
        // pickup's 0 is a real key press.
        val pickups = "L1L2 OFF_HOOK \r\n Set OFF-hook 230\r\n Play tone\r\nH1H2L1L2 FLASH \r\n Set OFF-hook 230\r\n.. Get PULSE 1 1\r\n Stop Playing Dialtone\r\n DTMF 1 :0 20: 2\r\nH1H2.Loop 1: Null Addr\r\n ON_HOOK \r\nL1L2 OFF_HOOK \r\n Play tone\r\n Stop Playing Audio\r\n DTMF 0 :0 20: 2\r\nH1H2 ON_HOOK \r\n"
        everySplit(pickups) { events ->
            assertEquals(listOf(Kind.PULSE, Kind.HANG_UP, Kind.DIGIT, Kind.HANG_UP), events.map { it.kind })
            assertEquals(listOf("1", "0"), events.filter { it.kind != Kind.HANG_UP }.map { it.digit })
        }
        val stale = Cell2JackDTMFParser()
        assertEquals(listOf(Kind.DIGIT), stale.append(bytes(".. Get PULSE 1 1\r\n ON_HOOK \r\nL1L2 OFF_HOOK \r\n DTMF 3 :0 20: 2\r\n")).map { it.kind })
        // Captured when Cell2Jack was plugged back in: it reports ON_HOOK as it starts, with no
        // pickup before it. Only putting the receiver back after a pickup is a hang-up.
        val hooks = Cell2JackDTMFParser()
        assertTrue(hooks.append(bytes(" ON_HOOK \r\n Set ON-hook 121\r\n Set Ring = 0\r\n Set ON-hook 121\r\n--Cell2Jack CopyRight00\r\n")).isEmpty())
        val lifted = hooks.append(bytes("L1L2 OFF_HOOK \r\nH1H2L1L2 FLASH \r\n Set OFF-hook 230\r\nH1H2 ON_HOOK \r\n Set ON-hook 121\r\n ON_HOOK \r\n"))
        assertTrue(lifted.map { it.kind } == listOf(Kind.HANG_UP) && lifted[0].line == "H1H2 ON_HOOK " && lifted[0].digit.isEmpty())
        assertEquals(listOf(Kind.DIGIT, Kind.HANG_UP), hooks.append(bytes("L1L2 OFF_HOOK \r\nNON_HOOKED\r\n DTMF 0 :0 20: 2 H1H2 ON_HOOK \r\n")).map { it.kind })
        // Logs that start with the receiver already up: a key press shows it was off the cradle.
        val startedLifted = Cell2JackDTMFParser()
        assertEquals(listOf(Kind.DIGIT, Kind.HANG_UP), startedLifted.append(bytes(" DTMF 5 :0 20: 2\r\nH1H2 ON_HOOK \r\n ON_HOOK \r\n")).map { it.kind })
    }
}
