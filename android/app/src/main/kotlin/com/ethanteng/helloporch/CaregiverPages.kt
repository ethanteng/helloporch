package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.icu.text.DateFormat as IcuDateFormat
import android.media.AudioAttributes
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ethanteng.helloporch.core.BedsideAttendance
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.BedsidePreferences
import com.ethanteng.helloporch.core.BedsideScene
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PorchExperience
import java.time.Instant
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/** One of caregiver mode's pages. `onBack` is there when the page has the screen to itself. */
@Composable
fun CaregiverPageContent(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, page: CaregiverPage, onBack: (() -> Unit)?,
    onScreen: (CaregiverScreen) -> Unit, onClose: () -> Unit) {
    // People opens a person, a key or an invitation in its own place, with its own bar.
    when (page) {
        CaregiverPage.PEOPLE -> { PeoplePages(app, admin, links, onBack); return }
        CaregiverPage.CALLS -> { CallsPages(app, admin, links, onBack); return }
        CaregiverPage.DROP_IN -> { DropInPages(app, admin, links, onBack); return }
        CaregiverPage.MESSAGES -> { MessagesPages(app, admin, links, onBack); return }
        // Its list of licenses scrolls by itself.
        CaregiverPage.ABOUT -> { AboutScreen(navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }); return }
        else -> {}
    }
    FormScreen(page.title(admin.onBedside), navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }) {
        when (page) {
            CaregiverPage.PEOPLE, CaregiverPage.CALLS, CaregiverPage.DROP_IN, CaregiverPage.MESSAGES, CaregiverPage.ABOUT -> {}
            CaregiverPage.DISPLAY -> DisplayPage(app, admin, links)
            CaregiverPage.PRIVACY -> PrivacyPage(app, admin, links)
            CaregiverPage.CAREGIVERS -> CaregiversPage(admin, links, onScreen)
            CaregiverPage.DEVICE -> DevicePage(app, onScreen, onClose)
        }
    }
}

/** A screen opened over a page, such as the household's name. */
@Composable
fun CaregiverScreenContent(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, screen: CaregiverScreen, onDone: () -> Unit) {
    val lovedOne = admin.state(links)?.householdName ?: "your loved one"
    when (screen) {
        CaregiverScreen.NAME -> HouseholdNameScreen(admin, links, onDone)
        CaregiverScreen.CHANGE_PIN -> ChangePINScreen(app, admin, onDone)
        CaregiverScreen.NUMBER -> {
            val scope = rememberCoroutineScope()
            val number = remember { SetupNumber(app, scope, { lovedOne }, onError = { admin.error = it }).also { it.load() } }
            // Setup puts this in its own bar. Without one here, the page has no Back and draws under the status bar.
            FormScreen("Porch number", navigation = { TextButton(onClick = onDone) { Text("Back") } }) {
                SetupNumberScreen(number, lovedOne, onContinue = onDone)
            }
        }
        CaregiverScreen.CONNECT_PHONE -> CordedPhoneSetup(app.cell2jack, onDone = onDone, onBack = onDone)
        CaregiverScreen.CONNECT_KEYPAD -> FormScreen("Connect the USB keypad", navigation = { TextButton(onClick = onDone) { Text("Back") } }) {
            SetupUSBKeypadScreen(lovedOne, onContinue = onDone)
        }
    }
}

// MARK: Calls

private enum class CallsScreen { HISTORY, BLOCKED }

/** The Calls page, or call history or blocked numbers opened from it in its place. */
@Composable
fun CallsPages(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onBack: (() -> Unit)?) {
    var screen by rememberSaveable { mutableStateOf<CallsScreen?>(null) }
    LaunchedEffect(screen) { if (screen != null) admin.refresh() }
    when (screen) {
        null -> FormScreen(CaregiverPage.CALLS.title(admin.onBedside), navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }) {
            CallsPage(app, admin, links, onHistory = { screen = CallsScreen.HISTORY }, onBlocked = { screen = CallsScreen.BLOCKED })
        }
        CallsScreen.HISTORY -> CallHistoryScreen(app, admin, onDone = { screen = null })
        CallsScreen.BLOCKED -> BlockedNumbersScreen(admin, links, onDone = { screen = null })
    }
}

/** Calls to and from the bedside, as iOS's CallSettingsViewController sets them. Ringing and screening are kept with the
 * household; phone fallback, leaving a message and hanging up after silence are the tablet's own. Changes apply at once.
 * A family phone, as on iOS, sets who can ring and sees call history; the rest is set on the bedside. */
@Composable
private fun CallsPage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onHistory: () -> Unit, onBlocked: () -> Unit) {
    val snapshot = admin.snapshot(links)
    val name = admin.state(links)?.householdName ?: "your loved one"
    val screening = admin.state(links)?.callScreening
    val settings = app.settings
    // What the page shows while a change saves. A change that fails goes back to what's saved.
    var ring by remember(snapshot?.ringSeconds) { mutableIntStateOf(snapshot?.ringSeconds ?: CallPreferences.defaultVoicemailSeconds) }
    fun changeRing(seconds: Int) {
        val previous = ring
        ring = seconds
        admin.perform("setRingSeconds", mapOf("seconds" to JsonPrimitive(seconds))) { saved -> if (!saved) ring = previous }
    }
    val ringRange = CallPreferences.voicemailRange
    CaregiverGroup("Calls to $name") {
        if (admin.onBedside) {
            StepperRow("Ring before voicemail", if (snapshot == null) "–" else duration(ring),
                onMinus = (snapshot != null && !admin.busy && ring - 5 >= ringRange.first).then { changeRing(ring - 5) },
                onPlus = (snapshot != null && !admin.busy && ring + 5 <= ringRange.last).then { changeRing(ring + 5) })
            HorizontalDivider()
        }
        ToggleRow("Block unknown callers", screening?.enabled == true,
            onChange = { admin.perform("setBlockUnknownCallers", mapOf("enabled" to JsonPrimitive(it))) },
            detail = when {
                screening == null -> "Not available on this Porch's server yet."
                screening.enabled -> "Only keypad contacts and numbers you allow can ring."
                else -> null
            }, enabled = screening != null && !admin.busy)
        HorizontalDivider()
        val blocked = screening?.blocked.orEmpty()
        // Who called while unknown callers were blocked, and the numbers allowed since.
        CaregiverRow(onClick = screening?.let { onBlocked }) {
            Column(Modifier.weight(1f)) {
                Text("Blocked numbers", style = MaterialTheme.typography.titleMedium)
                screening?.allowed?.takeIf { it.isNotEmpty() }?.let { Text("${it.size} allowed", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            Text(if (blocked.isEmpty()) "None" else "${blocked.size}", style = MaterialTheme.typography.titleMedium)
            if (screening != null) Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (!admin.onBedside) {
        CaregiverGroup { CallHistoryRow(onHistory) }
        return
    }
    var fallback by remember { mutableIntStateOf(CallPreferences.fallbackSeconds(settings)) }
    var leaveMessage by remember { mutableStateOf(CallPreferences.leaveMessageWhenUnanswered(settings)) }
    val fallbackRange = CallPreferences.fallbackRange
    CaregiverGroup("Calls from $name", "If Porch isn't answered, Porch calls the person's phone.") {
        fun changeFallback(seconds: Int) { CallPreferences.saveFallbackSeconds(seconds, settings); fallback = CallPreferences.fallbackSeconds(settings) }
        StepperRow("Try their phone after", duration(fallback),
            onMinus = (fallback - 5 >= fallbackRange.first).then { changeFallback(fallback - 5) },
            onPlus = (fallback + 5 <= fallbackRange.last).then { changeFallback(fallback + 5) })
        HorizontalDivider()
        ToggleRow("Leave a message if no one answers", leaveMessage, onChange = {
            CallPreferences.saveLeaveMessageWhenUnanswered(it, settings); leaveMessage = it
        })
    }
    var silence by remember { mutableStateOf(CallPreferences.disconnectAfterSilence(settings)) }
    var silenceSeconds by remember { mutableIntStateOf(CallPreferences.silenceSeconds(settings)) }
    CaregiverGroup("All calls") {
        ToggleRow("End calls after silence", silence, onChange = {
            CallPreferences.saveSilence(it, silenceSeconds, settings); silence = it
        })
        if (silence) {
            HorizontalDivider()
            // Whole minutes, from 1 to 30. A time an older version saved in seconds moves to a whole minute on its first change.
            fun changeSilence(minutes: Int) {
                CallPreferences.saveSilence(true, CallPreferences.silenceSeconds(minutes, silenceSeconds), settings)
                silenceSeconds = CallPreferences.silenceSeconds(settings)
            }
            val minutes = silenceSeconds / 60
            val partial = silenceSeconds % 60 != 0
            StepperRow("After no one talks for", duration(silenceSeconds),
                onMinus = (minutes > 1 || (partial && minutes >= 1)).then { changeSilence(if (partial) minutes else minutes - 1) },
                onPlus = (minutes < CallPreferences.silenceRange.last / 60).then { changeSilence(minutes + 1) })
        }
        HorizontalDivider()
        CallHistoryRow(onHistory)
        HorizontalDivider()
        SoundTests(app)
    }
}

@Composable
private fun CallHistoryRow(onClick: () -> Unit) {
    CaregiverRow(onClick = onClick) {
        Text("Call history", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
        Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Ringing and the drop-in announcement, played as they would be for a call, with no call placed. */
@Composable
private fun SoundTests(app: PorchApplication) {
    val ring = remember { TonePlayer(AudioAttributes.USAGE_NOTIFICATION_RINGTONE) }
    val announcer = remember { Announcer(app) }
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) { onDispose { ring.stop(); announcer.stop() } }
    Column(Modifier.padding(16.dp)) {
        Text("Test sounds", style = MaterialTheme.typography.titleMedium)
        androidx.compose.foundation.layout.Row(Modifier.padding(top = 8.dp), horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = {
                announcer.stop()
                status = if (ring.play(CallTone.INCOMING)) "Playing a three-second ringing test." else "Couldn't play the sound. Check the tablet's volume and try again."
                scope.launch { delay(3_000); ring.stop() }
            }, Modifier.weight(1f)) { Text("Ringing") }
            OutlinedButton(onClick = {
                ring.stop()
                status = "Playing the drop-in announcement in the bedside language."
                announcer.announceDropIn(BedsideText.string(app, "A family member"), video = true) { said ->
                    status = if (said) "Announcement finished. No call was placed." else "Couldn't play the announcement. Check the tablet's volume."
                }
            }, Modifier.weight(1f)) { Text("Drop-in announcement") }
        }
        status?.let { Text(it, Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

// MARK: Display & voice

/**
 * The clock and the bedside's voice, as iOS's BedsideDisplaySettingsViewController sets them. Changes wait for Save:
 * the clock and built-in voice stay on this tablet, and the language and natural voices are saved with the household
 * too, since phone voicemail greets callers in the bedside's language.
 */
@Composable
private fun DisplayPage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks) {
    var draft by remember { mutableStateOf(BedsidePreferences.load(app.settings)) }
    /** Natural voice choices not saved yet, by language. A null value is the built-in voice. */
    var naturalDrafts by remember { mutableStateOf(mapOf<BedsideLanguage, String?>()) }
    var saved by remember { mutableStateOf<String?>(null) }
    val natural = links.state?.speech
    val language = draft.language
    fun naturalVoice(of: BedsideLanguage): String? = if (of in naturalDrafts) naturalDrafts[of] else natural?.choices(of)?.selected

    FormSection("Clock") {
        Choices(listOf("Dark", "Day & night"), if (draft.appearance == BedsidePreferences.Appearance.DYNAMIC) 1 else 0, Modifier.fillMaxWidth()) {
            draft = draft.copy(appearance = if (it == 1) BedsidePreferences.Appearance.DYNAMIC else BedsidePreferences.Appearance.DEFAULT); saved = null
        }
        if (draft.appearance == BedsidePreferences.Appearance.DYNAMIC) {
            val scene = BedsideScene(Instant.now(), draft)
            Box(Modifier.fillMaxWidth().height(210.dp).clip(RoundedCornerShape(20.dp)), contentAlignment = Alignment.Center) {
                BedsideScenePicture(scene, Modifier.fillMaxSize())
                Text(IcuDateFormat.getDateTimeInstance(IcuDateFormat.MEDIUM, IcuDateFormat.SHORT, language.locale).format(Date()),
                    color = ScenePalette(scene).foreground, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
    FormSection("Bedside language") {
        CaregiverGroup {
            BedsideLanguage.entries.forEachIndexed { index, choice ->
                if (index > 0) HorizontalDivider()
                CaregiverRow(onClick = { draft = draft.copy(language = choice); saved = null }) {
                    RadioButton(choice == language, onClick = null)
                    Text(choice.choiceLabel, style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    }
    AnnouncementVoice(app, language, draft.announcementVoiceIdentifier(language), natural?.choices(language), naturalVoice(language),
        onBuiltIn = { draft = draft.withAnnouncementVoiceIdentifier(it, language); if (natural?.choices(language) != null) naturalDrafts = naturalDrafts + (language to null); saved = null },
        onNatural = { naturalDrafts = naturalDrafts + (language to it); saved = null })
    if (draft.appearance == BedsidePreferences.Appearance.DYNAMIC) {
        val locale = LocalConfiguration.current.locales[0]
        fun hour(value: Int) = IcuDateFormat.getInstanceForSkeleton("j", locale)
            .format(Date.from(java.time.LocalDate.of(2026, 1, 1).atTime(value, 0).atZone(java.time.ZoneId.systemDefault()).toInstant()))
        FormSection("Day & night") {
            CaregiverGroup {
                StepperRow("Day begins", hour(draft.dayStart),
                    onMinus = (draft.dayStart > 0).then { draft = draft.copy(dayStart = draft.dayStart - 1); saved = null },
                    onPlus = (draft.dayStart < 11).then { draft = draft.copy(dayStart = draft.dayStart + 1); saved = null })
                HorizontalDivider()
                StepperRow("Night begins", hour(draft.nightStart),
                    onMinus = (draft.nightStart > 12).then { draft = draft.copy(nightStart = draft.nightStart - 1); saved = null },
                    onPlus = (draft.nightStart < 23).then { draft = draft.copy(nightStart = draft.nightStart + 1); saved = null })
            }
        }
        FormSection("Seasons") {
            Choices(listOf("Northern", "Southern"), if (draft.hemisphere == BedsidePreferences.Hemisphere.NORTHERN) 0 else 1, Modifier.fillMaxWidth()) {
                draft = draft.copy(hemisphere = if (it == 0) BedsidePreferences.Hemisphere.NORTHERN else BedsidePreferences.Hemisphere.SOUTHERN); saved = null
            }
        }
    }
    FormButton(if (admin.busy) "Saving…" else "Save", onClick = {
        draft.save(app.settings)
        val report = links.state?.languageToReport(draft.language)
        val changes = naturalDrafts.filter { (choice, voice) -> natural?.choices(choice) != null && natural.choices(choice)?.selected != voice }
        // One change at a time, each with the caregiver PIN, then the page says it's saved.
        val steps = buildList<Pair<String, Map<String, kotlinx.serialization.json.JsonElement>>> {
            report?.let { add("setBedsideLanguage" to mapOf("language" to JsonPrimitive(it.code))) }
            changes.forEach { (choice, voice) -> add("setSpeechVoice" to mapOf("language" to JsonPrimitive(choice.code), "voiceID" to (voice?.let(::JsonPrimitive) ?: JsonNull))) }
        }
        fun next(index: Int) {
            if (index == steps.size) { naturalDrafts = emptyMap(); saved = "Saved."; return }
            admin.perform(steps[index].first, steps[index].second) { ok -> if (ok) next(index + 1) }
        }
        next(0)
    }, enabled = !admin.busy)
    saved?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
}

/** The announcement voice for the bedside's language: the household's natural voices, and the tablet's own. */
@Composable
private fun AnnouncementVoice(app: PorchApplication, language: BedsideLanguage, builtIn: String?, choices: com.ethanteng.helloporch.core.NaturalVoices.Choices?,
    natural: String?, onBuiltIn: (String?) -> Unit, onNatural: (String) -> Unit) {
    var voices by remember(language) { mutableStateOf(app.speech.voices(language)) }
    // The engine may still be starting when the page opens.
    LaunchedEffect(language) { repeat(10) { if (voices.isNotEmpty()) return@LaunchedEffect; delay(500); voices = app.speech.voices(language) } }
    var open by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    val announcer = remember { Announcer(app) }
    DisposableEffect(Unit) { onDispose { announcer.stop() } }
    val naturalChoice = natural?.let { id -> choices?.voices?.firstOrNull { it.id == id } }
    val chosen = voices.firstOrNull { it.name == builtIn }
    val title = naturalChoice?.let { "${it.name} · Natural" } ?: chosen?.let { voiceLabel(it) } ?: "System default"
    FormSection("Announcement voice") {
        Box {
            OutlinedButton(onClick = { open = true }, Modifier.fillMaxWidth()) { Text(title) }
            DropdownMenu(open, onDismissRequest = { open = false }) {
                choices?.voices?.forEach { voice ->
                    DropdownMenuItem(text = { Text("${voice.name} · ${voice.detail}") }, onClick = { open = false; onNatural(voice.id) })
                }
                if (choices != null) HorizontalDivider()
                DropdownMenuItem(text = { Text("System default") }, onClick = { open = false; onBuiltIn(null) })
                voices.forEach { voice -> DropdownMenuItem(text = { Text(voiceLabel(voice)) }, onClick = { open = false; onBuiltIn(voice.name) }) }
            }
        }
        val note = when {
            naturalChoice != null && choices?.selected != naturalChoice.id -> "Tap Save to use ${naturalChoice.name}."
            naturalChoice == null && voices.isEmpty() ->
                "No voice is available for ${language.displayName}. Add one in Android Settings → Accessibility → Text-to-speech output. Until then, drop-ins must be answered."
            builtIn != null && chosen == null && naturalChoice == null -> "The saved voice isn't available, so the tablet's own voice is used for now."
            else -> null
        }
        note?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        FormButton("Preview announcement", filled = false, onClick = {
            status = "Playing the voice…"
            // In the language being chosen, which may not be saved yet.
            val message = language.format("%@ is dropping in with video. Connecting in five seconds.", language.text("A family member"))
            announcer.speak(message, language, builtIn, natural, naturalWait = 8_000) { said ->
                status = if (said) "Preview completed. Tap Save to keep your choice." else "Couldn't play the preview. Check the tablet's volume."
            }
        })
        status?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

private fun voiceLabel(voice: android.speech.tts.Voice): String {
    val region = voice.locale.getDisplayName(java.util.Locale.ENGLISH)
    return "$region · ${voice.name}${if (voice.isNetworkConnectionRequired) " · Online" else ""}"
}

/** Two or three choices side by side, as iOS's segmented controls are. */
@Composable
fun Choices(options: List<String>, selected: Int, modifier: Modifier = Modifier, onSelect: (Int) -> Unit) {
    SingleChoiceSegmentedButtonRow(modifier) {
        options.forEachIndexed { index, option ->
            SegmentedButton(index == selected, onClick = { onSelect(index) }, shape = SegmentedButtonDefaults.itemShape(index, options.size)) { Text(option) }
        }
    }
}

// MARK: Privacy

/** What family learn about someone being at the tablet. Sharing it is kept with the household, so a phone can change it
 * too. The camera check uses this tablet's own camera, so only the tablet shows that switch, kept on the tablet. */
@Composable
private fun PrivacyPage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks) {
    val share = admin.state(links)?.shareAttendance
    val context = LocalContext.current
    var camera by remember { mutableStateOf(BedsideAttendance.cameraEnabled(app.settings)) }
    val refused = "Allow camera access in Settings → Apps → Porch → Permissions to tell family when someone is at the tablet."
    val askCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            // The activity may have been recreated while Android's question was up, which drops the switch's own state.
            camera = true
            BedsideAttendance.setCameraEnabled(true, app.settings)
        } else {
            camera = false
            admin.error = refused
        }
    }
    // Camera access taken away in Settings since the switch was turned on: the clock can't look, so the switch says so.
    // Opening Privacy checks, and so does coming back to it, such as after turning access off in Settings.
    fun cameraAccessTakenAway() {
        if (admin.onBedside && camera && ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            camera = false
            BedsideAttendance.setCameraEnabled(false, app.settings)
            admin.error = refused
        }
    }
    LaunchedEffect(Unit) { cameraAccessTakenAway() }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { cameraAccessTakenAway() }
    CaregiverGroup {
        ToggleRow("Show family when someone is at the ${bedsideDevice(admin.snapshot(links))}", share == true,
            onChange = { admin.perform("setShareAttendance", mapOf("enabled" to JsonPrimitive(it))) },
            detail = if (share == null) "Not available on this Porch's server yet." else "Touches and key presses count.",
            enabled = share != null && !admin.busy)
        if (admin.onBedside) {
            HorizontalDivider()
            // Only while family are shown it. The clock reads the switch again when caregiver mode closes.
            ToggleRow("Check with the camera", camera, detail = "About every 30 seconds. Nothing is recorded.", enabled = share == true,
                onChange = { on ->
                    camera = on
                    when {
                        !on -> BedsideAttendance.setCameraEnabled(false, app.settings)
                        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED ->
                            BedsideAttendance.setCameraEnabled(true, app.settings)
                        // Turned back off if Android's question is refused.
                        else -> askCamera.launch(Manifest.permission.CAMERA)
                    }
                })
        }
    }
    PrivacyPolicyLink()
}

// MARK: Caregivers & PIN

/** Who can open caregiver mode from their phone with the PIN, and on the bedside, the PIN itself. A caregiver's phone
 * can't take its own access away: another caregiver can. */
@Composable
private fun CaregiversPage(admin: CaregiverAdmin, links: FamilyLinks, onScreen: (CaregiverScreen) -> Unit) {
    Text("Caregivers can change settings from their phone with the PIN.", style = MaterialTheme.typography.bodyLarge)
    val people = admin.state(links)?.people.orEmpty()
    CaregiverGroup {
        if (people.isEmpty()) CaregiverRow { Text("No family members yet.") }
        people.forEachIndexed { index, person ->
            if (index > 0) HorizontalDivider()
            val isMe = person.id == admin.myID
            ToggleRow(if (isMe) "${person.name} (this phone)" else person.name, person.caregiver == true, enabled = !admin.busy && !isMe,
                detail = if (isMe) "Another caregiver can change this." else null,
                onChange = { admin.perform("setCaregiver", mapOf("memberID" to JsonPrimitive(person.id), "enabled" to JsonPrimitive(it))) })
        }
    }
    if (admin.onBedside) CaregiverGroup { ActionRow("Change caregiver PIN") { onScreen(CaregiverScreen.CHANGE_PIN) } }
}

@Composable
private fun ChangePINScreen(app: PorchApplication, admin: CaregiverAdmin, onDone: () -> Unit) {
    var current by rememberSaveable { mutableStateOf("") }
    var new by rememberSaveable { mutableStateOf("") }
    var confirm by rememberSaveable { mutableStateOf("") }
    FormScreen("Change caregiver PIN", navigation = { TextButton(onClick = onDone) { Text("Cancel") } }) {
        FormSection("Your six-digit PIN") {
            val pin = KeyboardOptions(keyboardType = KeyboardType.NumberPassword)
            FormField(current, { current = it.filter(Char::isDigit).take(6) }, "Current PIN", "Six digits", keyboardOptions = pin, visualTransformation = PasswordVisualTransformation())
            FormField(new, { new = it.filter(Char::isDigit).take(6) }, "New PIN", "Six digits", keyboardOptions = pin, visualTransformation = PasswordVisualTransformation())
            FormField(confirm, { confirm = it.filter(Char::isDigit).take(6) }, "Confirm new PIN", "Repeat the new PIN", keyboardOptions = pin, visualTransformation = PasswordVisualTransformation())
            FormButton(if (admin.busy) "Saving…" else "Save new PIN", enabled = !admin.busy, onClick = {
                if (new.length != 6 || new != confirm) { admin.error = "Enter the same six digits in both new PIN fields."; return@FormButton }
                val chosen = new
                admin.perform("setCaregiverPIN", mapOf("pin" to JsonPrimitive(chosen)), pin = current) { ok ->
                    if (ok) { app.caregiverPIN = chosen; onDone() }
                }
            })
        }
    }
}

// MARK: Name

@Composable
private fun HouseholdNameScreen(admin: CaregiverAdmin, links: FamilyLinks, onDone: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(admin.state(links)?.householdName.orEmpty()) }
    FormScreen("Name", navigation = { TextButton(onClick = onDone) { Text("Cancel") } }) {
        FormField(name, { name = it }, "Who is this Porch for?", "Your loved one",
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        FormButton(if (admin.busy) "Saving…" else "Save", enabled = !admin.busy && name.isNotBlank(), onClick = {
            admin.perform("setHouseholdName", mapOf("name" to JsonPrimitive(name.trim()))) { ok -> if (ok) onDone() }
        })
    }
}

// MARK: This tablet

/** The tablet itself: the corded phone or a USB keypad as its keypad, Porch as its home screen, Android's settings, and
 * what the tablet is used as. */
@Composable
private fun DevicePage(app: PorchApplication, onScreen: (CaregiverScreen) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    val keypad = app.cell2jack
    val enabled by keypad.enabled.collectAsStateWithLifecycle()
    var receiverHangUp by remember { mutableStateOf(keypad.receiverHangUp) }
    CaregiverGroup("Cell2Jack phone keypad", "Plug the Cell2Jack into this tablet's USB port.") {
        ActionRow("Connect the phone") { onScreen(CaregiverScreen.CONNECT_PHONE) }
        HorizontalDivider()
        ToggleRow("Use Cell2Jack phone keypad", enabled, onChange = keypad::setEnabled)
        HorizontalDivider()
        ToggleRow("Hang up when the receiver is put back", receiverHangUp, onChange = { keypad.setReceiverHangUp(it); receiverHangUp = it })
        HorizontalDivider()
        ActionRow("Retry phone connection") { keypad.retry() }
        HorizontalDivider()
        ActionRow("Open app settings") { open(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))) }
    }
    CaregiverGroup("USB keypad", "A number keypad plugged into this tablet works as Porch's keypad.") {
        ActionRow("Connect the USB keypad") { onScreen(CaregiverScreen.CONNECT_KEYPAD) }
    }
    var isHome by remember { mutableStateOf(BedsideHomeScreen.isHome(context)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { isHome = BedsideHomeScreen.isHome(context) }
    val askHome = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { isHome = BedsideHomeScreen.isHome(context) }
    val makeHome = if (isHome) null else BedsideHomeScreen.request(context)
    CaregiverGroup("Home screen", if (isHome) "Porch comes back after a restart, and Home returns to it." else "Make Porch the home screen so it comes back after a restart.") {
        if (isHome) ActionRow("Choose another home screen") { open(context, Intent(Settings.ACTION_HOME_SETTINGS)) }
        else makeHome?.let { ask -> ActionRow("Make Porch the home screen") { askHome.launch(ask) } }
        if (isHome || makeHome != null) HorizontalDivider()
        ActionRow("Tablet settings", "Android's own settings, such as Wi-Fi and the volume.") { open(context, Intent(Settings.ACTION_SETTINGS)) }
    }
    // Ringing while Porch isn't in front needs notifications, which a tablet set up before Porch could ring that way
    // was never asked for.
    RingWhenClosed(app, bedside = true)
    var confirming by remember { mutableStateOf(false) }
    CaregiverGroup { ActionRow("Use this tablet as a family device") { confirming = true } }
    PrivacyPolicyLink()
    if (confirming) AlertDialog(onDismissRequest = { confirming = false },
        title = { Text("Use this tablet as a family device?") },
        text = { Text("For calling the bedside Porch from this tablet. You can switch back later.") },
        confirmButton = { TextButton(onClick = { confirming = false; onClose(); app.switchExperience(PorchExperience.FAMILY) }) { Text("Use as family device") } },
        dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } })
}

private fun open(context: Context, intent: Intent) {
    try { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: ActivityNotFoundException) {}
}

/** `block` when this is true, for a − or + that can't go further. */
private fun Boolean.then(block: () -> Unit): (() -> Unit)? = if (this) block else null
