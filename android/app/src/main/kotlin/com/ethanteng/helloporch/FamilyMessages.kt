package com.ethanteng.helloporch

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.icu.text.DateFormat
import android.media.MediaMetadataRetriever
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyMessageThread
import com.ethanteng.helloporch.core.MessageStatus
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.ThreadEntry
import java.io.File
import java.util.Calendar
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive

/**
 * Preview frames for video messages, as iOS's MessagePosters keeps them: saved when a video is sent from this phone, or
 * made once from the stored video, half a second in, and kept by message ID in the cache.
 */
object MessagePosters {
    private fun folder(context: Context) = File(context.cacheDir, "PorchMessagePosters")
    private fun file(context: Context, id: String) = File(folder(context), "$id.jpg")

    fun cached(context: Context, id: String): Bitmap? = file(context, id).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }

    fun save(context: Context, image: Bitmap, id: String) {
        runCatching {
            folder(context).mkdirs()
            val temporary = File(folder(context), "$id.tmp")
            temporary.outputStream().use { image.compress(Bitmap.CompressFormat.JPEG, 80, it) }
            temporary.renameTo(file(context, id))
        }
    }

    /** A frame half a second into a video: a recording's file, or a short-lived link to a stored one, which is read
     * only as far as that frame. */
    suspend fun frame(source: String): Bitmap? = withContext(Dispatchers.IO) {
        val retriever = MediaMetadataRetriever()
        try {
            if (source.startsWith("http")) retriever.setDataSource(source, emptyMap()) else retriever.setDataSource(source)
            retriever.getScaledFrameAtTime(500_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 720, 720)
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }
}

/** When messages were sent and played, as iOS's MessageText says it. */
internal object MessageText {
    /** "4:02 PM", for a message under its day's heading. */
    fun time(seconds: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(seconds * 1_000))

    /** "Today, 4:02 PM", or "Nov 3, 2026, 9:15 AM", for what a screen reader says. */
    fun `when`(seconds: Long): String = DateFormat.getDateTimeInstance(DateFormat.RELATIVE_MEDIUM, DateFormat.SHORT).format(Date(seconds * 1_000))

    /** "today at 4:02 PM", "yesterday at 6:04 PM" or "Oct 25 at 6:04 PM", short enough for a tag. */
    fun played(seconds: Long?): String {
        if (seconds == null) return ""
        val day = when (daysAgo(seconds)) {
            0 -> "today"
            1 -> "yesterday"
            else -> DateFormat.getInstanceForSkeleton(if (sameYear(seconds)) "MMMd" else "MMMdy").format(Date(seconds * 1_000))
        }
        return "$day at ${time(seconds)}"
    }

    /** "Today", "Yesterday", or the weekday and date, over that day's messages. */
    fun day(seconds: Long): String = when (daysAgo(seconds)) {
        0 -> "Today"
        1 -> "Yesterday"
        else -> DateFormat.getInstanceForSkeleton(if (sameYear(seconds)) "EEEEMMMMd" else "EEEEMMMMdy").format(Date(seconds * 1_000))
    }

    private fun daysAgo(seconds: Long): Int {
        fun start(calendar: Calendar) = calendar.apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        val then = start(Calendar.getInstance().apply { timeInMillis = seconds * 1_000 })
        val today = start(Calendar.getInstance())
        return ((today.timeInMillis - then.timeInMillis) / 86_400_000L).toInt()
    }

    private fun sameYear(seconds: Long) =
        Calendar.getInstance().apply { timeInMillis = seconds * 1_000 }.get(Calendar.YEAR) == Calendar.getInstance().get(Calendar.YEAR)
}

/**
 * Messages between this phone and the bedside in one thread, as iOS's MessageThreadViewController shows them: oldest
 * first like a text conversation, theirs on the left and this phone's on the right, each tagged with whether it was
 * played, under each day's heading. Others' messages to the bedside aren't shown. Playing one of theirs marks it
 * played; each plays again while its recording is kept (90 days). It loads again when the bedside leaves a new one.
 */
@Composable
fun MessageThreadScreen(app: PorchApplication, family: FamilyCredential, links: FamilyLinks, onBack: () -> Unit, onRecord: (String) -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state = links.state(family)
    var entries by remember { mutableStateOf<List<ThreadEntry>?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loadedName by remember { mutableStateOf<String?>(null) }
    var playing by remember { mutableStateOf<MessageMedia?>(null) }
    var opening by remember { mutableStateOf(false) }
    var unsending by remember { mutableStateOf<String?>(null) }
    var loads by remember { mutableIntStateOf(0) }
    /** Refresh was tapped, so a failed load is reported rather than left for the next one. */
    var reportFailure by remember { mutableStateOf(false) }
    val list = rememberLazyListState()
    var placed by remember { mutableStateOf(false) }
    val posters = remember { mutableStateMapOf<String, Bitmap>() }
    val name = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }?.name ?: loadedName ?: state?.householdName ?: "your loved one"
    // Again whenever the bedside leaves a new message, or one is played, unsent or refreshed.
    LaunchedEffect(state?.newMessages, loads) {
        try {
            val response = app.service(family).send("listMessages")
            val received = response.received.orEmpty()
            received.firstOrNull()?.fromName?.let { loadedName = it }
            entries = FamilyMessageThread.entries(response.messages.orEmpty(), received)
            loadError = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Messages already on screen stay; only a refresh someone asked for says it failed.
            val reason = e.message ?: "Couldn't load messages. Check the connection and try again."
            if (entries == null) loadError = reason else if (reportFailure) error = reason
        }
        reportFailure = false
    }
    // Missing preview frames, one at a time; each is kept, so this happens once per video.
    LaunchedEffect(entries) {
        for (entry in entries.orEmpty()) {
            if (!entry.video || !entry.playable || posters.containsKey(entry.id)) continue
            val cached = withContext(Dispatchers.IO) { MessagePosters.cached(context, entry.id) }
            if (cached != null) { posters[entry.id] = cached; continue }
            try {
                val url = app.service(family).send(entry.mediaAction, mapOf("messageID" to JsonPrimitive(entry.id))).media?.url ?: continue
                val image = MessagePosters.frame(url) ?: continue
                withContext(Dispatchers.IO) { MessagePosters.save(context, image, entry.id) }
                posters[entry.id] = image
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
        }
    }
    fun play(entry: ThreadEntry) {
        if (opening || !entry.playable) return
        opening = true
        scope.launch {
            try {
                val service = app.service(family)
                val url = service.send(entry.mediaAction, mapOf("messageID" to JsonPrimitive(entry.id))).media?.url ?: return@launch
                playing = MessageMedia(url, FamilyMessageThread.type(entry), entry.video)
                if (entry.isNew) {
                    runCatching { service.send("receivedMessagePlayed", mapOf("messageID" to JsonPrimitive(entry.id))) }
                    loads++
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Couldn't play this message. Try again."
            } finally {
                opening = false
            }
        }
    }
    // Each day's heading, then its messages, oldest first.
    val rows = remember(entries) {
        buildList {
            var lastDay: String? = null
            for (entry in entries.orEmpty()) {
                val day = MessageText.day(entry.time)
                if (day != lastDay) { lastDay = day; add(day) }
                add(entry)
            }
        }
    }
    // Opening goes to the first of theirs that hasn't been played, or else to the newest; a new one arriving goes to it.
    val newest = entries?.lastOrNull()?.id
    LaunchedEffect(newest) {
        if (rows.isEmpty()) return@LaunchedEffect
        val firstNew = rows.indexOfFirst { it is ThreadEntry && it.isNew }
        list.scrollToItem(if (!placed && firstNew >= 0) firstNew else rows.lastIndex)
        placed = true
    }
    FormScreen("Messages with $name", navigation = { TextButton(onClick = onBack) { Text("Back") } },
        actions = { TextButton(onClick = { reportFailure = true; loads++ }) { Text("Refresh") } }, scrolls = false) {
        LazyColumn(Modifier.fillMaxSize(), state = list, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            when {
                entries == null -> item { Text(loadError ?: "Loading…", style = MaterialTheme.typography.bodyLarge) }
                rows.isEmpty() -> item { Text("No messages yet.", Modifier.fillMaxWidth(), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center) }
                else -> items(rows, key = { if (it is ThreadEntry) it.id else "day:$it" }) { row ->
                    if (row is ThreadEntry) ThreadRow(row, name, posters[row.id], onPlay = { play(row) }, onUnsend = { unsending = row.id })
                    else Text(row as String, Modifier.fillMaxWidth().padding(top = 12.dp).semantics { heading() }, style = MaterialTheme.typography.titleSmall,
                        textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    if (state?.messagesEnabled != false) FormButton("Record a message for $name", onClick = { onRecord(name) })
                    Text("Your messages wait on $name's Porch until they're played. When you miss a Porch call from $name, they can leave you a message here.",
                        Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
    playing?.let { MessagePlayerDialog(it) { playing = null } }
    unsending?.let { id ->
        AlertDialog(onDismissRequest = { unsending = null }, title = { Text("Unsend this message?") },
            text = { Text("It will be removed from $name's Porch before it plays.") },
            confirmButton = {
                TextButton(onClick = {
                    unsending = null
                    scope.launch {
                        try { app.service(family).send("unsendMessage", mapOf("messageID" to JsonPrimitive(id))) }
                        catch (e: CancellationException) { throw e }
                        catch (e: Exception) { error = e.message ?: "Couldn't unsend it. Try again." }
                        loads++
                    }
                }) { Text("Unsend", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { unsending = null }) { Text("Cancel") } })
    }
    PorchErrorDialog(error) { error = null }
}

/** Who and when over the message, then whether it was played. Theirs keep to the left, this phone's to the right. */
@Composable
private fun ThreadRow(entry: ThreadEntry, name: String, poster: Bitmap?, onPlay: () -> Unit, onUnsend: () -> Unit) {
    val mine = entry is ThreadEntry.Sent
    val type = FamilyMessageThread.type(entry)
    val length = FamilyMessageThread.length(entry.durationSeconds)
    val status = when (entry) {
        is ThreadEntry.Sent -> FamilyMessageThread.status(entry.message, name, MessageText::played)
        is ThreadEntry.Received -> FamilyMessageThread.status(entry.message, MessageText::played)
    }
    val caption = when (entry) {
        is ThreadEntry.Sent -> "You · ${MessageText.time(entry.time)}"
        is ThreadEntry.Received -> "${entry.message.fromName} · ${MessageText.time(entry.time)}"
    }
    val spoken = when (entry) {
        is ThreadEntry.Sent -> "Your ${type.lowercase()}, $length, sent ${MessageText.`when`(entry.time)}"
        is ThreadEntry.Received -> "$type from ${entry.message.fromName}, $length, left ${MessageText.`when`(entry.time)}"
    }
    val alignment = if (mine) Alignment.End else Alignment.Start
    Box(Modifier.fillMaxWidth(), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
        Column(Modifier.fillMaxWidth(0.84f).widthIn(max = 520.dp), horizontalAlignment = alignment, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(caption, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val accent = MaterialTheme.colorScheme.primary
            val ink = if (mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
            Surface(shape = RoundedCornerShape(22.dp), color = if (mine) accent else MaterialTheme.colorScheme.surfaceContainerLow,
                border = if (mine) null else BorderStroke(if (entry.isNew) 2.dp else 1.dp, if (entry.isNew) accent else MaterialTheme.colorScheme.outlineVariant),
                modifier = Modifier.fillMaxWidth().clearAndSetSemantics {
                    contentDescription = listOfNotNull(spoken, status.text, status.note).joinToString(". ")
                    if (entry.playable) { role = Role.Button; onClick { onPlay(); true } }
                }.then(if (entry.playable) Modifier.clickable(onClick = onPlay) else Modifier)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (entry.video && (poster != null || entry.playable)) Poster(poster, entry.playable)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        PlayGlyph(ink, entry.playable)
                        Column {
                            Text(type, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = ink)
                            Text(length, style = MaterialTheme.typography.bodyMedium, color = ink.copy(alpha = 0.8f))
                        }
                    }
                }
            }
            StatusTag(status)
            status.note?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (entry is ThreadEntry.Sent && FamilyMessageThread.canUnsend(entry.message)) {
                TextButton(onClick = onUnsend) { Text("Unsend", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

/** A video's preview frame, or a gray space until it's made. */
@Composable
private fun Poster(image: Bitmap?, playable: Boolean) {
    Box(Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center) {
        if (image != null) Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().height(200.dp))
        if (playable) Box(Modifier.size(56.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape), contentAlignment = Alignment.Center) {
            Text("▶", color = Color.White, fontSize = 26.sp)
        }
    }
}

/** A play symbol on a message that can be played, or a dash on one whose recording is gone. */
@Composable
private fun PlayGlyph(color: Color, playable: Boolean) {
    Box(Modifier.size(40.dp).background(color.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
        Text(if (playable) "▶" else "–", color = color, fontSize = 18.sp)
    }
}

/** Whether a message was played, as a colored tag: filled for new, green once played, amber while it waits, gray once
 * it's gone, red if it didn't send. */
@Composable
private fun StatusTag(status: MessageStatus) {
    val accent = MaterialTheme.colorScheme.primary
    val (foreground, background) = when (status.tone) {
        MessageStatus.Tone.NEW -> MaterialTheme.colorScheme.onPrimary to accent
        MessageStatus.Tone.PLAYED -> accent to accent.copy(alpha = 0.12f)
        MessageStatus.Tone.WAITING -> Color(0.52f, 0.32f, 0f) to Color(0.98f, 0.74f, 0.24f, 0.26f)
        MessageStatus.Tone.ENDED -> MaterialTheme.colorScheme.onSurfaceVariant to MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f)
        MessageStatus.Tone.FAILED -> Color(0.68f, 0.13f, 0.1f) to Color(1f, 0.23f, 0.19f, 0.12f)
    }
    Text(status.text, Modifier.background(background, RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 6.dp),
        color = foreground, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
}
