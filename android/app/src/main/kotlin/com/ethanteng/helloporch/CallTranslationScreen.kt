package com.ethanteng.helloporch

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.BedsideLanguage

/** Above a call's buttons: on the bedside, "Translation on" and what the translator just said to it, large; on a family
 * phone, the Translate switch, the language the bedside hears, and the last few things said. As iOS lays them out. */
@Composable
internal fun TranslationControls(app: PorchApplication, translation: CallTranslation) {
    if (translation.bedside) {
        if (!translation.showsCaption) return
        Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(16.dp)).padding(12.dp)
            .testTag("call.translation"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(BedsideText.string(app, "Translation on"), color = CallColors.secondary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            translation.caption?.let {
                Text(it, Modifier.testTag("call.translation.caption"), color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center)
            }
        }
        return
    }
    if (!translation.offered) return
    Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(16.dp)).padding(12.dp)
        .testTag("call.translation"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (translation.isOn) Transcript(translation)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Translate", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Box(Modifier.weight(1f)) { LanguageChoice(translation) }
            Switch(translation.isOn, onCheckedChange = translation::toggle, enabled = !translation.sending,
                modifier = Modifier.testTag("call.translation.toggle").semantics { contentDescription = "Translate" },
                colors = SwitchDefaults.colors(checkedTrackColor = CallColors.answer))
        }
        translation.notice?.let { Text(it, Modifier.fillMaxWidth(), color = CallColors.secondary, fontSize = 15.sp, textAlign = TextAlign.Center) }
    }
}

/** The language the bedside hears for this call. The bedside's own until someone picks another. */
@Composable
private fun LanguageChoice(translation: CallTranslation) {
    var open by remember { mutableStateOf(false) }
    val current = translation.language
    TextButton(onClick = { open = true }, enabled = !translation.sending, modifier = Modifier.testTag("call.translation.language")) {
        Text((current?.displayName ?: "${translation.peerName}'s language") + " ▾", color = Color.White, fontSize = 17.sp,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    DropdownMenu(open, onDismissRequest = { open = false }) {
        Text("${translation.peerName} hears", Modifier.padding(horizontal = 16.dp, vertical = 8.dp), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        BedsideLanguage.entries.forEach { option ->
            DropdownMenuItem(text = { Text(option.choiceLabel + if (option == current) "  ✓" else "") },
                onClick = { open = false; translation.choose(option) })
        }
    }
}

/** The last few things said, newest at the bottom: what the translator heard and what it said for the other side. */
@Composable
private fun Transcript(translation: CallTranslation) {
    val lines = translation.lines.takeLast(3)
    if (lines.isEmpty()) return
    Column(Modifier.fillMaxWidth().testTag("call.translation.transcript"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        lines.forEach { line ->
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (line.fromBedside) {
                    // Their words in your language first; what they actually said below.
                    Text("${line.name}: ${line.said ?: line.heard}", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 3)
                    if (line.said != null) Text(line.heard, color = CallColors.secondary, fontSize = 15.sp, maxLines = 3)
                } else {
                    val who = if (translation.isMine(line)) "You" else line.name
                    Text("$who: ${line.heard}", color = CallColors.secondary, fontSize = 15.sp, maxLines = 3)
                    line.said?.let { Text("${translation.peerName} hears: $it", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 3) }
                }
            }
        }
    }
}
