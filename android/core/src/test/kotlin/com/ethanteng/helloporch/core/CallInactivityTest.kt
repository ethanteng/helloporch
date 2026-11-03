package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CallInactivityTest {
    /** A timer on a test clock, and `update` at a time in seconds. */
    private class Timer(timeout: Double?) {
        private var now = 0L
        private val timer = CallInactivityTimer(timeout) { now }
        fun update(at: Double, connected: Boolean, speaking: Boolean): Boolean {
            now = (at * 1000).toLong()
            return timer.update(connected, speaking)
        }
        fun reset() = timer.reset()
    }

    @Test fun ringingAndReconnectionNeverCountTowardSilence() {
        val timer = Timer(120.0)
        assertFalse(timer.update(at = 0.0, connected = false, speaking = false))
        assertFalse(timer.update(at = 900.0, connected = false, speaking = false))
        assertFalse(timer.update(at = 901.0, connected = true, speaking = false))
        assertFalse(timer.update(at = 1020.0, connected = true, speaking = false))
        assertFalse(timer.update(at = 1021.0, connected = false, speaking = false))
        assertFalse(timer.update(at = 2000.0, connected = true, speaking = false))
        assertFalse(timer.update(at = 2119.0, connected = true, speaking = false))
        assertTrue(timer.update(at = 2120.0, connected = true, speaking = false))
    }

    @Test fun voicemailGreetingAndMessageRestartTheFullInterval() {
        val timer = Timer(30.0)
        assertFalse(timer.update(at = 0.0, connected = true, speaking = false))
        // The remote voicemail greeting counts as speech, as does Mom's message.
        for (second in 1..45) {
            assertFalse(timer.update(at = second.toDouble(), connected = true, speaking = true))
        }
        assertFalse(timer.update(at = 74.0, connected = true, speaking = false))
        assertTrue(timer.update(at = 75.0, connected = true, speaking = false))
    }

    @Test fun briefUtteranceBetweenTicksResetsSilence() {
        val timer = Timer(15.0)
        assertFalse(timer.update(at = 0.0, connected = true, speaking = false))
        assertFalse(timer.update(at = 14.5, connected = true, speaking = true))
        assertFalse(timer.update(at = 15.0, connected = true, speaking = false))
        assertFalse(timer.update(at = 29.0, connected = true, speaking = false))
        assertTrue(timer.update(at = 29.5, connected = true, speaking = false))
    }

    @Test fun disabledAndInvalidTimeoutsNeverDisconnect() {
        for (timeout in listOf(null, 0.0, -10.0, Double.POSITIVE_INFINITY, Double.NaN)) {
            val timer = Timer(timeout)
            assertFalse(timer.update(at = 0.0, connected = true, speaking = false))
            assertFalse(timer.update(at = 1_000_000.0, connected = true, speaking = false))
        }
    }

    @Test fun resetAndBackwardsClockStartANewInterval() {
        val timer = Timer(30.0)
        assertFalse(timer.update(at = 100.0, connected = true, speaking = false))
        timer.reset()
        assertFalse(timer.update(at = 200.0, connected = true, speaking = false))
        assertFalse(timer.update(at = 10.0, connected = true, speaking = false))
        assertFalse(timer.update(at = 39.0, connected = true, speaking = false))
        assertTrue(timer.update(at = 40.0, connected = true, speaking = false))
    }
}
