package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyLinks

/**
 * Who the bedside can call, as iOS's people picker shows the keypad: a card for each person on a key, with the key to
 * press. Pressing the key here calls them too. A caregiver puts people on keys in caregiver mode's People page.
 */
@Composable
fun BedsidePeople(app: PorchApplication, links: FamilyLinks, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    // A photo that just downloaded shows at once, not at the next check-in.
    val slots = remember(links, FamilyPhotos.saved) { try { CallSlots.load(app.settings, app.photos) } catch (_: Exception) { CallSlots() } }
    val keyed = remember(slots) { CallSlots.digits.mapNotNull { digit -> slots.contact(digit)?.let { digit to it } } }
    // One choice. A second tap would otherwise start another call and report that caregiver mode isn't set up.
    var chosen by remember { mutableStateOf(false) }
    fun place(call: () -> Unit) {
        if (chosen || app.calls.busy) return
        chosen = true
        onClose()
        call()
    }
    // A key with nobody on it stays here. Closing first would leave the clock, which is where that notice is shown.
    CallKeys(app, onDigit = { digit -> if (slots.contact(digit) != null) place { app.calls.bedsideKey(digit) } },
        onHangUp = { "hang-up ignored on people" })
    fun text(english: String, vararg arguments: Any?) = BedsideText.string(app, english, *arguments)
    // The sizes the iOS people picker uses, which the bedside is built around: large enough to read from the bed.
    LargeType { BoxWithConstraints(Modifier.fillMaxSize().background(CallColors.night).safeDrawingPadding().padding(32.dp)) {
        val tablet = maxWidth >= 600.dp
        val columns = if (tablet) 2 else 1
        val cardWidth = (maxWidth - 16.dp * (columns - 1)) / columns
        val nameSize = (cardWidth.value * 0.18f).coerceIn(54f, 88f).sp
        val keySize = (cardWidth.value * 0.10f).coerceIn(36f, 48f).sp
        // The list has to have a finite height. A lazy grid measured with an infinite height can't be laid out.
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(text("Who would you like to call?"), Modifier.weight(1f), color = CallColors.text,
                    fontSize = if (tablet) 60.sp else 40.sp, fontWeight = FontWeight.SemiBold)
                CallButton(text("Back to clock"), true, onClick = onClose, app = app, translated = true)
            }
            Text(text(if (keyed.isEmpty()) "Your caregiver can add people using the settings icon on the clock screen."
                else "Tap a name or press their number on the keypad."), color = CallColors.text, fontSize = if (tablet) 34.sp else 28.sp)
            LazyVerticalGrid(GridCells.Fixed(columns), Modifier.weight(1f).fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                items(keyed, key = { "key-${it.first}" }) { (digit, contact) ->
                    PersonCard(contact.name, contact.photoData, text("Press %@", CallSlots.symbol(digit)), nameSize, keySize, buttonColor(contact.buttonColorHex)) {
                        place { app.calls.bedsideKey(digit) }
                    }
                }
            }
        }
    } }
}

@Composable
private fun PersonCard(name: String, photo: ByteArray?, detail: String, nameSize: TextUnit, detailSize: TextUnit, color: Color? = null, onClick: () -> Unit) {
    // A key's button color, chosen in caregiver mode, with lettering that reads on it.
    val text = color?.let(::foreground) ?: CallColors.text
    Column(Modifier.fillMaxWidth().heightIn(min = maxOf(200f, nameSize.value * 3.5f).dp).clip(RoundedCornerShape(24.dp))
        .background(color ?: CallColors.control).clickable(onClick = onClick).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
        Photo(photo, Modifier.heightIn(max = 240.dp))
        Text(name, color = text, fontSize = nameSize, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text(detail, color = if (color == null) CallColors.secondary else text.copy(alpha = 0.8f), fontSize = detailSize, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center)
    }
}
