package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class Cell2JackProtocolTest {
    /** As ProtocolTests.cpp checks PorchC2JBaudRegister. */
    @Test fun theBaudRegisterIsTwoMegabaudWithShortPacketsPast0x27() {
        assertEquals(0xFD83, Cell2JackProtocol.baudRegister(0x31))
        assertEquals(0xFD03, Cell2JackProtocol.baudRegister(0x27))
        val encoded = Cell2JackProtocol.baudRegister(0x31)
        val divisor = 256 - (encoded shr 8)
        val prescaler = encoded and 3
        val factor = (encoded shr 2) and 1
        assertEquals(2_000_000, 48_000_000 / ((1 shl (12 - 3 * prescaler - factor)) * divisor))
        assertEquals(0x1A86 to 0x7523, Cell2JackProtocol.vendorID to Cell2JackProtocol.productID)
    }

    /** As VersionParserTests.swift checks Cell2JackVersionResult: the observed reply, fragmentation, malformed data and
     * raw rendering. */
    @Test fun onlyTheObservedVersionHeaderCounts() {
        fun version(text: String) = Cell2JackVersionResult(text.toByteArray()).version
        assertEquals("a06", version(" >>>>>>>>>>>>>> CJ Version = a06\r\n"))
        assertEquals("A06", version("CJ Version = A06\r\n"))
        assertNull(version("DTMF 1 :0 20: 2\r\n"))
        assertNull(version("CJ Version = a0"))
        assertNull(version("CJ Version = a061\n"))
        assertNull(version(""))
        val first = " >>> CJ Ver".toByteArray()
        val second = "sion = a06\r\n".toByteArray()
        assertNull(Cell2JackVersionResult(first).version)
        assertEquals("a06", Cell2JackVersionResult(first + second).version)
        val binary = Cell2JackVersionResult(byteArrayOf(0, 0xFF.toByte(), 0x0A, 0x41))
        assertNull(binary.version)
        assertEquals("\\x00\\xff\nA", binary.displayText)
        assertEquals("00 ff 0a 41", binary.hex)
    }

    @Test fun thePhoneKeypadIsOffAndReceiverHangUpOnUntilChanged() {
        val settings = MemorySettings()
        assertFalse(Cell2JackSettings.enabled(settings), "Off by default, including on installs from before the setting")
        assertTrue(Cell2JackSettings.receiverHangUp(settings))
        Cell2JackSettings.setEnabled(settings, true)
        Cell2JackSettings.setReceiverHangUp(settings, false)
        // The iOS app's keys, so a household's settings mean the same on both.
        assertEquals(true, settings.getBoolean("porch.cell2jack.enabled"))
        assertEquals(false, settings.getBoolean("porch.cell2jack.receiverHangUp"))
        assertTrue(Cell2JackSettings.enabled(settings))
        assertFalse(Cell2JackSettings.receiverHangUp(settings))
    }

    /** As the iOS test of SetupPhoneViewController: connected, a key, then hanging up. */
    @Test fun setupChecksAKeyThenHangingUp() {
        var check: Cell2JackPhoneCheck = Cell2JackPhoneCheck.Waiting
        assertEquals("Waiting for the phone…", check.status)
        check = check.answering(true)
        assertEquals("The phone is connected. Lift the receiver and press a key.", check.status)
        assertEquals(check, check.hangUp(), "A hang-up before a key")
        check = check.key("*", receiverHangUp = true)
        assertEquals("Porch heard *. Now put the receiver back.", check.status)
        assertFalse(check.checked)
        check = check.hangUp()
        assertEquals("Porch heard you hang up. The phone is ready.", check.status)
        assertTrue(check.checked)
        assertEquals(check, check.key("5", receiverHangUp = true), "The phone is already checked")
        assertEquals(check, check.answering(false), "Unplugging after the check doesn't undo it")
    }

    @Test fun withoutReceiverHangUpTheKeyIsTheCheckAndADropStartsOver() {
        val heard = Cell2JackPhoneCheck.Waiting.key("5", receiverHangUp = false)
        assertEquals("Porch heard 5. The phone is ready.", heard.status)
        assertTrue(heard.checked)
        // Unplugged before the check finished: a hang-up meanwhile went unheard.
        val connected = Cell2JackPhoneCheck.Waiting.answering(true)
        assertEquals(Cell2JackPhoneCheck.Waiting, connected.key("1", receiverHangUp = true).answering(false))
        assertEquals(Cell2JackPhoneCheck.Waiting, connected.answering(false))
        assertEquals(Cell2JackPhoneCheck.Heard("1"), connected.key("1", receiverHangUp = true).answering(true))
    }
}
