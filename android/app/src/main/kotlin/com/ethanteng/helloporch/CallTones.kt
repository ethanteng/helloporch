package com.ethanteng.helloporch

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.BedsidePreferences
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.PorchExperience

/**
 * Plays Porch's own cues ([CallTone]) on this device only. They are never published to a call, as on iOS. Ringing and
 * ringback repeat until stopped. Main thread only.
 */
class TonePlayer(private val usage: Int = AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING) {
    private var track: AudioTrack? = null

    /** False if the sound couldn't start, such as when the audio system turned it away. */
    fun play(tone: CallTone, volume: Float = 1f): Boolean {
        stop()
        return try {
            val wave = tone.wave()
            // The WAV header is 44 bytes; AudioTrack takes the 16-bit samples after it.
            val pcm = wave.copyOfRange(44, wave.size)
            val attributes = AudioAttributes.Builder().setUsage(usage).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            val format = AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(16_000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()
            val player = AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(format)
                .setTransferMode(AudioTrack.MODE_STATIC).setBufferSizeInBytes(pcm.size).build()
            player.write(pcm, 0, pcm.size)
            if (tone.loops) player.setLoopPoints(0, pcm.size / 2, -1)
            player.setVolume(volume)
            player.play()
            track = player
            player.playState == AudioTrack.PLAYSTATE_PLAYING
        } catch (_: Exception) {
            stop()
            false
        }
    }

    fun stop() {
        val player = track ?: return
        track = null
        runCatching { player.stop() }
        player.release()
    }
}

/** The ringback a caller hears while Porch rings the other end: the US ring cadence at 70% volume, as on iOS. */
class Ringback {
    private val player = TonePlayer()
    var playing = false
        private set
    /** Whether ringback is wanted, even while it waits for a sentence. */
    private var wanted = false
    private var holding: OutgoingAnnouncement? = null

    /** Ringing waits until the bedside has said who it's calling. */
    fun hold(until: OutgoingAnnouncement) {
        holding = until
        until.then {
            if (holding !== until) return@then
            holding = null
            if (wanted) play()
        }
    }

    fun start() {
        wanted = true
        if (holding == null) play()
    }

    fun stop() {
        wanted = false
        playing = false
        player.stop()
    }

    private fun play() {
        if (playing) return
        playing = player.play(CallTone.RINGBACK, volume = 0.7f)
    }
}

/** The bedside's wording, in the language a caregiver chose for it. Family phones use English, as on iOS. */
object BedsideText {
    fun language(app: PorchApplication): BedsideLanguage =
        if (app.device.experience == PorchExperience.BEDSIDE) BedsidePreferences.load(app.settings).language else BedsideLanguage.ENGLISH

    fun string(app: PorchApplication, english: String, vararg arguments: Any?): String {
        val language = language(app)
        return if (arguments.isEmpty()) language.text(english) else language.format(english, *arguments)
    }

    /** An error to show on the bedside. One the bedside's language has no words for asks for a caregiver's help
     * instead of showing English to someone who may not read it. */
    fun error(app: PorchApplication, description: String): String {
        val language = language(app)
        val translated = language.text(description)
        return if (language != BedsideLanguage.ENGLISH && translated == description)
            string(app, "Please ask your caregiver for help, then try again.") else translated
    }
}
