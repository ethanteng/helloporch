package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ethanteng.helloporch.core.Cell2JackDigitEvent
import com.ethanteng.helloporch.core.Cell2JackPhoneCheck
import kotlinx.coroutines.delay

/**
 * Connect the phone: the desk phone by the bed, through the Cell2Jack, becomes Porch's keypad. As on iOS
 * (SetupPhoneViewController), Porch tries the Cell2Jack while this screen is open and turns the phone keypad on itself
 * once it answers, then has the caregiver press a key and hang up to check the phone. Unlike the iPad there's no
 * driver to turn on, no ten-second replug and no M-chip requirement: Android asks once to let Porch use the Cell2Jack
 * instead.
 *
 * Keys pressed here only show the one Porch heard, so nothing else should act on [Cell2JackKeypad.events] while this
 * screen is showing. Do this later, or going back to choose another way, leaves the phone keypad off unless the phone
 * was already checked; This tablet in caregiver mode can open this screen again.
 */
@Composable
fun CordedPhoneSetup(keypad: Cell2JackKeypad, onDone: () -> Unit, onBack: () -> Unit) {
    var check by rememberSaveable(stateSaver = phoneCheckSaver) { mutableStateOf<Cell2JackPhoneCheck>(Cell2JackPhoneCheck.Waiting) }
    // This screen turned the keypad on. Leaving before the check finishes undoes that; one that was already on stays on.
    var enabledHere by rememberSaveable { mutableStateOf(false) }
    // Leaving, so a late change can't put the waiting text back up or turn the keypad on again.
    var leaving by remember { mutableStateOf(false) }
    var tips by remember { mutableStateOf(false) }
    val ready by keypad.isReady.collectAsStateWithLifecycle()
    val access by keypad.access.collectAsStateWithLifecycle()

    // Porch tries the Cell2Jack while this screen is open, with the phone keypad on or off. A trial that's still
    // running when it goes would keep the desk phone live with the keypad off.
    DisposableEffect(keypad) {
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
    // Help waits until about 30 seconds go by with nothing happening.
    LaunchedEffect(check) {
        tips = false
        if (!check.checked) { delay(30_000); tips = true }
    }

    fun leave(turnOff: Boolean) {
        leaving = true
        if (turnOff) { keypad.setEnabled(false); enabledHere = false }
        if (keypad.trying) keypad.endTrial()
    }
    // Going back to choose another way is like Do this later.
    val back = { leave(turnOff = enabledHere && !check.checked); onBack() }
    BackHandler(onBack = back)

    val status = when {
        check != Cell2JackPhoneCheck.Waiting -> check.status
        access == Cell2JackKeypad.Access.NEEDS_PERMISSION -> "Porch needs permission to use the Cell2Jack."
        else -> check.status
    }
    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 760.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                TextButton(onClick = back) { Text("Back") }
                Text("Connect the phone", style = MaterialTheme.typography.headlineMedium)
                Text("${LocalBedsideName.current} can call by pressing a key on the desk phone. You'll need the phone and the Cell2Jack.")
                Text("1. Plug the phone into the Cell2Jack, and the Cell2Jack into this tablet.", style = MaterialTheme.typography.bodyLarge)
                Text("2. When Android asks to let Porch use the Cell2Jack, choose to always open Porch, then tap OK.",
                    style = MaterialTheme.typography.bodyLarge)
                if (access == Cell2JackKeypad.Access.NEEDS_PERMISSION && !check.checked) {
                    OutlinedButton(onClick = keypad::requestPermission, Modifier.testTag("setup.phoneAllow")) { Text("Allow Porch to use the Cell2Jack") }
                }
                Text(status, Modifier.fillMaxWidth().testTag("setup.phoneStatus").semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                if (tips) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Not working?", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                        for (tip in phoneTips) Text("• $tip", style = MaterialTheme.typography.bodyLarge)
                    }
                }
                if (check.checked) {
                    Button(onClick = { leave(turnOff = false); onDone() }, Modifier.testTag("setup.phoneDone")) { Text("Continue") }
                } else {
                    // Do this later is the way out before the check finishes, and it leaves the keypad off.
                    TextButton(onClick = { leave(turnOff = enabledHere); onDone() }, Modifier.testTag("setup.phoneLater")) { Text("Do this later") }
                }
            }
        }
    }
}

private val phoneTips = listOf(
    "Unplug the Cell2Jack and plug it back in. When Android asks, choose to always open Porch.",
    "Set the phone to tone dialing. Porch can't hear pulse dialing.",
    "The keys work only while the receiver is lifted.",
    "If the Cell2Jack says the phone isn't connected when you lift the receiver, press a key and it stops.",
)

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
