package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.ethanteng.helloporch.core.PhoneNumberNormalization
import com.ethanteng.helloporch.core.ValidationException
import kotlinx.coroutines.launch

/** What adding someone to a call opens over the call screen: who can be rung in, the form for a phone number, the added
 * phone's keypad, and why something didn't go through. */
@Composable
fun CallGuestDialogs(guests: CallGuests, video: Boolean) {
    guests.choices?.let { people ->
        AlertDialog(onDismissRequest = guests::closeChoices,
            title = { Text("Add someone to this call") },
            text = {
                // A large family scrolls, so everyone stays reachable on a short phone.
                Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (video) Text("Family join on Porch with video.")
                    people.forEach { person ->
                        TextButton(onClick = { guests.ring(person) }, Modifier.fillMaxWidth()) { Text(person.name, fontSize = 20.sp) }
                    }
                    if (guests.choicesIncludePhone) TextButton(onClick = guests::choosePhone, Modifier.fillMaxWidth()) { Text("A phone number…", fontSize = 20.sp) }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = guests::closeChoices) { Text("Cancel") } })
    }
    if (guests.phoneForm) PhoneGuestForm(guests)
    else PorchErrorDialog(guests.dialProblem) { guests.dialProblem = null }
    if (guests.keypad) PhoneGuestKeypad(guests)
    PorchErrorDialog(guests.error) { guests.error = null }
}

/** Under the call's status: Keypad and Hang up for the phone this one added, such as a bank, while it's on the call. */
@Composable
fun PhoneGuestControls(app: PorchApplication, guests: CallGuests, modifier: Modifier = Modifier) {
    val phone = guests.phone ?: return
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CallButton("Keypad", guests.phoneAnswered, onClick = guests::openKeypad, app = app, modifier = Modifier.weight(1f))
        CallButton("Hang up ${phone.label}", !guests.hangingUp, onClick = guests::hangUp, color = CallColors.end, translated = true, app = app,
            modifier = Modifier.weight(1f))
    }
}

/** Names and dials the phone to add, as iOS's AddPhoneGuestViewController does. The name is what the bedside shows. */
@Composable
private fun PhoneGuestForm(guests: CallGuests) {
    var name by rememberSaveable { mutableStateOf("") }
    var number by rememberSaveable { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pickContact = rememberLauncherForActivityResult(PickPhoneNumber()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val picked = pickedNumber(context, uri) ?: run { problem = "That contact's number couldn't be read. Type it instead."; return@launch }
            picked.first?.takeIf { it.isNotBlank() }?.let { name = it.take(40) }
            number = picked.second
        }
    }
    fun dial() {
        val label = name.trim()
        if (label.isEmpty()) { problem = "Enter who you're calling, such as Bank."; return }
        // Numbers without a country code are North American, wherever this phone is set up.
        val e164 = try { PhoneNumberNormalization.e164(number, "US") } catch (e: ValidationException) { problem = e.message; return }
        guests.beginDial(label.take(40), e164)
    }
    fun chooseContact() {
        // A phone with no contacts app must not crash the call. The number can be typed instead.
        try { pickContact.launch(Unit) } catch (_: ActivityNotFoundException) { problem = "This phone has no contacts app. Type the number instead." }
    }
    // Closing or turning the phone doesn't cancel a dial that may already be ringing, so Cancel waits until it settles.
    Dialog(onDismissRequest = { if (!guests.dialing) guests.closePhoneForm() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        FormScreen("Add a phone", navigation = { TextButton(onClick = guests::closePhoneForm, enabled = !guests.dialing) { Text("Cancel") } }) {
            FormSection("Who should join the call?", "Porch calls this number and adds them to your call. If you hang up, their call ends too.") {
                FormField(name, { name = it.take(40) }, "Who are you calling?", "For example, Bank", enabled = !guests.dialing,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
                Text("The bedside shows this name.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                FormField(number, { number = it }, "Their phone number", "(800) 555-0123", enabled = !guests.dialing,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone))
                Text("US and Canadian numbers, including toll-free numbers.", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                FormButton("Choose from Contacts", filled = false, enabled = !guests.dialing, onClick = ::chooseContact)
                FormButton(if (guests.dialing) "Calling…" else "Call and add to this call", enabled = !guests.dialing, onClick = ::dial)
            }
        }
    }
    PorchErrorDialog(problem ?: guests.dialProblem) { problem = null; guests.dialProblem = null }
}

/** Sends key presses to the added phone, for menus such as "press 1 for your account balance". */
@Composable
private fun PhoneGuestKeypad(guests: CallGuests) {
    val label = guests.phone?.label ?: return
    Dialog(onDismissRequest = guests::closeKeypad, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        FormScreen("Keypad for $label", actions = { TextButton(onClick = guests::closeKeypad) { Text("Done") } }) {
            Text(guests.keysPressed.ifEmpty { " " }, Modifier.fillMaxWidth().semantics { contentDescription = "Keys pressed" },
                fontSize = 32.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.StartEllipsis)
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                listOf("123", "456", "789", "*0#").forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        row.forEach { key ->
                            val spoken = when (key) { '*' -> "Star"; '#' -> "Pound"; else -> key.toString() }
                            Button(onClick = { guests.press(key) }, Modifier.weight(1f).heightIn(min = 72.dp).semantics { contentDescription = spoken },
                                colors = ButtonDefaults.filledTonalButtonColors()) {
                                Text(key.toString(), fontSize = 30.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
        }
    }
}
