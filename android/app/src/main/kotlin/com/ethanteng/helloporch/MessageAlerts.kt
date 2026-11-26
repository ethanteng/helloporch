package com.ethanteng.helloporch

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PorchExperience

/**
 * Notifications for messages the bedside leaves when this phone misses its call, as iOS's FamilyMessageAlerts shows
 * them, and for caregivers when another caregiver turns Every call drop-in on or off (`type: "everyCall"`, on the
 * `every-call` channel), or the bedside's desk phone has been out for a while or is back (`type: "phone"`, on the `phone`
 * channel), which open the Call tab. The server sends each as a Firebase notification on the `messages` channel, tagged with the family it's from
 * (lib/family/push.ts), which Android shows itself while Porch isn't in front; while it is, Porch shows it the same way.
 * Tapping one opens that family's thread. A family's notification goes once its messages have been played. Main thread
 * only.
 */
class MessageAlerts(private val app: PorchApplication) {
    /** A family's thread to open, by this phone's device ID in it, from a tapped notification. */
    var opening by mutableStateOf<String?>(null)
    /** A family to make current on the Call tab, by this phone's device ID in it, from a tapped Every call, call or phone notice. */
    var openingCall by mutableStateOf<String?>(null)
    /** Each family's unplayed count when it last checked in, by device ID. */
    private val unplayed = mutableMapOf<String, Int>()

    /** Whether message notifications can show: allowed, and the channel not turned off. */
    fun allowed(): Boolean {
        val permitted = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val manager = NotificationManagerCompat.from(app)
        val channel = manager.getNotificationChannel(CHANNEL)
        return permitted && manager.areNotificationsEnabled() && channel?.importance != NotificationManager.IMPORTANCE_NONE
    }

    /** A message notification that arrived while Porch is running, which Android leaves to Porch to show. */
    fun received(title: String?, body: String?, data: Map<String, String>) {
        val recipient = data["recipientID"] ?: return
        if (app.device.experience != PorchExperience.FAMILY || app.device.families.none { it.deviceID == recipient }) return
        if (!allowed()) return
        val count = data["badge"]?.toIntOrNull() ?: 1
        // Left while this phone was on Do Not Disturb: in the quiet channel, as Firebase would have shown it.
        val quiet = data["quiet"] == "1"
        val notification = NotificationCompat.Builder(app, if (quiet) QUIET_CHANNEL else CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title ?: "New message")
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(if (quiet) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setNumber(count)
            .setContentIntent(open(app, recipient))
            .build()
        try {
            NotificationManagerCompat.from(app).notify(tag(recipient), 0, notification)
        } catch (_: SecurityException) {
            // Notifications were turned off meanwhile.
        }
    }

    /** An Every call notice that arrived while Porch is running, shown as Firebase would have: one per family, the newest
     * replacing the last. */
    fun receivedEveryCall(title: String?, body: String?, data: Map<String, String>) {
        val recipient = data["recipientID"] ?: return
        if (app.device.experience != PorchExperience.FAMILY || app.device.families.none { it.deviceID == recipient }) return
        val permitted = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (!permitted) return
        val notification = NotificationCompat.Builder(app, EVERY_CALL_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title ?: "Every call drop-in changed")
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(open(app, recipient, "everyCall"))
            .build()
        try {
            NotificationManagerCompat.from(app).notify("$EVERY_CALL_TAG_PREFIX$recipient", 0, notification)
        } catch (_: SecurityException) {
            // Notifications were turned off meanwhile.
        }
    }

    /** A notice that the bedside's desk phone isn't connected, or is again, that arrived while Porch is running, shown as
     * Firebase would have: one of each for a family, the newest replacing the last. */
    fun receivedPhone(title: String?, body: String?, data: Map<String, String>) {
        val recipient = data["recipientID"] ?: return
        val state = data["state"]?.takeIf { it == "out" || it == "back" } ?: return
        if (app.device.experience != PorchExperience.FAMILY || app.device.families.none { it.deviceID == recipient }) return
        val permitted = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (!permitted) return
        val notification = NotificationCompat.Builder(app, PHONE_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title ?: if (state == "out") "The phone isn’t connected" else "The phone is connected again")
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(open(app, recipient, "phone"))
            .build()
        try {
            NotificationManagerCompat.from(app).notify("$PHONE_TAG_PREFIX$recipient-$state", 0, notification)
        } catch (_: SecurityException) {
            // Notifications were turned off meanwhile.
        }
    }

    /** A tapped notification opened Porch: its family's thread opens, or for an Every call, call or phone notice the Call tab
     * with that family as the current one, once that family is on this phone. Firebase's own notifications carry their
     * data as extras on the launch, and Porch's carry the same. */
    fun opened(intent: Intent?) {
        val type = intent?.getStringExtra("type")
        if (type != "message" && type != "everyCall" && type != "phone") return
        val recipient = intent.getStringExtra("recipientID") ?: return
        if (app.device.experience != PorchExperience.FAMILY) return
        if (type == "message") opening = recipient else openingCall = recipient
    }

    /** With each check-in: a family's notification goes once its messages are played, when it removed this phone, or
     * when this phone has left that family. */
    fun noteLinks(links: FamilyLinks) {
        if (app.device.experience != PorchExperience.FAMILY) return
        val manager = NotificationManagerCompat.from(app)
        val present = mutableSetOf<String>()
        for (link in links.links) {
            val id = link.credential.deviceID
            present += id
            val count = if (link.accessRemoved) 0 else link.state?.newMessages ?: continue
            val before = unplayed.put(id, count)
            if (count == 0 && before != 0) {
                // The first count this process sees can come from a check-in that left before a notification it doesn't
                // know of yet. One shown in the last minute stays, until a later check-in counts it; an older one, such as
                // for messages played while Porch was closed, goes.
                if (before == null && !link.accessRemoved) cancelShownBefore(manager, id, System.currentTimeMillis() - 60_000)
                else manager.cancel(tag(id), 0)
            }
        }
        // Leave this family drops the link without a zero count, so the notification would stay.
        for (id in unplayed.keys.filter { it !in present }) {
            unplayed.remove(id)
            manager.cancel(tag(id), 0)
        }
        // One posted before this process recorded a count, such as Firebase's own, is still showing.
        try {
            for (status in manager.activeNotifications) {
                val tag = status.tag ?: continue
                if (!tag.startsWith(TAG_PREFIX) || tag.removePrefix(TAG_PREFIX) in present) continue
                manager.cancel(tag, status.id)
            }
        } catch (_: RuntimeException) {
            // The notification service can be briefly unavailable. The next check-in tries again.
        }
    }

    private fun cancelShownBefore(manager: NotificationManagerCompat, id: String, time: Long) {
        try {
            for (status in manager.activeNotifications) {
                if (status.tag == tag(id) && status.postTime < time) manager.cancel(status.tag, status.id)
            }
        } catch (_: RuntimeException) {
            // The notification service can be briefly unavailable. A later check-in clears it once it's played.
        }
    }

    companion object {
        /** The channel the server names for message notifications. */
        const val CHANNEL = "messages"

        /** The channel the server names for messages left while this phone is on Do Not Disturb: no sound, no pop-up. */
        const val QUIET_CHANNEL = "messages-quiet"

        /** The channel the server names for Every call notices. */
        const val EVERY_CALL_CHANNEL = "every-call"
        private const val EVERY_CALL_TAG_PREFIX = "porch-everycall-"

        /** The channel the server names for notices that the bedside's desk phone isn't connected, or is again. */
        const val PHONE_CHANNEL = "phone"
        /** The server tags each with the family and whether it's out or back: porch-phone-<recipientID>-<state>. */
        private const val PHONE_TAG_PREFIX = "porch-phone-"

        /** The tag the server gives a family's message notifications, so its newest replaces the last. */
        private const val TAG_PREFIX = "porch-messages-"
        fun tag(recipientID: String) = "$TAG_PREFIX$recipientID"

        fun createChannel(context: Context) {
            val manager = context.getSystemService<NotificationManager>() ?: return
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "When your loved one leaves you a message after a call you missed."
            })
            manager.createNotificationChannel(NotificationChannel(QUIET_CHANNEL, "Messages during Do Not Disturb", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Messages your loved one leaves while Do Not Disturb is on in Porch."
            })
            manager.createNotificationChannel(NotificationChannel(EVERY_CALL_CHANNEL, "Drop-in changes", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "For caregivers: when someone turns Every call drop-in on or off."
            })
            manager.createNotificationChannel(NotificationChannel(PHONE_CHANNEL, "Phone connection", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "For caregivers: when the desk phone by the bed isn’t connected, and when it’s back."
            })
        }

        /** Opens Porch at a family's thread, or with `type` "everyCall" or "phone" at its Call tab card (`opened`). */
        internal fun open(context: Context, recipient: String, type: String = "message"): PendingIntent =
            // NEW_TASK: this intent is fired from a notification, not an activity. Without it, tapping the
            // notification after Porch has left its task throws and the thread never opens. singleTask still
            // delivers it to the running activity (onNewIntent) when Porch is already open.
            PendingIntent.getActivity(context, if (type == "message") recipient.hashCode() else "$type:$recipient".hashCode(), Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("type", type).putExtra("recipientID", recipient),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}
