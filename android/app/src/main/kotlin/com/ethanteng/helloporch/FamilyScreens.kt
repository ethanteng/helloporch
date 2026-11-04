package com.ethanteng.helloporch

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyInvitation
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyNames
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.joinFamily
import java.net.URI
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Phase 1's screens: joining a family from an invitation, and the families this phone is in. */
@Composable
fun PorchScreens(app: PorchApplication, link: String?, onLinkHandled: () -> Unit) {
    val links by app.coordinator.links.collectAsStateWithLifecycle()
    var joining by rememberSaveable { mutableStateOf(false) }
    // Joining or removing a family changes the list before any family has checked in.
    var changes by remember { mutableIntStateOf(0) }
    val families = remember(links, changes) { app.device.families }
    val done = { joining = false; changes++; onLinkHandled() }
    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            when {
                link != null && isBedsideSetup(link) -> BedsideSetupLater(onLinkHandled)
                link != null || joining || families.isEmpty() ->
                    JoinFamily(app, link.orEmpty(), adding = families.isNotEmpty(), onJoined = done, onCancel = if (families.isEmpty()) null else done)
                else -> Families(app, links, families, onJoinAnother = { joining = true }, onChanged = { changes++ })
            }
        }
    }
}

private fun isBedsideSetup(link: String) = runCatching { URI(link) }.getOrNull()?.let { it.host == "activate" || it.path == "/setup" } == true

@Composable
private fun BedsideSetupLater(onDone: () -> Unit) {
    Text("Set up a bedside tablet", style = MaterialTheme.typography.headlineMedium)
    Text("This test version of Porch for Android joins families on a phone. Setting up a tablet to stay with your loved one comes in a later version.")
    Button(onClick = onDone) { Text("OK") }
}

@Composable
private fun JoinFamily(app: PorchApplication, initialLink: String, adding: Boolean, onJoined: () -> Unit, onCancel: (() -> Unit)?) {
    var text by rememberSaveable(initialLink) { mutableStateOf(initialLink) }
    var nickname by rememberSaveable { mutableStateOf("") }
    // Saved, so turning the phone doesn't hide why a join failed.
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var naming by rememberSaveable(stateSaver = namingSaver) { mutableStateOf<Naming?>(null) }
    val scope = rememberCoroutineScope()
    Text(if (adding) "Join another family" else "Join a family", style = MaterialTheme.typography.headlineMedium)
    Text("Paste the invitation link a caregiver sent you. It works once, for 24 hours.")
    OutlinedTextField(text, { text = it; error = null }, Modifier.fillMaxWidth(), label = { Text("Invitation link") }, singleLine = true)
    if (adding) OutlinedTextField(nickname, { nickname = it }, Modifier.fillMaxWidth(), label = { Text("What you call this family (optional)") }, singleLine = true)
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    Button(enabled = !busy && text.isNotBlank(), onClick = {
        val invitation = try { FamilyInvitation(text.trim(), BuildConfig.PORCH_SERVER_URL) } catch (e: IllegalArgumentException) { error = e.message; return@Button }
        busy = true; error = null
        scope.launch {
            try {
                val joined = joinFamily(invitation, nickname.ifBlank { null }, app.device, app.coordinator, { app.service(it) }, { app.service(it) })
                val shared = joined.sharedName; val numbered = joined.numberedName
                if (shared != null && numbered != null) naming = Naming(joined.credential.deviceID, shared, numbered) else onJoined()
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Couldn't join. Check the connection and try again." }
            finally { busy = false }
        }
    }) { Text(if (busy) "Joining…" else "Join family") }
    onCancel?.let { TextButton(onClick = it) { Text("Cancel") } }
    naming?.let { NameFamily(app, it, onDone = { naming = null; onJoined() }) }
}

/** A joined family waiting to be named. Saved, so turning the phone keeps the prompt; only its device ID is, since the
 * pairing itself stays in the secret store. */
private data class Naming(val deviceID: String, val sharedName: String, val numberedName: String)
private val namingSaver = listSaver<Naming?, String>(
    save = { it?.let { naming -> listOf(naming.deviceID, naming.sharedName, naming.numberedName) } ?: emptyList() },
    restore = { if (it.size == 3) Naming(it[0], it[1], it[2]) else null })

/** Two sets of parents are often both "Mom". Left unnamed, the new one is numbered, so Porch asks now, while it's clear
 * which one it is. */
@Composable
private fun NameFamily(app: PorchApplication, naming: Naming, onDone: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    AlertDialog(onDismissRequest = onDone,
        title = { Text("Name this family") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("You're in more than one family called ${naming.sharedName}. Until you name this one, it's ${naming.numberedName}.")
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true)
            }
        },
        confirmButton = { TextButton(enabled = name.isNotBlank(), onClick = {
            app.device.families.firstOrNull { it.deviceID == naming.deviceID }?.let { app.device.setNickname(name, it) }
            onDone()
        }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDone) { Text("Keep ${naming.numberedName}") } })
}

@Composable
private fun Families(app: PorchApplication, links: FamilyLinks, families: List<FamilyCredential>, onJoinAnother: () -> Unit, onChanged: () -> Unit) {
    // The family being left, by device ID, while the phone asks to be sure.
    var leaving by rememberSaveable { mutableStateOf<String?>(null) }
    var leaveError by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Text(if (families.size == 1) "Your family" else "Your families", style = MaterialTheme.typography.headlineMedium)
    for (family in families) {
        val link = links.link(family)
        val state = link?.state
        val bedside = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(app.device.familyName(family) ?: state?.householdName ?: "Your family", style = MaterialTheme.typography.titleLarge)
                Text(when {
                    link?.accessRemoved == true -> "This phone was removed from this family. Ask a caregiver for a new invitation."
                    // A failed check-in keeps the last snapshot. Showing that bedside as on would stay true until the
                    // next one that works, which is what a dropped connection looks like.
                    link?.error != null -> link.error!!
                    bedside != null -> "${bedside.name}'s ${if (bedside.platform == "android") "tablet" else "iPad"} ${if (bedside.online) "is on and ready." else "isn't checking in right now."}"
                    else -> "Checking in…"
                })
                if (link?.accessRemoved == true) TextButton(onClick = { app.coordinator.forget(family); onChanged() }) { Text("Remove from this phone") }
                else TextButton(onClick = { leaveError = null; leaving = family.deviceID }) { Text("Leave this family") }
            }
        }
    }
    Text("This test version joins families and checks in with them. Calls, messages and caregiver mode come in later versions.",
        style = MaterialTheme.typography.bodySmall)
    leaveError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    if (families.size < FamilyNames.limit) OutlinedButton(onClick = onJoinAnother) { Text("Join another family") }
    families.firstOrNull { it.deviceID == leaving }?.let { family ->
        val name = app.device.familyName(family) ?: links.state(family)?.householdName ?: "this family"
        // As on iOS (FamilyProfiles.swift): the phone leaves on the server, then forgets the family.
        AlertDialog(onDismissRequest = { leaving = null },
            title = { Text("Leave $name?") },
            text = { Text("This phone stops getting their calls and messages. To join again, you'll need a new invitation.") },
            confirmButton = { TextButton(onClick = {
                leaving = null
                scope.launch {
                    try { app.coordinator.leave(family); onChanged() }
                    catch (e: CancellationException) { throw e }
                    catch (e: Exception) { leaveError = e.message ?: "Couldn't leave. Check the connection and try again." }
                }
            }) { Text("Leave") } },
            dismissButton = { TextButton(onClick = { leaving = null }) { Text("Cancel") } })
    }
}
