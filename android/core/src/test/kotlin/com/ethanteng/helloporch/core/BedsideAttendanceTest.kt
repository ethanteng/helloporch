package com.ethanteng.helloporch.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BedsideAttendanceTest {
    @Test fun familySeeSomeoneIsThereThenHowLongAgoAndNothingOnceItsStale() {
        fun text(attendedAt: Double?, now: Double) = BedsideAttendance.text(attendedAt, now, device = "tablet")
        assertNull(text(attendedAt = null, now = 1000.0))
        assertEquals("Someone is at the tablet", text(attendedAt = 1000.0, now = 1000.0))
        assertEquals("Someone is at the tablet", text(attendedAt = 1000.0, now = 1089.0))
        // A server time a little behind the bedside's report still reads as now.
        assertEquals("Someone is at the tablet", text(attendedAt = 1005.0, now = 1000.0))
        assertEquals("Someone was at the tablet 1 minute ago", text(attendedAt = 1000.0, now = 1090.0))
        assertEquals("Someone was at the tablet 25 minutes ago", text(attendedAt = 0.0, now = 25 * 60 + 59.0))
        assertEquals("Someone was at the tablet 1 hour ago", text(attendedAt = 0.0, now = 3600.0))
        assertEquals("Someone was at the tablet 5 hours ago", text(attendedAt = 0.0, now = 5 * 3600 + 3599.0))
        assertEquals("Someone was at the tablet 1 day ago", text(attendedAt = 0.0, now = 86400.0))
        assertEquals("Someone was at the tablet 6 days ago", text(attendedAt = 0.0, now = 6 * 86400 + 86399.0))
        assertNull(text(attendedAt = 0.0, now = 7 * 86400.0))
        assertTrue(BedsideAttendance.isPresent(attendedAt = 1000.0, now = 1089.0))
        assertFalse(BedsideAttendance.isPresent(attendedAt = 1000.0, now = 1090.0))
        assertFalse(BedsideAttendance.isPresent(attendedAt = null, now = 1000.0))
    }

    @Test fun anIPadBedsideIsCalledAnIPad() {
        assertEquals("Someone is at the iPad", BedsideAttendance.text(attendedAt = 1000.0, now = 1000.0, device = "iPad"))
        assertEquals("Someone was at the iPad 5 minutes ago", BedsideAttendance.text(attendedAt = 1000.0, now = 1300.0, device = "iPad"))
    }

    @Test fun theCameraIsOffUntilACaregiverTurnsItOn() {
        val settings = MemorySettings()
        assertFalse(BedsideAttendance.cameraEnabled(settings))
        BedsideAttendance.setCameraEnabled(true, settings)
        assertTrue(BedsideAttendance.cameraEnabled(settings))
        BedsideAttendance.setCameraEnabled(false, settings)
        assertFalse(BedsideAttendance.cameraEnabled(settings))
    }

    @Test fun theBedsideReportsWholeSecondsSinceItLastNoticedSomeone() {
        var now = Instant.ofEpochSecond(1_800_000_000)
        val tracker = AttendanceTracker { now }
        assertNull(tracker.secondsSince, "nothing to report until someone is noticed")
        tracker.noticed()
        assertEquals(0, tracker.secondsSince)
        now = now.plusMillis(41_700)
        assertEquals(41, tracker.secondsSince)
        tracker.noticed()
        assertEquals(0, tracker.secondsSince)
        // A clock set back must not be reported as someone just arriving.
        now = now.minusSeconds(600)
        assertNull(tracker.secondsSince)
        tracker.noticed()
        assertEquals(0, tracker.secondsSince, "a touch after the clock changes still counts")
        tracker.forget()
        assertNull(tracker.secondsSince, "nothing from while sharing was off")
    }
}
