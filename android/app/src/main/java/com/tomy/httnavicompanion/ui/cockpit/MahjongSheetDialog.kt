package com.tomy.httnavicompanion.ui.cockpit

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.*

private val MjBgGreen = Color(0xFF0C3B26)
private val MjCardGreen = Color(0xFF072618)
private val MjGold = Color(0xFFE0B861)
private val MjRed = Color(0xFFCC2D34)
private val MjBlue = Color(0xFF1877F2)
private val MjCream = Color(0xFFFAF2E0)

@Composable
fun KOnGameRoomSheetDialog(onDismiss: () -> Unit) {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val ddzEngine = manager.doudizhuEngine
    val mjEngine = manager.mahjongEngine
    val lang by manager.language.collectAsState()
    var selectedGame by remember { mutableStateOf(0) } // 0 = 斗地主, 1 = 广东红中麻将

    fun tr(hans: String, hant: String, en: String): String = when (lang) {
        AppLanguage.ZH_HANS -> hans
        AppLanguage.ZH_HANT -> hant
        AppLanguage.EN -> en
    }

    val context = LocalContext.current
    val ddzPhase by ddzEngine.phase.collectAsState()
    val mjPhase by mjEngine.phase.collectAsState()
    val ddzHosting by ddzEngine.isHostingRoom.collectAsState()
    val ddzServerConn by ddzEngine.isServerConnected.collectAsState()
    val ddzPeers by ddzEngine.connectedPeerNames.collectAsState()
    val mjHosting by mjEngine.isHostingRoom.collectAsState()
    val mjServerConn by mjEngine.isServerConnected.collectAsState()
    val mjPeers by mjEngine.connectedPeerNames.collectAsState()
    val inLobbyNow = (selectedGame == 0 && ddzPhase == DoudizhuGamePhase.LOBBY) || (selectedGame == 1 && mjPhase == MahjongGamePhase.LOBBY)
    val isInJoinedRoom = !inLobbyNow ||
        (selectedGame == 0 && (ddzHosting || ddzServerConn || ddzPeers.isNotEmpty())) ||
        (selectedGame == 1 && (mjHosting || mjServerConn || mjPeers.isNotEmpty()))

    val activity = remember(context) {
        var ctx: Context? = context
        var act: Activity? = null
        while (ctx is ContextWrapper) {
            if (ctx is Activity) { act = ctx; break }
            ctx = ctx.baseContext
        }
        act
    }
    val prevOrientation = remember { activity?.requestedOrientation ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }

    LaunchedEffect(inLobbyNow) {
        if (!inLobbyNow) {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else {
            activity?.requestedOrientation = prevOrientation
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            activity?.requestedOrientation = prevOrientation
            ddzEngine.leaveRoomAndResetLobby()
            mjEngine.leaveRoomAndResetLobby()
        }
    }

    Dialog(
        onDismissRequest = {
            ddzEngine.leaveRoomAndResetLobby()
            mjEngine.leaveRoomAndResetLobby()
            onDismiss()
        },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = if (selectedGame == 0) Color(0xFF104B2C) else MjBgGreen
        ) {
            Column(modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                // Unified Header
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (!inLobbyNow) {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(16.dp))
                                .background(MjCardGreen)
                                .clickable {
                                    if (selectedGame == 0) ddzEngine.leaveRoomAndResetLobby()
                                    else mjEngine.leaveRoomAndResetLobby()
                                }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        ) {
                            Text(tr("< 退出房间", "< 退出房間", "< Leave"), color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    } else {
                        Spacer(Modifier.width(72.dp))
                    }
                    Text(
                        tr("放课后茶会 · 放课后棋牌室", "放課後茶會 · 放課後棋牌室", "HTT · Game Room"),
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Black,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (inLobbyNow) {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(16.dp))
                                .background(MjCardGreen)
                                .clickable {
                                    ddzEngine.leaveRoomAndResetLobby()
                                    mjEngine.leaveRoomAndResetLobby()
                                    onDismiss()
                                }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        ) {
                            Text(tr("✕ 关闭", "✕ 關閉", "✕ Close"), color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    } else {
                        Spacer(Modifier.width(72.dp))
                    }
                }

                // Game Switcher Bar (hidden once user enters/hosts a room or starts an active game)
                if (!isInJoinedRoom) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(9.dp))
                            .background(if (selectedGame == 0) MjRed else Color.Black.copy(alpha = 0.42f))
                            .border(
                                if (selectedGame == 0) 1.5.dp else 1.dp,
                                if (selectedGame == 0) MjGold else MjGold.copy(alpha = 0.35f),
                                RoundedCornerShape(9.dp)
                            )
                            .clickable {
                                if (selectedGame != 0) {
                                    mjEngine.leaveRoomAndResetLobby()
                                    selectedGame = 0
                                }
                            }
                            .padding(vertical = 7.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            tr("🃏 放课后斗地主 (3人)", "🃏 放課後鬥地主 (3人)", "🃏 Doudizhu (3P)"),
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Black
                        )
                    }
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(9.dp))
                            .background(if (selectedGame == 1) Color(0xFF146C43) else Color.Black.copy(alpha = 0.42f))
                            .border(
                                if (selectedGame == 1) 1.5.dp else 1.dp,
                                if (selectedGame == 1) MjGold else MjGold.copy(alpha = 0.35f),
                                RoundedCornerShape(9.dp)
                            )
                            .clickable {
                                if (selectedGame != 1) {
                                    ddzEngine.leaveRoomAndResetLobby()
                                    selectedGame = 1
                                }
                            }
                            .padding(vertical = 7.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            tr("🀄 广东红中麻将 (4人)", "🀄 廣東紅中麻將 (4人)", "🀄 Mahjong (4P)"),
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Black
                        )
                    }
                }

                }

                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    if (selectedGame == 0) {
                        KOnDoudizhuSheetDialog(onDismiss = onDismiss, embeddedInGameRoom = true)
                    } else {
                        KOnMahjongSheetDialog(onDismiss = onDismiss, embeddedInGameRoom = true)
                    }
                }
            }
        }
    }
}

@Composable
fun KOnMahjongSheetDialog(onDismiss: () -> Unit, embeddedInGameRoom: Boolean = false) {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val engine = manager.mahjongEngine
    val lang by manager.language.collectAsState()
    val allMemberFrames by manager.allMemberFrames.collectAsState()

    val phase by engine.phase.collectAsState()
    val networkMode by engine.networkMode.collectAsState()
    val serverUrl by engine.serverUrl.collectAsState()
    val directIp by engine.directConnectIp.collectAsState()
    val localIp by engine.localIpAddress.collectAsState()
    val roomCode by engine.roomCode.collectAsState()
    val nickname by engine.myNickname.collectAsState()
    val myChar by engine.myChar.collectAsState()
    val isHosting by engine.isHostingRoom.collectAsState()
    val isScanning by engine.isScanningRooms.collectAsState()
    val isServerConn by engine.isServerConnected.collectAsState()
    val isRoomAuthority by engine.isRoomAuthority.collectAsState()
    val discoveredRooms by engine.discoveredRooms.collectAsState()
    val connectedPeers by engine.connectedPeerNames.collectAsState()

    val totalRounds by engine.totalRounds.collectAsState()
    val currentRound by engine.currentRound.collectAsState()
    val baseScore by engine.baseScore.collectAsState()
    val turnLimit by engine.turnTimeLimit.collectAsState()
    val turnRem by engine.turnRemainingSeconds.collectAsState()
    val statusBanner by engine.statusBanner.collectAsState()

    val seats by engine.seats.collectAsState()
    val mySeatIdx by engine.mySeatIndex.collectAsState()
    val wallCount by engine.wallCount.collectAsState()
    val currentTurn by engine.currentTurnSeat.collectAsState()
    val selectedTileId by engine.selectedTileId.collectAsState()
    val drawnTileId by engine.drawnTileId.collectAsState()
    val pendingClaim by engine.pendingClaim.collectAsState()
    val winnerSeat by engine.winnerSeat.collectAsState()
    val winReason by engine.winReason.collectAsState()

    LaunchedEffect(Unit) { engine.refreshLocalIpAddress() }
    DisposableEffect(Unit) { onDispose { engine.leaveRoomAndResetLobby() } }

    val contentBody: @Composable () -> Unit = {
            Column(modifier = Modifier.fillMaxSize().padding(8.dp)) {
                if (!embeddedInGameRoom) {
                // Top Bar
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(MjCardGreen)
                            .clickable { engine.leaveRoomAndResetLobby() }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text("🀄 房间大厅", color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                    Text("放课后茶会 · 广东红中麻将", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black, maxLines = 1)
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(MjCardGreen)
                            .clickable {
                                engine.leaveRoomAndResetLobby()
                                onDismiss()
                            }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text("✕ 关闭", color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
                }

                Spacer(Modifier.height(5.dp))

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(MjCardGreen)
                        .border(1.dp, MjGold.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                ) {
                    Text(statusBanner, color = MjCream, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                }

                Spacer(Modifier.height(6.dp))

                if (phase == MahjongGamePhase.LOBBY) {
                    Column(
                        modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val isP2P = networkMode == DoudizhuNetworkMode.FACE_TO_FACE_P2P
                            Box(
                                modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp))
                                    .background(if (isP2P) MjRed else MjCardGreen)
                                    .border(1.5.dp, if (isP2P) MjGold else Color.Transparent, RoundedCornerShape(10.dp))
                                    .clickable { engine.setNetworkMode(DoudizhuNetworkMode.FACE_TO_FACE_P2P) }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) { Text("📡 面对面开房联机", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black) }
                            Box(
                                modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp))
                                    .background(if (!isP2P) MjBlue else MjCardGreen)
                                    .border(1.5.dp, if (!isP2P) MjGold else Color.Transparent, RoundedCornerShape(10.dp))
                                    .clickable { engine.setNetworkMode(DoudizhuNetworkMode.ONLINE_SERVER) }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) { Text("☁️ 在线服务器联机", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black) }
                        }

                        // 1. Profile
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MjCardGreen).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text("1. 昵称与轻音角色", color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Black)
                            OutlinedTextField(
                                value = nickname,
                                onValueChange = { engine.setMyNickname(it) },
                                singleLine = true,
                                colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White, focusedBorderColor = MjGold),
                                modifier = Modifier.fillMaxWidth()
                            )
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                CharacterFilter.fiveIndividuals.forEach { ch ->
                                    val sel = myChar == ch
                                    Column(
                                        modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp))
                                            .background(if (sel) MjRed else Color.Black.copy(alpha = 0.25f))
                                            .border(1.5.dp, if (sel) MjGold else Color.White.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                                            .clickable { engine.setMyCharacter(ch) }.padding(vertical = 5.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        allMemberFrames[ch.charId]?.let { bmp ->
                                            Image(bitmap = bmp.asImageBitmap(), contentDescription = null, filterQuality = FilterQuality.None, modifier = Modifier.size(34.dp))
                                        }
                                        Text(ch.displayName(lang), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                    }
                                }
                            }
                        }

                        // 2. Room
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MjCardGreen).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(if (networkMode == DoudizhuNetworkMode.FACE_TO_FACE_P2P) "2. 面对面麻将房间 (4人)" else "2. 在线麻将房间 (4人)", color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text("房号:", color = Color.LightGray, fontSize = 11.sp)
                                    OutlinedTextField(
                                        value = roomCode, onValueChange = { engine.setRoomCode(it) },
                                        placeholder = { Text("必填", color = Color.Gray, fontSize = 10.sp) },
                                        singleLine = true,
                                        colors = OutlinedTextFieldDefaults.colors(focusedTextColor = MjGold, unfocusedTextColor = MjGold, focusedBorderColor = MjGold),
                                        modifier = Modifier.width(80.dp)
                                    )
                                }
                            }
                            if (networkMode == DoudizhuNetworkMode.FACE_TO_FACE_P2P) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(onClick = { engine.startHostingFaceToFaceRoom() }, colors = ButtonDefaults.buttonColors(containerColor = if (isHosting) Color(0xFF2E7D32) else MjRed), shape = RoundedCornerShape(10.dp), modifier = Modifier.weight(1f)) {
                                        Text(if (isHosting) "📡 已开房" else "🏠 创建麻将房", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    }
                                    Button(onClick = { engine.startScanningFaceToFaceRooms() }, colors = ButtonDefaults.buttonColors(containerColor = if (isScanning) MjBlue else Color(0xFF1B5E20)), shape = RoundedCornerShape(10.dp), modifier = Modifier.weight(1f)) {
                                        Text(if (isScanning) "🔍 扫描中..." else "📡 扫描加入", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    }
                                }
                                Text("📱 本机IP: $localIp", color = MjGold, fontSize = 10.sp)
                                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    OutlinedTextField(
                                        value = directIp, onValueChange = { engine.setDirectConnectIp(it) },
                                        placeholder = { Text("输入房主IP直连", color = Color.Gray, fontSize = 10.sp) },
                                        singleLine = true,
                                        colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White, focusedBorderColor = MjGold),
                                        modifier = Modifier.weight(1f)
                                    )
                                    Button(onClick = { engine.connectDirectToHostIp() }, colors = ButtonDefaults.buttonColors(containerColor = MjBlue)) {
                                        Text("IP直连", color = Color.White, fontSize = 11.sp)
                                    }
                                }
                                discoveredRooms.forEach { room ->
                                    Row(
                                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.35f)).border(1.dp, MjGold, RoundedCornerShape(8.dp)).clickable { engine.joinDiscoveredRoom(room) }.padding(8.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text("${room.hostName} (房号:${room.roomCode})", color = Color.White, fontSize = 11.sp)
                                        Text("点击加入 >", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    }
                                }
                            } else {
                                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    OutlinedTextField(
                                        value = serverUrl, onValueChange = { engine.setServerUrl(it) }, singleLine = true,
                                        colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White, focusedBorderColor = MjGold),
                                        modifier = Modifier.weight(1f)
                                    )
                                    Button(onClick = { engine.connectOnlineServerRoom() }, colors = ButtonDefaults.buttonColors(containerColor = if (isServerConn) Color(0xFF2E7D32) else MjBlue)) {
                                        Text(if (isServerConn) "已连($roomCode)" else "连接", color = Color.White, fontSize = 11.sp)
                                    }
                                    if (isServerConn) {
                                        Button(onClick = { engine.leaveRoomAndResetLobby() }, colors = ButtonDefaults.buttonColors(containerColor = MjRed)) {
                                            Text("退出", color = Color.White, fontSize = 11.sp)
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Rules
                        val canEdit = isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MjCardGreen).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("3. 广东红中麻将规则 (红中赖子·不能吃·可碰杠)", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                Text(if (canEdit) "第$currentRound/${if (totalRounds == 0) "∞" else totalRounds}局" else "🔒仅房主可改", color = if (canEdit) Color(0xFF00E676) else Color(0xFFFFB74D), fontSize = 10.sp)
                            }
                            MjRuleRow("局数:", listOf(4 to "4局", 8 to "8局", 16 to "16局", 0 to "无限"), totalRounds, MjRed) { if (canEdit) engine.setTotalRounds(it) }
                            MjRuleRow("底分:", listOf(50 to "50分", 100 to "100分", 200 to "200分", 500 to "500分"), baseScore, Color(0xFFD99426)) { if (canEdit) engine.setBaseScore(it) }
                            MjRuleRow("限时:", listOf(15 to "15秒", 20 to "20秒", 30 to "30秒", 0 to "不限"), turnLimit, MjBlue) { if (canEdit) engine.setTurnTimeLimit(it) }
                        }

                        // 4. 4-Seat Preview
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MjCardGreen).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text("4. 四人牌桌座位预览 (不足4人由轻音AI补位)", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                seats.forEach { s ->
                                    Column(
                                        modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.28f)).border(1.dp, if (!s.isAI) Color(0xFF00E676) else Color.White.copy(alpha = 0.15f), RoundedCornerShape(8.dp)).padding(6.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        allMemberFrames[s.character.charId]?.let { bmp ->
                                            Image(bitmap = bmp.asImageBitmap(), contentDescription = null, filterQuality = FilterQuality.None, modifier = Modifier.size(34.dp))
                                        }
                                        Text(s.name, color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(if (s.isAI) "🤖 AI" else "📱 真人", color = if (s.isAI) Color(0xFF64B5F6) else Color(0xFF00E676), fontSize = 8.sp)
                                        Text("${s.score}分", color = Color.LightGray, fontSize = 8.sp)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))
                    val isGuestWaiting = !isRoomAuthority && (isServerConn || connectedPeers.isNotEmpty())
                    Button(
                        onClick = { if (!isGuestWaiting) engine.startNewGame() },
                        enabled = !isGuestWaiting,
                        colors = ButtonDefaults.buttonColors(containerColor = if (isGuestWaiting) Color.DarkGray else MjRed),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth().height(44.dp)
                    ) {
                        Text(if (isGuestWaiting) "⏳ 等待1号房主开始麻将..." else "🀄 立即开始广东红中麻将 (底分 $baseScore)", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black)
                    }
                } else {
                    // Active 4-Player Mahjong Table
                    val oppIdx = (mySeatIdx + 2) % 4
                    val leftIdx = (mySeatIdx + 3) % 4
                    val rightIdx = (mySeatIdx + 1) % 4

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        seats.getOrNull(oppIdx)?.let { opp ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                MjSeatBadge(opp, currentTurn == oppIdx, allMemberFrames[opp.character.charId])
                                Row(
                                    modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 5.dp, vertical = 3.dp),
                                    horizontalArrangement = Arrangement.spacedBy(1.5.dp)
                                ) {
                                    repeat(minOf(14, maxOf(0, opp.hand.size))) {
                                        MjTileBack(13.dp, 20.dp)
                                    }
                                }
                            }
                        }
                        Row(
                            modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(MjCardGreen).padding(horizontal = 8.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                                repeat(((wallCount + 14) / 15).coerceIn(1, 8)) {
                                    Box(modifier = Modifier.size(10.dp, 14.dp)) {
                                        MjTileBack(10.dp, 12.dp)
                                    }
                                }
                            }
                            Text("余 $wallCount 张 · 第${currentRound}局 · ⏱${turnRem}s", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                        }
                    }

                    seats.getOrNull(oppIdx)?.let { MjDiscardRiver(it) }

                    Row(modifier = Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        // Left Seat with Standing Vertical Tile Wall
                        Row(modifier = Modifier.weight(0.35f).fillMaxHeight(), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                            seats.getOrNull(leftIdx)?.let { lSeat ->
                                Column(
                                    modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(Color.Black.copy(alpha = 0.32f)).padding(3.dp),
                                    verticalArrangement = Arrangement.spacedBy(1.dp)
                                ) {
                                    repeat(minOf(10, maxOf(0, lSeat.hand.size))) {
                                        MjTileBack(18.dp, 8.dp)
                                    }
                                }
                                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    MjSeatBadge(lSeat, currentTurn == leftIdx, allMemberFrames[lSeat.character.charId])
                                    MjDiscardRiver(lSeat)
                                }
                            }
                        }

                        // Tencent-Style Center 4-Direction Wind Compass + Big Countdown + Ting Pill
                        var showTingPopup by remember { mutableStateOf(false) }
                        Box(
                            modifier = Modifier.weight(0.30f).fillMaxHeight(),
                            contentAlignment = Alignment.Center
                        ) {
                            val cl = pendingClaim
                            when {
                                cl != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("⚡ 响应牌", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    Spacer(Modifier.height(4.dp))
                                    MjTileCard(cl.tile, 36.dp, 50.dp, isSelected = false, isHighlight = true)
                                }
                                phase == MahjongGamePhase.ROUND_OVER -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(if (winnerSeat != null) "🀄 胡!" else "🌊 流局", color = Color.Yellow, fontSize = 22.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center)
                                    if (winnerSeat != null) {
                                        Text("${seats.getOrNull(winnerSeat!!)?.name} · $winReason", color = Color.White, fontSize = 10.sp, textAlign = TextAlign.Center)
                                    }
                                }
                                else -> {
                                    val me = seats.getOrNull(mySeatIdx)
                                    val ting = if (me != null) MahjongEvaluator.readyTiles(me.hand, me.melds.size) else emptyList()
                                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Column(
                                            modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Color(0xFF072B33)).border(1.5.dp, MjGold.copy(alpha = 0.7f), RoundedCornerShape(10.dp)).padding(horizontal = 8.dp, vertical = 4.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally
                                        ) {
                                            Text("北", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == oppIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == oppIdx) MjRed else Color.Transparent).padding(horizontal = 8.dp, vertical = 1.dp))
                                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                                Text("西", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == leftIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == leftIdx) MjRed else Color.Transparent).padding(horizontal = 3.dp, vertical = 4.dp))
                                                Box(
                                                    modifier = Modifier.size(32.dp).clip(RoundedCornerShape(16.dp)).background(Color(0xFF0A3A46)).border(1.5.dp, MjGold, RoundedCornerShape(16.dp)),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Text("$turnRem", color = if (turnRem <= 5) Color.Red else Color.Cyan, fontSize = 14.sp, fontWeight = FontWeight.Black)
                                                }
                                                Text("东", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == rightIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == rightIdx) MjRed else Color.Transparent).padding(horizontal = 3.dp, vertical = 4.dp))
                                            }
                                            Text("南", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == mySeatIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == mySeatIdx) MjRed else Color.Transparent).padding(horizontal = 8.dp, vertical = 1.dp))
                                        }
                                        if (ting.isNotEmpty()) {
                                            Box(
                                                modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(MjGold).clickable { showTingPopup = !showTingPopup }.padding(horizontal = 8.dp, vertical = 2.dp)
                                            ) {
                                                Text("💡 听牌 (${ting.size})", color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.Black)
                                            }
                                        }
                                    }
                                    if (showTingPopup && ting.isNotEmpty()) {
                                        Dialog(onDismissRequest = { showTingPopup = false }) {
                                            Surface(shape = RoundedCornerShape(14.dp), color = Color(0xFFF1F9F5), modifier = Modifier.border(2.dp, MjGold, RoundedCornerShape(14.dp))) {
                                                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                                    Text("💡 听牌提示 (共${ting.size}种)", color = Color(0xFF1A5233), fontSize = 13.sp, fontWeight = FontWeight.Black)
                                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                                        ting.take(8).forEach { tt ->
                                                            val seen = seats.flatMap { it.discards }.count { it.suit == tt.suit && it.rank == tt.rank } + (me?.hand?.count { it.suit == tt.suit && it.rank == tt.rank } ?: 0)
                                                            val rem = (4 - seen).coerceAtLeast(0)
                                                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                                                MjTileCard(tt, 28.dp, 38.dp, isSelected = false, isHighlight = rem > 0)
                                                                Text("余${rem}张", color = if (rem == 0) Color.Gray else MjRed, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Right Seat with Standing Vertical Tile Wall
                        Row(modifier = Modifier.weight(0.35f).fillMaxHeight(), horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                            seats.getOrNull(rightIdx)?.let { rSeat ->
                                Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    MjSeatBadge(rSeat, currentTurn == rightIdx, allMemberFrames[rSeat.character.charId])
                                    MjDiscardRiver(rSeat)
                                }
                                Column(
                                    modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(Color.Black.copy(alpha = 0.32f)).padding(3.dp),
                                    verticalArrangement = Arrangement.spacedBy(1.dp)
                                ) {
                                    repeat(minOf(10, maxOf(0, rSeat.hand.size))) {
                                        MjTileBack(18.dp, 8.dp)
                                    }
                                }
                            }
                        }
                    }

                    // Compact Single-Line My Info + Action Bar + My Discard River + Melds & Hand Row
                    val me = seats.getOrNull(mySeatIdx)
                    if (me != null) {
                        if (me.discards.isNotEmpty()) {
                            MjDiscardRiver(me)
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(MjCardGreen).padding(horizontal = 8.dp, vertical = 3.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                allMemberFrames[me.character.charId]?.let { bmp ->
                                    Image(bitmap = bmp.asImageBitmap(), contentDescription = null, filterQuality = FilterQuality.None, modifier = Modifier.size(22.dp))
                                }
                                Text("${me.name}${if (me.isDealer) "[庄]" else ""} · ${me.score}分", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }

                            Row(modifier = Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                val cl = pendingClaim
                                if (phase == MahjongGamePhase.CLAIM_WINDOW && cl != null) {
                                    val canHu = cl.eligibleHuSeats.contains(mySeatIdx) && !cl.passedSeats.contains(mySeatIdx)
                                    val canKong = cl.eligibleKongSeats.contains(mySeatIdx) && !cl.passedSeats.contains(mySeatIdx)
                                    val canPong = cl.eligiblePongSeats.contains(mySeatIdx) && !cl.passedSeats.contains(mySeatIdx)
                                    if (canHu || canKong || canPong) {
                                        if (canHu) Button(onClick = { engine.sendClaimResponse("hu") }, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = MjRed), modifier = Modifier.weight(1f).height(32.dp)) { Text("🀄 胡!", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black) }
                                        if (canKong) Button(onClick = { engine.sendClaimResponse("kong") }, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD99426)), modifier = Modifier.weight(1f).height(32.dp)) { Text("杠", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black) }
                                        if (canPong) Button(onClick = { engine.sendClaimResponse("pong") }, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = MjBlue), modifier = Modifier.weight(1f).height(32.dp)) { Text("碰", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black) }
                                        Button(onClick = { engine.sendClaimResponse("pass") }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = Color.DarkGray), modifier = Modifier.height(32.dp)) { Text("过", color = Color.White, fontSize = 12.sp) }
                                    } else {
                                        Text("⏳ 等待其他玩家响应...", color = MjGold, fontSize = 11.sp)
                                    }
                                } else if (phase == MahjongGamePhase.PLAYING && currentTurn == mySeatIdx) {
                                    if (engine.canDeclareSelfHu()) {
                                        Button(onClick = { engine.declareSelfHu() }, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = MjRed), modifier = Modifier.weight(1f).height(32.dp)) { Text("🀄 自摸胡!", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black) }
                                    }
                                    engine.selfKongOptions().firstOrNull()?.let { kt ->
                                        Button(onClick = { engine.declareSelfKong(kt) }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD99426)), modifier = Modifier.height(32.dp)) { Text("杠 ${kt.fullName}", color = Color.White, fontSize = 11.sp) }
                                    }
                                    val selTile = me.hand.firstOrNull { it.id == selectedTileId }
                                    if (selTile != null) {
                                        Button(onClick = { engine.discardTile(selTile) }, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)), modifier = Modifier.weight(1f).height(32.dp)) {
                                            Text("打出 ${selTile.fullName}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                        }
                                    } else {
                                        Text("👉 点选后点击【打出】出牌（再点取消）", color = Color(0xFF00E676), fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    }
                                } else if (phase == MahjongGamePhase.ROUND_OVER) {
                                    val inRoom = isServerConn || isHosting || connectedPeers.isNotEmpty()
                                    val isGuestWaiting = inRoom && !isRoomAuthority
                                    Button(onClick = { if (!isGuestWaiting) engine.startNewGame() }, enabled = !isGuestWaiting, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = if (isGuestWaiting) Color.DarkGray else MjRed), modifier = Modifier.weight(1f).height(32.dp)) {
                                        Text(if (isGuestWaiting) "⏳ 等待房主..." else "▶ 再来一局", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                    }
                                    if (inRoom && isRoomAuthority) {
                                        Button(onClick = { engine.returnRoomToLobby() }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = MjCardGreen), modifier = Modifier.height(32.dp)) { Text("房间设置", color = MjGold, fontSize = 11.sp) }
                                    } else {
                                        Button(onClick = { engine.leaveRoomAndResetLobby() }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = MjCardGreen), modifier = Modifier.height(32.dp)) { Text("退出房间", color = MjGold, fontSize = 11.sp) }
                                    }
                                }
                            }
                        }

                        Spacer(Modifier.height(4.dp))

                        // Melds + Hand Tiles side-by-side on bottom row so tiles are 100% visible!
                        BoxWithConstraints(modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                            val totalW = maxWidth
                            val meldW = (me.melds.size * 84).dp
                            val handW = (totalW - meldW - 12.dp).coerceAtLeast(220.dp)
                            val tileW = (handW / me.hand.size.coerceAtLeast(1)).coerceIn(26.dp, 36.dp)
                            val tileH = tileW * 1.4f
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.Bottom,
                                horizontalArrangement = Arrangement.Center
                            ) {
                                if (me.melds.isNotEmpty()) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(end = 8.dp)) {
                                        me.melds.forEach { m ->
                                            Row(modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(Color.Black.copy(alpha = 0.35f)).padding(2.dp), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                                                repeat(if (m.kind == MahjongMeldKind.PONG) 3 else 4) { idx ->
                                                    if (m.kind == MahjongMeldKind.CONCEALED_KONG && idx != 2) {
                                                        MjTileBack(24.dp, 34.dp)
                                                    } else {
                                                        MjTileCard(m.tile, 24.dp, 34.dp, isSelected = false, isHighlight = false)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                var mjDealtCount by remember(currentRound) { mutableIntStateOf(me.hand.size) }
                                var mjDealingOrder by remember(currentRound) { mutableStateOf<List<MahjongTile>>(emptyList()) }
                                var isMjDealing by remember(currentRound) { mutableStateOf(false) }
                                LaunchedEffect(phase, currentRound) {
                                    if (phase == MahjongGamePhase.PLAYING && me.hand.isNotEmpty() && mjDealingOrder.isEmpty()) {
                                        mjDealingOrder = me.hand.shuffled()
                                        isMjDealing = true
                                        mjDealtCount = 0
                                        for (i in 1..me.hand.size) {
                                            kotlinx.coroutines.delay(40L)
                                            mjDealtCount = i
                                        }
                                        kotlinx.coroutines.delay(160L)
                                        isMjDealing = false
                                    } else if (phase == MahjongGamePhase.LOBBY) {
                                        isMjDealing = false
                                        mjDealingOrder = emptyList()
                                    }
                                }
                                val shownTiles = if (isMjDealing) mjDealingOrder.take(mjDealtCount) else me.hand
                                Row(horizontalArrangement = Arrangement.spacedBy(1.5.dp)) {
                                    shownTiles.forEach { t ->
                                        MjTileCard(t, tileW, tileH, selectedTileId == t.id, drawnTileId == t.id) { engine.selectOrDiscardTile(t) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
    }
    if (embeddedInGameRoom) {
        contentBody()
    } else {
        Dialog(
            onDismissRequest = {
                engine.leaveRoomAndResetLobby()
                onDismiss()
            },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth(0.98f)
                    .fillMaxHeight(0.96f)
                    .clip(RoundedCornerShape(18.dp))
                    .border(2.dp, MjGold, RoundedCornerShape(18.dp)),
                color = MjBgGreen
            ) {
                contentBody()
            }
        }
    }
}

@Composable
private fun MjRuleRow(title: String, opts: List<Pair<Int, String>>, selected: Int, accent: Color, onSelect: (Int) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, color = Color.LightGray, fontSize = 10.sp, modifier = Modifier.width(36.dp))
        opts.forEach { (v, lbl) ->
            val sel = selected == v
            Box(
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(6.dp)).background(if (sel) accent else Color.Black.copy(alpha = 0.35f)).clickable { onSelect(v) }.padding(vertical = 4.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(lbl, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun MjSeatBadge(seat: MahjongSeat, isTurn: Boolean, bmp: android.graphics.Bitmap?) {
    Row(
        modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.45f)).border(if (isTurn) 1.5.dp else 0.8.dp, if (isTurn) MjGold else Color.White.copy(alpha = 0.2f), RoundedCornerShape(8.dp)).padding(horizontal = 6.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        bmp?.let { Image(bitmap = it.asImageBitmap(), contentDescription = null, filterQuality = FilterQuality.None, modifier = Modifier.size(22.dp)) }
        Column {
            Text(seat.name, color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${seat.score}分 · ${seat.hand.size}张", color = MjGold, fontSize = 8.sp)
        }
    }
}

@Composable
private fun MjDiscardRiver(seat: MahjongSeat) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (seat.melds.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                seat.melds.forEach { m ->
                    Row(modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Color.Black.copy(alpha = 0.35f)).padding(2.dp), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                        val cnt = if (m.kind == MahjongMeldKind.PONG) 3 else 4
                        repeat(cnt) { idx ->
                            if (m.kind == MahjongMeldKind.CONCEALED_KONG && idx != 2) {
                                MjTileBack(15.dp, 21.dp)
                            } else {
                                MjTileCard(m.tile, 15.dp, 21.dp, isSelected = false, isHighlight = false)
                            }
                        }
                    }
                }
            }
        }
        val latestId = seat.discards.lastOrNull()?.id
        seat.discards.chunked(6).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(1.5.dp)) {
                row.forEach { t ->
                    val isLatest = (t.id == latestId)
                    val popScale by animateFloatAsState(
                        targetValue = if (isLatest) 1.06f else 1.0f,
                        animationSpec = spring(dampingRatio = 0.55f, stiffness = 420f),
                        label = "mj_discard_pop"
                    )
                    Box(modifier = Modifier.graphicsLayer(scaleX = popScale, scaleY = popScale), contentAlignment = Alignment.TopCenter) {
                        MjTileCard(t, 19.dp, 26.dp, isSelected = false, isHighlight = isLatest)
                        if (isLatest) {
                            Text("▼", color = Color(0xFFFF9800), fontSize = 9.sp, fontWeight = FontWeight.Black, modifier = Modifier.offset(y = (-8).dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MjTileCard(tile: MahjongTile, w: Dp, h: Dp, isSelected: Boolean, isHighlight: Boolean, onClick: (() -> Unit)? = null) {
    val tileBmp = HTTNaviApp.instance.assetDecryptor.getMahjongTileBitmap(tile.id, tile.suit.code, tile.rank)
    Box(
        modifier = Modifier
            .offset(y = if (isSelected) (-6).dp else 0.dp)
            .size(w, h)
            .clip(RoundedCornerShape(4.dp))
            .background(Color(0xFFFAF7ED))
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) MjGold else if (isHighlight) Color(0xFF00E676) else Color(0xFFBFAE96), RoundedCornerShape(4.dp))
            .let { if (onClick != null) it.clickable { onClick() } else it },
        contentAlignment = Alignment.Center
    ) {
        if (tileBmp != null) {
            Image(
                bitmap = tileBmp.asImageBitmap(),
                contentDescription = tile.fullName,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Text(tile.shortLabel, color = Color.Black, fontSize = (w.value * 0.40f).coerceAtLeast(9f).sp, fontWeight = FontWeight.Black)
        }
        if (tile.isLaizi) {
            Text(
                "赖", color = Color.White, fontSize = 7.sp, fontWeight = FontWeight.Black,
                modifier = Modifier.align(Alignment.TopEnd).clip(RoundedCornerShape(2.dp)).background(MjGold).padding(horizontal = 1.5.dp)
            )
        }
    }
}

@Composable
private fun MjTileBack(w: Dp, h: Dp) {
    Box(
        modifier = Modifier
            .size(w, h)
            .clip(RoundedCornerShape(3.dp))
            .background(Color(0xFF0E7A48))
            .border(0.8.dp, Color(0xFFD8F3E4).copy(alpha = 0.75f), RoundedCornerShape(3.dp))
    )
}
