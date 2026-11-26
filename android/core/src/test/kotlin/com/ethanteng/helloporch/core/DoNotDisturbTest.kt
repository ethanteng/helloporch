package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json

class DoNotDisturbTest {
    private val zone = ZoneId.of("America/Los_Angeles")
    private fun at(hour: Int, minute: Int = 0): Instant = ZonedDateTime.of(2026, 11, 25, hour, minute, 0, 0, zone).toInstant()

    @Test fun offUntilTurnedOnAndKeptOnThisPhone() {
        val prefs = MemorySettings()
        val start = DoNotDisturb.load(prefs)
        assertFalse(start.on); assertFalse(start.scheduled)
        assertEquals(listOf(22, 7), listOf(start.startHour, start.endHour), "the hours offered first are overnight")
        assertFalse(start.applies(at(23), zone), "the hours do nothing until scheduled")
        start.copy(on = true).save(prefs)
        assertEquals(start.copy(on = true), DoNotDisturb.load(prefs))
        assertTrue(DoNotDisturb.load(prefs).applies(at(12), zone))
    }

    @Test fun scheduledHoursRunPastMidnightAndTheSameHourIsAllDay() {
        val night = DoNotDisturb(scheduled = true)
        assertTrue(night.applies(at(22), zone)); assertTrue(night.applies(at(6, 59), zone))
        assertFalse(night.applies(at(7), zone)); assertFalse(night.applies(at(21, 59), zone))
        val work = night.copy(startHour = 9, endHour = 17)
        assertTrue(work.applies(at(9), zone)); assertFalse(work.applies(at(17), zone))
        assertTrue(night.copy(startHour = 9, endHour = 9).applies(at(3), zone))
    }

    @Test fun checkInsSayHoursOnlyWhenScheduledWithThisPhonesTimeZone() {
        val tokyo = ZoneId.of("Asia/Tokyo")
        assertEquals(Json.parseToJsonElement("""{"on":false}"""), DoNotDisturb().checkIn(tokyo), "all off still says so, to clear it")
        assertEquals(Json.parseToJsonElement("""{"on":true}"""), DoNotDisturb(on = true).checkIn(tokyo))
        assertEquals(Json.parseToJsonElement("""{"on":true,"hours":{"start":23,"end":6},"timeZone":"Asia/Tokyo"}"""),
            DoNotDisturb(on = true, scheduled = true, startHour = 23, endHour = 6).checkIn(tokyo))
    }

    @Test fun savedHoursOutOfRangeFallBackToTheDefaults() {
        val prefs = MemorySettings()
        prefs.putString("porch.doNotDisturb.v1", """{"on":true,"scheduled":true,"startHour":30,"endHour":7}""")
        assertEquals(DoNotDisturb(), DoNotDisturb.load(prefs))
        DoNotDisturb(startHour = -2, endHour = 40).save(prefs)
        assertEquals(listOf(0, 23), DoNotDisturb.load(prefs).let { listOf(it.startHour, it.endHour) })
    }
}
