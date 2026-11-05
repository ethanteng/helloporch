package com.ethanteng.helloporch

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchNumber
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/**
 * The household's own phone number, as `SetupNumberViewController` gets it on iOS. Porch fills in an area code near the
 * tablet, so it's one tap; another can be chosen first. Setup can't go on without trying for a number, but once Porch has
 * tried, Continue works whether the number is ready or not: Porch keeps trying by itself.
 */
class SetupNumber(
    private val app: PorchApplication,
    private val scope: CoroutineScope,
    private val lovedOne: () -> String,
    private val onError: (String) -> Unit,
) {
    var areaCode by mutableStateOf("")
    var nearby by mutableStateOf(emptyList<String>())
        private set
    var message by mutableStateOf("")
        private set
    /** The number, once it's set up. Everything for choosing one goes away then. */
    var assigned by mutableStateOf<String?>(null)
        private set
    var showsContinue by mutableStateOf(false)
        private set
    /** The area code field, and the choices near it, shown when there's an area code to type. */
    var showsAreaChoice by mutableStateOf(true)
        private set
    var showsDifferent by mutableStateOf(false)
        private set
    var busy by mutableStateOf(false)
        private set
    /** Getting a number: the area code stays as it is until that's over. */
    var assigning by mutableStateOf(false)
        private set
    /** Counts requests to put the cursor in the area code. */
    var focusRequests by mutableIntStateOf(0)
        private set
    private var task: Job? = null

    fun load() {
        app.coordinator.state?.porchNumber?.let { show(it); return }
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return
        val setUp = app.coordinator.state?.phoneSetup
        areaCode = setUp?.areaCode ?: ""
        message = if (setUp?.needsChoice == true) setUp.error ?: "" else "Finding an area code near this tablet…"
        if (setUp?.needsChoice != true) showsAreaChoice = false
        busy = true
        task = scope.launch {
            try {
                // Without a suggestion, such as outside the US, the caregiver types one.
                val options = try {
                    app.service(credential).send("phoneNumberOptions", pin = app.caregiverPIN.ifEmpty { null })
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    null
                }
                // The reply carries the household, including a number a background try already bought.
                options?.let(app.coordinator::update)
                options?.porchNumber?.let { show(it); return@launch }
                if (areaCode.isEmpty()) areaCode = options?.areaCode ?: ""
                nearby = options?.nearby ?: emptyList()
                if (setUp?.needsChoice == true) return@launch
                // With an area code near the tablet, getting the number is one tap.
                if (PorchNumber.isAreaCode(areaCode)) {
                    showsAreaChoice = false; showsDifferent = true
                    message = "Porch will get a number in area code $areaCode, near this tablet."
                } else {
                    showsAreaChoice = true
                    message = "Type the area code you'd like, such as 510."
                }
            } finally {
                busy = false
            }
        }
    }

    fun chooseAreaCode() {
        showsAreaChoice = true; showsDifferent = false
        message = "Choose an area code near this tablet, or type another."
        focusRequests++
    }

    fun assign() {
        val code = areaCode.trim()
        if (!PorchNumber.isAreaCode(code)) { onError("Enter a three-digit US area code, such as 510."); return }
        if (busy) return
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return
        val offeredAnother = showsDifferent
        busy = true; assigning = true; showsDifferent = false
        message = "Getting a number in area code $code. This can take a little while."
        task = scope.launch {
            try {
                // The first number Porch buys also sets up its phone line, which takes longer than most requests.
                val response = app.service(credential).send("assignPhoneNumber", mapOf("areaCode" to JsonPrimitive(code)), pin = app.caregiverPIN.ifEmpty { null })
                app.coordinator.update(response)
                val number = response.porchNumber
                if (number != null) show(number)
                else waiting("Porch is still getting ${lovedOne()}'s number. It keeps trying, and caregiver mode shows the number once it's ready.")
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val failure = error as? FamilyServiceException
                val text = error.message ?: "Couldn't reach Porch. Check the connection and try again."
                // Another area code is up to the caregiver. Porch's own limit clears by itself, and it keeps trying.
                when {
                    failure?.code == "noNumbers" || failure?.status == 400 -> { showsAreaChoice = true; message = text }
                    failure?.code == "numberLimit" -> waiting("$text Porch keeps trying, and caregiver mode shows the number once it's ready.")
                    else -> waiting("$text You can go on and get the number in caregiver mode later.")
                }
            } finally {
                busy = false; assigning = false
                // Without a number yet, another area code can still be chosen the way it could before.
                if (assigned == null && !showsAreaChoice) showsDifferent = offeredAnother
            }
        }
    }

    fun cancel() { task?.cancel() }

    private fun waiting(text: String) {
        message = text; showsContinue = true
    }

    private fun show(number: String) {
        assigned = PorchNumber.display(number)
        showsAreaChoice = false; showsDifferent = false
        message = "Anyone can call ${lovedOne()}'s Porch on this number. When ${lovedOne()} calls a regular phone, it shows this number too."
        showsContinue = true
    }
}

/** `onContinue` goes on: setup goes to the microphone and camera. Caregiver mode opens this screen too (phase 4). */
@Composable
fun SetupNumberScreen(number: SetupNumber, lovedOne: String, onContinue: () -> Unit) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(number.focusRequests) { if (number.focusRequests > 0) focus.requestFocus() }
    FormSection("$lovedOne's Porch number", "People can call $lovedOne's Porch from any phone.") {
        number.assigned?.let {
            Text(it, Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite }, fontSize = 34.sp, fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center, style = MaterialTheme.typography.headlineLarge)
        }
        Text(number.message, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, style = MaterialTheme.typography.bodyLarge)
        if (number.assigned == null) {
            if (number.showsAreaChoice) {
                FormField(number.areaCode, { typed -> number.areaCode = typed.filter(Char::isDigit).take(3) }, "Area code", "For example, 510",
                    Modifier.focusRequester(focus), enabled = !number.assigning, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                if (number.nearby.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        for (code in number.nearby) {
                            OutlinedButton(onClick = { number.areaCode = code }, Modifier.weight(1f).semantics { contentDescription = "Area code $code" }) { Text(code) }
                        }
                    }
                }
            }
            FormButton("Get number", onClick = number::assign, enabled = !number.busy)
            if (number.showsDifferent) FormLink("Use a different area code", onClick = number::chooseAreaCode)
        }
        if (number.showsContinue) FormButton("Continue", onClick = onContinue)
    }
}
