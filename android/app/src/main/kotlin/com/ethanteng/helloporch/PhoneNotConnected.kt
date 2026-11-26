package com.ethanteng.helloporch

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.ethanteng.helloporch.core.BedsidePhone
import java.time.Instant
import java.time.ZoneId

/** The honey of a desk phone that isn't connected, as iOS's: its banner and status row, the icon and words on it, and the
 * steps' numbers; and the green of one that's back. */
internal object PhoneNoticeColors {
    val tint = Color(0xFFFAEBC9)
    val icon = Color(0xFF8A5300)
    val title = Color(0xFF6B4200)
    val meta = Color(0xFF6B4F2A)
    val dot = Color(0xFFC98A1B)
    val number = PorchBrand.honey
    val backTint = Color(0xFFDCEFE3)
    val backDot = PorchBrand.go
    val backText = Color(0xFF1E5A3C)
}

/** When the phone went out, by this phone's clock: "2:14 PM" today, otherwise with the day. */
private fun BedsidePhone.time(): String = time(Instant.now(), ZoneId.systemDefault())

/** Caregivers: the bedside's desk phone has been out a while. A honey strip on the bedside's card, laid out as Every
 * call's, with since when. The whole strip opens [ReconnectPhoneSheet], so a chevron ends it rather than a button that
 * would squeeze its title at phone width. `name` is the bedside's. */
@Composable
internal fun PhoneNotConnectedBanner(phone: BedsidePhone, name: String, onWhatToCheck: () -> Unit) {
    val time = phone.time()
    CaregiverNotice(R.drawable.ic_phone_disabled, PhoneNoticeColors.icon, "Phone not connected", PhoneNoticeColors.title,
        BedsidePhone.since(time), PhoneNoticeColors.meta, PhoneNoticeColors.tint,
        Modifier.clickable(onClick = onWhatToCheck)
            .clearAndSetSemantics {
                contentDescription = BedsidePhone.notConnectedDescription(name, time)
                role = Role.Button
                onClick(label = "Show what to check") { onWhatToCheck(); true }
            }
            .testTag("call.phone.banner")) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
            Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, Modifier.size(24.dp), tint = PhoneNoticeColors.title)
        }
    }
}

/**
 * What to check at the bedside to reconnect its phone, plug by plug, for how it's plugged in there, with the setup guide
 * and a way to send the steps to whoever is there. Its status follows check-ins: once the phone is back (`connected`), it
 * says so in green. `name` is the bedside's, and `bedsideDevice` "tablet" or "iPad".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReconnectPhoneSheet(phone: BedsidePhone, connected: Boolean, name: String, bedsideDevice: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = PorchBrand.paper, contentColor = PorchBrand.ink,
        modifier = Modifier.testTag("call.phone.sheet")) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).navigationBarsPadding()
            .padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(BedsidePhone.reconnect(name), Modifier.semantics { heading() }, style = porchTitleStyle())
            PhoneStatus(phone, connected)
            Text(BedsidePhone.checkEachPlug(name, bedsideDevice), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                phone.steps(bedsideDevice).forEachIndexed { index, step -> Step(index + 1, step) }
            }
            // The steps, the parts and the tips are on the website, as in setup.
            TextButton(onClick = { open(context, Intent(Intent.ACTION_VIEW, phone.guideURL(bedsideDevice).toUri())) },
                Modifier.align(Alignment.CenterHorizontally).testTag("call.phone.guide")) {
                Text("Step-by-step instructions")
                Spacer(Modifier.width(6.dp))
                Icon(painterResource(R.drawable.ic_north_east), contentDescription = null, Modifier.size(16.dp))
            }
            FormButton("Share these steps", onClick = {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, phone.shareText(name, bedsideDevice))
                open(context, Intent.createChooser(send, null))
            }, Modifier.testTag("call.phone.share"))
        }
    }
}

/** Not connected since when, in honey, or Connected, in green, once a check-in says it's back. */
@Composable
private fun PhoneStatus(phone: BedsidePhone, connected: Boolean) {
    Surface(Modifier.fillMaxWidth().testTag("call.phone.status"), shape = RoundedCornerShape(12.dp),
        color = if (connected) PhoneNoticeColors.backTint else PhoneNoticeColors.tint) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(if (connected) PhoneNoticeColors.backDot else PhoneNoticeColors.dot))
            Text(if (connected) "Connected" else BedsidePhone.notConnected(phone.time()), style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold, color = if (connected) PhoneNoticeColors.backText else PhoneNoticeColors.title)
        }
    }
}

/** One plug to check, its number in a honey circle. */
@Composable
private fun Step(number: Int, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(PhoneNoticeColors.number), contentAlignment = Alignment.Center) {
            Text("$number", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = PhoneNoticeColors.title)
        }
        Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
    }
}

private fun open(context: Context, intent: Intent) {
    try { context.startActivity(intent) } catch (_: ActivityNotFoundException) {}
}
