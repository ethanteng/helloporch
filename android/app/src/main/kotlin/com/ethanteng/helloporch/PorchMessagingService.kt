package com.ethanteng.helloporch

import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Firebase Cloud Messaging, which wakes Porch for a call when it isn't open (lib/family/push.ts): a data-only,
 * high-priority message with `type: "call"`, `callID`, `recipientID`, `callerName`, `mode` and `expiresAt`. There's no
 * push that cancels one; the ringing notices by checking in. A message the bedside left is a notification with
 * `type: "message"`, which Firebase shows itself unless Porch is running, when it comes here to show (MessageAlerts).
 * A caregiver's notice that Every call drop-in was turned on or off is one too, with `type: "everyCall"`. A notice of a
 * phone call to the bedside while Every call is on is data only, `type: "callNotice"`, which Porch shows (CallNotices).
 * A caregiver's notice that the bedside's desk phone isn't connected, or is again, is a notification with `type: "phone"`.
 * Firebase calls this off the main thread.
 */
class PorchMessagingService : FirebaseMessagingService() {
    private val main = Handler(Looper.getMainLooper())

    override fun onNewToken(token: String) {
        val app = application as PorchApplication
        main.post { app.push.tokenChanged(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data.toMap()
        val app = application as PorchApplication
        if (data["type"] == "message") {
            val title = message.notification?.title
            val body = message.notification?.body
            main.post { app.messageAlerts.received(title, body, data) }
            return
        }
        // Data only, so Porch builds it with End call and Turn off Every call, whether or not it's running.
        if (data["type"] == "callNotice") {
            main.post { CallNotices.received(app, data) }
            return
        }
        if (data["type"] == "everyCall") {
            val title = message.notification?.title
            val body = message.notification?.body
            main.post { app.messageAlerts.receivedEveryCall(title, body, data) }
            return
        }
        if (data["type"] == "phone") {
            val title = message.notification?.title
            val body = message.notification?.body
            main.post { app.messageAlerts.receivedPhone(title, body, data) }
            return
        }
        if (data["type"] != "call") return
        // Android allows a call's service to start only for a moment after a high-priority message, so this doesn't wait.
        main.post { app.systemCalls.receivePush(data) }
    }
}
