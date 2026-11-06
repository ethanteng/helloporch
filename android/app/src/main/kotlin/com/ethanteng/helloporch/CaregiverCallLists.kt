package com.ethanteng.helloporch

import android.icu.text.DateFormat as IcuDateFormat
import android.icu.text.DisplayContext
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.CallHistoryEntry
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.NativeCall
import java.time.Instant
import java.time.ZoneId
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/**
 * Calls to and from the bedside for the last 90 days, newest first and grouped by day, as iOS's CallHistoryViewController
 * shows them. The server keeps them (`callHistory`); this screen asks for them when it opens and on Refresh.
 */
@Composable
internal fun CallHistoryScreen(app: PorchApplication, admin: CaregiverAdmin, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    val scope = rememberCoroutineScope()
    var calls by remember { mutableStateOf<List<CallHistoryEntry>?>(null) }
    var slots by remember { mutableStateOf<CallSlots?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    fun reload() {
        if (loading) return
        loading = true
        scope.launch {
            try {
                calls = admin.request("callHistory").calls.orEmpty()
                // A check-in can rename a keypad contact while this list stays open, so Refresh reads those names again.
                // A family phone has no keypad, so phone callers show as Porch named them.
                slots = if (!admin.onBedside) null else try { CallSlots.load(app.settings, app.photos) } catch (_: Exception) { null }
                failure = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = "Couldn't load call history. ${e.message.orEmpty()}".trim()
            } finally {
                loading = false
            }
        }
    }
    LaunchedEffect(Unit) { reload() }
    FormScreen("Call history", navigation = { TextButton(onClick = onDone) { Text("Back") } },
        actions = { TextButton(onClick = ::reload, enabled = !loading) { Text(if (loading) "Loading…" else "Refresh") } }) {
        val shown = calls
        val problem = failure
        when {
            problem != null -> {
                Text(problem, style = MaterialTheme.typography.bodyLarge)
                FormButton("Try again", onClick = ::reload, enabled = !loading)
            }
            shown == null -> Text("Loading calls…", style = MaterialTheme.typography.bodyLarge)
            shown.isEmpty() -> Text("No calls yet.", style = MaterialTheme.typography.bodyLarge)
            else -> CallDays(shown, slots)
        }
    }
}

@Composable
private fun CallDays(calls: List<CallHistoryEntry>, slots: CallSlots?) {
    Text("Last 90 days", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    // The bedside names phone numbers saved on its keypad, as it does elsewhere.
    val zone = ZoneId.systemDefault()
    val days = remember(calls) { calls.groupBy { Instant.ofEpochSecond(it.startedAt).atZone(zone).toLocalDate() }.toSortedMap(reverseOrder()) }
    // "Today", "Yesterday", then the full date, capitalized as a heading.
    val dayFormat = remember {
        IcuDateFormat.getDateInstance(IcuDateFormat.RELATIVE_FULL).apply { setContext(DisplayContext.CAPITALIZATION_FOR_STANDALONE) }
    }
    val timeFormat = remember { IcuDateFormat.getTimeInstance(IcuDateFormat.SHORT) }
    for ((day, entries) in days) {
        CaregiverGroup(dayFormat.format(Date.from(day.atStartOfDay(zone).toInstant()))) {
            entries.sortedByDescending { it.startedAt }.forEachIndexed { index, call ->
                if (index > 0) HorizontalDivider()
                CallRow(call, slots, timeFormat.format(Date(call.startedAt * 1000)))
            }
        }
    }
}

@Composable
private fun CallRow(call: CallHistoryEntry, slots: CallSlots?, time: String) {
    val number = call.number?.let(::displayNumber)
    val keypadName = if (call.via == "phone") slots?.contact(call.number)?.name?.ifEmpty { null } else null
    // A caller known only by their number shows it once, formatted.
    val name = keypadName ?: if (call.name == call.number) number ?: call.name else call.name
    val details = listOfNotNull(call.kindText, call.outcomeText, number?.takeIf { it != name }).joinToString(" · ")
    val colors = MaterialTheme.colorScheme
    val video = call.via == "porch" && call.mode == NativeCall.Mode.VIDEO
    val direction = if (call.isIncoming) "↙︎" else "↗︎"
    // Read as one line: who, how it went, and when.
    Column(Modifier.semantics(mergeDescendants = true) { contentDescription = listOf(name, details, time).joinToString(", ") }) {
        CaregiverRow {
            Text(direction + if (video) "▶︎" else "", Modifier.width(36.dp).clearAndSetSemantics {},
                color = if (call.isMissed) colors.error else colors.primary, fontSize = 22.sp)
            Column(Modifier.weight(1f).clearAndSetSemantics {}) {
                Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Medium, color = if (call.isMissed) colors.error else colors.onSurface)
                Text(details, style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
            }
            Text(time, Modifier.clearAndSetSemantics {}, color = colors.onSurfaceVariant)
        }
    }
}

/**
 * Numbers that called while unknown callers were blocked, and numbers a caregiver allowed, as iOS's
 * BlockedCallersViewController shows them. Allowing a number lets it ring; clearing the list leaves the numbers blocked.
 */
@Composable
internal fun BlockedNumbersScreen(admin: CaregiverAdmin, links: FamilyLinks, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    var clearing by remember { mutableStateOf(false) }
    val screening = admin.state(links)?.callScreening
    val format = remember { IcuDateFormat.getDateTimeInstance(IcuDateFormat.RELATIVE_SHORT, IcuDateFormat.SHORT) }
    fun moment(seconds: Long): String = format.format(Date(seconds * 1000))
    FormScreen("Blocked numbers", navigation = { TextButton(onClick = onDone) { Text("Back") } }) {
        if (screening == null) {
            Text("Not available on this Porch's server yet.", style = MaterialTheme.typography.bodyLarge)
        } else {
            CaregiverGroup("Blocked") {
                if (screening.blocked.isEmpty()) CaregiverRow {
                    Text(if (screening.enabled) "No blocked calls." else "Turn on Block unknown callers to block numbers that aren't on the keypad.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                screening.blocked.forEachIndexed { index, caller ->
                    if (index > 0) HorizontalDivider()
                    val number = displayNumber(caller.number)
                    val calls = if (caller.calls == 1) "Called ${moment(caller.lastCallAt)}" else "Called ${caller.calls} times · last ${moment(caller.lastCallAt)}"
                    CaregiverRow {
                        Column(Modifier.weight(1f)) {
                            Text(number, style = MaterialTheme.typography.titleMedium)
                            Text(calls, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = { admin.perform("setCallerAllowed", mapOf("number" to JsonPrimitive(caller.number), "allowed" to JsonPrimitive(true))) },
                            enabled = !admin.busy, modifier = Modifier.semantics { contentDescription = "Allow $number" }) { Text("Allow") }
                    }
                }
                if (screening.blocked.isNotEmpty()) {
                    HorizontalDivider()
                    CaregiverRow(onClick = { clearing = true }) { Text("Clear this list", color = MaterialTheme.colorScheme.error) }
                }
            }
            CaregiverGroup("Allowed") {
                if (screening.allowed.isEmpty()) CaregiverRow { Text("None yet.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                screening.allowed.forEachIndexed { index, caller ->
                    if (index > 0) HorizontalDivider()
                    val number = displayNumber(caller.number)
                    CaregiverRow {
                        Column(Modifier.weight(1f)) {
                            Text(number, style = MaterialTheme.typography.titleMedium)
                            Text("Allowed ${moment(caller.allowedAt)}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = { admin.perform("setCallerAllowed", mapOf("number" to JsonPrimitive(caller.number), "allowed" to JsonPrimitive(false))) },
                            enabled = !admin.busy, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                            modifier = Modifier.semantics { contentDescription = "Remove $number from allowed numbers" }) { Text("Remove") }
                    }
                }
            }
        }
    }
    if (clearing) AlertDialog(onDismissRequest = { clearing = false },
        title = { Text("Clear blocked numbers?") },
        text = { Text("This only clears the list. The numbers stay blocked.") },
        confirmButton = {
            TextButton(onClick = {
                // Another save is still in flight. Closing now would drop the clear and look like it worked.
                if (admin.busy) return@TextButton
                clearing = false
                admin.perform("clearBlockedCallers")
            }, enabled = !admin.busy) { Text("Clear") }
        },
        dismissButton = { TextButton(onClick = { clearing = false }) { Text("Cancel") } })
}
