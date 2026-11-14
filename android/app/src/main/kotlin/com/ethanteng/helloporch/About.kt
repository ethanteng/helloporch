package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import com.ethanteng.helloporch.core.LicenseText
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchNumber
import com.mikepenz.aboutlibraries.Libs
import com.mikepenz.aboutlibraries.ui.compose.android.produceLibraries

/** Where to reach the person who makes Porch, as iOS's ContactViewController has it. */
const val contactEmail = "ethan@helloporch.store"
const val contactPhone = "+14158676937"

private enum class AboutPage { CONTACT, LICENSES }

/**
 * Porch's version, who made it and how to reach him, and the open-source licenses one tap away, as iOS's About
 * (AboutViewController.swift) has them, screen for screen and word for word. The last page of caregiver mode, and About
 * Porch on a family phone. `navigation` is the bar's button back to where About was opened from. Contact, Licenses and
 * each license open in About's place, each with its own Back.
 */
@Composable
fun AboutScreen(navigation: (@Composable () -> Unit)?) {
    var page by rememberSaveable { mutableStateOf<AboutPage?>(null) }
    // The open license, by its row's title.
    var license by rememberSaveable { mutableStateOf<String?>(null) }
    // Gathered from the app's dependencies when it's built (the AboutLibraries plugin).
    val libraries by produceLibraries(R.raw.aboutlibraries)
    val licenses = remember(libraries) { libraries?.let(::aboutLicenses) }
    val shown = license?.let { title -> licenses?.firstOrNull { it.title == title } }
    when {
        shown != null -> {
            BackHandler { license = null }
            LicenseScreen(shown, onBack = { license = null })
        }
        page == AboutPage.LICENSES -> {
            BackHandler { page = null }
            LicensesScreen(licenses, onBack = { page = null }, onLicense = { license = it.title })
        }
        page == AboutPage.CONTACT -> {
            BackHandler { page = null }
            ContactScreen(onBack = { page = null })
        }
        else -> AboutHome(navigation, onContact = { page = AboutPage.CONTACT }, onLicenses = { page = AboutPage.LICENSES })
    }
}

@Composable
private fun AboutHome(navigation: (@Composable () -> Unit)?, onContact: () -> Unit, onLicenses: () -> Unit) {
    FormScreen("About", navigation = navigation) {
        Column(Modifier.fillMaxWidth().padding(top = 28.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Image(painterResource(R.drawable.about_icon), contentDescription = null, Modifier.padding(bottom = 10.dp).size(88.dp).clip(RoundedCornerShape(20.dp)))
            Text("Porch", Modifier.semantics { heading() }, fontSize = 26.sp, fontWeight = FontWeight.Medium)
            Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = MaterialTheme.typography.titleMedium, fontSize = 18.sp)
            Text("Built with ❤️ in Oakland, CA", Modifier.padding(top = 14.dp), style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            // The whole line opens Contact, as on iOS.
            val contact = buildAnnotatedString {
                append("Questions or feedback? ")
                withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)) { append("Contact me.") }
            }
            Text(contact, Modifier.clip(RoundedCornerShape(8.dp)).clickable(role = Role.Button, onClick = onContact).padding(horizontal = 4.dp, vertical = 8.dp),
                style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
        CaregiverGroup {
            CaregiverRow(onClick = onLicenses, label = "Licenses") {
                Text("Licenses", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/**
 * How to reach the person who makes Porch. On a family device the email starts one, and on a phone the number calls it,
 * with caregiver mode kept open behind them. On the bedside they're only shown, since either would leave Porch.
 */
@Composable
private fun ContactScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val app = context.applicationContext as PorchApplication
    val familyDevice = app.device.experience != PorchExperience.BEDSIDE
    val canCall = familyDevice && context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)
    FormScreen("Contact", navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        CaregiverGroup {
            ContactRow(R.drawable.ic_mail, "Email", contactEmail,
                onClick = if (familyDevice) ({ openOutside(context, Intent(Intent.ACTION_SENDTO, "mailto:$contactEmail".toUri())) }) else null)
            HorizontalDivider()
            ContactRow(R.drawable.ic_call, "Phone", PorchNumber.display(contactPhone),
                onClick = if (canCall) ({ openOutside(context, Intent(Intent.ACTION_DIAL, "tel:$contactPhone".toUri())) }) else null)
        }
    }
}

/** A row that does something, in the accent color, or the same icon and words only to read. */
@Composable
private fun ContactRow(@DrawableRes icon: Int, label: String, text: String, onClick: (() -> Unit)?) {
    CaregiverRow(onClick = onClick, label = "$label, $text") {
        Icon(painterResource(icon), contentDescription = null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
        Text(text, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium,
            color = if (onClick != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
    }
}

private fun openOutside(context: Context, intent: Intent) {
    try { staysInCaregiverMode { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
    catch (_: ActivityNotFoundException) {}
}

/** The open-source software in Porch, one row each. A tap shows its license here, never in a browser, which on a family
 * phone would end caregiver mode. Nothing shows while the list is still being read. */
@Composable
private fun LicensesScreen(licenses: List<AboutLicense>?, onBack: () -> Unit, onLicense: (AboutLicense) -> Unit) {
    FormScreen("Licenses", navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        if (licenses.isNullOrEmpty()) return@FormScreen
        CaregiverGroup {
            licenses.forEachIndexed { index, license ->
                if (index > 0) HorizontalDivider()
                CaregiverRow(onClick = { onLicense(license) }, label = license.title) {
                    Text(license.title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** One license, titled with what it's for. */
@Composable
private fun LicenseScreen(license: AboutLicense, onBack: () -> Unit) {
    FormScreen(license.title, navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        CaregiverGroup {
            Text(LicenseText.reflowed(license.text), Modifier.padding(16.dp), style = MaterialTheme.typography.bodyMedium)
        }
    }
}

/** One row of Licenses: what Porch includes, as "name version", and its license's text. */
internal data class AboutLicense(val title: String, val text: String)

/** Each library once, in alphabetical order. Some are listed twice, once for each platform they're built for, with the same
 * name and version. */
internal fun aboutLicenses(libs: Libs): List<AboutLicense> =
    libs.libraries.groupBy { listOfNotNull(it.name, it.artifactVersion?.takeIf(String::isNotBlank)).joinToString(" ") }
        .map { (title, same) -> AboutLicense(title, licenseText(same.flatMap { it.licenses }.distinctBy { it.hash })) }
        .sortedBy { it.title.lowercase() }

/** The licenses' own text. Some come without it, such as ML Kit's terms: then their names, and where to read them. */
private fun licenseText(licenses: List<com.mikepenz.aboutlibraries.entity.License>): String {
    val texts = licenses.mapNotNull { it.licenseContent?.trim()?.takeIf(String::isNotEmpty) }.distinct()
    if (texts.isNotEmpty()) return texts.joinToString("\n\n")
    return licenses.joinToString("\n\n") { listOfNotNull(it.name, it.url).joinToString("\n") }
}
