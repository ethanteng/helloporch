package com.ethanteng.helloporch

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import android.icu.text.DateFormat as IcuDateFormat
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
        PeopleRoute.Kind.INVITE -> InviteScreen(app, admin, links, onDone = close)
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

// MARK: Inviting

/**
 * A new invitation, as iOS's FamilyInviteViewController makes it: who it's for, drop-in, and caregiver mode. Once it's
 * made, it shows its code for a phone's camera, and can send it. Made on a caregiver's phone, the drop-in it approves
 * still answers on the bedside, so the phone doesn't ask for its own microphone. The bedside adds someone with Add
 * someone instead.
 */
@Composable
fun InviteScreen(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mediaAccess = rememberMediaAccess(admin.onBedside)
    var name by rememberSaveable { mutableStateOf("") }
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
        // It finds its key by name once they join (`CallSlots.followInvitations`).
        FormSection("Who is this invitation for?", "If they're on the keypad, use the name on their key.") {
            FormField(name, { name = it }, "Their name", "For example, Ethan", enabled = !made,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        }
        CaregiverGroup("Approve drop-in", "Connects without ${lovedOne(admin, links)} answering.") {
            ToggleRow("Audio drop-in", audio, { audio = it }, enabled = !made)
            HorizontalDivider()
            ToggleRow("Video drop-in", video, { video = it }, enabled = !made)
        }
        CaregiverGroup("Caregiver mode", "Can change settings from their phone.") {
            ToggleRow("Caregiver mode", caregiver, { caregiver = it }, enabled = !made)
        }
        val shown = link?.takeIf { expiresAt > System.currentTimeMillis() / 1000 }
        if (shown != null) {
            InvitationCode(shown, "QR code for ${name.trim().ifEmpty { "their" }} invitation")
            Text("Invitation ready. Show them this code or share it, then tap Done.",
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
internal fun linked(contact: CallContact, memberID: String? = null, invitationID: String?, name: String): CallContact =
    CallContact(name = "", nativeCall = contact.nativeCall, phoneNumber = contact.phoneNumber, otherPhoneNumbers = contact.otherPhoneNumbers,
        familyMemberID = memberID, invitationID = invitationID, memberName = name, buttonColorHex = contact.buttonColorHex, photoData = contact.customPhotoData)

/** A new key's own call room. */
internal fun newRoom(): String = "contact-" + UUID.randomUUID().toString().take(8).lowercase()

/** The tablet's country, for numbers typed without a country code. */
internal fun homeRegion(): String = Locale.getDefault().country.ifEmpty { "US" }

/** Android's contact picker, showing only contacts' phone numbers. Porch may read the one number tapped. */
internal class PickPhoneNumber : ActivityResultContract<Unit, Uri?>() {
    override fun createIntent(context: Context, input: Unit) = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
    override fun parseResult(resultCode: Int, intent: Intent?): Uri? = intent?.data?.takeIf { resultCode == Activity.RESULT_OK }
}

/** The picked contact's name and the number tapped. */
internal suspend fun pickedNumber(context: Context, uri: Uri): Pair<String?, String>? = withContext(Dispatchers.IO) {
    try {
        val columns = arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER)
        context.contentResolver.query(uri, columns, null, null, null)?.use { row ->
            if (!row.moveToFirst()) return@use null
            val number = row.getString(1)?.takeIf { it.isNotBlank() } ?: return@use null
            row.getString(0) to number
        }
    } catch (_: SecurityException) {
        null
    }
}

/** A number as people read it: national at home, international otherwise. */
internal fun displayNumber(e164: String): String = PhoneNumberNormalization.display(e164, homeRegion())

/** A key's button color, or null for the default. */
internal fun buttonColor(hex: String?): Color? =
    hex?.takeIf { it.length == 6 }?.toLongOrNull(16)?.let { Color(0xFF000000 or it) }

/** Black or white, whichever reads better on `color`. */
internal fun foreground(color: Color): Color = if (color.luminance() > 0.179f) Color.Black else Color.White
