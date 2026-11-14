package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ethanteng.helloporch.core.AddSomeoneDraft
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyInvitation
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.PhoneNumberList
import com.ethanteng.helloporch.core.PhoneNumberNormalization
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.ValidationException
import java.util.UUID
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Where Add someone opens: from People's Add someone, from an empty key, or from a key that does something else. */
enum class AddSomeoneStart { PEOPLE, KEY_TILE, CONTROL }

private enum class AddScreen { WHO, REACH, CHECK, INVITE, PHONE, APP, KEY, KEY_ACTION }

/** A photo chosen for someone being added. It outlives a rotation here, rather than in the saved draft: a photo can be
 * close to 1 MB, more than a screen may keep when it turns. */
class AddSomeonePhoto : ViewModel() {
    var data by mutableStateOf<ByteArray?>(null)
}

/**
 * Add someone on the bedside, a step at a time, as iOS's AddSomeone.swift does it: who they are, how Porch reaches them,
 * then a check of their key as the bedside will show it. Saving approves their number, invites them to Porch and puts
 * them on their key, in that order, and an invitation then shows its code and link. A key that does something else
 * opens what it does first (`AddSomeoneStart.CONTROL`). Back goes back one screen.
 */
@Composable
fun AddSomeone(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, key: Int?, start: AddSomeoneStart, onDone: () -> Unit) {
    var draft by rememberSaveable { mutableStateOf(AddSomeoneDraft(key, tile = key.takeIf { start != AddSomeoneStart.PEOPLE })) }
    var screens by rememberSaveable { mutableStateOf(listOf(if (start == AddSomeoneStart.CONTROL) AddScreen.KEY_ACTION else AddScreen.WHO)) }
    var saving by remember { mutableStateOf(false) }
    val flow = rememberSaveable { UUID.randomUUID().toString() }
    val photo = viewModel<AddSomeonePhoto>(key = "add-someone-$flow")
    // Kept through a rotation, and let go once Add someone closes.
    val activity = LocalActivity.current
    DisposableEffect(photo) { onDispose { if (activity?.isChangingConfigurations != true) photo.data = null } }
    val scope = rememberCoroutineScope()
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val region = remember { homeRegion() }
    val lovedOne = lovedOne(admin, links)
    val title = draft.key?.takeIf { draft.fromKeyTile }?.let { "Key ${CallSlots.symbol(it)}" } ?: "Add someone"
    val update: ((AddSomeoneDraft) -> AddSomeoneDraft) -> Unit = { change -> draft = change(draft) }
    fun open(screen: AddScreen) { screens = screens + screen }
    fun back() {
        if (saving) return
        val top = screens.last()
        // An invitation that's been made stays made, so its screen ends Add someone.
        if (top == AddScreen.INVITE || screens.size == 1) { onDone(); return }
        screens = screens.dropLast(1)
        // They're reached by phone when they have a number.
        if (top == AddScreen.PHONE) draft = draft.copy(viaPhone = draft.numbers.isNotEmpty())
    }
    BackHandler(onBack = ::back)

    /** Approves their number, invites them, then puts them on their key, as the person page's Phone screen and the invite
     * screen do. */
    fun save() {
        if (saving) return
        val saved = draft
        if (!saved.reachable) { admin.error = AddSomeoneDraft.unreachable; return }
        // Someone on a key by name only: a name Porch won't take is refused before anything is sent.
        if (saved.key != null && !saved.inviting) try { saved.contact(null, newRoom(), null) } catch (e: ValidationException) { admin.error = e.message; return }
        saving = true
        scope.launch {
            try {
                saved.numbers.firstOrNull()?.let { PhoneApprovals.authorize(app, it, refresh = true) }
                // Only an invitation made for this name and drop-in is reused. One left over from a failed save must not
                // follow a different person, phone only, or drop-in the caregiver has since changed.
                var invitation = saved.reusableInvitation()
                if (saved.inviting && invitation == null) {
                    // Drop-in answers on the bedside, so only the tablet can grant its own microphone and camera.
                    if ((saved.dropInAudio || saved.dropInVideo) && !mediaAccess.granted(saved.dropInVideo)) {
                        admin.error = "Grant microphone and camera access before approving drop-in."
                        return@launch
                    }
                    val origin = admin.origin ?: throw IllegalStateException("Go back to the clock and open caregiver mode to finish setup.")
                    val invitedName = saved.name.trim()
                    val response = admin.request("createInvite", mapOf("name" to JsonPrimitive(invitedName), "caregiver" to JsonPrimitive(false),
                        "permissions" to JsonObject(mapOf("audio" to JsonPrimitive(saved.dropInAudio), "video" to JsonPrimitive(saved.dropInVideo)))))
                    val code = response.code
                    val id = response.invitationID
                    if (code == null || id == null) throw IllegalStateException("Couldn't make the invitation. Try again.")
                    invitation = id
                    draft = draft.copy(invitationID = id, link = FamilyInvitation.url(origin, code, app.device.defaultOrigin),
                        invitationName = invitedName, invitationAudio = saved.dropInAudio, invitationVideo = saved.dropInVideo)
                }
                val at = saved.key
                if (at != null) {
                    val contact = saved.contact(invitation, newRoom(), photo.data)
                    if (!admin.saveSlots { it.setContact(contact, at); it.setAction(KeypadAction.PERSON, at) }) return@launch
                }
                if (saved.inviting) open(AddScreen.INVITE) else onDone()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                admin.error = e.message ?: "Couldn't reach Porch. Check the connection and try again."
            } finally {
                saving = false
            }
        }
    }

    when (screens.last()) {
        AddScreen.WHO -> WhoStep(app, admin, links, draft, title, region, update, onCancel = onDone,
            onMember = { person -> draft = draft.choosing(person); open(AddScreen.CHECK) },
            onNext = { draft = draft.someoneNew(); open(AddScreen.REACH) },
            onSomethingElse = { open(AddScreen.KEY_ACTION) })
        AddScreen.REACH -> ReachStep(admin, draft, title, lovedOne, region, update, onBack = ::back, onNext = { open(AddScreen.CHECK) })
        AddScreen.CHECK -> CheckStep(app, admin, links, draft, photo, title, lovedOne, region, saving, update, onBack = ::back, onOpen = ::open,
            onSave = ::save)
        AddScreen.INVITE -> InviteStep(draft, title, onDone)
        // A number added or picked means Porch can call their phone.
        AddScreen.PHONE -> PhoneNumbersScreen(admin, draft.numbers, { numbers -> update { it.copy(numbers = numbers, viaPhone = numbers.isNotEmpty()) } },
            lovedOne, region, saving = false, problem = null, onBack = ::back, onDone = { back() })
        AddScreen.APP -> AppScreen(draft, lovedOne, update, onBack = ::back)
        AddScreen.KEY -> KeyScreen(admin, draft, update, onBack = ::back)
        AddScreen.KEY_ACTION -> {
            // Opened from the key, it's that key's. From Step 1, it's the key Step 1 is for.
            val control = screens.size == 1
            (if (control) draft.tile else draft.key)?.let { at ->
                KeyActionScreen(admin, at, control, onBack = ::back, onSomeone = { open(AddScreen.WHO) }, onSaved = onDone)
            }
        }
    }
}

/** Asks for the microphone, and the camera with `video`, and waits for the answer. */
private suspend fun MediaAccess.granted(video: Boolean): Boolean = suspendCancellableCoroutine { waiting -> this(video) { waiting.resume(it) } }

// MARK: Step 1

@Composable
private fun WhoStep(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, draft: AddSomeoneDraft, title: String, region: String,
    update: ((AddSomeoneDraft) -> AddSomeoneDraft) -> Unit, onCancel: () -> Unit, onMember: (FamilyPerson) -> Unit, onNext: () -> Unit,
    onSomethingElse: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pickContact = rememberLauncherForActivityResult(PickPhoneNumber()) { uri ->
        if (uri != null) scope.launch {
            val picked = pickedNumber(context, uri) ?: run { admin.error = "That contact's number couldn't be read. Type it instead."; return@launch }
            try {
                val number = PhoneNumberNormalization.e164(picked.second, region)
                // Android's picker hands Porch the one number tapped, without the contact's others.
                update { it.someoneNew(picked.first?.takeIf { name -> name.isNotBlank() } ?: it.name).copy(numbers = listOf(number), viaPhone = true) }
            } catch (e: ValidationException) {
                admin.error = e.message
            }
        }
    }
    val key = draft.key?.takeIf { draft.fromKeyTile }?.let(CallSlots::symbol)
    FormScreen(title, navigation = { TextButton(onClick = onCancel) { Text("Cancel") } }) {
        StepBars(1)
        Heading(if (key != null) "Who goes on key $key?" else "Who are you adding?")
        val slots = admin.slots
        val people = admin.state(links)?.people.orEmpty().filter { it.role == PorchExperience.FAMILY && keyFor(slots, it) == null }
        // Someone already on Porch is added only to put them on a key.
        if (draft.key != null && people.isNotEmpty()) CaregiverGroup("On Porch") {
            people.forEachIndexed { index, person ->
                if (index > 0) HorizontalDivider()
                CaregiverRow(onClick = { onMember(person) }) {
                    Avatar(person.name, memberPhoto(app, admin, person), 44.dp)
                    Text(person.name, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    Chevron()
                }
            }
        }
        CaregiverGroup("Someone new") {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                FormButton("Choose from Contacts", filled = false, icon = R.drawable.ic_account, onClick = {
                    try { pickContact.launch(Unit) } catch (_: ActivityNotFoundException) { admin.error = "This tablet has no contacts app. Type the number instead." }
                })
                FormField(draft.name, { typed -> update { it.copy(name = typed) } }, "Name", "For example, David",
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
            }
        }
        FormButton("Next", enabled = draft.name.isNotBlank(), onClick = onNext)
        if (key != null) FormLink("Use key $key for something else", onClick = onSomethingElse)
    }
}

// MARK: Step 2

@Composable
private fun ReachStep(admin: CaregiverAdmin, draft: AddSomeoneDraft, title: String, lovedOne: String, region: String,
    update: ((AddSomeoneDraft) -> AddSomeoneDraft) -> Unit, onBack: () -> Unit, onNext: () -> Unit) {
    var typed by rememberSaveable { mutableStateOf(draft.numbers.firstOrNull()?.let(::displayNumber).orEmpty()) }
    var bad by rememberSaveable { mutableStateOf(false) }
    // Porch calls a phone from a key, so someone who isn't on the keypad can't be reached by phone.
    val phoneAllowed = draft.key != null
    val phone = draft.viaPhone && phoneAllowed
    val first = draft.firstName
    FormScreen(title, navigation = { BackButton(onBack) }) {
        StepBars(2)
        Heading("How should $lovedOne reach $first?")
        OptionCard("Phone", null, R.drawable.ic_call, phone, enabled = phoneAllowed, onChange = { on -> update { it.copy(viaPhone = on) } }) {
            if (phone) Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                PorchTextField(typed, { typed = it; bad = false }, "$first's phone number",
                    Modifier.fillMaxWidth().semantics { contentDescription = "$first's phone number" }, placeholder = { Text("Phone number") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), isError = bad)
                if (bad) Text(PhoneNumberList.badNumber, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
        }
        OptionCard("Porch app", "Video calls, photos and messages", R.drawable.ic_videocam, draft.viaApp, onChange = { on -> update { it.copy(viaApp = on) } })
        FormButton("Next", onClick = {
            when {
                !phone && !draft.viaApp -> admin.error = AddSomeoneDraft.unreachable
                phone -> try { update { it.reaching(typed, region) }; onNext() } catch (_: ValidationException) { bad = true }
                else -> { update { it.copy(numbers = emptyList(), viaPhone = false) }; onNext() }
            }
        })
    }
}

/** A choice of how to reach them: a checkbox, its icon and its name, outlined in the accent color when it's chosen.
 * `content` shows under it, such as the number for Phone. */
@Composable
private fun OptionCard(title: String, detail: String?, @DrawableRes icon: Int, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit,
    content: @Composable ColumnScope.() -> Unit = {}) {
    val colors = MaterialTheme.colorScheme
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), tonalElevation = 2.dp,
        border = if (checked) BorderStroke(2.dp, colors.primary) else null) {
        Column {
            Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).toggleable(checked, enabled = enabled, role = Role.Checkbox, onValueChange = onChange)
                .alpha(if (enabled) 1f else 0.5f).padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Checkbox(checked, onCheckedChange = null, enabled = enabled)
                Icon(painterResource(icon), contentDescription = null, Modifier.size(24.dp), tint = colors.primary)
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleMedium)
                    detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant) }
                }
            }
            content()
        }
    }
}

// MARK: Step 3

/** Button colors that keep a name readable, as Step 3 offers them, after the bedside's own. */
private val swatches = listOf(null to "Default color", "1565C0" to "Blue", "00838F" to "Teal", "EF6C00" to "Orange", "C62828" to "Red", "6A1B9A" to "Purple")

@Composable
private fun CheckStep(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, draft: AddSomeoneDraft, photo: AddSomeonePhoto, title: String,
    lovedOne: String, region: String, saving: Boolean, update: ((AddSomeoneDraft) -> AddSomeoneDraft) -> Unit, onBack: () -> Unit,
    onOpen: (AddScreen) -> Unit, onSave: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val prepared = FamilyPhotos.prepared(context, uri)
            if (prepared != null) photo.data = prepared else admin.error = "That photo couldn't be opened. Please choose another photo."
        }
    }
    // A family member's key shows their photo from Porch.
    val person = draft.memberID?.let { id -> admin.state(links)?.people?.firstOrNull { it.id == id } }
    val shown = if (person != null) memberPhoto(app, admin, person) else if (draft.member) null else photo.data
    val key = draft.key?.let(CallSlots::symbol)
    FormScreen(title, navigation = { BackButton(onBack, enabled = !saving) }) {
        StepBars(3)
        Heading(if (key != null) "Check key $key" else "Check ${draft.firstName}")
        if (key != null) {
            Text("On $lovedOne's screen", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            KeyPreview(draft.name.trim(), shown, key, buttonColor(draft.colorHex))
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(8.dp),
                itemVerticalAlignment = Alignment.CenterVertically) {
                if (!draft.member) OutlinedButton(onClick = {
                    try { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                    catch (_: ActivityNotFoundException) { admin.error = "No app on this device can choose a photo." }
                }, enabled = !saving, contentPadding = PaddingValues(horizontal = 14.dp)) {
                    Icon(painterResource(R.drawable.ic_photo), contentDescription = null, Modifier.size(20.dp))
                    Text("Photo", Modifier.padding(start = 8.dp))
                }
                // The colors stay at the right, with or without Photo beside them.
                Row(Modifier.selectableGroup().then(if (draft.member) Modifier.fillMaxWidth() else Modifier), horizontalArrangement = Arrangement.End) {
                    swatches.forEach { (hex, label) ->
                        Swatch(hex, label, selected = draft.colorHex == hex, enabled = !saving) { update { it.copy(colorHex = hex) } }
                    }
                }
            }
        }
        val rows = buildList {
            if (draft.viaApp || draft.member) add(Summary(R.drawable.ic_videocam, "Porch app", draft.porchAppValue, AddScreen.APP))
            if (key != null) {
                val number = draft.phoneValue(region)
                add(Summary(R.drawable.ic_call, "Phone", number ?: "Add", AddScreen.PHONE, accent = number == null))
            }
            add(Summary(R.drawable.ic_dialpad, "Key", key ?: "None", AddScreen.KEY))
        }
        CaregiverGroup {
            rows.forEachIndexed { index, row ->
                if (index > 0) HorizontalDivider()
                SummaryRow(row, enabled = !saving) { onOpen(row.screen) }
            }
        }
        FormButton(when { saving -> "Adding…"; key != null -> "Add to key $key"; else -> "Invite ${draft.firstName}" }, enabled = !saving, onClick = onSave)
    }
}

/** A key's card as the bedside's people screen draws it (BedsidePeople's PersonCard), at a caregiver form's size: the
 * button color with lettering that reads on it, their photo or initials, their name, and the key to press. */
@Composable
private fun KeyPreview(name: String, photo: ByteArray?, key: String, color: Color?) {
    val background = color ?: CallColors.control
    val text = color?.let(::foreground) ?: CallColors.text
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(background).padding(20.dp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (photo != null) Photo(photo, Modifier.size(96.dp))
        else Box(Modifier.size(64.dp).clip(CircleShape).background(text), contentAlignment = Alignment.Center) {
            val initials = name.split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.first().uppercase() }
            Text(initials, Modifier.clearAndSetSemantics {}, color = background, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(name, color = text, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text("Press $key", color = if (color == null) CallColors.secondary else text.copy(alpha = 0.8f), fontSize = 17.sp, fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center)
    }
}

/** One button color: a 30 dp circle in a 40 dp target, ringed in the accent color when it's chosen. */
@Composable
private fun Swatch(hex: String?, label: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Box(Modifier.size(40.dp).clip(CircleShape).selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick)
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        if (selected) Box(Modifier.size(38.dp).border(2.dp, colors.primary, CircleShape))
        Box(Modifier.size(30.dp).clip(CircleShape).background(buttonColor(hex) ?: CallColors.control).border(1.dp, colors.outlineVariant, CircleShape))
    }
}

/** A row of Step 3's card: what it's about, what it's set to, and the screen that changes it. `accent` is for a value
 * that's something to do, such as Add. */
private class Summary(@param:DrawableRes val icon: Int, val title: String, val value: String, val screen: AddScreen, val accent: Boolean = false)

@Composable
private fun SummaryRow(row: Summary, enabled: Boolean, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    CaregiverRow(onClick = if (enabled) onClick else null) {
        Icon(painterResource(row.icon), contentDescription = null, Modifier.size(24.dp), tint = colors.onSurfaceVariant)
        Text(row.title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
        Text(row.value, color = if (row.accent) colors.primary else colors.onSurfaceVariant, style = MaterialTheme.typography.bodyLarge)
        Chevron()
    }
}

// MARK: Step 4

@Composable
private fun InviteStep(draft: AddSomeoneDraft, title: String, onDone: () -> Unit) {
    val context = LocalContext.current
    val first = draft.firstName
    FormScreen(title) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(Modifier.size(64.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
                Icon(painterResource(R.drawable.ic_check), contentDescription = null, Modifier.size(36.dp), tint = Color.White)
            }
        }
        Heading(draft.key?.let { "$first is on key ${CallSlots.symbol(it)}" } ?: "Invite ready", TextAlign.Center)
        draft.link?.let { link ->
            FormCard("Send $first the invite") {
                InvitationCode(link, "Invitation QR code")
                FormButton("Share invite link", onClick = { shareInvitation(context, link) }, icon = R.drawable.ic_share)
                Text("Works once, for 24 hours.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center)
            }
        }
        FormButton("Done", filled = false, onClick = onDone)
    }
}

// MARK: Phone, Porch app and Key

/**
 * The Phone screen: someone's numbers, the one Porch calls first, which any of them can become, and adding, picking and
 * removing them. Add someone changes its draft's numbers here, and a person's page the numbers on their key
 * (PersonPhoneScreen). `problem` shows under the card. Done adds a number still typed, then hands over the numbers.
 */
@Composable
private fun PhoneNumbersScreen(admin: CaregiverAdmin, numbers: List<String>, onChange: (List<String>) -> Unit, lovedOne: String, region: String,
    saving: Boolean, problem: String?, onBack: () -> Unit, onDone: (List<String>) -> Unit) {
    var typed by rememberSaveable { mutableStateOf("") }
    /** Why what's typed or picked can't be added, under the field. */
    var refused by rememberSaveable { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val current by rememberUpdatedState(numbers)
    val pickContact = rememberLauncherForActivityResult(PickPhoneNumber()) { uri ->
        if (uri != null) scope.launch {
            val picked = pickedNumber(context, uri) ?: run { refused = "That contact's number couldn't be read. Type it instead."; return@launch }
            try {
                onChange(PhoneNumberList.picking(current, picked.second, region))
                refused = null
            } catch (e: ValidationException) {
                refused = e.message
            }
        }
    }
    /** The numbers with what's typed added. Null, with why under the field, when it can't be added. */
    fun withTyped(): List<String>? {
        if (typed.isBlank()) return numbers
        return try {
            PhoneNumberList.adding(numbers, typed, region).also { onChange(it); typed = ""; refused = null }
        } catch (e: ValidationException) {
            refused = e.message
            null
        }
    }
    val colors = MaterialTheme.colorScheme
    FormScreen("Phone", navigation = { BackButton(onBack, enabled = !saving) }) {
        CaregiverGroup {
            numbers.forEachIndexed { index, number ->
                if (index > 0) HorizontalDivider()
                val shown = displayNumber(number)
                val calls = index == 0
                CaregiverRow {
                    Row(Modifier.weight(1f).heightIn(min = 48.dp)
                        .selectable(calls, enabled = !saving, role = Role.RadioButton) { onChange(PhoneNumberList.makingPrimary(numbers, number)) },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        RadioButton(calls, onClick = null, enabled = !saving)
                        Text(shown, style = MaterialTheme.typography.titleMedium)
                        if (calls) Text("Porch calls", Modifier.clip(RoundedCornerShape(50)).background(colors.secondaryContainer)
                            .padding(horizontal = 10.dp, vertical = 2.dp), color = colors.onSecondaryContainer, style = MaterialTheme.typography.labelMedium)
                    }
                    IconButton(onClick = { onChange(numbers - number) }, enabled = !saving) {
                        Icon(painterResource(R.drawable.ic_close), contentDescription = "Remove $shown", tint = colors.onSurfaceVariant)
                    }
                }
            }
            if (numbers.isNotEmpty()) HorizontalDivider()
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                PorchTextField(typed, { typed = it; refused = null }, "Add a number", Modifier.weight(1f), enabled = !saving,
                    placeholder = { Text("Add a number") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), isError = refused != null)
                OutlinedButton(onClick = { withTyped() }, enabled = !saving) { Text("Add") }
            }
            refused?.let { Text(it, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), color = colors.error, style = MaterialTheme.typography.bodyMedium) }
            HorizontalDivider()
            // Android's picker hands Porch the one number tapped, without the contact's others.
            CaregiverRow(onClick = if (saving) null else ({
                try { pickContact.launch(Unit) } catch (_: ActivityNotFoundException) { admin.error = "This tablet has no contacts app. Type the number instead." }
            })) {
                Icon(painterResource(R.drawable.ic_account), contentDescription = null, Modifier.size(24.dp), tint = colors.primary)
                Text("Choose from Contacts", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, color = colors.primary)
            }
        }
        problem?.let { Text(it, color = colors.error, style = MaterialTheme.typography.bodyMedium) }
        Text("All of these can call $lovedOne.", style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
        FormButton(if (saving) "Saving…" else "Done", enabled = !saving, onClick = { withTyped()?.let(onDone) })
    }
}

/**
 * The numbers of someone already on a key, from their page's Phone row: the Phone screen on a copy, which Back leaves
 * as it was. Done approves the number Porch calls with the server, so one it can't call is refused while the caregiver
 * is here, moves a phone drop-in approval to it, then saves the key with only its numbers changed.
 */
@Composable
internal fun PersonPhoneScreen(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, key: Int, contact: CallContact, onDone: () -> Unit) {
    var numbers by rememberSaveable { mutableStateOf(contact.phoneNumbers) }
    var problem by rememberSaveable { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    val region = remember { homeRegion() }
    BackHandler { if (!saving) onDone() }

    /** Moves a phone drop-in approval to the new number Porch calls, or withdraws it when there's none. False, with the
     * reason shown, when it can't. */
    suspend fun followDropIn(previous: String?, number: String?): Boolean {
        if (previous == null || previous == number) return true
        if (app.coordinator.links.value.state?.phoneDropIns.orEmpty().none { it.number == previous }) return true
        val values = if (number != null) {
            // A drop-in answers on this tablet, so it needs its own microphone.
            if (!mediaAccess.granted(false)) {
                admin.error = "Allow the microphone in the tablet's settings before approving drop-in."
                return false
            }
            mapOf("number" to JsonPrimitive(number), "name" to JsonPrimitive(contact.name), "enabled" to JsonPrimitive(true),
                "replacing" to JsonPrimitive(previous))
        } else mapOf("number" to JsonPrimitive(previous), "enabled" to JsonPrimitive(false))
        return admin.send("setPhoneDropIn", values)
    }
    fun save(changed: List<String>) {
        if (saving) return
        val saved = contact
        if (changed == saved.phoneNumbers) { onDone(); return }
        PhoneNumberList.missing(changed, saved)?.let { problem = it; return }
        saving = true
        scope.launch {
            try {
                changed.firstOrNull()?.let { PhoneApprovals.authorize(app, it, refresh = true) }
                if (!followDropIn(saved.phoneNumber, changed.firstOrNull())) return@launch
                val updated = CallContact(name = saved.customName, nativeCall = saved.nativeCall, phoneNumber = changed.firstOrNull(),
                    otherPhoneNumbers = changed.drop(1), familyMemberID = saved.familyMemberID, invitationID = saved.invitationID,
                    memberName = saved.memberName, buttonColorHex = saved.buttonColorHex, photoData = saved.customPhotoData)
                if (admin.saveSlots { it.setContact(updated, key) }) onDone()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                admin.error = e.message ?: "Couldn't save this number. Check your internet and try again."
            } finally {
                saving = false
            }
        }
    }
    PhoneNumbersScreen(admin, numbers, { numbers = it; problem = null }, lovedOne(admin, links), region, saving, problem,
        onBack = { if (!saving) onDone() }, onDone = ::save)
}

/** How their calls start and, for someone invited, the drop-in their invitation approves. */
@Composable
private fun AppScreen(draft: AddSomeoneDraft, lovedOne: String, update: ((AddSomeoneDraft) -> AddSomeoneDraft) -> Unit, onBack: () -> Unit) {
    FormScreen("Porch app", navigation = { BackButton(onBack) }) {
        CaregiverGroup("Calls start with") {
            Box(Modifier.padding(16.dp)) {
                Choices(listOf("Voice", "Video"), if (draft.video) 1 else 0, Modifier.fillMaxWidth()) { choice -> update { it.copy(video = choice == 1) } }
            }
        }
        if (draft.inviting) CaregiverGroup("Drop-in", "Connects without $lovedOne answering.") {
            ToggleRow("Audio", draft.dropInAudio, { on -> update { it.copy(dropInAudio = on) } })
            HorizontalDivider()
            ToggleRow("Video", draft.dropInVideo, { on -> update { it.copy(dropInVideo = on) } })
        }
        FormButton("Done", onClick = onBack)
    }
}

/** Which key they go on, from the keys with nothing on them. Keys in use say who or what is on them. */
@Composable
private fun KeyScreen(admin: CaregiverAdmin, draft: AddSomeoneDraft, update: ((AddSomeoneDraft) -> AddSomeoneDraft) -> Unit, onBack: () -> Unit) {
    var chosen by rememberSaveable { mutableStateOf(draft.key) }
    val slots = admin.slots
    FormScreen("Key", navigation = { BackButton(onBack) }) {
        Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AddSomeoneDraft.keypadOrder.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { digit ->
                        // The key Add someone was opened from is theirs to take, whatever it does now.
                        val free = slots.action(digit) == KeypadAction.UNASSIGNED || digit == draft.tile
                        val label = if (digit == chosen) draft.firstName else occupant(slots, digit)
                        KeyChoice(CallSlots.symbol(digit), label, selected = digit == chosen, enabled = free, Modifier.weight(1f).fillMaxHeight()) { chosen = digit }
                    }
                }
            }
        }
        FormButton("Done", onClick = { update { it.copy(key = chosen) }; onBack() })
        // Porch calls a phone from a key, and someone already on Porch is added only to put them on one.
        if (draft.numbers.isEmpty() && draft.inviting) FormLink("Not on the keypad", onClick = { update { it.copy(key = null) }; onBack() })
    }
}

/** Who or what is on a key. */
private fun occupant(slots: CallSlots, digit: Int): String = when (slots.action(digit)) {
    KeypadAction.PERSON -> slots.contact(digit)?.name.orEmpty()
    KeypadAction.CALL_CONTROL -> "Answer / hang up"
    KeypadAction.TOGGLE_VIDEO -> "Video on / off"
    KeypadAction.MESSAGES -> "Messages"
    KeypadAction.UNASSIGNED, null -> ""
}

/** One key to choose: its symbol in the corner and who's on it. A key in use is greyed and can't be chosen. */
@Composable
private fun KeyChoice(key: String, label: String, selected: Boolean, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(16.dp)
    Box(modifier.heightIn(min = 88.dp).clip(shape).background(if (enabled) colors.surface else colors.surfaceContainerHighest)
        .border(if (selected) 3.dp else 1.dp, if (selected) colors.primary else colors.outlineVariant, shape)
        .selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick)
        .semantics { contentDescription = if (label.isEmpty()) "Key $key" else "Key $key, $label" }) {
        val tint = if (enabled) 1f else 0.5f
        Text(key, Modifier.padding(start = 12.dp, top = 8.dp).alpha(tint).clearAndSetSemantics {}, color = colors.primary, fontSize = 17.sp,
            fontWeight = FontWeight.Bold)
        Text(label, Modifier.align(Alignment.Center).padding(start = 8.dp, top = 24.dp, end = 8.dp, bottom = 8.dp).alpha(tint).clearAndSetSemantics {},
            color = colors.onSurface, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center, maxLines = 2)
    }
}

// MARK: What a key does

private val keyActions = listOf(KeypadAction.CALL_CONTROL to "Answer / hang up", KeypadAction.TOGGLE_VIDEO to "Video on / off",
    KeypadAction.MESSAGES to "Play messages", KeypadAction.UNASSIGNED to "Nothing")

/** What a key does other than call someone. Opened from the key itself (`control`), it can put someone on it instead. */
@Composable
private fun KeyActionScreen(admin: CaregiverAdmin, key: Int, control: Boolean, onBack: () -> Unit, onSomeone: () -> Unit, onSaved: () -> Unit) {
    val symbol = CallSlots.symbol(key)
    var choice by rememberSaveable(key) { mutableStateOf(admin.slots.action(key)?.takeIf { it != KeypadAction.PERSON } ?: KeypadAction.UNASSIGNED) }
    FormScreen("Key $symbol", navigation = { BackButton(onBack) }) {
        Heading("What should key $symbol do?")
        if (control) CaregiverGroup {
            CaregiverRow(onClick = onSomeone) {
                Text("Someone", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                Chevron()
            }
        }
        CaregiverGroup {
            Column(Modifier.selectableGroup()) {
                keyActions.forEachIndexed { index, (action, title) ->
                    if (index > 0) HorizontalDivider()
                    CaregiverRow(onClick = { choice = action }) {
                        RadioButton(choice == action, onClick = null)
                        Text(title, style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
        FormButton("Save", onClick = { if (admin.saveSlots { it.setContact(null, key); it.setAction(choice, key) }) onSaved() })
    }
}

// MARK: Shared pieces

/** Who the bedside is for, as the screens here name them: the household's name, or "your loved one". */
private fun lovedOne(admin: CaregiverAdmin, links: FamilyLinks): String = admin.state(links)?.householdName?.takeIf { it.isNotBlank() } ?: "your loved one"

/** Where a screen is in the three steps: a bar for each, filled up to this one. */
@Composable
private fun StepBars(step: Int) {
    val colors = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "Step $step of 3" }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(3) { index ->
            Box(Modifier.weight(1f).height(4.dp).clip(RoundedCornerShape(2.dp)).background(if (index < step) colors.primary else colors.outlineVariant))
        }
    }
}

@Composable
private fun Heading(text: String, align: TextAlign = TextAlign.Start) {
    Text(text, Modifier.fillMaxWidth().semantics { heading() }, style = MaterialTheme.typography.headlineMedium, textAlign = align)
}

@Composable
private fun BackButton(onBack: () -> Unit, enabled: Boolean = true) {
    TextButton(onClick = onBack, enabled = enabled) { Text("Back") }
}

/** The row opens another screen. */
@Composable
private fun Chevron() {
    Text("›", Modifier.clearAndSetSemantics {}, fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
}
