package com.ethanteng.helloporch

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.CallTranslationLine

/** The translation colors on a call's night background, as iOS's CallTranslationColors. */
internal object TranslationColors {
    val live = Color(0xFF5FD08A)
    val link = Color(0xFF9FD1AE)
    val sheet = Color(0xFF1B2420)
    val well = Color(0xFF222D29)
    val title = Color(0xFFE4ECE6)
    val chipBorder = Color(0xFF3A4842)
    val chipChosen = Color(0xFF2E5A42)
    val stop = Color(0xFFC94A4A)
    val stopText = Color(0xFFF4C2BF)
}

/** Translate among a call's buttons, or Translating, green, while it's on. One tap turns it on in the bedside's
 * language; another turns it off. */
@Composable
internal fun TranslateButton(app: PorchApplication, translation: CallTranslation, modifier: Modifier) {
    val on = translation.isOn
    CallButton(if (on) "Translating" else "Translate", !translation.sending, onClick = translation::tapped,
        color = if (on) CallColors.answer else CallColors.control, translated = true, app = app,
        modifier = modifier.testTag("call.translation.toggle"))
}

/** Above a call's buttons: on the bedside, "Translation on" and what the translator just said to it, large; on a family
 * phone while translation is on, a card saying which language the bedside hears and the latest exchange, which opens
 * the translation sheet. As iOS lays them out. It's at most [maxHeight] tall, so the call's buttons always fit; longer
 * words scroll inside it. */
@Composable
internal fun TranslationControls(app: PorchApplication, translation: CallTranslation, maxHeight: Dp, modifier: Modifier = Modifier) {
    if (translation.bedside) {
        if (!translation.showsCaption) return
        Column(modifier.fillMaxWidth().heightIn(max = maxHeight).background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(16.dp))
            .padding(12.dp).testTag("call.translation"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(BedsideText.string(app, "Translation on"), color = CallColors.secondary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            translation.caption?.let {
                // A new caption starts at its beginning.
                val scroll = rememberScrollState()
                LaunchedEffect(it) { scroll.scrollTo(0) }
                Text(it, Modifier.weight(1f, fill = false).verticalScroll(scroll).testTag("call.translation.caption"), color = Color.White,
                    fontSize = 30.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            }
        }
        return
    }
    if (translation.sheetOpen && translation.isOn) TranslationSheet(translation)
    val on = translation.isOn
    if (!on && translation.problem == null) return
    Column(modifier.fillMaxWidth().heightIn(max = maxHeight).background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(16.dp))
        .padding(horizontal = 12.dp, vertical = 6.dp).testTag("call.translation"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        val language = translation.language
        if (on) CardHeader(translation, language)
        val hint = on && !translation.starting && language != null && translation.lines.isEmpty() && translation.problem == null
        if (hint || (on && translation.lines.isNotEmpty())) {
            // The latest exchange takes what's left under the header, scrolled to the newest line.
            val scroll = rememberScrollState()
            LaunchedEffect(translation.lines.size, scroll.maxValue) { scroll.scrollTo(scroll.maxValue) }
            Column(Modifier.weight(1f, fill = false).verticalScroll(scroll).padding(bottom = 6.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (hint && language != null) {
                    Text("Talk as you usually do, even mixing languages. ${translation.peerName} hears it in ${language.displayName} and sees the words on screen.",
                        color = CallColors.secondary, fontSize = 16.sp)
                }
                if (on && translation.lines.isNotEmpty()) {
                    Column(Modifier.fillMaxWidth().testTag("call.translation.transcript"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        translation.lines.takeLast(2).forEach { Entry(translation, it, maxLines = 3) }
                    }
                }
            }
        }
        // Under the exchange, so a change that didn't go through stays visible when the card is full.
        translation.problem?.let { Text(it, Modifier.fillMaxWidth().padding(bottom = 6.dp), color = CallColors.secondary, fontSize = 15.sp) }
    }
}

/** Which language the bedside hears, and Change, which opens the sheet. */
@Composable
private fun CardHeader(translation: CallTranslation, language: BedsideLanguage?) {
    val starting = translation.starting || language == null
    val title = if (starting) "Starting translation…" else "${translation.peerName} hears ${language!!.displayName}"
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(enabled = !translation.sending, role = Role.Button,
        onClickLabel = "Change the language, see the conversation or stop translating", onClick = translation::openSheet)
        .semantics { if (!starting) contentDescription = "${translation.peerName} hears ${language!!.choiceLabel}" }
        .testTag("call.translation.language"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        LiveDot()
        Text(title, Modifier.weight(1f), color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 2,
            overflow = TextOverflow.Ellipsis)
        if (!starting) Text("Change ›", color = TranslationColors.link, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun LiveDot() = Box(Modifier.size(9.dp).background(TranslationColors.live, CircleShape))

/** The card's sheet: the language the bedside hears for this call, the conversation so far, and Stop translating. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TranslationSheet(translation: CallTranslation) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val screen = LocalConfiguration.current.screenHeightDp.dp
    ModalBottomSheet(onDismissRequest = translation::closeSheet, sheetState = state, containerColor = TranslationColors.sheet,
        contentColor = TranslationColors.title, modifier = Modifier.testTag("call.translation.sheet")) {
        Column(Modifier.fillMaxWidth().heightIn(max = screen * 0.8f).padding(horizontal = 20.dp).navigationBarsPadding().padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LiveDot()
                Text("Translating", Modifier.weight(1f).semantics { heading() }, fontSize = 22.sp, color = TranslationColors.title)
                TextButton(onClick = translation::closeSheet, modifier = Modifier.semantics { contentDescription = "Close" }) {
                    Text("✕", color = CallColors.text, fontSize = 20.sp)
                }
            }
            Section("${translation.peerName} hears")
            val current = translation.language
            FlowRow(Modifier.fillMaxWidth().testTag("call.translation.languages"), horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                BedsideLanguage.entries.forEach { option -> LanguageChip(option, option == current, !translation.sending) { translation.choose(option) } }
            }
            Section("Conversation")
            if (translation.lines.isEmpty()) Text("Nothing said yet.", color = CallColors.secondary, fontSize = 15.sp)
            else {
                // Newest at the bottom, in view.
                val scroll = rememberScrollState()
                LaunchedEffect(translation.lines.size, scroll.maxValue) { scroll.scrollTo(scroll.maxValue) }
                Column(Modifier.weight(1f, fill = false).fillMaxWidth().background(TranslationColors.well, RoundedCornerShape(14.dp))
                    .verticalScroll(scroll).padding(horizontal = 16.dp, vertical = 14.dp).testTag("call.translation.conversation"),
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    translation.lines.forEach { Entry(translation, it, maxLines = Int.MAX_VALUE) }
                }
            }
            translation.problem?.let { Text(it, color = CallColors.secondary, fontSize = 15.sp) }
            OutlinedButton(onClick = translation::stop, enabled = !translation.sending, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
                .testTag("call.translation.stop"), border = BorderStroke(1.5.dp, TranslationColors.stop),
                colors = ButtonDefaults.outlinedButtonColors(containerColor = TranslationColors.stop.copy(alpha = 0.18f), contentColor = TranslationColors.stopText)) {
                Text("Stop translating", fontSize = 18.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun Section(text: String) =
    Text(text, Modifier.semantics { heading() }, color = TranslationColors.link, fontSize = 14.sp, fontWeight = FontWeight.Medium)

@Composable
private fun LanguageChip(option: BedsideLanguage, chosen: Boolean, enabled: Boolean, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = enabled, shape = RoundedCornerShape(8.dp), contentPadding = PaddingValues(horizontal = 14.dp),
        border = BorderStroke(1.5.dp, if (chosen) TranslationColors.live else TranslationColors.chipBorder),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = if (chosen) TranslationColors.chipChosen else Color.Transparent,
            contentColor = TranslationColors.title, disabledContentColor = TranslationColors.title.copy(alpha = 0.6f)),
        modifier = Modifier.heightIn(min = 48.dp).widthIn(min = 48.dp).semantics { selected = chosen; contentDescription = option.choiceLabel }) {
        Text((if (chosen) "✓  " else "") + option.displayName, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

/** One thing said. Their words in your language first, what they actually said below; your words, then what the
 * bedside heard. */
@Composable
private fun Entry(translation: CallTranslation, line: CallTranslationLine, maxLines: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (line.fromBedside) {
            Text("${line.name}: ${line.said ?: line.heard}", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = maxLines)
            if (line.said != null) Text(line.heard, color = CallColors.secondary, fontSize = 15.sp, maxLines = maxLines)
        } else {
            val who = if (translation.isMine(line)) "You" else line.name
            Text("$who: ${line.heard}", color = CallColors.secondary, fontSize = 15.sp, maxLines = maxLines)
            line.said?.let { Text("${translation.peerName} hears: $it", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = maxLines) }
        }
    }
}
