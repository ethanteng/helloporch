package com.ethanteng.helloporch

import android.icu.text.DateFormat
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyMessage
import com.ethanteng.helloporch.core.FamilyText
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonPrimitive

/**
 * Family messages, as iOS's MessageSettingsViewController shows them: whether family can send them, and the ones
 * waiting on the bedside, where a caregiver lets held phone voicemail and texts through or removes them. Playing
 * messages when someone is in front of the tablet comes with presence (android/PLAN.md, phase 5).
 */
@Composable
fun MessagesPages(admin: CaregiverAdmin, links: FamilyLinks, onBack: (() -> Unit)?) {
    var reviewing by rememberSaveable { mutableStateOf(false) }
    // A family phone reads the household again as the review opens, as it does for each page.
    LaunchedEffect(reviewing) { if (reviewing) admin.refresh() }
    if (reviewing) { WaitingMessagesScreen(admin, links, onDone = { reviewing = false }); return }
    FormScreen(CaregiverPage.MESSAGES.title(admin.onBedside), navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }) {
        val state = admin.state(links)
        val messages = state?.messages.orEmpty()
        val texts = state?.texts.orEmpty()
        val total = messages.size + texts.size
        val held = heldCount(messages, texts)
        CaregiverGroup {
            ToggleRow("Allow family messages", state?.messagesEnabled != false, enabled = state != null && !admin.busy,
                onChange = { admin.perform("setMessages", mapOf("enabled" to JsonPrimitive(it))) })
            HorizontalDivider()
            // Phone voicemail and texts from numbers that aren't on the keypad wait for a caregiver's OK.
            CaregiverRow(onClick = if (total > 0) ({ reviewing = true }) else null,
                label = if (total == 0) "No messages waiting" else if (held > 0) "Waiting messages, $total, ${needsOK(held)} your OK" else "Waiting messages, $total") {
                Column(Modifier.weight(1f)) {
                    Text("Waiting messages", style = MaterialTheme.typography.titleMedium)
                    if (held > 0) Text("${needsOK(held)} your OK", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary)
                }
                Text(if (total == 0) "None" else "$total", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (total > 0) Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** What the Messages row in caregiver mode's list says, as iOS's does: how many need an OK, or are waiting, or that
 * messages are off. */
fun messagesSummary(messages: List<FamilyMessage>, texts: List<FamilyText>, enabled: Boolean?): String? {
    val held = heldCount(messages, texts)
    val waiting = messages.size + texts.size
    return when {
        held > 0 -> "${needsOK(held)} OK"
        waiting > 0 -> "$waiting waiting"
        enabled == false -> "Off"
        else -> null
    }
}

private fun heldCount(messages: List<FamilyMessage>, texts: List<FamilyText>) = messages.count { it.held == true } + texts.count { it.held }

private fun needsOK(held: Int) = if (held == 1) "1 needs" else "$held need"

/**
 * Each message and text waiting on the bedside, as iOS's MessageQueueViewController lists them: held texts first, then
 * messages with held phone voicemail first, then the other texts. A text's words come from `caregiverTexts`, which only
 * the PIN-checked review can read, and a held one can be let through only once they're shown.
 */
@Composable
private fun WaitingMessagesScreen(admin: CaregiverAdmin, links: FamilyLinks, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    val state = admin.state(links)
    val messages = state?.messages.orEmpty()
    val texts = state?.texts.orEmpty()
    val bedside = bedsideDevice(admin.snapshot(links))
    // Each waiting text's words, by ID, and the texts caregiverTexts has answered for: one it answered for but left out
    // has none to show.
    var words by remember { mutableStateOf<Map<String, FamilyText>>(emptyMap()) }
    var answered by remember { mutableStateOf<Set<String>>(emptySet()) }
    var wordsFailed by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<Any?>(null) }
    var preview by remember { mutableStateOf<Preview?>(null) }
    var opening by remember { mutableStateOf(false) }
    // The list follows the household as it changes, so a text that arrives while it's open is read for too.
    val textIDs = texts.map { it.id }.toSet()
    LaunchedEffect(textIDs) {
        if (textIDs.all { it in answered }) return@LaunchedEffect
        try {
            val loaded = admin.request("caregiverTexts").texts.orEmpty()
            words = words + loaded.associateBy { it.id }
            answered = answered + textIDs + loaded.map { it.id }
            wordsFailed = false
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            wordsFailed = true
        }
    }
    fun listen(message: FamilyMessage) {
        if (opening) return
        opening = true
        admin.launch {
            try {
                request("caregiverMessageMedia", mapOf("messageID" to JsonPrimitive(message.id))).media?.let { preview = Preview(it.url, messageTitle(message), message.mode == "video") }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Couldn't play this message. Try again."
            } finally {
                opening = false
            }
        }
    }
    FormScreen("Waiting messages", navigation = { TextButton(onClick = onDone) { Text("Back") } }) {
        if (messages.isEmpty() && texts.isEmpty()) Text("No messages are waiting.", style = MaterialTheme.typography.bodyLarge)
        // Held texts first, then held phone voicemail: they're what needs a decision.
        for (text in texts.filter { it.held }.sortedBy { it.sentAt }) {
            TextSection(admin, text, bedside, words[text.id], text.id in answered, wordsFailed, onRemove = { removing = text })
        }
        for (message in messages.sortedWith(compareBy({ if (it.held == true) 0 else 1 }, { it.sentAt }))) {
            CaregiverGroup(messageTitle(message), messageDetail(message, bedside)) {
                ActionRow(if (message.held == true) "Listen first" else "Preview") { listen(message) }
                if (message.held == true) {
                    HorizontalDivider()
                    ActionRow("Let it play on Porch", enabled = !admin.busy) {
                        admin.perform("releaseMessage", mapOf("messageID" to JsonPrimitive(message.id)))
                    }
                }
                HorizontalDivider()
                RemoveRow(enabled = !admin.busy) { removing = message }
            }
        }
        for (text in texts.filter { !it.held }.sortedBy { it.sentAt }) {
            TextSection(admin, text, bedside, words[text.id], text.id in answered, wordsFailed, onRemove = { removing = text })
        }
    }
    preview?.let { MessagePreview(it) { preview = null } }
    // Caregiver changes go one at a time, and one made while another is saving is dropped, so Remove waits for it.
    when (val item = removing) {
        is FamilyMessage -> ConfirmRemove("Remove this message?",
            if (item.fromPhone) "It won't play on the bedside Porch, and the recording is deleted."
            else "It won't play on the bedside Porch. ${item.fromName} will see that a caregiver removed it.",
            enabled = !admin.busy, onDismiss = { removing = null }) { removing = null; admin.perform("removeMessage", mapOf("messageID" to JsonPrimitive(item.id))) }
        is FamilyText -> ConfirmRemove("Remove this text?", "It won't show on the bedside Porch, and its words are deleted.",
            enabled = !admin.busy, onDismiss = { removing = null }) { removing = null; admin.perform("removeText", mapOf("textID" to JsonPrimitive(item.id))) }
    }
}

/** A text with its words, and what the bedside shows when it translated them. `answered` once caregiverTexts has
 * answered for it, with its words or without. */
@Composable
private fun TextSection(admin: CaregiverAdmin, text: FamilyText, bedside: String, loaded: FamilyText?, answered: Boolean, failed: Boolean,
    onRemove: () -> Unit) {
    val state = if (text.held) "Waiting for your OK: number isn't saved on the keypad" else if (text.delivered) "Ready on the $bedside" else "Not on the $bedside yet"
    CaregiverGroup("Text from ${senderName(text.from)}", "Sent ${whenSent(text.sentAt)} · $state") {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when {
                loaded != null -> {
                    loaded.body?.takeIf { it.isNotEmpty() }?.let { Text("“$it”", style = MaterialTheme.typography.bodyLarge) }
                    loaded.translation?.let { translation ->
                        val language = loaded.sourceLanguage?.let { Locale.forLanguageTag(it).getDisplayLanguage(Locale.ENGLISH) }?.takeIf { it.isNotEmpty() }
                        Text(language?.let { "Shown on Porch, translated from $it: $translation" } ?: "Shown on Porch as: $translation",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                answered -> Text("The words for this text aren't available.", style = MaterialTheme.typography.bodyMedium)
                failed -> Text("Couldn't load this text. Go back and try again.", style = MaterialTheme.typography.bodyMedium)
                else -> Text("Loading the text…", style = MaterialTheme.typography.bodyMedium)
            }
            val pictures = text.pictures ?: 0
            if (pictures > 0) Text(if (pictures == 1) "It came with a picture, which Porch doesn't show yet." else "It came with $pictures pictures, which Porch doesn't show yet.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val others = text.attachments ?: 0
            if (others > 0) Text(if (others == 1) "It came with an attachment, such as a contact card or voice clip, which Porch doesn't show yet."
                else "It came with $others attachments, such as contact cards or voice clips, which Porch doesn't show yet.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        // Not until the words are here: otherwise Let it show approves a text the caregiver hasn't read.
        if (text.held && loaded != null) {
            HorizontalDivider()
            ActionRow("Let it show on Porch", enabled = !admin.busy) { admin.perform("releaseText", mapOf("textID" to JsonPrimitive(text.id))) }
        }
        HorizontalDivider()
        RemoveRow(enabled = !admin.busy, onClick = onRemove)
    }
}

@Composable
private fun RemoveRow(enabled: Boolean, onClick: () -> Unit) {
    CaregiverRow(onClick = if (enabled) onClick else null) {
        Text("Remove", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium,
            color = if (enabled) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ConfirmRemove(title: String, detail: String, enabled: Boolean, onDismiss: () -> Unit, onRemove: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(detail) },
        confirmButton = {
            TextButton(onClick = onRemove, enabled = enabled) {
                Text("Remove", color = if (enabled) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}

private class Preview(val url: String, val title: String, val video: Boolean)

/**
 * A waiting message, played here for the caregiver from the server's short-lived link, as iOS plays it in its own
 * player. Closing it, or leaving the app, stops it.
 */
@OptIn(UnstableApi::class)
@Composable
private fun MessagePreview(preview: Preview, onClose: () -> Unit) {
    val context = LocalContext.current
    val activity = LocalActivity.current
    var ended by remember(preview) { mutableStateOf(false) }
    var failed by remember(preview) { mutableStateOf(false) }
    val player = remember(preview) {
        ExoPlayer.Builder(context).build().apply {
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) { ended = playbackState == Player.STATE_ENDED }
                override fun onPlayerError(error: PlaybackException) { failed = true }
            })
            setMediaItem(MediaItem.fromUri(preview.url))
            prepare()
            play()
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    // Leaving the app closes it. Pausing instead left the dialog saying "Playing…" with no sound when Porch came back.
    // Turning the tablet recreates the activity, which is still this screen, so that isn't leaving.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        if (activity?.isChangingConfigurations != true) onClose() else player.pause()
    }
    AlertDialog(onDismissRequest = onClose,
        title = { Text(preview.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (preview.video && !failed) ContentFrame(player, Modifier.fillMaxWidth().aspectRatio(4f / 3f))
                Text(when {
                    failed -> "Couldn't play this message. Try again."
                    ended -> "That's the whole message."
                    else -> "Playing…"
                }, style = MaterialTheme.typography.bodyLarge)
            }
        },
        dismissButton = if (ended && !failed) ({ TextButton(onClick = { player.seekTo(0); player.play() }) { Text("Play again") } }) else null,
        confirmButton = { TextButton(onClick = onClose) { Text("Done") } })
}

private fun messageTitle(message: FamilyMessage): String {
    val type = when {
        message.fromPhone -> "Phone voicemail"
        message.kind == "voicemail" -> "Voicemail"
        message.mode == "video" -> "Video message"
        else -> "Audio message"
    }
    val from = if (!message.fromPhone) message.fromName else message.callerNumber?.let(::displayNumber) ?: "an unknown caller"
    return "$type from $from"
}

private fun messageDetail(message: FamilyMessage, bedside: String): String {
    val state = when {
        message.held != true -> if (message.delivered) "Downloaded to the $bedside" else "Not downloaded yet"
        message.callerNumber == null -> "Waiting for your OK: hidden number"
        message.callerVerified == true -> "Waiting for your OK: number isn't on the keypad"
        else -> "Waiting for your OK: number couldn't be checked"
    }
    val seconds = message.durationSeconds
    return "%d:%02d · Sent %s · %s".format(Locale.US, seconds / 60, seconds % 60, whenSent(message.sentAt), state)
}

private fun senderName(from: String) = if (from.startsWith("+")) displayNumber(from) else from

/** "Today, 4:02 PM", "Yesterday, 6:04 PM" or "Nov 3, 2026, 9:15 AM", as iOS's relative dates read. */
private fun whenSent(sentAt: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.RELATIVE_MEDIUM, DateFormat.SHORT).format(Date(sentAt * 1_000))
