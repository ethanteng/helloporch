package com.ethanteng.helloporch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.PowerManager
import android.util.Size
import androidx.annotation.OptIn
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import androidx.lifecycle.Observer
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.ethanteng.helloporch.core.AttendanceTracker
import com.ethanteng.helloporch.core.BedsideAttendance
import com.ethanteng.helloporch.core.FamilySnapshot
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PresenceTrigger
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.Executors
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Notices someone sitting in front of the bedside tablet, as iOS's BedsidePresence does: the front camera runs at a low
 * rate and ML Kit's on-device face detection looks at about three frames a second. No picture is recorded, kept or sent.
 * The clock runs it ([ClockPresence]) for a few seconds at a time when a caregiver lets family see that someone is at the
 * tablet, and it stops before anything else uses the camera ([stopThen]). It binds only its own analysis, on a lifecycle
 * of its own, because the voicemail recorder uses the same camera through CameraX. Main thread only.
 */
class BedsidePresence(private val context: Context) {
    /** Someone has been in front of the tablet for a couple of seconds, while it's watching for messages. */
    var onPresent: (() -> Unit)? = null
    /** A face close by has stayed for a moment: about once a second while someone is there. */
    var onSighting: (() -> Unit)? = null
    /** Watching, including while the camera is still opening. */
    var running = false
        private set
    /** Someone settling in front of the tablet calls [onPresent]. */
    private var watchingMessages = false
    private val trigger = PresenceTrigger()
    /** A moment's steady face, so one odd frame doesn't count as someone there. */
    private val sighting = PresenceTrigger(requiredSeconds = 1.0)
    /** Counts each camera start and each stop. A frame from before a stop, or a start still waiting for CameraX when one
     * comes, is from an older one and is ignored. */
    private var session = 0
    private val scope = MainScope()
    private var provider: ProcessCameraProvider? = null
    private var analysis: ImageAnalysis? = null
    private var lifecycle: CameraLifecycle? = null
    /** The front camera as CameraX last bound it, kept after a stop to tell when it has closed. */
    private var camera: Camera? = null
    /** Frames are analyzed off the main thread, one at a time. */
    private val frames = Executors.newSingleThreadExecutor()
    private val main = ContextCompat.getMainExecutor(context)
    // Only each face's box is needed. ML Kit's smallest face is a fraction of the frame's width, and by default skips
    // faces narrower than 0.1 of it: in an upright landscape frame, that's taller than the 0.12 of its height that counts.
    private val faces by lazy {
        FaceDetection.getClient(FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
            .setMinFaceSize(0.07f)
            .build())
    }

    /** Starts watching, or keeps watching. `armed`: someone settling in front of the tablet calls [onPresent]; otherwise
     * only [onSighting] is called. Without the camera allowed, it doesn't start. */
    fun start(armed: Boolean) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) { stop(); return }
        // Someone already sitting there when messages start waiting counts from then.
        if (armed && !(running && watchingMessages)) trigger.reset()
        watchingMessages = armed
        if (running) return
        running = true
        sighting.reset()
        val token = ++session
        provider?.let { bind(it, token); return }
        scope.launch {
            val provider = try {
                ProcessCameraProvider.awaitInstance(context)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            if (token != session) return@launch
            if (provider == null) { running = false; return@launch }
            this@BedsidePresence.provider = provider
            bind(provider, token)
        }
    }

    private fun bind(provider: ProcessCameraProvider, token: Int) {
        // About 640×480, the size iOS looks at, or the nearest the camera has. A frame that arrives while another is
        // being looked at replaces the one waiting.
        val size = ResolutionSelector.Builder()
            .setResolutionStrategy(ResolutionStrategy(Size(640, 480), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER))
            .build()
        val analysis = ImageAnalysis.Builder().setResolutionSelector(size)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
        analysis.setAnalyzer(frames, FrameAnalyzer(token))
        val owner = CameraLifecycle()
        owner.resume()
        try {
            camera = provider.bindToLifecycle(owner, CameraSelector.DEFAULT_FRONT_CAMERA, analysis)
        } catch (_: Exception) {
            // No front camera, or CameraX can't use it now. The next start tries again.
            analysis.clearAnalyzer()
            owner.end()
            running = false
            return
        }
        this.analysis = analysis
        lifecycle = owner
    }

    /** Stops watching. The camera closes a moment later; [stopThen] waits for that. */
    fun stop() {
        session++
        if (!running) return
        running = false
        // Only this analysis: the voicemail recorder may be binding the camera for itself.
        analysis?.let {
            provider?.unbind(it)
            it.clearAnalyzer()
        }
        analysis = null
        lifecycle?.end()
        lifecycle = null
    }

    /**
     * Stops if needed, then calls [done] on the main thread once the camera has closed, for a call's LiveKit, which opens
     * the camera itself through Camera2, or the voicemail recorder. Never blocks. A camera that still hasn't closed after
     * 2 seconds is left for whoever comes next to open anyway.
     */
    fun stopThen(done: () -> Unit) {
        stop()
        val state = camera?.cameraInfo?.cameraState ?: run { done(); return }
        var waiting = true
        val closed = object : Observer<CameraState> {
            override fun onChanged(value: CameraState) {
                if (!waiting || value.type != CameraState.Type.CLOSED) return
                waiting = false
                state.removeObserver(this)
                done()
            }
        }
        // Called at once with how the camera is now, which may already be closed.
        state.observeForever(closed)
        if (!waiting) return
        scope.launch {
            delay(2_000)
            if (!waiting) return@launch
            waiting = false
            state.removeObserver(closed)
            done()
        }
    }

    /** [stopThen], for a coroutine: returns once the camera is free. A caller that gives up meanwhile, such as a video
     * call hung up while the camera is still closing, or a message interrupted before the beep, must not be resumed:
     * that throws and takes the app down. The camera still closes. */
    suspend fun release() = suspendCancellableCoroutine { continuation ->
        stopThen { if (continuation.isActive) continuation.resume(Unit) }
    }

    /** One analyzed frame: the tallest face's height as a fraction of the upright frame's, or null for none. */
    private fun observed(faceHeight: Double?, time: Double, token: Int) {
        if (!running || token != session) return
        if (sighting.observe(faceHeight, time)) {
            sighting.reset()
            onSighting?.invoke()
        }
        // A sighting may have stopped it.
        if (running && token == session && watchingMessages && trigger.observe(faceHeight, time)) onPresent?.invoke()
    }

    /** One camera start's frames, on [frames]. Every frame is closed, so the next one can come. */
    private inner class FrameAnalyzer(private val token: Int) : ImageAnalysis.Analyzer {
        private var lastAnalysis: Long? = null

        @OptIn(ExperimentalGetImage::class)
        override fun analyze(image: ImageProxy) {
            val time = image.imageInfo.timestamp
            val media = image.image
            // About three looks a second is plenty, and keeps the tablet cool.
            val last = lastAnalysis
            if (media == null || (last != null && time - last < ANALYSIS_INTERVAL_NANOS)) { image.close(); return }
            lastAnalysis = time
            // ML Kit turns the frame upright and measures faces in it, so the height they're a fraction of is upright too.
            val rotation = image.imageInfo.rotationDegrees
            val height = if (rotation == 90 || rotation == 270) image.width else image.height
            faces.process(InputImage.fromMediaImage(media, rotation)).addOnCompleteListener(frames) { task ->
                image.close()
                if (!task.isSuccessful) return@addOnCompleteListener
                val tallest = task.result.maxOfOrNull { it.boundingBox.height() }?.let { it.toDouble() / height }
                main.execute { observed(tallest, time / 1e9, token) }
            }
        }
    }

    private companion object {
        const val ANALYSIS_INTERVAL_NANOS = 300_000_000L
    }
}

/**
 * The presence camera on the bedside's clock, as iOS's clock screen runs it. With Check with the camera on in Privacy, and
 * family shown when someone is at the tablet, it looks for someone as soon as the clock is free, then every
 * `BedsideAttendance.lookInterval`, for up to `lookSeconds`, and a face held for a moment tells family someone is there.
 * Presence autoplay passes `watchMessages` while messages are waiting, to keep it watching, and `onPresent` for someone
 * settling in front of the tablet. The clock is free with nothing over it (`covered` is anything PorchRoot shows over
 * it, such as an error), Porch in front, no call starting, the household not busy and the tablet not hot. Leaving the
 * clock, or Porch leaving the front, stops the camera at once.
 */
@Composable
fun ClockPresence(app: PorchApplication, state: FamilySnapshot, covered: Boolean, watchMessages: Boolean = false, onPresent: () -> Unit = {}) {
    val presence = app.presence
    var resumed by remember { mutableStateOf(false) }
    // From the lifecycle itself: once Porch is out of sight Compose stops drawing, so a stop left to the next frame could
    // wait until Porch is back.
    LifecycleResumeEffect(presence) {
        resumed = true
        onPauseOrDispose {
            resumed = false
            presence.stop()
        }
    }
    val cool = rememberCool()
    val free = resumed && !covered && cool && !app.calls.opening && !state.busy && app.device.experience == PorchExperience.BEDSIDE
    // A caregiver lets family see someone is at the tablet, and lets the camera check. Read again with each check-in;
    // the switch is in caregiver mode, and the clock reads it afresh when it's back.
    val cameraOn = remember(state) { BedsideAttendance.cameraEnabled(app.settings) } && state.shareAttendance == true
    val looks = free && cameraOn
    var looking by remember { mutableStateOf(false) }
    LaunchedEffect(looks) {
        looking = false
        if (!looks) return@LaunchedEffect
        while (true) {
            looking = true
            delay((BedsideAttendance.lookSeconds * 1_000).toLong())
            looking = false
            delay(((BedsideAttendance.lookInterval - BedsideAttendance.lookSeconds) * 1_000).toLong())
        }
    }
    // Watching for messages sees anyone there anyway, so a look only matters while it isn't.
    val armed = free && watchMessages
    val wanted = armed || (looks && looking)
    DisposableEffect(wanted, armed) {
        if (wanted) presence.start(armed) else presence.stop()
        onDispose {}
    }
    val sharing by rememberUpdatedState(cameraOn)
    val present by rememberUpdatedState(onPresent)
    DisposableEffect(presence) {
        val seen = {
            // Family hear of it only if a caregiver turned that on: starting messages alone tells no one. Seen, so this
            // look can stop early.
            if (sharing) {
                AttendanceTracker.shared.noticed()
                looking = false
            }
        }
        val settled = { present() }
        presence.onSighting = seen
        presence.onPresent = settled
        // Only its own, in case the clock of a recreated activity has already set them.
        onDispose {
            if (presence.onSighting === seen) presence.onSighting = null
            if (presence.onPresent === settled) presence.onPresent = null
        }
    }
}

/** Whether the tablet is cool enough for the camera: below Android's severe thermal status, as iOS stops at serious. */
@Composable
private fun rememberCool(): Boolean {
    val context = LocalContext.current
    val power = remember(context) { context.getSystemService<PowerManager>() }
    var status by remember(power) { mutableIntStateOf(power?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE) }
    DisposableEffect(power) {
        val listener = PowerManager.OnThermalStatusChangedListener { status = it }
        power?.addThermalStatusListener(ContextCompat.getMainExecutor(context), listener)
        onDispose { power?.removeThermalStatusListener(listener) }
    }
    return status < PowerManager.THERMAL_STATUS_SEVERE
}
