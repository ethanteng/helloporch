package com.ethanteng.helloporch

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.ethanteng.helloporch.core.RemoteCaregiverSession

/** Porch's one activity. An invitation or setup link that opens Porch arrives here, when it starts or while it's open. */
class MainActivity : ComponentActivity() {
    private val link = mutableStateOf<String?>(null)
    private val keys = KeyListener()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A link not yet handled survives the activity being recreated, such as when the phone turns.
        link.value = if (savedInstanceState == null) intent?.dataString else savedInstanceState.getString(linkKey)
        val app = application as PorchApplication
        if (savedInstanceState == null) openedForCall(intent)
        // The Cell2Jack is the bedside's keypad, so it runs only while the bedside is in front, setup included.
        // Switching to the bedside while this activity is already resumed starts it too (PorchApplication.switchExperience).
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onResume(owner: LifecycleOwner) { app.bedsideCameToFront(); RemoteCaregiverSession.shared.returned() }
            override fun onPause(owner: LifecycleOwner) = app.bedsideLeftFront()
            // Caregiver mode on a family phone ends when Porch leaves the screen, as on iOS, but not when it turns.
            override fun onStop(owner: LifecycleOwner) { if (!isChangingConfigurations) RemoteCaregiverSession.shared.leftForeground() }
        })
        setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalKeyListener provides keys) {
                    PorchRoot(app, link.value, onLinkHandled = { link.value = null },
                        cordedPhoneSetup = { onDone, onBack -> CordedPhoneSetup(app.cell2jack, onDone, onBack) })
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Opened again from outside, such as from the launcher while a photo picker it opened was up: the caregiver
        // went elsewhere from there, so a family phone's caregiver mode ends. Porch never saw them leave.
        RemoteCaregiverSession.shared.reopened()
        openedForCall(intent)
        intent.dataString?.let { link.value = it }
    }

    /** Opened from a call's notification: over the lock screen, turning the screen on, as Android shows a phone call.
     * Answer on the notification answers as Porch shows the call. */
    private fun openedForCall(intent: Intent?) {
        val action = intent?.action
        if (action != CallNotifications.ACTION_INCOMING && action != CallNotifications.ACTION_ANSWER) return
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        val app = application as PorchApplication
        app.calls.openForCall()
        if (action == CallNotifications.ACTION_ANSWER) intent.getStringExtra(CallNotifications.EXTRA_CALL)?.let(app.systemCalls::answerWhenShown)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(linkKey, link.value)
    }

    // A keypad's keys reach the screen listening for them once Compose has passed them up, as `pressesBegan` does on
    // iOS. Nothing on that screen takes typing, so digits always get here.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = keys.onKey?.invoke(event) == true || super.onKeyDown(keyCode, event)
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean = keys.onKey?.invoke(event) == true || super.onKeyUp(keyCode, event)

    private companion object { const val linkKey = "porch.link" }
}

/** Keys from a keypad or keyboard that Compose didn't use, for the one screen listening for them. It returns true for a
 * key it handled. */
class KeyListener { var onKey: ((KeyEvent) -> Boolean)? = null }

val LocalKeyListener = staticCompositionLocalOf { KeyListener() }
