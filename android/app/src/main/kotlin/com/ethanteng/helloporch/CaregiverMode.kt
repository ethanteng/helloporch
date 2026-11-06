package com.ethanteng.helloporch

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyAdminState
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchNumber
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/** Caregiver mode's pages on the bedside, as iOS's CaregiverPage lists them. Messages comes with messages
 * (android/PLAN.md, phase 5). */
enum class CaregiverPage(val title: String) {
    PEOPLE("People"), CALLS("Calls"), DROP_IN("Drop-in"), DISPLAY("Display & voice"), PRIVACY("Privacy"), CAREGIVERS("Caregivers & PIN"), DEVICE("This tablet"),
}

/** Screens a caregiver opens over a page. */
enum class CaregiverScreen { NAME, NUMBER, CHANGE_PIN, CONNECT_PHONE, CONNECT_KEYPAD }

/**
 * Caregiver mode's changes, as iOS's FamilyAdminViewController makes them: each one goes to the server with the caregiver
 * PIN, and the household it sends back is shown everywhere. One change at a time. Main thread only.
 */
class CaregiverAdmin(private val app: PorchApplication, private val scope: CoroutineScope) {
    var busy by mutableStateOf(false); private set
    /** Why the last change didn't go through, until it's dismissed. */
    var error by mutableStateOf<String?>(null)
    /** The keypad as it's saved on this tablet. A saved keypad that can't be read shows empty, and saving a key starts
     * it again. */
    var slots by mutableStateOf(CallSlots()); private set
    var slotsUnreadable by mutableStateOf(false); private set

    init { reloadSlots() }

    /** Reads the keypad again, as after a check-in, which can change who a key shows. */
    fun reloadSlots() {
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
    fun saveSlots(change: (CallSlots) -> Unit): Boolean = try {
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

    /** Makes `action` with the caregiver PIN, and says whether it went through. The reason it didn't is shown. */
    suspend fun send(action: String, values: Map<String, JsonElement> = emptyMap(), pin: String? = null): Boolean {
        val credential = app.device.credential(PorchExperience.BEDSIDE)
        if (busy || credential == null) return false
        busy = true
        return try {
            app.coordinator.update(app.service(credential).send(action, values, pin = pin ?: app.caregiverPIN))
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: "Couldn't reach Porch. Check the connection and try again."
            false
        } finally {
            busy = false
        }
    }

    /** Uploads a photo a caregiver chose for a family member, then shows it for them everywhere. */
    suspend fun chooseOverridePhoto(data: ByteArray, memberID: String): Boolean {
        val credential = app.device.credential(PorchExperience.BEDSIDE)
        if (busy || credential == null) return false
        busy = true
        val photo = try {
            FamilyPhotos.upload(app, data, "overridePhotoUpload", mapOf("memberID" to JsonPrimitive(memberID)), credential, app.caregiverPIN)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: "Couldn't upload the photo. Try again."
            null
        } finally {
            busy = false
        }
        return photo != null && send("setMemberOverride", mapOf("memberID" to JsonPrimitive(memberID), "photo" to photo))
    }

    /** The household as caregiver mode sees it: who's in the family and how the household is set. */
    fun state(links: FamilyLinks): FamilyAdminState? = links.state?.let {
        FamilyAdminState(it.householdName, it.dropInEnabled, it.people.filter { person -> person.role == PorchExperience.FAMILY },
            it.messagesEnabled, it.messages, it.texts, it.phoneDropIns, it.invitations, it.callScreening, it.shareAttendance)
    }

    /** Makes `action` with the caregiver PIN, then calls `done` with whether it went through. */
    fun perform(action: String, values: Map<String, JsonElement> = emptyMap(), pin: String? = null, done: (Boolean) -> Unit = {}) {
        if (busy || app.device.credential(PorchExperience.BEDSIDE) == null) { done(false); return }
        scope.launch { done(send(action, values, pin)) }
    }
}

/**
 * Caregiver mode on the bedside: the household and the list of pages, with the open page beside it on a wide screen or
 * in its place on a narrow one, as iOS's split view does. Back closes what's open, then caregiver mode.
 */
@Composable
fun CaregiverMode(app: PorchApplication, links: FamilyLinks, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val admin = remember { CaregiverAdmin(app, scope) }
    var page by rememberSaveable { mutableStateOf<CaregiverPage?>(null) }
    var screen by rememberSaveable { mutableStateOf<CaregiverScreen?>(null) }
    val state = admin.state(links)
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
                    CaregiverList(app, links, state, page ?: CaregiverPage.PEOPLE, onClose, onPage = { page = it }, onScreen = open)
                }
                VerticalDivider()
                Column(Modifier.weight(1f).fillMaxHeight()) {
                    CaregiverPageContent(app, admin, links, page ?: CaregiverPage.PEOPLE, onBack = null, onScreen = open, onClose = onClose)
                }
            }
            page != null -> CaregiverPageContent(app, admin, links, page!!, onBack = { page = null }, onScreen = open, onClose = onClose)
            else -> CaregiverList(app, links, state, null, onClose, onPage = { page = it }, onScreen = open)
        }
    }
    PorchErrorDialog(admin.error) { admin.error = null }
}

/** Who this Porch is for, its number, and the pages. */
@Composable
private fun CaregiverList(app: PorchApplication, links: FamilyLinks, state: FamilyAdminState?, selected: CaregiverPage?, onClose: () -> Unit,
    onPage: (CaregiverPage) -> Unit, onScreen: (CaregiverScreen) -> Unit) {
    FormScreen("Caregiver mode", navigation = { TextButton(onClick = onClose) { Text("Back to clock") } }) {
        val name = state?.householdName ?: "Your loved one"
        val snapshot = links.state
        CaregiverGroup {
            CaregiverRow(onClick = { onScreen(CaregiverScreen.NAME) }) {
                Avatar(name)
                Column(Modifier.weight(1f)) {
                    Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("Change the name family see", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            // The number, or how getting one is going. One that isn't ready opens the number screen to choose again.
            val number = snapshot?.porchNumber?.let(PorchNumber::display)
            val summary = number ?: snapshot?.phoneSetup?.let { if (it.needsChoice == true) "Choose an area code" else "Getting it…" } ?: "Not set up"
            HorizontalDivider()
            CaregiverRow(onClick = if (number == null && snapshot != null) ({ onScreen(CaregiverScreen.NUMBER) }) else null) {
                Column(Modifier.weight(1f)) {
                    Text("Porch number", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(summary, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        CaregiverGroup {
            CaregiverPage.entries.forEachIndexed { index, page ->
                if (index > 0) HorizontalDivider()
                val value = when (page) {
                    CaregiverPage.CAREGIVERS -> state?.people?.count { it.caregiver == true }?.takeIf { it > 0 }?.toString()
                    else -> null
                }
                CaregiverRow(onClick = { onPage(page) }, selected = page == selected) {
                    Text(page.title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    value?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (app.device.credential(PorchExperience.BEDSIDE) == null) Text("Go back to the clock and open caregiver mode to finish setup.")
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

/** One row of a group: tappable when it opens something, and marked when its page is open beside the list. */
@Composable
fun CaregiverRow(onClick: (() -> Unit)? = null, selected: Boolean = false, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    var modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
    if (selected) modifier = modifier.background(MaterialTheme.colorScheme.secondaryContainer)
    if (onClick != null) modifier = modifier.clickable(onClick = onClick)
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
