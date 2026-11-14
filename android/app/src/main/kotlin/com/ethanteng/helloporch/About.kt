package com.ethanteng.helloporch

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.mikepenz.aboutlibraries.ui.compose.android.produceLibraries
import com.mikepenz.aboutlibraries.ui.compose.m3.LibrariesContainer
import com.mikepenz.aboutlibraries.ui.compose.style.LibraryActionBadges
import com.mikepenz.aboutlibraries.ui.compose.variant.LibraryDetailMode

/**
 * Porch's version, and the open-source software in it with each license, as iOS lists them in Settings
 * (Settings.bundle's Acknowledgements). The list is gathered from the app's dependencies when it's built.
 */
@Composable
fun AboutScreen(navigation: (@Composable () -> Unit)?) {
    val libraries by produceLibraries(R.raw.aboutlibraries)
    FormScreen("About", navigation = navigation, scrolls = false) {
        Text("Porch ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.titleLarge)
        Text("Tap one to read its license.",
            style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        // A tap shows the license here, in a dialog. Links to a library's source, website or license page would leave for a
        // browser, which on a family phone also ends caregiver mode.
        LibrariesContainer(libraries, Modifier.fillMaxWidth().weight(1f), detailMode = LibraryDetailMode.Dialog,
            actionLabels = LibraryActionBadges(sourceEnabled = false, websiteEnabled = false, sponsorEnabled = false, licenseEnabled = false))
    }
}
