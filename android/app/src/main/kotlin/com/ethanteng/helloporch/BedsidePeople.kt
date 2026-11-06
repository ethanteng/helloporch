package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PorchExperience

/**
 * Who the bedside can call, as iOS's people picker shows the keypad: a card for each person on a key, with the key to
 * press. Pressing the key here calls them too. Until caregiver mode (phase 4) can put people on keys, family members who
 * aren't on one are listed after them, and a tap calls them.
 */
@Composable
fun BedsidePeople(app: PorchApplication, links: FamilyLinks, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val slots = remember(links) { try { CallSlots.load(app.settings, app.photos) } catch (_: Exception) { CallSlots() } }
    val keyed = remember(slots) { CallSlots.digits.mapNotNull { digit -> slots.contact(digit)?.let { digit to it } } }
    val others = remember(links, keyed) {
        links.state?.people.orEmpty().filter { person ->
            person.role == PorchExperience.FAMILY && person.canReceiveCalls != false && keyed.none { it.second.familyMemberID == person.id }
        }
    }
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
    Surface(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.safeDrawingPadding().fillMaxSize().padding(24.dp)) {
            val columns = if (maxWidth >= 600.dp) 2 else 1
            // The list has to have a finite height. A lazy grid measured with an infinite height can't be laid out.
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text("Who would you like to call?"), Modifier.weight(1f), style = MaterialTheme.typography.headlineMedium)
                    TextButton(onClick = onClose) { Text(text("Back to clock"), fontSize = 20.sp) }
                }
                if (keyed.isEmpty() && others.isEmpty()) Text(text("No one is on the keypad yet. A caregiver can add people in caregiver mode."),
                    style = MaterialTheme.typography.titleLarge)
                LazyVerticalGrid(GridCells.Fixed(columns), Modifier.weight(1f).fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    items(keyed, key = { "key-${it.first}" }) { (digit, contact) ->
                        PersonCard(contact.name, contact.photoData, text("Press %@", CallSlots.symbol(digit))) { place { app.calls.bedsideKey(digit) } }
                    }
                    items(others, key = { "member-${it.id}" }) { person ->
                        val photo = remember(person.photoID) { person.photoID?.let { app.photos.familyMembers.data(it) } }
                        PersonCard(person.name, photo, text("Tap to call")) { place { app.calls.callFromBedside(person) } }
                    }
                }
            }
        }
    }
}

@Composable
private fun PersonCard(name: String, photo: ByteArray?, detail: String, onClick: () -> Unit) {
    ElevatedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Photo(photo, Modifier.size(96.dp))
            Column {
                Text(name, fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
                Text(detail, fontSize = 20.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
