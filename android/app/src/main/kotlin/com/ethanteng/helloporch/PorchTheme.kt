package com.ethanteng.helloporch

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** The website's design system (app/(site)/globals.css), as iOS's PorchStyle has it: a cream page, paper cards, ink text
 * and buttons, and deep tomato for the small things. */
internal object PorchBrand {
    /** The site's page, --bg. */
    val page = Color(0xFFF9EFDA)
    /** Cards and groups: the site's --paper. */
    val paper = Color(0xFFFEFBF6)
    /** Text, and filled buttons as the site's own: --ink. */
    val ink = Color(0xFF2E1D15)
    /** Secondary text: --muted, 8:1 on cards. */
    val secondary = Color(0xFF5B493F)
    /** Links, the chosen tab, switches, icons and badges: --tomato-deep. The logo's own tomato is too light for text. */
    val accent = Color(0xFFC0401F)
    val border = Color(0xFFDCCDB9)
    /** Highlights, such as the chosen tab's pill and a photo's placeholder: --honey. */
    val honey = Color(0xFFF2D39F)
    /** Green only where it means go: someone is at the bedside, a keypad is connected, Answer. */
    val go = Color(0xFF2F7A55)
    /** End call and Decline: the site's --help. */
    val danger = Color(0xFFC13D34)
    /** The wordmark's brown, --brown-ink, and the logo's tomato. */
    val wordmark = Color(0xFF64281A)
    val tomato = Color(0xFFE05D3D)
}

/** DM Sans, the website's text font. */
private val dmSans = FontFamily(
    Font(R.font.dm_sans_regular, FontWeight.Normal),
    Font(R.font.dm_sans_medium, FontWeight.Medium),
    Font(R.font.dm_sans_semibold, FontWeight.SemiBold),
    Font(R.font.dm_sans_bold, FontWeight.Bold),
)
/** Newsreader, the website's headings: screen titles and the names on the Call tab. */
internal val newsreader = FontFamily(Font(R.font.newsreader_medium, FontWeight.Medium))
/** Bricolage Grotesque, the wordmark's. */
private val bricolage = FontFamily(Font(R.font.bricolage_grotesque_extrabold, FontWeight.ExtraBold))

private val porchColors = lightColorScheme(
    primary = PorchBrand.accent, onPrimary = Color.White,
    primaryContainer = PorchBrand.honey, onPrimaryContainer = PorchBrand.ink,
    inversePrimary = Color(0xFFF2A58E),
    secondary = PorchBrand.secondary, onSecondary = Color.White,
    secondaryContainer = PorchBrand.honey, onSecondaryContainer = PorchBrand.ink,
    tertiary = PorchBrand.accent, onTertiary = Color.White,
    tertiaryContainer = PorchBrand.honey, onTertiaryContainer = PorchBrand.ink,
    background = PorchBrand.page, onBackground = PorchBrand.ink,
    // Cards, groups, menus and dialogs are paper on the page. Material tints a raised surface with surfaceTint, which
    // paper over paper leaves as it is.
    surface = PorchBrand.paper, onSurface = PorchBrand.ink, surfaceTint = PorchBrand.paper,
    surfaceVariant = PorchBrand.page, onSurfaceVariant = PorchBrand.secondary,
    surfaceBright = PorchBrand.paper, surfaceDim = Color(0xFFE8DCC6),
    surfaceContainerLowest = PorchBrand.paper, surfaceContainerLow = PorchBrand.paper, surfaceContainer = PorchBrand.paper,
    surfaceContainerHigh = PorchBrand.paper, surfaceContainerHighest = Color(0xFFF4E6D2),
    inverseSurface = PorchBrand.ink, inverseOnSurface = PorchBrand.page,
    outline = PorchBrand.border, outlineVariant = Color(0xFFEFE5D6),
)

/** Material's type scale, every style in DM Sans. */
private val porchTypography = Typography().run {
    fun TextStyle.sans() = copy(fontFamily = dmSans)
    Typography(
        displayLarge = displayLarge.sans(), displayMedium = displayMedium.sans(), displaySmall = displaySmall.sans(),
        headlineLarge = headlineLarge.sans(), headlineMedium = headlineMedium.sans(), headlineSmall = headlineSmall.sans(),
        titleLarge = titleLarge.sans(), titleMedium = titleMedium.sans(), titleSmall = titleSmall.sans(),
        bodyLarge = bodyLarge.sans(), bodyMedium = bodyMedium.sans(), bodySmall = bodySmall.sans(),
        labelLarge = labelLarge.sans(), labelMedium = labelMedium.sans(), labelSmall = labelSmall.sans(),
    )
}

/** FormButton's shape, where a theme sets one. Without one it's Material's pill. */
val LocalFormButtonShape = staticCompositionLocalOf<Shape?> { null }
/** A filled FormButton's color, where a theme sets one: ink, as the website's buttons. Without one it's primary. */
val LocalFormButtonColor = staticCompositionLocalOf<Color?> { null }
/** Screen titles' font, where a theme sets one: Newsreader. Without one it's the title style's own. */
val LocalTitleFontFamily = staticCompositionLocalOf<FontFamily?> { null }

/** A filled button's colors: the theme's (ink, with white words), else Material's. */
@Composable
fun porchButtonColors(): ButtonColors =
    LocalFormButtonColor.current?.let { ButtonDefaults.buttonColors(containerColor = it, contentColor = Color.White) } ?: ButtonDefaults.buttonColors()

/** A screen title's style: titleLarge, in Newsreader where the theme sets it. */
@Composable
fun porchTitleStyle(base: TextStyle = MaterialTheme.typography.titleLarge): TextStyle =
    LocalTitleFontFamily.current?.let { base.copy(fontFamily = it, fontWeight = FontWeight.Medium) } ?: base

/** The family's and caregivers' look, as iOS's: the website's colors and fonts, paper cards on a cream page, and ink
 * buttons with rounded corners rather than pills. Light only, as iOS keeps Porch's screens light. */
@Composable
fun PorchTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = porchColors, typography = porchTypography) {
        CompositionLocalProvider(LocalFormButtonShape provides RoundedCornerShape(14.dp), LocalFormButtonColor provides PorchBrand.ink,
            LocalTitleFontFamily provides newsreader, content = content)
    }
}

/** Mom's own screens (the bedside clock and its people, its messages, the call screens): the website's colors, and the
 * system font they were sized and tested with. */
@Composable
fun PorchBedsideTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = porchColors) {
        CompositionLocalProvider(LocalFormButtonColor provides PorchBrand.ink, content = content)
    }
}

/** The HelloPorch logo as the website draws it (components/PorchLogo.tsx): the smiling "p" in tomato beside "Porch" in
 * the wordmark's brown. The Call tab's title; TalkBack reads it as the "Porch" heading it replaces. */
@Composable
fun PorchWordmark(modifier: Modifier = Modifier, size: Float = 24f) {
    Row(modifier.clearAndSetSemantics { contentDescription = "Porch"; heading() }, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy((size * 0.2f).dp)) {
        // The mark is 1.05em tall, its viewBox 82 by 88.
        val height = size * 1.05f
        Canvas(Modifier.size(width = (height * 82f / 88f).dp, height = height.dp)) {
            val unit = this.size.height / 88f
            scale(unit, unit, pivot = Offset.Zero) {
                translate(-11f, -7.5f) {
                    val stroke = Stroke(width = 9f, cap = StrokeCap.Round)
                    drawLine(PorchBrand.tomato, Offset(20f, 44f), Offset(20f, 91f), strokeWidth = 9f, cap = StrokeCap.Round)
                    drawCircle(PorchBrand.tomato, radius = 32f, center = Offset(52f, 44f), style = stroke)
                    drawPath(Path().apply { moveTo(36f, 42f); quadraticTo(52f, 60f, 68f, 42f) }, PorchBrand.tomato, style = stroke)
                }
            }
        }
        Text("Porch", color = PorchBrand.wordmark, fontFamily = bricolage, fontWeight = FontWeight.ExtraBold, fontSize = size.sp,
            letterSpacing = (-0.045).em, maxLines = 1)
    }
}
