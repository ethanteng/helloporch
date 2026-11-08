package com.ethanteng.helloporch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.CamcorderProfile
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
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException

/**
 * The microphone, or the front camera and microphone, for one message, as iOS's BedsideMessageRecorder records the
 * bedside's: recording stops on its own at two minutes, and a recording `keep` turns down isn't kept, such as one
 * without any sound. Audio is AAC in an `.m4a`; video is CameraX's SD quality (about 640×480) in an `.mp4`, with AAC
 * sound. Main thread only.
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
    private var provider: ProcessCameraProvider? = null
    private var capture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var audio: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L
    private var loudChecks = 0
    /** The loudest a video's sound has been since the last check, from 0 to 1. */
    private var videoAmplitude = 0.0
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
        if (video && canRecordVideo(context)) {
            var bound: ProcessCameraProvider? = null
            try {
                val provider = ProcessCameraProvider.awaitInstance(context)
                if (discarding) return
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
                return
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                bound?.unbindAll()
                camera.end()
            }
        }
        video = false
        val file = File(context.cacheDir, "bedside-message-${UUID.randomUUID()}.m4a")
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
            // Two minutes stops it, and what was recorded is kept.
            recorder.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) { runCatching { audio?.stop() }; finish(true) }
            }
            recorder.setOnErrorListener { _, _, _ -> finish(false) }
            recorder.prepare()
        } catch (e: Exception) {
            recorder.release()
            file.delete()
            throw RecorderException()
        }
        audio = recorder
        this.file = file
        if (discarding) release()
    }

    /** Starts recording, or false when it can't. */
    fun start(): Boolean {
        if (isRecording || discarding || finished) return false
        if (video) {
            val capture = capture ?: return false
            // Checked again here: recording video with sound needs the microphone.
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return false
            val file = File(context.cacheDir, "bedside-message-${UUID.randomUUID()}.mp4")
            this.file = file
            val output = FileOutputOptions.Builder(file).setDurationLimitMillis((MessageRecordingCheck.MAX_SECONDS * 1_000).toLong()).build()
            recording = try {
                capture.output.prepareRecording(context, output).withAudioEnabled().start(ContextCompat.getMainExecutor(context)) { event ->
                    when (event) {
                        is VideoRecordEvent.Status -> videoAmplitude = maxOf(videoAmplitude, event.recordingStats.audioStats.audioAmplitude)
                        // Reaching two minutes, or the camera going away, still leaves a complete file.
                        is VideoRecordEvent.Finalize -> finish(event.error in completeFiles)
                        else -> {}
                    }
                }
            } catch (_: Exception) {
                return false
            }
        } else {
            try { audio?.start() ?: return false } catch (_: Exception) { return false }
        }
        startedAt = SystemClock.elapsedRealtime()
        return true
    }

    /** Called a few times a second while recording: whether something louder than a quiet room was heard. */
    fun sample() {
        if (!isRecording) return
        val amplitude = if (video) videoAmplitude.also { videoAmplitude = 0.0 }
            else (runCatching { audio?.maxAmplitude ?: 0 }.getOrDefault(0)) / 32_767.0
        if (MessageRecordingCheck.loud(amplitude)) loudChecks += 1
    }

    /** Finishes the recording; [onFinish] receives it. */
    fun stop() {
        if (!isRecording) return
        if (video) recording?.stop()
        else finish(runCatching { audio?.stop() }.isSuccess)
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

    private fun finish(successfully: Boolean) {
        if (finished) return
        finished = true
        val duration = minOf(MessageRecordingCheck.MAX_SECONDS, elapsed)
        startedAt = 0L
        recording = null
        release()
        val callback = onFinish
        onFinish = null
        val file = file
        if (!successfully || discarding || file == null || !keep(duration, loudChecks)) {
            file?.delete()
            callback?.invoke(null)
            return
        }
        callback?.invoke(MessageRecording(file, if (video) "video" else "audio", if (video) "video/mp4" else "audio/mp4", duration))
    }

    /** Lets go of the microphone and the camera. */
    private fun release() {
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
        /**
         * Whether this device can record a video message: with the camera allowed, a front camera, and sound every
         * family phone plays.
         */
        fun canRecordVideo(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED && videoSupported(context)

        /** Whether this device could record a video message once the camera is allowed. */
        fun videoSupported(context: Context): Boolean = frontCameraRecordsAAC(context)

        /**
         * Whether there's a front camera whose video records its sound as AAC, which every family phone plays. CameraX
         * records the sound the device's recording profiles name, and some name AMR (the emulator's do), which iPhones
         * can't play: a device like that records messages as audio. A camera without profiles leaves it to CameraX, which
         * uses AAC.
         */
        private fun frontCameraRecordsAAC(context: Context): Boolean {
            // Cameras that can't be listed are tried anyway: one that can't be used then records audio.
            val front = try {
                val manager = context.getSystemService(CameraManager::class.java)
                manager.cameraIdList.firstOrNull { manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT }
                    ?: return false
            } catch (_: Exception) {
                return true
            }
            val qualities = listOf(CamcorderProfile.QUALITY_480P, CamcorderProfile.QUALITY_720P, CamcorderProfile.QUALITY_HIGH)
            val codecs = try {
                if (Build.VERSION.SDK_INT >= 31) qualities.flatMap { quality -> CamcorderProfile.getAll(front, quality)?.audioProfiles?.map { it.codec }.orEmpty() }
                else front.toIntOrNull()?.let { id ->
                    @Suppress("DEPRECATION")
                    qualities.filter { CamcorderProfile.hasProfile(id, it) }.map { CamcorderProfile.get(id, it).audioCodec }
                }.orEmpty()
            } catch (_: Exception) {
                emptyList()
            }
            return codecs.all { it == MediaRecorder.AudioEncoder.AAC }
        }

        /** 2 Mbps: about 30 MB for two minutes. */
        private const val VIDEO_BITRATE = 2_000_000
        private val completeFiles = setOf(VideoRecordEvent.Finalize.ERROR_NONE, VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED,
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED, VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE)
    }
}
