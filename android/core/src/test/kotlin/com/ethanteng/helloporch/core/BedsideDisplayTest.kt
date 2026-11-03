package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneOffset
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BedsideDisplayTest {
    private val zone = ZoneOffset.UTC
    private fun date(month: Int = 10, hour: Int, minute: Int = 0): Instant = ZonedDateTime.of(2026, month, 16, hour, minute, 0, 0, zone).toInstant()

    @Test fun sunAndMoonFollowScheduleAcrossMidnight() {
        val prefs = BedsidePreferences()
        val dawn = BedsideScene(date(hour = 6), prefs, zone)
        val midday = BedsideScene(date(hour = 12), prefs, zone)
        val dusk = BedsideScene(date(hour = 18), prefs, zone)
        val midnight = BedsideScene(date(hour = 0), prefs, zone)
        assertTrue(dawn.isDay); assertEquals(0.0, dawn.progress)
        assertEquals(0.5, midday.progress); assertEquals(BedsideScene.Period.AFTERNOON, midday.period)
        assertFalse(dusk.isDay); assertEquals(0.0, dusk.progress); assertEquals(BedsideScene.Period.EVENING, dusk.period)
        assertEquals(0.5, midnight.progress); assertEquals(BedsideScene.Period.NIGHT, midnight.period)
        for (hour in 0..23) {
            val scene = BedsideScene(date(hour = hour, minute = 59), prefs, zone)
            assertTrue(scene.progress >= 0); assertTrue(scene.progress < 1)
        }
    }

    @Test fun seasonsFollowHemisphereAndLocalCalendar() {
        var prefs = BedsidePreferences()
        val seasons = listOf(
            Triple(1, BedsideScene.Season.WINTER, BedsideScene.Season.SUMMER), Triple(4, BedsideScene.Season.SPRING, BedsideScene.Season.FALL),
            Triple(7, BedsideScene.Season.SUMMER, BedsideScene.Season.WINTER), Triple(10, BedsideScene.Season.FALL, BedsideScene.Season.SPRING),
        )
        for ((month, north, south) in seasons) {
            prefs = prefs.copy(hemisphere = BedsidePreferences.Hemisphere.NORTHERN)
            assertEquals(north, BedsideScene(date(month = month, hour = 12), prefs, zone).season)
            prefs = prefs.copy(hemisphere = BedsidePreferences.Hemisphere.SOUTHERN)
            assertEquals(south, BedsideScene(date(month = month, hour = 12), prefs, zone).season)
        }
        val local = ZoneOffset.ofHours(-7)
        prefs = prefs.copy(hemisphere = BedsidePreferences.Hemisphere.NORTHERN)
        assertFalse(BedsideScene(date(hour = 8), prefs, local).isDay)
    }

    @Test fun displayPreferencesDefaultDarkAndPersistSchedule() {
        val settings = MemorySettings()
        var prefs = BedsidePreferences.load(settings)
        assertEquals(BedsidePreferences.Appearance.DEFAULT, prefs.appearance)
        prefs = prefs.copy(appearance = BedsidePreferences.Appearance.DYNAMIC, hemisphere = BedsidePreferences.Hemisphere.SOUTHERN, dayStart = 7, nightStart = 20)
        prefs.save(settings)
        assertEquals(prefs, BedsidePreferences.load(settings))
        assertFalse(BedsideScene(date(hour = 19), BedsidePreferences(), zone).isDay)
        assertTrue(BedsideScene(date(hour = 19), prefs, zone).isDay)
    }
}
