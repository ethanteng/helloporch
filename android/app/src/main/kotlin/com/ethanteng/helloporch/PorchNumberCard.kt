package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.provider.ContactsContract
import android.widget.Toast
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.core.content.FileProvider
import com.ethanteng.helloporch.core.PorchContactCard
import com.ethanteng.helloporch.core.PorchNumber
import java.io.File
import java.util.UUID

/** Anyone can call the bedside on its own number, from any phone, so a family phone offers to save it and share it, on a
 * card of its own as on iOS. `name` is who the Porch is for. */
@Composable
fun PorchNumberCard(name: String, number: String) {
    val context = LocalContext.current
    FormCard("$name's Porch number") {
        Text(PorchNumber.display(number), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        FormPlainButton("Add to Contacts", onClick = { addToContacts(context, name, number) }, icon = R.drawable.ic_person_add)
        FormPlainButton("Share this number", onClick = { shareNumber(context, name, number) }, icon = R.drawable.ic_share)
    }
}

/** A new contact for the Porch number, which they can change before saving. Porch never reads Contacts. */
private fun addToContacts(context: Context, name: String, number: String) {
    val intent = Intent(ContactsContract.Intents.Insert.ACTION).setType(ContactsContract.RawContacts.CONTENT_TYPE)
        .putExtra(ContactsContract.Intents.Insert.NAME, PorchContactCard.contactName(name))
        .putExtra(ContactsContract.Intents.Insert.PHONE, number)
        .putExtra(ContactsContract.Intents.Insert.PHONE_TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MAIN)
    try { context.startActivity(intent) }
    catch (_: ActivityNotFoundException) { Toast.makeText(context, "This phone has no Contacts app to save it in.", Toast.LENGTH_LONG).show() }
}

/** A text with the Porch number, through whichever app they choose, with a contact card so it saves in one tap. The
 * text carries the number too, so a card that can't be made is left out. */
private fun shareNumber(context: Context, name: String, number: String) {
    val note = PorchContactCard.note(name, number)
    val send = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_TEXT, note)
    val uri = try {
        val shared = File(context.cacheDir, "shared")
        // Each share gets its own folder. Two families can both be "Mom", and a messaging app may read its attachment
        // only when the text is sent, so a later share must not replace an earlier one's card. A day is plenty.
        shared.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86_400_000 }?.forEach { it.deleteRecursively() }
        val folder = File(shared, UUID.randomUUID().toString()).apply { mkdirs() }
        val card = File(folder, PorchContactCard.fileName(name)).apply { writeText(PorchContactCard.vCard(name, number)) }
        // Handing the file to another app can fail on its own. The text below still carries the number.
        FileProvider.getUriForFile(context, "${context.packageName}.files", card)
    } catch (_: Exception) { null }
    if (uri != null) {
        send.setType("text/x-vcard").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri(null, uri)
    } else send.setType("text/plain")
    try { context.startActivity(Intent.createChooser(send, "Share this number")) }
    catch (_: ActivityNotFoundException) { Toast.makeText(context, "This phone has no app to share it with.", Toast.LENGTH_LONG).show() }
}
