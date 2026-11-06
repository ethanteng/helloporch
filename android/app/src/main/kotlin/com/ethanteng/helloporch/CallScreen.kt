package com.ethanteng.helloporch

import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTrigger
import com.ethanteng.helloporch.core.Cell2JackDigitEvent
import com.ethanteng.helloporch.core.PorchExperience
import io.livekit.android.renderer.TextureViewRenderer
import io.livekit.android.room.Room
import io.livekit.android.room.track.VideoTrack
import livekit.org.webrtc.RendererCommon

/** The night colors calls use on iOS (PorchStyle), so faces stand out. */
internal object CallColors {
    val night = PorchColors.night
    val text = PorchColors.nightText
    val secondary = PorchColors.nightSecondary
    val control = PorchColors.nightSurface
    val end = Color(0.68f, 0.19f, 0.19f)
    val answer = Color(0xFF2E7D32)
}

/**
 * A call's screen: the other people's video, this device's camera in a corner, and Mute, Camera and End call, as iOS's
 * CallScreenLayout lays them out. The screen stays on for the whole call.
 */
@Composable
fun CallScreen(app: PorchApplication, call: PorchCall) = LargeType {
    KeepScreenOn()
    BackHandler { call.endCall() }
    CallKeys(app, onDigit = call::keypadDigit, onHangUp = { call.endCall(); "call end requested" })
    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        // Backing out of the dialog answers with no results. `all` on that empty map is true, which would count as allowed.
        call.permissionsAnswered(results.isNotEmpty() && results.values.all { it })
    }
    val context = LocalContext.current
    val request = call.permissionRequest
    LaunchedEffect(request) {
        if (request == null) return@LaunchedEffect
        if (request.all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }) call.permissionsAnswered(true)
        else permissions.launch(request.toTypedArray())
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(CallColors.night)) {
        val wide = maxWidth > maxHeight
        // About 30% of the short side, at most 200 dp, 4:3 and turned with the screen.
        val selfWidth = selfViewWidth(maxWidth, maxHeight, wide)
        // The other people's video fills the screen. Two share it: side by side when it's wide, stacked when it's tall.
        if (call.video && !call.showingPlaceholder) {
            val tiles = call.tiles
            if (tiles.size == 1) VideoTile(call.room, tiles[0], Modifier.fillMaxSize())
            else if (wide) Row(Modifier.fillMaxSize()) { tiles.forEach { VideoTile(call.room, it, Modifier.weight(1f).fillMaxSize()) } }
            else Column(Modifier.fillMaxSize()) { tiles.forEach { VideoTile(call.room, it, Modifier.weight(1f).fillMaxSize()) } }
        }
        // Shade behind the name and the buttons, so they read over bright video.
        if (call.video && !call.showingPlaceholder) {
            Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().fillMaxHeight(0.3f)
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.65f), Color.Transparent))))
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().fillMaxHeight(0.25f)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f)))))
        }
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            // The name and status stay clear of the self view.
            Column(Modifier.fillMaxWidth().padding(end = if (call.localTrack != null) selfWidth + 16.dp else 0.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(call.name, color = CallColors.text, fontSize = 40.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                Text(call.status, color = CallColors.text, fontSize = 17.sp, textAlign = TextAlign.Center)
                call.keypadHint?.let { Text(it, color = CallColors.secondary, fontSize = 16.sp, textAlign = TextAlign.Center) }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (call.showingPlaceholder) Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Photo(call.photo, Modifier.widthIn(max = 280.dp).fillMaxWidth(0.5f))
                    Text(call.placeholder, color = Color.White, fontSize = 28.sp, textAlign = TextAlign.Center)
                }
            }
            // As wide as the screen allows, up to a comfortable width on a tablet, with each button an equal share.
            Row(Modifier.widthIn(max = 720.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                val each = Modifier.weight(1f)
                CallButton(if (call.microphoneOn) "Mute" else "Unmute", call.controlsEnabled, onClick = call::toggleMicrophone, app = app, modifier = each)
                if (call.video) CallButton(if (call.cameraOn) "Camera off" else "Camera on", call.controlsEnabled, onClick = call::toggleCamera, app = app, modifier = each)
                CallButton(call.endTitle, call.endEnabled, onClick = call::endCall, color = CallColors.end, translated = true, app = app, modifier = each)
            }
        }
        call.localTrack?.let { track ->
            VideoTrackView(call.room, track, Modifier.align(Alignment.TopEnd).safeDrawingPadding().padding(16.dp).width(selfWidth)
                .aspectRatio(if (wide) 4f / 3f else 3f / 4f).clip(RoundedCornerShape(12.dp)), mirror = true)
        }
    }
}

private fun selfViewWidth(width: Dp, height: Dp, wide: Boolean): Dp {
    val side = min(min(width, height) * 0.3f, 200.dp)
    // The short side of the 4:3 view is `side`.
    return if (wide) side * 4f / 3f else side
}

@Composable
private fun VideoTile(room: Room, tile: PorchCall.Tile, modifier: Modifier) {
    Box(modifier.background(CallColors.night), contentAlignment = Alignment.BottomStart) {
        if (tile.track != null) VideoTrackView(room, tile.track, Modifier.fillMaxSize())
        else Text(tile.name, Modifier.align(Alignment.Center), color = CallColors.text, fontSize = 28.sp)
    }
}

/** A LiveKit video track, drawn into a TextureView. The track changes in place as people turn cameras off and on. */
@Composable
fun VideoTrackView(room: Room, track: VideoTrack?, modifier: Modifier, mirror: Boolean = false) {
    val attached = remember { arrayOfNulls<VideoTrack>(1) }
    AndroidView(
        factory = { context ->
            TextureViewRenderer(context).apply {
                room.initVideoRenderer(this)
                setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
            }
        },
        modifier = modifier,
        update = { renderer ->
            renderer.setMirror(mirror)
            if (attached[0] !== track) {
                attached[0]?.removeRenderer(renderer)
                track?.addRenderer(renderer)
                attached[0] = track
            }
        },
        onRelease = { renderer ->
            attached[0]?.removeRenderer(renderer)
            attached[0] = null
            renderer.release()
        },
    )
}

@Composable
internal fun CallButton(title: String, enabled: Boolean, onClick: () -> Unit, app: PorchApplication, modifier: Modifier = Modifier,
    color: Color = CallColors.control, translated: Boolean = false) {
    // Three buttons share a phone's width, so the words get the room a button's usual padding would take.
    val narrow = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.width.toDp() } < 600.dp
    Button(onClick = onClick, enabled = enabled, modifier = modifier.heightIn(min = 64.dp),
        contentPadding = PaddingValues(horizontal = if (narrow) 8.dp else 16.dp, vertical = 8.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = CallColors.text,
            disabledContainerColor = color.copy(alpha = 0.4f), disabledContentColor = CallColors.text.copy(alpha = 0.6f))) {
        Text(if (translated) title else BedsideText.string(app, title), fontSize = if (narrow) 16.sp else 20.sp, maxLines = 1,
            softWrap = false, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
internal fun Photo(data: ByteArray?, modifier: Modifier) {
    val bitmap = remember(data) { data?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() } } ?: return
    Image(bitmap.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop,
        modifier = modifier.aspectRatio(1f).clip(RoundedCornerShape(24.dp)))
}

/** Large type on the bedside and call screens. Material's text styles fix the line height for small type, so big
 * words that wrap would overlap; here each line is as tall as its font. */
@Composable
internal fun LargeType(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalTextStyle provides LocalTextStyle.current.copy(lineHeight = TextUnit.Unspecified), content = content)
}

/** The screen stays on while it's showing, as iOS keeps it on during calls. */
@Composable
internal fun KeepScreenOn() {
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
}

/**
 * Keypad keys for the screen showing: a USB keypad or keyboard, and on the bedside the Cell2Jack phone. Each press acts
 * once, however long it's held. Auto-repeat and keys with Ctrl, Alt or Meta are ignored, as on iOS.
 */
@Composable
internal fun CallKeys(app: PorchApplication, onDigit: (Int) -> Unit, onHangUp: () -> String,
    onKeyDown: ((Int, Int) -> Boolean)? = null, onKeyUp: ((Int, Int) -> Boolean)? = null) {
    val keys = LocalKeyListener.current
    val trigger = remember { CallTrigger() }
    DisposableEffect(keys) {
        keys.onKey = handler@{ event ->
            val digit = keypadSlot(event) ?: return@handler false
            when (event.action) {
                KeyEvent.ACTION_DOWN -> {
                    if (onKeyDown != null) return@handler event.repeatCount != 0 || onKeyDown(digit, event.keyCode)
                    if (event.repeatCount == 0 && trigger.keyDown(event.keyCode)) onDigit(digit)
                    true
                }
                KeyEvent.ACTION_UP -> {
                    trigger.keyUp(event.keyCode)
                    onKeyUp?.invoke(digit, event.keyCode) ?: true
                }
                else -> true
            }
        }
        onDispose { keys.onKey = null; trigger.resetKeys() }
    }
    if (app.device.experience == PorchExperience.BEDSIDE) LaunchedEffect(Unit) {
        app.cell2jack.events.collect { event ->
            when (event.kind) {
                Cell2JackDigitEvent.Kind.DIGIT -> CallSlots.digit(event.digit)?.let(onDigit)
                Cell2JackDigitEvent.Kind.HANG_UP -> app.cell2jack.record("hangUpRouted", "outcome" to onHangUp())
                else -> {}
            }
        }
    }
}
