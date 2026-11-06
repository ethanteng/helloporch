package com.ethanteng.helloporch

import android.animation.ValueAnimator
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ethanteng.helloporch.core.BedsidePreferences
import com.ethanteng.helloporch.core.BedsideScene
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PorchExperience
import java.time.Instant

/**
 * The bedside's clock, as iOS's clock screen lays it out: the weekday, the time and the date, fitted to the screen, on
 * night colors, or on the dynamic clock's picture when a caregiver chose it, with Call someone beneath. A keypad key
 * calls whoever is on it. Until the tablet is set up, Set up Porch takes Call someone's place, and a setup that stopped
 * after its PIN goes on from here. Caregiver mode comes in phase 4.
 */
@Composable
fun BedsideHome(app: PorchApplication, links: FamilyLinks, setup: BedsideSetup) {
    val paired = links.credential != null || app.device.credential(PorchExperience.BEDSIDE) != null
    val state = links.state
    var picking by rememberSaveable { mutableStateOf(false) }
    if (picking && state != null) { BedsidePeople(app, links, onClose = { picking = false }); return }
    // A key calls whoever is on it. The receiver put back while a call is starting stops it opening.
    if (state != null) CallKeys(app, onDigit = app.calls::bedsideKey, onHangUp = app.calls::cancelPendingCall)
    val context = LocalContext.current
    val now = rememberMinute()
    val preferences = remember(now) { BedsidePreferences.load(app.settings) }
    val language = remember(now) { BedsideText.language(app) }
    val clock = remember(now, language) { ClockText(context, language, now) }
    val scene = if (preferences.appearance == BedsidePreferences.Appearance.DYNAMIC) remember(now, preferences) {
        BedsideScene(Instant.ofEpochMilli(now), preferences)
    } else null
    val palette = remember(scene) { scene?.let { ScenePalette(it) } }
    var isHome by remember { mutableStateOf(BedsideHomeScreen.isHome(context)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { isHome = BedsideHomeScreen.isHome(context) }
    val askHome = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { isHome = BedsideHomeScreen.isHome(context) }
    fun text(english: String, vararg arguments: Any?) = BedsideText.string(app, english, *arguments)

    Box(Modifier.fillMaxSize().background(PorchColors.night)) {
        if (scene != null) ScenePictureFading(scene, Modifier.fillMaxSize())
        LargeType { BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 32.dp, vertical = 16.dp)) {
            // Fitted to the tablet, as on iOS, rather than capped at phone-sized text. The bottom is kept for calling.
            // iOS measures the safe area. This box is already inset by the padding on it: 32 dp on each side, 16 dp
            // above and below.
            val safeWidth = maxWidth + 64.dp
            val safeHeight = maxHeight + 32.dp
            val large = safeWidth >= 600.dp && safeHeight >= 500.dp
            val narrow = safeWidth < 400.dp
            val callHeight = if (large) 124.dp else if (safeHeight < 500.dp) 80.dp else 96.dp
            val width = maxOf(200f, maxWidth.value)
            val height = maxOf(80f, maxHeight.value - callHeight.value - 116f)
            val timeSize = minOf(width * 0.43f, height * 0.48f).sp
            val primary = palette?.foreground ?: PorchColors.nightText
            val secondary = palette?.foreground ?: PorchColors.nightSecondary
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.weight(1f).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(minOf(24f, height * 0.025f).dp, Alignment.CenterVertically)) {
                    if (scene != null) Text("${text(scene.period.rawValue)} · ${text(scene.season.rawValue)}", color = primary,
                        fontSize = maxOf(18f, minOf(32f, height * 0.07f)).sp, fontWeight = FontWeight.SemiBold)
                    // iOS's sizes, shrunk to fit when the words are wider than the screen, as its labels do.
                    FittedText(AnnotatedString(clock.weekday), secondary, minOf(width * 0.075f, height * 0.13f).sp, FontWeight.Medium)
                    FittedText(clock.styledTime, primary, timeSize, FontWeight.Medium, digits = true)
                    FittedText(AnnotatedString(clock.date), secondary, minOf(width * 0.061f, height * 0.11f).sp)
                }
                val calls = app.calls
                val name = state?.householdName
                val status = when {
                    !paired -> "Porch isn't set up on this tablet yet."
                    links.accessRemoved -> "This tablet isn't part of ${name?.let { "$it's" } ?: "its"} Porch anymore."
                    // A failed check-in keeps the last snapshot, which is what a dropped connection looks like.
                    links.error != null -> "Porch can't check in right now. ${links.error}"
                    state == null -> "Checking in…"
                    else -> calls.notice
                }
                // On the dynamic clock the line sits on a plate, as on iOS, so it doesn't sit on the hills.
                status?.let {
                    val plate = palette?.let { colors -> Modifier.background(colors.controlBackground.copy(alpha = 0.6f), RoundedCornerShape(10.dp))
                        .padding(horizontal = 12.dp, vertical = 6.dp) } ?: Modifier
                    Text(it, Modifier.padding(bottom = 12.dp).then(plate), color = palette?.controlForeground ?: PorchColors.nightSecondary,
                        fontSize = 22.sp, textAlign = TextAlign.Center)
                }
                val buttonColor = palette?.controlBackground?.copy(alpha = 0.6f) ?: PorchColors.nightSurface
                val buttonText = palette?.controlForeground ?: PorchColors.nightText
                when {
                    !paired -> ClockButton("Set up Porch", callHeight, buttonColor, buttonText, large, narrow) { setup.start() }
                    state != null && setup.unfinished -> ClockButton("Finish setting up Porch", callHeight, buttonColor, buttonText, large, narrow, onClick = setup::openGate)
                    state != null -> ClockButton(text(if (calls.opening) "Calling…" else "Call someone"), callHeight, buttonColor, buttonText, large, narrow,
                        enabled = !calls.opening) { picking = true }
                }
                // For a caregiver, until caregiver mode (phase 4) has a place for it: Porch should be the home screen, so
                // the tablet comes back to it after a restart and Home can't leave it.
                if (paired && !isHome) BedsideHomeScreen.request(context)?.let { ask ->
                    TextButton(onClick = { askHome.launch(ask) }) {
                        Text("Make Porch this tablet's home screen", color = palette?.controlForeground ?: PorchColors.nightSecondary, fontSize = 18.sp)
                    }
                }
            }
        } }
        // Above the clock, so a short landscape screen's date doesn't paint over it. A tap, or a hold of half a
        // second, opens the PIN, as on iOS.
        if (paired && state != null) CaregiverButton(palette?.controlForeground ?: PorchColors.nightSecondary,
            Modifier.align(Alignment.TopEnd).safeDrawingPadding().padding(8.dp), onOpen = setup::openGate)
    }
}

/** One line of the clock at `size`, or smaller until it fits the width. `digits` keeps the time's digits the same width,
 * so it doesn't shift as the minutes change. */
@Composable
private fun FittedText(text: AnnotatedString, color: Color, size: TextUnit, weight: FontWeight = FontWeight.Normal, digits: Boolean = false) {
    BasicText(text, Modifier.fillMaxWidth(), maxLines = 1,
        style = LocalTextStyle.current.merge(TextStyle(color = color, fontWeight = weight, textAlign = TextAlign.Center,
            fontFeatureSettings = if (digits) "tnum" else null)),
        autoSize = TextAutoSize.StepBased(minFontSize = 12.sp, maxFontSize = size, stepSize = 2.sp))
}

/** The gear in the clock's corner that opens caregiver mode, after the PIN. */
@Composable
private fun CaregiverButton(color: Color, modifier: Modifier, onOpen: () -> Unit) {
    // A click, so a screen reader's double-tap opens it as a touch does. The click merges its content, so the gear's
    // name goes on the glyph inside it, which is otherwise read as "⚙".
    Box(modifier.size(64.dp).clip(CircleShape)
        .combinedClickable(role = Role.Button, onClickLabel = "Open caregiver mode", onClick = onOpen, onLongClick = onOpen),
        contentAlignment = Alignment.Center) {
        Text("\u2699\uFE0E", Modifier.clearAndSetSemantics { contentDescription = "Caregiver mode" }, color = color, fontSize = 32.sp)
    }
}

/** The clock's big button: Call someone, or setting Porch up. */
@Composable
private fun ClockButton(title: String, height: Dp, color: Color, text: Color, large: Boolean, narrow: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled, modifier = Modifier.widthIn(max = 720.dp).fillMaxWidth().height(height),
        shape = RoundedCornerShape(24.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = text, disabledContainerColor = color, disabledContentColor = text.copy(alpha = 0.6f))) {
        // A longer title, such as Finish setting up Porch or another language's, shrinks to fit rather than being cut off.
        BasicText(title, maxLines = 1, style = LocalTextStyle.current.merge(TextStyle(color = if (enabled) text else text.copy(alpha = 0.6f),
            fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)),
            autoSize = TextAutoSize.StepBased(minFontSize = 16.sp, maxFontSize = if (large) 48.sp else if (narrow) 28.sp else 32.sp, stepSize = 2.sp))
    }
}

/** The dynamic clock's picture. A new minute's picture fades in over 1.5 seconds, unless animations are off. At the
 * switch between day and night it changes at once, along with the lettering, so the clock never loses contrast. */
@Composable
private fun ScenePictureFading(scene: BedsideScene, modifier: Modifier) {
    var shown by remember { mutableStateOf(scene) }
    val sameHalf = shown.isDay == scene.isDay
    LaunchedEffect(scene) { shown = scene }
    Crossfade(scene, modifier, animationSpec = if (sameHalf && ValueAnimator.areAnimatorsEnabled()) tween(1_500) else snap(), label = "scene") {
        BedsideScenePicture(it, Modifier.fillMaxSize())
    }
}

/** The caregiver PIN before setup goes on, as caregiver mode's gate asks for it on iOS. */
@Composable
fun CaregiverGate(setup: BedsideSetup) {
    var pin by rememberSaveable { mutableStateOf("") }
    BackHandler { setup.closeGate() }
    FormScreen("Caregiver mode", navigation = { TextButton(onClick = setup::closeGate) { Text("Cancel") } }) {
        FormSection("Your caregiver PIN") {
            FormField(pin, { pin = it.filter(Char::isDigit).take(6) }, "Six-digit PIN", "Enter six digits",
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), visualTransformation = PasswordVisualTransformation())
            FormButton("Open caregiver mode", onClick = { setup.unlock(pin) }, enabled = !setup.checkingPIN)
        }
        // Reachable without the PIN, so anyone at the bedside can read it.
        PrivacyPolicyLink()
    }
    PorchErrorDialog(setup.error) { setup.error = null }
}
