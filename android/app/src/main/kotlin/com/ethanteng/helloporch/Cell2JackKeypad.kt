package com.ethanteng.helloporch

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.SystemClock
import android.util.AtomicFile
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import androidx.core.content.getSystemService
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.ethanteng.helloporch.core.AttendanceTracker
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.Cell2JackConnector
import com.ethanteng.helloporch.core.Cell2JackDiagnostics
import com.ethanteng.helloporch.core.Cell2JackDigitEvent
import com.ethanteng.helloporch.core.Cell2JackException
import com.ethanteng.helloporch.core.Cell2JackLink
import com.ethanteng.helloporch.core.Cell2JackSettings
import com.ethanteng.helloporch.core.Cell2JackUpdate
import com.ethanteng.helloporch.core.PorchSettings
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The desk phone by the bed as Porch's keypad: its keys, and the receiver going back, reach Porch as [events] through
 * the Cell2Jack plugged into this tablet. The Android counterpart of the iOS Cell2JackKeypad, without a driver: Porch
 * talks to the Cell2Jack itself ([AndroidCell2JackLink], run by [Cell2JackConnector]).
 *
 * It connects only while the bedside is in front, and only while the phone keypad is on or setup is trying the phone
 * ([beginTrial]). The app calls [start] and [stop] as the bedside comes and goes, or adds [lifecycleObserver] to its
 * activity's lifecycle; a family device never starts it. Stopping sends /q and closes the connection. Main thread only;
 * one per process.
 */
class Cell2JackKeypad(context: Context, private val settings: PorchSettings) {
    /** Whether Porch can use the Cell2Jack, for setup's first step. */
    enum class Access {
        NOT_PLUGGED_IN,
        /** Plugged in, but Android hasn't let Porch use it yet. [requestPermission] asks. */
        NEEDS_PERMISSION,
        /** Android is asking. */
        ASKING,
        ALLOWED,
    }

    private val context = context.applicationContext
    private val usb: UsbManager = checkNotNull(this.context.getSystemService()) { "No USB service" }
    private val clock = { SystemClock.elapsedRealtime() }
    private val scope = MainScope()
    // One USB call at a time: a stopping connection's /q goes out before the next connection opens.
    private val usbThread = Dispatchers.IO.limitedParallelism(1)
    private val fileThread = Dispatchers.IO.limitedParallelism(1)
    private val actionsFile = File(this.context.filesDir, "cell2jack-call-actions.json")
    private val tailFile = File(this.context.filesDir, "cell2jack-usb-tail.bin")
    private val savingActions = AtomicBoolean(false)

    /** The last 200 actions and the last 64 KiB the Cell2Jack sent, also saved in the app's files as
     * cell2jack-call-actions.json and cell2jack-usb-tail.bin, as the iOS app saves them. */
    val diagnostics = Cell2JackDiagnostics(onChange = ::saveActions)
    private val connector = Cell2JackConnector({ open() }, diagnostics, clock)

    private val _status = MutableStateFlow("Phone keypad off")
    /** What the phone keypad is doing, such as "Connecting phone keypad…", or why it stopped. For diagnostics and
     * caregiver mode: the bedside itself shows only [notice]. */
    val status: StateFlow<String> = _status.asStateFlow()

    private val _notice = MutableStateFlow<String?>(null)
    /** "Phone keypad ready" for 3 seconds once the phone keypad connects while it's on, otherwise null. Only the brief
     * success confirmation belongs on the bedside; connection diagnostics stay in the diagnostic files. */
    val notice: StateFlow<String?> = _notice.asStateFlow()
    private var noticeJob: Job? = null

    private val _isReady = MutableStateFlow(false)
    /** The Cell2Jack is answering: the phone is plugged in and its logs are arriving. */
    val isReady: StateFlow<Boolean> = _isReady.asStateFlow()

    private val _enabled = MutableStateFlow(Cell2JackSettings.enabled(settings))
    /** Use Cell2Jack phone keypad. Off by default, including on installs from before it existed: setup turns it on
     * once the phone answers. */
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    private val _access = MutableStateFlow(Access.NOT_PLUGGED_IN)
    val access: StateFlow<Access> = _access.asStateFlow()

    private val _events = MutableSharedFlow<Cell2JackDigitEvent>(extraBufferCapacity = 64)
    /**
     * A key pressed on the phone ([Cell2JackDigitEvent.Kind.DIGIT], 0 to 9, * or #) or the receiver put back on the
     * cradle (HANG_UP, while [receiverHangUp] is on). Pulse digits, repeats and other keys are only recorded. Only the
     * screen in front that accepts phone keys should act on them, through the same handling as keyboard keys.
     */
    val events: SharedFlow<Cell2JackDigitEvent> = _events.asSharedFlow()

    /** Hang up when the receiver is put back. On by default. */
    val receiverHangUp: Boolean get() = Cell2JackSettings.receiverHangUp(settings)

    /** Connecting while the phone keypad is off, for setup's Connect the phone screen to test the phone before it's
     * turned on. */
    var trying = false
        private set

    private var foreground = false
    private var wanted = false
    private var asking = false
    private var job: Job? = null
    private var stopping: Job? = null
    private var tokens = 0
    /** The running connection's token; anything else's updates are stale and can't act. */
    private var generation = 0
    /** Unlike [generation], this survives [stop] until that connection finishes cleanup, so its last word is shown. */
    private var connectionID = 0

    /** As [Cell2JackKeypad.start] and [stop], for the activity's lifecycle: running while it's resumed. */
    val lifecycleObserver: DefaultLifecycleObserver = object : DefaultLifecycleObserver {
        override fun onResume(owner: LifecycleOwner) = start()
        override fun onPause(owner: LifecycleOwner) = stop()
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                permissionAction -> {
                    asking = false
                    updateAccess()
                    record("usbPermission", "allowed" to (access.value == Access.ALLOWED))
                    if (access.value == Access.ALLOWED) retry()
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    updateAccess()
                    val device = IntentCompat.getParcelableExtra(intent, UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    // Plugged back in: no need to wait out the backoff.
                    if (device != null && AndroidCell2JackLink.matches(device)) retry()
                }
                // A connection that was using it fails on its next read and tries again.
                UsbManager.ACTION_USB_DEVICE_DETACHED -> updateAccess()
            }
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(permissionAction)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        ContextCompat.registerReceiver(this.context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        updateAccess()
    }

    fun setEnabled(value: Boolean) {
        Cell2JackSettings.setEnabled(settings, value)
        _enabled.value = value
        refresh()
    }

    fun setReceiverHangUp(value: Boolean) = Cell2JackSettings.setReceiverHangUp(settings, value)

    /** Connects even while the phone keypad is off, until [endTrial]. Turning it on is up to whoever started the trial. */
    fun beginTrial() { trying = true; refresh() }
    fun endTrial() { trying = false; refresh() }

    /** The bedside is in front. */
    fun start() {
        foreground = true
        if (enabled.value) record("sceneActive", "trying" to trying)
        updateAccess()
        refresh()
    }

    /** The bedside went away, such as behind another app or the screen turning off: /q, and the connection closes. */
    fun stop() {
        foreground = false
        if (enabled.value || job != null) record("sceneInactive")
        refresh()
    }

    /** Connects again now rather than after the wait, such as when the Cell2Jack is plugged back in. A connection
     * that's working is left alone. */
    fun retry() {
        if (!wanted || isReady.value) return
        halt()
        refresh()
    }

    /**
     * Asks Android to let Porch use the Cell2Jack, unless it can already or the Cell2Jack isn't plugged in. Android's
     * question offers to always open Porch for it, which keeps the permission when it's unplugged and plugged back in.
     */
    fun requestPermission() {
        val device = findDevice()
        if (device == null || usb.hasPermission(device) || asking) { updateAccess(); return }
        asking = true
        updateAccess()
        record("usbPermissionRequested")
        // Immutable, so Android doesn't fill in the answer. Porch asks UsbManager instead when it hears back.
        val intent = Intent(permissionAction).setPackage(context.packageName)
        usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE))
    }

    /** Adds to the diagnostics while the phone keypad is on or connected, as call screens do on iOS. */
    fun record(kind: String, vararg values: Pair<String, Any?>) {
        if (!enabled.value && job == null && !trying) return
        diagnostics.record(kind, *values)
    }

    private fun refresh() {
        wanted = (enabled.value || trying) && foreground
        if (!wanted) { halt(); return }
        if (job != null) return
        val token = ++tokens
        generation = token
        connectionID = token
        setStatus("Connecting phone keypad…")
        val previous = stopping
        job = scope.launch(usbThread) {
            previous?.join()
            connector.run { update -> scope.launch { handle(update, token) } }
        }
    }

    private fun halt() {
        generation = 0
        _isReady.value = false
        val running = job
        if (running == null) {
            if (stopping?.isActive != true) setStatus(if (enabled.value) "Phone keypad paused" else "Phone keypad off")
            return
        }
        job = null
        stopping = running
        setStatus("Stopping phone keypad…")
        running.cancel()
    }

    private fun handle(update: Cell2JackUpdate, token: Int) {
        when (update) {
            Cell2JackUpdate.Connecting -> if (generation == token) { setStatus("Connecting phone keypad…"); updateAccess() }
            Cell2JackUpdate.Ready -> if (generation == token) { _isReady.value = true; setStatus(readyStatus) }
            is Cell2JackUpdate.Keys -> receive(update, token)
            is Cell2JackUpdate.Health -> saveTail()
            is Cell2JackUpdate.Finished -> if (connectionID == token) {
                _isReady.value = false
                setStatus(update.message)
                saveTail()
                updateAccess()
            }
            is Cell2JackUpdate.Retrying -> {}
        }
    }

    private fun receive(keys: Cell2JackUpdate.Keys, token: Int) {
        val age = clock() - keys.receivedAt
        if (generation != token || !wanted || age >= 1_000) {
            record("digitIgnored", "reason" to "session or foreground gate",
                "symbols" to keys.events.filter { it.kind == Cell2JackDigitEvent.Kind.DIGIT }.joinToString("") { it.digit },
                "hangUp" to keys.events.any { it.kind == Cell2JackDigitEvent.Kind.HANG_UP },
                "callbackAge" to age / 1_000.0, "generationMatches" to (generation == token), "wanted" to wanted)
            return
        }
        for (event in keys.events) {
            when (event.kind) {
                Cell2JackDigitEvent.Kind.PULSE -> record("pulseDigitIgnored", "symbol" to event.digit, "rawLine" to event.line)
                Cell2JackDigitEvent.Kind.HANG_UP -> {
                    if (!receiverHangUp) {
                        record("hangUp", "outcome" to "receiver hang-up off", "rawLine" to event.line)
                    } else {
                        AttendanceTracker.shared.noticed()
                        record("hangUp", "outcome" to deliver(event), "rawLine" to event.line)
                    }
                }
                Cell2JackDigitEvent.Kind.DIGIT -> {
                    // Someone pressed a key on the phone by the bed.
                    AttendanceTracker.shared.noticed()
                    val outcome = if (CallSlots.digit(event.digit) == null) "unassigned symbol" else deliver(event)
                    record("digit", "symbol" to event.digit, "outcome" to outcome, "rawLine" to event.line,
                        "embeddedInLine" to event.embeddedInLine)
                }
                // The same key reported again.
                Cell2JackDigitEvent.Kind.DOUBLE_REPORT -> {}
            }
        }
    }

    private fun deliver(event: Cell2JackDigitEvent): String = when {
        _events.subscriptionCount.value == 0 -> "screen does not accept phone keys"
        _events.tryEmit(event) -> "delivered"
        else -> "dropped: screen is behind"
    }

    private fun setStatus(text: String) {
        // Duplicate statuses must not restart the ready confirmation.
        if (_status.value == text) return
        _status.value = text
        noticeJob?.cancel()
        noticeJob = null
        val shown = if (enabled.value && text == readyStatus) text else null
        _notice.value = shown
        if (shown != null) noticeJob = scope.launch { delay(3_000); _notice.value = null }
    }

    private fun findDevice(): UsbDevice? = usb.deviceList.values.firstOrNull(AndroidCell2JackLink::matches)

    private fun updateAccess() {
        val device = findDevice()
        if (device == null || usb.hasPermission(device)) asking = false
        _access.value = when {
            device == null -> Access.NOT_PLUGGED_IN
            usb.hasPermission(device) -> Access.ALLOWED
            asking -> Access.ASKING
            else -> Access.NEEDS_PERMISSION
        }
    }

    /** On the USB thread. Throws, saying why, when the Cell2Jack can't be used now; the connector tries again. */
    private fun open(): Cell2JackLink {
        val device = findDevice() ?: throw Cell2JackException("No Cell2Jack is plugged in")
        if (!usb.hasPermission(device)) throw Cell2JackException("Android hasn't let Porch use the Cell2Jack yet")
        return AndroidCell2JackLink.open(usb, device)
    }

    private fun saveActions() {
        // Records come from the USB thread too. One write catches up with every record made while it waited.
        if (!savingActions.compareAndSet(false, true)) return
        scope.launch(fileThread) {
            savingActions.set(false)
            write(actionsFile, diagnostics.json().encodeToByteArray())
        }
    }

    private fun saveTail() {
        scope.launch(fileThread) { diagnostics.rawTailIfChanged()?.let { write(tailFile, it) } }
    }

    private fun write(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file)
        val stream = try { atomic.startWrite() } catch (_: IOException) { return }
        try {
            stream.write(bytes)
            atomic.finishWrite(stream)
        } catch (_: IOException) {
            // Diagnostic storage never disables the call controls.
            atomic.failWrite(stream)
        }
    }

    companion object {
        const val readyStatus = "Phone keypad ready"
        private const val permissionAction = "com.ethanteng.helloporch.CELL2JACK_PERMISSION"
    }
}
