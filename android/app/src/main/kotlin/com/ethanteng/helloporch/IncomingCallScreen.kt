package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Someone calling: their photo and name, what kind of call it is, and Answer and Decline, as on iOS. */
@Composable
fun IncomingCallScreen(app: PorchApplication, incoming: IncomingCall) = LargeType {
    KeepScreenOn()
    BackHandler { incoming.decline() }
    CallKeys(app, onDigit = { incoming.cell2jackDigit(it) }, onHangUp = { "hang-up ignored while ringing" },
        onKeyDown = incoming::keyDown, onKeyUp = incoming::keyUp)
    Column(Modifier.fillMaxSize().background(CallColors.night).safeDrawingPadding().padding(24.dp)) {
        Box(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(28.dp)) {
                Photo(incoming.photo, Modifier.widthIn(max = 520.dp).fillMaxWidth(0.6f))
                Text(incoming.name, color = CallColors.text, fontSize = 48.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                Text(incoming.status, color = CallColors.text, fontSize = 28.sp, textAlign = TextAlign.Center)
                incoming.keypadHint?.let { Text(it, color = CallColors.secondary, fontSize = 18.sp, textAlign = TextAlign.Center) }
            }
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            CallButton(incoming.answerTitle, !incoming.answering, onClick = incoming::answer, app = app, color = CallColors.answer,
                translated = true, modifier = Modifier.fillMaxWidth())
            CallButton(incoming.declineTitle, true, onClick = incoming::decline, app = app, color = CallColors.end,
                translated = true, modifier = Modifier.fillMaxWidth())
        }
    }
}
