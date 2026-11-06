package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PhoneNumberNormalization
import com.ethanteng.helloporch.core.ValidationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

private enum class DropInScreen { PERSON, ADD_PHONE }

/** The Drop-in page, or a person or a new phone number opened from it in its place. */
@Composable
fun DropInPages(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onBack: (() -> Unit)?) {
    var screen by rememberSaveable { mutableStateOf<DropInScreen?>(null) }
    var memberID by rememberSaveable { mutableStateOf<String?>(null) }
    when (screen) {
        null -> FormScreen(CaregiverPage.DROP_IN.title, navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }) {
            DropInPage(app, admin, links, onPerson = { memberID = it; screen = DropInScreen.PERSON }, onAddPhone = { screen = DropInScreen.ADD_PHONE })
        }
        DropInScreen.PERSON -> PersonPage(app, admin, links, memberID, null, onDone = { screen = null })
        DropInScreen.ADD_PHONE -> AddPhoneDropInScreen(admin, onDone = { screen = null })
    }
}

/**
 * Who can drop in, as iOS's DropInSettingsViewController shows it: the switch that pauses drop-ins for everyone, then
 * family members and phone numbers that can, and family members who can't. A drop-in answers on this tablet, so it
 * needs the tablet's microphone, and for video its camera.
 */
@Composable
private fun DropInPage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onPerson: (String) -> Unit, onAddPhone: () -> Unit) {
    val context = LocalContext.current
    val mediaAccess = rememberMediaAccess()
    val state = admin.state(links)
    val enabled = state?.dropInEnabled == true
    val people = state?.people.orEmpty()
    val video = people.any { it.permissions.video }
    // Read again when Porch comes back, such as from the tablet's settings.
    var checks by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { checks++ }
    val granted = remember(video, checks) { mediaGranted(context, video) }
    val devices = if (video) "microphone and camera" else "microphone"

    Text("Drop-ins connect on their own after a short announcement.", style = MaterialTheme.typography.bodyLarge)
    CaregiverGroup {
        ToggleRow("Allow drop-ins", enabled, enabled = state != null && !admin.busy, detail = if (enabled) null else "Paused. Approvals are kept.", onChange = { on ->
            if (!on) admin.perform("setDropIn", mapOf("enabled" to JsonPrimitive(false)))
            else mediaAccess(video) { allowed ->
                checks++
                if (allowed) admin.perform("setDropIn", mapOf("enabled" to JsonPrimitive(true)))
                else admin.error = "Allow the $devices for Porch in the tablet's settings before turning on drop-ins."
            }
        })
        if (enabled && !granted) {
            HorizontalDivider()
            CaregiverRow { Text("Allow the $devices for Porch in the tablet's settings, or drop-ins can't connect.", color = MaterialTheme.colorScheme.error) }
        }
    }

    val ink = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant
    val can = people.filter { it.permissions.audio || it.permissions.video }
    val phones = state?.phoneDropIns.orEmpty()
    CaregiverGroup("Can drop in") {
        can.forEachIndexed { index, person ->
            if (index > 0) HorizontalDivider()
            val photo = remember(person.photoID, FamilyPhotos.saved) { FamilyPhotos.data(app, person.photoID) }
            CaregiverRow(onClick = { onPerson(person.id) }) {
                Avatar(person.name, photo, 40.dp)
                Column(Modifier.weight(1f)) {
                    Text(person.name, style = MaterialTheme.typography.titleMedium, color = ink)
                    Text(person.dropInModes.orEmpty(), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        phones.forEachIndexed { index, approval ->
            if (can.isNotEmpty() || index > 0) HorizontalDivider()
            val number = displayNumber(approval.number)
            val name = approval.name.ifBlank { number }
            CaregiverRow {
                GlyphBadge("☎︎", empty = false)
                Column(Modifier.weight(1f)) {
                    Text(name, style = MaterialTheme.typography.titleMedium, color = ink)
                    Text(if (name == number) "By phone" else "$number · By phone", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TextButton(onClick = { admin.perform("setPhoneDropIn", mapOf("number" to JsonPrimitive(approval.number), "enabled" to JsonPrimitive(false))) },
                    enabled = !admin.busy, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.semantics { contentDescription = "Remove phone drop-in for $name" }) { Text("Remove") }
            }
        }
        if (can.isEmpty() && phones.isEmpty()) CaregiverRow { Text("No one yet.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        HorizontalDivider()
        ActionRow("Add a phone number", onClick = onAddPhone)
    }

    val cannot = people.filter { !it.permissions.audio && !it.permissions.video }
    if (cannot.isNotEmpty()) CaregiverGroup("Can't drop in") {
        cannot.forEachIndexed { index, person ->
            if (index > 0) HorizontalDivider()
            val photo = remember(person.photoID, FamilyPhotos.saved) { FamilyPhotos.data(app, person.photoID) }
            CaregiverRow(onClick = { onPerson(person.id) }) {
                Avatar(person.name, photo, 40.dp)
                Text(person.name, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                Text("Off", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Approves one phone number for audio drop-in when it calls the household's Porch number, as iOS's
 * PhoneDropInViewController does. */
@Composable
private fun AddPhoneDropInScreen(admin: CaregiverAdmin, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mediaAccess = rememberMediaAccess()
    val region = remember { homeRegion() }
    var name by rememberSaveable { mutableStateOf("") }
    var phone by rememberSaveable { mutableStateOf("") }
    val pickContact = rememberLauncherForActivityResult(PickPhoneNumber()) { uri ->
        if (uri != null) scope.launch {
            val picked = pickedNumber(context, uri) ?: run { admin.error = "That contact's number couldn't be read. Type it instead."; return@launch }
            picked.first?.let { name = it }
            try { phone = PhoneNumberNormalization.e164(picked.second, region) } catch (e: ValidationException) { admin.error = e.message }
        }
    }
    FormScreen("Add a phone number", navigation = { TextButton(onClick = onDone) { Text("Cancel") } }) {
        FormSection("Who can drop in by phone?") {
            FormField(name, { name = it }, "Their name", "For example, David", keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
            Column {
                FormField(phone, { phone = it }, "Their phone number", "+14158676937", keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone))
                Text("Start international numbers with +.", Modifier.padding(top = 4.dp), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            FormButton("Choose from Contacts", filled = false, onClick = {
                // Android's picker hands Porch the one number tapped, without access to the rest of the contacts.
                try { pickContact.launch(Unit) } catch (_: ActivityNotFoundException) { admin.error = "This tablet has no contacts app. Type the number instead." }
            })
            FormButton(if (admin.busy) "Saving…" else "Approve audio drop-in", enabled = !admin.busy, onClick = {
                val trimmed = name.trim()
                // The server refuses a blank or oversized name. Ask for the microphone only once this can be saved.
                if (trimmed.isEmpty() || trimmed.length > 80) { admin.error = "Enter a name with 1–80 characters."; return@FormButton }
                val number = try { PhoneNumberNormalization.e164(phone, region) } catch (e: ValidationException) { admin.error = e.message; return@FormButton }
                // A drop-in answers on this tablet, so only it can grant its own microphone.
                mediaAccess(false) { allowed ->
                    if (!allowed) admin.error = "Allow the microphone in the tablet's settings before approving drop-in."
                    else admin.perform("setPhoneDropIn", mapOf("number" to JsonPrimitive(number), "name" to JsonPrimitive(trimmed),
                        "enabled" to JsonPrimitive(true))) { saved -> if (saved) onDone() }
                }
            })
        }
    }
}

/** Whether this tablet may use its microphone, and its camera too with `video`. */
private fun mediaGranted(context: Context, video: Boolean): Boolean =
    listOfNotNull(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA.takeIf { video })
        .all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
