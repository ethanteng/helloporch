package com.ethanteng.helloporch

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.PorchExperience
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/**
 * This phone's name and photo in one family, as iOS's FamilyProfileViewController shows them: what the bedside shows
 * for it, unless a caregiver chose otherwise, which it says. A photo comes from the camera or the library, made a JPEG
 * under 1 MB with its longest side at most 768 pixels, then uploaded (`profilePhotoUpload`) and saved (`setProfile`).
 * Also whether video calls start with the camera on, which is this phone's.
 */
@Composable
fun FamilyProfileScreen(app: PorchApplication, family: FamilyCredential, links: FamilyLinks, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state = links.state(family)
    val me = state?.me
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var editedName by rememberSaveable { mutableStateOf<String?>(null) }
    var choosing by remember { mutableStateOf(false) }
    var camera by remember { mutableStateOf(CallPreferences.startVideoWithCamera(app.settings)) }
    val lovedOne = state?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }?.name ?: state?.householdName ?: "your loved one"
    // A new phone, or a photo saved elsewhere: it downloads, and tries again on later check-ins if that fails.
    val photoID = me?.profile?.photoID
    val photo = remember(photoID, FamilyPhotos.saved) { FamilyPhotos.data(app, photoID) }
    LaunchedEffect(photoID, photo == null) {
        if (photoID == null || photo != null) return@LaunchedEffect
        // A download that failed may be tried again after a minute, so it is, until the photo is here.
        while (true) {
            FamilyPhotos.loadOwn(app, photoID, family)
            delay(61_000)
        }
    }

    /** Saves a new name or photo: a photo is uploaded first, and JsonNull removes it. */
    fun save(change: Map<String, JsonElement>, photoData: ByteArray? = null) {
        if (saving) return
        saving = true
        scope.launch {
            try {
                val values = if (photoData != null) change + ("photo" to FamilyPhotos.upload(app, photoData, "profilePhotoUpload", emptyMap(), family, pin = null))
                    else change
                app.coordinator.update(app.service(family).send("setProfile", values))
                if ("name" in change) editedName = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Couldn't save. Check the connection and try again."
            } finally {
                saving = false
            }
        }
    }
    fun chosen(uri: Uri?) {
        if (uri == null) return
        scope.launch {
            val data = FamilyPhotos.prepared(context, uri)
            if (data == null) error = "That photo couldn't be opened. Please choose another photo."
            else save(emptyMap(), data)
        }
    }
    val library = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { chosen(it) }
    // The camera app saves its photo to a file in Porch's cache, through Porch's file provider.
    var shot by rememberSaveable { mutableStateOf<String?>(null) }
    val takePicture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
        val uri = shot?.let(Uri::parse)
        shot = null
        if (taken) chosen(uri)
    }
    fun takeShot() {
        try {
            val folder = File(context.cacheDir, "camera").apply { mkdirs() }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", File(folder, "profile.jpg"))
            shot = uri.toString()
            takePicture.launch(uri)
        } catch (_: ActivityNotFoundException) {
            error = "No app on this phone can take a photo."
        } catch (_: SecurityException) {
            error = "Allow Porch to use the camera in Settings to take a photo."
        }
    }
    // Porch declares the camera, for calls, so Android lets it open the camera app only once the camera is allowed.
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) takeShot() else error = "Allow Porch to use the camera in Settings to take a photo."
    }

    FormScreen("Your name and photo", navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        if (me == null) { Text("Connecting to your family…"); return@FormScreen }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Avatar(me.profile?.name ?: me.name, photo, 96.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column {
                    OutlinedButton(onClick = { choosing = true }, enabled = !saving) { Text(if (photo == null) "Add a photo" else "Change photo") }
                    DropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }) {
                        DropdownMenuItem(text = { Text("Take a photo") }, onClick = {
                            choosing = false
                            if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) takeShot()
                            else cameraPermission.launch(Manifest.permission.CAMERA)
                        })
                        DropdownMenuItem(text = { Text("Choose a photo") }, onClick = {
                            choosing = false
                            try { library.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                            catch (_: ActivityNotFoundException) { error = "No app on this phone can choose a photo." }
                        })
                    }
                }
                if (photo != null || me.profile?.photoID != null) OutlinedButton(onClick = { save(mapOf("photo" to JsonNull)) }, enabled = !saving) {
                    Text("Remove photo", color = MaterialTheme.colorScheme.error)
                }
            }
        }
        // A caregiver's choice is what the bedside shows, which would otherwise be a surprise.
        val chosen = me.override
        val note = when {
            chosen?.name != null && chosen.photoID != null -> "A caregiver set your name to “${chosen.name}” and chose your photo. $lovedOne sees those."
            chosen?.name != null -> "A caregiver set your name to “${chosen.name}”. $lovedOne sees that name."
            chosen?.photoID != null -> "A caregiver chose your photo. $lovedOne sees that photo."
            else -> null
        }
        val name = editedName ?: me.profile?.name.orEmpty()
        FormField(name, { editedName = it }, "Name", me.invitedName ?: me.name,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words))
        FormButton(if (saving) "Saving…" else "Save name", onClick = { save(mapOf("name" to JsonPrimitive(name.trim()))) },
            enabled = !saving && name.trim() != me.profile?.name.orEmpty())
        note?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        CaregiverGroup {
            ToggleRow("Start video calls with my camera on", camera, onChange = {
                CallPreferences.saveStartVideoWithCamera(it, app.settings)
                camera = it
            }, detail = "On this phone, in every family.")
        }
    }
    PorchErrorDialog(error) { error = null }
}
