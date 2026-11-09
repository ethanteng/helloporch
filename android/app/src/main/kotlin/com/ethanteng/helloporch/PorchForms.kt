package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.annotation.DrawableRes
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
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import com.ethanteng.helloporch.core.RemoteCaregiverSession

/** A screen of Porch's forms, as iOS's caregiver forms are: a bar with its title and a way back, and one column, at most
 * 760 dp wide like the iOS card, that scrolls. `navigation` is the bar's button, such as Cancel or Back. */
@Composable
fun FormScreen(title: String, navigation: (@Composable () -> Unit)? = null, actions: (@Composable () -> Unit)? = null,
    scrolls: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    // The page, which FormCard's cards sit on. Material's own theme makes it the same color as a surface.
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.safeDrawingPadding()) {
            // The title takes the room between the button and the bar's far end, so a narrow pane never overlaps them. It gets
            // smaller before it's cut short, as beside Back to clock in caregiver mode's list on a 10-inch tablet.
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                navigation?.invoke()
                val style = MaterialTheme.typography.titleLarge
                Text(title, Modifier.weight(1f).padding(horizontal = 8.dp), style = style, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, textAlign = if (navigation == null) TextAlign.Center else TextAlign.Start,
                    autoSize = TextAutoSize.StepBased(minFontSize = 16.sp, maxFontSize = style.fontSize))
                actions?.invoke()
            }
            HorizontalDivider()
            // Porch keyboard, once chosen, types in the fields here (PorchKeyboard.kt).
            PorchKeyboardHost {
                // A page that scrolls a list of its own, such as About's licenses, fills the screen instead.
                val scrolling = if (scrolls) Modifier.verticalScroll(rememberScrollState()) else Modifier
                Box(Modifier.fillMaxSize().then(scrolling), contentAlignment = Alignment.TopCenter) {
                    val size = if (scrolls) Modifier.fillMaxWidth() else Modifier.fillMaxSize()
                    Column(Modifier.widthIn(max = 760.dp).then(size).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
                }
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

/** A card of its own on the page, as iOS's `section` is: a centered heading, what it's about, and what goes with it,
 * centered under them. Raised as CaregiverGroup's cards are, so it stands out on Material's page as well as PorchTheme's,
 * which keeps it white. */
@Composable
fun FormCard(title: String, detail: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), tonalElevation = 2.dp) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, Modifier.fillMaxWidth().semantics { heading() }, style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            detail?.let {
                Text(it, Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center)
            }
            content()
        }
    }
}

/** A full-width button: filled for the way on, outlined for another choice. `icon` goes before its words, as iOS's
 * buttons show a symbol. */
@Composable
fun FormButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, filled: Boolean = true,
    @DrawableRes icon: Int? = null) {
    val size = modifier.fillMaxWidth().heightIn(min = 50.dp)
    val shape = LocalFormButtonShape.current
    if (filled) Button(onClick, size, enabled = enabled, shape = shape ?: ButtonDefaults.shape) { ButtonLabel(text, icon) }
    else OutlinedButton(onClick, size, enabled = enabled, shape = shape ?: ButtonDefaults.outlinedShape) { ButtonLabel(text, icon) }
}

/** A full-width button that's only its words, as iOS's plain buttons are: one of several things to do, such as Send a
 * message under the call buttons. `color` is for one that removes something. */
@Composable
fun FormPlainButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, color: Color = Color.Unspecified,
    @DrawableRes icon: Int? = null) {
    TextButton(onClick, modifier.fillMaxWidth().heightIn(min = 50.dp), enabled = enabled,
        shape = LocalFormButtonShape.current ?: ButtonDefaults.textShape) {
        ButtonLabel(text, icon, color)
    }
}

/** A button's icon and words, in the button's color unless `color` says otherwise. The icon starts the text itself, so
 * it stays beside the words when they wrap, as iOS's does, rather than at the edge of a full-width line. It's
 * decoration: a screen reader hears only the words. */
@Composable
private fun ButtonLabel(text: String, @DrawableRes icon: Int?, color: Color = Color.Unspecified) {
    val style = MaterialTheme.typography.titleMedium
    if (icon == null) { Text(text, textAlign = TextAlign.Center, style = style, color = color); return }
    val label = buildAnnotatedString {
        appendInlineContent("icon", " ")
        append(" ")
        append(text)
    }
    // Sized in em, so it grows with the words under a larger font setting.
    val inline = mapOf("icon" to InlineTextContent(Placeholder(1.4.em, 1.4.em, PlaceholderVerticalAlign.TextCenter)) {
        Icon(painterResource(icon), contentDescription = null, Modifier.fillMaxSize(), tint = color.takeOrElse { LocalContentColor.current })
    })
    val words = AnnotatedString(text)
    Text(label, Modifier.clearAndSetSemantics { this.text = words }, textAlign = TextAlign.Center, style = style,
        color = color, inlineContent = inline)
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
    PorchTextField(value, onValueChange, title, modifier, enabled = enabled, label = { Text(title) }, placeholder = { Text(placeholder) },
        keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, visualTransformation = visualTransformation)
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
    try { staysInCaregiverMode { context.startActivity(Intent(Intent.ACTION_VIEW, "https://helloporch.store/privacy".toUri())) } }
    catch (_: ActivityNotFoundException) {}
}

/** Before Porch opens another app's screen for the caregiver, such as the photo picker, the share sheet or the privacy
 * policy: caregiver mode on a family phone stays open behind it. A picker `answers`, so coming back without its answer
 * ends caregiver mode (RemoteCaregiverSession). If the screen doesn't open, the next time Porch leaves is still the
 * caregiver leaving. */
fun staysInCaregiverMode(answers: Boolean = false, open: () -> Unit) {
    RemoteCaregiverSession.shared.stayThroughNextStop(answers)
    try {
        open()
    } catch (e: Exception) {
        RemoteCaregiverSession.shared.didNotOpen()
        throw e
    }
}
