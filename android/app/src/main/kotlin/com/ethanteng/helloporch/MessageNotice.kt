package com.ethanteng.helloporch

import android.animation.ValueAnimator
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect

/**
 * "You have N new messages", shown over the clock and said aloud when someone settles in front of the tablet with
 * messages waiting, as iOS's MessageNoticeView is. Once it's said, the messages play. Not now, or any key, puts them off
 * for 30 minutes ([BedsideMessages.declineNotice]). Main thread only.
 */
class MessageNotice(app: PorchApplication, count: Int) {
    val text = text(app, count)
    private val announcer = Announcer(app)
    private var ended = false

    /** The chime, then the sentence, in the household's natural voice if it's here within 3 seconds, as on iOS, or
     * text-to-speech. Then `onFinished`, unless it ended first. */
    fun begin(onFinished: () -> Unit) {
        announcer.speak(text, naturalWait = 3_000) { if (!ended) { end(); onFinished() } }
    }

    /** Stops it without starting anything. */
    fun end() {
        if (ended) return
        ended = true
        announcer.stop()
    }

    companion object {
        /** What the bedside says when messages are waiting. */
        fun text(app: PorchApplication, count: Int) =
            if (count == 1) BedsideText.string(app, "You have 1 new message.") else BedsideText.string(app, "You have %d new messages.", count)

        private val warm = Color(1f, 0.74f, 0.32f)
    }

    /** The notice over the clock, while there is one: the screen dimmed, a warm border pulsing around it, and the sentence
     * with Not now. Touches elsewhere go nowhere. Porch leaving the front, or the clock going, ends it. */
    @Composable
    fun Overlay(app: PorchApplication) {
        val pulse = if (ValueAnimator.areAnimatorsEnabled()) {
            rememberInfiniteTransition(label = "notice").animateFloat(1f, 0.3f,
                infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "glow").value
        } else 1f
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).pointerInput(Unit) { detectTapGestures {} }
            .drawBehind {
                // A 16 dp border, and a glow inside it that fades out over 36 dp, as iOS's shadow does.
                val border = 16.dp.toPx()
                val glow = 36.dp.toPx()
                val steps = 12
                for (step in steps downTo 1) {
                    val inset = border + glow * step / steps
                    drawRect(warm.copy(alpha = pulse * 0.35f * (1f - step.toFloat() / (steps + 1))), topLeft = Offset(inset / 2, inset / 2),
                        size = Size(size.width - inset, size.height - inset), style = Stroke(glow / steps * 2))
                }
                drawRect(warm.copy(alpha = pulse), topLeft = Offset(border / 2, border / 2), size = Size(size.width - border, size.height - border),
                    style = Stroke(border))
            },
            contentAlignment = Alignment.Center) {
            // Opaque, where iOS's card lets a little through: here the clock's large digits sit right behind the words.
            Column(Modifier.safeDrawingPadding().padding(32.dp)
                .background(PorchColors.night, RoundedCornerShape(32.dp))
                .padding(horizontal = 48.dp, vertical = 40.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(28.dp)) {
                Text("✉︎", Modifier.clearAndSetSemantics {}, color = warm, fontSize = 72.sp)
                Text(text, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, color = PorchColors.nightText, fontSize = 44.sp,
                    fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, lineHeight = 52.sp)
                Button(onClick = app.messages::declineNotice, modifier = Modifier.heightIn(min = 88.dp), shape = RoundedCornerShape(24.dp),
                    contentPadding = PaddingValues(horizontal = 40.dp, vertical = 20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0.32f, 0.32f, 0.32f), contentColor = Color.White)) {
                    Text("✕", Modifier.padding(end = 16.dp).clearAndSetSemantics {}, fontSize = 28.sp)
                    Text(BedsideText.string(app, "Not now"), fontSize = 32.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

/** The clock's messages notice, while there is one. Porch leaving the front, or the clock going, ends it without putting
 * anything off, as iOS's clock does. Turning the tablet, or plugging the keypad in, recreates the activity and is still
 * the same clock, so the notice goes on, as messages playing do. */
@Composable
fun ClockMessageNotice(app: PorchApplication, covered: Boolean) {
    val messages = app.messages
    val activity = LocalActivity.current
    LifecycleResumeEffect(messages) { onPauseOrDispose { if (activity?.isChangingConfigurations != true) messages.endNotice() } }
    // Something over the clock, such as an error, ends it too.
    LaunchedEffect(covered) { if (covered) messages.endNotice() }
    messages.notice?.Overlay(app)
}
