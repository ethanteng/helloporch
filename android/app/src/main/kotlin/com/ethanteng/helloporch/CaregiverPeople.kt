package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.icu.text.DateFormat as IcuDateFormat
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.AddSomeoneDraft
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyAdminState
import com.ethanteng.helloporch.core.FamilyInvitation
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PhoneNumberNormalization
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.RemoteCaregiverSession
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Where the People page is: its list, or a person, Add someone or an invitation opened from it. Kept across a rotation. */
data class PeopleRoute(val kind: Kind, val memberID: String? = null, val slot: Int? = null, val start: AddSomeoneStart = AddSomeoneStart.PEOPLE) :
    java.io.Serializable {
    enum class Kind { PERSON, ADD, INVITE }
}

/**
 * The People page, as iOS's PeopleSettingsViewController shows it on the bedside: the keypad as it's laid out, and
 * everyone on Porch with the invitations still waiting. A person, Add someone or a new invitation opens in the page's
 * place.
 */
@Composable
fun PeoplePages(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onBack: (() -> Unit)?) {
    var route by rememberSaveable { mutableStateOf<PeopleRoute?>(null) }
    LaunchedEffect(route) { if (route != null) admin.refresh() }
    val open = route
    val close = { route = null }
    when (open?.kind) {
        null -> FormScreen(CaregiverPage.PEOPLE.title(admin.onBedside), navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }) {
            PeopleList(app, admin, links, onOpen = { route = it })
        }
        PeopleRoute.Kind.PERSON -> PersonPage(app, admin, links, open.memberID, open.slot, onDone = close)
        PeopleRoute.Kind.ADD -> AddSomeone(app, admin, links, open.slot, open.start, onDone = close)
        PeopleRoute.Kind.INVITE -> InviteScreen(app, admin, prefilledName = null, returnsToPerson = false, onCreated = { _, _ -> }, onDone = close, fromKey = false)
    }
}

@Composable
private fun PeopleList(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onOpen: (PeopleRoute) -> Unit) {
    val state = admin.state(links)
    val slots = admin.slots
    // The keypad is set on the bedside. A family phone lists just the family, as iOS's does.
    if (!admin.onBedside) { FamilyGroup(app, admin, state, slots, onOpen); return }
    Text("Keypad", style = MaterialTheme.typography.titleLarge)
    if (admin.slotsUnreadable) {
        Text("The saved keypad couldn't be read. Set up each key again, and each one is saved as you go.", color = MaterialTheme.colorScheme.error)
    }
    // As the keypad is laid out: 1 2 3, 4 5 6, 7 8 9, * 0 #.
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        AddSomeoneDraft.keypadOrder.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { digit ->
                    KeyTile(app, digit, slots, state, Modifier.weight(1f).fillMaxHeight()) {
                        // A person opens their page, and an empty key adds someone to it. Any other key opens what it does.
                        onOpen(when (slots.action(digit) ?: KeypadAction.UNASSIGNED) {
                            KeypadAction.PERSON -> PeopleRoute(PeopleRoute.Kind.PERSON, slot = digit)
                            KeypadAction.UNASSIGNED -> PeopleRoute(PeopleRoute.Kind.ADD, slot = digit, start = AddSomeoneStart.KEY_TILE)
                            else -> PeopleRoute(PeopleRoute.Kind.ADD, slot = digit, start = AddSomeoneStart.CONTROL)
                        })
                    }
                }
            }
        }
    }
    FamilyGroup(app, admin, state, slots, onOpen)
}

/** One key: who it calls, or what it does. */
@Composable
private fun KeyTile(app: PorchApplication, digit: Int, slots: CallSlots, state: FamilyAdminState?, modifier: Modifier, onClick: () -> Unit) {
    val key = CallSlots.symbol(digit)
    val action = slots.action(digit) ?: KeypadAction.UNASSIGNED
    val contact = slots.contact(digit)
    val (title, detail, glyph) = when (action) {
        KeypadAction.PERSON -> Triple(contact?.name.orEmpty(), contact?.let { keyDetail(it, state) }, null)
        KeypadAction.UNASSIGNED -> Triple("Add", null, "+")
        KeypadAction.CALL_CONTROL -> Triple("Answer / hang up", "Hold to decline", "☎︎")
        KeypadAction.TOGGLE_VIDEO -> Triple("Video on / off", null, "▶︎")
        KeypadAction.MESSAGES -> Triple("Messages", null, "✉︎")
    }
    val empty = action == KeypadAction.UNASSIGNED
    val colors = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(16.dp)
    val photo = remember(contact, FamilyPhotos.saved) { contact?.photoData }
    Box(modifier.heightIn(min = 150.dp).clip(shape)
        .then(if (empty) Modifier.border(1.5.dp, colors.outlineVariant, shape) else Modifier.background(colors.surfaceContainerHigh))
        .clickable(role = Role.Button, onClick = onClick)
        .semantics { contentDescription = "Key $key, ${contact?.name ?: action.title}"; detail?.let { stateDescription = it } }) {
        Box(Modifier.fillMaxWidth().clearAndSetSemantics {}.padding(start = 12.dp, top = 10.dp, end = 8.dp, bottom = 12.dp)) {
            Text(key, color = colors.primary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            Column(Modifier.fillMaxWidth().padding(top = 22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (glyph != null) GlyphBadge(glyph, empty) else Avatar(contact?.name ?: key, photo, 48.dp)
                Text(title, color = if (empty) colors.onSurfaceVariant else colors.onSurface, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center,
                    maxLines = 2)
                detail?.let { Text(it, fontSize = 13.sp, color = colors.onSurfaceVariant, textAlign = TextAlign.Center, maxLines = 2) }
            }
        }
    }
}

/** A key's symbol in a circle: filled for what the key does, outlined for an empty key. */
@Composable
internal fun GlyphBadge(glyph: String, empty: Boolean) {
    val colors = MaterialTheme.colorScheme
    Box(Modifier.size(48.dp).clip(CircleShape).then(if (empty) Modifier.border(1.5.dp, colors.outlineVariant, CircleShape) else Modifier.background(colors.primaryContainer)),
        contentAlignment = Alignment.Center) {
        Text(glyph, fontSize = 22.sp, color = if (empty) colors.onSurfaceVariant else colors.onPrimaryContainer)
    }
}

/** How the bedside reaches the person on a key. */
private fun keyDetail(contact: CallContact, state: FamilyAdminState?): String {
    val mode = if (contact.nativeCall.mode == NativeCall.Mode.VIDEO) "Video" else "Voice"
    if (contact.familyMemberID != null && state?.people?.any { it.id == contact.familyMemberID } != false) return "Porch app · $mode"
    if (contact.invitationID != null && state?.invitations?.any { it.id == contact.invitationID } == true) return "Invite sent"
    return if (contact.phoneNumber == null) "Finish setup" else "Phone"
}

/** Everyone with access and everyone invited, so a waiting invitation sits beside the people it will join. */
@Composable
private fun FamilyGroup(app: PorchApplication, admin: CaregiverAdmin, state: FamilyAdminState?, slots: CallSlots, onOpen: (PeopleRoute) -> Unit) {
    val people = state?.people.orEmpty()
    val invitations = state?.invitations.orEmpty()
    // Invitations last a day, so the expiry needs its day ("tomorrow, 3:14 PM").
    val expiry = remember { IcuDateFormat.getDateTimeInstance(IcuDateFormat.RELATIVE_SHORT, IcuDateFormat.SHORT) }
    CaregiverGroup(if (admin.onBedside) "Family on Porch" else null) {
        people.forEachIndexed { index, person ->
            if (index > 0) HorizontalDivider()
            val access = person.access ?: "Calls only"
            val key = keyFor(slots, person)?.let(CallSlots::symbol)
            val photo = memberPhoto(app, admin, person)
            CaregiverRow(onClick = { onOpen(PeopleRoute(PeopleRoute.Kind.PERSON, memberID = person.id)) }) {
                Avatar(person.name, photo)
                Column(Modifier.weight(1f)) {
                    Text(if (person.id == admin.myID) "${person.name} (this phone)" else person.name, style = MaterialTheme.typography.titleMedium)
                    Text("${person.shortStatus} · $access", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                key?.let { Text("Key $it", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        invitations.forEachIndexed { index, invitation ->
            if (people.isNotEmpty() || index > 0) HorizontalDivider()
            val name = invitation.name?.takeIf { it.isNotBlank() } ?: "Invitation"
            CaregiverRow {
                GlyphBadge("◔︎", empty = true)
                Column(Modifier.weight(1f)) {
                    Text(name, style = MaterialTheme.typography.titleMedium)
                    Text("Invited · expires ${expiry.format(Date(invitation.expiresAt * 1000))}", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TextButton(onClick = { admin.perform("cancelInvite", mapOf("inviteID" to JsonPrimitive(invitation.id))) }, enabled = !admin.busy,
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.semantics { contentDescription = "Cancel invitation for $name" }) { Text("Cancel") }
            }
        }
        if (people.isNotEmpty() || invitations.isNotEmpty()) HorizontalDivider()
        // The bedside adds someone a step at a time, on the first empty key. A family phone, which has no keypad, invites.
        if (admin.onBedside) ActionRow("Add someone") { onOpen(PeopleRoute(PeopleRoute.Kind.ADD, slot = AddSomeoneDraft.firstFreeKey(slots))) }
        else ActionRow("Invite someone") { onOpen(PeopleRoute(PeopleRoute.Kind.INVITE)) }
    }
}

// MARK: One person

/** Who the page is about, found again on every change: a key can move, and a key's person can join Porch. */
private data class Subject(val member: FamilyPerson?, val slot: Int?, val contact: CallContact?) {
    val name: String get() = member?.name ?: contact?.name.orEmpty()
    val firstName: String get() = name.split(" ").firstOrNull { it.isNotEmpty() } ?: name
}

private fun resolve(state: FamilyAdminState?, slots: CallSlots, memberID: String?, slot: Int?): Subject {
    val people = state?.people.orEmpty()
    var member = memberID?.let { id -> people.firstOrNull { it.id == id } }
    var key = slot?.takeIf { slots.contact(it) != null }
    if (member != null && key?.let(slots::contact)?.let { isFor(it, member) } != true) key = keyFor(slots, member)
    val contact = key?.let(slots::contact)
    if (member == null && contact != null) member = people.firstOrNull { isFor(contact, it) }
    return Subject(member, key, contact)
}

private enum class Removing { KEYPAD, PORCH, EITHER }
private enum class PersonScreen { PHONE, INVITE }

/**
 * One person, as iOS's PersonViewController shows them: their name and photo, their key, how the bedside reaches them,
 * drop-in, caregiver mode, and removing them. A Porch family member has one name and photo, kept with their Porch
 * profile, which their key and calls show. Someone on the keypad only by phone keeps the name and photo saved with their
 * key.
 */
@Composable
internal fun PersonPage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, initialMemberID: String?, initialSlot: Int?, onDone: () -> Unit) {
    var memberID by rememberSaveable { mutableStateOf(initialMemberID) }
    var slot by rememberSaveable { mutableStateOf(initialSlot) }
    var screen by rememberSaveable { mutableStateOf<PersonScreen?>(null) }
    var editedName by rememberSaveable { mutableStateOf<String?>(null) }
    var removing by remember { mutableStateOf<Removing?>(null) }
    var choosingColor by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val state = admin.state(links)
    val slots = admin.slots
    val subject = resolve(state, slots, memberID, slot)
    /** The person as of now, for a change that finishes after the page last drew. */
    fun latest() = resolve(admin.state(app.coordinator.links.value), admin.slots, memberID, slot)

    LaunchedEffect(subject.member?.id, subject.slot) { memberID = subject.member?.id; slot = subject.slot }
    // Removed here or by another caregiver.
    val gone = subject.member == null && subject.contact == null
    LaunchedEffect(gone) { if (gone) onDone() }
    if (gone) return

    BackHandler(enabled = screen == null, onBack = onDone)
    val contact = subject.contact
    val key = subject.slot
    when (screen) {
        PersonScreen.PHONE -> if (key != null && contact != null) {
            KeyEditor(app, admin, links, key, contact, KeypadAction.PERSON, onDone = { screen = null })
            return
        }
        PersonScreen.INVITE -> if (key != null && contact != null) {
            InviteScreen(app, admin, prefilledName = contact.name, returnsToPerson = false, onDone = { screen = null }, onCreated = { id, invitedName ->
                // The name moves to the invitation, and the key follows the name they choose once they join.
                val current = latest()
                val at = current.slot
                val keyed = current.contact
                if (at != null && keyed != null) admin.saveSlots { it.setContact(linked(keyed, invitationID = id, name = invitedName.ifEmpty { keyed.name }), at) }
            })
            return
        }
        null -> {}
    }

    fun clearKeyPhoto() {
        val current = latest()
        val at = current.slot ?: return
        val keyed = current.contact?.takeIf { it.customPhotoData != null } ?: return
        admin.saveSlots { it.setContact(keyed.updatingPhoto(null), at) }
    }
    fun photoChosen(data: ByteArray?) {
        if (data == null) { admin.error = "That photo couldn't be opened. Please choose another photo."; return }
        val current = latest()
        val member = current.member
        val at = current.slot
        val keyed = current.contact
        if (member != null) {
            // One photo per person: the key shows the one saved with their Porch profile.
            admin.launch { if (chooseOverridePhoto(data, member.id)) clearKeyPhoto() }
        } else if (at != null && keyed != null) admin.saveSlots { it.setContact(keyed.updatingPhoto(data), at) }
    }
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        RemoteCaregiverSession.shared.answered()
        if (uri != null) scope.launch { photoChosen(FamilyPhotos.prepared(context, uri)) }
    }
    suspend fun removeFromKeypad() {
        val current = latest()
        val at = current.slot ?: return
        val keyed = current.contact ?: return
        // Their phone drop-in goes with their key.
        val number = keyed.phoneNumber
        if (number != null && app.coordinator.links.value.state?.phoneDropIns.orEmpty().any { it.number == number }) {
            if (!admin.send("setPhoneDropIn", mapOf("number" to JsonPrimitive(number), "enabled" to JsonPrimitive(false)))) return
        }
        admin.saveSlots { it.setContact(null, at) }
    }

    FormScreen(subject.name, navigation = { TextButton(onClick = onDone) { Text("Back") } }) {
        // Name and photo.
        val member = subject.member
        val memberPhoto = member?.let { memberPhoto(app, admin, it) }
        val photo = remember(contact, memberPhoto) { contact?.customPhotoData ?: memberPhoto ?: contact?.photoData }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Avatar(subject.name, photo, 96.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = {
                    try { staysInCaregiverMode(answers = true) { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) } }
                    catch (_: ActivityNotFoundException) { admin.error = "No app on this device can choose a photo." }
                }, enabled = !admin.busy) {
                    Text(if (photo == null) "Add photo" else "Change photo")
                }
                // Back to their own photo, or no photo: a caregiver's choice for a family member, or a key's own photo.
                val keyPhoto = contact?.customPhotoData != null
                val chosen = member?.override?.photoID != null
                if (chosen || keyPhoto) {
                    OutlinedButton(onClick = {
                        if (member != null && chosen) {
                            admin.launch { if (send("setMemberOverride", mapOf("memberID" to JsonPrimitive(member.id), "photo" to JsonNull))) clearKeyPhoto() }
                        } else clearKeyPhoto()
                    }, enabled = !admin.busy) { Text(if (member?.profile?.photoID != null) "Use their own photo" else "Remove photo") }
                }
            }
            val pending = invitePending(subject, state)
            Text(member?.shortStatus ?: if (pending) "Invite sent" else "Not on Porch", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val saved = if (member != null) member.override?.name ?: contact?.customName?.ifEmpty { null } else contact?.customName
        val placeholder = member?.let { it.profile?.name ?: it.invitedName ?: it.name } ?: "Their name"
        CaregiverGroup {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // No floating label, so the name they go by shows in the empty field, as iOS's placeholder does.
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Name", style = MaterialTheme.typography.titleMedium)
                    PorchTextField(editedName ?: saved.orEmpty(), { editedName = it }, "Name", Modifier.fillMaxWidth(), enabled = !admin.busy,
                        placeholder = { Text(placeholder) }, keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
                }
                OutlinedButton(onClick = {
                    val typed = (editedName ?: saved.orEmpty()).trim()
                    val current = latest()
                    val who = current.member
                    if (who != null) {
                        admin.launch {
                            if (!send("setMemberOverride", mapOf("memberID" to JsonPrimitive(who.id), "name" to JsonPrimitive(typed)))) return@launch
                            editedName = null
                            // One name per person: the key goes by the one saved with their Porch profile.
                            val now = latest()
                            val at = now.slot
                            val keyed = now.contact
                            if (at != null && keyed != null && keyed.customName.isNotEmpty()) saveSlots { it.setContact(keyed.updating(name = ""), at) }
                        }
                    } else {
                        val at = current.slot
                        val keyed = current.contact
                        if (at != null && keyed != null && admin.saveSlots { it.setContact(keyed.updating(name = typed), at) }) editedName = null
                    }
                }, enabled = !admin.busy, modifier = Modifier.semantics { contentDescription = "Save name" }) { Text("Save") }
            }
        }

        // The keypad, which only the bedside has.
        if (admin.onBedside) CaregiverGroup {
            CaregiverRow {
                Text("Keypad key", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                Box {
                    var open by remember { mutableStateOf(false) }
                    val choices = CallSlots.digits.filter { it == key || slots.action(it) == KeypadAction.UNASSIGNED }
                    OutlinedButton(onClick = { open = true }, enabled = choices.isNotEmpty()) {
                        Text(when { key != null -> "Key ${CallSlots.symbol(key)}"; choices.isEmpty() -> "Keypad is full"; else -> "Add to keypad" })
                    }
                    DropdownMenu(open, onDismissRequest = { open = false }) {
                        choices.forEach { digit ->
                            DropdownMenuItem(text = { Text("Key ${CallSlots.symbol(digit)}") }, onClick = {
                                open = false
                                // Moves their key, or gives a family member who isn't on the keypad one.
                                val current = latest()
                                val from = current.slot
                                val keyed = current.contact
                                val who = current.member
                                if (from != null && keyed != null) {
                                    if (from != digit && admin.saveSlots { it.setContact(null, from); it.setContact(keyed, digit) }) slot = digit
                                } else if (who != null) {
                                    val made = CallContact(name = "", nativeCall = NativeCall(newRoom(), NativeCall.Mode.VOICE), familyMemberID = who.id,
                                        invitationID = who.invitationID, memberName = who.name)
                                    if (admin.saveSlots { it.setContact(made, digit) }) slot = digit
                                }
                            }, trailingIcon = if (digit == key) ({ Text("✓") }) else null)
                        }
                        if (key != null) {
                            HorizontalDivider()
                            DropdownMenuItem(text = { Text("Take off the keypad", color = MaterialTheme.colorScheme.error) },
                                onClick = { open = false; removing = Removing.KEYPAD })
                        }
                    }
                }
            }
            if (contact != null) {
                HorizontalDivider()
                CaregiverRow(onClick = { choosingColor = true }) {
                    Text("Button color", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    ColorSwatch(contact.buttonColorHex, Modifier.size(36.dp))
                }
            }
        }

        // How the bedside reaches them.
        if (key != null && contact != null) ReachGroup(app, admin, state, slots, subject, key, contact,
            onInvite = { screen = PersonScreen.INVITE }, onPhone = { screen = PersonScreen.PHONE }, onLinked = { editedName = null })

        DropInGroup(app, admin, state, subject, mediaAccess)

        member?.let { person ->
            // A caregiver's phone can't take its own access away: another caregiver can.
            val isMe = person.id == admin.myID
            CaregiverGroup {
                ToggleRow("Caregiver mode", person.caregiver == true, enabled = !admin.busy && !isMe,
                    detail = if (isMe) "Another caregiver can change this." else "Can change settings from their phone with the PIN.",
                    onChange = { admin.perform("setCaregiver", mapOf("memberID" to JsonPrimitive(person.id), "enabled" to JsonPrimitive(it))) })
            }
        }

        // This phone can't remove itself. The server refuses that, and the refusal would end caregiver mode. Another
        // caregiver removes it; leaving the family is on this phone's own card. The bedside isn't one of these people.
        if (member?.id != admin.myID || admin.myID == null) {
            OutlinedButton(onClick = { removing = if (member == null) Removing.KEYPAD else if (key == null) Removing.PORCH else Removing.EITHER },
                Modifier.fillMaxWidth().heightIn(min = 50.dp), enabled = !admin.busy,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Remove ${subject.firstName}") }
        }
    }

    if (choosingColor && contact != null) ButtonColorDialog(contact.buttonColorHex, onDismiss = { choosingColor = false }, onChoose = { hex ->
        choosingColor = false
        val current = latest()
        val at = current.slot
        val keyed = current.contact
        if (at != null && keyed != null) admin.saveSlots { it.setContact(keyed.updating(buttonColorHex = hex), at) }
    })

    val leaving = "Their device will need a new invitation to call this Porch again."
    val member = subject.member
    fun removeFromPorch(person: FamilyPerson) {
        val onKeypad = latest().slot != null
        admin.launch { if (send("revoke", mapOf("memberID" to JsonPrimitive(person.id))) && onKeypad) removeFromKeypad() }
    }
    when (removing) {
        Removing.KEYPAD -> AlertDialog(onDismissRequest = { removing = null },
            title = { Text("Take ${subject.name} off the keypad?") },
            text = { Text(key?.let { "Key ${CallSlots.symbol(it)} will be empty." } ?: "") },
            confirmButton = { TextButton(onClick = { removing = null; admin.launch { removeFromKeypad() } }) { Text("Remove") } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } })
        Removing.PORCH -> if (member != null) AlertDialog(onDismissRequest = { removing = null },
            title = { Text("Remove ${member.name} from Porch?") },
            text = { Text(leaving) },
            confirmButton = { TextButton(onClick = { removing = null; removeFromPorch(member) }) { Text("Remove") } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } })
        Removing.EITHER -> if (member != null) AlertDialog(onDismissRequest = { removing = null },
            title = { Text("Remove ${member.name}?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Remove from Porch also empties their key. $leaving")
                    TextButton(onClick = { removing = null; admin.launch { removeFromKeypad() } }, Modifier.fillMaxWidth()) { Text("Take off the keypad") }
                    TextButton(onClick = { removing = null; removeFromPorch(member) }, Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Remove from Porch") }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } })
        null -> {}
    }
}

private fun invitePending(subject: Subject, state: FamilyAdminState?): Boolean =
    subject.member == null && subject.contact?.invitationID?.let { id -> state?.invitations?.any { it.id == id } == true } == true

/** Whether the bedside reaches them on Porch, and the phone numbers it has for them. */
@Composable
private fun ReachGroup(app: PorchApplication, admin: CaregiverAdmin, state: FamilyAdminState?, slots: CallSlots, subject: Subject, key: Int, contact: CallContact,
    onInvite: () -> Unit, onPhone: () -> Unit, onLinked: () -> Unit) {
    val pending = invitePending(subject, state)
    val porch = when {
        subject.member != null -> "Connected"
        pending -> "Invite sent"
        contact.invitationID != null -> "Invite expired"
        else -> "Not on Porch"
    }
    val linked = subject.member != null || contact.invitationID != null
    val fallback = if (linked && contact.phoneNumber != null)
        "If Porch isn't answered in ${CallPreferences.fallbackSeconds(app.settings)} seconds, Porch calls their phone. Voice only." else null
    CaregiverGroup("Reach ${subject.firstName}", fallback) {
        CaregiverRow {
            Text("Porch app", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            Text(porch, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (subject.member == null && !pending) {
            HorizontalDivider()
            ActionRow("Invite ${subject.firstName}", onClick = onInvite)
            // Or they joined Porch some other way, such as an invitation from People.
            val unlinked = state?.people.orEmpty().filter { keyFor(slots, it) == null }
            if (unlinked.isNotEmpty()) {
                HorizontalDivider()
                Box {
                    var open by remember { mutableStateOf(false) }
                    ActionRow("Choose from Family on Porch") { open = true }
                    DropdownMenu(open, onDismissRequest = { open = false }) {
                        unlinked.forEach { person ->
                            DropdownMenuItem(text = { Text(person.name) }, onClick = {
                                open = false
                                // A name typed for the phone key must not be saved over this person's Porch name.
                                onLinked()
                                admin.saveSlots { it.setContact(linked(contact, memberID = person.id, invitationID = person.invitationID, name = person.name), key) }
                            })
                        }
                    }
                }
            }
        }
        if (linked) {
            HorizontalDivider()
            CaregiverRow {
                Text("Calls start as", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                Choices(listOf("Voice", "Video"), if (contact.nativeCall.mode == NativeCall.Mode.VIDEO) 1 else 0, Modifier.width(220.dp)) { choice ->
                    admin.saveSlots { it.setContact(contact.updating(mode = if (choice == 1) NativeCall.Mode.VIDEO else NativeCall.Mode.VOICE), key) }
                }
            }
        }
        HorizontalDivider()
        val others = contact.otherPhoneNumbers.size
        val number = contact.phoneNumber?.let { displayNumber(it) + if (others > 0) " +$others" else "" }
        CaregiverRow(onClick = onPhone) {
            Text("Phone", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            Text(number ?: "Add", color = MaterialTheme.colorScheme.primary)
            Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Drop-in in their Porch app and by phone, approved apart, each on its own card. */
@Composable
private fun DropInGroup(app: PorchApplication, admin: CaregiverAdmin, state: FamilyAdminState?, subject: Subject, mediaAccess: MediaAccess) {
    val person = subject.member
    // Approvals live on the server, so a bedside that isn't paired yet can't offer them. A key's number is the bedside's.
    val number = subject.contact?.phoneNumber?.takeIf { admin.onBedside && app.device.credential(PorchExperience.BEDSIDE) != null }
    if (person == null && number == null) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Drop-in", style = MaterialTheme.typography.titleLarge)
        Text(if (state?.dropInEnabled == false) "Drop-ins are paused for everyone." else "Drop-ins connect without anyone answering.",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (person != null) {
            fun change(audio: Boolean, video: Boolean) {
                val send = { admin.perform("setPermissions", mapOf("memberID" to JsonPrimitive(person.id),
                    "permissions" to JsonObject(mapOf("audio" to JsonPrimitive(audio), "video" to JsonPrimitive(video))))) }
                // Drop-in answers on the bedside, so only the tablet can grant its own microphone and camera.
                if (audio || video) mediaAccess(video) { granted ->
                    if (granted) send() else admin.error = "Allow the microphone and camera in the tablet's settings before approving drop-in."
                } else send()
            }
            Text("In ${person.firstName}'s Porch app", Modifier.padding(top = 8.dp), style = MaterialTheme.typography.titleSmall)
            CaregiverGroup {
                ToggleRow("Audio drop-in", person.permissions.audio, enabled = !admin.busy, onChange = { change(it, person.permissions.video) })
                HorizontalDivider()
                ToggleRow("Video drop-in", person.permissions.video, enabled = !admin.busy, onChange = { change(person.permissions.audio, it) })
            }
        }
        if (number != null) {
            val approved = state?.phoneDropIns.orEmpty().any { it.number == number }
            Text("By phone", Modifier.padding(top = 8.dp), style = MaterialTheme.typography.titleSmall)
            CaregiverGroup {
                ToggleRow("Calls from ${displayNumber(number)} drop in", approved, detail = "Audio only.", enabled = !admin.busy, onChange = { on ->
                    if (!on) admin.perform("setPhoneDropIn", mapOf("number" to JsonPrimitive(number), "enabled" to JsonPrimitive(false)))
                    else mediaAccess(false) { granted ->
                        if (!granted) admin.error = "Allow the microphone in the tablet's settings before approving drop-in."
                        else admin.perform("setPhoneDropIn", mapOf("number" to JsonPrimitive(number), "name" to JsonPrimitive(subject.contact.name),
                            "enabled" to JsonPrimitive(true)))
                    }
                })
            }
        }
    }
}

// MARK: Inviting

/**
 * A new invitation, as iOS's FamilyInviteViewController makes it: who it's for, drop-in, and caregiver mode. Once it's
 * made, it shows its code for a phone's camera, and can send it. Made on a caregiver's phone, the drop-in it approves
 * still answers on the bedside, so the phone doesn't ask for its own microphone.
 */
@Composable
fun InviteScreen(app: PorchApplication, admin: CaregiverAdmin, prefilledName: String?, returnsToPerson: Boolean, onCreated: (id: String, name: String) -> Unit,
    onDone: () -> Unit, fromKey: Boolean = true) {
    BackHandler(onBack = onDone)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    var name by rememberSaveable { mutableStateOf(prefilledName.orEmpty()) }
    // Family can drop in unless the caregiver turns it off for them.
    var audio by rememberSaveable { mutableStateOf(true) }
    var video by rememberSaveable { mutableStateOf(true) }
    var caregiver by rememberSaveable { mutableStateOf(false) }
    var link by rememberSaveable { mutableStateOf<String?>(null) }
    var expiresAt by rememberSaveable { mutableLongStateOf(0L) }
    var busy by remember { mutableStateOf(false) }
    val made = link != null
    fun create() {
        val origin = admin.origin ?: return
        busy = true
        scope.launch {
            try {
                val values = mapOf("name" to JsonPrimitive(name), "caregiver" to JsonPrimitive(caregiver),
                    "permissions" to JsonObject(mapOf("audio" to JsonPrimitive(audio), "video" to JsonPrimitive(video))))
                val response = admin.request("createInvite", values)
                val code = response.code
                val id = response.invitationID
                if (code == null || id == null) throw IllegalStateException("Couldn't make the invitation. Try again.")
                onCreated(id, name.trim())
                link = FamilyInvitation.url(origin, code, app.device.defaultOrigin)
                expiresAt = response.expiresAt ?: 0
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                admin.error = e.message ?: "Couldn't reach Porch. Check the connection and try again."
            } finally {
                busy = false
            }
        }
    }
    FormScreen("Invite someone", navigation = { TextButton(onClick = onDone) { Text(if (made) "Done" else "Cancel") } }) {
        // An invitation from a key is already that key's. One from People finds its key by name once they join
        // (`CallSlots.followInvitations`).
        FormSection("Who is this invitation for?", if (fromKey) null else "Already on the keypad? Use the name on their key, and it calls their Porch app once they join.") {
            FormField(name, { name = it }, "Their name", "For example, Ethan", enabled = !made,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        }
        CaregiverGroup("Approve drop-in", "Lets them connect without anyone answering.") {
            ToggleRow("Audio drop-in", audio, { audio = it }, enabled = !made)
            HorizontalDivider()
            ToggleRow("Video drop-in", video, { video = it }, enabled = !made)
        }
        CaregiverGroup("Caregiver mode", "Can change settings from their phone with the PIN.") {
            ToggleRow("Caregiver mode", caregiver, { caregiver = it }, enabled = !made)
        }
        val shown = link?.takeIf { expiresAt > System.currentTimeMillis() / 1000 }
        if (shown != null) {
            InvitationCode(shown, "QR code for ${name.trim().ifEmpty { "their" }} invitation")
            Text(if (returnsToPerson) "Invitation ready. Show them this code or share it, tap Done, then tap Save."
                else "Invitation ready. Show them this code or share it, then tap Done.",
                Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyLarge)
        }
        FormButton(when { shown != null -> "Share invitation"; busy -> "Creating…"; else -> "Create invitation" }, enabled = !busy && (shown != null || !made), onClick = {
            if (shown != null) { shareInvitation(context, shown); return@FormButton }
            // Drop-in answers on the bedside, so only the tablet can grant its own microphone and camera.
            if (audio || video) mediaAccess(video) { granted ->
                if (granted) create() else admin.error = "Grant microphone and camera access before approving drop-in."
            } else create()
        })
    }
}

/** The share sheet, with a note and the link, as iOS's `shareItems` sends it. */
fun shareInvitation(context: Context, link: String) {
    // A web link opens Porch, or shows how to get it first.
    val note = if (link.startsWith("https:")) "Join our Porch! Open this link on your phone. If you don't have Porch yet, it shows you how to get it. It works once, for 24 hours."
        else "Join our Porch! This link works once, for 24 hours."
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "$note\n$link")
    try { staysInCaregiverMode { context.startActivity(Intent.createChooser(send, null)) } } catch (_: ActivityNotFoundException) {}
}

// MARK: Shared pieces

/** Asks for the microphone, and the camera with `video`, then calls back with whether the tablet may use them. */
typealias MediaAccess = (video: Boolean, done: (Boolean) -> Unit) -> Unit

/** `ask` is false on a family phone, whose own microphone and camera a drop-in doesn't use: it allows at once. */
@Composable
fun rememberMediaAccess(ask: Boolean = true): MediaAccess {
    val context = LocalContext.current
    val waiting = remember { mutableStateOf<((Boolean) -> Unit)?>(null) }
    val asked = remember { mutableStateOf<List<String>>(emptyList()) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        val done = waiting.value
        val needed = asked.value
        waiting.value = null
        asked.value = emptyList()
        // Dismissing the prompt returns an empty map, and `all` on an empty collection is true, so check each permission
        // that was asked for. Otherwise drop-in would be approved without the microphone or camera.
        done?.invoke(needed.isNotEmpty() && needed.all { results[it] == true })
    }
    return remember(launcher, ask) {
        { video, done ->
            val missing = listOfNotNull(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA.takeIf { video })
                .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
            if (!ask || missing.isEmpty()) done(true) else {
                waiting.value = done
                asked.value = missing
                launcher.launch(missing.toTypedArray())
            }
        }
    }
}

internal val FamilyPerson.shortStatus: String
    get() = if (online) "Porch is open" else if (canReceiveCalls == true) "Can ring while locked" else "Offline"

internal val FamilyPerson.dropInModes: String?
    get() = when {
        permissions.audio && permissions.video -> "Audio and video"
        permissions.audio -> "Audio"
        permissions.video -> "Video"
        else -> null
    }

/** A one-line summary for the family list; null when they can only make ordinary calls. */
internal val FamilyPerson.access: String?
    get() = listOfNotNull(dropInModes?.let { "$it drop-in" }, "Caregiver".takeIf { caregiver == true }).joinToString(" · ").ifEmpty { null }

internal val FamilyPerson.firstName: String get() = name.split(" ").firstOrNull { it.isNotEmpty() } ?: name

/** Whether a key is for this family member, by the invitation that brought them or by who they are. */
internal fun isFor(contact: CallContact, person: FamilyPerson): Boolean =
    (contact.invitationID != null && contact.invitationID == person.invitationID) || (contact.familyMemberID != null && contact.familyMemberID == person.id)

/** The key that calls this family member, if any. */
internal fun keyFor(slots: CallSlots, person: FamilyPerson): Int? = CallSlots.digits.firstOrNull { digit -> slots.contact(digit)?.let { isFor(it, person) } == true }

/** A key for someone on Porch, or invited to it: it keeps the key's numbers, how calls start, color and photo, and goes by
 * their Porch name. */
private fun linked(contact: CallContact, memberID: String? = null, invitationID: String?, name: String): CallContact =
    CallContact(name = "", nativeCall = contact.nativeCall, phoneNumber = contact.phoneNumber, otherPhoneNumbers = contact.otherPhoneNumbers,
        familyMemberID = memberID, invitationID = invitationID, memberName = name, buttonColorHex = contact.buttonColorHex, photoData = contact.customPhotoData)

/** A new key's own call room. */
internal fun newRoom(): String = "contact-" + UUID.randomUUID().toString().take(8).lowercase()

/** The tablet's country, for numbers typed without a country code. */
internal fun homeRegion(): String = Locale.getDefault().country.ifEmpty { "US" }

/** A number as people read it: national at home, international otherwise. */
internal fun displayNumber(e164: String): String = PhoneNumberNormalization.display(e164, homeRegion())

/** A key's button color, or null for the default. */
internal fun buttonColor(hex: String?): Color? =
    hex?.takeIf { it.length == 6 }?.toLongOrNull(16)?.let { Color(0xFF000000 or it) }

/** Black or white, whichever reads better on `color`. */
internal fun foreground(color: Color): Color = if (color.luminance() > 0.179f) Color.Black else Color.White

@Composable
internal fun ColorSwatch(hex: String?, modifier: Modifier = Modifier, selected: Boolean = false) {
    val color = buttonColor(hex) ?: CallColors.control
    Box(modifier.clip(CircleShape).background(color)
        .border(if (selected) 3.dp else 1.dp, if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, CircleShape)
        .semantics { contentDescription = hex?.let { "Color #$it" } ?: "Default color"; this.selected = selected })
}

/** Colors that keep a name readable on a key, and a hex field for any other, as a stand-in for iOS's color picker. */
private val palette = listOf("C62828", "AD1457", "6A1B9A", "283593", "1565C0", "00838F", "2E7D32", "827717", "F9A825", "EF6C00", "4E342E", "37474F")

@Composable
internal fun ButtonColorDialog(current: String?, onChoose: (String?) -> Unit, onDismiss: () -> Unit) {
    var hex by remember { mutableStateOf(current.orEmpty()) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Button color") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                palette.chunked(4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        row.forEach { value ->
                            ColorSwatch(value, Modifier.size(52.dp).clickable(role = Role.Button) { hex = value }, selected = hex.equals(value, ignoreCase = true))
                        }
                    }
                }
                OutlinedTextField(hex, { typed -> hex = typed.filter { it.isLetterOrDigit() }.take(6).uppercase() }, singleLine = true,
                    label = { Text("Hex color") }, prefix = { Text("#") })
            }
        },
        confirmButton = { TextButton(onClick = { onChoose(hex.uppercase()) }, enabled = buttonColor(hex) != null) { Text("Use this color") } },
        dismissButton = {
            Row {
                if (current != null) TextButton(onClick = { onChoose(null) }) { Text("Use the default color") }
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        })
}
