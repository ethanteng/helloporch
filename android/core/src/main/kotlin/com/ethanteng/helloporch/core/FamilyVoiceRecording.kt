package com.ethanteng.helloporch.core

import kotlin.math.log10

/**
 * A caregiver's own announcement voice, recorded on their phone (lib/family/voices.ts): about a minute of reading this
 * script aloud, somewhere quiet. The server makes a voice from it with ElevenLabs and doesn't keep the recording.
 */
object FamilyVoiceRecording {
    /** An `.m4a`: AAC, as MessageRecorder records it. */
    const val CONTENT_TYPE = "audio/mp4"
    /** The server takes 20 seconds to three minutes. */
    const val MIN_SECONDS = 20.0
    const val MAX_SECONDS = 180.0
    /** What the progress bar fills toward: about a minute makes a good voice. */
    const val TARGET_SECONDS = 60.0
    /** About how long a paragraph takes to read aloud. */
    const val SECONDS_PER_PARAGRAPH = 12.0

    val script = listOf(
        "Good morning! It’s a lovely day. I hope you slept well and had some breakfast.",
        "The kids are calling this afternoon, and I’ll come by on Sunday. We’ll bring lunch.",
        "The garden looks wonderful this year, and the tomatoes are almost ready. Your neighbor waved hello this morning.",
        "We found the old photo album, and the kids loved the pictures from the lake. I’ll bring it on Sunday so we can look at it together.",
        "If you need anything, just tap the screen, and one of us will call you right back.",
        "Remember to drink some water and take a little walk. I love you, and I’ll talk to you soon.",
    )

    /** The paragraph to be reading `seconds` into the recording. The last one stays once it's reached. */
    fun paragraph(seconds: Double): Int = (seconds / SECONDS_PER_PARAGRAPH).toInt().coerceIn(0, script.lastIndex)

    /** Stop is offered once there's enough to make a voice from. */
    fun canStop(seconds: Double): Boolean = seconds >= MIN_SECONDS

    /** How far toward a minute, from 0 to 1. */
    fun progress(seconds: Double): Float = (seconds / TARGET_SECONDS).coerceIn(0.0, 1.0).toFloat()

    /** The microphone's loudest sample since it was last asked (MediaRecorder's `maxAmplitude`, 0 to 32767), from 0 to 1
     * on a 50 dB scale, so speech fills most of the meter and a quiet room barely shows. */
    fun level(amplitude: Int): Float {
        if (amplitude <= 0) return 0f
        val decibels = 20 * log10(amplitude.coerceAtMost(32_767) / 32_767.0)
        return ((decibels + 50) / 50).coerceIn(0.0, 1.0).toFloat()
    }

    /** A recording's levels as `count` bars, each the loudest of its stretch. Fewer levels than bars are stretched. */
    fun bars(levels: List<Float>, count: Int): List<Float> {
        if (count <= 0) return emptyList()
        if (levels.isEmpty()) return List(count) { 0f }
        return List(count) { bar ->
            val from = bar * levels.size / count
            val to = maxOf(from + 1, (bar + 1) * levels.size / count)
            if (from >= levels.size) 0f else levels.subList(from, minOf(to, levels.size)).max()
        }
    }
}
