package com.tomy.httnavicompanion.ui.cockpit

import android.content.res.Configuration
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import com.tomy.httnavicompanion.ui.map.OsmMapView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.*

private val HTTCrimson = Color(0xFFA61E2E)
private val HTTGold = Color(0xFFE0B861)
private val HTTCream = Color(0xFFFAF2E0)
private val HTTDarkPanel = Color(0xFF141720)

private fun characterThemeColor(char: CharacterFilter): Color = when (char) {
    CharacterFilter.YUI -> Color(0xFFE65261)
    CharacterFilter.MIO -> Color(0xFF407AD1)
    CharacterFilter.RITSU -> Color(0xFFD99426)
    CharacterFilter.MUGI -> Color(0xFFC785AD)
    CharacterFilter.AZUSA -> Color(0xFF38A685)
    CharacterFilter.ALL -> HTTCrimson
}

@Composable
fun CockpitScreen(
    onStartFloatingPet: () -> Unit
) {
    val configuration = LocalConfiguration.current
    val isLandscape = configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val musicMgr = app.musicManager

    val lang by manager.language.collectAsState()
    val showMapMode by manager.showMapMode.collectAsState()
    val isMapEnlarged by manager.isMapEnlarged.collectAsState()
    val isHUDMirrored by manager.isHUDMirrored.collectAsState()
    val themeBgBmp by manager.themeBackgroundBitmap.collectAsState()
    val isDraggingMascot by manager.isDraggingMascot.collectAsState()
    val isTouchingMap by manager.isTouchingMap.collectAsState()

    var showMusicDialog by remember { mutableStateOf(false) }
    var showAlbumDialog by remember { mutableStateOf(false) }
    var albumInitialTab by remember { mutableStateOf(0) }
    var showSearchDialog by remember { mutableStateOf(false) }
    var showSoundboardDialog by remember { mutableStateOf(false) }
    var showGameRoomDialog by remember { mutableStateOf(false) }
    var showAIChatDialog by remember { mutableStateOf(false) }
    var showVehicleDialog by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(HTTDarkPanel)
            .scale(scaleX = if (isHUDMirrored) -1f else 1f, scaleY = 1f)
    ) {
        // RM-500HTT Official Background Wallpaper Layer (matches iOS 0.38 opacity)
        if (themeBgBmp != null && !isMapEnlarged) {
            Image(
                bitmap = themeBgBmp!!.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                alpha = 0.38f
            )
        }

        if (isMapEnlarged) {
            EnlargedNavigationHUDView(
                manager = manager,
                musicMgr = musicMgr,
                isLandscape = isLandscape,
                onOpenSearch = { showSearchDialog = true },
                onOpenMusic = { showMusicDialog = true }
            )
        } else if (isLandscape) {
            // Landscape Dual-Column Cockpit matching iOS ContentView.swift
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .verticalScroll(rememberScrollState(), enabled = !isDraggingMascot && !isTouchingMap)
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                TopBezelBar(
                    manager = manager,
                    musicMgr = musicMgr,
                    onOpenMusic = { showMusicDialog = true },
                    onOpenAlbum = {
                        albumInitialTab = 0
                        showAlbumDialog = true
                    },
                    onOpenSoundboard = { showSoundboardDialog = true },
                    onStartFloatingPet = onStartFloatingPet,
                    onOpenAIChat = { showAIChatDialog = true },
                    onOpenGameRoom = { showGameRoomDialog = true },
                    onOpenVehicle = { showVehicleDialog = true }
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    // Left Column (0.46 weight): Speedometer + Tactical Grid + Outfit/Camera/Gift + Author Bar
                    Column(
                        modifier = Modifier.weight(0.46f),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        SpeedometerCockpit(manager = manager, isCompact = true)
                        UtilityControlGrid(
                            manager = manager,
                            isCompact = true,
                            onOpenSearch = { showSearchDialog = true }
                        )
                        OutfitCameraGiftRow(
                            manager = manager,
                            onOpenWardrobe = {
                                albumInitialTab = 0
                                showAlbumDialog = true
                            }
                        )
                        AuthorAndFeedbackBar(
                            manager = manager,
                            onClick = {
                                albumInitialTab = 2
                                showAlbumDialog = true
                            }
                        )
                    }

                    // Right Column (0.54 weight): Stage/Map + Speech Bubble + Character Strip + Travel Modes + Mini Music Bar
                    Column(
                        modifier = Modifier.weight(0.54f),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        MainStageOrMapSection(
                            manager = manager,
                            stageHeight = 205.dp,
                            onOpenSearch = { showSearchDialog = true }
                        )
                        CharacterSelectorStrip(manager = manager)
                        TravelModesRow(manager = manager)
                    }
                }
            }
        } else {
            // Portrait Single-Column Cockpit matching iOS ContentView.swift (adaptive height for all Android screen ratios)
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val adaptiveStageH = (maxHeight * 0.245f).coerceIn(176.dp, 212.dp)
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .statusBarsPadding()
                        .navigationBarsPadding()
                        .verticalScroll(rememberScrollState(), enabled = !isDraggingMascot && !isTouchingMap)
                        .padding(horizontal = 9.dp, vertical = 3.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    TopBezelBar(
                        manager = manager,
                        musicMgr = musicMgr,
                        onOpenMusic = { showMusicDialog = true },
                        onOpenAlbum = {
                            albumInitialTab = 0
                            showAlbumDialog = true
                        },
                        onOpenSoundboard = { showSoundboardDialog = true },
                        onStartFloatingPet = onStartFloatingPet,
                        onOpenAIChat = { showAIChatDialog = true },
                        onOpenGameRoom = { showGameRoomDialog = true },
                        onOpenVehicle = { showVehicleDialog = true }
                    )
                    SpeedometerCockpit(manager = manager, isCompact = false)
                    MainStageOrMapSection(
                        manager = manager,
                        stageHeight = adaptiveStageH,
                        onOpenSearch = { showSearchDialog = true }
                    )
                CharacterSelectorStrip(manager = manager)
                UtilityControlGrid(
                    manager = manager,
                    isCompact = false,
                    onOpenSearch = { showSearchDialog = true }
                )
                TravelModesRow(manager = manager)
                OutfitCameraGiftRow(
                    manager = manager,
                    onOpenWardrobe = {
                        albumInitialTab = 0
                        showAlbumDialog = true
                    }
                )
                AuthorAndFeedbackBar(
                    manager = manager,
                    onClick = {
                        albumInitialTab = 2
                        showAlbumDialog = true
                    }
                )
                }
            }
        }

        // Modals
        if (showMusicDialog) {
            MusicLibrarySheetDialog(onDismiss = { showMusicDialog = false })
        }
        if (showAlbumDialog) {
            RM500AlbumAndOutfitSheetDialog(
                initialTab = albumInitialTab,
                onDismiss = { showAlbumDialog = false }
            )
        }
        if (showSearchDialog) {
            DestinationSearchSheetDialog(onDismiss = { showSearchDialog = false })
        }
        if (showSoundboardDialog) {
            SoundboardSheetDialog(onDismiss = { showSoundboardDialog = false })
        }
        if (showAIChatDialog) {
            LocalAIChatSheetDialog(
                onDismiss = { showAIChatDialog = false },
                onOpenGameRoom = { showGameRoomDialog = true },
                onOpenSearch = { showSearchDialog = true }
            )
        }
        if (showGameRoomDialog) {
            KOnGameRoomSheetDialog(onDismiss = { showGameRoomDialog = false })
        }
        if (showVehicleDialog) {
            VehicleAndPlateSettingsDialog(onDismiss = { showVehicleDialog = false })
        }
    }
}

@Composable
fun TopBezelBar(
    manager: AudioPlayerManager,
    musicMgr: KOnMusicManager,
    onOpenMusic: () -> Unit,
    onOpenAlbum: () -> Unit,
    onOpenSoundboard: () -> Unit,
    onStartFloatingPet: () -> Unit,
    onOpenAIChat: () -> Unit,
    onOpenGameRoom: () -> Unit,
    onOpenVehicle: () -> Unit
) {
    val showMapMode by manager.showMapMode.collectAsState()
    val isMusicPlaying by musicMgr.isPlaying.collectAsState()
    val lang by manager.language.collectAsState()
    val isHUDMirrored by manager.isHUDMirrored.collectAsState()
    var showLangMenu by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        // 1. Stage / Map Mode Toggle
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(HTTCrimson)
                .border(1.dp, HTTGold.copy(alpha = 0.55f), RoundedCornerShape(8.dp))
                .clickable { manager.toggleMapMode() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                if (showMapMode) Icons.Default.Map else Icons.Default.Coffee,
                contentDescription = null,
                tint = HTTGold,
                modifier = Modifier.size(13.dp)
            )
            Text(
                if (showMapMode) "地图模式" else "舞台模式",
                color = HTTCream,
                fontSize = 11.sp,
                fontWeight = FontWeight.Black,
                maxLines = 1
            )
        }

        // 2. Music Hall Button
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(if (isMusicPlaying) Color(0xFF8E24AA) else Color.White.copy(alpha = 0.14f))
                .border(1.dp, HTTGold.copy(alpha = 0.7f), RoundedCornerShape(8.dp))
                .clickable { onOpenMusic() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                Icons.Default.LibraryMusic,
                contentDescription = null,
                tint = if (isMusicPlaying) Color.White else HTTGold,
                modifier = Modifier.size(13.dp)
            )
            Text(
                "音乐",
                color = if (isMusicPlaying) Color.White else HTTGold,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }

        // 原声库按钮已按需求隐藏 (与 iOS v1.6.3 保持一致)

        // 4. Desktop Floating Pet Trigger
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(Color(0xFF1E3A5F))
                .border(1.dp, Color(0xFF00E5FF), RoundedCornerShape(8.dp))
                .clickable { onStartFloatingPet() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Icon(Icons.Default.PictureInPictureAlt, contentDescription = null, tint = Color(0xFF00E5FF), modifier = Modifier.size(13.dp))
            Text("悬浮宠", color = Color(0xFF00E5FF), fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }

        // 4.4 K-ON! Local AI Tea Time Co-Pilot (AI茶会)
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(Color(0xFF5E35B1))
                .border(1.dp, HTTGold, RoundedCornerShape(8.dp))
                .clickable { onOpenAIChat() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text("✨", fontSize = 11.sp)
            Text(
                when (lang) {
                    AppLanguage.ZH_HANS -> "AI茶会"
                    AppLanguage.ZH_HANT -> "AI茶會"
                    AppLanguage.EN -> "AI Tea"
                },
                color = Color.White,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }

        // 4.5 K-ON! Ho-kago Game Room (放课后棋牌室：斗地主 + 广东红中麻将)
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(Color(0xFF1B5E20))
                .border(1.dp, HTTGold, RoundedCornerShape(8.dp))
                .clickable { onOpenGameRoom() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text("🀄", fontSize = 11.sp)
            Text(
                when (lang) {
                    AppLanguage.ZH_HANS -> "放课后棋牌室"
                    AppLanguage.ZH_HANT -> "放課後棋牌室"
                    AppLanguage.EN -> "Game Room"
                },
                color = Color.White,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }

        // 5. Language Switcher
        Box {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color.White.copy(alpha = 0.14f))
                    .clickable { showLangMenu = true }
                    .padding(horizontal = 7.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Icon(Icons.Default.Language, contentDescription = null, tint = HTTGold, modifier = Modifier.size(12.dp))
                Text(lang.label, color = HTTGold, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
            DropdownMenu(expanded = showLangMenu, onDismissRequest = { showLangMenu = false }) {
                AppLanguage.values().forEach { l ->
                    DropdownMenuItem(
                        text = { Text(l.label) },
                        onClick = {
                            manager.setLanguage(l)
                            showLangMenu = false
                        }
                    )
                }
            }
        }

        // 6. HUD Mirror Button
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(if (isHUDMirrored) HTTGold else Color.White.copy(alpha = 0.12f))
                .clickable { manager.toggleHUDMirror() }
                .padding(horizontal = 7.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Icon(
                Icons.Default.Flip,
                contentDescription = null,
                tint = if (isHUDMirrored) Color.Black else HTTCream,
                modifier = Modifier.size(12.dp)
            )
            Text(
                if (isHUDMirrored) "镜像" else "HUD",
                color = if (isHUDMirrored) Color.Black else HTTCream,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }

        // 7. Album / Outfit Button
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(Color(0xFFE91E63).copy(alpha = 0.88f))
                .border(1.dp, HTTGold, RoundedCornerShape(8.dp))
                .clickable { onOpenAlbum() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            val albumIconBmp = remember { HTTNaviApp.instance.assetDecryptor.getSpriteBitmap("rm_btn_icon_on") }
            if (albumIconBmp != null) {
                Image(
                    bitmap = albumIconBmp.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier.size(15.dp).clip(RoundedCornerShape(3.dp))
                )
            } else {
                Icon(Icons.Default.PhotoLibrary, contentDescription = null, tint = Color.White, modifier = Modifier.size(13.dp))
            }
            Text("相册/车标", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black, maxLines = 1)
        }
    }
}

@Composable
fun SpeedometerCockpit(manager: AudioPlayerManager, isCompact: Boolean) {
    val speed by manager.currentSpeedKmh.collectAsState()
    val maxSpeed by manager.maxSpeedKmh.collectAsState()
    val speedLimit by manager.speedLimitKmh.collectAsState()
    val gpsPoor by manager.isGPSSignalPoor.collectAsState()
    val tripDist by manager.tripDistanceKm.collectAsState()
    val drivingSecs by manager.drivingSeconds.collectAsState()
    val heading by manager.headingDegrees.collectAsState()

    val isOverspeed = speed > speedLimit

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color.Black.copy(alpha = 0.65f))
            .border(2.dp, if (isOverspeed) Color.Red else HTTGold.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
            .padding(if (isCompact) 8.dp else 10.dp),
        verticalArrangement = Arrangement.spacedBy(if (isCompact) 4.dp else 6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "$speed",
                        color = if (isOverspeed) Color.Red else Color(0xFF59FAA6),
                        fontSize = if (isCompact) 36.sp else 44.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = FontFamily.Monospace
                    )
                    Text(
                        text = "km/h",
                        color = HTTCream.copy(alpha = 0.7f),
                        fontSize = if (isCompact) 11.sp else 13.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        modifier = Modifier.padding(bottom = 5.dp)
                    )
                }

                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(5.dp))
                        .background(if (gpsPoor) Color(0xFFFF9800).copy(alpha = 0.3f) else Color(0xFF4CAF50).copy(alpha = 0.18f))
                        .clickable { manager.triggerGPSSignalAlert() }
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Icon(
                        Icons.Default.GpsFixed,
                        contentDescription = null,
                        tint = if (gpsPoor) Color(0xFFFF9800) else Color(0xFF4CAF50),
                        modifier = Modifier.size(11.dp)
                    )
                    Text(
                        if (gpsPoor) "GPS弱(点按播报)" else "GPS信号正常",
                        color = if (gpsPoor) Color(0xFFFF9800) else Color(0xFF4CAF50),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Right Telemetry Badges: DIR, TRIP, TIME
            val dirStr = remember(heading) { manager.compassDirectionString() }
            val timeStr = remember(drivingSecs) { manager.formattedDrivingTime() }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                TelemetryBadge(label = "方向", value = dirStr)
                TelemetryBadge(label = "里程", value = String.format("%.1f km", tripDist))
                TelemetryBadge(label = "时长", value = timeStr)
            }
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.15f))

        // Speed Limit Row: 60 / 80 / 100 / 120 + MAX
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                modifier = Modifier.clickable { manager.triggerSpeedLimitPrompt() },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Icon(Icons.Default.Speed, contentDescription = null, tint = HTTGold, modifier = Modifier.size(13.dp))
                Text("限速播报:", color = HTTGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }

            listOf(60, 80, 100, 120).forEach { lim ->
                val sel = speedLimit == lim
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(5.dp))
                        .background(if (sel) HTTCrimson else Color.White.copy(alpha = 0.1f))
                        .clickable { manager.setSpeedLimit(lim) }
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text("$lim", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Text("最高: $maxSpeed", color = HTTGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun TelemetryBadge(label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, color = Color.Gray, fontSize = 10.sp)
        Text(value, color = HTTCream, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
    }
}

@Composable
fun MainStageOrMapSection(
    manager: AudioPlayerManager,
    stageHeight: Dp,
    onOpenSearch: () -> Unit
) {
    val showMapMode by manager.showMapMode.collectAsState()

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (showMapMode) {
            InteractiveMapBoxView(
                manager = manager,
                stageHeight = stageHeight,
                onOpenSearch = onOpenSearch
            )
        } else {
            ClubroomStageView(
                manager = manager,
                stageHeight = stageHeight
            )
        }
        SpeechBubbleBox(manager = manager)
    }
}

@Composable
fun ClubroomStageView(
    manager: AudioPlayerManager,
    stageHeight: Dp
) {
    val app = HTTNaviApp.instance
    val density = LocalDensity.current
    val selectedChar by manager.selectedCharacter.collectAsState()
    val mascotAction by manager.mascotAction.collectAsState()
    val allMemberFrames by manager.allMemberFrames.collectAsState()
    val currentSprite by manager.currentSpriteFrame.collectAsState()
    val teaPartyBmp by manager.teaPartyCompositedFrame.collectAsState()
    val offsetX by manager.mascotOffsetX.collectAsState()
    val offsetY by manager.mascotOffsetY.collectAsState()
    val isDragging by manager.isDraggingMascot.collectAsState()
    val draggedMemberId by manager.draggedMemberId.collectAsState()
    val memberPositions by manager.memberPositions.collectAsState()
    val unseatedTeaIds by manager.unseatedTeaMemberIds.collectAsState()
    val lang by manager.language.collectAsState()

    var dragDeltaX by remember { mutableStateOf(0f) }
    var dragDeltaY by remember { mutableStateOf(0f) }

    val themeColor = characterThemeColor(selectedChar)
    val isCompactStage = stageHeight < 215.dp
    val spriteSize = if (isCompactStage) 64.dp else 72.dp
    val singleSpriteSize = if (isCompactStage) 76.dp else 86.dp
    val teaSceneHeight = if (isCompactStage) 118.dp else 134.dp

    val seatedOrder = remember {
        listOf(
            CharacterFilter.MIO,
            CharacterFilter.RITSU,
            CharacterFilter.YUI,
            CharacterFilter.MUGI,
            CharacterFilter.AZUSA
        )
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(stageHeight)
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.verticalGradient(
                    listOf(themeColor.copy(alpha = 0.35f), Color.Black.copy(alpha = 0.78f))
                )
            )
            .border(2.dp, HTTGold, RoundedCornerShape(16.dp))
    ) {
        // 1. Characters / Tea Party Scene Layer (with 1:1 iOS Drag-to-Lift "提起挣扎" support!)
        if (mascotAction == MascotActionState.TEA_CAKE && teaPartyBmp != null) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .padding(bottom = if (isCompactStage) 6.dp else 10.dp),
                contentAlignment = Alignment.BottomCenter
            ) {
                Image(
                    bitmap = teaPartyBmp!!.asImageBitmap(),
                    contentDescription = "放课后茶会下午茶",
                    filterQuality = FilterQuality.None,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .height(teaSceneHeight)
                        .fillMaxWidth(0.96f)
                )

                if (selectedChar == CharacterFilter.ALL) {
                    // 5 interactive seat hit-boxes over the tea table so any seated girl can be tapped or lifted out of her chair!
                    Row(
                        modifier = Modifier
                            .height(teaSceneHeight)
                            .width((teaSceneHeight * 1.92f).coerceAtMost(290.dp)),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        seatedOrder.forEachIndexed { sIdx, member ->
                            val isUnseated = unseatedTeaIds.contains(member.charId)
                            val isThisLifted = isDragging && draggedMemberId == member.charId
                            val seatCenterOffsetDp = (sIdx - 2) * 52f
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                                    .then(
                                        if (!isUnseated) {
                                            Modifier
                                                .pointerInput(member.charId, "tea_seat") {
                                                    detectDragGestures(
                                                        onDragStart = {
                                                            dragDeltaX = 0f
                                                            dragDeltaY = 0f
                                                            manager.markDragActive(member.charId)
                                                        },
                                                        onDrag = { change, dragAmount ->
                                                            change.consume()
                                                            dragDeltaX += with(density) { dragAmount.x.toDp().value }
                                                            dragDeltaY += with(density) { dragAmount.y.toDp().value }
                                                            manager.markDragActive(member.charId)
                                                        },
                                                        onDragEnd = {
                                                            val dropX = (seatCenterOffsetDp + dragDeltaX).coerceIn(-125f, 125f)
                                                            val dropY = dragDeltaY.coerceIn(-48f, 26f)
                                                            manager.finishDraggingMascot(member.charId, dropX, dropY)
                                                            dragDeltaX = 0f
                                                            dragDeltaY = 0f
                                                        },
                                                        onDragCancel = {
                                                            manager.finishDraggingMascot(member.charId, seatCenterOffsetDp, 0f)
                                                            dragDeltaX = 0f
                                                            dragDeltaY = 0f
                                                        }
                                                    )
                                                }
                                                .clickable { manager.triggerCharacterTap(member) }
                                        } else Modifier
                                    ),
                                contentAlignment = Alignment.Center
                            ) {
                                if (isThisLifted && !isUnseated) {
                                    allMemberFrames[member.charId]?.let { grabbedBmp ->
                                        Image(
                                            bitmap = grabbedBmp.asImageBitmap(),
                                            contentDescription = member.displayName(lang),
                                            filterQuality = FilterQuality.None,
                                            contentScale = ContentScale.Fit,
                                            modifier = Modifier
                                                .size(spriteSize)
                                                .offset(x = dragDeltaX.dp, y = dragDeltaY.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Render any unseated girls who were lifted out of the tea table at their dropped stage positions!
                    seatedOrder.forEach { member ->
                        if (unseatedTeaIds.contains(member.charId)) {
                            val frame = allMemberFrames[member.charId]
                            val savedPos = memberPositions[member.charId] ?: Pair(0f, 0f)
                            val isThisDragged = isDragging && draggedMemberId == member.charId
                            val curX = savedPos.first + if (isThisDragged) dragDeltaX else 0f
                            val curY = savedPos.second + if (isThisDragged) dragDeltaY else 0f

                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                modifier = Modifier
                                    .offset(x = curX.dp, y = curY.dp)
                                    .clickable { manager.triggerCharacterTap(member) }
                                    .pointerInput(member.charId, "unseated") {
                                        detectDragGestures(
                                            onDragStart = {
                                                dragDeltaX = 0f
                                                dragDeltaY = 0f
                                                manager.markDragActive(member.charId)
                                            },
                                            onDrag = { change, dragAmount ->
                                                change.consume()
                                                dragDeltaX += with(density) { dragAmount.x.toDp().value }
                                                dragDeltaY += with(density) { dragAmount.y.toDp().value }
                                                manager.markDragActive(member.charId)
                                            },
                                            onDragEnd = {
                                                val oldP = manager.memberPositions.value[member.charId] ?: Pair(0f, 0f)
                                                val dropX = (oldP.first + dragDeltaX).coerceIn(-125f, 125f)
                                                val dropY = (oldP.second + dragDeltaY).coerceIn(-48f, 26f)
                                                manager.finishDraggingMascot(member.charId, dropX, dropY)
                                                dragDeltaX = 0f
                                                dragDeltaY = 0f
                                            },
                                            onDragCancel = {
                                                val oldP = manager.memberPositions.value[member.charId] ?: Pair(0f, 0f)
                                                manager.finishDraggingMascot(member.charId, oldP.first, oldP.second)
                                                dragDeltaX = 0f
                                                dragDeltaY = 0f
                                            }
                                        )
                                    }
                            ) {
                                if (frame != null) {
                                    Image(
                                        bitmap = frame.asImageBitmap(),
                                        contentDescription = member.displayName(lang),
                                        filterQuality = FilterQuality.None,
                                        contentScale = ContentScale.Fit,
                                        modifier = Modifier.size(spriteSize)
                                    )
                                }
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(4.dp))
                                        .background(characterThemeColor(member).copy(alpha = 0.90f))
                                        .padding(horizontal = 5.dp, vertical = 1.dp)
                                ) {
                                    Text(member.displayName(lang), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                }
                            }
                        }
                    }
                } else {
                    // Single character seated at the afternoon tea table: tap or drag to lift her out of her chair!
                    Box(
                        modifier = Modifier
                            .height(teaSceneHeight)
                            .fillMaxWidth(0.94f)
                            .clickable { manager.triggerCharacterTap(selectedChar) }
                            .pointerInput(selectedChar.charId, "single_tea") {
                                detectDragGestures(
                                    onDragStart = {
                                        dragDeltaX = 0f
                                        dragDeltaY = 0f
                                        manager.markDragActive(selectedChar.charId)
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        dragDeltaX += with(density) { dragAmount.x.toDp().value }
                                        dragDeltaY += with(density) { dragAmount.y.toDp().value }
                                        manager.markDragActive(selectedChar.charId)
                                    },
                                    onDragEnd = {
                                        val dropX = dragDeltaX.coerceIn(-125f, 125f)
                                        val dropY = dragDeltaY.coerceIn(-48f, 26f)
                                        manager.finishDraggingMascot(null, dropX, dropY)
                                        dragDeltaX = 0f
                                        dragDeltaY = 0f
                                    },
                                    onDragCancel = {
                                        manager.finishDraggingMascot(null, 0f, 0f)
                                        dragDeltaX = 0f
                                        dragDeltaY = 0f
                                    }
                                )
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        if (isDragging && currentSprite != null) {
                            Image(
                                bitmap = currentSprite!!.asImageBitmap(),
                                contentDescription = selectedChar.displayName(lang),
                                filterQuality = FilterQuality.None,
                                contentScale = ContentScale.Fit,
                                modifier = Modifier
                                    .size(singleSpriteSize)
                                    .offset(x = dragDeltaX.dp, y = dragDeltaY.dp)
                            )
                        }
                    }
                }
            }
        } else if (selectedChar == CharacterFilter.ALL) {
            // 5-Member Standing / Walking / Dance Stage Mode (each girl can be individually lifted & dragged!)
            val deskBmp = app.assetDecryptor.deskSpriteFrame
            if (deskBmp != null) {
                Image(
                    bitmap = deskBmp.asImageBitmap(),
                    contentDescription = null,
                    filterQuality = FilterQuality.None,
                    contentScale = ContentScale.Fit,
                    alpha = 0.55f,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .height(if (isCompactStage) 66.dp else 76.dp)
                        .padding(bottom = 10.dp)
                )
            }

            val walkShift = if (mascotAction == MascotActionState.WALK_LEFT || mascotAction == MascotActionState.WALK_RIGHT) {
                offsetX * 0.42f
            } else 0f

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 4.dp)
                    .padding(bottom = if (isCompactStage) 8.dp else 14.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.Bottom
            ) {
                CharacterFilter.fiveIndividuals.forEach { member ->
                    val frame = allMemberFrames[member.charId]
                    val savedPos = memberPositions[member.charId] ?: Pair(0f, 0f)
                    val isThisDragged = isDragging && draggedMemberId == member.charId
                    val totalX = savedPos.first + if (isThisDragged) dragDeltaX else walkShift
                    val totalY = savedPos.second + if (isThisDragged) dragDeltaY else 0f

                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier
                            .weight(1f)
                            .offset(x = totalX.dp, y = totalY.dp)
                            .clickable { manager.triggerCharacterTap(member) }
                            .pointerInput(member.charId) {
                                detectDragGestures(
                                    onDragStart = {
                                        dragDeltaX = 0f
                                        dragDeltaY = 0f
                                        manager.markDragActive(member.charId)
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        dragDeltaX += with(density) { dragAmount.x.toDp().value }
                                        dragDeltaY += with(density) { dragAmount.y.toDp().value }
                                        manager.markDragActive(member.charId)
                                    },
                                    onDragEnd = {
                                        val oldP = manager.memberPositions.value[member.charId] ?: Pair(0f, 0f)
                                        val newX = (oldP.first + dragDeltaX).coerceIn(-120f, 120f)
                                        val newY = (oldP.second + dragDeltaY).coerceIn(-45f, 30f)
                                        manager.finishDraggingMascot(member.charId, newX, newY)
                                        dragDeltaX = 0f
                                        dragDeltaY = 0f
                                    },
                                    onDragCancel = {
                                        val oldP = manager.memberPositions.value[member.charId] ?: Pair(0f, 0f)
                                        manager.finishDraggingMascot(member.charId, oldP.first, oldP.second)
                                        dragDeltaX = 0f
                                        dragDeltaY = 0f
                                    }
                                )
                            }
                    ) {
                        if (frame != null) {
                            Image(
                                bitmap = frame.asImageBitmap(),
                                contentDescription = member.displayName(lang),
                                filterQuality = FilterQuality.None,
                                contentScale = ContentScale.Fit,
                                modifier = Modifier.size(spriteSize)
                            )
                        }
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(4.dp))
                                .background(characterThemeColor(member).copy(alpha = 0.90f))
                                .padding(horizontal = 5.dp, vertical = 1.dp)
                        ) {
                            Text(member.displayName(lang), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                        }
                    }
                }
            }
        } else {
            // Single Character Mode (Yui, Mio, Ritsu, Mugi, or Azusa) with full Drag-to-Lift support!
            val deskBmp = app.assetDecryptor.deskSpriteFrame
            if (deskBmp != null) {
                Image(
                    bitmap = deskBmp.asImageBitmap(),
                    contentDescription = null,
                    filterQuality = FilterQuality.None,
                    contentScale = ContentScale.Fit,
                    alpha = 0.45f,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .height(if (isCompactStage) 90.dp else 106.dp)
                        .padding(bottom = 10.dp)
                )
            }

            val totalSingleX = offsetX + if (isDragging) dragDeltaX else 0f
            val totalSingleY = offsetY + if (isDragging) dragDeltaY else 0f

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .offset(x = totalSingleX.dp, y = totalSingleY.dp)
                    .padding(bottom = if (isCompactStage) 8.dp else 14.dp)
                    .clickable { manager.triggerCharacterTap(selectedChar) }
                    .pointerInput(selectedChar.charId) {
                        detectDragGestures(
                            onDragStart = {
                                dragDeltaX = 0f
                                dragDeltaY = 0f
                                manager.markDragActive(null)
                            },
                            onDrag = { change, dragAmount ->
                                change.consume()
                                dragDeltaX += with(density) { dragAmount.x.toDp().value }
                                dragDeltaY += with(density) { dragAmount.y.toDp().value }
                                manager.markDragActive(null)
                            },
                            onDragEnd = {
                                val newX = (manager.mascotOffsetX.value + dragDeltaX).coerceIn(-125f, 125f)
                                val newY = (manager.mascotOffsetY.value + dragDeltaY).coerceIn(-45f, 30f)
                                manager.finishDraggingMascot(null, newX, newY)
                                dragDeltaX = 0f
                                dragDeltaY = 0f
                            },
                            onDragCancel = {
                                manager.finishDraggingMascot(null, manager.mascotOffsetX.value, manager.mascotOffsetY.value)
                                dragDeltaX = 0f
                                dragDeltaY = 0f
                            }
                        )
                    }
            ) {
                if (currentSprite != null) {
                    Image(
                        bitmap = currentSprite!!.asImageBitmap(),
                        contentDescription = selectedChar.displayName(lang),
                        filterQuality = FilterQuality.None,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(singleSpriteSize)
                    )
                }
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(5.dp))
                        .background(themeColor.copy(alpha = 0.92f))
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                ) {
                    Text(selectedChar.displayName(lang), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        // 2. Top Pose Pill Control Bar (Drawn LAST inside Box so it sits on top of all sprites and responds to 100% of taps!)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 7.dp)
                .align(Alignment.TopCenter),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            PosePill(title = "待机", isActive = mascotAction == MascotActionState.IDLE) {
                manager.setMascotPose(MascotActionState.IDLE)
            }
            PosePill(
                title = "散步",
                isActive = mascotAction == MascotActionState.WALK_LEFT || mascotAction == MascotActionState.WALK_RIGHT
            ) {
                manager.setMascotPose(MascotActionState.WALK_RIGHT)
            }
            PosePill(title = "招牌动作", isActive = mascotAction == MascotActionState.SPECIAL) {
                manager.setMascotPose(MascotActionState.SPECIAL)
            }
            PosePill(title = "喝下午茶", isActive = mascotAction == MascotActionState.TEA_CAKE) {
                manager.setMascotPose(MascotActionState.TEA_CAKE)
            }

            Spacer(modifier = Modifier.weight(1f))

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(HTTCrimson)
                    .padding(horizontal = 7.dp, vertical = 3.dp)
            ) {
                Text(mascotAction.localizedTitle(lang), color = HTTCream, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
    }
}

@Composable
fun PosePill(title: String, isActive: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(6.dp),
        color = if (isActive) HTTGold else Color.Black.copy(alpha = 0.65f),
        border = androidx.compose.foundation.BorderStroke(1.dp, if (isActive) Color.White else HTTGold.copy(alpha = 0.45f))
    ) {
        Text(
            text = title,
            color = if (isActive) Color.Black else HTTCream,
            fontSize = 11.sp,
            fontWeight = FontWeight.Black,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

@Composable
fun InteractiveMapBoxView(
    manager: AudioPlayerManager,
    stageHeight: Dp,
    onOpenSearch: () -> Unit
) {
    val destName by manager.destinationName.collectAsState()
    val isSimulating by manager.isDemoSimulating.collectAsState()
    val camMode by manager.cameraMode.collectAsState()
    val lang by manager.language.collectAsState()
    val currentSprite by manager.currentSpriteFrame.collectAsState()
    val stepInstruction by manager.currentStepInstruction.collectAsState()
    val tlCountdown by manager.trafficLightCountdown.collectAsState()
    val tlColor by manager.trafficLightColor.collectAsState()
    val trackingUser by manager.mapTrackingUser.collectAsState()
    val tappedCoord by manager.tappedCoord.collectAsState()
    val tappedTitle by manager.tappedTitle.collectAsState()
    val tappedAddress by manager.tappedAddress.collectAsState()

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(stageHeight)
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF141D2B))
            .border(2.dp, HTTGold, RoundedCornerShape(16.dp))
    ) {
        // Real Interactive Map (osmdroid: Mainland China Amap + HK/Macau/Global Google Maps)
        OsmMapView(
            manager = manager,
            modifier = Modifier.fillMaxSize()
        )

        // Top Map Action Bar: Search + Demo + Recenter + Camera + Enlarge
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(6.dp)
                .align(Alignment.TopCenter),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(7.dp))
                    .background(Color.Black.copy(alpha = 0.78f))
                    .border(1.dp, HTTGold.copy(alpha = 0.7f), RoundedCornerShape(7.dp))
                    .clickable { onOpenSearch() }
                    .padding(horizontal = 8.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(Icons.Default.Search, contentDescription = null, tint = HTTGold, modifier = Modifier.size(13.dp))
                Text(
                    if (destName.isEmpty()) "搜索路线..." else destName,
                    color = Color.White,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(7.dp))
                    .background(if (isSimulating) Color(0xFFFF9800) else Color(0xFF8E24AA))
                    .clickable { manager.toggleDemoSimulation() }
                    .padding(horizontal = 6.dp, vertical = 5.dp)
            ) {
                Text(if (isSimulating) "停止" else "模拟", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(7.dp))
                    .background(if (trackingUser) Color(0xFF2E7D32) else Color.Black.copy(alpha = 0.75f))
                    .clickable { manager.triggerFastRecenter() }
                    .padding(horizontal = 6.dp, vertical = 5.dp)
            ) {
                Icon(Icons.Default.MyLocation, contentDescription = null, tint = Color.White, modifier = Modifier.size(13.dp))
            }

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(7.dp))
                    .background(Color(0xFF1976D2))
                    .clickable { manager.toggleCameraMode() }
                    .padding(horizontal = 6.dp, vertical = 5.dp)
            ) {
                Text(camMode.shortTitle(lang), color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(7.dp))
                    .background(HTTCrimson)
                    .clickable { manager.setMapEnlarged(true) }
                    .padding(horizontal = 6.dp, vertical = 5.dp)
            ) {
                Text("放大", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }
        }

        // Tapped POI Card Overlay (Compact)
        if (tappedCoord != null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 38.dp)
                    .align(Alignment.TopCenter)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color.Black.copy(alpha = 0.88f))
                    .border(1.dp, HTTGold, RoundedCornerShape(10.dp))
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(tappedTitle, color = HTTGold, fontSize = 11.sp, fontWeight = FontWeight.Black, maxLines = 1)
                    Text(tappedAddress, color = Color.LightGray, fontSize = 9.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(HTTCrimson)
                            .clickable { manager.startRouteToPlace(tappedTitle, tappedCoord!!) }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text("去这里", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color.DarkGray)
                            .clickable { manager.clearTappedPOI() }
                            .padding(horizontal = 6.dp, vertical = 4.dp)
                    ) {
                        Text("✕", color = Color.White, fontSize = 10.sp)
                    }
                }
            }
        }

        // Bottom-left Mascot Companion + Bottom-right Traffic Light & Step
        if (currentSprite != null) {
            Image(
                bitmap = currentSprite!!.asImageBitmap(),
                contentDescription = null,
                filterQuality = FilterQuality.None,
                modifier = Modifier
                    .size(88.dp)
                    .align(Alignment.BottomStart)
                    .padding(start = 8.dp, bottom = 6.dp)
                    .clickable { manager.triggerCharacterTap(null) }
            )
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(8.dp),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.Black.copy(alpha = 0.78f))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(stepInstruction, color = HTTCream, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
    }
}

@Composable
fun TrafficLightCapsule(colorState: Int, countdown: Int) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF070A12))
            .border(1.dp, HTTGold.copy(alpha = 0.6f), RoundedCornerShape(16.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Box(modifier = Modifier.size(9.dp).clip(CircleShape).background(if (colorState == 0) Color(0xFFFF1744) else Color(0xFF3A1018)))
        Box(modifier = Modifier.size(9.dp).clip(CircleShape).background(if (colorState == 1) Color(0xFFFFD600) else Color(0xFF3A3210)))
        Box(modifier = Modifier.size(9.dp).clip(CircleShape).background(if (colorState == 2) Color(0xFF00E676) else Color(0xFF103A20)))
        Text(
            text = "${countdown}s",
            color = when (colorState) {
                0 -> Color(0xFFFF1744)
                1 -> Color(0xFFFFD600)
                else -> Color(0xFF00E676)
            },
            fontWeight = FontWeight.Black,
            fontFamily = FontFamily.Monospace,
            fontSize = 12.sp,
            maxLines = 1
        )
    }
}

@Composable
fun SpeechBubbleBox(manager: AudioPlayerManager) {
    val selectedChar by manager.selectedCharacter.collectAsState()
    val lang by manager.language.collectAsState()
    val bubbleText by manager.currentSpeechBubble.collectAsState()
    val isPlaying by manager.isPlaying.collectAsState()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(HTTCream)
            .border(1.2.dp, HTTGold, RoundedCornerShape(10.dp))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    selectedChar.roleTag(lang),
                    color = HTTCrimson,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 1
                )
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(HTTCrimson.copy(alpha = 0.14f))
                        .clickable { manager.resetPositions() }
                        .padding(horizontal = 5.dp, vertical = 1.dp)
                ) {
                    Text("位置归位", color = HTTCrimson, fontSize = 8.5.sp, fontWeight = FontWeight.Bold)
                }
            }
            Text(
                text = bubbleText,
                color = Color.Black.copy(alpha = 0.88f),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        if (isPlaying) {
            IconButton(onClick = { manager.stopAudio() }, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Default.StopCircle, contentDescription = null, tint = Color.Red)
            }
        }
    }
}

@Composable
fun CharacterSelectorStrip(manager: AudioPlayerManager) {
    val selectedChar by manager.selectedCharacter.collectAsState()
    val lang by manager.language.collectAsState()

    LazyRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        items(CharacterFilter.values().toList()) { char ->
            val isSel = selectedChar == char
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isSel) characterThemeColor(char) else Color.White.copy(alpha = 0.12f))
                    .border(
                        width = 1.5.dp,
                        color = if (isSel) HTTGold else Color.Transparent,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .clickable { manager.selectCharacter(char) }
                    .padding(horizontal = 11.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    if (char == CharacterFilter.ALL) Icons.Default.Groups else Icons.Default.Person,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = char.displayName(lang),
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
fun UtilityControlGrid(
    manager: AudioPlayerManager,
    isCompact: Boolean,
    onOpenSearch: () -> Unit
) {
    val isCruise by manager.isCruiseModeActive.collectAsState()
    val cruiseMins by manager.cruiseIntervalMinutes.collectAsState()
    val cruiseRem by manager.cruiseRemainingSeconds.collectAsState()
    var showIntervalMenu by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(if (isCompact) 4.dp else 5.dp)) {
        // Row 1: 3 Tactical Buttons (出发进行 / 多人相声 / 顶蛋糕下午茶)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(if (isCompact) 5.dp else 7.dp)
        ) {
            TacticalButton(
                title = "出发进行",
                subtitle = "点火出发音",
                icon = Icons.Default.Flag,
                bgColor = HTTCrimson,
                modifier = Modifier.weight(1f),
                onClick = { manager.triggerDepartureGreeting() }
            )
            TacticalButton(
                title = "多人相声",
                subtitle = "多人对话彩蛋",
                icon = Icons.Default.Forum,
                bgColor = Color(0xFF9452C7),
                modifier = Modifier.weight(1f),
                onClick = { manager.triggerBanter() }
            )
            TacticalButton(
                title = "喝下午茶",
                subtitle = "桌宠蛋糕休息",
                icon = Icons.Default.Cake,
                bgColor = Color(0xFFD18F2E),
                modifier = Modifier.weight(1f),
                onClick = { manager.triggerTeaTimeReminder() }
            )
        }

        // Row 2: Left = Cruise Companion + Interval Menu; Right = Destination Route Navigation
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(if (isCompact) 5.dp else 7.dp)
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(11.dp))
                    .background(if (isCruise) Color(0xFF4CAF50).copy(alpha = 0.28f) else Color.White.copy(alpha = 0.1f))
                    .border(1.4.dp, if (isCruise) Color(0xFF4CAF50) else HTTGold.copy(alpha = 0.4f), RoundedCornerShape(11.dp))
                    .padding(horizontal = 8.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .clickable { manager.toggleCruiseMode() },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp)
                ) {
                    Icon(
                        if (isCruise) Icons.Default.Timer else Icons.Default.PlayCircleFilled,
                        contentDescription = null,
                        tint = if (isCruise) Color(0xFF4CAF50) else HTTGold,
                        modifier = Modifier.size(16.dp)
                    )
                    Column {
                        val remStr = remember(cruiseRem) { manager.formattedCruiseCountdown() }
                        Text(
                            if (isCruise) "巡航: $remStr" else "开启巡航陪伴",
                            color = Color.White,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1
                        )
                        Text(
                            "后台保活·定时播报",
                            color = Color.White.copy(alpha = 0.75f),
                            fontSize = 9.sp,
                            maxLines = 1
                        )
                    }
                }

                Box {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(5.dp))
                            .background(Color.Black.copy(alpha = 0.38f))
                            .clickable { showIntervalMenu = true }
                            .padding(horizontal = 5.dp, vertical = 3.dp)
                    ) {
                        Text("${cruiseMins}m▾", color = HTTGold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                    DropdownMenu(expanded = showIntervalMenu, onDismissRequest = { showIntervalMenu = false }) {
                        listOf(1, 3, 5, 10, 15, 30).forEach { m ->
                            DropdownMenuItem(
                                text = { Text("$m 分钟") },
                                onClick = {
                                    manager.setCruiseInterval(m)
                                    showIntervalMenu = false
                                }
                            )
                        }
                    }
                }
            }

            // Right: Destination Route Navigation
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(11.dp))
                    .background(HTTCrimson)
                    .border(1.4.dp, HTTGold.copy(alpha = 0.8f), RoundedCornerShape(11.dp))
                    .clickable { onOpenSearch() }
                    .padding(horizontal = 8.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Icon(Icons.Default.Navigation, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                Column {
                    Text("目的地路线导航", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                    Text("真实路口触发轻音指路", color = Color.White.copy(alpha = 0.85f), fontSize = 9.sp, maxLines = 1)
                }
            }
        }
    }
}

@Composable
fun TacticalButton(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    bgColor: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(bgColor)
            .border(1.dp, HTTGold.copy(alpha = 0.72f), RoundedCornerShape(10.dp))
            .clickable { onClick() }
            .padding(vertical = 4.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Icon(icon, contentDescription = null, tint = HTTCream, modifier = Modifier.size(12.dp))
            Text(title, color = Color.White, fontSize = 10.5.sp, fontWeight = FontWeight.Black, maxLines = 1)
        }
        Text(subtitle, color = HTTCream.copy(alpha = 0.85f), fontSize = 8.sp, maxLines = 1)
    }
}

@Composable
fun OutfitCameraGiftRow(
    manager: AudioPlayerManager,
    onOpenWardrobe: () -> Unit
) {
    val outfit by manager.arrowOutfit.collectAsState()
    val camMode by manager.cameraMode.collectAsState()
    val lang by manager.language.collectAsState()

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // 1. Outfit Button
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(10.dp))
                .background(Color.Black.copy(alpha = 0.75f))
                .border(1.2.dp, HTTGold.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
                .clickable { onOpenWardrobe() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Icon(Icons.Default.Checkroom, contentDescription = null, tint = HTTGold, modifier = Modifier.size(14.dp))
            Column {
                Text("车标换装", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black, maxLines = 1)
                Text(outfit.title(lang), color = HTTGold, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }

        // 2. Camera Mode Button
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(10.dp))
                .background(Color.Black.copy(alpha = 0.75f))
                .border(1.2.dp, Color(0xFF00E5FF).copy(alpha = 0.6f), RoundedCornerShape(10.dp))
                .clickable { manager.toggleCameraMode() }
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Icon(Icons.Default.Explore, contentDescription = null, tint = Color(0xFF00E5FF), modifier = Modifier.size(14.dp))
            Column {
                Text("视角模式", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black, maxLines = 1)
                Text(camMode.title(lang), color = Color(0xFF00E5FF), fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }

        // 3. Special Birthday Voice Button [特典音]
        Column(
            modifier = Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(Color.Black.copy(alpha = 0.75f))
                .border(1.2.dp, Color(0xFFFF4081).copy(alpha = 0.75f), RoundedCornerShape(10.dp))
                .clickable { manager.triggerBirthdaySpecialVoice() }
                .padding(horizontal = 10.dp, vertical = 5.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(Icons.Default.CardGiftcard, contentDescription = null, tint = Color(0xFFFF4081), modifier = Modifier.size(14.dp))
            Text("特典音", color = Color(0xFFFF80AB), fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun TravelModesRow(manager: AudioPlayerManager) {
    val currentMode by manager.travelMode.collectAsState()
    val lang by manager.language.collectAsState()

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        NavigationTravelMode.values().forEach { mode ->
            val sel = currentMode == mode
            val icon = when (mode) {
                NavigationTravelMode.DRIVING -> Icons.Default.DirectionsCar
                NavigationTravelMode.EBIKE -> Icons.Default.TwoWheeler
                NavigationTravelMode.WALKING -> Icons.Default.DirectionsWalk
                NavigationTravelMode.TRANSIT -> Icons.Default.DirectionsBus
            }
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(9.dp))
                    .background(if (sel) HTTCrimson else Color.Black.copy(alpha = 0.78f))
                    .border(1.2.dp, if (sel) HTTGold else Color.White.copy(alpha = 0.22f), RoundedCornerShape(9.dp))
                    .clickable { manager.setTravelMode(mode) }
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(icon, contentDescription = null, tint = if (sel) Color.White else HTTCream, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text(
                    mode.title(lang),
                    color = if (sel) Color.White else HTTCream,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
fun MiniMusicPlayerStrip(
    musicMgr: KOnMusicManager,
    onOpenMusicSheet: () -> Unit
) {
    val currentTrack by musicMgr.currentTrack.collectAsState()
    val isPlaying by musicMgr.isPlaying.collectAsState()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Color.Black.copy(alpha = 0.72f))
            .border(1.dp, HTTGold.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .clickable { onOpenMusicSheet() },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(Icons.Default.Album, contentDescription = null, tint = HTTGold, modifier = Modifier.size(18.dp))
            Column {
                Text(
                    currentTrack.title,
                    color = Color.White,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    "${currentTrack.artist} · 点按展开27首轻音曲库",
                    color = HTTGold.copy(alpha = 0.85f),
                    fontSize = 9.sp,
                    maxLines = 1
                )
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { musicMgr.togglePlayPause() }, modifier = Modifier.size(28.dp)) {
                Icon(
                    if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = null,
                    tint = Color.White
                )
            }
            IconButton(onClick = { musicMgr.nextTrack() }, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Default.SkipNext, contentDescription = null, tint = HTTGold)
            }
        }
    }
}

@Composable
fun AuthorAndFeedbackBar(
    manager: AudioPlayerManager,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, HTTGold.copy(alpha = 0.45f), RoundedCornerShape(8.dp))
            .clickable { onClick() }
            .padding(horizontal = 10.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = HTTGold, modifier = Modifier.size(11.dp))
        Spacer(Modifier.width(5.dp))
        Text(manager.appAuthorLabel(), color = HTTGold, fontSize = 10.sp, fontWeight = FontWeight.Black)
        Text(" · ", color = Color.Gray, fontSize = 10.sp)
        Text("v${manager.appVersion}", color = Color.White.copy(alpha = 0.85f), fontSize = 10.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
        Text(" · ", color = Color.Gray, fontSize = 10.sp)
        Icon(Icons.Default.BugReport, contentDescription = null, tint = Color(0xFFFF9800), modifier = Modifier.size(12.dp))
        Spacer(Modifier.width(2.dp))
        Text("BUG反馈 & 社区二维码", color = Color(0xFF66CCFF), fontSize = 10.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun EnlargedNavigationHUDView(
    manager: AudioPlayerManager,
    musicMgr: KOnMusicManager,
    isLandscape: Boolean,
    onOpenSearch: () -> Unit,
    onOpenMusic: () -> Unit
) {
    val stepInstruction by manager.currentStepInstruction.collectAsState()
    val distMeters by manager.distanceToNextStepMeters.collectAsState()
    val speed by manager.currentSpeedKmh.collectAsState()
    val speedLimit by manager.speedLimitKmh.collectAsState()
    val currentSprite by manager.currentSpriteFrame.collectAsState()
    val bubbleText by manager.currentSpeechBubble.collectAsState()
    val camDist by manager.upcomingCameraDistance.collectAsState()
    val remKm by manager.remainingRouteDistanceKm.collectAsState()
    val remMins by manager.remainingRouteMinutes.collectAsState()
    val candidateRoutes by manager.candidateRoutes.collectAsState()
    val isRoutePreviewing by manager.isRoutePreviewing.collectAsState()
    val transitFirstLegUseBike by manager.transitFirstLegUseBike.collectAsState()
    val drivingAvoids by manager.drivingAvoidOptions.collectAsState()
    val destName by manager.destinationName.collectAsState()
    val selectedRouteIdx by manager.selectedRouteIndex.collectAsState()
    val tappedCoord by manager.tappedCoord.collectAsState()
    val tappedTitle by manager.tappedTitle.collectAsState()
    val tappedAddress by manager.tappedAddress.collectAsState()
    val travelMode by manager.travelMode.collectAsState()
    val isDemo by manager.isDemoSimulating.collectAsState()
    val hasNav by manager.hasActiveNavigation.collectAsState()
    val heading by manager.headingDegrees.collectAsState()

    val distLabel = if (distMeters >= 1000) String.format("%.1f公里", distMeters / 1000.0) else "${distMeters}米"
    val compassDir = when (((heading % 360.0 + 360.0) % 360.0)) {
        in 22.5..67.5 -> "东北 NE"
        in 67.5..112.5 -> "东 E"
        in 112.5..157.5 -> "东南 SE"
        in 157.5..202.5 -> "南 S"
        in 202.5..247.5 -> "西南 SW"
        in 247.5..292.5 -> "西 W"
        in 292.5..337.5 -> "西北 NW"
        else -> "北 N"
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0E1622))
    ) {
        // Real Full-Screen Interactive Map (Amap in China / Google Maps Overseas)
        OsmMapView(
            manager = manager,
            modifier = Modifier.fillMaxSize()
        )

        // Top Overlay Stack (1:1 iOS Enlarged Navigation Layout)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (!hasNav || isRoutePreviewing) {
            // Row 1: 4 Travel Mode Pills (开车 / 骑车 / 步行 / 公交/地铁) matching iOS
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                NavigationTravelMode.values().forEach { mode ->
                    val sel = travelMode == mode
                    val (icon, title) = when (mode) {
                        NavigationTravelMode.DRIVING -> Icons.Default.DirectionsCar to "开车"
                        NavigationTravelMode.EBIKE -> Icons.Default.TwoWheeler to "骑车"
                        NavigationTravelMode.WALKING -> Icons.Default.DirectionsWalk to "步行"
                        NavigationTravelMode.TRANSIT -> Icons.Default.DirectionsTransit to "公交/地铁"
                    }
                    Row(
                        modifier = Modifier
                            .weight(if (mode == NavigationTravelMode.TRANSIT) 1.25f else 1f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (sel) HTTCrimson else Color(0xFF141824).copy(alpha = 0.88f))
                            .border(1.dp, if (sel) HTTGold else Color.White.copy(alpha = 0.16f), RoundedCornerShape(10.dp))
                            .clickable { manager.setTravelMode(mode) }
                            .padding(vertical = 7.dp, horizontal = 4.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(3.dp))
                        Text(title, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
                    }
                }
            }

            }

            // Active Turn-by-Turn Banner at VERY TOP (1:1 iOS Layout — never blocks center map!)
            if (hasNav && !isRoutePreviewing) {
                val etaCal = java.util.Calendar.getInstance().apply { add(java.util.Calendar.MINUTE, remMins.coerceAtLeast(1)) }
                val etaStr = String.format("%02d:%02d", etaCal.get(java.util.Calendar.HOUR_OF_DAY), etaCal.get(java.util.Calendar.MINUTE))
                Surface(
                    color = Color(0xFF0F141E).copy(alpha = 0.94f),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(1.2.dp, HTTGold.copy(alpha = 0.85f), RoundedCornerShape(14.dp))
                ) {
                    Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val turnIcon = when {
                                travelMode == NavigationTravelMode.TRANSIT -> Icons.Default.DirectionsTransit
                                travelMode == NavigationTravelMode.WALKING -> Icons.Default.DirectionsWalk
                                travelMode == NavigationTravelMode.EBIKE -> Icons.Default.DirectionsBike
                                stepInstruction.contains("调头") || stepInstruction.contains("掉头") -> Icons.Default.UTurnLeft
                                stepInstruction.contains("左") && !stepInstruction.contains("右") -> Icons.Default.TurnLeft
                                stepInstruction.contains("右") && !stepInstruction.contains("左") -> Icons.Default.TurnRight
                                else -> Icons.Default.ArrowUpward
                            }
                            Box(
                                modifier = Modifier
                                    .size(34.dp)
                                    .clip(CircleShape)
                                    .background(HTTCrimson),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(turnIcon, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(stepInstruction, color = Color.White, fontSize = 12.5.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text(distLabel, color = Color(0xFF4ADE80), fontSize = 12.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
                                    if (remKm > 0.05) {
                                        Text(String.format("· 余 %.1fkm · %d分 · 预计 %s 到达", remKm, remMins.coerceAtLeast(1), etaStr), color = HTTGold, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                            }
                            Box(
                                modifier = Modifier
                                    .size(26.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFF8B1A24))
                                    .clickable { manager.stopNavigation() },
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(Icons.Default.Close, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
                            }
                        }
                        if (candidateRoutes.size > 1) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                candidateRoutes.forEachIndexed { idx, r ->
                                    val sel = idx == selectedRouteIdx
                                    val durMins = (r.durationSeconds / 60).toInt().coerceAtLeast(1)
                                    Box(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(7.dp))
                                            .background(if (sel) HTTCrimson else Color.White.copy(alpha = 0.08f))
                                            .border(1.dp, if (sel) HTTGold else Color.Transparent, RoundedCornerShape(7.dp))
                                            .clickable { manager.selectRoute(idx) }
                                            .padding(vertical = 3.dp, horizontal = 4.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text("${r.name} · ${durMins}分", color = Color.White, fontSize = 9.5.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Row 2: Left Status Badges + Right Quick Action Pills (搜索 / 音乐 / 返回驾驶舱)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                // Left Telemetry Badges (matching iOS)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF141824).copy(alpha = 0.90f))
                            .border(1.dp, Color(0xFFEF4444).copy(alpha = 0.85f), RoundedCornerShape(10.dp))
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(24.dp)
                                .clip(CircleShape)
                                .background(Color.White)
                                .border(2.dp, Color(0xFFDC2626), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("$speedLimit", color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Black)
                        }
                        Column {
                            Text("测速电子眼", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            Text("距离 ${camDist}m", color = Color(0xFFFF8A80), fontSize = 9.sp)
                        }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(12.dp))
                                .background(Color(0xFF0F291E).copy(alpha = 0.90f))
                                .border(1.dp, Color(0xFF22C55E).copy(alpha = 0.55f), RoundedCornerShape(12.dp))
                                .padding(horizontal = 7.dp, vertical = 3.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(Color(0xFF4ADE80)))
                            Text("道路畅通", color = Color(0xFF86EFAC), fontSize = 9.5.sp, fontWeight = FontWeight.Bold)
                        }
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(12.dp))
                                .background(Color(0xFF0F291E).copy(alpha = 0.90f))
                                .border(1.dp, Color(0xFF22C55E).copy(alpha = 0.55f), RoundedCornerShape(12.dp))
                                .padding(horizontal = 7.dp, vertical = 3.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(Icons.Default.GpsFixed, contentDescription = null, tint = Color(0xFF4ADE80), modifier = Modifier.size(11.dp))
                            Text("GPS正常", color = Color(0xFF86EFAC), fontSize = 9.5.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                // Right Action Bar + Vertical Map Controls (matching iOS)
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color(0xFF141824).copy(alpha = 0.90f))
                                .border(1.dp, HTTGold.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                                .clickable { onOpenSearch() }
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(Icons.Default.Search, contentDescription = null, tint = Color.White, modifier = Modifier.size(13.dp))
                            Text("搜索", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }

                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color(0xFF141824).copy(alpha = 0.90f))
                                .border(1.dp, HTTGold.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                                .clickable { onOpenMusic() }
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(Icons.Default.MusicNote, contentDescription = null, tint = HTTGold, modifier = Modifier.size(13.dp))
                            Text("音乐", color = HTTGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }

                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color(0xFF141824).copy(alpha = 0.90f))
                                .border(1.dp, HTTGold.copy(alpha = 0.55f), RoundedCornerShape(10.dp))
                                .clickable { manager.setMapEnlarged(false) }
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(Icons.Default.FullscreenExit, contentDescription = null, tint = HTTGold, modifier = Modifier.size(13.dp))
                            Text("返回驾驶舱", color = HTTGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }

                    // Compass + 回中 + Zoom Pill + 模拟 + 结束 (Vertical Right Rail matching iOS)
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF141824).copy(alpha = 0.90f))
                            .border(1.dp, Color.White.copy(alpha = 0.18f), CircleShape)
                            .clickable { manager.toggleCameraMode() },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Navigation, contentDescription = null, tint = Color(0xFFEF4444), modifier = Modifier.size(18.dp))
                    }

                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF141824).copy(alpha = 0.90f))
                            .border(1.dp, HTTGold.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                            .clickable { manager.triggerFastRecenter() }
                            .padding(horizontal = 9.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Icon(Icons.Default.NearMe, contentDescription = null, tint = HTTGold, modifier = Modifier.size(12.dp))
                        Text("回中", color = HTTGold, fontSize = 10.5.sp, fontWeight = FontWeight.Bold)
                    }

                    Column(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF141824).copy(alpha = 0.90f))
                            .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(10.dp)),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Box(
                            modifier = Modifier
                                .size(34.dp, 30.dp)
                                .clickable { manager.triggerZoom(1) },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
                        }
                        Divider(color = Color.White.copy(alpha = 0.15f), modifier = Modifier.width(24.dp))
                        Box(
                            modifier = Modifier
                                .size(34.dp, 30.dp)
                                .clickable { manager.triggerZoom(-1) },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Remove, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
                        }
                    }

                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (isDemo) HTTCrimson else Color(0xFF141824).copy(alpha = 0.90f))
                            .border(1.dp, HTTGold.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                            .clickable { manager.toggleDemoSimulation() }
                            .padding(horizontal = 9.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Icon(if (isDemo) Icons.Default.Stop else Icons.Default.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(13.dp))
                        Text(if (isDemo) "停止" else "模拟", color = Color.White, fontSize = 10.5.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

        }

        // Amap-Style Interactive Route Preview Sheet (Preserves K-ON! Outline: Top Pills, Right Controls, Bottom Music + Speed + Bubble + Mascot)
        if (hasNav && isRoutePreviewing && candidateRoutes.isNotEmpty()) {
            val selectedRoute = candidateRoutes.getOrNull(selectedRouteIdx) ?: candidateRoutes.first()
            val directKm = selectedRoute.totalDistanceMeters / 1000.0
            Surface(
                color = Color(0xFF101522).copy(alpha = 0.96f),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(start = 10.dp, end = 10.dp, bottom = 128.dp)
                    .border(1.2.dp, HTTGold.copy(alpha = 0.78f), RoundedCornerShape(16.dp))
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 11.dp, vertical = 9.dp),
                    verticalArrangement = Arrangement.spacedBy(7.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "路线预览 · $destName",
                                color = HTTGold,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Black,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                "共 ${candidateRoutes.size} 套方案 · 选定方案后点击下方「开始导航」",
                                color = Color(0xFFD1D5DB),
                                fontSize = 9.5.sp
                            )
                        }
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(7.dp))
                                .background(Color.White.copy(alpha = 0.12f))
                                .clickable { manager.stopNavigation() }
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            Text("取消", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }
                    }

                    if (travelMode == NavigationTravelMode.DRIVING) {
                        Row(
                            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            listOf(
                                DrivingAvoidanceOption.AVOID_CONGESTION to "躲避拥堵",
                                DrivingAvoidanceOption.AVOID_HIGHWAY to "不走高速",
                                DrivingAvoidanceOption.AVOID_TOLL to "少收费"
                            ).forEach { (opt, label) ->
                                val active = drivingAvoids.contains(opt)
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(if (active) Color(0xFF1D4ED8) else Color.White.copy(alpha = 0.08f))
                                        .border(1.dp, if (active) Color(0xFF60A5FA) else Color.White.copy(alpha = 0.18f), RoundedCornerShape(8.dp))
                                        .clickable { manager.toggleDrivingAvoidOption(opt) }
                                        .padding(horizontal = 8.dp, vertical = 4.dp)
                                ) {
                                    Text(label, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                    }

                    if (travelMode == NavigationTravelMode.TRANSIT) {
                        if (directKm > 0.0 && directKm < 3.5) {
                            val walkM = (selectedRoute.totalDistanceMeters / 76.0).toInt().coerceAtLeast(1)
                            val bikeM = (selectedRoute.totalDistanceMeters / 250.0).toInt().coerceAtLeast(1)
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(9.dp))
                                    .background(Color(0xFF3A2510))
                                    .border(1.dp, HTTGold.copy(alpha = 0.55f), RoundedCornerShape(9.dp))
                                    .padding(horizontal = 8.dp, vertical = 5.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Text("距离较近", color = HTTGold, fontSize = 10.sp, fontWeight = FontWeight.Black)
                                Spacer(Modifier.weight(1f))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(Color(0xFF15803D))
                                        .clickable { manager.switchTransitToDirectMode(NavigationTravelMode.WALKING) }
                                        .padding(horizontal = 7.dp, vertical = 4.dp)
                                ) {
                                    Text("步行 ${walkM}分", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                }
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(Color(0xFF0F766E))
                                        .clickable { manager.switchTransitToDirectMode(NavigationTravelMode.EBIKE) }
                                        .padding(horizontal = 7.dp, vertical = 4.dp)
                                ) {
                                    Text("骑行 ${bikeM}分", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text("第一步去上车站：", color = HTTCream, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (!transitFirstLegUseBike) Color(0xFF2563EB) else Color.White.copy(alpha = 0.1f))
                                    .clickable { manager.setTransitFirstLegUseBike(false) }
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Text("🚶 步行前往", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            }
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (transitFirstLegUseBike) Color(0xFF0D9488) else Color.White.copy(alpha = 0.1f))
                                    .clickable { manager.setTransitFirstLegUseBike(true) }
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Text("🚲 骑车前往", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        candidateRoutes.take(3).forEachIndexed { idx, r ->
                            val isSel = idx == selectedRouteIdx
                            val mins = (r.durationSeconds / 60.0).toInt().coerceAtLeast(1)
                            val kmStr = String.format("%.1f公里", r.totalDistanceMeters / 1000.0)
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (isSel) Color(0xFF1E293B) else Color.White.copy(alpha = 0.06f))
                                    .border(if (isSel) 1.5.dp else 1.dp, if (isSel) HTTGold else Color.White.copy(alpha = 0.15f), RoundedCornerShape(10.dp))
                                    .clickable { manager.selectRoute(idx) }
                                    .padding(horizontal = 8.dp, vertical = 6.dp),
                                verticalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Text(r.name, color = if (isSel) HTTGold else Color(0xFF9CA3AF), fontSize = 9.5.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("${mins}分钟", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Black)
                                Text(kmStr, color = Color(0xFFD1D5DB), fontSize = 10.sp)
                            }
                        }
                    }

                    if (travelMode == NavigationTravelMode.TRANSIT && selectedRoute.steps.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            selectedRoute.steps.take(3).forEachIndexed { idx, st ->
                                Text(
                                    "${idx + 1}. ${st.instruction}",
                                    color = if (idx == 1) Color(0xFF7DD3FC) else HTTCream,
                                    fontSize = 10.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }

                    Button(
                        onClick = { manager.confirmStartNavigation() },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF16A34A)),
                        shape = RoundedCornerShape(10.dp),
                        modifier = Modifier.fillMaxWidth().height(38.dp),
                        contentPadding = PaddingValues(0.dp)
                    ) {
                        Text("🚀 开始导航（${selectedRoute.name}）", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black)
                    }
                }
            }
        }

        // Bottom Stack (1:1 iOS Layout: Music Player Strip + Speedometer + Cream Speech Bubble + Right Mascot!)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            MiniMusicPlayerStrip(
                musicMgr = musicMgr,
                onOpenMusicSheet = onOpenMusic
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Left Speedometer Card (matching iOS)
                Column(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF141824).copy(alpha = 0.92f))
                        .border(1.dp, HTTGold.copy(alpha = 0.65f), RoundedCornerShape(14.dp))
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                    horizontalAlignment = Alignment.Start
                ) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text("$speed", color = Color(0xFF4ADE80), fontSize = 26.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
                        Text("km/h", color = HTTCream, fontSize = 10.sp, modifier = Modifier.padding(bottom = 4.dp))
                    }
                    Text("限速: $speedLimit  $compassDir", color = HTTGold, fontSize = 9.5.sp, fontWeight = FontWeight.Bold, softWrap = false)
                }

                // Middle Cream Speech Bubble (matching iOS!)
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(14.dp))
                        .background(HTTCream.copy(alpha = 0.95f))
                        .border(1.dp, HTTGold, RoundedCornerShape(14.dp))
                        .padding(horizontal = 10.dp, vertical = 8.dp)
                ) {
                    Text(
                        bubbleText,
                        color = Color(0xFF231815),
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // Right Mascot Sprite (matching iOS!)
                if (currentSprite != null) {
                    Image(
                        bitmap = currentSprite!!.asImageBitmap(),
                        contentDescription = null,
                        filterQuality = FilterQuality.None,
                        modifier = Modifier
                            .size(56.dp)
                            .clickable { manager.triggerCharacterTap(null) }
                    )
                }
            }
        }
    }
}
