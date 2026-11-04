package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MessageAutoplayTest {
    private val zone = ZoneId.of("America/Los_Angeles")
    private fun at(hour: Int, minute: Int = 0): Instant = ZonedDateTime.of(2026, 10, 18, hour, minute, 0, 0, zone).toInstant()

    @Test fun autoplayIsOffUntilACaregiverTurnsItOnAndKeepsToItsHours() {
        val prefs = MemorySettings()
        var settings = MessageAutoplay.load(prefs)
        assertFalse(settings.enabled); assertFalse(settings.allows(at(12), zone))
        settings = settings.copy(enabled = true); settings.save(prefs)
        val saved = MessageAutoplay.load(prefs)
        assertEquals(settings, saved)
        assertFalse(saved.allows(at(7, 59), zone))
        assertTrue(saved.allows(at(8), zone)); assertTrue(saved.allows(at(20, 59), zone))
        assertFalse(saved.allows(at(21), zone))
        // Hours that wrap past midnight, for a night owl.
        val late = saved.copy(startHour = 20, endHour = 2)
        assertTrue(late.allows(at(23), zone)); assertTrue(late.allows(at(1), zone))
        assertFalse(late.allows(at(12), zone))
        val always = saved.copy(startHour = 9, endHour = 9)
        assertTrue(always.allows(at(3), zone))
    }

    @Test fun stopDefersOnlyMessagesThatWereAlreadyWaiting() {
        assertEquals(setOf("b"), MessageAutoplay.deferredMessageIDs(startedWith = listOf("a", "b"), stillReady = listOf("b", "c")))
        assertTrue(MessageAutoplay.deferredMessageIDs(startedWith = listOf("a"), stillReady = listOf("c")).isEmpty())
        assertTrue(MessageAutoplay.deferredMessageIDs(startedWith = listOf("a", "b"), stillReady = emptyList()).isEmpty())
    }

    @Test fun presenceNeedsACloseFaceForTwoSecondsAndFiresOnce() {
        val trigger = PresenceTrigger()
        // Someone across the room, or walking past, doesn't count.
        for (step in 0 until 17) assertFalse(trigger.observe(faceHeight = 0.05, time = step * 0.3))
        assertFalse(trigger.observe(faceHeight = 0.3, time = 5.0)); assertFalse(trigger.observe(faceHeight = null, time = 6.5))
        assertFalse(trigger.observe(faceHeight = 0.3, time = 7.0), "a gap restarts the count")
        assertFalse(trigger.observe(faceHeight = 0.3, time = 8.0))
        // A blink or a turned head for a moment doesn't.
        assertFalse(trigger.observe(faceHeight = null, time = 8.3))
        assertTrue(trigger.observe(faceHeight = 0.25, time = 9.0))
        assertFalse(trigger.observe(faceHeight = 0.25, time = 12.0), "only once until reset")
        trigger.reset()
        assertFalse(trigger.observe(faceHeight = 0.25, time = 20.0)); assertFalse(trigger.observe(faceHeight = 0.25, time = 21.0))
        assertTrue(trigger.observe(faceHeight = 0.25, time = 22.0))
    }
}
