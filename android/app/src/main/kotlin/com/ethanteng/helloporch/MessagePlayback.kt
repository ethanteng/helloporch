package com.ethanteng.helloporch

import androidx.activity.compose.LocalActivity
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame

/** A message to play: a short-lived link from the server, or a recording's file, with what it's called. */
class MessageMedia(val uri: String, val title: String, val video: Boolean)

/**
 * A message played here: a waiting one for a caregiver, one in a family phone's thread, or a recording before it's sent,
 * as iOS plays them in its own player. Closing it, or leaving the app, stops it.
 */
@OptIn(UnstableApi::class)
@Composable
internal fun MessagePlayerDialog(preview: MessageMedia, onClose: () -> Unit) {
    val context = LocalContext.current
    val activity = LocalActivity.current
    var ended by remember(preview) { mutableStateOf(false) }
    var failed by remember(preview) { mutableStateOf(false) }
    // The video's own shape: a phone records upright, the tablet sideways.
    var aspect by remember(preview) { mutableFloatStateOf(4f / 3f) }
    val player = remember(preview) {
        ExoPlayer.Builder(context).build().apply {
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) { ended = playbackState == Player.STATE_ENDED }
                override fun onPlayerError(error: PlaybackException) { failed = true }
                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.width <= 0 || videoSize.height <= 0) return
                    val width = videoSize.width * videoSize.pixelWidthHeightRatio
                    val height = videoSize.height.toFloat()
                    aspect = if (videoSize.unappliedRotationDegrees % 180 == 90) height / width else width / height
                }
            })
            setMediaItem(MediaItem.fromUri(preview.uri))
            prepare()
            play()
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    // Leaving the app closes it. Pausing instead left the dialog saying "Playing…" with no sound when Porch came back.
    // Turning the tablet recreates the activity, which is still this screen, so that isn't leaving.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        if (activity?.isChangingConfigurations != true) onClose() else player.pause()
    }
    AlertDialog(onDismissRequest = onClose,
        title = { Text(preview.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (preview.video && !failed) ContentFrame(player, Modifier.heightIn(max = 480.dp).fillMaxWidth().aspectRatio(aspect.coerceIn(0.5f, 2f)))
                Text(when {
                    failed -> "Couldn't play this message. Try again."
                    ended -> "That's the whole message."
                    else -> "Playing…"
                }, style = MaterialTheme.typography.bodyLarge)
            }
        },
        dismissButton = if (ended && !failed) ({ TextButton(onClick = { player.seekTo(0); player.play() }) { Text("Play again") } }) else null,
        confirmButton = { TextButton(onClick = onClose) { Text("Done") } })
}
