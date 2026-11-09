package com.ethanteng.helloporch

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

// iOS's PorchStyle colors (CaregiverUI.swift).
private val page = Color(0xFFF2F5F0)
private val ink = Color(0xFF1F302B)
private val secondary = Color(0xFF596961)
private val accent = Color(0xFF295C4A)
private val border = Color(0xFFC4CFC7)

/** A pale green page with white cards on it, dark green ink, and dark green buttons. Light only, as iOS keeps Porch's
 * screens light. */
private val porchColors = lightColorScheme(
    primary = accent, onPrimary = Color.White,
    primaryContainer = Color(0xFFD3E6DB), onPrimaryContainer = ink,
    inversePrimary = Color(0xFF9CCFB7),
    secondary = secondary, onSecondary = Color.White,
    secondaryContainer = Color(0xFFDCE7E0), onSecondaryContainer = ink,
    tertiary = accent, onTertiary = Color.White,
    tertiaryContainer = Color(0xFFD3E6DB), onTertiaryContainer = ink,
    background = page, onBackground = ink,
    // Cards, groups, menus and dialogs are white on the page. Material tints a raised surface with surfaceTint, which
    // white over white leaves as it is.
    surface = Color.White, onSurface = ink, surfaceTint = Color.White,
    surfaceVariant = page, onSurfaceVariant = secondary,
    surfaceBright = Color.White, surfaceDim = Color(0xFFDCE2DD),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color.White, surfaceContainer = Color.White,
    surfaceContainerHigh = Color.White, surfaceContainerHighest = Color(0xFFE4EAE5),
    inverseSurface = ink, inverseOnSurface = page,
    outline = border, outlineVariant = Color(0xFFDDE3DE),
)

/** FormButton's shape, where a theme sets one. Without one it's Material's pill. */
val LocalFormButtonShape = staticCompositionLocalOf<Shape?> { null }

/** Family mode's look, as iOS's family screens look: PorchStyle's colors, white cards on a pale green page, and buttons
 * with rounded corners rather than pills. The bedside's screens keep Material's defaults. */
@Composable
fun PorchTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = porchColors) {
        CompositionLocalProvider(LocalFormButtonShape provides RoundedCornerShape(14.dp), content = content)
    }
}
