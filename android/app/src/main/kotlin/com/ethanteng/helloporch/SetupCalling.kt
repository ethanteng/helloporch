package com.ethanteng.helloporch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.input.InputManager
import android.os.Handler
import android.os.Looper
import android.view.InputDevice
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTrigger
import kotlinx.coroutines.delay

/** The microphone and camera, asked for in setup so the first call doesn't stop at a prompt. */
object SetupPermissions {
    val all = listOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA)
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
    FormSection("Microphone and camera", "Porch uses them for calls, so family can hear and see $lovedOne. The tablet asks once for each.") {
        FormButton("Continue", onClick = {
            val asking = SetupPermissions.all.filter { !SetupPermissions.granted(app, it) }
            SetupPermissions.noteAsked(app)
            if (asking.isEmpty()) onContinue() else request.launch(asking.toTypedArray())
        })
    }
}

/** How they'll call: a corded phone through the Cell2Jack, or a USB keypad, each with a screen to connect and check it,
 * or just the touchscreen, which needs nothing. Android needs no driver for the Cell2Jack, so a tablet that can be a USB
 * host offers it. */
@Composable
fun SetupCallingScreen(lovedOne: String, offersCordedPhone: Boolean, onCordedPhone: () -> Unit, onUSBKeypad: () -> Unit, onTouchscreen: () -> Unit) {
    FormSection("How will $lovedOne call?", "$lovedOne presses a key to call someone. The touchscreen works too, whichever you choose.") {
        if (offersCordedPhone) CallingOption("Corded phone", "A desk phone plugged into a Cell2Jack.", onCordedPhone)
        CallingOption("USB keypad", "A number keypad plugged into this tablet.", onUSBKeypad)
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

/**
 * Connect the USB keypad, as `SetupUSBKeypadViewController` does on iOS: a number keypad plugged into the tablet is a
 * keyboard to it, so there's nothing to turn on. The screen shows when the tablet sees a keyboard, then has the caregiver
 * press a key and shows the one Porch heard, without acting on it. Do this later goes on all the same. `onContinue`
 * goes on, for Continue and Do this later; setup goes to adding the caregiver's phone.
 */
@Composable
fun SetupUSBKeypadScreen(lovedOne: String, onContinue: () -> Unit) {
    val context = LocalContext.current
    // The key Porch heard. Saved, because plugging a keypad in recreates the activity.
    var heard by rememberSaveable { mutableStateOf<String?>(null) }
    var connected by remember { mutableStateOf(externalKeyboardConnected(context)) }
    var helping by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        val input = context.getSystemService(InputManager::class.java)
        val listener = object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(deviceId: Int) { connected = externalKeyboardConnected(context) }
            override fun onInputDeviceRemoved(deviceId: Int) { connected = externalKeyboardConnected(context) }
            override fun onInputDeviceChanged(deviceId: Int) { connected = externalKeyboardConnected(context) }
        }
        input.registerInputDeviceListener(listener, Handler(Looper.getMainLooper()))
        onDispose { input.unregisterInputDeviceListener(listener) }
    }
    // Keys come here while the screen is open, so pressing one never calls anyone.
    val keys = LocalKeyListener.current
    val trigger = remember { CallTrigger() }
    val receive by rememberUpdatedState { digit: Int -> heard = CallSlots.symbol(digit) }
    DisposableEffect(keys) {
        keys.onKey = { event ->
            val slot = keypadSlot(event)
            when {
                slot == null -> false
                event.action == KeyEvent.ACTION_DOWN -> { if (event.repeatCount == 0 && trigger.keyDown(event.keyCode)) receive(slot); true }
                event.action == KeyEvent.ACTION_UP -> { trigger.keyUp(event.keyCode); true }
                else -> true
            }
        }
        onDispose { keys.onKey = null; trigger.resetKeys() }
    }
    // Help waits until about 30 seconds go by with nothing happening. A key heard is the check; plugging and
    // unplugging after it doesn't undo that.
    val checked = heard != null
    LaunchedEffect(checked, connected) {
        helping = false
        if (!checked) { delay(30_000); helping = true }
    }
    val status = when {
        heard != null -> "Porch heard $heard. The keypad is ready."
        // Any keyboard counts, such as a keyboard case, so the key is the check.
        connected -> "A keypad or keyboard is connected. Press a number key."
        else -> "Waiting for the keypad…"
    }
    FormSection("Connect the USB keypad", "$lovedOne can call by pressing a key on a number keypad plugged into this tablet.") {
        Text("1. Plug the keypad into this tablet. If its plug doesn't fit, use an adapter for the tablet's port.", style = MaterialTheme.typography.bodyLarge)
        Text("2. Press a number key.", style = MaterialTheme.typography.bodyLarge)
        Text(status, Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite }, textAlign = TextAlign.Center,
            style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        if (helping && !checked) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Not working?", style = MaterialTheme.typography.titleMedium)
                Text("• Unplug the keypad and plug it back in, then press a number key.", style = MaterialTheme.typography.bodyLarge)
                Text("• If the keypad has a Num Lock key, press it once, then press a number key again.", style = MaterialTheme.typography.bodyLarge)
            }
        }
        if (checked) FormButton("Continue", onClick = onContinue) else FormLink("Do this later", onClick = onContinue)
    }
}

/** The keypad key for a key press, as `UIKey.keypadDigit` reads it on iOS: none with Ctrl, Alt or Meta held. */
fun keypadSlot(event: KeyEvent): Int? {
    if (event.isCtrlPressed || event.isAltPressed || event.isMetaPressed) return null
    val character = event.getUnicodeChar(event.metaState)
    val characters = if (character > 0) String(Character.toChars(character)) else ""
    return CallTrigger.slot(event.keyCode, characters, event.isShiftPressed)
}

/** A keyboard or keypad plugged in, as `GCKeyboard.coalesced` sees one on iOS. The tablet's own buttons and the
 * on-screen keyboard aren't. */
private fun externalKeyboardConnected(context: Context): Boolean {
    val input = context.getSystemService(InputManager::class.java)
    return input.inputDeviceIds.any { id ->
        val device = input.getInputDevice(id) ?: return@any false
        !device.isVirtual && device.isExternal && device.supportsSource(InputDevice.SOURCE_KEYBOARD)
    }
}
