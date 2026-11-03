package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Android key codes (`KeyEvent.KEYCODE_*`), where the iOS tests use HID usages. */
private const val KEY_0 = 7
private const val KEY_1 = 8
private const val KEY_3 = 10
private const val KEY_8 = 15
private const val KEY_STAR = 17
private const val KEY_POUND = 18
private const val KEY_A = 29
private const val KEY_ENTER = 66
private const val KEY_BACKSLASH = 73
private const val NUMPAD_0 = 144
private const val NUMPAD_1 = 145
private const val NUMPAD_MULTIPLY = 155
private const val NUMPAD_DOT = 158
private const val NUMPAD_ENTER = 160

class CallTriggerTest {
    @Test fun heldKeyCannotRepeatUntilReleased() {
        val trigger = CallTrigger()
        assertTrue(trigger.keyDown(NUMPAD_1))
        assertFalse(trigger.keyDown(NUMPAD_1))
        trigger.keyUp(NUMPAD_1)
        assertTrue(trigger.keyDown(NUMPAD_1))
        assertNull(CallTrigger.slot(NUMPAD_ENTER, "\n", shift = false)) // keypad Enter must not call
    }

    @Test fun keypadAndKeyboardRouteToAllTenDigits() {
        val trigger = CallTrigger()
        for (slot in 1..9) {
            for (code in listOf(NUMPAD_1 + slot - 1, KEY_1 + slot - 1)) {
                assertEquals(slot, CallTrigger.slot(code))
                assertTrue(trigger.keyDown(code))
                assertFalse(trigger.keyDown(code))
                trigger.keyUp(code)
            }
        }
        assertEquals(0, CallTrigger.slot(NUMPAD_0))
        assertEquals(0, CallTrigger.slot(KEY_0))
        for (code in listOf(NUMPAD_ENTER, NUMPAD_DOT, KEY_ENTER, KEY_A)) assertNull(CallTrigger.slot(code))
    }

    @Test fun starAndPoundRouteFromKeypadsAndKeyboardsOfAnyLayout() {
        assertEquals(CallSlots.star, CallTrigger.slot(NUMPAD_MULTIPLY)) // keypad *
        assertEquals(CallSlots.star, CallTrigger.slot(KEY_STAR))
        assertEquals(CallSlots.pound, CallTrigger.slot(KEY_POUND))
        assertEquals(CallSlots.star, CallTrigger.slot(NUMPAD_MULTIPLY, "*", shift = false))
        // Keyboards type them with Shift: 8 and 3 on a US layout, and # has its own key on a UK one.
        assertEquals(CallSlots.star, CallTrigger.slot(KEY_8, "*", shift = true))
        assertEquals(CallSlots.pound, CallTrigger.slot(KEY_3, "#", shift = true))
        assertEquals(CallSlots.pound, CallTrigger.slot(KEY_BACKSLASH, "#", shift = false))
        assertEquals(1, CallTrigger.slot(KEY_1, "1", shift = false))
        assertNull(CallTrigger.slot(KEY_1, "!", shift = true), "Shift never turns a digit key into that digit")
        assertNull(CallTrigger.slot(KEY_3, "£", shift = true))
        val trigger = CallTrigger()
        assertTrue(trigger.keyDown(KEY_BACKSLASH))
        assertFalse(trigger.keyDown(KEY_BACKSLASH))
        trigger.keyUp(KEY_BACKSLASH)
        assertTrue(trigger.keyDown(KEY_BACKSLASH))
    }

    @Test fun touchAndKeyboardShareCooldownEvenAfterFocusReset() {
        val trigger = CallTrigger()
        assertTrue(trigger.allowLaunch(10.0))
        trigger.resetKeys()
        assertFalse(trigger.allowLaunch(11.0))
        assertTrue(trigger.allowLaunch(12.0))
    }

    @Test fun callControlDistinguishesTapHoldDropInAndCancellation() {
        val input = IncomingCallKey()
        assertNull(input.begin(NUMPAD_0, dropIn = false)); assertNull(input.begin(NUMPAD_0, dropIn = false))
        assertEquals(IncomingCallKey.Decision.ANSWER, input.release(NUMPAD_0)); assertNull(input.release(NUMPAD_0))
        assertNull(input.begin(NUMPAD_0, dropIn = false)); assertEquals(IncomingCallKey.Decision.DECLINE, input.held(NUMPAD_0))
        assertNull(input.release(NUMPAD_0), "A declined call must never also answer on key release")
        assertEquals(IncomingCallKey.Decision.DECLINE, input.begin(NUMPAD_0, dropIn = true)); assertNull(input.release(NUMPAD_0))
        assertNull(input.begin(NUMPAD_0, dropIn = false)); input.cancel(); assertNull(input.release(NUMPAD_0))
    }
}
