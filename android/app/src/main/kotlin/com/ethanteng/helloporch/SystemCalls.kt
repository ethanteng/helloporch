package com.ethanteng.helloporch

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyNames
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.PorchExperience
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/**
 * A call ringing while Porch isn't on screen: the Android counterpart of iOS's SystemIncomingCalls, which rings through
 * CallKit. A push says a call is on its way ([receivePush]). A call notification rings, and on a locked phone shows
 * Porch's incoming screen over the lock screen. A phone-call foreground service keeps Porch checking in on the call
 * every second, so the ringing stops when the caller hangs up or it runs out, as iOS's `poll` does.
 *
 * Once Porch is on screen, its own incoming screen takes the call over ([handOver]), and Answer on the notification
 * opens Porch and answers there ([answerWhenShown]). Porch leaving the screen while its own screen rings hands the call
 * back here. Main thread only.
 */
class SystemCalls(private val app: PorchApplication) {
    private class Ringing(val callID: String, val credential: FamilyCredential, val notification: Notification, var expiresAt: Long) {
        var job: Job? = null
    }

    private var ringing: Ringing? = null
    /** Calls that rang here or were turned away, newest last, so a repeated push doesn't ring again. */
    private val recent = ArrayDeque<String>()
    /** A call answered from its notification, which Porch answers as it opens. */
    private var answering: String? = null

    /** Whether this call rings here now. */
    fun isRinging(callID: String) = ringing?.callID == callID

    /** What Porch's call service shows while a call rings here. */
    val notification: Notification? get() = ringing?.notification

    /** A call push, from Firebase (PorchMessagingService). */
    fun receivePush(data: Map<String, String>) {
        val callID = data["callID"]?.lowercase()
        val name = data["callerName"]?.take(80)?.ifBlank { null } ?: "Family"
        val expiresAt = data["expiresAt"]?.toDoubleOrNull()?.toLong() ?: 0
        // Porch on screen rings in its own screen from its next check-in, a second or two away.
        if (app.onScreen && app.screenReady) return
        // Porch's own screen may already be showing this call: the server pushes even when Porch is open, and that
        // push can arrive after the check-in that rang. Ending it here would hang up the call on screen.
        if (callID != null && (ringing?.callID == callID || app.calls.owns(callID))) return
        val credential = recipient(data["recipientID"])
        if (callID == null || !idPattern.matches(callID) || credential == null || expiresAt <= nowSeconds() || callID in recent) {
            // Every call push shows a call before anything else, even one that's stale or a repeat, which then ends at
            // once, as iOS must with PushKit. Firebase also stops trusting high-priority messages that show nothing.
            acknowledge()
            return
        }
        if (app.calls.busy || ringing != null) {
            // On another call: it shows and ends, and the caller hears it was missed.
            acknowledge()
            remember(callID)
            app.scope.launch { endMissed(callID, credential) }
            return
        }
        ring(callID, credential, name, data["mode"] == "video", expiresAt)
    }

    /**
     * Rings through a notification: a push's call, or one Porch's own screen was ringing when Porch left the screen.
     * `quiet` keeps it showing without ringing, as after the power button, which silences a phone's call.
     */
    fun ring(callID: String, credential: FamilyCredential, name: String, video: Boolean, expiresAt: Long, quiet: Boolean = false) {
        if (ringing != null || expiresAt <= nowSeconds()) return
        val caller = if (credential.role == PorchExperience.FAMILY) FamilyNames.caller(name, app.device.familyName(credential)) else name
        val notification = CallNotifications.incoming(app, callID, caller, video, expiresAt, quiet)
        val call = Ringing(callID, credential, notification, expiresAt)
        ringing = call
        remember(callID)
        // Posted before anything else, so it rings even if the service can't start.
        CallNotifications.post(app, CallNotifications.INCOMING, notification)
        app.calls.updateService()
        call.job = app.scope.launch { poll(call) }
    }

    /**
     * Checks in on the ringing call every second, as iOS does with `receivedCallID`, which tells the caller it rang here.
     * It stops when the call ends, someone else answers, nothing gets through for 25 seconds, or it runs out.
     */
    private suspend fun poll(call: Ringing) {
        var lastSuccess = SystemClock.elapsedRealtime()
        while (ringing === call) {
            try {
                val values = app.coordinator.pollOrder.next(mapOf("available" to JsonPrimitive(false), "receivedCallID" to JsonPrimitive(call.callID)))
                val response = app.service(call.credential).send("poll", values)
                if (ringing !== call) return
                app.coordinator.update(response)
                val state = response.state
                val current = state?.call
                if (state == null || current == null || current.id != call.callID || current.to != state.me.id || current.kind != "call" ||
                    current.state != "pending") {
                    stop(call)
                    return
                }
                call.expiresAt = current.expiresAt
                lastSuccess = SystemClock.elapsedRealtime()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if ((e as? FamilyServiceException)?.status == 401 || SystemClock.elapsedRealtime() - lastSuccess > 25_000) {
                    stop(call)
                    return
                }
            }
            if (nowSeconds() >= call.expiresAt) {
                stop(call)
                // A family phone leaves an unanswered call to the bedside's own wait, which may try their phone next.
                if (call.credential.role == PorchExperience.BEDSIDE) app.scope.launch { endMissed(call.callID, call.credential) }
                return
            }
            delay(1_000)
        }
    }

    /** Porch's own incoming screen took this call over, now that Porch is on screen. */
    fun handOver(callID: String) {
        val call = ringing?.takeIf { it.callID == callID } ?: return
        stop(call)
    }

    /** Decline, on the notification. Porch's own incoming screen, once it has the call, declines it. */
    fun decline(callID: String) {
        val call = ringing?.takeIf { it.callID == callID } ?: run {
            app.calls.incoming?.takeIf { it.call.id == callID }?.decline()
            return
        }
        stop(call)
        app.scope.launch {
            try { app.service(call.credential).send("endCall", mapOf("callID" to JsonPrimitive(callID))) }
            catch (e: CancellationException) { throw e } catch (_: Exception) {}
        }
    }

    /** Answer, on the notification, opens Porch. Its incoming screen answers as soon as it shows the call, or now if
     * it's already showing it. */
    fun answerWhenShown(callID: String) {
        val showing = app.calls.incoming?.takeIf { it.call.id == callID.lowercase() }
        if (showing != null && app.onScreen) showing.answer() else answering = callID.lowercase()
    }

    /** Whether Porch should answer this call as it shows it, because Answer was tapped on its notification. */
    fun takeAnswer(callID: String): Boolean {
        if (answering != callID.lowercase()) return false
        answering = null
        return true
    }

    private fun stop(call: Ringing) {
        if (ringing !== call) return
        ringing = null
        call.job?.cancel()
        NotificationManagerCompat.from(app).cancel(CallNotifications.INCOMING)
        // Porch's own incoming screen or a call in progress may still need the service.
        app.calls.updateService()
    }

    /** Shows a call for a moment and takes it away, silently: a push that won't ring still shows something, as
     * Firebase requires. */
    private fun acknowledge() {
        CallNotifications.post(app, CallNotifications.MISSED, CallNotifications.passing(app))
        NotificationManagerCompat.from(app).cancel(CallNotifications.MISSED)
    }

    private suspend fun endMissed(callID: String, credential: FamilyCredential) {
        try { app.service(credential).send("endCall", mapOf("callID" to JsonPrimitive(callID), "unanswered" to JsonPrimitive(true))) }
        catch (e: CancellationException) { throw e } catch (_: Exception) {}
    }

    /** The pairing a push is for. A family phone has one per family, each with its own member ID. */
    private fun recipient(memberID: String?): FamilyCredential? {
        memberID ?: return null
        return when (app.device.experience) {
            PorchExperience.BEDSIDE -> app.device.credential(PorchExperience.BEDSIDE)?.takeIf { it.deviceID == memberID }
            PorchExperience.FAMILY -> app.device.families.firstOrNull { it.deviceID == memberID }
            else -> null
        }
    }

    private fun remember(callID: String) {
        recent.addLast(callID)
        while (recent.size > 32) recent.removeFirst()
    }

    private fun nowSeconds() = System.currentTimeMillis() / 1_000

    private companion object {
        val idPattern = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
    }
}

/** Porch's call notifications: one that rings, and one for a call in progress while Porch isn't in front. */
object CallNotifications {
    const val INCOMING = 41
    const val ONGOING = 42
    const val MISSED = 43
    const val ACTION_INCOMING = "com.ethanteng.helloporch.INCOMING_CALL"
    const val ACTION_ANSWER = "com.ethanteng.helloporch.ANSWER_CALL"
    const val ACTION_DECLINE = "com.ethanteng.helloporch.DECLINE_CALL"
    const val ACTION_HANG_UP = "com.ethanteng.helloporch.HANG_UP_CALL"
    const val EXTRA_CALL = "callID"
    private const val RINGING_CHANNEL = "calls"
    private const val ONGOING_CHANNEL = "calls-in-progress"

    /** The ringing channel plays the ringtone and vibrates, like a phone call, and the in-progress one is silent. */
    fun createChannels(context: Context) {
        val manager = context.getSystemService<NotificationManager>() ?: return
        val ringtone = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        manager.createNotificationChannel(NotificationChannel(RINGING_CHANNEL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Rings when family calls and Porch isn't open."
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), ringtone)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1_000, 1_000)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        })
        manager.createNotificationChannel(NotificationChannel(ONGOING_CHANNEL, "Calls in progress", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Shows a Porch call that goes on while Porch isn't in front."
            setSound(null, null)
        })
    }

    /** Rings until it's answered, declined or taken away, and shows Porch full screen on a locked phone. A `quiet` one
     * only shows, such as while Porch's own incoming screen is up, or after the power button silenced it. */
    fun incoming(context: Context, callID: String, caller: String, video: Boolean, expiresAt: Long, quiet: Boolean = false): Notification {
        val person = Person.Builder().setName(caller).setImportant(true).build()
        val open = activity(context, ACTION_INCOMING, callID, 0)
        val answer = activity(context, ACTION_ANSWER, callID, 1)
        val decline = PendingIntent.getBroadcast(context, 2, Intent(context, CallActionReceiver::class.java).setAction(ACTION_DECLINE)
            .putExtra(EXTRA_CALL, callID), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = NotificationCompat.Builder(context, if (quiet) ONGOING_CHANNEL else RINGING_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(caller)
            .setContentText(if (video) "Incoming video call" else "Incoming audio call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(if (quiet) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setContentIntent(open)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, decline, answer).setIsVideo(video))
            .setTimeoutAfter(((expiresAt - System.currentTimeMillis() / 1_000).coerceAtLeast(1)) * 1_000)
        if (quiet) return builder.build()
        // Rings again and again, like a phone, rather than once.
        return builder.setFullScreenIntent(open, true).build().apply { flags = flags or Notification.FLAG_INSISTENT }
    }

    /** A call going on while Porch isn't in front, with Hang up. Tapping it opens Porch's call screen. */
    fun ongoing(context: Context, name: String): Notification {
        val person = Person.Builder().setName(name).setImportant(true).build()
        val hangUp = PendingIntent.getBroadcast(context, 3, Intent(context, CallActionReceiver::class.java).setAction(ACTION_HANG_UP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(context, ONGOING_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(name)
            .setContentText("Porch call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(activity(context, ACTION_INCOMING, "", 4))
            .setStyle(NotificationCompat.CallStyle.forOngoingCall(person, hangUp))
            .build()
    }

    /** A silent note for a call that won't ring here, taken away at once. */
    fun passing(context: Context): Notification = NotificationCompat.Builder(context, ONGOING_CHANNEL)
        .setSmallIcon(R.drawable.ic_launcher_monochrome)
        .setContentTitle("Porch")
        .setContentText("A call that can't ring now")
        .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
        .setTimeoutAfter(1_000)
        .build()

    fun post(context: Context, id: Int, notification: Notification) {
        try { NotificationManagerCompat.from(context).notify(id, notification) }
        catch (e: SecurityException) { Log.w("Porch", "Notifications aren't allowed", e) }
    }

    private fun activity(context: Context, action: String, callID: String, code: Int) =
        PendingIntent.getActivity(context, code, Intent(context, MainActivity::class.java).setAction(action).putExtra(EXTRA_CALL, callID)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}

/**
 * Keeps Porch running for a call while it isn't in front: ringing, as a phone call, and a call in progress, with the
 * microphone too, so it goes on when the phone locks (decision 8 in android/PLAN.md). The camera only runs while Porch
 * is in front.
 */
class CallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val shown = pending
        if (shown != null && promote(shown.id, shown.notification, shown.types)) return START_NOT_STICKY
        // The microphone type can be refused once Porch is in the background. A phone-call service still keeps the call.
        val phoneCall = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        if (shown != null && shown.types != phoneCall && promote(shown.id, shown.notification, phoneCall)) return START_NOT_STICKY
        // startForegroundService crashes the process unless startForeground runs, including when the call ended first.
        promote(CallNotifications.MISSED, CallNotifications.passing(this), phoneCall)
        stopSelf()
        return START_NOT_STICKY
    }

    /** Android requires this for every startForegroundService, or it kills the process a few seconds later. */
    private fun promote(id: Int, notification: Notification, types: Int): Boolean = try {
        ServiceCompat.startForeground(this, id, notification, types)
        true
    } catch (e: Exception) {
        Log.w("Porch", "The call's service couldn't start", e)
        false
    }

    override fun onDestroy() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private class Shown(val id: Int, val notification: Notification, val types: Int)

    companion object {
        private var pending: Shown? = null
        private var running = false

        /** Starts the service, or changes what it shows, such as from ringing to a call in progress. */
        fun show(context: Context, id: Int, notification: Notification, types: Int) {
            pending = Shown(id, notification, types)
            try {
                ContextCompat.startForegroundService(context, Intent(context, CallService::class.java))
                running = true
            } catch (e: Exception) {
                // Android can refuse to start it from the background. The notification still rings.
                Log.w("Porch", "The call's service couldn't start", e)
            }
        }

        fun stop(context: Context) {
            pending = null
            if (!running) return
            running = false
            context.stopService(Intent(context, CallService::class.java))
        }
    }
}

/** Decline and Hang up, on Porch's call notifications. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as PorchApplication
        when (intent.action) {
            CallNotifications.ACTION_DECLINE -> intent.getStringExtra(CallNotifications.EXTRA_CALL)?.let(app.systemCalls::decline)
            CallNotifications.ACTION_HANG_UP -> app.calls.active?.endCall()
        }
    }
}
