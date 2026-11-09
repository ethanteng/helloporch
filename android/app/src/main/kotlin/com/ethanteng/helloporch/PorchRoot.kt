package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ethanteng.helloporch.core.BedsideInvitation
import com.ethanteng.helloporch.core.FamilyInvitation
import com.ethanteng.helloporch.core.PorchExperience

/** Before a device is set up either way: the welcome screen, the explanation a phone gives for setting up the bedside,
 * or joining a family from the welcome screen. */
private enum class WelcomePage { WELCOME, ON_TABLET, JOINING }

/**
 * Which screens Porch shows, as `PorchContainerViewController` picks them on iOS: the welcome screen on a device that
 * isn't set up either way, then family mode's or the bedside's. Links that open Porch come here first. `cordedPhoneSetup`
 * is setup's screen for connecting the corded phone.
 */
@Composable
fun PorchRoot(
    app: PorchApplication,
    link: String?,
    onLinkHandled: () -> Unit,
    cordedPhoneSetup: CordedPhoneStep = { onDone, onBack -> CordedPhoneLater(onDone, onBack) },
) {
    val setup: BedsideSetup = viewModel()
    val links by app.coordinator.links.collectAsStateWithLifecycle()
    // Read again when a pairing comes or goes, or the mode changes.
    val credentials = links.links.map { it.credential }
    val modes = app.modeChanges
    val experience = remember(credentials, modes) { app.device.rememberExperience(); app.device.experience }
    val welcoming = remember(credentials, modes, setup.open) { app.device.needsWelcome }
    var page by rememberSaveable { mutableStateOf(WelcomePage.WELCOME) }
    var notice by rememberSaveable { mutableStateOf<String?>(null) }
    /** A setup link opened on a tablet that's already a bedside, waiting for the caregiver to say to replace it. */
    var replacement by rememberSaveable { mutableStateOf<String?>(null) }
    var familyReady by remember { mutableStateOf(false) }

    val defaultOrigin = app.device.defaultOrigin
    val setupLink = link != null && runCatching { BedsideInvitation(link, defaultOrigin) }.isSuccess
    val familyLink = link != null && !setupLink && runCatching { FamilyInvitation(link, defaultOrigin) }.isSuccess
    val calls = app.calls
    val busy = setup.open || setup.unlocking || setup.caregiver || replacement != null || calls.busy

    fun setUpBedside(url: String, replacing: Boolean) {
        app.device.saveActivation(url)
        // The welcome screen is neither mode, so leaving it always switches.
        if (welcoming || experience != PorchExperience.BEDSIDE) app.switchExperience(PorchExperience.BEDSIDE)
        setup.start(replacing)
    }

    LaunchedEffect(link) {
        if (link == null) return@LaunchedEffect
        when {
            // Something is on screen, such as setup. Say so rather than drop the link.
            (setupLink || familyLink) && busy -> notice = "Finish what's open in Porch, then tap the invitation link again."
            setupLink && !app.device.canBeBedside ->
                // A phone that isn't set up yet explains as Set up does; one that's in a family is told where to open it.
                if (welcoming) page = WelcomePage.ON_TABLET
                else notice = "This setup link is for the tablet that stays with your loved one. Open it on that tablet."
            setupLink && app.device.credential(PorchExperience.BEDSIDE) != null -> replacement = link
            setupLink -> setUpBedside(link, replacing = false)
            // Joined below, with phase 1's screens, which say when it's handled.
            familyLink -> return@LaunchedEffect
        }
        onLinkHandled()
    }

    // A family invitation opens the join screen whatever mode this is. Only a join that lands switches to family mode.
    val joining = familyLink && !busy
    val family = joining || (welcoming && page == WelcomePage.JOINING) || (!welcoming && experience == PorchExperience.FAMILY)
    BackHandler(enabled = joining && (welcoming || experience != PorchExperience.FAMILY)) { onLinkHandled() }
    BackHandler(enabled = !joining && welcoming && page != WelcomePage.WELCOME) { page = WelcomePage.WELCOME }

    // The bedside is always on, over the lock screen, and Porch is its home screen. Setup and caregiver screens keep the
    // system bars; the clock and calls hide them.
    val bedside = !welcoming && experience == PorchExperience.BEDSIDE
    val paired = links.credential != null || app.device.credential(PorchExperience.BEDSIDE) != null
    // A family phone's call shows over the lock screen too, while it rings or goes on.
    BedsideWindow(alwaysOn = bedside, immersive = bedside && !setup.open && !setup.unlocking && !setup.caregiver && replacement == null,
        overLock = bedside || calls.incoming != null || calls.active != null || calls.openedForCall)
    val context = LocalContext.current
    LaunchedEffect(bedside, paired) { BedsideHomeScreen.sync(context, bedside && paired) }
    val active = calls.active
    val incoming = calls.incoming
    // A call takes over from messages playing, and isn't Stop.
    val callShowing = active != null || incoming != null
    // A call also closes a message being recorded, which sends what was said.
    LaunchedEffect(callShowing) { if (callShowing) { app.messages.interrupt(); calls.voicemail?.interrupt {} } }
    val playback = app.messages.playback
    val voicemail = calls.voicemail
    when {
        // A call takes over from whatever is showing, as on iOS.
        active != null -> CallScreen(app, active)
        incoming != null -> IncomingCallScreen(app, incoming)
        bedside && voicemail != null -> BedsideVoicemailScreen(app, voicemail)
        bedside && playback != null -> MessagePlayerScreen(app, playback)
        family -> PorchTheme { FamilyScreens(app, if (joining) link else null, onLinkHandled, onReady = { familyReady = it }) }
        welcoming && page == WelcomePage.ON_TABLET -> BedsideOnTablet(onJoin = { page = WelcomePage.JOINING }, onBack = { page = WelcomePage.WELCOME })
        welcoming -> Welcome(
            onSetUp = {
                if (app.device.canBeBedside) { app.switchExperience(PorchExperience.BEDSIDE); setup.start() } else page = WelcomePage.ON_TABLET
            },
            onJoin = { page = WelcomePage.JOINING })
        setup.open -> BedsideSetupFlow(app, setup, cordedPhoneSetup)
        setup.unlocking -> CaregiverGate(setup)
        setup.caregiver -> CaregiverMode(app, links, onClose = setup::closeCaregiver)
        // The dialogs below cover the clock, so its presence camera stops while one shows.
        else -> BedsideHome(app, links, setup, covered = notice != null || calls.error != null || replacement != null)
    }
    // Only the bedside's home and a family phone's list of families, or its caregiver mode, can take a call, with nothing
    // open over them.
    val ready = notice == null && !calls.busy && if (family) familyReady && !joining else !welcoming && !busy
    SideEffect { app.screenReady = ready }

    replacement?.let { url -> ReplaceBedside(app, onReplace = { replacement = null; setUpBedside(url, replacing = true) }, onCancel = { replacement = null }) }
    PorchErrorDialog(notice) { notice = null }
    if (active == null && incoming == null) PorchErrorDialog(calls.error) { calls.error = null }
}

/** The first screen on a device that isn't set up either way: setting Porch up for someone, or joining a family. */
@Composable
private fun Welcome(onSetUp: () -> Unit, onJoin: () -> Unit) {
    FormScreen("Porch") {
        FormSection("Welcome to Porch", "Set up Porch on the tablet that stays with your loved one, or join your family's Porch from your phone.") {
            FormButton("Set up Porch for someone", onClick = onSetUp)
            FormButton("I'm joining my family", onClick = onJoin, filled = false)
        }
        PrivacyPolicyLink()
    }
}

/** On a phone: the bedside runs on the tablet that stays with them, so that's where setup happens. */
@Composable
private fun BedsideOnTablet(onJoin: () -> Unit, onBack: () -> Unit) {
    FormScreen("Set up Porch", navigation = { TextButton(onClick = onBack) { Text("Back") } }) {
        FormSection("Set up Porch on their tablet",
            "Porch runs on the tablet that stays with your loved one. Open your setup link on that tablet: it opens Porch there, or shows how to get it. Once it's set up, you can add your phone from the tablet.") {
            FormButton("I'm joining my family", onClick = onJoin, filled = false)
        }
    }
}

/** A setup link on a tablet that's already a bedside, such as one handed on to someone else, sets up a new Porch in place
 * of this one once it's confirmed. Nothing changes until the new Porch's PIN step: cancelling setup before then keeps
 * this one as it is. */
@Composable
private fun ReplaceBedside(app: PorchApplication, onReplace: () -> Unit, onCancel: () -> Unit) {
    // Until Porch has checked in since it opened, it doesn't have their name.
    val name = app.coordinator.state?.takeIf { it.me.role == PorchExperience.BEDSIDE }?.householdName
    val keypad = name?.let { "$it's" } ?: "This tablet's"
    val family = name?.let { "$it's family" } ?: "its family"
    val number = name?.let { "$it's Porch number" } ?: "This tablet's Porch number"
    AlertDialog(onDismissRequest = onCancel,
        title = { Text("Replace ${name?.let { "$it's Porch" } ?: "this tablet's Porch"}?") },
        text = { Text("This tablet will be set up as a new Porch. $keypad keypad, messages and settings are removed from it, and it stops ringing for $family. $number and family stay. Nothing changes until you choose the new Porch's PIN.") },
        confirmButton = { TextButton(onClick = onReplace) { Text("Replace") } },
        dismissButton = { TextButton(onClick = onCancel) { Text("Cancel") } })
}
