package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withClip
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallGroup
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.ValidationException
import java.io.ByteArrayOutputStream
import java.util.UUID
import kotlinx.coroutines.launch

/** A group key as it's being set: who it rings, the name the caregiver typed, its color, how calls start, and whether
 * its photo was taken away. Kept across a rotation. A photo just chosen is kept apart (AddSomeonePhoto): it can be
 * close to 1 MB, more than a screen may keep when it turns. */
private data class GroupDraft(val memberIDs: List<String>, val name: String, val colorHex: String?, val video: Boolean,
    val photoRemoved: Boolean = false) : java.io.Serializable

private enum class GroupStep { WHO, CHECK }

/**
 * A key that rings two family members on Porch at once, as the iPad sets one up: who's in the group, then a check of
 * the key as the bedside will show it, with its photo, color, name and how calls start. Saving puts the group on the key,
 * in place of what was there, and goes back to People. Opened from a group key (`editing`), it starts at that check,
 * which can also change the people and take the group off the key. Back goes back one screen.
 */
@Composable
internal fun GroupKey(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, key: Int, editing: Boolean, onBack: () -> Unit,
    onDone: () -> Unit) {
    val existing = admin.slots.group(key)?.takeIf { editing }
    // Taken off the key meanwhile, such as by forgetting the keypad: the page closes.
    val gone = editing && existing == null
    LaunchedEffect(gone) { if (gone) onDone() }
    if (gone) return
    var draft by rememberSaveable(key) {
        mutableStateOf(GroupDraft(existing?.memberIDs.orEmpty(), existing?.customName.orEmpty(), existing?.buttonColorHex,
            video = existing?.mode != NativeCall.Mode.VOICE))
    }
    var steps by rememberSaveable(key) { mutableStateOf(listOf(if (editing) GroupStep.CHECK else GroupStep.WHO)) }
    var removing by remember { mutableStateOf(false) }
    val flow = rememberSaveable { UUID.randomUUID().toString() }
    val photo = viewModel<AddSomeonePhoto>(key = "group-key-$flow")
    // Kept through a rotation, and let go once the group's screens close.
    val activity = LocalActivity.current
    DisposableEffect(photo) { onDispose { if (activity?.isChangingConfigurations != true) photo.data = null } }
    fun back() { if (steps.size == 1) onBack() else steps = steps.dropLast(1) }
    BackHandler(onBack = ::back)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val prepared = FamilyPhotos.prepared(context, uri)
            if (prepared == null) admin.error = "That photo couldn't be opened. Please choose another photo."
            else { photo.data = prepared; draft = draft.copy(photoRemoved = false) }
        }
    }

    val people = admin.state(links)?.people.orEmpty()
    val symbol = CallSlots.symbol(key)
    /** The chosen people's names: as Porch shows them now, or as the key last showed someone who has since left. */
    fun names(ids: List<String>): List<String> = ids.map { id ->
        people.firstOrNull { it.id == id }?.name ?: existing?.let { it.memberNames.getOrNull(it.memberIDs.indexOf(id)) }.orEmpty()
    }
    fun save() {
        val saved = draft
        val group = try {
            val names = names(saved.memberIDs)
            val mode = if (saved.video) NativeCall.Mode.VIDEO else NativeCall.Mode.VOICE
            val made = existing?.updating(name = saved.name, memberIDs = saved.memberIDs, memberNames = names, mode = mode, buttonColorHex = saved.colorHex)
                ?: CallGroup(saved.name, saved.memberIDs, names, mode, saved.colorHex)
            val chosen = photo.data
            if (chosen != null) made.updatingPhoto(chosen) else if (saved.photoRemoved) made.updatingPhoto(null) else made
        } catch (e: ValidationException) {
            admin.error = e.message
            return
        }
        if (admin.saveSlots { it.setGroup(group, key) }) onDone()
    }

    when (steps.last()) {
        GroupStep.WHO -> GroupPeople(app, admin, people, draft.memberIDs, "Key $symbol", if (editing) "Done" else "Next", onBack = ::back) { ids ->
            draft = draft.copy(memberIDs = ids)
            if (editing) back() else steps = steps + GroupStep.CHECK
        }
        GroupStep.CHECK -> {
            val saved = remember(existing) { existing?.photoData }
            /** The key's own photo, as it would be saved. */
            val keyPhoto = photo.data ?: saved.takeIf { !draft.photoRemoved }
            val names = names(draft.memberIDs)
            val peopleNames = CallGroup.joined(names)
            val shownName = draft.name.trim().ifEmpty { peopleNames }
            // Without a photo of its own, the key shows its people's.
            val peoplePhoto = remember(draft.memberIDs, names, people, FamilyPhotos.saved) { GroupAppearance.photo(app, draft.memberIDs, names, people) }
            FormScreen("Key $symbol", navigation = { BackButton(::back) }) {
                Heading(if (editing) "Key $symbol" else "Check key $symbol")
                Text("On ${lovedOne(admin, links)}'s screen", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                KeyPreview(shownName, keyPhoto ?: peoplePhoto, symbol, buttonColor(draft.colorHex))
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(8.dp),
                    itemVerticalAlignment = Alignment.CenterVertically) {
                    PhotoButton(keyPhoto != null, if (keyPhoto != null) "Remove photo" else null, enabled = !admin.busy, onChoose = {
                        try { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                        catch (_: ActivityNotFoundException) { admin.error = "No app on this device can choose a photo." }
                    }, onRemove = { photo.data = null; draft = draft.copy(photoRemoved = true) })
                    // A color chosen on an iPad's older picker stays, chosen, until one of these replaces it.
                    val custom = draft.colorHex?.takeIf { chosen -> swatches.none { it.first == chosen } }
                    Row(Modifier.selectableGroup()) {
                        swatches.forEach { (hex, label) -> Swatch(hex, label, selected = draft.colorHex == hex, enabled = true) { draft = draft.copy(colorHex = hex) } }
                        custom?.let { Swatch(it, "Color #$it", selected = true, enabled = true) {} }
                    }
                }
                CaregiverGroup {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Name", style = MaterialTheme.typography.titleMedium)
                        PorchTextField(draft.name, { typed -> draft = draft.copy(name = typed) }, "Name", Modifier.semantics { contentDescription = "Name" },
                            placeholder = { Text(peopleNames, maxLines = 1) }, keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
                    }
                    if (editing) {
                        HorizontalDivider()
                        DetailRow(R.drawable.ic_account, "People", peopleNames) { steps = steps + GroupStep.WHO }
                    }
                    HorizontalDivider()
                    CaregiverRow {
                        Text("Call", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                        Choices(listOf("Video", "Voice"), if (draft.video) 0 else 1) { choice -> draft = draft.copy(video = choice == 0) }
                    }
                }
                FormButton(if (editing) "Save" else "Add to key $symbol", enabled = !admin.busy, onClick = ::save)
                if (editing) FormPlainButton("Remove", onClick = { removing = true }, enabled = !admin.busy, color = MaterialTheme.colorScheme.error)
            }
            // As a person's key asks before it's emptied.
            if (removing) AlertDialog(onDismissRequest = { removing = false },
                title = { Text("Take $shownName off the keypad?") },
                text = { Text("Key $symbol will be empty.") },
                confirmButton = {
                    TextButton(onClick = { removing = false; if (admin.saveSlots { it.setGroup(null, key) }) onDone() },
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Remove") }
                },
                dismissButton = { TextButton(onClick = { removing = false }) { Text("Cancel") } })
        }
    }
}

/** Who's in the group: two of the family on Porch, ticked in the order they're called. With fewer than two on Porch,
 * there's no group to make yet. */
@Composable
private fun GroupPeople(app: PorchApplication, admin: CaregiverAdmin, people: List<FamilyPerson>, chosen: List<String>, title: String, button: String,
    onBack: () -> Unit, onChosen: (List<String>) -> Unit) {
    var picked by rememberSaveable { mutableStateOf(chosen) }
    // Someone who has left Porch isn't listed, and no longer counts.
    val listed = picked.filter { id -> people.any { it.id == id } }
    FormScreen(title, navigation = { BackButton(onBack) }) {
        Heading("Who's in the group?")
        if (people.size < CallGroup.maximumPeople) {
            Text("Group calls need two people on Porch.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            Text("Choose two.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            CaregiverGroup("On Porch") {
                people.forEachIndexed { index, person ->
                    if (index > 0) HorizontalDivider()
                    val checked = person.id in listed
                    val enabled = checked || listed.size < CallGroup.maximumPeople
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp)
                        .toggleable(checked, enabled = enabled, role = Role.Checkbox) { on -> picked = if (on) listed + person.id else listed - person.id }
                        .alpha(if (enabled) 1f else 0.5f).padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Avatar(person.name, memberPhoto(app, admin, person), 44.dp)
                        Text(person.name, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                        Checkbox(checked, onCheckedChange = null, enabled = enabled)
                    }
                }
            }
            FormButton(button, enabled = listed.size == CallGroup.maximumPeople, onClick = { onChosen(listed) })
        }
    }
}

/** Group keys show their people's photos, which the bedside keeps for everyone in the family, as the iPad shows them. */
internal object GroupAppearance {
    /**
     * A group key without a photo of its own shows its people's photos side by side, each filling half, and the initial
     * of anyone without one. Null when neither has a photo, so the key reads like a person without one. `people` is the
     * family on Porch: someone who has left it has no photo.
     */
    fun photo(app: PorchApplication, memberIDs: List<String>, memberNames: List<String>, people: List<FamilyPerson>?): ByteArray? {
        val photos = memberIDs.map { id ->
            people?.firstOrNull { it.id == id }?.photoID?.let { FamilyPhotos.data(app, it) }
                ?.let { data -> runCatching { BitmapFactory.decodeByteArray(data, 0, data.size) }.getOrNull() }
        }
        if (photos.all { it == null }) return null
        val side = 480f
        val image = createBitmap(side.toInt(), side.toInt())
        val canvas = Canvas(image)
        val width = side / photos.size
        val drawing = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val letters = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            textSize = side * 0.3f
            typeface = Typeface.create(Typeface.DEFAULT, 600, false)
            textAlign = Paint.Align.CENTER
        }
        photos.forEachIndexed { index, photo ->
            val frame = RectF(index * width, 0f, (index + 1) * width, side)
            canvas.withClip(frame) {
                if (photo != null) {
                    // Fills its half, cropped from the middle.
                    val scale = maxOf(frame.width() / photo.width, frame.height() / photo.height)
                    val (w, h) = photo.width * scale to photo.height * scale
                    drawBitmap(photo, null, RectF(frame.centerX() - w / 2, frame.centerY() - h / 2, frame.centerX() + w / 2, frame.centerY() + h / 2), drawing)
                } else {
                    drawColor(PorchColors.nightSurface.toArgb())
                    val initial = memberNames.getOrNull(index)?.firstOrNull()?.uppercase().orEmpty()
                    drawText(initial, frame.centerX(), frame.centerY() - (letters.descent() + letters.ascent()) / 2, letters)
                }
            }
        }
        // A thin line between the two halves.
        val line = Paint().apply { color = android.graphics.Color.argb(217, 255, 255, 255) }
        for (index in 1 until photos.size) canvas.drawRect(index * width - 2, 0f, index * width + 2, side, line)
        return ByteArrayOutputStream().use { out -> image.compress(Bitmap.CompressFormat.JPEG, 85, out); out.toByteArray() }
    }

    fun photo(app: PorchApplication, group: CallGroup, people: List<FamilyPerson>?): ByteArray? =
        group.photoData ?: photo(app, group.memberIDs, group.memberNames, people)

    /** A group key as the bedside shows and calls it: its name, color, and its photo or its people's. */
    fun contact(app: PorchApplication, group: CallGroup, people: List<FamilyPerson>?): CallContact {
        if (group.photoID != null) return group.callContact
        val photo = photo(app, group.memberIDs, group.memberNames, people) ?: return group.callContact
        return group.callContact.updatingPhoto(photo)
    }
}
