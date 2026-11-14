package com.tomy.httnavicompanion.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = HTTPink,
    secondary = HTTGold,
    tertiary = NeonCyan,
    background = CockpitBg,
    surface = CockpitCardBg,
    onPrimary = TextPrimary,
    onSecondary = CockpitBg,
    onBackground = TextPrimary,
    onSurface = TextPrimary
)

@Composable
fun HTTNaviCompanionTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
