package com.ethanteng.helloporch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.ethanteng.helloporch.core.MessageRecordingCheck
import com.ethanteng.helloporch.core.MessageSoundSync
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The microphone, or the front camera and microphone, for one message, as iOS's BedsideMessageRecorder records the
 * bedside's: recording stops on its own at two minutes, and a recording `keep` turns down isn't kept, such as one
 * without any sound. The sound is always MediaRecorder's AAC, 44.1 kHz mono at 64 kbps: an `.m4a` for audio, and for
 * video the sound of an `.mp4` whose picture is CameraX's SD quality (about 640×480), put together by MessageMuxer.
 * CameraX records only the picture because it would take the sound's format from the device's recording profiles, and
 * some name 8 kHz (the KB10's) or AMR (the emulator's). Main thread only.
 */
class MessageRecorder(
    private val context: Context,
    video: Boolean,
    /** Whether a recording of this many seconds, with sound heard on this many checks, is worth sending. */
    private val keep: (seconds: Double, loudChecks: Int) -> Boolean = MessageRecordingCheck::keep,
) {
    /** Becomes false when the camera can't be used, and the message is audio instead. */
    var video = video
        private set
    /** The finished recording, or null when nothing worth sending was recorded. Not called after [cancel]. */
    var onFinish: ((MessageRecording?) -> Unit)? = null
    /** The camera runs while this is resumed: its own, so the camera stops when the message does, not with a screen. */
    private val camera = CameraLifecycle()
    private val preview = Preview.Builder().build()
    private val scope = MainScope()
    private var provider: ProcessCameraProvider? = null
    private var capture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var audio: MediaRecorder? = null
    /** The microphone's recording, which is the message for audio. */
    private var sound: File? = null
    /** The camera's recording, without sound, for video. */
    private var picture: File? = null
    private var soundRunning = false
    private var soundComplete = false
    /** When the microphone and the camera were asked to stop, which is about when each recording ends: with each one's
     * length, when each started, which lines the sound up with the picture (MessageSoundSync). */
    private var soundStoppedNanos = 0L
    private var pictureStoppedNanos = 0L
    private var startedAt = 0L
    private var loudChecks = 0
    private var discarding = false
    private var finished = false

    val isRecording: Boolean get() = startedAt != 0L
    val elapsed: Double get() = if (startedAt == 0L) 0.0 else (SystemClock.elapsedRealtime() - startedAt) / 1_000.0

    class RecorderException : Exception("Couldn't record a message.")

    /** Where the camera shows while recording video, or null while nothing shows it. */
    fun showPreview(surface: Preview.SurfaceProvider?) = preview.setSurfaceProvider(surface)

    /** Sets up the input. Video becomes audio when the camera can't be used. Throws without the microphone. */
    suspend fun prepare() {
        if (!granted(Manifest.permission.RECORD_AUDIO)) throw RecorderException()
        val name = "bedside-message-${UUID.randomUUID()}"
        val sound = File(context.cacheDir, "$name.m4a")
        audio = prepareSound(sound)
        this.sound = sound
        if (video && canRecordVideo(context)) {
            var bound: ProcessCameraProvider? = null
            try {
                val provider = ProcessCameraProvider.awaitInstance(context)
                if (discarding) { release(); return }
                bound = provider
                // About the size of a family phone's video message. A camera without SD takes the next size down, or
                // else up, and the bitrate keeps two minutes at any size well under the server's 100 MB.
                val recorder = Recorder.Builder()
                    .setQualitySelector(QualitySelector.from(Quality.SD, FallbackStrategy.lowerQualityOrHigherThan(Quality.SD)))
                    .setTargetVideoEncodingBitRate(VIDEO_BITRATE).build()
                val capture = VideoCapture.withOutput(recorder)
                camera.resume()
                provider.unbindAll()
                provider.bindToLifecycle(camera, CameraSelector.DEFAULT_FRONT_CAMERA, preview, capture)
                this.provider = provider
                this.capture = capture
                picture = File(context.cacheDir, "$name-camera.mp4")
            } catch (e: CancellationException) {
                release()
                throw e
            } catch (_: Exception) {
                bound?.unbindAll()
                camera.end()
                video = false
            }
        } else {
            video = false
        }
        if (discarding) release()
    }

    /** The microphone as AAC in an `.m4a`, ready to start. */
    private fun prepareSound(file: File): MediaRecorder {
        val recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(44_100)
            recorder.setAudioChannels(1)
            recorder.setAudioEncodingBitRate(64_000)
            recorder.setMaxDuration((MessageRecordingCheck.MAX_SECONDS * 1_000).toInt())
            recorder.setOutputFile(file.path)
            // Two minutes stops it, and what was recorded is kept; for video, the camera stops with it.
            recorder.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) stop()
            }
            recorder.setOnErrorListener { _, _, _ ->
                soundRunning = false
                soundComplete = false
                if (video) recording?.stop() else finish(false)
            }
            recorder.prepare()
            return recorder
        } catch (_: Exception) {
            recorder.release()
            file.delete()
            throw RecorderException()
        }
    }

    /** Starts recording, or false when it can't. */
    fun start(): Boolean {
        if (isRecording || discarding || finished) return false
        val audio = audio ?: return false
        val capture = if (video) capture ?: return false else null
        val picture = if (video) picture ?: return false else null
        try { audio.start() } catch (_: Exception) { return false }
        soundRunning = true
        soundComplete = true
        if (capture != null && picture != null) {
            val output = FileOutputOptions.Builder(picture).setDurationLimitMillis((MessageRecordingCheck.MAX_SECONDS * 1_000).toLong()).build()
            val main = ContextCompat.getMainExecutor(context)
            recording = try {
                capture.output.prepareRecording(context, output).start(main) { event ->
                    // Reaching two minutes, or the camera going away, still leaves a complete file. A camera that
                    // stopped by itself ended about now.
                    if (event is VideoRecordEvent.Finalize) {
                        if (pictureStoppedNanos == 0L) pictureStoppedNanos = SystemClock.elapsedRealtimeNanos()
                        finish(event.error in completeFiles)
                    }
                }
            } catch (_: Exception) {
                stopSound()
                return false
            }
        }
        startedAt = SystemClock.elapsedRealtime()
        return true
    }

    /** Called a few times a second while recording: whether something louder than a quiet room was heard. */
    fun sample() {
        if (!isRecording) return
        val amplitude = (runCatching { audio?.maxAmplitude ?: 0 }.getOrDefault(0)) / 32_767.0
        if (MessageRecordingCheck.loud(amplitude)) loudChecks += 1
    }

    /** Finishes the recording; [onFinish] receives it. */
    fun stop() {
        if (!isRecording) return
        // The camera stops first: the microphone's stop waits while it finishes its file.
        if (video) {
            pictureStoppedNanos = SystemClock.elapsedRealtimeNanos()
            recording?.stop()
            stopSound()
        } else {
            finish(stopSound())
        }
    }

    /**
     * Lets go of the camera and the microphone now, for a call that's taking over, without waiting for the recording to
     * finish. A recording that still finishes goes to [onFinish] as usual.
     */
    fun letGo() = release()

    /** Throws the recording away, whether or not it started. */
    fun cancel() {
        discarding = true
        onFinish = null
        if (isRecording) stop() else { release(); finish(false) }
    }

    /** Stops the microphone, once, so its file is complete. Whether it recorded something. */
    private fun stopSound(): Boolean {
        if (!soundRunning) return soundComplete
        soundRunning = false
        soundStoppedNanos = SystemClock.elapsedRealtimeNanos()
        soundComplete = runCatching { audio?.stop() }.isSuccess
        return soundComplete
    }

    private fun finish(successfully: Boolean) {
        if (finished) return
        finished = true
        val duration = minOf(MessageRecordingCheck.MAX_SECONDS, elapsed)
        startedAt = 0L
        recording = null
        // The camera can stop first, such as at two minutes.
        val sounded = stopSound()
        release()
        val callback = onFinish
        onFinish = null
        val sound = sound
        val picture = picture?.takeIf { video }
        if (!successfully || !sounded || discarding || sound == null || !keep(duration, loudChecks)) {
            sound?.delete()
            picture?.delete()
            callback?.invoke(null)
            return
        }
        if (picture == null) {
            callback?.invoke(MessageRecording(sound, "audio", "audio/mp4", duration))
            return
        }
        val message = File(context.cacheDir, sound.name.removeSuffix(".m4a") + ".mp4")
        scope.launch {
            val combined = withContext(Dispatchers.IO) {
                try {
                    val shift = MessageSoundSync.shiftMicros(pictureStoppedNanos, MessageMuxer.durationMicros(picture, "video/"),
                        soundStoppedNanos, MessageMuxer.durationMicros(sound, "audio/"))
                    MessageMuxer.combine(picture, sound, shift, message)
                    true
                } catch (_: Exception) {
                    message.delete()
                    false
                }
            }
            picture.delete()
            if (discarding) { sound.delete(); message.delete(); return@launch }
            if (combined) {
                sound.delete()
                callback?.invoke(MessageRecording(message, "video", "video/mp4", duration))
            } else {
                // The sound alone still says it.
                callback?.invoke(MessageRecording(sound, "audio", "audio/mp4", duration))
            }
        }
    }

    /** Lets go of the microphone and the camera. */
    private fun release() {
        stopSound()
        audio?.let { runCatching { it.release() } }
        audio = null
        provider?.unbindAll()
        provider = null
        capture = null
        camera.end()
    }

    private fun granted(permission: String) = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private class CameraLifecycle : LifecycleOwner {
        private val registry = LifecycleRegistry(this)
        override val lifecycle: Lifecycle get() = registry
        fun resume() { registry.currentState = Lifecycle.State.RESUMED }
        fun end() { if (registry.currentState.isAtLeast(Lifecycle.State.CREATED)) registry.currentState = Lifecycle.State.DESTROYED }
    }

    companion object {
        /** Whether this device can record a video message: with the camera allowed and a front camera. */
        fun canRecordVideo(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED && videoSupported(context)

        /** Whether this device could record a video message once the camera is allowed: it has a front camera. Cameras
         * that can't be listed are tried anyway, and one that can't be used then records audio. */
        fun videoSupported(context: Context): Boolean = try {
            val manager = context.getSystemService(CameraManager::class.java)
            manager.cameraIdList.any { manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT }
        } catch (_: Exception) {
            true
        }

        /** 2 Mbps: about 30 MB for two minutes. */
        private const val VIDEO_BITRATE = 2_000_000
        private val completeFiles = setOf(VideoRecordEvent.Finalize.ERROR_NONE, VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED,
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED, VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE)
    }
}
