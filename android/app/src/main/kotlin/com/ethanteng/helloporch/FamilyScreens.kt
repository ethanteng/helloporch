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
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.input.KeyboardCapitalization
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.PorchNumber
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

/** Family mode's screens: joining a family from an invitation, then three tabs, as on iOS (FamilyTabs.swift): Call, with
 * a card for each family's bedside; Messages, with one thread for each; and You, with this phone's families, each with a
 * page of its own, and this phone's settings. Setup links go to the bedside's screens instead (PorchRoot). `onReady` says
 * whether a tab's first screen, the messages or caregiver mode is showing, which is where a call could ring. A call takes
 * over the screen and closes caregiver mode, and a message not yet sent. */
@Composable
fun FamilyScreens(app: PorchApplication, link: String?, onLinkHandled: () -> Unit, onReady: (Boolean) -> Unit = {}) {
    val links by app.coordinator.links.collectAsStateWithLifecycle()
    var joining by rememberSaveable { mutableStateOf(false) }
    // The family caregiver mode is open for, by device ID, and why it last ended on its own, such as a changed PIN.
    var caregiving by rememberSaveable { mutableStateOf<String?>(null) }
    var caregiverNotice by rememberSaveable { mutableStateOf<String?>(null) }
    var about by rememberSaveable { mutableStateOf(false) }
    var tab by rememberSaveable { mutableStateOf(FamilyTab.CALL) }
    // On Messages, a family's thread, by device ID. On You, a family's page, and on it, this phone's name and photo
    // there, what this phone calls the family, or its bedside's Porch number.
    var thread by rememberSaveable { mutableStateOf<String?>(null) }
    var page by rememberSaveable { mutableStateOf<String?>(null) }
    var pageScreen by rememberSaveable { mutableStateOf(FamilyPageScreen.PAGE) }
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
    val threadFamily = families.firstOrNull { it.deviceID == thread }?.takeIf { tab == FamilyTab.MESSAGES }
    val pageFamily = families.firstOrNull { it.deviceID == page }?.takeIf { tab == FamilyTab.YOU }
    // A tapped message notification opens that family's thread, as iOS opens it: what else was open closes first,
    // caregiver mode, joining, and a message not yet sent included.
    val notified = app.messageAlerts.opening
    LaunchedEffect(notified, families) {
        val id = notified ?: return@LaunchedEffect
        if (families.any { it.deviceID == id }) {
            composing = null
            about = false
            if (caregiving != null) { RemoteCaregiverSession.shared.end(); caregiving = null }
            joining = false
            if (link != null) onLinkHandled()
            tab = FamilyTab.MESSAGES
            thread = id
        }
        app.messageAlerts.opening = null
    }
    val tabs = caregiverFamily == null && composeFamily == null && !(link != null || joining || families.isEmpty()) && !about
    SideEffect { onReady((tabs && pageFamily == null) || caregiverFamily != null) }
    // A call that didn't go through offers a message instead, as iOS does. Not once that family has left this phone,
    // removed it, or turned messages off: Leave a message would open a composer that can't send.
    app.calls.messageOffer?.takeIf { offer ->
        val link = links.link(offer.family)
        offer.recent && composeFamily == null && caregiverFamily == null &&
            families.any { it.deviceID == offer.family.deviceID } &&
            link?.accessRemoved != true && link?.state?.messagesEnabled != false
    }?.let { offer ->
        AlertDialog(onDismissRequest = { app.calls.messageOffer = null }, title = { Text(offer.title) },
            text = { Text("Leave a message?") },
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
    // From You, or the join screen, as long as no invitation is waiting.
    if (about && link == null) {
        BackHandler { about = false }
        AboutScreen(navigation = { TextButton(onClick = { about = false }) { Text("Back") } })
        return
    }
    val openCaregiver = { family: FamilyCredential ->
        // Every visit starts with the PIN.
        RemoteCaregiverSession.shared.end()
        caregiving = family.deviceID
    }
    if (!tabs) {
        // Titled Porch, as iOS's Call tab is.
        FormScreen("Porch") {
            JoinFamily(app, link.orEmpty(), adding = families.isNotEmpty(), onJoined = done, onCancel = if (families.isEmpty()) null else done,
                onAbout = { about = true })
        }
        PorchErrorDialog(caregiverNotice) { caregiverNotice = null }
        return
    }
    FamilyTabBar(tab, messages = familyMessagesWaiting(families, links), onSelect = { chosen ->
        // The tab that's showing goes back to its first screen, as iOS's do.
        if (chosen == tab) { thread = null; page = null; pageScreen = FamilyPageScreen.PAGE }
        tab = chosen
    }) {
        when (tab) {
            FamilyTab.CALL -> CallTab(app, links, families, onChanged = { changes++ })
            FamilyTab.MESSAGES -> if (threadFamily != null) {
                MessageThreadScreen(app, threadFamily, links, onBack = { thread = null },
                    onRecord = { name -> composing = Composing(threadFamily.deviceID, name, "message", startAudio = false) })
            } else MessagesTab(app, links, families, onThread = { thread = it.deviceID }, onCaregiver = openCaregiver)
            FamilyTab.YOU -> if (pageFamily != null) {
                val back = { pageScreen = FamilyPageScreen.PAGE }
                when (pageScreen) {
                    FamilyPageScreen.PROFILE -> FamilyProfileScreen(app, pageFamily, links, onBack = back)
                    FamilyPageScreen.NAME -> FamilyNameScreen(app, pageFamily, links, onDone = { back(); changes++ })
                    FamilyPageScreen.NUMBER -> PorchNumberScreen(app, pageFamily, links, onBack = back)
                    FamilyPageScreen.PAGE -> FamilyPage(app, pageFamily, links, onBack = { page = null }, onOpen = { pageScreen = it },
                        onCaregiver = { openCaregiver(pageFamily) }, onGone = { page = null; changes++ })
                }
            } else YouTab(app, links, families, onFamily = { page = it.deviceID; pageScreen = FamilyPageScreen.PAGE },
                onJoinAnother = { joining = true }, onAbout = { about = true })
        }
    }
    PorchErrorDialog(caregiverNotice) { caregiverNotice = null }
}

/** Family mode's tabs, in the order iOS has them. */
private enum class FamilyTab { CALL, MESSAGES, YOU }
/** What's open on You past a family's page. */
internal enum class FamilyPageScreen { PAGE, PROFILE, NAME, NUMBER }

/** New messages from every family's bedside, and for caregivers what's waiting for their OK, as iOS's Messages badge counts. */
private fun familyMessagesWaiting(families: List<FamilyCredential>, links: FamilyLinks): Int = families.sumOf { family ->
    val link = links.link(family)
    val state = link?.state?.takeIf { link.accessRemoved != true } ?: return@sumOf 0
    val review = if (state.me.caregiver == true) (state.heldMessages ?: 0) + (state.heldTexts ?: 0) else 0
    (state.newMessages ?: 0) + review
}

/** The tabs under whichever of their screens is open. The screens keep their own bar at the top and scroll above these. */
@Composable
private fun FamilyTabBar(selected: FamilyTab, messages: Int, onSelect: (FamilyTab) -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        // The bar below sits over the system's navigation, so the screen above it doesn't pad for that again.
        Box(Modifier.weight(1f).consumeWindowInsets(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom))) { content() }
        NavigationBar {
            val items = listOf(Triple(FamilyTab.CALL, "Call", R.drawable.ic_call), Triple(FamilyTab.MESSAGES, "Messages", R.drawable.ic_forum),
                Triple(FamilyTab.YOU, "You", R.drawable.ic_account))
            for ((tab, title, icon) in items) {
                NavigationBarItem(selected = tab == selected, onClick = { onSelect(tab) }, label = { Text(title) },
                    icon = {
                        if (tab == FamilyTab.MESSAGES && messages > 0) {
                            BadgedBox(badge = { Badge { Text("$messages") } }) { Icon(painterResource(icon), contentDescription = null) }
                        } else Icon(painterResource(icon), contentDescription = null)
                    },
                    modifier = Modifier.semantics { if (tab == FamilyTab.MESSAGES && messages > 0) contentDescription = "Messages, $messages new" })
            }
        }
    }
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
    Text("Paste the link a caregiver sent you.")
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

/** How a bedside is, or why it can't be reached, centered as on iOS. */
@Composable
private fun Status(text: String) {
    Text(text, Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center)
}

/** A call or drop-in a family phone is about to place, while Android asks for the microphone and camera. */
private class CallRequest(val family: FamilyCredential, val person: FamilyPerson, val mode: NativeCall.Mode, val dropIn: Boolean = false)

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
                Text("You're in more than one family called ${naming.sharedName}. What do you call this one?")
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true)
            }
        },
        confirmButton = { TextButton(enabled = name.isNotBlank(), onClick = {
            app.device.families.firstOrNull { it.deviceID == naming.deviceID }?.let { app.device.setNickname(name, it) }
            onDone()
        }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDone) { Text("Keep ${naming.numberedName}") } })
}

/** What a family's card says under its bedside's name, as on iOS: why it can't be reached, or how it is, and whether
 * that's someone at the bedside right now. */
internal fun familyStatus(link: FamilyLinks.Link?): Pair<String, Boolean> {
    if (link?.accessRemoved == true) return "This phone was removed from this family." to false
    link?.error?.let { return it to false }
    val state = link?.state ?: return "Connecting…" to false
    val bedside = state.people.firstOrNull { it.role == PorchExperience.BEDSIDE }
    if (bedside == null || !bedside.online) return "Porch isn't ready" to false
    if (state.busy) return "On a call" to false
    // Without a fresh check-in the last one's time stands still, so an error above shows instead.
    val attendedAt = state.bedsideAttendedAt?.toDouble()
    val now = state.serverTime.toDouble()
    BedsideAttendance.text(attendedAt, now, bedsideDevice(state))?.let { return it to BedsideAttendance.isPresent(attendedAt, now) }
    return "Porch is open" to false
}

/** What a family is called on this phone's screens: what this phone calls it, or its household's name. */
private fun familyTitle(app: PorchApplication, links: FamilyLinks, family: FamilyCredential): String =
    app.device.familyName(family) ?: links.state(family)?.householdName ?: "Family"

/** The Call tab: a card for each family's bedside with its calls, as iOS's. With more than one family, a card names its
 * family when that says something the bedside's name doesn't. */
@Composable
private fun CallTab(app: PorchApplication, links: FamilyLinks, families: List<FamilyCredential>, onChanged: () -> Unit) {
    // A family that removed this phone, by device ID, while the phone asks before taking it off.
    var removing by rememberSaveable { mutableStateOf<String?>(null) }
    // As on iOS, the microphone and, for video, the camera are asked for before the call starts. Asking after would
    // leave the bedside ringing while the question is up, or after it's refused.
    val context = LocalContext.current
    var request by remember { mutableStateOf<CallRequest?>(null) }
    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        val call = request ?: return@rememberLauncherForActivityResult
        request = null
        // Backing out of the dialog answers with no results. `all` on that empty map is true, which would place the call.
        if (results.isNotEmpty() && results.values.all { it }) app.calls.call(call.person, call.mode, call.family, call.dropIn)
        else app.calls.error = "Allow Porch to use the microphone and camera in Settings before calling."
    }
    val calling = { call: CallRequest ->
        val needed = listOfNotNull(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA.takeIf { call.mode == NativeCall.Mode.VIDEO })
            .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
        if (needed.isEmpty()) app.calls.call(call.person, call.mode, call.family, call.dropIn)
        else { request = call; permissions.launch(needed.toTypedArray()) }
    }
    FormScreen("Porch") {
        RingWhenClosed(app)
        val several = families.size > 1
        for (family in families) {
            val link = links.link(family)
            val state = link?.state
            val bedside = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }
            val name = bedside?.name ?: state?.householdName ?: app.device.familyName(family) ?: "Family"
            val familyName = if (several) app.device.familyName(family)?.takeIf { it != name } else null
            val (status, present) = familyStatus(link)
            Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), tonalElevation = 2.dp) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(name, size = 56.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(name, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                            familyName?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            Text(status, style = MaterialTheme.typography.bodyLarge, fontWeight = if (present) FontWeight.SemiBold else FontWeight.Normal,
                                color = if (present) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    when {
                        // A family that removed this phone can't reach it again. Taking it off leaves the others as they are.
                        link?.accessRemoved == true -> FormPlainButton("Remove from this phone", onClick = { removing = family.deviceID },
                            color = MaterialTheme.colorScheme.error, icon = R.drawable.ic_remove_circle)
                        state != null && bedside != null -> {
                            val enabled = !app.calls.opening && link.error == null && bedside.online && !state.busy
                            val dropIns = listOf(NativeCall.Mode.VOICE to state.me.permissions.audio, NativeCall.Mode.VIDEO to state.me.permissions.video)
                                .filter { state.dropInEnabled && it.second }.map { it.first }
                            CallButtons(name, enabled, dropIns, onCall = { mode, dropIn -> calling(CallRequest(family, bedside, mode, dropIn)) })
                        }
                    }
                }
            }
        }
    }
    families.firstOrNull { it.deviceID == removing }?.let { family ->
        // As on iOS (confirmRemoval): only a new invitation brings the family back.
        val name = if (families.size > 1) app.device.familyName(family) ?: links.state(family)?.householdName else null
        AlertDialog(onDismissRequest = { removing = null },
            title = { Text("Remove ${name ?: "this family"} from this phone?") },
            text = { Text("They've already removed this phone. To join again, you'll need a new invitation.") },
            confirmButton = { TextButton(onClick = { removing = null; app.coordinator.forget(family); onChanged() }) {
                Text("Remove", color = MaterialTheme.colorScheme.error)
            } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } })
    }
}

/** Call, Video and, when it's approved for this phone, Drop in, side by side as on iOS. Approved for both, Drop in asks
 * which. Very large text stacks them, since three don't fit across. */
@Composable
private fun CallButtons(name: String, enabled: Boolean, dropIns: List<NativeCall.Mode>, onCall: (NativeCall.Mode, Boolean) -> Unit) {
    var choosing by remember { mutableStateOf(false) }
    val buttons: @Composable (Modifier) -> Unit = { each ->
        CallButton("Call", R.drawable.ic_call, "Call $name", enabled, filled = true, each) { onCall(NativeCall.Mode.VOICE, false) }
        CallButton("Video", R.drawable.ic_videocam, "Video call $name", enabled, filled = true, each) { onCall(NativeCall.Mode.VIDEO, false) }
        dropIns.firstOrNull()?.let { only ->
            Box(each) {
                val label = when { dropIns.size > 1 -> "Drop in on $name"; only == NativeCall.Mode.VIDEO -> "Drop in on $name with video"; else -> "Drop in on $name with audio" }
                CallButton("Drop in", R.drawable.ic_waveform, label, enabled, filled = false, Modifier.fillMaxWidth()) {
                    if (dropIns.size > 1) choosing = true else onCall(only, true)
                }
                DropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }) {
                    DropdownMenuItem(text = { Text("Drop in with audio") }, leadingIcon = { Icon(painterResource(R.drawable.ic_waveform), null) },
                        onClick = { choosing = false; onCall(NativeCall.Mode.VOICE, true) })
                    DropdownMenuItem(text = { Text("Drop in with video") }, leadingIcon = { Icon(painterResource(R.drawable.ic_videocam), null) },
                        onClick = { choosing = false; onCall(NativeCall.Mode.VIDEO, true) })
                }
            }
        }
    }
    if (LocalDensity.current.fontScale > 1.5f) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { buttons(Modifier.fillMaxWidth()) }
    else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { buttons(Modifier.weight(1f)) }
}

@Composable
private fun CallButton(text: String, @DrawableRes icon: Int, label: String, enabled: Boolean, filled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val content: @Composable RowScope.() -> Unit = {
        Icon(painterResource(icon), contentDescription = null, Modifier.size(18.dp))
        Text(text, Modifier.padding(start = 6.dp), style = MaterialTheme.typography.titleMedium, maxLines = 1)
    }
    val described = modifier.heightIn(min = 50.dp).semantics { contentDescription = label }
    val padding = PaddingValues(horizontal = 8.dp, vertical = 8.dp)
    if (filled) Button(onClick, described, enabled = enabled, contentPadding = padding, content = content)
    else OutlinedButton(onClick, described, enabled = enabled, contentPadding = padding, content = content)
}

/** The Messages tab: what's waiting for a caregiver's OK, then one thread for each family's bedside, as on iOS. */
@Composable
private fun MessagesTab(app: PorchApplication, links: FamilyLinks, families: List<FamilyCredential>, onThread: (FamilyCredential) -> Unit,
    onCaregiver: (FamilyCredential) -> Unit) {
    FormScreen("Messages") {
        val several = families.size > 1
        val shown = families.filter { links.link(it)?.accessRemoved != true && links.state(it) != null }
        // Families that removed this phone aren't listed. When that's all of them, say so rather than Connecting, as on iOS.
        if (shown.isEmpty()) {
            val removed = families.isNotEmpty() && families.all { links.link(it)?.accessRemoved == true }
            Status(when {
                !removed -> "Connecting to your family…"
                families.size == 1 -> "This phone was removed from this family."
                else -> "This phone was removed from these families."
            })
            return@FormScreen
        }
        // Phone voicemail and texts from numbers that aren't on the keypad wait for a caregiver.
        for (family in shown) {
            val state = links.state(family) ?: continue
            val held = state.heldMessages ?: 0
            val texts = state.heldTexts ?: 0
            if (state.me.caregiver == true && held + texts > 0) {
                FormButton(reviewTitle(held, texts) + if (several) "\n${familyTitle(app, links, family)}" else "", onClick = { onCaregiver(family) },
                    icon = R.drawable.ic_review)
            }
        }
        CaregiverGroup {
            shown.forEachIndexed { index, family ->
                val state = links.state(family)
                val name = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }?.name ?: familyTitle(app, links, family)
                val familyName = if (several) familyTitle(app, links, family).takeIf { it != name } else null
                val unheard = state?.newMessages ?: 0
                val new = when { unheard == 1 -> "1 new message"; unheard > 1 -> "$unheard new messages"; else -> null }
                if (index > 0) HorizontalDivider()
                CaregiverRow(onClick = { onThread(family) }, label = "Messages with " + listOfNotNull(name, familyName, new).joinToString(", ")) {
                    Avatar(name, size = 44.dp)
                    Column(Modifier.weight(1f)) {
                        Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        listOfNotNull(familyName, new).joinToString(" · ").takeIf { it.isNotEmpty() }?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = if (new != null) FontWeight.SemiBold else FontWeight.Normal,
                                color = if (new != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** The You tab: this phone's families, each with its own page, joining another, and this phone's own settings. */
@Composable
private fun YouTab(app: PorchApplication, links: FamilyLinks, families: List<FamilyCredential>, onFamily: (FamilyCredential) -> Unit,
    onJoinAnother: () -> Unit, onAbout: () -> Unit) {
    var camera by remember { mutableStateOf(CallPreferences.startVideoWithCamera(app.settings)) }
    FormScreen("You") {
        CaregiverGroup("Your families") {
            families.forEachIndexed { index, family ->
                val name = familyTitle(app, links, family)
                val person = links.state(family)?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }?.name?.takeIf { it != name }
                if (index > 0) HorizontalDivider()
                ValueRow(name, person, onClick = { onFamily(family) })
            }
            if (families.size < FamilyNames.limit) {
                HorizontalDivider()
                CaregiverRow(onClick = onJoinAnother, label = "Join another family") {
                    Icon(painterResource(R.drawable.ic_add), contentDescription = null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
                    Text("Join another family", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        CaregiverGroup("On this phone") {
            ToggleRow("Start video calls with my camera on", camera, onChange = {
                CallPreferences.saveStartVideoWithCamera(it, app.settings)
                camera = it
            })
        }
        // The open-source licenses, for anyone, not only a family's caregivers.
        FormLink("About Porch", onClick = onAbout)
    }
}

/** A row that opens a page, with what it's set to now at its end, as iOS's `linkRow` with a value. */
@Composable
private fun ValueRow(title: String, value: String?, @DrawableRes icon: Int? = null, onClick: () -> Unit) {
    CaregiverRow(onClick = onClick, label = listOfNotNull(title, value).joinToString(", ")) {
        icon?.let { Icon(painterResource(it), contentDescription = null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary) }
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
        value?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1) }
        Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** One family on this phone, opened from You, as iOS's FamilyPageViewController: what the bedside shows for this phone,
 * what this phone calls the family, caregiver mode, the bedside's Porch number, and leaving. */
@Composable
private fun FamilyPage(app: PorchApplication, family: FamilyCredential, links: FamilyLinks, onBack: () -> Unit, onOpen: (FamilyPageScreen) -> Unit,
    onCaregiver: () -> Unit, onGone: () -> Unit) {
    BackHandler(onBack = onBack)
    var leaving by rememberSaveable { mutableStateOf(false) }
    var removing by rememberSaveable { mutableStateOf(false) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val link = links.link(family)
    val state = link?.state
    val name = familyTitle(app, links, family)
    FormScreen(name, navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        when {
            link?.accessRemoved == true -> {
                Text("This phone was removed from this family.")
                FormPlainButton("Remove $name from this phone", onClick = { removing = true }, color = MaterialTheme.colorScheme.error)
            }
            state == null -> {
                Status(link?.error ?: "Connecting to your family…")
                FormPlainButton("Leave $name", onClick = { leaving = true }, color = MaterialTheme.colorScheme.error)
            }
            else -> {
                CaregiverGroup {
                    ValueRow("Your name and photo", state.me.name, R.drawable.ic_account) { onOpen(FamilyPageScreen.PROFILE) }
                    HorizontalDivider()
                    ValueRow("Family name", name, R.drawable.ic_label) { onOpen(FamilyPageScreen.NAME) }
                    if (state.me.caregiver == true) {
                        HorizontalDivider()
                        ValueRow("Caregiver mode", null, R.drawable.ic_lock, onClick = onCaregiver)
                    }
                }
                // Anyone can call the bedside on its own number, from any phone.
                state.porchNumber?.let { number ->
                    CaregiverGroup { ValueRow("Porch number", PorchNumber.display(number), R.drawable.ic_dialpad) { onOpen(FamilyPageScreen.NUMBER) } }
                }
                FormPlainButton("Leave $name", onClick = { leaving = true }, color = MaterialTheme.colorScheme.error)
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
    if (leaving) {
        // As on iOS: the phone leaves on the server, then forgets the family.
        AlertDialog(onDismissRequest = { leaving = false },
            title = { Text("Leave $name?") },
            text = { Text("This phone stops getting their calls and messages. To join again, you'll need a new invitation.") },
            confirmButton = { TextButton(onClick = {
                leaving = false
                scope.launch {
                    try { app.coordinator.leave(family); onGone() }
                    catch (e: CancellationException) { throw e }
                    catch (e: Exception) { error = e.message ?: "Couldn't leave. Check the connection and try again." }
                }
            }) { Text("Leave") } },
            dismissButton = { TextButton(onClick = { leaving = false }) { Text("Cancel") } })
    }
    if (removing) {
        AlertDialog(onDismissRequest = { removing = false },
            title = { Text("Remove $name from this phone?") },
            text = { Text("They've already removed this phone. To join again, you'll need a new invitation.") },
            confirmButton = { TextButton(onClick = { removing = false; app.coordinator.forget(family); onGone() }) {
                Text("Remove", color = MaterialTheme.colorScheme.error)
            } },
            dismissButton = { TextButton(onClick = { removing = false }) { Text("Cancel") } })
    }
}

/** What this phone calls a family, to tell it from the others: two sets of parents are often both "Mom". */
@Composable
private fun FamilyNameScreen(app: PorchApplication, family: FamilyCredential, links: FamilyLinks, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    var name by rememberSaveable { mutableStateOf(app.device.nickname(family).orEmpty()) }
    val household = links.state(family)?.householdName ?: familyTitle(app, links, family)
    FormScreen("Family name", navigation = { TextButton(onClick = onDone) { Text("Back") } }) {
        FormField(name, { name = it }, "Family name", household, keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        Text("Only on this phone.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        FormButton("Save", onClick = { app.device.setNickname(name, family); onDone() })
    }
}

/** A bedside's own phone number, which anyone can call it on: in Contacts in one tap, or sent to someone. */
@Composable
private fun PorchNumberScreen(app: PorchApplication, family: FamilyCredential, links: FamilyLinks, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val state = links.state(family)
    val from = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }?.name ?: state?.householdName ?: familyTitle(app, links, family)
    FormScreen("Porch number", navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        state?.porchNumber?.let { PorchNumberCard(from, it) } ?: Status("Connecting to your family…")
    }
}
