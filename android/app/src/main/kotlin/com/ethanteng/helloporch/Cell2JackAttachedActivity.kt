package com.ethanteng.helloporch

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.UserManager
import androidx.core.content.getSystemService

/**
 * Where Android sends the Cell2Jack when it's plugged in. Opening Porch for it is what lets Porch use it: Android gives
 * the permission to the app it opens. When the tablet starts up with the Cell2Jack already plugged in, Android looks for
 * that app before the tablet is unlocked, and then finds only apps that can run before it is. Porch's main activity
 * can't, so the permission was never given and the phone stayed silent until someone plugged it back in.
 *
 * This activity can run then. It runs in its own process (`:usb`), where [PorchApplication] starts nothing, because
 * Porch's settings can't be read until the tablet is unlocked. Once it is, it opens Porch, as plugging the Cell2Jack in
 * always has.
 */
class Cell2JackAttachedActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (getSystemService<UserManager>()?.isUserUnlocked == true) {
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        finish()
    }

    companion object {
        /** The process this activity runs in, named in AndroidManifest.xml. */
        const val processSuffix = ":usb"
    }
}
