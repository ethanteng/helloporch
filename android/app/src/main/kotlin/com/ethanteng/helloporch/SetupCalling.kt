package com.ethanteng.helloporch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.view.KeyEvent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.CallTrigger

/** The microphone and camera, asked for in setup so the first call doesn't stop at a prompt, and on Android 13 and
 * later notifications, which ring the tablet if Porch isn't in front. */
object SetupPermissions {
    val all = listOfNotNull(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA,
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null)
    /** Android says only whether a permission is granted, not whether it was ever asked, which iOS's resume rule goes
     * by. So Porch notes when it asks. */
    private const val askedKey = "porch.setup.permissionsAsked"

    fun granted(context: Context, permission: String) = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    /** Setup skips the screen when both are already allowed. */
    fun needed(context: Context) = all.any { !granted(context, it) }
    /** Either was never asked about: iOS's `notDetermined`. */
    fun neverAsked(app: PorchApplication) = needed(app) && app.settings.getBoolean(askedKey) != true
    fun noteAsked(app: PorchApplication) = app.settings.putBoolean(askedKey, true)
}

/** One Continue asks for both. Turned off, before or just now, Porch goes on; Settings can still turn them on. */
@Composable
fun SetupPermissionsScreen(app: PorchApplication, lovedOne: String, onContinue: () -> Unit) {
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { onContinue() }
    val notifications = Build.VERSION.SDK_INT >= 33
    FormSection(if (notifications) "Microphone, camera and notifications" else "Microphone and camera",
        if (notifications) "Porch uses the microphone and camera for calls, so family can hear and see $lovedOne, and notifications to ring if " +
            "Porch isn't in front. The tablet asks once for each."
        else "Porch uses them for calls, so family can hear and see $lovedOne. The tablet asks once for each.") {
        FormButton("Continue", onClick = {
            val asking = SetupPermissions.all.filter { !SetupPermissions.granted(app, it) }
            SetupPermissions.noteAsked(app)
            if (asking.isEmpty()) onContinue() else request.launch(asking.toTypedArray())
        })
    }
}

/** How they'll call: a corded phone through the Cell2Jack, with a screen to connect and check it, or just the
 * touchscreen, which needs nothing. Android needs no driver for the Cell2Jack, so a tablet that can be a USB host offers
 * it. */
@Composable
fun SetupCallingScreen(lovedOne: String, offersCordedPhone: Boolean, onCordedPhone: () -> Unit, onTouchscreen: () -> Unit) {
    FormSection("How will $lovedOne call?", "$lovedOne presses a key to call someone. The touchscreen works too, whichever you choose.") {
        if (offersCordedPhone) CallingOption("Corded phone", "A desk phone plugged into a Cell2Jack.", onCordedPhone)
        FormLink("Just the touchscreen", onClick = onTouchscreen)
    }
}

/** A choice, which opens the screen for connecting it. That screen can come back here to choose another. */
@Composable
private fun CallingOption(title: String, detail: String, onClick: () -> Unit) {
    Button(onClick, Modifier.fillMaxWidth().heightIn(min = 50.dp)) {
        Column(Modifier.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)
            Text(detail, Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

/** The name setup is using, such as Mom, for a screen that comes in through the corded-phone slot. */
val LocalBedsideName = compositionLocalOf { "Your loved one" }

/** Stands in for connecting the corded phone, which needs the Cell2Jack connection (built alongside this). */
@Composable
fun CordedPhoneLater(onDone: () -> Unit, onBack: () -> Unit) {
    FormScreen("Set up Porch", navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        FormSection("Connect the phone", "The corded phone connection comes in a later build of Porch for Android. Go back to choose another way, or skip it for now.") {
            FormButton("Skip", onClick = onDone)
        }
    }
}

/** The keypad key for a key press, as `UIKey.keypadDigit` reads it on iOS: none with Ctrl, Alt or Meta held. */
fun keypadSlot(event: KeyEvent): Int? {
    if (event.isCtrlPressed || event.isAltPressed || event.isMetaPressed) return null
    val character = event.getUnicodeChar(event.metaState)
    val characters = if (character > 0) String(Character.toChars(character)) else ""
    return CallTrigger.slot(event.keyCode, characters, event.isShiftPressed)
}
