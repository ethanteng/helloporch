package com.ethanteng.helloporch

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PhoneNumberNormalization
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.ValidationException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/**
 * What a key does, as iOS's SetupViewController sets it: no action, a call control, or a person, with how Porch reaches
 * them, their photo and their button color. With `contact`, it edits that person's phone numbers only, as the person
 * page's Phone row opens it. Saving a number asks the server to approve it for calls, so a number it can't call is
 * refused now, while the caregiver is here.
 */
@Composable
fun KeyEditor(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, slot: Int, contact: CallContact?, initialAction: KeypadAction, onDone: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val editingNumbers = contact != null
    val key = CallSlots.symbol(slot)
    val region = remember { homeRegion() }
    var action by rememberSaveable { mutableStateOf(initialAction) }
    var name by rememberSaveable { mutableStateOf(contact?.customName.orEmpty()) }
    var selectedFamilyID by rememberSaveable { mutableStateOf(contact?.familyMemberID) }
    var invitationID by rememberSaveable { mutableStateOf(contact?.invitationID) }
    var memberName by rememberSaveable { mutableStateOf(contact?.memberName) }
    // A new person's calls start with video.
    var video by rememberSaveable { mutableStateOf(contact?.nativeCall?.mode != NativeCall.Mode.VOICE) }
    var callPhone by rememberSaveable { mutableStateOf(!contact?.phoneNumber.isNullOrEmpty()) }
    var phone by rememberSaveable { mutableStateOf(contact?.phoneNumber.orEmpty()) }
    var otherNumbers by rememberSaveable { mutableStateOf(contact?.otherPhoneNumbers.orEmpty()) }
    var otherField by rememberSaveable { mutableStateOf("") }
    var buttonColorHex by rememberSaveable { mutableStateOf(contact?.buttonColorHex) }
    var photoData by remember { mutableStateOf(contact?.customPhotoData) }
    /** The number approved for phone drop-in when the editor opened. A changed primary number takes the approval with it. */
    var approvedNumber by remember { mutableStateOf(contact?.phoneNumber?.takeIf { number -> links.state?.phoneDropIns.orEmpty().any { it.number == number } }) }
    var saving by remember { mutableStateOf(false) }
    var inviting by rememberSaveable { mutableStateOf(false) }
    var choosingColor by remember { mutableStateOf(false) }

    val state = links.state
    val people = state?.people.orEmpty().filter { it.role == PorchExperience.FAMILY }
    // An accepted invitation links the key to its family member, and a family member who left unlinks it.
    LaunchedEffect(people, invitationID) {
        invitationID?.let { id -> people.firstOrNull { it.invitationID == id } }?.let { selectedFamilyID = it.id }
        if (selectedFamilyID != null && state != null && people.none { it.id == selectedFamilyID }) selectedFamilyID = null
    }
    val linkedPerson = selectedFamilyID?.let { id -> people.firstOrNull { it.id == id } }
    val linked = selectedFamilyID != null || invitationID != null
    val pending = invitationID?.let { id -> state?.invitations.orEmpty().any { it.id == id } } ?: false
    val knownName = linkedPerson?.name ?: memberName
    val nameHidden = linked && !knownName.isNullOrBlank()

    BackHandler(enabled = !inviting, onBack = onDone)
    if (inviting) {
        InviteScreen(app, admin, prefilledName = name.trim().ifEmpty { memberName }, returnsToPerson = true, onDone = { inviting = false },
            onCreated = { id, invited -> invitationID = id; memberName = invited; name = ""; selectedFamilyID = null })
        return
    }

    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val prepared = FamilyPhotos.prepared(context, uri)
            if (prepared != null) photoData = prepared else admin.error = "That photo couldn't be opened. Please choose another photo."
        }
    }
    val pickContact = rememberLauncherForActivityResult(PickPhoneNumber()) { uri ->
        if (uri != null) scope.launch {
            val picked = pickedNumber(context, uri) ?: run { admin.error = "That contact's number couldn't be read. Type it instead."; return@launch }
            try {
                val primary = PhoneNumberNormalization.e164(picked.second, region)
                phone = primary
                otherNumbers = otherNumbers - primary
                if (!linked && !editingNumbers && picked.first != null) name = picked.first.orEmpty()
                callPhone = true
            } catch (e: ValidationException) {
                admin.error = e.message
            }
        }
    }
    fun chooseContact() {
        // Android's picker hands Porch the one number tapped, without access to the rest of the contacts.
        try { pickContact.launch(Unit) } catch (_: ActivityNotFoundException) { admin.error = "This tablet has no contacts app. Type the number instead." }
    }

    /** Adds what's typed under Other numbers. */
    fun takeOtherNumber() {
        val typed = otherField.trim()
        if (typed.isEmpty()) return
        val number = PhoneNumberNormalization.e164(typed, region)
        val primary = runCatching { PhoneNumberNormalization.e164(phone, region) }.getOrNull()
        if (number == primary || number in otherNumbers) throw ValidationException("That number is already saved for them.")
        if (otherNumbers.size + 1 >= CallContact.maximumPhoneNumbers) throw ValidationException("Save up to ${CallContact.maximumPhoneNumbers} phone numbers for one person.")
        otherNumbers = otherNumbers + number
        otherField = ""
    }
    /** Moves a phone drop-in approval to the new primary number, or withdraws it when there's none. */
    suspend fun syncPhoneDropIn(number: String?, name: String): Boolean {
        val previous = approvedNumber ?: return true
        if (previous == number) return true
        val values: Map<String, JsonElement> = if (number != null) {
            // A drop-in answers on this tablet, so it needs its own microphone.
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                admin.error = "Allow the microphone in the tablet's settings before approving drop-in."
                return false
            }
            mapOf("number" to JsonPrimitive(number), "name" to JsonPrimitive(name), "enabled" to JsonPrimitive(true), "replacing" to JsonPrimitive(previous))
        } else mapOf("number" to JsonPrimitive(previous), "enabled" to JsonPrimitive(false))
        if (!admin.send("setPhoneDropIn", values)) return false
        approvedNumber = number
        return true
    }
    /** The person as the form says, or why they can't be saved. */
    fun person(): CallContact {
        if (callPhone) takeOtherNumber()
        if (!linked && !callPhone) throw ValidationException("Invite them to Porch or add a phone number so Porch can reach this person.")
        val ownDetails = editingNumbers || !linked
        val typedName = name.trim()
        val knownMemberName = knownName?.trim()
        val supplyingName = knownMemberName.isNullOrEmpty() && !ownDetails && !nameHidden
        if (supplyingName && typedName.length > 80) throw ValidationException("Use a name with 80 characters or fewer.")
        val pendingName = if (!knownMemberName.isNullOrEmpty()) knownMemberName else if (supplyingName) typedName else null
        val call = NativeCall(contact?.nativeCall?.room ?: newRoom(), if (video) NativeCall.Mode.VIDEO else NativeCall.Mode.VOICE)
        return CallContact(name = if (ownDetails) name else "", nativeCall = call,
            phoneNumber = if (callPhone) PhoneNumberNormalization.e164(phone, region) else null,
            otherPhoneNumbers = if (callPhone) otherNumbers else emptyList(), familyMemberID = selectedFamilyID, invitationID = invitationID,
            memberName = pendingName, buttonColorHex = buttonColorHex, photoData = if (ownDetails) photoData else null)
    }
    fun save() {
        if (saving) return
        if (action != KeypadAction.PERSON) {
            val chosen = action
            saving = true
            admin.launch {
                try {
                    if (syncPhoneDropIn(null, "") && saveSlots { it.setContact(null, slot); it.setAction(chosen, slot) }) onDone()
                } finally {
                    saving = false
                }
            }
            return
        }
        val saved = try { person() } catch (e: Exception) { admin.error = e.message; return }
        phone = saved.phoneNumber.orEmpty()
        otherNumbers = saved.otherPhoneNumbers
        saving = true
        admin.launch {
            try {
                saved.phoneNumber?.let { PhoneApprovals.authorize(app, it, refresh = true) }
                if (syncPhoneDropIn(saved.phoneNumber, saved.name) && saveSlots { it.setContact(saved, slot); it.setAction(KeypadAction.PERSON, slot) }) onDone()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Couldn't save this number. Check your internet and try again."
            } finally {
                saving = false
            }
        }
    }

    FormScreen(if (editingNumbers) "Phone" else "Key $key", navigation = { TextButton(onClick = onDone) { Text("Cancel") } }) {
        if (!editingNumbers) {
            FormSection("What key $key does") {
                CaregiverGroup {
                    KeypadAction.entries.forEachIndexed { index, choice ->
                        if (index > 0) HorizontalDivider()
                        CaregiverRow(onClick = { action = choice }) {
                            RadioButton(choice == action, onClick = null)
                            Text(choice.title, style = MaterialTheme.typography.titleMedium)
                        }
                    }
                }
            }
        }
        val person = action == KeypadAction.PERSON
        if (person && !editingNumbers) {
            FormSection("Their details") {
                val status = when {
                    selectedFamilyID != null -> "${knownName ?: "They"}'s Porch app is connected"
                    pending -> "Waiting for ${knownName ?: "them"} to accept the invite"
                    invitationID != null -> "Invite expired or cancelled. Send a new invite."
                    else -> null
                }
                status?.let { Text(it, Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium) }
                if (selectedFamilyID == null && !pending && people.isNotEmpty()) {
                    Box {
                        var open by remember { mutableStateOf(false) }
                        FormButton("Choose from Family on Porch", filled = false, onClick = { open = true })
                        DropdownMenu(open, onDismissRequest = { open = false }) {
                            people.forEach { member ->
                                DropdownMenuItem(text = { Text(member.name) }, onClick = {
                                    open = false
                                    selectedFamilyID = member.id; invitationID = member.invitationID; memberName = member.name
                                })
                            }
                        }
                    }
                }
                if (selectedFamilyID == null && !pending) {
                    FormButton(if (invitationID == null) "Invite them" else "Invite again", filled = false, onClick = { inviting = true })
                }
                if (!nameHidden) {
                    FormField(name, { name = it }, "Name", "For example, David", keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
                }
                FormButton("Choose from Contacts", filled = false, onClick = ::chooseContact)
                if (linked) {
                    Text("Calls start as", style = MaterialTheme.typography.titleMedium)
                    Choices(listOf("Voice", "Video"), if (video) 1 else 0, Modifier.fillMaxWidth()) { video = it == 1 }
                }
            }
            FormSection("Photo & button color") {
                val memberPhotoID = if (linkedPerson != null) linkedPerson.photoID else if (selectedFamilyID == null) null else contact?.memberPhotoID
                val memberPhoto = remember(memberPhotoID, FamilyPhotos.saved) { FamilyPhotos.data(app, memberPhotoID) }
                // Someone on Porch shows their Porch photo. Someone who isn't shows the one chosen here.
                val fallback = if (photoData == null || linked) memberPhoto else null
                val preview = if (linked) fallback else photoData ?: fallback
                if (preview != null) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Photo(preview, Modifier.size(240.dp)) }
                if (linked && fallback != null) Text("Their photo from Porch", Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                if (!linked) {
                    FormButton(if (photoData != null) "Change photo" else "Add photo", filled = false,
                        onClick = { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })
                    if (photoData != null) FormButton("Remove photo", filled = false, onClick = { photoData = null })
                }
                val color = buttonColor(buttonColorHex)
                OutlinedButton(onClick = { choosingColor = true }, Modifier.fillMaxWidth().heightIn(min = 50.dp)
                    .semantics { contentDescription = "Choose button color, " + (buttonColorHex?.let { "color #$it" } ?: "default color") },
                    colors = if (color != null) ButtonDefaults.outlinedButtonColors(containerColor = color, contentColor = foreground(color)) else ButtonDefaults.outlinedButtonColors()) {
                    Text("Choose button color", style = MaterialTheme.typography.titleMedium)
                }
                if (buttonColorHex != null) FormButton("Use default color", filled = false, onClick = { buttonColorHex = null })
            }
        }
        if (person) {
            FormSection("Phone") {
                if (linked && callPhone) {
                    Text("If Porch isn't answered in ${CallPreferences.fallbackSeconds(app.settings)} seconds, Porch calls this phone. Voice only.",
                        Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                }
                CaregiverGroup { ToggleRow("Call their phone", callPhone, { callPhone = it }) }
                if (callPhone) {
                    val numberKeyboard = KeyboardOptions(keyboardType = KeyboardType.Phone)
                    FormField(phone, { phone = it }, "Primary number", "+14158676937", keyboardOptions = numberKeyboard)
                    Text("Start international numbers with +.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Other numbers", style = MaterialTheme.typography.titleMedium)
                    CaregiverGroup {
                        if (otherNumbers.isEmpty()) CaregiverRow { Text("None", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        otherNumbers.forEachIndexed { index, number ->
                            if (index > 0) HorizontalDivider()
                            val shown = displayNumber(number)
                            CaregiverRow {
                                Text(shown, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                                TextButton(onClick = {
                                    val previous = runCatching { PhoneNumberNormalization.e164(phone, region) }.getOrNull()
                                    otherNumbers = otherNumbers.mapNotNull { if (it == number) previous else it }
                                    phone = number
                                }, Modifier.semantics { contentDescription = "Make $shown the primary number" }) { Text("Make primary") }
                                TextButton(onClick = { otherNumbers = otherNumbers - number },
                                    Modifier.semantics { contentDescription = "Remove $shown" },
                                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Remove") }
                            }
                        }
                    }
                    FormField(otherField, { otherField = it }, "Add another number", "+14155550123", keyboardOptions = numberKeyboard)
                    Text("These can call in. Porch only calls the primary number.", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    FormButton("Add number", filled = false, onClick = {
                        try { takeOtherNumber() } catch (e: ValidationException) { admin.error = e.message }
                    })
                }
            }
        }
        if (editingNumbers) FormButton("Choose from Contacts", filled = false, onClick = ::chooseContact)
        FormButton(if (saving) "Saving…" else "Save", enabled = !saving && !admin.busy, onClick = ::save)
    }
    if (choosingColor) ButtonColorDialog(buttonColorHex, onDismiss = { choosingColor = false }, onChoose = { buttonColorHex = it; choosingColor = false })
}

/** Android's contact picker, showing only contacts' phone numbers. Porch may read the one number tapped. */
private class PickPhoneNumber : ActivityResultContract<Unit, Uri?>() {
    override fun createIntent(context: Context, input: Unit) = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
    override fun parseResult(resultCode: Int, intent: Intent?): Uri? = intent?.data?.takeIf { resultCode == Activity.RESULT_OK }
}

/** The picked contact's name and the number tapped. */
private suspend fun pickedNumber(context: Context, uri: Uri): Pair<String?, String>? = withContext(Dispatchers.IO) {
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
