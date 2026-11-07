package com.ethanteng.helloporch

import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.view.WindowManager
import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.core.content.getSystemService
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/**
 * Porch as the bedside tablet's home screen, so it's what the tablet shows after it restarts or loses power, and what
 * Home comes back to. An activity alias with the home category (`BedsideLauncher` in AndroidManifest.xml) is on only
 * while this device is the bedside, so a family phone never offers Porch as a home screen. Android 15 won't start a
 * call's foreground service from a boot broadcast; a home app avoids needing one.
 */
object BedsideHomeScreen {
    private fun alias(context: Context) = ComponentName(context.packageName, "com.ethanteng.helloporch.BedsideLauncher")

    /** Offers Porch as a home screen in bedside mode, and stops offering it otherwise. */
    fun sync(context: Context, bedside: Boolean) {
        val packages = context.packageManager
        val current = packages.getComponentEnabledSetting(alias(context))
        // The manifest leaves the alias disabled, which PackageManager reports as DEFAULT until this sets it.
        val enabled = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        if (enabled == bedside) return
        val state = if (bedside) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        packages.setComponentEnabledSetting(alias(context), state, PackageManager.DONT_KILL_APP)
    }

    /** Whether Porch is this tablet's home screen. */
    fun isHome(context: Context): Boolean = context.getSystemService<RoleManager>()?.isRoleHeld(RoleManager.ROLE_HOME) == true

    /** Android's question to make Porch the home screen, or null where there's none to ask. */
    fun request(context: Context): Intent? =
        context.getSystemService<RoleManager>()?.takeIf { it.isRoleAvailable(RoleManager.ROLE_HOME) }?.createRequestRoleIntent(RoleManager.ROLE_HOME)
}

/**
 * The bedside's window: always on, so the clock stays lit and calls can ring, and shown over the lock screen, turning
 * the screen on when Porch comes to the front, as for an incoming call. `overLock` shows a family phone's call over the
 * lock screen too, while it rings or goes on. `immersive` also hides the status and navigation bars, which a swipe
 * brings back for a moment; setup and caregiver screens keep them.
 */
@Composable
fun BedsideWindow(alwaysOn: Boolean, immersive: Boolean, overLock: Boolean = alwaysOn) {
    val activity = LocalActivity.current ?: return
    DisposableEffect(activity, alwaysOn) {
        if (alwaysOn) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {}
    }
    DisposableEffect(activity, alwaysOn || overLock) {
        activity.setShowWhenLocked(alwaysOn || overLock)
        activity.setTurnScreenOn(alwaysOn || overLock)
        onDispose {}
    }
    DisposableEffect(activity, immersive) {
        val bars = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
        bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (immersive) bars.hide(WindowInsetsCompat.Type.systemBars()) else bars.show(WindowInsetsCompat.Type.systemBars())
        onDispose {}
    }
}
