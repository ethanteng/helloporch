package com.ethanteng.helloporch

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.PorchExperience
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/**
 * A caregiver's notice of each phone call to the bedside while Every call is on (lib/family/push.ts): a data-only Firebase
 * message with `type: "callNotice"`, `recipientID`, `callID`, `title` and `body`, which Porch builds itself so it can carry
 * End call and Turn off Every call, as iOS's PORCH_CALL_NOTICE category does. Both run in the background with that
 * family's own credential and no PIN (CallNoticeReceiver), and the notice goes once one has gone through. Tapping the
 * notice opens the Call tab, as an Every call notice does. Each call has its own notice, on the `every-call` channel.
 */
object CallNotices {
    const val ACTION_END_CALL = "com.ethanteng.helloporch.action.END_BEDSIDE_CALL"
    const val ACTION_TURN_OFF = "com.ethanteng.helloporch.action.TURN_OFF_EVERY_CALL"
    internal const val EXTRA_RECIPIENT = "recipientID"
    internal const val EXTRA_CALL = "callID"
    internal const val EXTRA_TITLE = "title"
    internal const val EXTRA_BODY = "body"
    /** As long as the server keeps the push, an hour: a notice of a call that's long over goes on its own. */
    private const val LIFETIME_MILLIS = 3_600_000L

    fun tag(callID: String) = "porch-call-$callID"

    /** A call notice from Firebase, which always comes here, Porch running or not. Main thread. */
    fun received(app: PorchApplication, data: Map<String, String>) {
        val recipient = data["recipientID"] ?: return
        val callID = data["callID"] ?: return
        if (app.device.experience != PorchExperience.FAMILY || app.device.families.none { it.deviceID == recipient }) return
        show(app, recipient, callID, data["title"] ?: "A call to the bedside", data["body"].orEmpty())
    }

    /** Shows the notice, or shows it again saying why an action didn't go through. Nothing while notifications aren't allowed. */
    fun show(context: Context, recipient: String, callID: String, title: String, body: String) {
        val permitted = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (!permitted) return
        val notification = NotificationCompat.Builder(context, MessageAlerts.EVERY_CALL_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setTimeoutAfter(LIFETIME_MILLIS)
            .setContentIntent(MessageAlerts.open(context, recipient, "everyCall"))
            .addAction(0, "End call", action(context, ACTION_END_CALL, recipient, callID, title, body))
            .addAction(0, "Turn off Every call", action(context, ACTION_TURN_OFF, recipient, callID, title, body))
            .build()
        try {
            NotificationManagerCompat.from(context).notify(tag(callID), 0, notification)
        } catch (_: SecurityException) {
            // Notifications were turned off meanwhile.
        }
    }

    fun dismiss(context: Context, callID: String) = NotificationManagerCompat.from(context).cancel(tag(callID), 0)

    /** An explicit, immutable broadcast to Porch's own receiver, one for each call and action. */
    private fun action(context: Context, action: String, recipient: String, callID: String, title: String, body: String): PendingIntent =
        PendingIntent.getBroadcast(context, "$action:$callID".hashCode(), Intent(context, CallNoticeReceiver::class.java).setAction(action)
            .putExtra(EXTRA_RECIPIENT, recipient).putExtra(EXTRA_CALL, callID).putExtra(EXTRA_TITLE, title).putExtra(EXTRA_BODY, body),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}

/**
 * End call and Turn off Every call on a call notice, without opening Porch: sent as the family member the notice is for,
 * which needs no PIN (`endBedsideCall`, `turnOffEveryCall`). Gone through, the notice goes; ending a call that's already
 * over goes through too. Otherwise the notice stays, saying why, so it can be tried again.
 */
class CallNoticeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as PorchApplication
        val recipient = intent.getStringExtra(CallNotices.EXTRA_RECIPIENT) ?: return
        val callID = intent.getStringExtra(CallNotices.EXTRA_CALL) ?: return
        val request: Pair<String, Map<String, JsonElement>> = when (intent.action) {
            CallNotices.ACTION_END_CALL -> "endBedsideCall" to mapOf("callID" to JsonPrimitive(callID))
            CallNotices.ACTION_TURN_OFF -> "turnOffEveryCall" to emptyMap()
            else -> return
        }
        // This phone left that family since: there's nothing it can do there.
        val family = app.device.families.firstOrNull { it.deviceID == recipient } ?: run { CallNotices.dismiss(app, callID); return }
        val title = intent.getStringExtra(CallNotices.EXTRA_TITLE).orEmpty()
        val pending = goAsync()
        app.scope.launch {
            try {
                val problem = try {
                    // A broadcast may run for about ten seconds, so this gives up a little sooner than the request would.
                    val response = withTimeoutOrNull(9_000) { app.service(family).send(request.first, request.second) }
                    if (response == null) "Couldn't reach Porch. Try again." else { app.coordinator.update(response); null }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: FamilyServiceException) {
                    e.message
                } catch (_: Exception) {
                    "Couldn't reach Porch. Try again."
                }
                if (problem == null) CallNotices.dismiss(app, callID) else CallNotices.show(app, recipient, callID, title, problem)
            } finally {
                pending.finish()
            }
        }
    }
}
