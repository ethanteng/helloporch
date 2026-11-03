package com.ethanteng.helloporch.core

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin

/** Original local cues, never published as a media track. */
enum class CallTone {
    RINGBACK, INCOMING, ANNOUNCEMENT, CONNECTED,
    /** `BEEP` starts a voicemail recording, as on a telephone. */
    BEEP;

    val loops: Boolean get() = this == RINGBACK || this == INCOMING
    val duration: Double get() = when (this) {
        RINGBACK -> 6.0
        INCOMING -> 3.0
        ANNOUNCEMENT -> 0.6
        CONNECTED -> 0.5
        BEEP -> 0.5
    }

    fun wave(): ByteArray {
        val rate = 16_000
        val samples = (duration * 16_000).toInt()
        val data = ByteBuffer.allocate(44 + samples * 2).order(ByteOrder.LITTLE_ENDIAN)
        fun ascii(text: String) { data.put(text.toByteArray(Charsets.US_ASCII)) }
        ascii("RIFF"); data.putInt(36 + samples * 2); ascii("WAVEfmt ")
        data.putInt(16); data.putShort(1); data.putShort(1); data.putInt(rate)
        data.putInt(rate * 2); data.putShort(2); data.putShort(16); ascii("data"); data.putInt(samples * 2)
        for (index in 0 until samples) {
            val t = index.toDouble() / rate
            val (start, end, first, second) = when (this) {
                RINGBACK -> listOf(0.0, 2.0, 440.0, 480.0)
                INCOMING -> if (t < 0.8) listOf(0.0, 0.6, 440.0, 480.0) else listOf(0.8, 1.4, 440.0, 480.0)
                ANNOUNCEMENT -> if (t < 0.3) listOf(0.0, 0.25, 660.0, 660.0) else listOf(0.3, 0.6, 880.0, 880.0)
                CONNECTED -> if (t < 0.2) listOf(0.0, 0.18, 660.0, 660.0) else listOf(0.2, 0.5, 880.0, 880.0)
                BEEP -> listOf(0.0, 0.45, 1000.0, 1000.0)
            }
            val fade = maxOf(0.0, minOf(1.0, (t - start) / 0.015, (end - t) / 0.015))
            val sample = (sin(2 * PI * first * t) + sin(2 * PI * second * t)) * 0.35 * fade
            data.putShort((sample * Short.MAX_VALUE).toInt().toShort())
        }
        return data.array()
    }
}
