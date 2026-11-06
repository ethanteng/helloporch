package com.ethanteng.helloporch

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyAdminState
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.FamilyResponse
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.FamilySnapshot
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchNumber
import com.ethanteng.helloporch.core.RemoteCaregiverSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/** Caregiver mode's pages, as iOS's CaregiverPage lists them. Messages comes with messages (android/PLAN.md, phase 5). */
enum class CaregiverPage(private val bedsideTitle: String, private val phoneTitle: String = bedsideTitle) {
    PEOPLE("People", "Family"), CALLS("Calls"), DROP_IN("Drop-in"), DISPLAY("Display & voice"), PRIVACY("Privacy"),
    CAREGIVERS("Caregivers & PIN", "Caregivers"), DEVICE("This tablet");

    fun title(onBedside: Boolean): String = if (onBedside) bedsideTitle else phoneTitle

    companion object {
        /** A family phone can't change the keypad, the clock or the tablet itself, so those pages stay on the bedside. */
        fun pages(onBedside: Boolean): List<CaregiverPage> = if (onBedside) entries else listOf(PEOPLE, CALLS, DROP_IN, PRIVACY, CAREGIVERS)
    }
}

/** Screens a caregiver opens over a page. */
enum class CaregiverScreen { NAME, NUMBER, CHANGE_PIN, CONNECT_PHONE, CONNECT_KEYPAD }

/**
 * Caregiver mode's changes, as iOS's FamilyAdminViewController makes them: each one goes to the server with the caregiver
 * PIN, and the household it sends back is shown everywhere. One change at a time. Main thread only.
 *
 * On the bedside it uses the tablet's pairing and saved PIN. Opened from a family phone, `remote` is that phone's pairing
 * with the family, the PIN is the one typed for this session (RemoteCaregiverSession), and the household is the copy the
 * server sends back with each change, since a family phone's own check-ins leave out caregiver details. A changed PIN,
 * withdrawn approval or an ended session locks it (`onLock`, with the reason when there's one to show).
 */
class CaregiverAdmin(private val app: PorchApplication, private val scope: CoroutineScope, val remote: FamilyCredential? = null,
    state: FamilyAdminState? = null, private val onLock: (String?) -> Unit = {}) {
    var busy by mutableStateOf(false); private set
    /** Why the last change didn't go through, until it's dismissed. */
    var error by mutableStateOf<String?>(null)
    /** The keypad as it's saved on this tablet. A saved keypad that can't be read shows empty, and saving a key starts
     * it again. A family phone has none: the keypad is set on the bedside. */
    var slots by mutableStateOf(CallSlots()); private set
    var slotsUnreadable by mutableStateOf(false); private set
    val onBedside: Boolean get() = remote == null
    /** On a family phone, which family member this phone is. */
    val myID: String? get() = remote?.deviceID
    private var remoteState by mutableStateOf(state)
    private var locked = false
    private val credential: FamilyCredential? get() = remote ?: app.device.credential(PorchExperience.BEDSIDE)
    /** The household's server, which invitation links point to. */
    val origin: String? get() = credential?.origin

    init { reloadSlots() }

    /** Ends caregiver mode on a family phone, as when the caregiver taps Done. */
    fun lock(reason: String? = null) {
        if (remote == null) return
        RemoteCaregiverSession.shared.end()
        if (locked) return
        locked = true
        onLock(reason)
    }

    /** The PIN for the next change. On a family phone, using it keeps the session going; one that has ended locks. */
    private fun pin(): String? {
        if (remote == null) return app.caregiverPIN
        return RemoteCaregiverSession.shared.activePIN ?: run { lock(); null }
    }

    /** Reads the keypad again, as after a check-in, which can change who a key shows. */
    fun reloadSlots() {
        if (remote != null) return
        try {
            slots = CallSlots.load(app.settings, app.photos)
            slotsUnreadable = false
        } catch (_: Exception) {
            slotsUnreadable = true
        }
    }

    /**
     * Changes the keypad and saves it, as iOS's `saveSlots` does: a key whose invitation was accepted meanwhile follows
     * its family member first, and the server hears the keypad's numbers. False, with the reason shown, when it can't
     * be saved.
     */
    fun saveSlots(change: (CallSlots) -> Unit): Boolean = if (remote != null) false else try {
        val updated = slots.copy()
        change(updated)
        app.coordinator.links.value.state?.let { updated.reconcile(it, app.photos.familyMembers) }
        updated.save(app.settings, app.photos)
        slots = updated
        slotsUnreadable = false
        app.keypadReport.report(updated, app.coordinator)
        true
    } catch (e: Exception) {
        error = e.message ?: "Couldn't save the keypad. Try again."
        false
    }

    /** Runs changes that go one after another, such as removing someone and then emptying their key. */
    fun launch(block: suspend CaregiverAdmin.() -> Unit) { scope.launch { block() } }

    /**
     * Makes `action` with the caregiver PIN (or `pin`, such as the current one when changing it) and takes the household
     * it returns. Throws with the reason it didn't go through. On a family phone, a refused PIN or approval locks.
     */
    suspend fun request(action: String, values: Map<String, JsonElement> = emptyMap(), pin: String? = null): FamilyResponse {
        val credential = credential ?: throw FamilyServiceException("Go back to the clock and open caregiver mode to finish setup.", 409)
        val code = pin ?: pin() ?: throw FamilyServiceException("Caregiver mode has ended. Open it again with the PIN.", 401)
        return try {
            app.service(credential).send(action, values, pin = code).also { response ->
                app.coordinator.update(response)
                if (remote != null) response.admin?.let { remoteState = it }
            }
        } catch (e: FamilyServiceException) {
            // A changed PIN, withdrawn approval or too many wrong PINs ends a phone's caregiver mode.
            if (e.status in listOf(401, 403, 429)) lock(e.message)
            throw e
        }
    }

    /** Makes `action` with the caregiver PIN, and says whether it went through. The reason it didn't is shown. */
    suspend fun send(action: String, values: Map<String, JsonElement> = emptyMap(), pin: String? = null): Boolean {
        if (busy || credential == null) return false
        busy = true
        return try {
            request(action, values, pin)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // A phone that just locked shows why on its family screen instead.
            if (!locked) error = e.message ?: "Couldn't reach Porch. Check the connection and try again."
            false
        } finally {
            busy = false
        }
    }

    /** Uploads a photo a caregiver chose for a family member, then shows it for them everywhere. */
    suspend fun chooseOverridePhoto(data: ByteArray, memberID: String): Boolean {
        val credential = credential
        if (busy || credential == null) return false
        val pin = pin() ?: return false
        busy = true
        val photo = try {
            FamilyPhotos.upload(app, data, "overridePhotoUpload", mapOf("memberID" to JsonPrimitive(memberID)), credential, pin)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if ((e as? FamilyServiceException)?.status in listOf(401, 403, 429)) lock(e.message)
            if (!locked) error = e.message ?: "Couldn't upload the photo. Try again."
            null
        } finally {
            busy = false
        }
        return photo != null && send("setMemberOverride", mapOf("memberID" to JsonPrimitive(memberID), "photo" to photo))
    }

    /** The household as caregiver mode sees it: who's in the family and how the household is set. */
    fun state(links: FamilyLinks): FamilyAdminState? = if (remote != null) remoteState else links.state?.let {
        FamilyAdminState(it.householdName, it.dropInEnabled, it.people.filter { person -> person.role == PorchExperience.FAMILY },
            it.messagesEnabled, it.messages, it.texts, it.phoneDropIns, it.invitations, it.callScreening, it.shareAttendance)
    }

    /** The household's check-in as this device last heard it. A phone in several families reads the one caregiver mode
     * was opened for. */
    fun snapshot(links: FamilyLinks): FamilySnapshot? = if (remote != null) links.state(remote) else links.state

    /**
     * On a family phone, reads the household again: its own check-ins leave out what caregiver mode shows, such as
     * blocked numbers, so it's read as each page or screen opens, as iOS reads it when its list comes back. Opening one
     * is the caregiver's doing, so it counts as activity. Failures show on the next change instead.
     */
    fun refresh() {
        if (remote == null || locked) return
        scope.launch {
            try { request("verifyPIN") } catch (e: CancellationException) { throw e } catch (_: Exception) {}
        }
    }

    /** The bedside downloads everyone's photo itself. A caregiver's phone downloads one when it's shown. */
    fun loadPhoto(person: FamilyPerson) {
        val remote = remote ?: return
        val id = person.photoID ?: return
        if (app.photos.familyMembers.contains(id)) return
        val pin = RemoteCaregiverSession.shared.activePIN ?: return
        FamilyPhotos.loadForCaregiver(app, id, person.id, remote, pin)
    }

    /** Makes `action` with the caregiver PIN, then calls `done` with whether it went through. */
    fun perform(action: String, values: Map<String, JsonElement> = emptyMap(), pin: String? = null, done: (Boolean) -> Unit = {}) {
        if (busy || credential == null) { done(false); return }
        scope.launch { done(send(action, values, pin)) }
    }
}

/** A family member's photo, if this device has it. Caregiver mode on a phone downloads it when it's first shown. */
@Composable
fun memberPhoto(app: PorchApplication, admin: CaregiverAdmin, person: FamilyPerson): ByteArray? {
    val photo = remember(person.photoID, FamilyPhotos.saved) { FamilyPhotos.data(app, person.photoID) }
    LaunchedEffect(person.photoID, photo == null) { if (photo == null) admin.loadPhoto(person) }
    return photo
}

/** What family call the bedside: "tablet" for an Android one, "iPad" otherwise. */
fun bedsideDevice(snapshot: FamilySnapshot?): String {
    val bedside = snapshot?.let { if (it.me.role == PorchExperience.BEDSIDE) it.me else it.people.firstOrNull { p -> p.role == PorchExperience.BEDSIDE } }
    return if (bedside?.platform == "android") "tablet" else "iPad"
}

/**
 * Caregiver mode on the bedside: the household and the list of pages, with the open page beside it on a wide screen or
 * in its place on a narrow one, as iOS's split view does. Back closes what's open, then caregiver mode.
 */
@Composable
fun CaregiverMode(app: PorchApplication, links: FamilyLinks, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val admin = remember { CaregiverAdmin(app, scope) }
    CaregiverModeContent(app, admin, links, "Back to clock", onClose)
}

/** Caregiver mode's list and pages, on the bedside or a family phone. `closeLabel` is the bar's way out. */
@Composable
fun CaregiverModeContent(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, closeLabel: String, onClose: () -> Unit) {
    var page by rememberSaveable { mutableStateOf<CaregiverPage?>(null) }
    var screen by rememberSaveable { mutableStateOf<CaregiverScreen?>(null) }
    val state = admin.state(links)
    // A family phone reads the household again as a page opens, and when it has none yet, such as after turning.
    LaunchedEffect(page) { if (page != null || state == null) admin.refresh() }
    // A check-in can change who a key shows, such as an invitation accepted, and so can a photo arriving.
    LaunchedEffect(links, FamilyPhotos.saved) { admin.reloadSlots() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 720.dp
        val listWidth = (maxWidth * 0.34f).coerceIn(280.dp, 360.dp)
        BackHandler {
            when {
                screen != null -> screen = null
                !wide && page != null -> page = null
                else -> onClose()
            }
        }
        val open = { opened: CaregiverScreen -> screen = opened }
        val current = screen
        when {
            current != null -> CaregiverScreenContent(app, admin, links, current, onDone = { screen = null })
            wide -> Row(Modifier.fillMaxSize()) {
                Column(Modifier.width(listWidth).fillMaxHeight()) {
                    CaregiverList(app, admin, links, state, page ?: CaregiverPage.PEOPLE, closeLabel, onClose, onPage = { page = it }, onScreen = open)
                }
                VerticalDivider()
                Column(Modifier.weight(1f).fillMaxHeight()) {
                    CaregiverPageContent(app, admin, links, page ?: CaregiverPage.PEOPLE, onBack = null, onScreen = open, onClose = onClose)
                }
            }
            page != null -> CaregiverPageContent(app, admin, links, page!!, onBack = { page = null }, onScreen = open, onClose = onClose)
            else -> CaregiverList(app, admin, links, state, null, closeLabel, onClose, onPage = { page = it }, onScreen = open)
        }
    }
    PorchErrorDialog(admin.error) { admin.error = null }
}

/** Who this Porch is for, its number, and the pages. On a family phone, what only the bedside can change is listed
 * apart, as iOS lists it. */
@Composable
private fun CaregiverList(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, state: FamilyAdminState?, selected: CaregiverPage?,
    closeLabel: String, onClose: () -> Unit, onPage: (CaregiverPage) -> Unit, onScreen: (CaregiverScreen) -> Unit) {
    FormScreen("Caregiver mode", navigation = { TextButton(onClick = onClose) { Text(closeLabel) } }) {
        val name = state?.householdName ?: "Your loved one"
        val snapshot = admin.snapshot(links)
        val bedside = bedsideDevice(snapshot)
        CaregiverGroup {
            CaregiverRow(onClick = { onScreen(CaregiverScreen.NAME) }) {
                Avatar(name)
                Column(Modifier.weight(1f)) {
                    Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("Change the name family see", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            // The number, or how getting one is going. On the bedside, one that isn't ready opens the number screen to
            // choose again. Only the bedside can choose.
            val number = snapshot?.porchNumber?.let(PorchNumber::display)
            val summary = number ?: snapshot?.phoneSetup?.let {
                if (it.needsChoice != true) "Getting it…" else if (admin.onBedside) "Choose an area code" else "Choose an area code on the $bedside"
            } ?: if (admin.onBedside) "Not set up" else null
            if (summary != null) {
                HorizontalDivider()
                CaregiverRow(onClick = if (admin.onBedside && number == null && snapshot != null) ({ onScreen(CaregiverScreen.NUMBER) }) else null) {
                    Column(Modifier.weight(1f)) {
                        Text("Porch number", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(summary, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
        CaregiverGroup {
            CaregiverPage.pages(admin.onBedside).forEachIndexed { index, page ->
                if (index > 0) HorizontalDivider()
                val value = when (page) {
                    CaregiverPage.CAREGIVERS -> state?.people?.count { it.caregiver == true }?.takeIf { it > 0 }?.toString()
                    // As iOS's list shows it, so a household with drop-ins paused can tell without opening the page.
                    CaregiverPage.DROP_IN -> state?.let { if (it.dropInEnabled) "On" else "Off" }
                    else -> null
                }
                CaregiverRow(onClick = { onPage(page) }, selected = page == selected) {
                    Text(page.title(admin.onBedside), Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    value?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (!admin.onBedside) CaregiverGroup("On the bedside $bedside") {
            listOf("Keypad", "Display & voice", "Caregiver PIN").forEachIndexed { index, title ->
                if (index > 0) HorizontalDivider()
                CaregiverRow(label = "$title, set on the bedside $bedside") {
                    LockGlyph(MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(title, style = MaterialTheme.typography.titleMedium)
                }
            }
        }
        if (admin.onBedside && app.device.credential(PorchExperience.BEDSIDE) == null) Text("Go back to the clock and open caregiver mode to finish setup.")
    }
}

/** A padlock, as iOS's `lock.fill` marks settings a phone can't change. */
@Composable
private fun LockGlyph(color: Color) {
    Canvas(Modifier.size(22.dp)) {
        val w = size.width
        val h = size.height
        val stroke = w * 0.11f
        // The shackle: an arch and its two legs down into the body.
        drawArc(color, 180f, 180f, useCenter = false, topLeft = Offset(w * 0.28f, h * 0.08f), size = Size(w * 0.44f, h * 0.44f), style = Stroke(stroke))
        drawLine(color, Offset(w * 0.28f, h * 0.3f), Offset(w * 0.28f, h * 0.48f), stroke)
        drawLine(color, Offset(w * 0.72f, h * 0.3f), Offset(w * 0.72f, h * 0.48f), stroke)
        drawRoundRect(color, topLeft = Offset(w * 0.16f, h * 0.44f), size = Size(w * 0.68f, h * 0.5f), cornerRadius = CornerRadius(w * 0.1f))
    }
}

/** Rows on a card, as iOS's caregiver groups are. */
@Composable
fun CaregiverGroup(title: String? = null, detail: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        title?.let { Text(it, style = MaterialTheme.typography.titleLarge) }
        detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Surface(shape = RoundedCornerShape(16.dp), tonalElevation = 2.dp, modifier = Modifier.fillMaxWidth()) {
            Column(content = content)
        }
    }
}

/** One row of a group: tappable when it opens something, and marked when its page is open beside the list. `label` is
 * what a screen reader says for the whole row, in place of its pieces one after another. */
@Composable
fun CaregiverRow(onClick: (() -> Unit)? = null, selected: Boolean = false, label: String? = null,
    content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    var modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
    if (selected) modifier = modifier.background(MaterialTheme.colorScheme.secondaryContainer)
    if (onClick != null) modifier = modifier.clickable(onClick = onClick)
    if (label != null) modifier = modifier.clearAndSetSemantics {
        contentDescription = label
        if (onClick != null) { role = Role.Button; onClick { onClick(); true } }
    }
    Row(modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

/** A setting that's on or off, with what it means under its name. */
@Composable
fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, detail: String? = null, enabled: Boolean = true) {
    CaregiverRow {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Switch(checked, onChange, enabled = enabled)
    }
}

/** A setting changed in steps, such as seconds of ringing: its name, its value, and − and +. */
@Composable
fun StepperRow(title: String, value: String, onMinus: (() -> Unit)?, onPlus: (() -> Unit)?) {
    CaregiverRow {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        OutlinedButton(onClick = { onMinus?.invoke() }, enabled = onMinus != null) { Text("−", fontSize = 20.sp) }
        OutlinedButton(onClick = { onPlus?.invoke() }, enabled = onPlus != null) { Text("+", fontSize = 20.sp) }
    }
}

/** A row that opens something or does something. */
@Composable
fun ActionRow(title: String, detail: String? = null, onClick: () -> Unit) {
    CaregiverRow(onClick = onClick) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

/** Someone's photo in a circle, or their initials where there's none. */
@Composable
fun Avatar(name: String, photo: ByteArray? = null, size: Dp = 52.dp) {
    val bitmap = remember(photo) { photo?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }.getOrNull() } }
    if (bitmap != null) {
        Image(bitmap, contentDescription = null, Modifier.size(size).clip(CircleShape), contentScale = ContentScale.Crop)
        return
    }
    val initials = name.split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.first().uppercase() }
    Surface(Modifier.size(size).clip(CircleShape), color = MaterialTheme.colorScheme.primaryContainer) {
        Box(contentAlignment = Alignment.Center) {
            Text(initials, fontSize = (size.value * 0.36f).sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onPrimaryContainer)
        }
    }
}

/** "45 sec", "2 min" or "1 min 30 sec", as iOS shows a wait. */
fun duration(seconds: Int): String = when {
    seconds < 60 -> "$seconds sec"
    seconds % 60 == 0 -> "${seconds / 60} min"
    else -> "${seconds / 60} min ${seconds % 60} sec"
}
