package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CallPreferencesTest {
    @Test fun fallbackWaitDefaultsPersistsAndBoundsInvalidValues() {
        val settings = MemorySettings()
        assertEquals(20, CallPreferences.fallbackSeconds(settings))
        CallPreferences.saveFallbackSeconds(45, settings)
        assertEquals(45, CallPreferences.fallbackSeconds(settings))
        CallPreferences.saveFallbackSeconds(1, settings)
        assertEquals(5, CallPreferences.fallbackSeconds(settings))
        CallPreferences.saveFallbackSeconds(500, settings)
        assertEquals(120, CallPreferences.fallbackSeconds(settings))
        settings.putInt("porch.phoneFallbackSeconds", -10)
        assertEquals(20, CallPreferences.fallbackSeconds(settings))
    }

    @Test fun bedsideLeavesMessagesForUnansweredCallsUnlessTurnedOff() {
        val settings = MemorySettings()
        assertTrue(CallPreferences.leaveMessageWhenUnanswered(settings))
        CallPreferences.saveLeaveMessageWhenUnanswered(false, settings)
        assertFalse(CallPreferences.leaveMessageWhenUnanswered(settings))
        CallPreferences.saveLeaveMessageWhenUnanswered(true, settings)
        assertTrue(CallPreferences.leaveMessageWhenUnanswered(settings))
    }

    @Test fun familyVideoCallsStartWithCameraUnlessTurnedOff() {
        val settings = MemorySettings()
        assertTrue(CallPreferences.startVideoWithCamera(settings))
        CallPreferences.saveStartVideoWithCamera(false, settings)
        assertFalse(CallPreferences.startVideoWithCamera(settings))
        CallPreferences.saveStartVideoWithCamera(true, settings)
        assertTrue(CallPreferences.startVideoWithCamera(settings))
    }

    @Test fun bedsideVideoCallsAlwaysStartWithCamera() {
        val settings = MemorySettings()
        assertTrue(CallPreferences.startVideoWithCamera(PorchExperience.BEDSIDE, settings))
        assertTrue(CallPreferences.startVideoWithCamera(PorchExperience.FAMILY, settings))
        // The family setting is per phone; it never turns off the bedside's camera.
        CallPreferences.saveStartVideoWithCamera(false, settings)
        assertTrue(CallPreferences.startVideoWithCamera(PorchExperience.BEDSIDE, settings))
        assertFalse(CallPreferences.startVideoWithCamera(PorchExperience.FAMILY, settings))
    }

    @Test fun preferencesDefaultOffPersistAndValidateBounds() {
        val settings = MemorySettings()
        assertFalse(CallPreferences.disconnectAfterSilence(settings))
        assertEquals(120, CallPreferences.silenceSeconds(settings))
        CallPreferences.saveSilence(enabled = true, seconds = 45, settings)
        assertTrue(CallPreferences.disconnectAfterSilence(settings))
        assertEquals(45, CallPreferences.silenceSeconds(settings))
        CallPreferences.saveSilence(enabled = false, seconds = 0, settings)
        assertFalse(CallPreferences.disconnectAfterSilence(settings))
        assertEquals(15, CallPreferences.silenceSeconds(settings))
        CallPreferences.saveSilence(enabled = true, seconds = 9999, settings)
        assertEquals(1800, CallPreferences.silenceSeconds(settings))
        settings.putInt("porch.silenceSeconds", -10)
        assertEquals(120, CallPreferences.silenceSeconds(settings))
    }

    @Test fun silenceMinuteStepFollowsWholeMinutesAndMovesOneMinuteFromALeftover() {
        assertEquals(300, CallPreferences.silenceSeconds(minutes = 5, current = 120))
        assertEquals(60, CallPreferences.silenceSeconds(minutes = 1, current = 120))
        // 45 seconds shows as 45 sec. The first + is one minute, not two.
        assertEquals(60, CallPreferences.silenceSeconds(minutes = 1, current = 45))
        // 1 min 30 sec: + is 2 min and − is 1 min, rather than jumping to 3 min.
        assertEquals(120, CallPreferences.silenceSeconds(minutes = 2, current = 90))
        assertEquals(60, CallPreferences.silenceSeconds(minutes = 0, current = 90))
        assertEquals(180, CallPreferences.silenceSeconds(minutes = 3, current = 150))
        assertEquals(120, CallPreferences.silenceSeconds(minutes = 1, current = 150))
    }
}
