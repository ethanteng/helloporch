package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import android.icu.text.DateFormat as IcuDateFormat
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyAdminState
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PersonRows
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.RemoteCaregiverSession
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

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

/** The small screens a person's rows open, and the invitation just made for them. */
private enum class PersonScreen { NAME, PORCH_APP, PHONE, KEY, DROP_IN, INVITE }

/**
 * One person, as iOS's PersonViewController shows them, laid out like Add someone's Check step: their key as the
 * bedside shows it, with its photo and color, or their photo and status when they're not on a key; then a row for each
 * of their name, Porch app, phone, key and drop-in, which opens a small screen of its own; caregiver mode; and removing
 * them. A Porch family member has one name and photo, kept with their Porch profile, which their key and calls show.
 * Someone on the keypad only by phone keeps the name and photo saved with their key. What's open redraws as the family
 * changes, and closes with the page once they're gone.
 */
@Composable
internal fun PersonPage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, initialMemberID: String?, initialSlot: Int?, onDone: () -> Unit) {
    var memberID by rememberSaveable { mutableStateOf(initialMemberID) }
    var slot by rememberSaveable { mutableStateOf(initialSlot) }
    var screen by rememberSaveable { mutableStateOf<PersonScreen?>(null) }
    /** The invitation just made for them, which the Invite ready screen shows. */
    var link by rememberSaveable { mutableStateOf<String?>(null) }
    var removing by remember { mutableStateOf<Removing?>(null) }
    var cancellingInvite by remember { mutableStateOf(false) }
    /** A new invitation is being made. */
    var inviting by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val state = admin.state(links)
    val slots = admin.slots
    val subject = resolve(state, slots, memberID, slot)
    /** The person as of now, for a change that finishes after the page last drew. */
    fun latest() = resolve(admin.state(app.coordinator.links.value), admin.slots, memberID, slot)

    LaunchedEffect(subject.member?.id, subject.slot) { memberID = subject.member?.id; slot = subject.slot }
    // Removed here or by another caregiver: the page closes, with whatever was open over it.
    val gone = subject.member == null && subject.contact == null
    LaunchedEffect(gone) { if (gone) onDone() }
    if (gone) return

    val member = subject.member
    val contact = subject.contact
    val key = subject.slot
    val onKey = admin.onBedside && key != null && contact != null
    val dropInNumber = phoneDropInNumber(app, admin, contact)
    val shown = screen?.takeIf {
        when (it) {
            PersonScreen.NAME -> true
            PersonScreen.PORCH_APP, PersonScreen.PHONE -> onKey
            PersonScreen.KEY -> admin.onBedside
            PersonScreen.DROP_IN -> member != null || dropInNumber != null
            PersonScreen.INVITE -> link != null
        }
    }
    // A screen whose row went away, such as Porch app once they're off the keypad, closes.
    LaunchedEffect(screen, shown) { if (screen != null && shown == null) screen = null }
    BackHandler {
        when {
            shown == null -> onDone()
            !inviting -> { screen = null; link = null }
        }
    }

    fun clearKeyPhoto() {
        val current = latest()
        val at = current.slot ?: return
        val keyed = current.contact?.takeIf { it.photoID != null } ?: return
        admin.saveSlots { it.setContact(keyed.updatingPhoto(null), at) }
    }
    fun photoChosen(data: ByteArray?) {
        if (data == null) { admin.error = "That photo couldn't be opened. Please choose another photo."; return }
        val current = latest()
        val who = current.member
        val at = current.slot
        val keyed = current.contact
        if (who != null) {
            // One photo per person: the key shows the one saved with their Porch profile.
            admin.launch { if (chooseOverridePhoto(data, who.id)) clearKeyPhoto() }
        } else if (at != null && keyed != null) admin.saveSlots { it.setContact(keyed.updatingPhoto(data), at) }
    }
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        RemoteCaregiverSession.shared.answered()
        if (uri != null) scope.launch { photoChosen(FamilyPhotos.prepared(context, uri)) }
    }
    fun choosePhoto() {
        try { staysInCaregiverMode(answers = true) { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) } }
        catch (_: ActivityNotFoundException) { admin.error = "No app on this device can choose a photo." }
    }
    /** Back to their own photo, or no photo: a caregiver's choice for a family member, or a key's own photo. */
    fun removePhoto() {
        val who = latest().member
        if (who?.override?.photoID != null) {
            admin.launch { if (send("setMemberOverride", mapOf("memberID" to JsonPrimitive(who.id), "photo" to JsonNull))) clearKeyPhoto() }
        } else clearKeyPhoto()
    }
    /** Takes them off the keypad. Their phone drop-in goes with their key. False, with why shown, when it can't. */
    suspend fun removeFromKeypad(): Boolean {
        val current = latest()
        val at = current.slot ?: return false
        val keyed = current.contact ?: return false
        val number = keyed.phoneNumber
        if (number != null && app.coordinator.links.value.state?.phoneDropIns.orEmpty().any { it.number == number }) {
            if (!admin.send("setPhoneDropIn", mapOf("number" to JsonPrimitive(number), "enabled" to JsonPrimitive(false)))) return false
        }
        return admin.saveSlots { it.setContact(null, at) }
    }
    fun removeFromPorch(person: FamilyPerson) {
        val onKeypad = latest().slot != null
        admin.launch { if (send("revoke", mapOf("memberID" to JsonPrimitive(person.id))) && onKeypad) removeFromKeypad() }
    }
    /** Their name: a family member's is the caregiver's choice for them, which an empty one clears, and one saved on
     * their key goes, so the key shows it. Someone only on the keypad keeps theirs with their key. */
    fun saveName(typed: String) {
        val current = latest()
        val who = current.member
        if (who != null) {
            admin.launch {
                if (!send("setMemberOverride", mapOf("memberID" to JsonPrimitive(who.id), "name" to JsonPrimitive(typed)))) return@launch
                val now = latest()
                val at = now.slot
                val keyed = now.contact
                if (at != null && keyed != null && keyed.customName.isNotEmpty()) saveSlots { it.setContact(keyed.updating(name = ""), at) }
                screen = null
            }
        } else {
            val at = current.slot
            val keyed = current.contact
            if (at != null && keyed != null && admin.saveSlots { it.setContact(keyed.updating(name = typed), at) }) screen = null
        }
    }
    fun saveColor(hex: String?) {
        val current = latest()
        val at = current.slot ?: return
        val keyed = current.contact ?: return
        admin.saveSlots { it.setContact(keyed.updating(buttonColorHex = hex), at) }
    }
    /** Moves their key, or gives a family member who isn't on the keypad one. */
    fun moveTo(digit: Int?) {
        val current = latest()
        val from = current.slot
        val keyed = current.contact
        val who = current.member
        if (digit == null || digit == from) { screen = null; return }
        val moved = if (from != null && keyed != null) admin.saveSlots { it.setContact(null, from); it.setContact(keyed, digit) }
        else if (who != null) {
            val made = CallContact(name = "", nativeCall = NativeCall(newRoom(), NativeCall.Mode.VOICE), familyMemberID = who.id,
                invitationID = who.invitationID, memberName = who.name)
            admin.saveSlots { it.setContact(made, digit) }
        } else false
        if (moved) { slot = digit; screen = null }
    }
    /** Their key goes to a family member who joined Porch some other way, such as an invitation from People. */
    fun linkTo(person: FamilyPerson) {
        val current = latest()
        val at = current.slot ?: return
        val keyed = current.contact ?: return
        admin.saveSlots { it.setContact(linked(keyed, memberID = person.id, invitationID = person.invitationID, name = person.name), at) }
    }
    fun setVideo(video: Boolean) {
        val current = latest()
        val at = current.slot ?: return
        val keyed = current.contact ?: return
        admin.saveSlots { it.setContact(keyed.updating(mode = if (video) NativeCall.Mode.VIDEO else NativeCall.Mode.VOICE), at) }
    }
    /**
     * Invites them again, as Add someone invites someone: drop-in on and no caregiver mode. An invitation still waiting is
     * cancelled first. Their key goes by the invitation's name and follows it, keeping its numbers, calls, color and
     * photo, then the invitation shows its code.
     */
    fun sendInvite() {
        if (inviting) return
        val current = latest()
        val keyed = current.contact ?: return
        val name = keyed.name
        val waiting = keyed.invitationID?.takeIf { id -> admin.state(app.coordinator.links.value)?.invitations.orEmpty().any { it.id == id } }
        inviting = true
        scope.launch {
            try {
                // Asked before the old invitation goes, so refusing leaves it as it was.
                if (!mediaAccess.granted(true)) {
                    admin.error = "Grant microphone and camera access before approving drop-in."
                    return@launch
                }
                waiting?.let { admin.request("cancelInvite", mapOf("inviteID" to JsonPrimitive(it))) }
                val made = createInvitation(app, admin, mediaAccess, name, audio = true, video = true) ?: return@launch
                val now = latest()
                val at = now.slot
                val nowKeyed = now.contact
                if (at != null && nowKeyed != null && admin.saveSlots { it.setContact(linked(nowKeyed, invitationID = made.id, name = name), at) }) {
                    link = made.link
                    screen = PersonScreen.INVITE
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                admin.error = e.message ?: "Couldn't reach Porch. Check the connection and try again."
            } finally {
                inviting = false
            }
        }
    }
    /** Cancels their waiting invitation. Their key stays, reached by phone, with the same name, numbers, color and photo. */
    fun cancelInvite() {
        val id = latest().contact?.invitationID ?: return
        admin.launch {
            if (!send("cancelInvite", mapOf("inviteID" to JsonPrimitive(id)))) return@launch
            // Cancelling updates the family first, and a key follows an invitation on its own. That keypad is saved
            // before this returns, and is newer than the one this screen was drawn from.
            reloadSlots()
            val now = latest()
            val at = now.slot ?: return@launch
            val keyed = now.contact ?: return@launch
            // A key with no number has no other way to reach them, so it keeps the invitation, which can be sent again.
            // A key that already followed a different invitation is left as it is.
            if (keyed.invitationID != id || keyed.phoneNumber == null) return@launch
            saveSlots { it.setContact(CallContact(name = keyed.name, nativeCall = keyed.nativeCall, phoneNumber = keyed.phoneNumber,
                otherPhoneNumbers = keyed.otherPhoneNumbers, buttonColorHex = keyed.buttonColorHex, photoData = keyed.customPhotoData), at) }
        }
    }

    val lovedOne = lovedOne(admin, links)
    val back = { screen = null }
    val porchApp = PersonRows.porchApp(member != null, contact?.invitationID, state?.invitations)
    val phoneApproved = dropInNumber != null && state?.phoneDropIns.orEmpty().any { it.number == dropInNumber }
    when (shown) {
        PersonScreen.NAME -> {
            val saved = if (member != null) member.override?.name ?: contact?.customName?.ifEmpty { null } else contact?.customName
            val placeholder = member?.let { it.profile?.name ?: it.invitedName ?: it.name } ?: "Their name"
            NameScreen(saved.orEmpty(), placeholder, admin.busy, onBack = back, onSave = ::saveName)
        }
        PersonScreen.PORCH_APP -> if (contact != null) PorchAppScreen(admin, state, slots, subject, contact, porchApp, inviting, onBack = back,
            onInvite = ::sendInvite, onCancelInvite = { cancellingInvite = true }, onLink = ::linkTo, onVideo = ::setVideo)
        PersonScreen.PHONE -> if (key != null && contact != null) PersonPhoneScreen(app, admin, links, key, contact, onDone = back)
        PersonScreen.KEY -> KeyScreen(slots, key, subject.firstName, admin.busy, onBack = back, onDone = ::moveTo,
            onTakeOff = { removing = Removing.KEYPAD })
        PersonScreen.DROP_IN -> PersonDropInScreen(app, admin, links, memberID, slot, "Drop-in", onBack = back)
        PersonScreen.INVITE -> InviteReady(subject.name, "Invite ready", subject.firstName, link, onDone = { screen = null; link = null })
        null -> FormScreen(subject.name, navigation = { BackButton(onDone) }) {
            val memberPhoto = member?.let { memberPhoto(app, admin, it) }
            val photo = remember(contact, memberPhoto) { contact?.customPhotoData ?: memberPhoto ?: contact?.photoData }
            val removal = if (member?.override?.photoID != null || contact?.photoID != null) {
                if (member?.profile?.photoID != null) "Use their own photo" else "Remove photo"
            } else null
            val photoButton = @Composable { PhotoButton(photo != null, removal, enabled = !admin.busy, onChoose = ::choosePhoto, onRemove = ::removePhoto) }
            if (onKey) {
                Text("On $lovedOne's screen", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                KeyPreview(subject.name, photo, CallSlots.symbol(key), buttonColor(contact.buttonColorHex))
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(8.dp),
                    itemVerticalAlignment = Alignment.CenterVertically) {
                    photoButton()
                    val hex = contact.buttonColorHex
                    // A color chosen with the old picker stays, chosen, until one of these replaces it.
                    val custom = hex?.takeIf { chosen -> swatches.none { it.first == chosen } }
                    Row(Modifier.selectableGroup()) {
                        swatches.forEach { (value, label) -> Swatch(value, label, selected = hex == value, enabled = !admin.busy) { saveColor(value) } }
                        custom?.let { Swatch(it, "Color #$it", selected = true, enabled = !admin.busy) {} }
                    }
                }
            } else Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Avatar(subject.name, photo, 96.dp)
                photoButton()
                val status = member?.let { it.shortStatus + if (it.id == admin.myID) " · This phone" else "" }
                    ?: if (porchApp == PersonRows.PorchApp.INVITE_SENT) "Invite sent" else "Not on Porch"
                Text(status, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            CaregiverGroup {
                DetailRow(R.drawable.ic_account, "Name", subject.name) { screen = PersonScreen.NAME }
                if (onKey) {
                    HorizontalDivider()
                    DetailRow(R.drawable.ic_videocam, "Porch app", porchApp.value, accent = porchApp == PersonRows.PorchApp.NOT_ON_PORCH) {
                        screen = PersonScreen.PORCH_APP
                    }
                    HorizontalDivider()
                    val others = contact.otherPhoneNumbers.size
                    val number = contact.phoneNumber?.let { displayNumber(it) + if (others > 0) " +$others" else "" }
                    DetailRow(R.drawable.ic_call, "Phone", number ?: "Add", accent = number == null) { screen = PersonScreen.PHONE }
                }
                if (admin.onBedside) {
                    HorizontalDivider()
                    DetailRow(R.drawable.ic_dialpad, "Key", key?.let(CallSlots::symbol) ?: "None") { screen = PersonScreen.KEY }
                }
                if (member != null || dropInNumber != null) {
                    HorizontalDivider()
                    DetailRow(R.drawable.ic_phone_in_talk, "Drop-in", PersonRows.dropIn(state?.dropInEnabled == false, member?.permissions, phoneApproved)) {
                        screen = PersonScreen.DROP_IN
                    }
                }
            }

            member?.let { person ->
                // A caregiver's phone can't take its own access away: another caregiver can.
                val isMe = person.id == admin.myID
                CaregiverGroup {
                    ToggleRow("Caregiver mode", person.caregiver == true, enabled = !admin.busy && !isMe,
                        detail = if (isMe) "Another caregiver can change this." else "Can change settings from their phone.",
                        onChange = { admin.perform("setCaregiver", mapOf("memberID" to JsonPrimitive(person.id), "enabled" to JsonPrimitive(it))) })
                }
            }

            // This phone can't remove itself. The server refuses that, and the refusal would end caregiver mode. Another
            // caregiver removes it; leaving the family is on this phone's own card. The bedside isn't one of these people.
            if (member?.id != admin.myID || admin.myID == null) {
                FormPlainButton("Remove ${subject.firstName}", onClick = {
                    removing = if (member == null) Removing.KEYPAD else if (key == null) Removing.PORCH else Removing.EITHER
                }, enabled = !admin.busy, color = MaterialTheme.colorScheme.error)
            }
        }
    }

    val leaving = "Their device will need a new invitation to call this Porch again."
    when (removing) {
        // From the page, or the Key screen, which goes back to the page once they're off the keypad.
        Removing.KEYPAD -> AlertDialog(onDismissRequest = { removing = null },
            title = { Text("Take ${subject.name} off the keypad?") },
            text = { Text(key?.let { "Key ${CallSlots.symbol(it)} will be empty." } ?: "") },
            confirmButton = { TextButton(onClick = { removing = null; admin.launch { if (removeFromKeypad()) screen = null } }) { Text("Remove") } },
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
    if (cancellingInvite) AlertDialog(onDismissRequest = { cancellingInvite = false },
        title = { Text("Cancel ${subject.firstName}'s invite?") },
        confirmButton = {
            TextButton(onClick = { cancellingInvite = false; cancelInvite() },
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Cancel invite") }
        },
        dismissButton = { TextButton(onClick = { cancellingInvite = false }) { Text("Keep") } })
}

/** Photo, or Change photo once there is one. With a photo that can go, it offers that beside choosing another. */
@Composable
private fun PhotoButton(hasPhoto: Boolean, removal: String?, enabled: Boolean, onChoose: () -> Unit, onRemove: () -> Unit) {
    Box {
        var open by remember { mutableStateOf(false) }
        OutlinedButton(onClick = { if (removal == null) onChoose() else open = true }, enabled = enabled, contentPadding = PaddingValues(horizontal = 14.dp)) {
            Icon(painterResource(R.drawable.ic_photo), contentDescription = null, Modifier.size(20.dp))
            Text(if (hasPhoto) "Change photo" else "Photo", Modifier.padding(start = 8.dp))
        }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text("Choose from library") }, onClick = { open = false; onChoose() })
            removal?.let { DropdownMenuItem(text = { Text(it) }, onClick = { open = false; onRemove() }) }
        }
    }
}

// MARK: The screens the rows open

/** Their name, with what they go by on Porch as the placeholder. Save goes back to the page once it's saved. */
@Composable
private fun NameScreen(saved: String, placeholder: String, busy: Boolean, onBack: () -> Unit, onSave: (String) -> Unit) {
    var name by rememberSaveable { mutableStateOf(saved) }
    FormScreen("Name", navigation = { BackButton(onBack) }) {
        PorchTextField(name, { name = it }, "Name", Modifier.fillMaxWidth().semantics { contentDescription = "Name" }, enabled = !busy,
            placeholder = { Text(placeholder) }, keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        FormButton("Save", enabled = !busy, onClick = { onSave(name.trim()) })
    }
}

/**
 * How their key reaches their Porch app: connected, an invitation waiting or expired, or not on Porch yet, with a new
 * invitation for each but the first. A key that's linked to Porch says how its calls start.
 */
@Composable
private fun PorchAppScreen(admin: CaregiverAdmin, state: FamilyAdminState?, slots: CallSlots, subject: Subject, contact: CallContact,
    status: PersonRows.PorchApp, inviting: Boolean, onBack: () -> Unit, onInvite: () -> Unit, onCancelInvite: () -> Unit, onLink: (FamilyPerson) -> Unit,
    onVideo: (Boolean) -> Unit) {
    // Invitations last a day, so the expiry needs its day ("tomorrow, 3:14 PM"), as the People list says it.
    val expiry = remember { IcuDateFormat.getDateTimeInstance(IcuDateFormat.RELATIVE_SHORT, IcuDateFormat.SHORT) }
    val busy = inviting || admin.busy
    FormScreen("Porch app", navigation = { BackButton(onBack, enabled = !inviting) }) {
        when (status) {
            PersonRows.PorchApp.CONNECTED -> StatusCard(null, status.value, subject.member?.shortStatus)
            PersonRows.PorchApp.INVITE_SENT -> {
                val expires = state?.invitations.orEmpty().firstOrNull { it.id == contact.invitationID }?.expiresAt
                StatusCard("◔︎", status.value, expires?.let { "Expires ${expiry.format(Date(it * 1000))}" })
                FormButton("Send a new invite", onClick = onInvite, enabled = !busy, filled = false)
                FormPlainButton("Cancel invite", onClick = onCancelInvite, enabled = !busy, color = MaterialTheme.colorScheme.error)
            }
            PersonRows.PorchApp.INVITE_EXPIRED -> {
                StatusCard(null, status.value, null)
                FormButton("Send a new invite", onClick = onInvite, enabled = !busy)
            }
            PersonRows.PorchApp.NOT_ON_PORCH -> FormButton("Invite ${subject.firstName}", onClick = onInvite, enabled = !busy)
        }
        if (subject.member != null || contact.invitationID != null) CaregiverGroup("Calls start with") {
            Box(Modifier.padding(16.dp)) {
                Choices(listOf("Voice", "Video"), if (contact.nativeCall.mode == NativeCall.Mode.VIDEO) 1 else 0, Modifier.fillMaxWidth()) { onVideo(it == 1) }
            }
        }
        // Or they joined Porch some other way, such as an invitation from People.
        val unlinked = state?.people.orEmpty().filter { keyFor(slots, it) == null }
        if (subject.member == null && status != PersonRows.PorchApp.INVITE_SENT && unlinked.isNotEmpty()) CaregiverGroup {
            Box {
                var open by remember { mutableStateOf(false) }
                ActionRow("Choose from Family on Porch", enabled = !busy) { open = true }
                DropdownMenu(open, onDismissRequest = { open = false }) {
                    unlinked.forEach { person -> DropdownMenuItem(text = { Text(person.name) }, onClick = { open = false; onLink(person) }) }
                }
            }
        }
    }
}

/** Where they are with Porch, on a card of its own: an icon for an invitation, what it is, and when. */
@Composable
private fun StatusCard(glyph: String?, title: String, detail: String?) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), tonalElevation = 2.dp) {
        Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            glyph?.let { GlyphBadge(it, empty = true) }
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center) }
        }
    }
}

/** Their key, chosen on the keypad as Add someone chooses one: Done moves them there. Taking them off asks first. */
@Composable
private fun KeyScreen(slots: CallSlots, key: Int?, name: String, busy: Boolean, onBack: () -> Unit, onDone: (Int?) -> Unit, onTakeOff: () -> Unit) {
    var chosen by rememberSaveable { mutableStateOf(key) }
    FormScreen("Key", navigation = { BackButton(onBack) }) {
        KeyGrid(slots, chosen, key, name) { chosen = it }
        FormButton("Done", enabled = !busy, onClick = { onDone(chosen) })
        if (key != null) FormPlainButton("Take off the keypad", onClick = onTakeOff, enabled = !busy, color = MaterialTheme.colorScheme.error)
    }
}

/** The number on their key that phone drop-in can approve. Approvals live on the server, so a bedside that isn't paired
 * yet can't offer them, and a key's number is the bedside's. */
private fun phoneDropInNumber(app: PorchApplication, admin: CaregiverAdmin, contact: CallContact?): String? =
    contact?.phoneNumber?.takeIf { admin.onBedside && app.device.credential(PorchExperience.BEDSIDE) != null }

/**
 * Someone's drop-in in their Porch app and by phone, approved apart: their page's Drop-in screen, which the Drop-in page
 * also opens for a family member, titled with their name. It closes once there's nothing left to set, such as when
 * they're removed.
 */
@Composable
internal fun PersonDropInScreen(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, memberID: String?, slot: Int?, title: String?,
    onBack: () -> Unit) {
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val state = admin.state(links)
    val subject = resolve(state, admin.slots, memberID, slot)
    val person = subject.member
    val number = phoneDropInNumber(app, admin, subject.contact)
    val empty = person == null && number == null
    LaunchedEffect(empty) { if (empty) onBack() }
    BackHandler(onBack = onBack)
    if (empty) return
    /** Drop-in answers on the bedside, so only the tablet can grant its own microphone and camera. */
    fun setApp(who: FamilyPerson, audio: Boolean, video: Boolean) {
        val send = { admin.perform("setPermissions", mapOf("memberID" to JsonPrimitive(who.id),
            "permissions" to JsonObject(mapOf("audio" to JsonPrimitive(audio), "video" to JsonPrimitive(video))))) }
        if (audio || video) mediaAccess(video) { granted ->
            if (granted) send() else admin.error = "Allow the microphone and camera in the tablet's settings before approving drop-in."
        } else send()
    }
    fun setPhone(on: Boolean) {
        val approving = number ?: return
        if (!on) admin.perform("setPhoneDropIn", mapOf("number" to JsonPrimitive(approving), "enabled" to JsonPrimitive(false)))
        else mediaAccess(false) { granted ->
            if (!granted) admin.error = "Allow the microphone in the tablet's settings before approving drop-in."
            else admin.perform("setPhoneDropIn", mapOf("number" to JsonPrimitive(approving), "name" to JsonPrimitive(subject.contact?.name.orEmpty()),
                "enabled" to JsonPrimitive(true)))
        }
    }
    DropInScreen(admin, state, title ?: subject.name, lovedOne(admin, links), person, number,
        phoneApproved = number != null && state?.phoneDropIns.orEmpty().any { it.number == number }, onBack = onBack, onApp = ::setApp, onPhone = { setPhone(it) })
}

@Composable
private fun DropInScreen(admin: CaregiverAdmin, state: FamilyAdminState?, title: String, lovedOne: String, person: FamilyPerson?, number: String?,
    phoneApproved: Boolean, onBack: () -> Unit, onApp: (FamilyPerson, Boolean, Boolean) -> Unit, onPhone: (Boolean) -> Unit) {
    FormScreen(title, navigation = { BackButton(onBack) }) {
        Text(if (state?.dropInEnabled == false) "Drop-ins are paused for everyone." else "Connects without $lovedOne answering.",
            style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (person != null) CaregiverGroup("Porch app") {
            ToggleRow("Audio", person.permissions.audio, { onApp(person, it, person.permissions.video) }, enabled = !admin.busy, label = "Audio drop-in")
            HorizontalDivider()
            ToggleRow("Video", person.permissions.video, { onApp(person, person.permissions.audio, it) }, enabled = !admin.busy, label = "Video drop-in")
        }
        if (number != null) CaregiverGroup("Phone") {
            ToggleRow("Calls from ${displayNumber(number)}", phoneApproved, onPhone, detail = "Audio only.", enabled = !admin.busy)
        }
    }
}
