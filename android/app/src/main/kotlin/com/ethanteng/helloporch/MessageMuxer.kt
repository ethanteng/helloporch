package com.ethanteng.helloporch

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import com.ethanteng.helloporch.core.MessageSoundSync
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer

/**
 * Puts a video message together from the camera's picture, which CameraX records, and the microphone's sound, which
 * MediaRecorder records as it does for audio messages. CameraX would record the sound in whatever format the device's
 * recording profiles name, and some name sound no better than a phone line (the KB10's say 8 kHz) or AMR, which iPhones
 * can't play.
 */
internal object MessageMuxer {
    /** Room for any one sample: a keyframe of SD video at 2 Mbps is well under this. */
    private const val MIN_BUFFER_BYTES = 1 shl 20

    /**
     * Writes [output] from [picture]'s video and [sound]'s audio, the sound moved [shiftMicros] earlier to line up with
     * the picture (MessageSoundSync). The picture keeps its rotation. Throws when either can't be read or the result
     * can't be written.
     */
    fun combine(picture: File, sound: File, shiftMicros: Long, output: File) {
        val rotation = rotation(picture)
        val video = MediaExtractor()
        val audio = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            video.setDataSource(picture.path)
            audio.setDataSource(sound.path)
            val videoFormat = select(video, "video/")
            val audioFormat = select(audio, "audio/")
            val writer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).also { muxer = it }
            writer.setOrientationHint(rotation)
            val videoTrack = writer.addTrack(videoFormat)
            val audioTrack = writer.addTrack(audioFormat)
            writer.start()
            val buffer = ByteBuffer.allocate(maxOf(MIN_BUFFER_BYTES, inputSize(videoFormat), inputSize(audioFormat)))
            val info = MediaCodec.BufferInfo()
            var videoTime = video.sampleTime
            var audioTime = nextSound(audio, shiftMicros)
            // In time order, so the two tracks interleave.
            while (videoTime >= 0 || audioTime >= 0) {
                val takeVideo = audioTime < 0 || (videoTime in 0..audioTime)
                val extractor = if (takeVideo) video else audio
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) { if (takeVideo) videoTime = -1 else audioTime = -1; continue }
                val key = extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0
                info.set(0, size, if (takeVideo) videoTime else audioTime, if (key) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                writer.writeSampleData(if (takeVideo) videoTrack else audioTrack, buffer, info)
                extractor.advance()
                if (takeVideo) videoTime = video.sampleTime else audioTime = nextSound(audio, shiftMicros)
            }
            writer.stop()
        } finally {
            runCatching { muxer?.release() }
            video.release()
            audio.release()
        }
    }

    /** How long the file's first track of this kind ("video/" or "audio/") is, in microseconds. */
    fun durationMicros(file: File, kind: String): Long {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.path)
            val format = select(extractor, kind)
            if (format.containsKey(MediaFormat.KEY_DURATION)) return format.getLong(MediaFormat.KEY_DURATION)
            var last = 0L
            while (extractor.sampleTime >= 0) { last = extractor.sampleTime; extractor.advance() }
            return last
        } finally {
            extractor.release()
        }
    }

    /** The next sound sample's time in the message, skipping sound from before the picture began, or -1 at the end. */
    private fun nextSound(audio: MediaExtractor, shiftMicros: Long): Long {
        while (true) {
            val time = audio.sampleTime
            if (time < 0) return -1
            MessageSoundSync.soundTime(time, shiftMicros)?.let { return it }
            audio.advance()
        }
    }

    /** Selects the file's first track of this kind ("video/" or "audio/") and returns its format. */
    private fun select(extractor: MediaExtractor, kind: String): MediaFormat {
        for (index in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME)?.startsWith(kind) == true) {
                extractor.selectTrack(index)
                return format
            }
        }
        throw IOException("No ${kind.trimEnd('/')} track.")
    }

    private fun inputSize(format: MediaFormat) =
        if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) else 0

    /** How the picture turns to be upright, which CameraX records from how the device was held. */
    private fun rotation(picture: File): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(picture.path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        } finally {
            retriever.release()
        }
    }
}
