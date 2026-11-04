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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyInvitation
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyNames
import com.ethanteng.helloporch.core.JoinedFamily
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
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var naming by remember { mutableStateOf<JoinedFamily?>(null) }
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
                app.device.experience = PorchExperience.FAMILY
                val joined = joinFamily(invitation, nickname.ifBlank { null }, app.device, app.coordinator, { app.service(it) }, { app.service(it) })
                if (joined.numberedName != null) naming = joined else onJoined()
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Couldn't join. Check the connection and try again." }
            finally { busy = false }
        }
    }) { Text(if (busy) "Joining…" else "Join family") }
    onCancel?.let { TextButton(onClick = it) { Text("Cancel") } }
    naming?.let { joined -> NameFamily(app, joined, onDone = { naming = null; onJoined() }) }
}

/** Two sets of parents are often both "Mom". Left unnamed, the new one is numbered, so Porch asks now, while it's clear
 * which one it is. */
@Composable
private fun NameFamily(app: PorchApplication, joined: JoinedFamily, onDone: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    AlertDialog(onDismissRequest = onDone,
        title = { Text("Name this family") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("You're in more than one family called ${joined.sharedName}. Until you name this one, it's ${joined.numberedName}.")
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true)
            }
        },
        confirmButton = { TextButton(enabled = name.isNotBlank(), onClick = { app.device.setNickname(name, joined.credential); onDone() }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDone) { Text("Keep ${joined.numberedName}") } })
}

@Composable
private fun Families(app: PorchApplication, links: FamilyLinks, families: List<FamilyCredential>, onJoinAnother: () -> Unit, onChanged: () -> Unit) {
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
                    bedside != null -> "${bedside.name}'s ${if (bedside.platform == "android") "tablet" else "iPad"} ${if (bedside.online) "is on and ready." else "isn't checking in right now."}"
                    link?.error != null -> link.error!!
                    else -> "Checking in…"
                })
                if (link?.accessRemoved == true) TextButton(onClick = { app.coordinator.forget(family); onChanged() }) { Text("Remove from this phone") }
            }
        }
    }
    Text("This test version joins families and checks in with them. Calls, messages and caregiver mode come in later versions.",
        style = MaterialTheme.typography.bodySmall)
    if (families.size < FamilyNames.limit) OutlinedButton(onClick = onJoinAnother) { Text("Join another family") }
}
