package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Recording a caregiver's voice: the script read about a paragraph every 12 seconds, Stop once there's enough for the
 * server (20 seconds), and the meter and waveform from the microphone's levels. */
class FamilyVoiceRecordingTest {
    @Test fun theScriptMovesOnAboutEveryTwelveSecondsAndStaysOnTheLast() {
        assertEquals(6, FamilyVoiceRecording.script.size)
        assertEquals(listOf(0, 0, 1, 2, 5, 5), listOf(0.0, 11.9, 12.0, 30.0, 60.0, 180.0).map(FamilyVoiceRecording::paragraph))
    }

    @Test fun stopWaitsForTwentySeconds() {
        assertFalse(FamilyVoiceRecording.canStop(19.9))
        assertTrue(FamilyVoiceRecording.canStop(20.0))
    }

    @Test fun progressFillsTowardAMinute() {
        assertEquals(listOf(0f, 0.5f, 1f, 1f), listOf(0.0, 30.0, 60.0, 150.0).map(FamilyVoiceRecording::progress))
    }

    @Test fun levelsAreFiftyDecibelsOfMeter() {
        assertEquals(0f, FamilyVoiceRecording.level(0))
        assertEquals(1f, FamilyVoiceRecording.level(32_767))
        assertEquals(1f, FamilyVoiceRecording.level(40_000), "louder than the scale")
        assertEquals(0.6f, FamilyVoiceRecording.level(3_277), 0.01f, "−20 dB")
        assertEquals(0f, FamilyVoiceRecording.level(50), "a quiet room")
    }

    @Test fun barsTakeTheLoudestOfEachStretch() {
        assertEquals(listOf(0.5f, 0.9f), FamilyVoiceRecording.bars(listOf(0.1f, 0.5f, 0.9f, 0.2f), 2))
        assertEquals(listOf(0.2f, 0.2f, 0.8f, 0.8f), FamilyVoiceRecording.bars(listOf(0.2f, 0.8f), 4), "stretched")
        assertEquals(listOf(0f, 0f, 0f), FamilyVoiceRecording.bars(emptyList(), 3))
        assertEquals(emptyList(), FamilyVoiceRecording.bars(listOf(0.5f), 0))
    }
}
