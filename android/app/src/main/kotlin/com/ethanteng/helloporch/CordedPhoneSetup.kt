package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ethanteng.helloporch.core.Cell2JackDigitEvent
import com.ethanteng.helloporch.core.Cell2JackPhoneCheck

/**
 * Connect the phone: the desk phone by the bed, through the Cell2Jack, becomes Porch's keypad. As on iOS
 * (SetupPhoneViewController), Porch tries the Cell2Jack while this screen is open and turns the phone keypad on itself
 * once it answers, then has the caregiver press a key and hang up to check the phone. Unlike the iPad there's no
 * adapter, driver or M chip: the Cell2Jack plugs straight in, and Android asks once to let Porch use it. The screen says
 * only that; the steps, the parts and the tips are in the Android guide, behind Step-by-step instructions.
 *
 * Keys pressed here only show the one Porch heard, so nothing else should act on [Cell2JackKeypad.events] while this
 * screen is showing. Do this later, or going back to choose another way, leaves the phone keypad off unless the phone
 * was already checked; This tablet in caregiver mode can open this screen again, with `title` Connect the phone.
 */
@Composable
fun CordedPhoneSetup(keypad: Cell2JackKeypad, onDone: () -> Unit, onBack: () -> Unit, title: String = "Set up Porch") {
    var check by rememberSaveable(stateSaver = phoneCheckSaver) { mutableStateOf<Cell2JackPhoneCheck>(Cell2JackPhoneCheck.Waiting) }
    // This screen turned the keypad on. Leaving before the check finishes undoes that; one that was already on stays on.
    var enabledHere by rememberSaveable { mutableStateOf(false) }
    // Leaving, so a late change can't put the waiting text back up or turn the keypad on again.
    var leaving by remember { mutableStateOf(false) }
    val ready by keypad.isReady.collectAsStateWithLifecycle()
    val access by keypad.access.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // Porch tries the Cell2Jack while this screen is open, with the phone keypad on or off. A trial that's still
    // running when it goes would keep the desk phone live with the keypad off. A connection waiting to try again
    // tries now, as This tablet's Retry phone connection used to: opening this screen is how to retry.
    DisposableEffect(keypad) {
        keypad.retry()
        keypad.beginTrial()
        onDispose { if (keypad.trying) keypad.endTrial() }
    }
    // Plugged in before this screen opened, Android asks now. Plugged in while it's open, Android asks by itself.
    LaunchedEffect(keypad) {
        if (keypad.access.value == Cell2JackKeypad.Access.NEEDS_PERMISSION) keypad.requestPermission()
    }
    LaunchedEffect(ready) {
        if (leaving) return@LaunchedEffect
        if (ready && !keypad.enabled.value) {
            // Turned on for them: from now on the phone is their keypad, here and on the clock.
            keypad.setEnabled(true)
            enabledHere = true
        }
        check = check.answering(ready)
    }
    LaunchedEffect(keypad) {
        keypad.events.collect { event ->
            if (leaving) return@collect
            check = if (event.kind == Cell2JackDigitEvent.Kind.HANG_UP) check.hangUp() else check.key(event.digit, keypad.receiverHangUp)
            val heard = if (event.kind == Cell2JackDigitEvent.Kind.HANG_UP) "hang-up" else event.digit
            keypad.record("setupPhone", "heard" to heard, "status" to check.status)
        }
    }

    fun leave(turnOff: Boolean) {
        leaving = true
        if (turnOff) { keypad.setEnabled(false); enabledHere = false }
        if (keypad.trying) keypad.endTrial()
    }
    // Going back to choose another way is like Do this later.
    val back = { leave(turnOff = enabledHere && !check.checked); onBack() }
    BackHandler(onBack = back)

    val needsPermission = access == Cell2JackKeypad.Access.NEEDS_PERMISSION && check == Cell2JackPhoneCheck.Waiting
    CordedPhoneSetupScreen(
        title, check,
        status = if (needsPermission) "Porch needs permission to use the Cell2Jack." else check.status,
        needsPermission = needsPermission && !check.checked,
        onAllow = keypad::requestPermission,
        onGuide = { openAndroidGuide(context) },
        onContinue = { leave(turnOff = false); onDone() },
        // Do this later is the way out before the check finishes, and it leaves the keypad off.
        onLater = { leave(turnOff = enabledHere); onDone() },
        onBack = back,
    )
}

/** What Connect the phone shows for a step of the check, apart from the Cell2Jack itself: the explanation and the guide,
 * then a panel with the step's icon over its status, then the way on. */
@Composable
internal fun CordedPhoneSetupScreen(title: String, check: Cell2JackPhoneCheck, status: String,
    needsPermission: Boolean, onAllow: () -> Unit, onGuide: () -> Unit, onContinue: () -> Unit, onLater: () -> Unit,
    onBack: () -> Unit) {
    FormScreen(title, navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        FormCard("Connect the phone") {
            // The link reads as part of the explanation, so they sit closer together than the rest of the card.
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Plug the desk phone in with the Cell2Jack.",
                    Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                // The steps, the parts and the tips are on the website, which can change without an update.
                TextButton(onClick = onGuide, Modifier.testTag("setup.phoneGuide")) {
                    Text("Step-by-step instructions")
                    Spacer(Modifier.width(6.dp))
                    Icon(painterResource(R.drawable.ic_north_east), contentDescription = null, Modifier.size(16.dp))
                }
            }
            PhoneCheckPanel(check, status)
            if (needsPermission) {
                FormButton("Allow Porch to use the Cell2Jack", onClick = onAllow, Modifier.testTag("setup.phoneAllow"), filled = false)
            }
            if (check.checked) FormButton("Continue", onClick = onContinue, Modifier.testTag("setup.phoneDone"))
            else TextButton(onClick = onLater, Modifier.testTag("setup.phoneLater")) { Text("Do this later") }
        }
    }
}

/** The status, under a round badge whose icon shows the step: waiting, press a key, put the receiver back, done. It's
 * the part of the screen that changes, so it sits apart in a tinted panel, as on iOS. */
@Composable
private fun PhoneCheckPanel(check: Cell2JackPhoneCheck, status: String) {
    val colors = MaterialTheme.colorScheme
    val icon = when (check) {
        Cell2JackPhoneCheck.Waiting -> R.drawable.ic_phone_in_talk
        Cell2JackPhoneCheck.Connected -> R.drawable.ic_dialpad
        is Cell2JackPhoneCheck.Heard -> R.drawable.ic_call_end
        is Cell2JackPhoneCheck.Done -> R.drawable.ic_check
    }
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), color = colors.surfaceVariant.copy(alpha = 0.5f)) {
        Column(Modifier.padding(horizontal = 24.dp, vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            // Done fills the badge in. Waiting is grey until the phone is there.
            Surface(Modifier.size(72.dp), shape = CircleShape, color = if (check.checked) colors.primary else colors.surface) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(painterResource(icon), contentDescription = null, Modifier.size(34.dp), tint = when {
                        check.checked -> colors.onPrimary
                        check == Cell2JackPhoneCheck.Waiting -> colors.onSurfaceVariant
                        else -> colors.primary
                    })
                }
            }
            Text(status, Modifier.fillMaxWidth().testTag("setup.phoneStatus").semantics { liveRegion = LiveRegionMode.Polite },
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        }
    }
}

/** Saved, so turning the tablet keeps a check that finished. A connected or half-done check starts over anyway, as
 * the Cell2Jack reconnects when the screen comes back. */
private val phoneCheckSaver = listSaver<Cell2JackPhoneCheck, String>(
    save = { check ->
        when (check) {
            Cell2JackPhoneCheck.Waiting -> listOf("waiting")
            Cell2JackPhoneCheck.Connected -> listOf("connected")
            is Cell2JackPhoneCheck.Heard -> listOf("heard", check.symbol)
            is Cell2JackPhoneCheck.Done -> listOf("done", check.message)
        }
    },
    restore = { saved ->
        when (saved.firstOrNull()) {
            "connected" -> Cell2JackPhoneCheck.Connected
            "heard" -> Cell2JackPhoneCheck.Heard(saved[1])
            "done" -> Cell2JackPhoneCheck.Done(saved[1])
            else -> Cell2JackPhoneCheck.Waiting
        }
    },
)
