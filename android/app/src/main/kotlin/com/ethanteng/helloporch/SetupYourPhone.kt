package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ethanteng.helloporch.core.FamilyInvitation
import com.ethanteng.helloporch.core.FamilySnapshot
import com.ethanteng.helloporch.core.PorchExperience
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Add your phone, as `SetupYourPhoneViewController` does on iOS: a QR code of a one-use invitation with caregiver mode,
 * for the caregiver's phone camera, or the same invitation sent another way. It has their name, so Porch can say who's
 * calling, and drop-in approved as other invitations do once the tablet can use its microphone and camera.
 */
class SetupYourPhone(
    private val app: PorchApplication,
    private val scope: CoroutineScope,
    private val lovedOne: () -> String,
    private val onError: (String) -> Unit,
) {
    /** The invitation the code is for, and when it stops working, in seconds since 1970. */
    data class Invitation(val id: String, val link: String, val expiresAt: Long)

    enum class Progress {
        /** Their name, then Show QR code. */
        NAMING,
        SHOWING,
        /** The code ran out and a new one couldn't be made, such as while the tablet is offline: Show QR code tries again. */
        EXPIRED,
        JOINED,
    }

    var name by mutableStateOf("")
    var progress by mutableStateOf(Progress.NAMING)
        private set
    var invitation by mutableStateOf<Invitation?>(null)
        private set
    var status by mutableStateOf("")
        private set
    var busy by mutableStateOf(false)
        private set
    private var task: Job? = null
    private var expiry: Job? = null

    fun createInvitation() {
        val chosen = name.trim()
        if (chosen.isEmpty()) { onError("Enter your name, so ${lovedOne()}'s Porch can say who's calling."); return }
        if (busy) return
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return
        // Drop-in answers on this tablet, so it's approved only once the tablet can use what it needs.
        val microphone = granted(app, Manifest.permission.RECORD_AUDIO)
        val camera = microphone && granted(app, Manifest.permission.CAMERA)
        // Replacing an expired code. A phone that joins with it, including via this reply, already counted.
        val replacing = invitation != null
        busy = true
        task = scope.launch {
            try {
                val values = mapOf("name" to JsonPrimitive(chosen), "caregiver" to JsonPrimitive(true),
                    "permissions" to JsonObject(mapOf("audio" to JsonPrimitive(microphone), "video" to JsonPrimitive(camera))))
                val response = app.service(credential).send("createInvite", values, pin = app.caregiverPIN.ifEmpty { null })
                val code = response.code; val id = response.invitationID
                if (code == null || id == null) throw IllegalStateException("Paste the complete Porch invitation link from your caregiver.")
                app.coordinator.update(response)
                if (replacing && invitation == null) return@launch
                show(Invitation(id, FamilyInvitation.url(credential.origin, code, app.device.defaultOrigin), response.expiresAt ?: 0))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (replacing && invitation == null) return@launch
                invitation?.let { if (it.expiresAt <= nowSeconds()) codeExpired() }
                onError(error.message ?: "Couldn't reach Porch. Check the connection and try again.")
            } finally {
                busy = false
            }
        }
    }

    private fun show(shown: Invitation) {
        invitation = shown
        progress = Progress.SHOWING
        status = "Waiting for your phone…"
        // An invitation lasts a day. One that runs out while it's showing is replaced, for the same name. It stays until
        // the new one is ready, so a phone that joins meanwhile still counts.
        expiry?.cancel()
        val waitSeconds = shown.expiresAt - nowSeconds()
        // Only a code that still has time left is replaced on that timer. A stamp already in the past (expiresAt
        // missing, or the tablet's clock a day ahead) stays on screen: a zero wait would ask for another code and
        // repeat. Coming back to this screen tries once more.
        if (waitSeconds <= 0) return
        expiry = scope.launch {
            delay(waitSeconds * 1000)
            if (invitation == shown) createInvitation()
        }
    }

    /** Their phone joined with the invitation. */
    fun familyChanged(state: FamilySnapshot?) {
        val shown = invitation ?: return
        if (state?.people?.any { it.invitationID == shown.id } != true) return
        invitation = null; expiry?.cancel()
        progress = Progress.JOINED
        status = "Your phone joined ${lovedOne()}'s Porch."
    }

    /** Back on screen: a code that ran out while Porch was away is replaced, as on iOS. */
    fun returnedToForeground() {
        val shown = invitation ?: return
        if (shown.expiresAt <= nowSeconds()) createInvitation()
    }

    private fun codeExpired() {
        invitation = null; expiry?.cancel()
        progress = Progress.EXPIRED
        status = "That code ran out. Tap Show QR code for a new one."
    }

    /** The share sheet, for the same invitation. An expired code is being replaced; its link would only say it ran out. */
    fun share(context: Context) {
        val shown = invitation?.takeIf { it.expiresAt > nowSeconds() } ?: return
        // A web link opens Porch, or shows how to get it first.
        val note = if (shown.link.startsWith("https:")) "Join our Porch! Open this link on your phone. If you don't have Porch yet, it shows you how to get it. It works once, for 24 hours."
            else "Join our Porch! This link works once, for 24 hours."
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "$note\n${shown.link}")
        try { context.startActivity(Intent.createChooser(send, null)) } catch (_: ActivityNotFoundException) {}
    }

    fun cancel() { task?.cancel(); expiry?.cancel() }

    companion object {
        /** A caregiver's phone has already joined, such as on a setup that was resumed, so there's no need. */
        fun needed(state: FamilySnapshot?): Boolean = state?.people?.any { it.role == PorchExperience.FAMILY && it.caregiver == true } != true

        private fun nowSeconds() = System.currentTimeMillis() / 1000
        private fun granted(context: Context, permission: String) = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
}

@Composable
fun SetupYourPhoneScreen(yourPhone: SetupYourPhone, lovedOne: String, onContinue: () -> Unit) {
    val context = LocalContext.current
    val showing = yourPhone.progress == SetupYourPhone.Progress.SHOWING
    LifecycleEventEffect(Lifecycle.Event.ON_START) { yourPhone.returnedToForeground() }
    FormSection("Add your phone", "Call $lovedOne, send messages and change settings from your phone. Your name tells $lovedOne who's calling.") {
        if (yourPhone.progress == SetupYourPhone.Progress.NAMING) {
            FormField(yourPhone.name, { yourPhone.name = it }, "Your name", "For example, Ethan",
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { yourPhone.createInvitation() }))
        }
        if (yourPhone.progress == SetupYourPhone.Progress.NAMING || yourPhone.progress == SetupYourPhone.Progress.EXPIRED) {
            FormButton("Show QR code", onClick = yourPhone::createInvitation, enabled = !yourPhone.busy)
        }
        val invitation = yourPhone.invitation
        if (showing && invitation != null) {
            InvitationCode(invitation.link)
            Text("Open the Camera on your phone and point it at this code. If Porch isn't on your phone yet, the link shows how to get it.",
                Modifier.fillMaxWidth(), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyLarge)
            FormLink("Send the invitation instead", onClick = { yourPhone.share(context) })
        }
        if (yourPhone.progress != SetupYourPhone.Progress.NAMING) {
            Text(yourPhone.status, Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite }, textAlign = TextAlign.Center,
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        }
        // Going on without a phone is quieter than showing the code, until a phone has joined.
        FormButton("Continue", onClick = onContinue, filled = yourPhone.progress == SetupYourPhone.Progress.JOINED)
    }
}

/** Black on white, whatever the theme, so any camera reads it: drawn a pixel to a module and scaled up without smoothing. */
@Composable
fun InvitationCode(link: String, description: String = "QR code for your phone's invitation") {
    val bitmap = remember(link) { qrCode(link) }
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(Modifier.background(Color.White, RoundedCornerShape(16.dp)).padding(16.dp)) {
            Image(bitmap.asImageBitmap(), description, Modifier.size(240.dp), filterQuality = FilterQuality.None)
        }
    }
}

/** Error correction M, as on iOS. The white frame around it is most of the quiet zone. */
private fun qrCode(text: String): Bitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0,
        mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 1, EncodeHintType.CHARACTER_SET to "UTF-8"))
    val pixels = IntArray(matrix.width * matrix.height) { if (matrix[it % matrix.width, it / matrix.width]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
    return createBitmap(matrix.width, matrix.height).apply { setPixels(pixels, 0, matrix.width, 0, 0, matrix.width, matrix.height) }
}
