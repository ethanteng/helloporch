package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ethanteng.helloporch.core.FamilyAdminState
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.RemoteCaregiverSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Caregiver mode on a family phone, as iOS opens it from RemoteCaregiverPINViewController: the household's caregiver PIN,
 * which the server checks, then the bedside's pages without what only the bedside can change. The PIN stays in memory
 * for ten idle minutes and is forgotten when Porch leaves the screen (RemoteCaregiverSession). `onClose` goes back to the
 * family screen, with why caregiver mode ended when there's something to say.
 */
@Composable
fun RemoteCaregiverMode(app: PorchApplication, family: FamilyCredential, links: FamilyLinks, onClose: (String?) -> Unit) {
    val scope = rememberCoroutineScope()
    val close by rememberUpdatedState(onClose)
    // A call taking over the screen closes caregiver mode, so its PIN is forgotten too. Turning the phone doesn't.
    val activity = LocalActivity.current
    DisposableEffect(Unit) { onDispose { if (activity?.isChangingConfigurations != true) RemoteCaregiverSession.shared.end() } }
    fun opened(state: FamilyAdminState?) = CaregiverAdmin(app, scope, remote = family, state = state, onLock = { close(it) })
    // Turning the phone keeps caregiver mode open while its session lasts, and reads the household again.
    var admin by remember { mutableStateOf(if (RemoteCaregiverSession.shared.isActive) opened(null) else null) }
    val open = admin
    if (open == null) {
        CaregiverPINScreen(app, family, links, onCancel = { close(null) }, onUnlocked = { admin = opened(it) })
        return
    }
    // Each check-in can show approval withdrawn or the phone removed, which locks it at once, as on iOS.
    val link = links.link(family)
    val removed = link?.accessRemoved == true || link?.state?.me?.caregiver == false
    LaunchedEffect(removed) { if (removed) open.lock("Caregiver mode is no longer available on this phone.") }
    // Ten idle minutes, or Porch having left the screen.
    LaunchedEffect(open) { while (true) { if (!RemoteCaregiverSession.shared.isActive) open.lock(); delay(5_000) } }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { if (!RemoteCaregiverSession.shared.isActive) open.lock() }
    CaregiverModeContent(app, open, links, "Done", onClose = { open.lock() })
}

/** The caregiver PIN, set on the bedside. A wrong one, or too many, is refused by the server with the reason. */
@Composable
private fun CaregiverPINScreen(app: PorchApplication, family: FamilyCredential, links: FamilyLinks, onCancel: () -> Unit,
    onUnlocked: (FamilyAdminState?) -> Unit) {
    BackHandler(onBack = onCancel)
    val scope = rememberCoroutineScope()
    // Not saved with the screen's state: the PIN stays in memory only.
    var pin by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    FormScreen("Caregiver mode", navigation = { TextButton(onClick = onCancel) { Text("Cancel") } }) {
        FormSection("Caregiver PIN", "The PIN set on the bedside ${bedsideDevice(links.state(family))}.") {
            FormField(pin, { pin = it.filter(Char::isDigit).take(6) }, "Six-digit PIN", "Enter six digits",
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), visualTransformation = PasswordVisualTransformation())
            FormButton(if (busy) "Checking…" else "Open caregiver mode", enabled = !busy, onClick = {
                if (!Regex("^[0-9]{6}$").matches(pin)) { error = "Enter six digits."; return@FormButton }
                val typed = pin
                busy = true
                scope.launch {
                    try {
                        val response = app.service(family).send("verifyPIN", pin = typed)
                        app.coordinator.update(response)
                        RemoteCaregiverSession.shared.begin(typed)
                        pin = ""
                        onUnlocked(response.admin)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        error = e.message ?: "Couldn't reach Porch. Check the connection and try again."
                    } finally {
                        busy = false
                    }
                }
            })
        }
        // Reachable without the PIN.
        PrivacyPolicyLink()
    }
    PorchErrorDialog(error) { error = null }
}
