package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri

/** A screen of Porch's forms, as iOS's caregiver forms are: a bar with its title and a way back, and one column, at most
 * 760 dp wide like the iOS card, that scrolls. `navigation` is the bar's button, such as Cancel or Back. */
@Composable
fun FormScreen(title: String, navigation: (@Composable () -> Unit)? = null, actions: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.safeDrawingPadding()) {
            // The title takes the room between the button and the bar's far end, so a narrow pane never overlaps them.
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                navigation?.invoke()
                Text(title, Modifier.weight(1f).padding(horizontal = 8.dp), style = MaterialTheme.typography.titleLarge, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, textAlign = if (navigation == null) TextAlign.Center else TextAlign.Start)
                actions?.invoke()
            }
            HorizontalDivider()
            Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), contentAlignment = Alignment.TopCenter) {
                Column(Modifier.widthIn(max = 760.dp).fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
            }
        }
    }
}

/** A heading, what it's for, and what goes with it. */
@Composable
fun FormSection(title: String, detail: String? = null, content: @Composable ColumnScope.() -> Unit = {}) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(title, style = MaterialTheme.typography.headlineMedium)
        detail?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        content()
    }
}

/** A full-width button: filled for the way on, outlined for another choice. */
@Composable
fun FormButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, filled: Boolean = true) {
    val label: @Composable () -> Unit = { Text(text, textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium) }
    val size = modifier.fillMaxWidth().heightIn(min = 50.dp)
    if (filled) Button(onClick, size, enabled = enabled) { label() } else OutlinedButton(onClick, size, enabled = enabled) { label() }
}

/** A quieter choice, such as Do this later. */
@Composable
fun FormLink(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TextButton(onClick, modifier.fillMaxWidth()) { Text(text, textAlign = TextAlign.Center) }
}

@Composable
fun FormField(
    value: String,
    onValueChange: (String) -> Unit,
    title: String,
    placeholder: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
) {
    OutlinedTextField(value, onValueChange, modifier.fillMaxWidth(), enabled = enabled, singleLine = true, label = { Text(title) },
        placeholder = { Text(placeholder) }, keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, visualTransformation = visualTransformation)
}

/** What went wrong, as iOS's `showPorchError` shows it. Null shows nothing. */
@Composable
fun PorchErrorDialog(message: String?, onDismiss: () -> Unit) {
    if (message == null) return
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text("Couldn't complete that") },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } })
}

/** Anyone can read it, from the first screen on. */
@Composable
fun PrivacyPolicyLink() {
    val context = LocalContext.current
    FormLink("Privacy policy", onClick = { openPrivacyPolicy(context) })
}

fun openPrivacyPolicy(context: Context) {
    try { context.startActivity(Intent(Intent.ACTION_VIEW, "https://helloporch.store/privacy".toUri())) } catch (_: ActivityNotFoundException) {}
}
