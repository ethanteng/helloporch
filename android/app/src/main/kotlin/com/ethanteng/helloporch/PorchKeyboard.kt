package com.ethanteng.helloporch

import android.content.ClipboardManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.getSystemService
import com.ethanteng.helloporch.core.PorchKeyLayout
import com.ethanteng.helloporch.core.PorchKeys
import com.ethanteng.helloporch.core.TypedText
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay

/**
 * Porch's own keyboard for its forms, as iOS's CaregiverTouchKeyboard is. Android hides its on-screen keyboard while a
 * hardware keyboard is attached, and a USB keypad counts as one, so a caregiver at the bedside could otherwise tap a
 * field and get nothing to type with. The system keyboard stays the default. Under a form, Porch keyboard switches every
 * field to keys drawn by Porch, and the choice lasts while Porch runs, so the next form opens with it too.
 */
@Stable
class PorchKeyboard internal constructor() {
    /** The field being typed in, while there is one. */
    internal var active by mutableStateOf<PorchKeyboardField?>(null)
    /** This screen's fields, in the order they first showed, which Next follows. */
    internal val fields = mutableStateListOf<PorchKeyboardField>()
    var uppercase by mutableStateOf(false)
    var symbols by mutableStateOf(false)

    companion object {
        /** Porch keyboard was chosen. Shared by every form, as a keypad stays attached from one to the next. */
        var inUse by mutableStateOf(false)
    }
}

/** One field the Porch keyboard can type in. What it reads and writes is updated after each composition. */
internal class PorchKeyboardField(val focus: FocusRequester) {
    var title = ""
    var keys = PorchKeys.TEXT
    var enabled = true
    var value = TextFieldValue()
    var onChange: (TextFieldValue) -> Unit = {}
}

internal val LocalPorchKeyboard = staticCompositionLocalOf<PorchKeyboard?> { null }

/** Which keys a field gets, from its keyboard type, as iOS picks them from `keyboardType`. */
internal fun porchKeys(type: KeyboardType): PorchKeys = when (type) {
    KeyboardType.Number, KeyboardType.NumberPassword, KeyboardType.Decimal -> PorchKeys.NUMBERS
    KeyboardType.Phone -> PorchKeys.PHONE
    else -> PorchKeys.TEXT
}

/** A key's edit, applied to a field's text and cursor. */
private fun TextFieldValue.edited(edit: (TypedText) -> TypedText): TextFieldValue {
    val result = edit(TypedText(text, selection.start, selection.end))
    return TextFieldValue(result.text, TextRange(result.start, result.end))
}

/** Android hides its on-screen keyboard while this is so (InputMethodService.onEvaluateInputViewShown). */
@Composable
internal fun hardwareKeyboardAttached(): Boolean {
    val configuration = LocalConfiguration.current
    return configuration.keyboard != Configuration.KEYBOARD_NOKEYS && configuration.hardKeyboardHidden != Configuration.HARDKEYBOARDHIDDEN_YES
}

/** "tablet" or "phone", for the system keyboard's name. */
@Composable
private fun deviceName(): String = if (LocalConfiguration.current.smallestScreenWidthDp >= 600) "tablet" else "phone"

/** A form's fields, with Porch keyboard beneath them once it's chosen. `content` is the form, which takes the room the
 * keyboard leaves. */
@Composable
internal fun PorchKeyboardHost(content: @Composable () -> Unit) {
    val keyboard = remember { PorchKeyboard() }
    CompositionLocalProvider(LocalPorchKeyboard provides keyboard) {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f)) { content() }
            PorchKeyboardChoice(keyboard)
            val field = keyboard.active
            if (PorchKeyboard.inUse && field != null) PorchKeyboardKeys(keyboard, field)
        }
    }
}

/** Under a form with fields: the system keyboard or Porch keyboard. With a keypad attached, the first is help. */
@Composable
private fun PorchKeyboardChoice(keyboard: PorchKeyboard) {
    if (keyboard.fields.isEmpty() || PorchKeyboard.inUse && keyboard.active != null) return
    val hardware = hardwareKeyboardAttached()
    val device = deviceName()
    val switcher = rememberKeyboardSwitcher(keyboard)
    var helping by remember { mutableStateOf(false) }
    // As wide as the form above it, at most.
    Column(Modifier.fillMaxWidth().wrapContentWidth().widthIn(max = 760.dp).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ChoiceButton(if (hardware) "Keyboard help" else "${device.replaceFirstChar(Char::uppercase)} keyboard") {
                if (hardware) helping = true else switcher.useSystem()
            }
            ChoiceButton("Porch keyboard") { switcher.usePorch() }
        }
        if (hardware && !PorchKeyboard.inUse && keyboard.active != null && device == "tablet") {
            Text("A connected keypad can hide the tablet keyboard. Unplug it while typing, or use Porch keyboard.",
                Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (helping) KeyboardHelp(device, onDismiss = { helping = false }, onPorch = { helping = false; switcher.usePorch() },
        onSystem = { helping = false; switcher.useSystem() })
}

/** Neither button takes focus from the field being typed in. */
@Composable
private fun RowScope.ChoiceButton(text: String, onClick: () -> Unit) {
    OutlinedButton(onClick, Modifier.weight(1f).heightIn(min = 48.dp).focusProperties { canFocus = false }) {
        Text(text, textAlign = TextAlign.Center)
    }
}

/** What happens with the system keyboard while a keypad is attached, as iOS's keyboard help says. */
@Composable
private fun KeyboardHelp(device: String, onDismiss: () -> Unit, onPorch: () -> Unit, onSystem: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text("${device.replaceFirstChar(Char::uppercase)} keyboard with a keypad") },
        text = {
            Text("A connected keypad can hide the $device keyboard. Unplug it while you type, or use Porch keyboard.\n\n" +
                "Android can also show its keyboard with a keypad attached: turn on the on-screen keyboard in Settings, under Physical keyboard.")
        },
        confirmButton = { TextButton(onClick = onPorch) { Text("Use Porch keyboard") } },
        dismissButton = {
            Row {
                TextButton(onClick = onSystem) { Text("Try $device keyboard") }
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        })
}

/** Switches between the keyboards, keeping the field being typed in, or starting in the first one. */
private class KeyboardSwitcher(private val keyboard: PorchKeyboard, private val restart: () -> Unit, private val showSystem: () -> Unit) {
    fun usePorch() {
        PorchKeyboard.inUse = true
        restart()
    }

    fun useSystem() {
        PorchKeyboard.inUse = false
        restart()
        showSystem()
    }

    fun target(): PorchKeyboardField? = keyboard.active ?: keyboard.fields.firstOrNull { it.enabled }
}

@Composable
private fun rememberKeyboardSwitcher(keyboard: PorchKeyboard): KeyboardSwitcher {
    val focusManager = LocalFocusManager.current
    val systemKeyboard = LocalSoftwareKeyboardController.current
    return remember(keyboard, focusManager, systemKeyboard) {
        lateinit var switcher: KeyboardSwitcher
        switcher = KeyboardSwitcher(keyboard,
            restart = {
                // Focusing again starts typing again, through the keyboard now chosen.
                val target = switcher.target()
                if (keyboard.active != null) { systemKeyboard?.hide(); focusManager.clearFocus() }
                target?.focus?.requestFocus()
            },
            showSystem = { systemKeyboard?.show() })
        switcher
    }
}

/** Porch keyboard's keys for the field being typed in, under the form. */
@Composable
private fun PorchKeyboardKeys(keyboard: PorchKeyboard, field: PorchKeyboardField) {
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val hardware = hardwareKeyboardAttached()
    val device = deviceName()
    val switcher = rememberKeyboardSwitcher(keyboard)
    var helping by remember { mutableStateOf(false) }
    val press: (String) -> Unit = { key -> pressKey(key, keyboard, field, context) { focusManager.clearFocus() } }
    Surface(color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(field.title.ifEmpty { "Porch keyboard" }, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = { if (hardware) helping = true else switcher.useSystem() }, Modifier.focusProperties { canFocus = false }) {
                    Text(if (hardware) "Keyboard help" else "Use $device keyboard")
                }
            }
            for (row in PorchKeyLayout.rows(field.keys, keyboard.symbols)) KeyRow(row, keyboard.uppercase, press)
            KeyRow(PorchKeyLayout.controls(field.keys, keyboard.uppercase, keyboard.symbols), keyboard.uppercase, press)
        }
    }
    if (helping) KeyboardHelp(device, onDismiss = { helping = false }, onPorch = { helping = false },
        onSystem = { helping = false; switcher.useSystem() })
}

private fun pressKey(key: String, keyboard: PorchKeyboard, field: PorchKeyboardField, context: Context, done: () -> Unit) {
    if (!field.enabled) return
    val typed = PorchKeyLayout.typed(key, keyboard.uppercase)
    when {
        typed != null -> field.onChange(field.value.edited { it.insert(typed) })
        key == PorchKeyLayout.DELETE -> field.onChange(field.value.edited { it.deleteBackward() })
        key == PorchKeyLayout.PASTE -> {
            val clip = context.getSystemService<ClipboardManager>()?.primaryClip?.takeIf { it.itemCount > 0 }
            val text = clip?.getItemAt(0)?.coerceToText(context)?.toString()?.replace("\n", " ")
            if (!text.isNullOrEmpty()) field.onChange(field.value.edited { it.insert(text) })
        }
        key == PorchKeyLayout.UPPERCASE || key == PorchKeyLayout.LOWERCASE -> keyboard.uppercase = !keyboard.uppercase
        key == PorchKeyLayout.SYMBOLS || key == PorchKeyLayout.LETTERS -> keyboard.symbols = !keyboard.symbols
        key == PorchKeyLayout.NEXT -> {
            val next = keyboard.fields.dropWhile { it !== field }.drop(1).firstOrNull { it.enabled }
            if (next != null) next.focus.requestFocus() else done()
        }
        key == PorchKeyLayout.DONE -> done()
    }
}

/** A row of equal keys, each 52 dp tall. Keys never take focus, so the field keeps it. */
@Composable
private fun KeyRow(keys: List<String>, uppercase: Boolean, press: (String) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (key in keys) {
            val title = PorchKeyLayout.title(key, uppercase)
            val description = if (key == PorchKeyLayout.DELETE) "Delete character" else title
            Box(Modifier.weight(1f).height(52.dp)
                .clip(RoundedCornerShape(9.dp))
                .background(MaterialTheme.colorScheme.surface)
                .focusProperties { canFocus = false }
                .clickable(role = Role.Button) { press(key) }
                .semantics { contentDescription = description },
                contentAlignment = Alignment.Center) {
                Text(title, Modifier.clearAndSetSemantics {}, maxLines = 1,
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = if (key.length > 1) 15.sp else 22.sp))
            }
        }
    }
}

/**
 * A text field Porch keyboard can type in, as iOS's form fields are. `title` names it above Porch keyboard's keys.
 * Outside a form, it's an ordinary field.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun PorchTextField(
    value: String,
    onValueChange: (String) -> Unit,
    title: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: (@Composable () -> Unit)? = null,
    placeholder: (@Composable () -> Unit)? = null,
    prefix: (@Composable () -> Unit)? = null,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
) {
    // The text with its cursor, so keys type where the cursor is. Text changed from outside, such as by a filter that
    // keeps a PIN to six digits, puts the cursor at the end.
    var edited by remember { mutableStateOf(TextFieldValue(value, TextRange(value.length))) }
    val shown = if (edited.text == value) edited else TextFieldValue(value, TextRange(value.length))
    val change: (TextFieldValue) -> Unit = { next ->
        edited = next
        if (next.text != value) onValueChange(next.text)
    }
    val keyboard = LocalPorchKeyboard.current
    val focus = remember { FocusRequester() }
    val bring = remember { BringIntoViewRequester() }
    val field = remember { PorchKeyboardField(focus) }
    var focused by remember { mutableStateOf(false) }
    SideEffect {
        field.title = title
        field.keys = porchKeys(keyboardOptions.keyboardType)
        field.enabled = enabled
        field.value = shown
        field.onChange = change
    }
    DisposableEffect(keyboard) {
        keyboard?.fields?.add(field)
        onDispose {
            keyboard?.fields?.remove(field)
            if (keyboard?.active === field) keyboard.active = null
        }
    }
    // Porch keyboard takes the bottom of the screen, so the field moves up into what's left.
    LaunchedEffect(focused, PorchKeyboard.inUse) {
        if (focused && PorchKeyboard.inUse) { delay(100); bring.bringIntoView() }
    }
    // While Porch keyboard is in use, this field doesn't open the system keyboard. Only Porch's own fields: another
    // field, such as one in a dialog over the form, which Porch keyboard can't reach, keeps the system keyboard.
    InterceptPlatformTextInput(interceptor = { request, next ->
        if (keyboard != null && PorchKeyboard.inUse) awaitCancellation() else next.startInputMethod(request)
    }) {
        OutlinedTextField(shown, change,
            modifier.fillMaxWidth().focusRequester(focus).bringIntoViewRequester(bring).onFocusChanged {
                focused = it.isFocused
                if (keyboard == null) return@onFocusChanged
                if (it.isFocused) keyboard.active = field else if (keyboard.active === field) keyboard.active = null
            },
            enabled = enabled, singleLine = true, label = label, placeholder = placeholder, prefix = prefix,
            keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, visualTransformation = visualTransformation)
    }
}
