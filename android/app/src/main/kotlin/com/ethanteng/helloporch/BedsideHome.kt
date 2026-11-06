package com.ethanteng.helloporch

import android.text.format.DateFormat
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchNumber
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.delay

/**
 * The bedside's home screen: the time, whether Porch is checking in, the household's number, and Call, which opens the
 * people the bedside can call. A keypad key calls whoever is on it. The full clock comes later in phase 3. Until the tablet is set up, Set up Porch opens setup, as the clock's caregiver button does
 * on iOS. A setup that stopped after its PIN goes on from here, after the PIN.
 */
@Composable
fun BedsideHome(app: PorchApplication, links: FamilyLinks, setup: BedsideSetup) {
    val paired = links.credential != null || app.device.credential(PorchExperience.BEDSIDE) != null
    val state = links.state
    var picking by rememberSaveable { mutableStateOf(false) }
    if (picking && state != null) { BedsidePeople(app, links, onClose = { picking = false }); return }
    // A key calls whoever is on it. The receiver put back while a call is starting stops it opening.
    if (state != null) CallKeys(app, onDigit = app.calls::bedsideKey, onHangUp = app.calls::cancelPendingCall)
    Surface(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.safeDrawingPadding().fillMaxSize()) {
            val clockSize = (minOf(maxWidth.value * 0.16f, maxHeight.value * 0.3f)).sp
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
                Clock(clockSize)
                Column(Modifier.widthIn(max = 760.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val name = state?.householdName
                    Text(when {
                        !paired -> "Porch isn't set up on this tablet yet."
                        links.accessRemoved -> "This tablet isn't part of ${name?.let { "$it's" } ?: "its"} Porch anymore."
                        // A failed check-in keeps the last snapshot, which is what a dropped connection looks like.
                        links.error != null -> "Porch can't check in right now. ${links.error}"
                        state != null -> "Porch is on and checking in."
                        else -> "Checking in…"
                    }, textAlign = TextAlign.Center, style = MaterialTheme.typography.titleLarge)
                    val number = state?.porchNumber
                    if (number != null && name != null) {
                        Text("$name's Porch number", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(PorchNumber.display(number), fontSize = 34.sp, fontWeight = FontWeight.Bold)
                    } else if (state?.phoneSetup != null && name != null) {
                        Text("Porch is still getting $name's phone number.", textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyLarge)
                    }
                    if (!paired) FormButton("Set up Porch", onClick = { setup.start() }, Modifier.widthIn(max = 420.dp))
                    else if (state != null && setup.unfinished) FormButton("Finish setting up Porch", onClick = setup::openGate, Modifier.widthIn(max = 420.dp))
                    if (state != null && !setup.unfinished) {
                        val calls = app.calls
                        FormButton(BedsideText.string(app, if (calls.opening) "Calling…" else "Call"), onClick = { picking = true },
                            Modifier.widthIn(max = 420.dp), enabled = !calls.opening)
                        calls.notice?.let { Text(it, textAlign = TextAlign.Center, style = MaterialTheme.typography.titleLarge) }
                    }
                    Text("This test version shows the clock, checks in and makes calls while Porch is open. Messages and caregiver mode come in later versions.",
                        textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

/** Weekday, time and date in the tablet's language, with AM or PM smaller, refreshed on the minute. */
@Composable
private fun Clock(size: androidx.compose.ui.unit.TextUnit) {
    val context = LocalContext.current
    var now by remember { mutableStateOf(LocalDateTime.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = LocalDateTime.now()
            delay(ChronoUnit.MILLIS.between(now, now.truncatedTo(ChronoUnit.MINUTES).plusMinutes(1)).coerceAtLeast(1))
        }
    }
    val twentyFour = DateFormat.is24HourFormat(context)
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(now.format(DateTimeFormatter.ofPattern("EEEE")), style = MaterialTheme.typography.headlineMedium)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(now.format(DateTimeFormatter.ofPattern(if (twentyFour) "H:mm" else "h:mm")), fontSize = size, fontWeight = FontWeight.Light, maxLines = 1)
            if (!twentyFour) Text(now.format(DateTimeFormatter.ofPattern("a")), Modifier.padding(start = 8.dp, bottom = (size.value * 0.2f).dp),
                fontSize = size * 0.25f, fontWeight = FontWeight.Light)
        }
        Text(now.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG)), style = MaterialTheme.typography.headlineSmall)
    }
}

/** The caregiver PIN before setup goes on, as caregiver mode's gate asks for it on iOS. */
@Composable
fun CaregiverGate(setup: BedsideSetup) {
    var pin by rememberSaveable { mutableStateOf("") }
    BackHandler { setup.closeGate() }
    FormScreen("Caregiver mode", navigation = { TextButton(onClick = setup::closeGate) { Text("Cancel") } }) {
        FormSection("Your caregiver PIN") {
            FormField(pin, { pin = it.filter(Char::isDigit).take(6) }, "Six-digit PIN", "Enter six digits",
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), visualTransformation = PasswordVisualTransformation())
            FormButton("Open caregiver mode", onClick = { setup.unlock(pin) }, enabled = !setup.checkingPIN)
        }
        // Reachable without the PIN, so anyone at the bedside can read it.
        PrivacyPolicyLink()
    }
    PorchErrorDialog(setup.error) { setup.error = null }
}
