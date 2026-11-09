package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.annotation.DrawableRes
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ethanteng.helloporch.core.BedsideAttendance
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyInvitation
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyNames
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.RemoteCaregiverSession
import com.ethanteng.helloporch.core.joinFamily
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Family mode's screens: joining a family from an invitation, the families this phone is in, a family's messages with
 * the bedside and recording one, and caregiver mode for one of them. Setup links go to the bedside's screens instead
 * (PorchRoot). `onReady` says whether the list of families, the messages or caregiver mode is showing, which is where a
 * call could ring. A call takes over the screen and closes caregiver mode, and a message not yet sent. */
@Composable
fun FamilyScreens(app: PorchApplication, link: String?, onLinkHandled: () -> Unit, onReady: (Boolean) -> Unit = {}) {
    val links by app.coordinator.links.collectAsStateWithLifecycle()
    var joining by rememberSaveable { mutableStateOf(false) }
    // The family caregiver mode is open for, by device ID, and why it last ended on its own, such as a changed PIN.
    var caregiving by rememberSaveable { mutableStateOf<String?>(null) }
    var caregiverNotice by rememberSaveable { mutableStateOf<String?>(null) }
    var about by rememberSaveable { mutableStateOf(false) }
    // A family's messages, by device ID, and a message being recorded for one, and this phone's name and photo in one.
    var thread by rememberSaveable { mutableStateOf<String?>(null) }
    var profile by rememberSaveable { mutableStateOf<String?>(null) }
    var composing by rememberSaveable(stateSaver = composingSaver) { mutableStateOf<Composing?>(null) }
    // Joining or removing a family changes the list before any family has checked in.
    var changes by remember { mutableIntStateOf(0) }
    val families = remember(links, changes) { app.device.families }
    val done = { joining = false; changes++; onLinkHandled() }
    // An invitation opened meanwhile, or the family leaving this phone, ends caregiver mode.
    val caregiverFamily = families.firstOrNull { it.deviceID == caregiving }?.takeIf { link == null && !joining }
    LaunchedEffect(caregiving, caregiverFamily == null) {
        if (caregiving != null && caregiverFamily == null) { RemoteCaregiverSession.shared.end(); caregiving = null }
    }
    val open = link == null && !joining
    val composeFamily = composing?.let { c -> families.firstOrNull { it.deviceID == c.deviceID } }?.takeIf { open && caregiverFamily == null }
    val threadFamily = families.firstOrNull { it.deviceID == thread }?.takeIf { open && caregiverFamily == null && composeFamily == null }
    val profileFamily = families.firstOrNull { it.deviceID == profile }?.takeIf { open && caregiverFamily == null && composeFamily == null && threadFamily == null }
    // A tapped message notification opens that family's thread, as iOS opens it: what else was open closes first,
    // caregiver mode, joining, and a message not yet sent included.
    val notified = app.messageAlerts.opening
    LaunchedEffect(notified, families) {
        val id = notified ?: return@LaunchedEffect
        if (families.any { it.deviceID == id }) {
            composing = null
            profile = null
            about = false
            if (caregiving != null) { RemoteCaregiverSession.shared.end(); caregiving = null }
            joining = false
            if (link != null) onLinkHandled()
            thread = id
        }
        app.messageAlerts.opening = null
    }
    val listing = caregiverFamily == null && composeFamily == null && threadFamily == null && profileFamily == null &&
        !(link != null || joining || families.isEmpty())
    SideEffect { onReady(listing || caregiverFamily != null || threadFamily != null) }
    // A call that didn't go through offers a message instead, as iOS does. Not once that family has left this phone,
    // removed it, or turned messages off: Leave a message would open a composer that can't send.
    app.calls.messageOffer?.takeIf { offer ->
        val link = links.link(offer.family)
        offer.recent && composeFamily == null && caregiverFamily == null &&
            families.any { it.deviceID == offer.family.deviceID } &&
            link?.accessRemoved != true && link?.state?.messagesEnabled != false
    }?.let { offer ->
        AlertDialog(onDismissRequest = { app.calls.messageOffer = null }, title = { Text(offer.title) },
            text = { Text("Leave a message? It waits on their Porch until they play it.") },
            confirmButton = {
                TextButton(onClick = {
                    app.calls.messageOffer = null
                    composing = Composing(offer.family.deviceID, offer.name, "voicemail", startAudio = true)
                }) { Text("Leave a message") }
            },
            dismissButton = { TextButton(onClick = { app.calls.messageOffer = null }) { Text("Not now") } })
    }
    if (caregiverFamily != null) {
        RemoteCaregiverMode(app, caregiverFamily, links, onClose = { reason -> caregiving = null; caregiverNotice = reason })
        return
    }
    if (composeFamily != null) {
        val c = composing!!
        MessageComposerScreen(app, composeFamily, c.recipient, c.kind, c.startAudio, onDone = { composing = null })
        return
    }
    if (threadFamily != null) {
        MessageThreadScreen(app, threadFamily, links, onBack = { thread = null },
            onRecord = { name -> composing = Composing(threadFamily.deviceID, name, "message", startAudio = false) })
        return
    }
    if (profileFamily != null) {
        FamilyProfileScreen(app, profileFamily, links, onBack = { profile = null })
        return
    }
    // From the families, or the join screen, as long as no invitation is waiting.
    if (about && link == null) {
        BackHandler { about = false }
        AboutScreen(navigation = { TextButton(onClick = { about = false }) { Text("Back") } })
        return
    }
    // Titled Porch, as iOS's family screen is.
    FormScreen("Porch") {
        if (!listing) JoinFamily(app, link.orEmpty(), adding = families.isNotEmpty(), onJoined = done, onCancel = if (families.isEmpty()) null else done,
            onAbout = { about = true })
        else Families(app, links, families, onJoinAnother = { joining = true }, onChanged = { changes++ }, onAbout = { about = true },
            onThread = { thread = it.deviceID }, onProfile = { profile = it.deviceID }, onCompose = { family, name -> composing = Composing(family.deviceID, name, "message", startAudio = false) },
            onCaregiver = { family ->
                // Every visit starts with the PIN.
                RemoteCaregiverSession.shared.end()
                caregiving = family.deviceID
            })
    }
    PorchErrorDialog(caregiverNotice) { caregiverNotice = null }
}

@Composable
private fun JoinFamily(app: PorchApplication, initialLink: String, adding: Boolean, onJoined: () -> Unit, onCancel: (() -> Unit)?,
    onAbout: () -> Unit) {
    var text by rememberSaveable(initialLink) { mutableStateOf(initialLink) }
    var nickname by rememberSaveable { mutableStateOf("") }
    // Saved, so turning the phone doesn't hide why a join failed.
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var naming by rememberSaveable(stateSaver = namingSaver) { mutableStateOf<Naming?>(null) }
    val scope = rememberCoroutineScope()
    Text(if (adding) "Join another family" else "Join a family", style = MaterialTheme.typography.headlineMedium)
    Text("Paste the invitation link a caregiver sent you. It works once, for 24 hours.")
    OutlinedTextField(text, { text = it; error = null }, Modifier.fillMaxWidth(), label = { Text("Invitation link") }, singleLine = true)
    if (adding) OutlinedTextField(nickname, { nickname = it }, Modifier.fillMaxWidth(), label = { Text("What you call this family (optional)") }, singleLine = true)
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    FormButton(if (busy) "Joining…" else "Join family", enabled = !busy && text.isNotBlank(), onClick = {
        val invitation = try { FamilyInvitation(text.trim(), BuildConfig.PORCH_SERVER_URL) } catch (e: IllegalArgumentException) { error = e.message; return@FormButton }
        busy = true; error = null
        scope.launch {
            try {
                val joined = joinFamily(invitation, nickname.ifBlank { null }, app.device, app.coordinator, { app.service(it) }, { app.service(it) })
                // Joining makes a tablet a family device, so a Cell2Jack it was using as the bedside stops. joinFamily
                // writes the mode without switchExperience, so the screens have to be told or they stay on the welcome
                // screen until the next check-in.
                app.stopCell2Jack()
                app.noteModeChanged()
                val shared = joined.sharedName; val numbered = joined.numberedName
                if (shared != null && numbered != null) naming = Naming(joined.credential.deviceID, shared, numbered) else onJoined()
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Couldn't join. Check the connection and try again." }
            finally { busy = false }
        }
    })
    onCancel?.let { FormLink("Cancel", onClick = it) }
    // The licenses, before a phone has joined any family.
    if (!adding) FormLink("About Porch", onClick = onAbout)
    naming?.let { NameFamily(app, it, onDone = { naming = null; onJoined() }) }
}

/**
 * What this phone needs to ring while Porch is closed, when it doesn't have it: notifications and the microphone, with
 * the camera asked alongside, then on Android 14 and later, permission to show a call over the lock screen. Asked again
 * after a trip to Settings.
 */
@Composable
internal fun RingWhenClosed(app: PorchApplication, bedside: Boolean = false) {
    if (!app.push.configured) return
    val context = LocalContext.current
    var checks by remember { mutableIntStateOf(0) }
    // Android stops asking after a refusal or two, so Allow then opens Porch's settings instead.
    var refused by rememberSaveable { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { checks++; app.push.register() }
    val canRing = remember(checks) { app.push.canRing() }
    val fullScreen = remember(checks) { app.push.canShowFullScreen() }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        checks++
        refused = !app.push.canRing()
        app.push.register()
    }
    // A phone asks for the camera too, which ringing doesn't need, so a first video call answered from the lock screen
    // doesn't wait on a camera prompt. The bedside asked for it during setup, and a phone without one isn't asked.
    val hasCamera = remember { context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    val askCamera = !bedside && hasCamera
    // The bedside is normally always in front, so it rings this way only when it isn't, such as in Android's settings.
    val device = if (bedside) "tablet" else "phone"
    val (title, detail, button) = when {
        !canRing -> Triple(if (bedside) "Ring when Porch isn't in front" else "Ring when Porch is closed",
            if (bedside) "Allow notifications and the microphone, so calls still ring this tablet when Porch isn't in front."
            else if (askCamera) "Allow notifications, the microphone and the camera, so calls ring this phone even when Porch isn't open, and video calls start right away."
            else "Allow notifications and the microphone, so calls ring this phone even when Porch isn't open.",
            if (refused) "Open settings" else "Allow")
        !fullScreen -> Triple("Show calls on the lock screen", "Allow full-screen notifications for Porch, so a call shows when this $device is locked.",
            "Open settings")
        else -> return
    }
    FormCard(title, detail) {
        FormButton(button, onClick = {
            val needed = listOfNotNull(Manifest.permission.RECORD_AUDIO, if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null)
                .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
            val settings = when {
                canRing && Build.VERSION.SDK_INT >= 34 ->
                    Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.fromParts("package", context.packageName, null))
                !canRing && needed.isEmpty() -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                refused -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                else -> null
            }
            val camera = listOf(Manifest.permission.CAMERA).takeIf { askCamera }.orEmpty()
                .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
            if (settings == null) ask.launch((needed + camera).toTypedArray())
            else try { context.startActivity(settings) } catch (_: ActivityNotFoundException) {}
        })
    }
}

/** A message being recorded for `recipient` in a family, by its device ID: "message", or "voicemail" offered after a call
 * that didn't go through, which can start recording audio at once. */
private data class Composing(val deviceID: String, val recipient: String, val kind: String, val startAudio: Boolean)
private val composingSaver = listSaver<Composing?, String>(
    save = { it?.let { c -> listOf(c.deviceID, c.recipient, c.kind, c.startAudio.toString()) } ?: emptyList() },
    restore = { if (it.size == 4) Composing(it[0], it[1], it[2], it[3].toBoolean()) else null })

/** What's waiting for a caregiver's OK: phone voicemail, texts, or both, as iOS says it. */
private fun reviewTitle(voicemails: Int, texts: Int): String = when {
    texts == 0 -> if (voicemails == 1) "1 phone voicemail needs your review" else "$voicemails phone voicemails need your review"
    voicemails == 0 -> if (texts == 1) "1 text needs your review" else "$texts texts need your review"
    else -> "${voicemails + texts} messages need your review"
}

/** A row that opens a page, as iOS's `linkRow` is: its icon in the accent color, its name, and an arrow. */
@Composable
private fun SettingsRow(@DrawableRes icon: Int, title: String, onClick: () -> Unit) {
    CaregiverRow(onClick = onClick, label = title) {
        Icon(painterResource(icon), contentDescription = null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
        Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** How a bedside is, or why it can't be reached, centered as on iOS. */
@Composable
private fun Status(text: String) {
    Text(text, Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center)
}

/** A call a family phone is about to place, while Android asks for the microphone and camera. */
private class CallRequest(val family: FamilyCredential, val person: FamilyPerson, val mode: NativeCall.Mode)

/** A joined family waiting to be named. Saved, so turning the phone keeps the prompt; only its device ID is, since the
 * pairing itself stays in the secret store. */
private data class Naming(val deviceID: String, val sharedName: String, val numberedName: String)
private val namingSaver = listSaver<Naming?, String>(
    save = { it?.let { naming -> listOf(naming.deviceID, naming.sharedName, naming.numberedName) } ?: emptyList() },
    restore = { if (it.size == 3) Naming(it[0], it[1], it[2]) else null })

/** Two sets of parents are often both "Mom". Left unnamed, the new one is numbered, so Porch asks now, while it's clear
 * which one it is. */
@Composable
private fun NameFamily(app: PorchApplication, naming: Naming, onDone: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    AlertDialog(onDismissRequest = onDone,
        title = { Text("Name this family") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("You're in more than one family called ${naming.sharedName}. Until you name this one, it's ${naming.numberedName}.")
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true)
            }
        },
        confirmButton = { TextButton(enabled = name.isNotBlank(), onClick = {
            app.device.families.firstOrNull { it.deviceID == naming.deviceID }?.let { app.device.setNickname(name, it) }
            onDone()
        }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDone) { Text("Keep ${naming.numberedName}") } })
}

@Composable
private fun Families(app: PorchApplication, links: FamilyLinks, families: List<FamilyCredential>, onJoinAnother: () -> Unit, onChanged: () -> Unit,
    onAbout: () -> Unit, onThread: (FamilyCredential) -> Unit, onProfile: (FamilyCredential) -> Unit, onCompose: (FamilyCredential, String) -> Unit, onCaregiver: (FamilyCredential) -> Unit) {
    // The family being left, by device ID, while the phone asks to be sure.
    var leaving by rememberSaveable { mutableStateOf<String?>(null) }
    var leaveError by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    // As on iOS, the microphone and, for video, the camera are asked for before the call starts. Asking after would
    // leave the bedside ringing while the question is up, or after it's refused.
    val context = LocalContext.current
    var request by remember { mutableStateOf<CallRequest?>(null) }
    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        val call = request ?: return@rememberLauncherForActivityResult
        request = null
        // Backing out of the dialog answers with no results. `all` on that empty map is true, which would place the call.
        if (results.isNotEmpty() && results.values.all { it }) app.calls.call(call.person, call.mode, call.family)
        else app.calls.error = "Allow Porch to use the microphone and camera in Settings before calling."
    }
    val calling = { call: CallRequest ->
        val needed = listOfNotNull(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA.takeIf { call.mode == NativeCall.Mode.VIDEO })
            .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
        if (needed.isEmpty()) app.calls.call(call.person, call.mode, call.family)
        else { request = call; permissions.launch(needed.toTypedArray()) }
    }
    RingWhenClosed(app)
    // Laid out as iOS's family screen is: the bedside on a card of its own, with its calls and messages, and its Porch
    // number on another. A phone in more than one family shows each under its name; with one, the page is its bedside.
    val several = families.size > 1
    families.forEachIndexed { index, family ->
        val link = links.link(family)
        val state = link?.state
        val bedside = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }
        val name = app.device.familyName(family) ?: state?.householdName ?: "this family"
        // A failed check-in keeps the last snapshot. Showing that bedside as on would stay true until the next one that
        // works, which is what a dropped connection looks like, so the error shows instead.
        val error = link?.error
        Column(Modifier.padding(top = if (index > 0) 24.dp else 0.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (several) Text(name, Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            when {
                link?.accessRemoved == true -> {
                    Status("This phone was removed from this family. Ask a caregiver for a new invitation.")
                    FormPlainButton(if (several) "Remove $name from this phone" else "Remove this family from this phone",
                        onClick = { app.coordinator.forget(family); onChanged() }, color = MaterialTheme.colorScheme.error, icon = R.drawable.ic_remove_circle)
                }
                state == null -> Status(error ?: "Connecting…")
                else -> {
                    val from = bedside?.name ?: state.householdName
                    // Phone voicemail and texts from numbers that aren't on the keypad wait for a caregiver.
                    val held = state.heldMessages ?: 0
                    val heldTexts = state.heldTexts ?: 0
                    if (state.me.caregiver == true && held + heldTexts > 0) FormButton(reviewTitle(held, heldTexts), onClick = { onCaregiver(family) }, icon = R.drawable.ic_review)
                    // Left by the bedside when its call to this phone wasn't answered.
                    val unheard = state.newMessages ?: 0
                    if (unheard > 0) FormButton(if (unheard == 1) "New message from $from" else "$unheard new messages from $from", onClick = { onThread(family) },
                        icon = R.drawable.ic_mail_unread)
                    // Both ways in one thread, which stays while sending is off so earlier messages still play.
                    val thread: @Composable () -> Unit = { FormPlainButton("Messages with $from", onClick = { onThread(family) }, icon = R.drawable.ic_forum) }
                    if (bedside != null) FormCard(bedside.name) {
                        Status(error ?: if (!bedside.online) "Porch isn't ready" else if (state.busy) "On a call" else "Porch is open")
                        // Whether someone is at the bedside, as on iOS. Without a fresh check-in the last one's time
                        // stands still, so it would look current forever.
                        if (error == null) {
                            val attendedAt = state.bedsideAttendedAt?.toDouble()
                            val now = state.serverTime.toDouble()
                            BedsideAttendance.text(attendedAt, now, bedsideDevice(state))?.let {
                                Text(it, Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                                    color = if (BedsideAttendance.isPresent(attendedAt, now)) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        val opening = app.calls.opening
                        FormButton("Audio call", onClick = { calling(CallRequest(family, bedside, NativeCall.Mode.VOICE)) }, enabled = !opening, icon = R.drawable.ic_call)
                        FormButton("Video call", onClick = { calling(CallRequest(family, bedside, NativeCall.Mode.VIDEO)) }, enabled = !opening, icon = R.drawable.ic_videocam)
                        // Messages wait on the bedside, so they don't need it to be open right now.
                        if (state.messagesEnabled != false) FormPlainButton("Send a message", onClick = { onCompose(family, bedside.name) }, icon = R.drawable.ic_mail)
                        thread()
                    } else {
                        error?.let { Status(it) }
                        thread()
                    }
                    // Anyone can call the bedside on its own number, from any phone.
                    state.porchNumber?.let { PorchNumberCard(from, it) }
                    // What the bedside shows for this phone and whether its video calls start with the camera on, and for
                    // caregivers, the bedside's settings with its PIN. iOS has these on its settings page.
                    CaregiverGroup {
                        SettingsRow(R.drawable.ic_account, "Your name and photo", onClick = { onProfile(family) })
                        if (state.me.caregiver == true) {
                            HorizontalDivider()
                            SettingsRow(R.drawable.ic_lock, "Caregiver mode", onClick = { onCaregiver(family) })
                        }
                    }
                }
            }
            if (link?.accessRemoved != true) FormLink(if (several) "Leave $name" else "Leave this family", onClick = { leaveError = null; leaving = family.deviceID })
        }
    }
    leaveError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    if (families.size < FamilyNames.limit) FormLink("Join another family", onClick = onJoinAnother)
    // The open-source licenses, for anyone, not only a family's caregivers.
    FormLink("About Porch", onClick = onAbout)
    families.firstOrNull { it.deviceID == leaving }?.let { family ->
        val name = app.device.familyName(family) ?: links.state(family)?.householdName ?: "this family"
        // As on iOS (FamilyProfiles.swift): the phone leaves on the server, then forgets the family.
        AlertDialog(onDismissRequest = { leaving = null },
            title = { Text("Leave $name?") },
            text = { Text("This phone stops getting their calls and messages. To join again, you'll need a new invitation.") },
            confirmButton = { TextButton(onClick = {
                leaving = null
                scope.launch {
                    try { app.coordinator.leave(family); onChanged() }
                    catch (e: CancellationException) { throw e }
                    catch (e: Exception) { leaveError = e.message ?: "Couldn't leave. Check the connection and try again." }
                }
            }) { Text("Leave") } },
            dismissButton = { TextButton(onClick = { leaving = null }) { Text("Cancel") } })
    }
}
