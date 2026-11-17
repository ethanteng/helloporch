package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.pm.PackageManager
import android.icu.text.DateFormat as IcuDateFormat
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ethanteng.helloporch.core.EveryCallDropIn
import com.ethanteng.helloporch.core.FamilyAdminState
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PhoneNumberNormalization
import com.ethanteng.helloporch.core.RemoteCaregiverSession
import com.ethanteng.helloporch.core.ValidationException
import java.util.Date
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

private enum class DropInScreen { PERSON, ADD_PHONE, EVERY_CALL }

/** Who can drop in: the Drop-in page's three answers, and what `setDropInMode` calls each. `summary` is the caregiver
 * list's word for it. */
enum class DropInMode(val server: String, val summary: String) {
    OFF("off", "Off"), APPROVED("approved", "On"), EVERY_CALL("everyCall", "Every call");

    companion object {
        fun of(state: FamilyAdminState): DropInMode = when {
            !state.dropInEnabled -> OFF
            state.everyCall != null -> EVERY_CALL
            else -> APPROVED
        }
    }
}

/** Every call's red, as iOS's: a faint tint behind its row, card and banner, the darker red of its words there, and the
 * card's edge. */
internal object EveryCallColors {
    val tint = Color(0xFFFBE3DD)
    val ink = Color(0xFF8E2A22)
    val meta = Color(0xFF6B3A2E)
    val edge = Color(0xFFE7A89B)
}

/** Who turned every call on and when, such as "Tom, 3:12 PM", or "Rose’s tablet, Yesterday, 9:05 AM". */
internal fun everyCallSince(everyCall: EveryCallDropIn, bedside: String): String {
    val millis = everyCall.at * 1000
    val time = if (DateUtils.isToday(millis)) IcuDateFormat.getTimeInstance(IcuDateFormat.SHORT).format(Date(millis))
        else IcuDateFormat.getDateTimeInstance(IcuDateFormat.RELATIVE_SHORT, IcuDateFormat.SHORT).format(Date(millis))
    return "${everyCall.turnedOnBy(bedside)}, $time"
}

/** The Drop-in page, or a person's drop-in, a new phone number or Every call's PIN opened from it in its place. */
@Composable
fun DropInPages(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onBack: (() -> Unit)?) {
    var screen by rememberSaveable { mutableStateOf<DropInScreen?>(null) }
    var memberID by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(screen) { if (screen != null) admin.refresh() }
    when (screen) {
        null -> FormScreen(CaregiverPage.DROP_IN.title(admin.onBedside), navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }) {
            DropInPage(app, admin, links, onPerson = { memberID = it; screen = DropInScreen.PERSON }, onAddPhone = { screen = DropInScreen.ADD_PHONE },
                onEveryCall = { screen = DropInScreen.EVERY_CALL })
        }
        // Their drop-in, titled with their name, rather than their whole page.
        DropInScreen.PERSON -> PersonDropInScreen(app, admin, links, memberID, null, title = null, onBack = { screen = null })
        DropInScreen.ADD_PHONE -> AddPhoneDropInScreen(admin, onDone = { screen = null })
        DropInScreen.EVERY_CALL -> EveryCallScreen(admin, links, onDone = { screen = null })
    }
}

/**
 * Who can drop in, as iOS's DropInSettingsViewController shows it: No one, People you approve or Every call, then family
 * members and phone numbers that can, and family members who can't. No one and People you approve apply at once; Every
 * call warns, then asks for the PIN on a page of its own. A drop-in answers on the bedside, so it needs the tablet's
 * microphone, and for video its camera. Only the tablet can grant those, so a family phone doesn't ask.
 */
@Composable
private fun DropInPage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onPerson: (String) -> Unit, onAddPhone: () -> Unit,
    onEveryCall: () -> Unit) {
    val context = LocalContext.current
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val state = admin.state(links)
    val mode = state?.let(DropInMode::of)
    val enabled = state?.dropInEnabled == true
    val everyCall = state?.everyCall
    val people = state?.people.orEmpty()
    // Every call can drop in with video from anyone.
    val video = everyCall != null || people.any { it.permissions.video }
    // Read again when Porch comes back, such as from the tablet's settings.
    var checks by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { checks++ }
    val granted = remember(video, checks) { mediaGranted(context, video) }
    val devices = if (video) "microphone and camera" else "microphone"
    var warning by remember { mutableStateOf(false) }
    val choose = { chosen: DropInMode -> admin.perform("setDropInMode", mapOf("mode" to JsonPrimitive(chosen.server))) }
    val ready = state != null && !admin.busy

    CaregiverGroup("Who can drop in?") {
        Column(Modifier.selectableGroup()) {
            ModeRow("No one", "Paused", mode == DropInMode.OFF, ready) { if (mode != DropInMode.OFF) choose(DropInMode.OFF) }
            HorizontalDivider()
            ModeRow("People you approve", "Listed below", mode == DropInMode.APPROVED, ready) {
                when (mode) {
                    DropInMode.APPROVED -> {}
                    // Turning drop-ins back on asks for what they need, as the switch this replaced did.
                    DropInMode.OFF -> mediaAccess(people.any { it.permissions.video }) { allowed ->
                        checks++
                        if (allowed) choose(DropInMode.APPROVED)
                        else admin.error = "Allow the ${if (people.any { it.permissions.video }) "microphone and camera" else "microphone"} for Porch in the tablet's settings before turning on drop-ins."
                    }
                    else -> choose(DropInMode.APPROVED)
                }
            }
            HorizontalDivider()
            ModeRow("Every call", everyCall?.let { "On · ${everyCallSince(it, bedsideDevice(admin.snapshot(links)))}" }, everyCall != null, ready,
                danger = true, locked = everyCall == null) { if (everyCall == null) warning = true }
        }
        if (enabled && !granted && admin.onBedside) {
            HorizontalDivider()
            CaregiverRow { Text("Allow the $devices for Porch in the tablet's settings, or drop-ins can't connect.", color = MaterialTheme.colorScheme.error) }
        }
    }

    // Paused, or every call dropping in, leaves approvals as they are for later.
    val ink = if (enabled && everyCall == null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant
    val can = people.filter { it.permissions.audio || it.permissions.video }
    val phones = state?.phoneDropIns.orEmpty()
    CaregiverGroup(if (everyCall != null) "Saved approvals" else "Can drop in") {
        can.forEachIndexed { index, person ->
            if (index > 0) HorizontalDivider()
            val photo = memberPhoto(app, admin, person)
            CaregiverRow(onClick = { onPerson(person.id) }, label = "${person.name}, Porch app, ${person.dropInModes.orEmpty()}") {
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
            val photo = memberPhoto(app, admin, person)
            CaregiverRow(onClick = { onPerson(person.id) }, label = "${person.name}, can't drop in") {
                Avatar(person.name, photo, 40.dp)
                Text(person.name, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                Text("Off", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    if (warning) AlertDialog(onDismissRequest = { warning = false },
        icon = { Icon(painterResource(R.drawable.ic_warning), contentDescription = null, tint = PorchBrand.danger) },
        title = { Text("Let every call drop in?") },
        text = { Text(everyCallWarning(lovedOne(admin, links), state)) },
        confirmButton = { TextButton(onClick = { warning = false; onEveryCall() }) { Text("Continue", color = PorchBrand.danger) } },
        dismissButton = { TextButton(onClick = { warning = false }) { Text("Cancel") } })
}

/** Strangers can get through only while Block unknown callers is off, so only then does the warning say so. */
private fun unknownToo(state: FamilyAdminState?): Boolean = state?.callScreening?.enabled != true

private fun everyCallWarning(lovedOne: String, state: FamilyAdminState?): String =
    "Anyone who calls will connect without $lovedOne answering" + if (unknownToo(state)) ", unknown numbers too." else "."

/** One of the three answers: a radio button, its name and what it means. Every call's turns red once it's chosen, and
 * says it needs the PIN until then. */
@Composable
private fun ModeRow(title: String, detail: String?, selected: Boolean, enabled: Boolean, danger: Boolean = false, locked: Boolean = false,
    onClick: () -> Unit) {
    val red = danger && selected
    var modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
    if (red) modifier = modifier.background(EveryCallColors.tint)
    Row(modifier.selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        RadioButton(selected, onClick = null, enabled = enabled,
            colors = if (danger) RadioButtonDefaults.colors(selectedColor = PorchBrand.danger) else RadioButtonDefaults.colors())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = if (red) EveryCallColors.ink else Color.Unspecified,
                fontWeight = if (red) FontWeight.Bold else null)
            val quiet = if (red) EveryCallColors.meta else MaterialTheme.colorScheme.onSurfaceVariant
            if (locked) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(painterResource(R.drawable.ic_lock), contentDescription = null, Modifier.size(14.dp), tint = quiet)
                Text("Needs the PIN", style = MaterialTheme.typography.bodyMedium, color = quiet)
            } else detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = quiet) }
        }
    }
}

/** Every call's warning in a line, on its faint red. */
@Composable
internal fun EveryCallCard(text: String) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), color = EveryCallColors.tint, border = BorderStroke(1.5.dp, EveryCallColors.edge)) {
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(painterResource(R.drawable.ic_warning), contentDescription = null, Modifier.size(24.dp), tint = PorchBrand.danger)
            Text(text, style = MaterialTheme.typography.bodyLarge, color = EveryCallColors.ink)
        }
    }
}

/**
 * Turning on Every call: the caregiver PIN typed again here, never the one caregiver mode keeps, as iOS's EveryCall page
 * asks. A wrong one says so without ending caregiver mode. On the tablet, the microphone and camera come first, since
 * anyone may now drop in with video.
 */
@Composable
private fun EveryCallScreen(admin: CaregiverAdmin, links: FamilyLinks, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val state = admin.state(links)
    // Not saved with the screen's state: the PIN stays in memory only.
    var pin by remember { mutableStateOf("") }
    FormScreen("Every call", navigation = { TextButton(onClick = onDone) { Text("Back") } }) {
        EveryCallCard(if (unknownToo(state)) "Every call will drop in, unknown numbers too." else "Every call will drop in.")
        FormField(pin, { pin = it.filter(Char::isDigit).take(6) }, "Caregiver PIN", "Six digits", Modifier.testTag("everyCall.pin"),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), visualTransformation = PasswordVisualTransformation())
        Button(onClick = {
            if (!Regex("^[0-9]{6}$").matches(pin)) { admin.error = "Enter six digits."; return@Button }
            val typed = pin
            mediaAccess(true) { allowed ->
                if (!allowed) admin.error = "Allow the microphone and camera for Porch in the tablet's settings first."
                else admin.perform("setDropInMode", mapOf("mode" to JsonPrimitive(DropInMode.EVERY_CALL.server)), pin = typed, typed = true) { saved ->
                    if (saved) { pin = ""; onDone() }
                }
            }
        }, Modifier.fillMaxWidth().heightIn(min = 50.dp), enabled = !admin.busy,
            shape = LocalFormButtonShape.current ?: ButtonDefaults.shape,
            colors = ButtonDefaults.buttonColors(containerColor = PorchBrand.danger, contentColor = Color.White)) {
            Text(if (admin.busy) "Turning on…" else "Turn on", style = MaterialTheme.typography.titleMedium)
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
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val region = remember { homeRegion() }
    var name by rememberSaveable { mutableStateOf("") }
    var phone by rememberSaveable { mutableStateOf("") }
    val pickContact = rememberLauncherForActivityResult(PickPhoneNumber()) { uri ->
        RemoteCaregiverSession.shared.answered()
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
                try { staysInCaregiverMode(answers = true) { pickContact.launch(Unit) } } catch (_: ActivityNotFoundException) { admin.error = "No contacts app is available. Type the number instead." }
            })
            FormButton(if (admin.busy) "Saving…" else "Approve audio drop-in", enabled = !admin.busy, onClick = {
                val trimmed = name.trim()
                // The server refuses a blank or oversized name. Ask for the microphone only once this can be saved.
                if (trimmed.isEmpty() || trimmed.length > 80) { admin.error = "Enter a name with 1–80 characters."; return@FormButton }
                val number = try { PhoneNumberNormalization.e164(phone, region) } catch (e: ValidationException) { admin.error = e.message; return@FormButton }
                // A drop-in answers on the bedside, so only the tablet can grant its own microphone.
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
