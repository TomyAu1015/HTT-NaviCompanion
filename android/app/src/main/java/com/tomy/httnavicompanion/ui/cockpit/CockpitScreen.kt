package com.tomy.httnavicompanion.ui.cockpit

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.HTTCharacter
import com.tomy.httnavicompanion.ui.theme.*

@Composable
fun CockpitScreen(
    onOpenFeedback: () -> Unit,
    onStartFloatingPet: () -> Unit
) {
    val configuration = LocalConfiguration.current
    val isLandscape = configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    val app = HTTNaviApp.instance
    val currentCharacter by app.audioPlayerManager.selectedCharacter.collectAsState()
    val mascotSpeech by app.audioPlayerManager.mascotSpeechText.collectAsState()
    val isMusicPlaying by app.musicManager.isPlaying.collectAsState()
    val currentTrack by app.musicManager.currentTrack.collectAsState()

    var currentSpeed by remember { mutableStateOf(58) }
    var trafficCountdown by remember { mutableStateOf(14) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF090D16), Color(0xFF0E1524), Color(0xFF05070B))
                )
            )
            .padding(8.dp)
    ) {
        if (isLandscape) {
            // Horizontal Split Cockpit Layout
            Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // Left Column: Speedometer, HUD, Controls
                Column(
                    modifier = Modifier
                        .weight(0.48f)
                        .fillMaxHeight(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    TopHUDBar(currentSpeed = currentSpeed, countdown = trafficCountdown)
                    SpeedometerCard(speed = currentSpeed)
                    CharacterSelectorRow(
                        selected = currentCharacter,
                        onSelect = { app.audioPlayerManager.selectCharacter(it) }
                    )
                }

                // Right Column: Stage, Mascot Bubble, Music, Actions
                Column(
                    modifier = Modifier
                        .weight(0.52f)
                        .fillMaxHeight(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    MascotStageCard(
                        character = currentCharacter,
                        speechText = mascotSpeech,
                        onTapMascot = { app.audioPlayerManager.triggerCharacterVoice(currentCharacter.id) },
                        onStartOverlay = onStartFloatingPet,
                        modifier = Modifier.weight(1f)
                    )
                    BottomMusicBar(
                        trackTitle = currentTrack.title,
                        isPlaying = isMusicPlaying,
                        onTogglePlay = { app.musicManager.togglePlayPause() },
                        onNext = { app.musicManager.nextTrack() },
                        onOpenFeedback = onOpenFeedback
                    )
                }
            }
        } else {
            // Portrait Cockpit Layout
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TopHUDBar(currentSpeed = currentSpeed, countdown = trafficCountdown)
                SpeedometerCard(speed = currentSpeed)
                CharacterSelectorRow(
                    selected = currentCharacter,
                    onSelect = { app.audioPlayerManager.selectCharacter(it) }
                )
                MascotStageCard(
                    character = currentCharacter,
                    speechText = mascotSpeech,
                    onTapMascot = { app.audioPlayerManager.triggerCharacterVoice(currentCharacter.id) },
                    onStartOverlay = onStartFloatingPet,
                    modifier = Modifier.weight(1f)
                )
                BottomMusicBar(
                    trackTitle = currentTrack.title,
                    isPlaying = isMusicPlaying,
                    onTogglePlay = { app.musicManager.togglePlayPause() },
                    onNext = { app.musicManager.nextTrack() },
                    onOpenFeedback = onOpenFeedback
                )
            }
        }
    }
}

@Composable
fun TopHUDBar(currentSpeed: Int, countdown: Int) {
    Card(
        colors = CardDefaults.cardColors(containerColor = CockpitCardBg),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().border(1.dp, CockpitCardBorder, RoundedCornerShape(12.dp))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Lane indicators
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf(Icons.Default.ArrowUpward, Icons.Default.ArrowUpward, Icons.Default.TurnRight, Icons.Default.TurnLeft).forEachIndexed { i, icon ->
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(if (i == 1) NeonCyan.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.05f))
                            .border(1.dp, if (i == 1) NeonCyan else Color.White.copy(alpha = 0.2f), RoundedCornerShape(4.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(icon, contentDescription = null, tint = if (i == 1) NeonCyan else Color.White.copy(alpha = 0.5f), modifier = Modifier.size(16.dp))
                    }
                }
            }

            // Traffic Light Capsule
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xFF05070D))
                    .border(1.dp, Color(0xFF1E2838), RoundedCornerShape(16.dp))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Box(modifier = Modifier.size(9.dp).clip(CircleShape).background(Color(0xFF330B0B)))
                Box(modifier = Modifier.size(9.dp).clip(CircleShape).background(Color(0xFF332B0B)))
                Box(modifier = Modifier.size(9.dp).clip(CircleShape).background(NeonGreen))
                Text(
                    text = "${countdown}s",
                    color = NeonGreen,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp
                )
            }

            // Speed Limit
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(Color.White)
                    .border(2.dp, Color.Red, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text("60", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black)
            }
        }
    }
}

@Composable
fun SpeedometerCard(speed: Int) {
    Card(
        colors = CardDefaults.cardColors(containerColor = CockpitCardBg),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().border(1.dp, CockpitCardBorder, RoundedCornerShape(12.dp))
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text("车速 SPEED", color = TextSecondary, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("$speed", color = TextPrimary, fontSize = 38.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
                    Spacer(Modifier.width(4.dp))
                    Text("km/h", color = NeonCyan, fontSize = 12.sp, modifier = Modifier.padding(bottom = 6.dp))
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("前方路况 · 畅通", color = NeonGreen, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                Text("距离下个转弯 380 米", color = TextSecondary, fontSize = 11.sp)
            }
        }
    }
}

@Composable
fun CharacterSelectorRow(selected: HTTCharacter, onSelect: (HTTCharacter) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        HTTCharacter.values().forEach { char ->
            val isSel = selected == char
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (isSel) HTTPink else CockpitCardBg)
                    .border(1.dp, if (isSel) HTTGold else CockpitCardBorder, RoundedCornerShape(8.dp))
                    .clickable { onSelect(char) }
                    .padding(vertical = 6.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = char.displayName.take(1),
                    color = if (isSel) Color.White else TextSecondary,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp
                )
            }
        }
    }
}

@Composable
fun MascotStageCard(
    character: HTTCharacter,
    speechText: String,
    onTapMascot: () -> Unit,
    onStartOverlay: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = CockpitCardBg),
        shape = RoundedCornerShape(12.dp),
        modifier = modifier.fillMaxWidth().border(1.dp, CockpitCardBorder, RoundedCornerShape(12.dp))
    ) {
        Box(modifier = Modifier.fillMaxSize().padding(12.dp)) {
            // Mascot Speech Bubble
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1E283D)),
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter)
            ) {
                Text(
                    text = speechText,
                    color = TextPrimary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(10.dp),
                    textAlign = TextAlign.Center
                )
            }

            // Mascot Avatar & Interaction Trigger
            Column(
                modifier = Modifier.align(Alignment.Center).clickable { onTapMascot() },
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Box(
                    modifier = Modifier
                        .size(90.dp)
                        .clip(CircleShape)
                        .background(
                            Brush.radialGradient(
                                listOf(HTTPink.copy(alpha = 0.4f), Color.Transparent)
                            )
                        )
                        .border(2.dp, HTTGold, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "🎸",
                        fontSize = 44.sp
                    )
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "${character.displayName} (${character.jpName})",
                    color = HTTGold,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(text = "点击互动发声", color = TextSecondary, fontSize = 10.sp)
            }

            // Desktop Overlay Pet Button
            Button(
                onClick = onStartOverlay,
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF23304F)),
                shape = RoundedCornerShape(16.dp),
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
                modifier = Modifier.align(Alignment.BottomEnd)
            ) {
                Text("开启桌面悬浮伴侣", color = NeonCyan, fontSize = 11.sp)
            }
        }
    }
}

@Composable
fun BottomMusicBar(
    trackTitle: String,
    isPlaying: Boolean,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onOpenFeedback: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = CockpitCardBg),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().border(1.dp, CockpitCardBorder, RoundedCornerShape(12.dp))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("🎵", fontSize = 18.sp)
                Column {
                    Text(trackTitle, color = TextPrimary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Text("放課後ティータイム · 原声馆", color = TextSecondary, fontSize = 10.sp)
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                IconButton(onClick = onTogglePlay, modifier = Modifier.size(32.dp)) {
                    Icon(
                        if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = null,
                        tint = HTTPink
                    )
                }
                IconButton(onClick = onNext, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Default.SkipNext, contentDescription = null, tint = Color.White)
                }
                IconButton(onClick = onOpenFeedback, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Default.Info, contentDescription = null, tint = TextSecondary)
                }
            }
        }
    }
}
