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
 * them. The server sends each as a Firebase notification on the `messages` channel, tagged with the family it's from
 * (lib/family/push.ts), which Android shows itself while Porch isn't in front; while it is, Porch shows it the same way.
 * Tapping one opens that family's thread. A family's notification goes once its messages have been played. Main thread
 * only.
 */
class MessageAlerts(private val app: PorchApplication) {
    /** A family's thread to open, by this phone's device ID in it, from a tapped notification. */
    var opening by mutableStateOf<String?>(null)
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
        val notification = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title ?: "New message")
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
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

    /** A tapped notification opened Porch: its family's thread opens, once that family is on this phone. Firebase's own
     * notifications carry their data as extras on the launch, and Porch's carry the same. */
    fun opened(intent: Intent?) {
        if (intent?.getStringExtra("type") != "message") return
        val recipient = intent.getStringExtra("recipientID") ?: return
        if (app.device.experience == PorchExperience.FAMILY) opening = recipient
    }

    /** With each check-in: a family's notification goes once its messages are played, or when it removed this phone. */
    fun noteLinks(links: FamilyLinks) {
        if (app.device.experience != PorchExperience.FAMILY) return
        val manager = NotificationManagerCompat.from(app)
        for (link in links.links) {
            val id = link.credential.deviceID
            val count = if (link.accessRemoved) 0 else link.state?.newMessages ?: continue
            val before = unplayed.put(id, count)
            if (count == 0 && before != 0) manager.cancel(tag(id), 0)
        }
    }

    companion object {
        /** The channel the server names for message notifications. */
        const val CHANNEL = "messages"

        /** The tag the server gives a family's message notifications, so its newest replaces the last. */
        fun tag(recipientID: String) = "porch-messages-$recipientID"

        fun createChannel(context: Context) {
            val manager = context.getSystemService<NotificationManager>() ?: return
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "When your loved one leaves you a message after a call you missed."
            })
        }

        private fun open(context: Context, recipient: String): PendingIntent =
            PendingIntent.getActivity(context, recipient.hashCode(), Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("type", "message").putExtra("recipientID", recipient),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}
