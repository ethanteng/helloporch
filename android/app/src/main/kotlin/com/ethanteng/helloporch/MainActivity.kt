package com.ethanteng.helloporch

import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Intent
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.ethanteng.helloporch.core.AttendanceTracker
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.RemoteCaregiverSession

/** Porch's one activity. An invitation or setup link that opens Porch arrives here, when it starts or while it's open. */
class MainActivity : ComponentActivity() {
    private val link = mutableStateOf<String?>(null)
    private val keys = KeyListener()
    /** Porch is showing a call in Android's floating picture-in-picture window (FloatingCall). */
    private val pictureInPicture = mutableStateOf(false)
    /** The family video call that shrinks to that window as Porch leaves the screen, if there is one. */
    private var floating: PorchCall? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A link not yet handled survives the activity being recreated, such as when the phone turns.
        link.value = if (savedInstanceState == null) intent?.dataString else savedInstanceState.getString(linkKey)
        // Android recreates the activity as it shrinks into the floating window, so the new one may start there.
        pictureInPicture.value = isInPictureInPictureMode
        val app = application as PorchApplication
        if (savedInstanceState == null) { openedForCall(intent); app.messageAlerts.opened(intent) }
        // The Cell2Jack is the bedside's keypad, so it runs only while the bedside is in front, setup included.
        // Switching to the bedside while this activity is already resumed starts it too (PorchApplication.switchExperience).
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onResume(owner: LifecycleOwner) { app.bedsideCameToFront(); RemoteCaregiverSession.shared.returned() }
            override fun onPause(owner: LifecycleOwner) = app.bedsideLeftFront()
            // Caregiver mode on a family phone ends when Porch leaves the screen, as on iOS, but not when it turns.
            override fun onStop(owner: LifecycleOwner) { if (!isChangingConfigurations) RemoteCaregiverSession.shared.leftForeground() }
        })
        setContent {
            PorchBedsideTheme {
                // A family member keeps seeing the person they're on a video call with while they use another app, as on
                // iOS (CallPictureInPicture). The bedside stays in front. A call that couldn't start stays on its
                // screen until Close, and must not float: the window would show a photo and name after the other side
                // was already hung up.
                val active = app.calls.active
                val call = active?.takeIf { it.role == PorchExperience.FAMILY && it.video && !it.failed }
                LaunchedEffect(call) { floatOnLeaving(call) }
                // The call ended in the window, or it failed: the window closes, rather than showing Porch that small.
                val over = pictureInPicture.value && (active == null || active.failed)
                LaunchedEffect(over) { if (over) moveTaskToBack(false) }
                CompositionLocalProvider(LocalKeyListener provides keys, LocalPictureInPicture provides pictureInPicture.value) {
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
        (application as PorchApplication).messageAlerts.opened(intent)
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

    /** Opens the floating window for `call` as Porch leaves, on Android 12 and later by itself, with End call on it. */
    private fun floatOnLeaving(call: PorchCall?) {
        floating = call
        val params = floatingParams(call)
        if (Build.VERSION.SDK_INT >= 31) params.setAutoEnterEnabled(call != null)
        runCatching { setPictureInPictureParams(params.build()) }
    }

    private fun floatingParams(call: PorchCall?): PictureInPictureParams.Builder {
        // The bedside stands sideways, so its picture is wide.
        val params = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        if (call != null) params.setActions(listOf(RemoteAction(Icon.createWithResource(this, R.drawable.ic_call_end),
            "End call", "End call", CallNotifications.hangUp(this))))
        return params
    }

    // Android 11 and earlier don't open the window by themselves, so leaving for the home screen or another app does.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < 31 && floating != null) runCatching { enterPictureInPictureMode(floatingParams(floating).build()) }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pictureInPicture.value = isInPictureInPictureMode
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(linkKey, link.value)
    }

    // Any touch or key press means someone is at the tablet, as `PorchWindow.sendEvent` counts them on iOS. Each still
    // goes on as before: nothing here uses one up.
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        AttendanceTracker.shared.noticed()
        return super.dispatchTouchEvent(event)
    }
    // Android calls this for every key event dispatched here, from a keypad, the Cell2Jack's adapter or a keyboard, and
    // for each touch going down. androidx restricts overriding `dispatchKeyEvent`.
    override fun onUserInteraction() {
        super.onUserInteraction()
        AttendanceTracker.shared.noticed()
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

/** Porch is showing a call in Android's floating picture-in-picture window. */
val LocalPictureInPicture = staticCompositionLocalOf { false }
