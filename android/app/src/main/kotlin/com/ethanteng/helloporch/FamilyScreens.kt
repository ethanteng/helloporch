package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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

/** Family mode's screens: joining a family from an invitation, the families this phone is in, and caregiver mode for
 * one of them. Setup links go to the bedside's screens instead (PorchRoot). `onReady` says whether the list of families
 * or caregiver mode is showing, which is where a call could ring. A call takes over the screen and closes caregiver
 * mode. */
@Composable
fun FamilyScreens(app: PorchApplication, link: String?, onLinkHandled: () -> Unit, onReady: (Boolean) -> Unit = {}) {
    val links by app.coordinator.links.collectAsStateWithLifecycle()
    var joining by rememberSaveable { mutableStateOf(false) }
    // The family caregiver mode is open for, by device ID, and why it last ended on its own, such as a changed PIN.
    var caregiving by rememberSaveable { mutableStateOf<String?>(null) }
    var caregiverNotice by rememberSaveable { mutableStateOf<String?>(null) }
    // Joining or removing a family changes the list before any family has checked in.
    var changes by remember { mutableIntStateOf(0) }
    val families = remember(links, changes) { app.device.families }
    val done = { joining = false; changes++; onLinkHandled() }
    // An invitation opened meanwhile, or the family leaving this phone, ends caregiver mode.
    val caregiverFamily = families.firstOrNull { it.deviceID == caregiving }?.takeIf { link == null && !joining }
    LaunchedEffect(caregiving, caregiverFamily == null) {
        if (caregiving != null && caregiverFamily == null) { RemoteCaregiverSession.shared.end(); caregiving = null }
    }
    val listing = caregiverFamily == null && !(link != null || joining || families.isEmpty())
    SideEffect { onReady(listing || caregiverFamily != null) }
    if (caregiverFamily != null) {
        RemoteCaregiverMode(app, caregiverFamily, links, onClose = { reason -> caregiving = null; caregiverNotice = reason })
        return
    }
    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (!listing) JoinFamily(app, link.orEmpty(), adding = families.isNotEmpty(), onJoined = done, onCancel = if (families.isEmpty()) null else done)
            else Families(app, links, families, onJoinAnother = { joining = true }, onChanged = { changes++ },
                onCaregiver = { family ->
                    // Every visit starts with the PIN.
                    RemoteCaregiverSession.shared.end()
                    caregiving = family.deviceID
                })
        }
    }
    PorchErrorDialog(caregiverNotice) { caregiverNotice = null }
}

@Composable
private fun JoinFamily(app: PorchApplication, initialLink: String, adding: Boolean, onJoined: () -> Unit, onCancel: (() -> Unit)?) {
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
    Button(enabled = !busy && text.isNotBlank(), onClick = {
        val invitation = try { FamilyInvitation(text.trim(), BuildConfig.PORCH_SERVER_URL) } catch (e: IllegalArgumentException) { error = e.message; return@Button }
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
    }) { Text(if (busy) "Joining…" else "Join family") }
    onCancel?.let { TextButton(onClick = it) { Text("Cancel") } }
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
    // The bedside is normally always in front, so it rings this way only when it isn't, such as in Android's settings.
    val device = if (bedside) "tablet" else "phone"
    val (title, detail, button) = when {
        !canRing -> Triple(if (bedside) "Ring when Porch isn't in front" else "Ring when Porch is closed",
            if (bedside) "Allow notifications and the microphone, so calls still ring this tablet when Porch isn't in front."
            else "Allow notifications, the microphone and the camera, so calls ring this phone even when Porch isn't open, and video calls start right away.",
            if (refused) "Open settings" else "Allow")
        !fullScreen -> Triple("Show calls on the lock screen", "Allow full-screen notifications for Porch, so a call shows when this $device is locked.",
            "Open settings")
        else -> return
    }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(detail)
            Button(onClick = {
                val needed = listOfNotNull(Manifest.permission.RECORD_AUDIO, if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null)
                    .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
                val settings = when {
                    canRing && Build.VERSION.SDK_INT >= 34 ->
                        Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.fromParts("package", context.packageName, null))
                    !canRing && needed.isEmpty() -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    refused -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                    else -> null
                }
                // A phone asks for the camera too, which ringing doesn't need, so a first video call answered from the lock
                // screen doesn't wait on a camera prompt. The bedside asked for it during setup.
                val camera = listOf(Manifest.permission.CAMERA).takeIf { !bedside }.orEmpty()
                    .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
                if (settings == null) ask.launch((needed + camera).toTypedArray())
                else try { context.startActivity(settings) } catch (_: ActivityNotFoundException) {}
            }) { Text(button) }
        }
    }
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
    onCaregiver: (FamilyCredential) -> Unit) {
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
    Text(if (families.size == 1) "Your family" else "Your families", style = MaterialTheme.typography.headlineMedium)
    RingWhenClosed(app)
    for (family in families) {
        val link = links.link(family)
        val state = link?.state
        val bedside = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(app.device.familyName(family) ?: state?.householdName ?: "Your family", style = MaterialTheme.typography.titleLarge)
                Text(when {
                    link?.accessRemoved == true -> "This phone was removed from this family. Ask a caregiver for a new invitation."
                    // A failed check-in keeps the last snapshot. Showing that bedside as on would stay true until the
                    // next one that works, which is what a dropped connection looks like.
                    link?.error != null -> link.error!!
                    bedside != null -> "${bedside.name}'s ${bedsideDevice(state)} ${if (bedside.online) "is on and ready." else "isn't checking in right now."}"
                    else -> "Checking in…"
                })
                if (bedside != null && link.accessRemoved != true) {
                    val opening = app.calls.opening
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Button(onClick = { calling(CallRequest(family, bedside, NativeCall.Mode.VOICE)) }, enabled = !opening) { Text("Audio call") }
                        Button(onClick = { calling(CallRequest(family, bedside, NativeCall.Mode.VIDEO)) }, enabled = !opening) { Text("Video call") }
                    }
                }
                // Anyone can call the bedside on its own number, from any phone.
                state?.porchNumber?.takeIf { link.accessRemoved != true }?.let { PorchNumberCard(bedside?.name ?: state.householdName, it) }
                // Caregivers change the bedside's settings from here with its PIN.
                if (state?.me?.caregiver == true && link.accessRemoved != true) {
                    OutlinedButton(onClick = { onCaregiver(family) }, Modifier.fillMaxWidth()) { Text("Caregiver mode") }
                }
                if (link?.accessRemoved == true) TextButton(onClick = { app.coordinator.forget(family); onChanged() }) { Text("Remove from this phone") }
                else TextButton(onClick = { leaveError = null; leaving = family.deviceID }) { Text("Leave this family") }
            }
        }
    }
    Text("This test version joins families, checks in with them, calls while Porch is open, and rings while it's closed. Messages come in a later version.",
        style = MaterialTheme.typography.bodySmall)
    leaveError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    if (families.size < FamilyNames.limit) OutlinedButton(onClick = onJoinAnother) { Text("Join another family") }
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
