package com.ethanteng.helloporch

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.icu.text.DateFormat as IcuDateFormat
import android.text.format.DateFormat
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.BedsideScene
import java.util.Date
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlinx.coroutines.delay

/** iOS's PorchStyle colors for the bedside. */
internal object PorchColors {
    val night = Color(0.035f, 0.055f, 0.05f)
    val nightSurface = Color(0.085f, 0.12f, 0.105f)
    val nightText = Color(0.78f, 0.83f, 0.79f)
    val nightSecondary = Color(0.56f, 0.64f, 0.59f)
    val ink = Color(0.12f, 0.19f, 0.17f)
}

/**
 * The time now, in milliseconds, as state that changes on each minute, and at once when the clock, the time zone or
 * the language changes.
 */
@Composable
internal fun rememberMinute(): Long {
    val context = LocalContext.current
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(60_000 - now % 60_000)
        }
    }
    DisposableEffect(context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) { now = System.currentTimeMillis() }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_LOCALE_CHANGED)
            addAction(Intent.ACTION_DATE_CHANGED)
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        onDispose { context.unregisterReceiver(receiver) }
    }
    return now
}

/** The clock's words in the bedside's language, as iOS formats them: the short time (12 or 24 hours as the tablet is set),
 * the weekday, and the date with the month spelled out. */
internal class ClockText(context: Context, language: BedsideLanguage, now: Long) {
    private val locale = language.locale
    private val moment = Date(now)
    val weekday: String = IcuDateFormat.getInstanceForSkeleton("EEEE", locale).format(moment)
    val date: String = IcuDateFormat.getInstanceForSkeleton("MMMMdyyyy", locale).format(moment)
    /** The time with no-break spaces made plain, so AM or PM can wrap below it on a narrow screen. */
    val time: String = IcuDateFormat.getInstanceForSkeleton(if (DateFormat.is24HourFormat(context)) "Hm" else "hm", locale).format(moment)
        .replace(' ', ' ').replace(' ', ' ')

    /** AM, PM or a Chinese day period such as 下午 at a quarter of the clock's size, as on iOS, whatever size the clock
     * shrinks to. */
    val styledTime: AnnotatedString = buildAnnotatedString {
        append(time)
        Regex("[\\p{L}\\p{M}]+").findAll(time).forEach { addStyle(SpanStyle(fontSize = 0.25.em), it.range.first, it.range.last + 1) }
    }
}

/**
 * The colors of the dynamic clock for one moment, as iOS's BedsideScenePalette: a bright daytime palette and a quiet
 * nighttime one, following the caregiver's schedule. The sky's keyframes meet at dawn and dusk without a jump.
 */
internal class ScenePalette(scene: BedsideScene) {
    val skyTop: Color
    val skyBottom: Color
    val foreground: Color = if (scene.isDay) PorchColors.ink else PorchColors.nightText
    val clockWash: Color = if (scene.isDay) Color(1f, 0.99f, 0.95f, 0.66f) else Color(0f, 0f, 0f, 0.80f)
    val controlBackground: Color = if (scene.isDay) Color(0.97f, 0.98f, 0.94f) else PorchColors.nightSurface
    val controlForeground: Color = if (scene.isDay) PorchColors.ink else PorchColors.nightText
    val illumination: Double = if (scene.isDay) 0.4 + 0.6 * sin(PI * scene.progress)
        else 0.4 * (1 - min(1.0, min(scene.progress, 1 - scene.progress) / 0.16))

    init {
        val dawnTop = Color(0.86f, 0.69f, 0.70f); val dawnBottom = Color(1f, 0.82f, 0.65f)
        val duskTop = Color(0.86f, 0.61f, 0.59f); val duskBottom = Color(0.99f, 0.72f, 0.49f)
        if (scene.isDay) {
            skyTop = ramp(listOf(0.0 to dawnTop, 0.18 to Color(0.64f, 0.81f, 0.94f), 0.5 to Color(0.35f, 0.68f, 0.91f), 0.8 to Color(0.67f, 0.77f, 0.91f), 1.0 to duskTop), scene.progress)
            skyBottom = ramp(listOf(0.0 to dawnBottom, 0.18 to Color(0.94f, 0.95f, 0.87f), 0.5 to Color(0.78f, 0.91f, 0.96f), 0.8 to Color(0.99f, 0.86f, 0.68f), 1.0 to duskBottom), scene.progress)
        } else {
            skyTop = ramp(listOf(0.0 to duskTop, 0.12 to Color(0.25f, 0.25f, 0.44f), 0.25 to Color(0.025f, 0.045f, 0.11f), 0.8 to Color(0.025f, 0.045f, 0.11f), 0.93 to Color(0.37f, 0.30f, 0.43f), 1.0 to dawnTop), scene.progress)
            skyBottom = ramp(listOf(0.0 to duskBottom, 0.12 to Color(0.38f, 0.28f, 0.39f), 0.25 to Color(0.07f, 0.12f, 0.19f), 0.8 to Color(0.07f, 0.12f, 0.19f), 0.93 to Color(0.62f, 0.40f, 0.40f), 1.0 to dawnBottom), scene.progress)
        }
    }

    companion object {
        fun blend(a: Color, b: Color, amount: Double): Color = lerp(a, b, amount.coerceIn(0.0, 1.0).toFloat())

        private fun ramp(stops: List<Pair<Double, Color>>, progress: Double): Color {
            for (index in 1 until stops.size) {
                val (lowerAt, lower) = stops[index - 1]
                val (upperAt, upper) = stops[index]
                if (progress <= upperAt) return blend(lower, upper, (progress - lowerAt) / (upperAt - lowerAt))
            }
            return stops.last().second
        }
    }
}

/**
 * The dynamic clock's picture, as iOS's BedsideSceneView draws it: the sky, stars at night, the sun or a crescent moon
 * along an arc, rolling hills and a seasonal tree, and a wash that keeps the clock readable. It sits behind the real
 * clock and changes only at the clock's minute; nothing flashes or moves in between.
 */
@Composable
internal fun BedsideScenePicture(scene: BedsideScene, modifier: Modifier) {
    val palette = remember(scene) { ScenePalette(scene) }
    Canvas(modifier) { drawScene(scene, palette) }
}

private fun DrawScope.drawScene(scene: BedsideScene, palette: ScenePalette) {
    val w = size.width
    val h = size.height
    drawRect(Brush.verticalGradient(listOf(palette.skyTop, palette.skyBottom)))
    if (!scene.isDay) {
        val starColor = Color(0.85f, 0.85f, 0.85f, (0.45 * (1 - palette.illumination / 0.4)).toFloat().coerceIn(0f, 1f))
        for (i in 0 until 24) {
            val x = ((i * 157 + 37) % 997) / 997f * w
            val y = ((i * 73 + 11) % 211) / 1000f * h
            val d = (if (i % 3 == 0) 3 else 2).dp.toPx()
            drawOval(starColor, Offset(x, y), Size(d, d))
        }
    }
    val radius = min(w, h) * 0.047f
    val point = Offset(w * (0.09f + 0.82f * scene.progress.toFloat()), h * (0.87f - 0.77f * sin(PI * scene.progress).toFloat()))
    if (scene.isDay) {
        drawCircle(Color(1f, 0.79f, 0.39f, 0.08f), radius * 1.4f, point)
        drawCircle(Color(1f, 0.83f, 0.48f), radius, point)
    } else {
        // A crescent: a symbolic moon, not a forecast of the moon's actual phase.
        val outer = Path().apply { addOval(Rect(point, radius)) }
        val cut = Path().apply { addOval(Rect(Offset(point.x - radius * 0.25f, point.y - radius * 1.2f), Size(radius * 1.7f, radius * 1.7f))) }
        drawPath(Path().apply { op(outer, cut, PathOperation.Difference) }, Color(0.91f, 0.89f, 0.73f))
    }
    // Quiet rolling hills frame the clock, with a seasonal tree at the edge.
    val snow = scene.season == BedsideScene.Season.WINTER
    fun hill(base: Float, color: Color, offset: Float) {
        val path = Path().apply {
            moveTo(0f, h * base)
            cubicTo(w * 0.36f, h * (base - 0.09f), w * 0.65f, h * (base + 0.05f), w, h * (base + offset))
            lineTo(w, h); lineTo(0f, h); close()
        }
        drawPath(path, color)
    }
    hill(0.86f, ScenePalette.blend(if (snow) Color(0.24f, 0.31f, 0.36f) else Color(0.10f, 0.23f, 0.22f),
        if (snow) Color(0.80f, 0.88f, 0.91f) else Color(0.51f, 0.72f, 0.48f), palette.illumination), -0.01f)
    hill(0.94f, ScenePalette.blend(if (snow) Color(0.33f, 0.39f, 0.41f) else Color(0.065f, 0.17f, 0.16f),
        if (snow) Color(0.91f, 0.94f, 0.93f) else Color(0.34f, 0.59f, 0.40f), palette.illumination), -0.025f)
    translate(w * 0.87f, h * 0.92f) {
        val unit = min(w, h) * 0.18f
        val branches = Path().apply {
            moveTo(0f, 0f); lineTo(-unit * 0.04f, -unit)
            for ((x, y) in listOf(-0.35f to -0.85f, 0.3f to -0.72f, -0.27f to -0.54f, 0.26f to -1.03f)) {
                moveTo(-unit * 0.02f, unit * y * 0.7f); lineTo(unit * x, unit * y)
            }
        }
        drawPath(branches, Color(0.33f, 0.28f, 0.23f), style = Stroke(width = max(3.dp.toPx(), unit * 0.04f), cap = StrokeCap.Round))
        if (!snow) {
            val foliage = when (scene.season) {
                BedsideScene.Season.FALL -> Color(0.65f, 0.34f, 0.18f)
                BedsideScene.Season.SPRING -> Color(0.46f, 0.55f, 0.37f)
                else -> Color(0.23f, 0.41f, 0.28f)
            }
            for ((x, y, r) in listOf(Triple(-0.24f, -0.83f, 0.26f), Triple(0.19f, -0.85f, 0.27f), Triple(0f, -1.07f, 0.28f),
                Triple(-0.15f, -0.58f, 0.23f), Triple(0.23f, -0.62f, 0.21f))) {
                drawCircle(foliage, unit * r, Offset(unit * x, unit * y))
            }
            if (scene.season == BedsideScene.Season.SPRING) {
                for ((x, y) in listOf(-0.24f to -0.9f, 0.19f to -0.9f, -0.02f to -1.15f, 0.22f to -0.64f)) {
                    drawOval(Color(0.85f, 0.66f, 0.63f), Offset(unit * x, unit * y), Size(unit * 0.07f, unit * 0.07f))
                }
            }
        } else {
            drawPath(branches, Color(0.75f, 0.79f, 0.79f), style = Stroke(width = max(1.dp.toPx(), unit * 0.014f), cap = StrokeCap.Round))
        }
    }
    // A light wash with dark lettering by day, and a dark one at night, so nothing in the picture hides the clock.
    val clear = palette.clockWash.copy(alpha = 0f)
    drawRect(Brush.verticalGradient(0f to clear, 0.18f to palette.clockWash, 0.78f to palette.clockWash, 1f to clear))
}
