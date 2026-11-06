package com.ethanteng.helloporch

import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ethanteng.helloporch.core.PorchNumber

/** The corded phone's own screen, which the Cell2Jack connection provides: `onDone` goes on to adding the caregiver's
 * phone, and `onBack` returns to the choice of how they'll call. */
typealias CordedPhoneStep = @Composable (onDone: () -> Unit, onBack: () -> Unit) -> Unit

/** Setup's screens, one at a time. The system Back button goes back as the bar's Back does. */
@Composable
fun BedsideSetupFlow(app: PorchApplication, setup: BedsideSetup, cordedPhoneSetup: CordedPhoneStep) {
    // Each check-in can change the name these screens use, a number set up in the background, or a phone that joined.
    val links by app.coordinator.links.collectAsStateWithLifecycle()
    val lovedOne = setup.lovedOne
    BackHandler(enabled = setup.canGoBack) { setup.back() }
    CompositionLocalProvider(LocalBedsideName provides lovedOne) {
        when (setup.step) {
            SetupStep.LINK -> SetupScreen(setup) { SetupLink(setup) }
            SetupStep.NAME -> SetupScreen(setup) { SetupName(setup) }
            SetupStep.PIN -> SetupScreen(setup) { SetupPIN(setup) }
            SetupStep.NUMBER -> SetupScreen(setup) {
                setup.number?.let { SetupNumberScreen(it, lovedOne, onContinue = { setup.show(SetupStage.PERMISSIONS) }) }
            }
            SetupStep.PERMISSIONS -> SetupScreen(setup) { SetupPermissionsScreen(app, lovedOne, onContinue = { setup.show(SetupStage.PHONE) }) }
            SetupStep.CALLING -> SetupScreen(setup) {
                val usbHost = LocalContext.current.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
                SetupCallingScreen(lovedOne, offersCordedPhone = usbHost, onCordedPhone = { setup.push(SetupStep.CORDED_PHONE) },
                    onUSBKeypad = { setup.push(SetupStep.USB_KEYPAD) }, onTouchscreen = { setup.show(SetupStage.YOUR_PHONE) })
            }
            SetupStep.USB_KEYPAD -> SetupScreen(setup) { SetupUSBKeypadScreen(lovedOne, onContinue = { setup.show(SetupStage.YOUR_PHONE) }) }
            SetupStep.CORDED_PHONE -> cordedPhoneSetup({ setup.show(SetupStage.YOUR_PHONE) }, { setup.back() })
            SetupStep.YOUR_PHONE -> SetupScreen(setup) {
                setup.yourPhone?.let { SetupYourPhoneScreen(it, lovedOne, onContinue = { setup.show(SetupStage.DONE) }) }
            }
            SetupStep.DONE -> SetupScreen(setup) { SetupDone(lovedOne, links.state?.porchNumber, onFinish = setup::finish) }
        }
    }
    PorchErrorDialog(setup.error) { setup.error = null }
}

/** One screen of setup, with Cancel on the first one until the tablet is set up, and Back on the ones after it. */
@Composable
private fun SetupScreen(setup: BedsideSetup, content: @Composable ColumnScope.() -> Unit) {
    val navigation: (@Composable () -> Unit)? = when {
        setup.canCancel -> { { TextButton(onClick = setup::cancel) { Text("Cancel") } } }
        setup.canGoBack -> { { TextButton(onClick = setup::back) { Text("Back") } } }
        else -> null
    }
    FormScreen("Set up Porch", navigation, content)
}

/** For the first screen: this device can be a family member's instead, and anyone can read the privacy policy. */
@Composable
private fun WayOut(setup: BedsideSetup) {
    if (setup.offersFamily) FormLink("Use this device as a family member", onClick = setup::useAsFamily)
    PrivacyPolicyLink()
}

/** The private setup link from the invitation, when Porch wasn't opened from it. */
@Composable
private fun SetupLink(setup: BedsideSetup) {
    var link by rememberSaveable { mutableStateOf("") }
    FormSection("Your setup link", "Paste the private link from your Porch invitation. If you don't have one, ask whoever invited you for your setup link.") {
        FormField(link, { link = it }, "Setup link", "Paste your setup link", keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
        FormButton("Continue", onClick = { setup.saveLink(link) })
    }
    WayOut(setup)
}

@Composable
private fun SetupName(setup: BedsideSetup) {
    var name by rememberSaveable { mutableStateOf(setup.name) }
    FormSection("Who is this Porch for?", "Family see this name, and you can change it later.") {
        FormField(name, { name = it }, "Their name", "For example, Mom", keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        FormButton("Continue", onClick = { setup.saveName(name) })
    }
    if (setup.steps.size == 1) WayOut(setup)
}

/** The caregiver PIN, chosen twice. Continuing sets the tablet up with the server. */
@Composable
private fun SetupPIN(setup: BedsideSetup) {
    var pin by rememberSaveable { mutableStateOf("") }
    var confirmation by rememberSaveable { mutableStateOf("") }
    val digits = KeyboardOptions(keyboardType = KeyboardType.NumberPassword)
    FormSection("Choose a caregiver PIN", "Six digits. Caregivers use it to change Porch's settings, here and on their phones.") {
        FormField(pin, { pin = it.filter(Char::isDigit).take(6) }, "Caregiver PIN", "Six digits", keyboardOptions = digits,
            visualTransformation = PasswordVisualTransformation())
        FormField(confirmation, { confirmation = it.filter(Char::isDigit).take(6) }, "Enter it again", "The same six digits", keyboardOptions = digits,
            visualTransformation = PasswordVisualTransformation())
        FormButton("Continue", onClick = { setup.enroll(pin, confirmation) }, enabled = !setup.enrolling)
    }
}

@Composable
private fun SetupDone(lovedOne: String, number: String?, onFinish: () -> Unit) {
    FormSection("$lovedOne's Porch is ready") {
        // A number that was still being set up appears here once it's ready.
        if (number == null) Text("Porch is still getting $lovedOne's phone number. Caregiver mode shows it once it's ready.", style = MaterialTheme.typography.bodyLarge)
        else Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("$lovedOne's Porch number", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyLarge)
            Text(PorchNumber.display(number), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, fontSize = 34.sp, fontWeight = FontWeight.Bold)
        }
        Text("Only people on the keypad and numbers you allow can call this number. Anyone else is turned away and listed under Blocked numbers, where you can allow them.",
            style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        // A caregiver puts people on the keypad in caregiver mode.
        FormButton("Back to the clock", onClick = onFinish)
    }
}
