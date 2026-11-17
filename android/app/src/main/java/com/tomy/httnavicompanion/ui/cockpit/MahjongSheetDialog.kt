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
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
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
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.TextStyle
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
    val rmkEngine = manager.rummikubEngine
    val lang by manager.language.collectAsState()
    var selectedGame by remember { mutableStateOf(0) } // 0 = 放课后斗地主(3P), 1 = 广东红中麻将(4P), 2 = 拉密数字牌(2-4P)

    fun tr(hans: String, hant: String, en: String): String = when (lang) {
        AppLanguage.ZH_HANS -> hans
        AppLanguage.ZH_HANT -> hant
        AppLanguage.EN -> en
    }

    val context = LocalContext.current
    val ddzPhase by ddzEngine.phase.collectAsState()
    val mjPhase by mjEngine.phase.collectAsState()
    val rmkPhase by rmkEngine.phase.collectAsState()
    val ddzHosting by ddzEngine.isHostingRoom.collectAsState()
    val ddzServerConn by ddzEngine.isServerConnected.collectAsState()
    val ddzPeers by ddzEngine.connectedPeerNames.collectAsState()
    val mjHosting by mjEngine.isHostingRoom.collectAsState()
    val mjServerConn by mjEngine.isServerConnected.collectAsState()
    val mjPeers by mjEngine.connectedPeerNames.collectAsState()
    val rmkServerConn by rmkEngine.isServerConnected.collectAsState()
    val rmkHosting by rmkEngine.isHostingRoom.collectAsState()
    val rmkPeers by rmkEngine.connectedPeerNames.collectAsState()
    val rmkPlayerCnt by rmkEngine.roomPlayerCount.collectAsState()

    val inLobbyNow = (selectedGame == 0 && ddzPhase == DoudizhuGamePhase.LOBBY) ||
        (selectedGame == 1 && mjPhase == MahjongGamePhase.LOBBY) ||
        (selectedGame == 2 && rmkPhase == RmkGamePhase.LOBBY)
    val isInJoinedRoom = !inLobbyNow ||
        (selectedGame == 0 && (ddzHosting || ddzServerConn || ddzPeers.isNotEmpty())) ||
        (selectedGame == 1 && (mjHosting || mjServerConn || mjPeers.isNotEmpty())) ||
        (selectedGame == 2 && (rmkHosting || rmkServerConn || rmkPeers.isNotEmpty()))

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
            rmkEngine.leaveRoomAndResetLobby()
        }
    }

    Dialog(
        onDismissRequest = {
            ddzEngine.leaveRoomAndResetLobby()
            mjEngine.leaveRoomAndResetLobby()
            rmkEngine.leaveRoomAndResetLobby()
            onDismiss()
        },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = if (selectedGame == 0) Color(0xFF104B2C) else MjBgGreen
        ) {
            Column(modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                // Unified Header (Hidden when inside Rummikub playing room so Rummikub table is 1:1 full-screen like the video!)
                if (!(selectedGame == 2 && !inLobbyNow)) {
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
                                    else if (selectedGame == 1) mjEngine.leaveRoomAndResetLobby()
                                    else rmkEngine.leaveRoomAndResetLobby()
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
                                    rmkEngine.leaveRoomAndResetLobby()
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
                }

                // Game Switcher Bar
                if (isInJoinedRoom && inLobbyNow) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                            .clip(RoundedCornerShape(9.dp))
                            .background(when (selectedGame) { 0 -> MjRed.copy(alpha = 0.85f); 1 -> Color(0xFF146C43).copy(alpha = 0.85f); else -> Color(0xFFFB8C00).copy(alpha = 0.88f) })
                            .border(1.2.dp, MjGold, RoundedCornerShape(9.dp))
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            when (selectedGame) { 0 -> "🃏 当前房间：放课后斗地主 (3人)"; 1 -> "🀄 当前房间：广东红中麻将 (4人)"; else -> "🔢 当前房间：拉密数字牌 (${rmkPlayerCnt}人)" },
                            color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black
                        )
                        Text(
                            "房号: ${when (selectedGame) { 0 -> ddzEngine.roomCode.collectAsState().value; 1 -> mjEngine.roomCode.collectAsState().value; else -> rmkEngine.roomCode.collectAsState().value }}",
                            color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Bold
                        )
                    }
                }
                if (!isInJoinedRoom) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
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
                                        rmkEngine.leaveRoomAndResetLobby()
                                        selectedGame = 0
                                    }
                                }
                                .padding(vertical = 7.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                tr("🃏 斗地主 (3人)", "🃏 鬥地主 (3人)", "🃏 Doudizhu (3P)"),
                                color = Color.White,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Black,
                                maxLines = 1
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
                                        rmkEngine.leaveRoomAndResetLobby()
                                        selectedGame = 1
                                    }
                                }
                                .padding(vertical = 7.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                tr("🀄 红中麻将 (4人)", "🀄 紅中麻將 (4人)", "🀄 Mahjong (4P)"),
                                color = Color.White,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Black,
                                maxLines = 1
                            )
                        }
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(9.dp))
                                .background(if (selectedGame == 2) Color(0xFFFB8C00) else Color.Black.copy(alpha = 0.42f))
                                .border(
                                    if (selectedGame == 2) 1.5.dp else 1.dp,
                                    if (selectedGame == 2) MjGold else MjGold.copy(alpha = 0.35f),
                                    RoundedCornerShape(9.dp)
                                )
                                .clickable {
                                    if (selectedGame != 2) {
                                        ddzEngine.leaveRoomAndResetLobby()
                                        mjEngine.leaveRoomAndResetLobby()
                                        selectedGame = 2
                                    }
                                }
                                .padding(vertical = 7.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                tr("🔢 拉密数字牌 (2-4人)", "🔢 拉密數字牌 (2-4人)", "🔢 Rummikub (2-4P)"),
                                color = Color.White,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Black,
                                maxLines = 1
                            )
                        }
                    }
                }

                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    if (selectedGame == 0) {
                        KOnDoudizhuSheetDialog(onDismiss = onDismiss, embeddedInGameRoom = true)
                    } else if (selectedGame == 1) {
                        KOnMahjongSheetDialog(onDismiss = onDismiss, embeddedInGameRoom = true)
                    } else {
                        KOnRummikubContent()
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
    val aiDifficulty by engine.aiDifficulty.collectAsState()
    val lastClaimEvent by engine.lastClaimEvent.collectAsState()

    LaunchedEffect(Unit) { engine.refreshLocalIpAddress() }
    DisposableEffect(Unit) { onDispose { engine.leaveRoomAndResetLobby() } }

    val contentBody: @Composable () -> Unit = {
            Column(modifier = Modifier.fillMaxSize().navigationBarsPadding().padding(horizontal = 8.dp, vertical = 4.dp)) {
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
                        Text(
                            "💡 联机说明：面对面(免流量)仅限安卓设备之间局域网/蓝牙直连；与 iOS / Switch 跨平台同桌请用【在线服务器联机】(可开热点共享网络)",
                            color = MjGold.copy(alpha = 0.95f),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(7.dp)).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 8.dp, vertical = 5.dp)
                        )

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
                            MjRuleRow("AI:", listOf(0 to "休闲 AI", 1 to "标准 AI", 2 to "大师 AI"), aiDifficulty.ordinal, Color(0xFF7E57C2)) { if (canEdit) engine.setAiDifficulty(MahjongAIDifficulty.entries[it]) }
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
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
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
                            if (isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())) {
                                Box(
                                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(MjGold).clickable { engine.startNewGame() }.padding(horizontal = 8.dp, vertical = 4.dp)
                                ) {
                                    Text("↻", color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }

                    seats.getOrNull(oppIdx)?.let { opp ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            MjSeatMelds(opp)
                            MjDiscardRiver(opp, maxCols = 8)
                        }
                    }

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
                                    MjSeatMelds(lSeat)
                                    MjDiscardRiver(lSeat, maxCols = 5)
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
                            val ev = lastClaimEvent
                            if (ev != null) {
                                Row(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(MjRed.copy(alpha = 0.95f))
                                        .border(2.dp, MjGold, RoundedCornerShape(12.dp))
                                        .padding(horizontal = 10.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    allMemberFrames[ev.character.charId]?.let { bmp ->
                                        Image(bitmap = bmp.asImageBitmap(), contentDescription = null, filterQuality = FilterQuality.None, modifier = Modifier.size(26.dp))
                                    }
                                    Column {
                                        Text(ev.seatName, color = Color.White, fontSize = 9.sp, maxLines = 1)
                                        Text("💥 ${ev.actionLabel} ${ev.tile.fullName}!", color = Color.Yellow, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                    }
                                    MjTileCard(ev.tile, 24.dp, 33.dp, isSelected = false, isHighlight = true)
                                }
                            } else when {
                                cl != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("⚡ 响应牌", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    Spacer(Modifier.height(4.dp))
                                    MjTileCard(cl.tile, 36.dp, 50.dp, isSelected = false, isHighlight = true)
                                }
                                phase == MahjongGamePhase.ROUND_OVER -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    val isSeriesDone = totalRounds > 0 && currentRound >= totalRounds
                                    if (isSeriesDone) {
                                        Text("🏆 整场积分排名", color = Color.Yellow, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                        seats.sortedByDescending { it.score }.forEachIndexed { idx, rs ->
                                            val medal = when (idx) { 0 -> "🥇"; 1 -> "🥈"; 2 -> "🥉"; else -> "4." }
                                            Text("$medal ${rs.name}: ${rs.score}分", color = Color.White, fontSize = 9.sp, maxLines = 1)
                                        }
                                    } else {
                                        Text(if (winnerSeat != null) "🀄 胡!" else "🌊 流局", color = Color.Yellow, fontSize = 20.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center)
                                        if (winnerSeat != null) {
                                            Text("${seats.getOrNull(winnerSeat!!)?.name} · $winReason", color = Color.White, fontSize = 10.sp, textAlign = TextAlign.Center)
                                        }
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
                                    MjSeatMelds(rSeat)
                                    MjDiscardRiver(rSeat, maxCols = 5)
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
                            MjDiscardRiver(me, maxCols = 10)
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
                            val tileW = (totalW / 16.2f).coerceIn(30.dp, 36.dp)
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
                                Row(horizontalArrangement = Arrangement.spacedBy(1.5.dp), verticalAlignment = Alignment.Bottom) {
                                    shownTiles.forEachIndexed { idx, t ->
                                        if (!isMjDealing && drawnTileId == t.id && idx == shownTiles.lastIndex && shownTiles.size > 1) {
                                            Spacer(Modifier.width(tileW * 0.48f))
                                        }
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
private fun MjSeatMelds(seat: MahjongSeat) {
    if (seat.melds.isEmpty()) return
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        seat.melds.forEach { m ->
            Row(modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Color.Black.copy(alpha = 0.42f)).padding(2.dp), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
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

@Composable
private fun MjDiscardRiver(seat: MahjongSeat, maxCols: Int = 6) {
    val latestId = seat.discards.lastOrNull()?.id
    val maxTiles = maxCols * 2
    val recentDiscards = if (seat.discards.size > maxTiles) seat.discards.takeLast(maxTiles) else seat.discards
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        recentDiscards.chunked(maxCols).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                row.forEach { t ->
                    val isLatest = (t.id == latestId)
                    val popScale by animateFloatAsState(
                        targetValue = if (isLatest) 1.06f else 1.0f,
                        animationSpec = spring(dampingRatio = 0.55f, stiffness = 420f),
                        label = "mj_discard_pop"
                    )
                    Box(modifier = Modifier.graphicsLayer(scaleX = popScale, scaleY = popScale)) {
                        MjTileCard(t, 22.dp, 30.dp, isSelected = false, isHighlight = isLatest)
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


@OptIn(ExperimentalFoundationApi::class)
@Composable
fun KOnRummikubContent() {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val rmk = manager.rummikubEngine
    val allFrames by manager.allMemberFrames.collectAsState()
    val lang by manager.language.collectAsState()

    val phase by rmk.phase.collectAsState()
    val playerCnt by rmk.roomPlayerCount.collectAsState()
    val seats by rmk.seats.collectAsState()
    val mySeat by rmk.mySeatIndex.collectAsState()
    val turnSeat by rmk.currentTurnSeat.collectAsState()
    val poolCount by rmk.poolCount.collectAsState()
    val remSec by rmk.turnRemainingSeconds.collectAsState()
    val banner by rmk.statusBanner.collectAsState()
    val myNick by rmk.myNickname.collectAsState()
    val myChar by rmk.myCharacter.collectAsState()
    val roomCode by rmk.roomCode.collectAsState()
    val serverUrl by rmk.serverUrl.collectAsState()
    val isConn by rmk.isServerConnected.collectAsState()
    val isAuth by rmk.isRoomAuthority.collectAsState()
    val selIds by rmk.selectedTileIds.collectAsState()
    val sortCol by rmk.sortByColor.collectAsState()
    val isEditing by rmk.isEditingTable.collectAsState()
    val tableMelds by rmk.tableMelds.collectAsState()
    val workingMelds by rmk.workingMelds.collectAsState()
    val workingHand by rmk.workingHand.collectAsState()
    val rackCols by rmk.rackCols.collectAsState()
    val rackSlots by rmk.rackSlots.collectAsState()
    val liftedIdx by rmk.liftedSlotIndex.collectAsState()
    val dealVisCnt by rmk.dealingVisibleCount.collectAsState()
    val isDealing by rmk.isDealingAnimation.collectAsState()
    val isDrawing by rmk.isDrawingAnimation.collectAsState()
    val drawAnimTile by rmk.drawingAnimatedTile.collectAsState()
    val highlightedIds by rmk.lastTurnHighlightedTileIds.collectAsState()
    val selectedTableTile by rmk.selectedTableTileSource.collectAsState()

    fun tileColor(c: RmkColor): Color = when (c) {
        RmkColor.RED -> Color(0xFFDC2832)
        RmkColor.BLUE -> Color(0xFF1E7AE6)
        RmkColor.YELLOW -> Color(0xFFE6950C)
        RmkColor.BLACK -> Color(0xFF209262)
        RmkColor.JOKER -> Color(0xFF7E48C6)
    }

    @Composable
    fun RmkTileCard(
        tile: RmkTile,
        selected: Boolean,
        highlighted: Boolean = false,
        compact: Boolean = false,
        customW: Dp? = null,
        customH: Dp? = null,
        onClick: (() -> Unit)? = null
    ) {
        val w = customW ?: if (compact) 42.dp else 48.dp
        val h = customH ?: if (compact) 58.dp else 64.dp
        val bmp = rmk.getAssetBitmap(tile.assetFileName)
        val borderCol = when {
            selected -> Color.Cyan
            highlighted -> Color(0xFFFF8F1F)
            else -> Color.Gray.copy(alpha = 0.38f)
        }
        val borderW = if (selected || highlighted) 2.5.dp else 1.dp
        Box(
            modifier = Modifier
                .size(width = w, height = h)
                .offset(y = if (selected) (-7).dp else 0.dp)
                .clip(RoundedCornerShape(7.dp))
                .background(Color(0xFFFCF8F2))
                .border(borderW, borderCol, RoundedCornerShape(7.dp))
                .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier),
            contentAlignment = Alignment.Center
        ) {
            if (bmp != null) {
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    filterQuality = FilterQuality.High,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    Text(if (tile.isJoker) "JOKER" else "${tile.number}", color = tileColor(tile.color), fontSize = if (compact) 15.sp else 17.sp, fontWeight = FontWeight.Black)
                    Text(if (tile.isJoker) "百搭" else tile.color.labelZh, color = tileColor(tile.color), fontSize = if (compact) 8.sp else 9.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }

    if (phase == RmkGamePhase.LOBBY) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 4.dp)) {
            Box(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(9.dp)).background(Color.Black.copy(alpha = 0.45f)).border(1.dp, MjGold.copy(alpha = 0.55f), RoundedCornerShape(9.dp)).padding(8.dp)) {
                Text("🔢 $banner", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 2)
            }
            Spacer(Modifier.height(6.dp))
            Column(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.45f)).padding(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("1. 昵称与角色", color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Black)
                        Spacer(Modifier.width(8.dp))
                        BasicTextField(value = myNick, onValueChange = { rmk.setNickname(it) }, textStyle = TextStyle(color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold),
                            modifier = Modifier.weight(1f).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 6.dp))
                    }
                    Spacer(Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        CharacterFilter.fiveIndividuals.forEach { ch ->
                            val sel = (myChar == ch)
                            Column(modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(if (sel) MjRed.copy(alpha = 0.85f) else Color.White.copy(alpha = 0.08f))
                                .border(if (sel) 1.5.dp else 0.dp, if (sel) MjGold else Color.Transparent, RoundedCornerShape(8.dp))
                                .clickable { rmk.setCharacter(ch); manager.playMascotVoice(ch) }.padding(vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                allFrames[ch.charId]?.let { bmp -> Image(bitmap = bmp.asImageBitmap(), contentDescription = null, modifier = Modifier.size(30.dp)) }
                                Text(ch.displayName(lang), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                            }
                        }
                    }
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val netMode by rmk.networkMode.collectAsState()
                    val isP2P = (netMode == RmkNetworkMode.LOCAL_LAN)
                    Box(modifier = Modifier.weight(1f).clip(RoundedCornerShape(9.dp)).background(if (isP2P) MjRed else Color.Black.copy(alpha = 0.45f))
                        .border(1.5.dp, if (isP2P) MjGold else Color.Transparent, RoundedCornerShape(9.dp))
                        .clickable { rmk.setNetworkMode(RmkNetworkMode.LOCAL_LAN) }.padding(vertical = 7.dp), contentAlignment = Alignment.Center) {
                        Text("📡 面对面开房联机 (免流量)", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                    }
                    Box(modifier = Modifier.weight(1f).clip(RoundedCornerShape(9.dp)).background(if (!isP2P) MjBlue else Color.Black.copy(alpha = 0.45f))
                        .border(1.5.dp, if (!isP2P) MjGold else Color.Transparent, RoundedCornerShape(9.dp))
                        .clickable { rmk.setNetworkMode(RmkNetworkMode.ONLINE_SERVER) }.padding(vertical = 7.dp), contentAlignment = Alignment.Center) {
                        Text("☁️ 在线服务器联机", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                    }
                }
                Text(
                    "💡 联机说明：面对面(免流量)仅限安卓设备之间局域网直连；与 iOS / Switch 跨平台同桌请用【在线服务器联机】(可开热点共享网络)",
                    color = MjGold.copy(alpha = 0.95f), fontSize = 10.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(7.dp)).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 8.dp, vertical = 5.dp)
                )
                Column(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.45f)).padding(8.dp)) {
                    val netMode by rmk.networkMode.collectAsState()
                    val isHosting by rmk.isHostingRoom.collectAsState()
                    val isScanning by rmk.isScanningRooms.collectAsState()
                    val discRooms by rmk.discoveredRooms.collectAsState()
                    val directIp by rmk.directConnectIp.collectAsState()
                    val localIp by rmk.localIpAddress.collectAsState()
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(if (netMode == RmkNetworkMode.LOCAL_LAN) "2. 面对面开房联机 (本机IP: $localIp)" else "2. 跨平台远程联机 (2~4人拉密数字牌)", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                        Text("房号:", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(4.dp))
                        BasicTextField(value = roomCode, onValueChange = { rmk.setRoomCode(it) }, textStyle = TextStyle(color = MjGold, fontSize = 12.sp, fontWeight = FontWeight.Black),
                            modifier = Modifier.width(72.dp).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.14f)).padding(6.dp))
                    }
                    Spacer(Modifier.height(6.dp))
                    if (netMode == RmkNetworkMode.LOCAL_LAN) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(if (isHosting) Color(0xFF2E7D32) else MjRed).clickable { rmk.startHostingFaceToFaceRoom() }.padding(vertical = 7.dp), contentAlignment = Alignment.Center) {
                                Text(if (isHosting) "已建房($roomCode)" else "创建面对面房间", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                            Box(modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(MjBlue).clickable { rmk.startScanningFaceToFaceRooms() }.padding(vertical = 7.dp), contentAlignment = Alignment.Center) {
                                Text(if (isScanning) "扫描中..." else "扫描附近房间", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                            if (isHosting) {
                                Box(modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(Color.Gray).clickable { rmk.leaveRoomAndResetLobby() }.padding(horizontal = 9.dp, vertical = 7.dp)) {
                                    Text("退出", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            BasicTextField(value = directIp, onValueChange = { rmk.setDirectConnectIp(it) }, textStyle = TextStyle(color = Color.White, fontSize = 11.sp),
                                modifier = Modifier.weight(1f).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.12f)).padding(7.dp))
                            Box(modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(Color(0xFF00897B)).clickable { rmk.connectDirectToHostIp() }.padding(horizontal = 10.dp, vertical = 7.dp)) {
                                Text("IP直连加入", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                        }
                        discRooms.forEach { rm ->
                            Spacer(Modifier.height(4.dp))
                            Row(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.12f)).clickable { rmk.joinDiscoveredRoom(rm) }.padding(7.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("📡 ${rm.hostName} (房号: ${rm.roomCode})", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                Text("点击加入", color = MjGold, fontSize = 10.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            BasicTextField(value = serverUrl, onValueChange = { rmk.setServerUrl(it) }, textStyle = TextStyle(color = Color.White, fontSize = 11.sp),
                                modifier = Modifier.weight(1f).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.12f)).padding(7.dp))
                            Box(modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(if (isConn) Color(0xFF2E7D32) else Color(0xFF1976D2)).clickable { rmk.connectOnlineServerRoom() }.padding(horizontal = 10.dp, vertical = 7.dp)) {
                                Text(if (isConn) "已连($roomCode)" else "连接房间", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                            if (isConn) {
                                Box(modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(MjRed).clickable { rmk.leaveRoomAndResetLobby() }.padding(horizontal = 9.dp, vertical = 7.dp)) {
                                    Text("退出", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }
                }
                Column(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.45f)).padding(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("3. 房间人数与规则 (真人进房自动替换AI)", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                        listOf(2, 3, 4).forEach { cnt ->
                            val isCntSel = (playerCnt == cnt)
                            Box(
                                modifier = Modifier.padding(start = 5.dp).clip(RoundedCornerShape(6.dp))
                                    .background(if (isCntSel) Color(0xFFFB8C00) else Color.White.copy(alpha = 0.12f))
                                    .border(1.dp, if (isCntSel) MjGold else Color.Transparent, RoundedCornerShape(6.dp))
                                    .clickable(enabled = !isConn || isAuth) { rmk.setRoomPlayerCount(cnt) }
                                    .padding(horizontal = 10.dp, vertical = 4.dp)
                            ) {
                                Text("${cnt}人局", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    }
                    Spacer(Modifier.height(4.dp))
                    Text("• 轻音部定制106张牌：唯(红)/澪(蓝)/律(黄)/紬(绿) 1~13各2张 + 梓喵百搭牌2张\n• 支持 2~4 人自由开房，不足人数由轻音AI补位，真人进房自动替换AI\n• 首次破冰 ≥30分（仅用自己牌架）；破冰后可自由拆解重组桌面；每回合限时60秒", color = Color.White.copy(alpha = 0.88f), fontSize = 10.sp)
                }
                Column(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.45f)).padding(8.dp)) {
                    Text("4. 牌桌座位预览 (${playerCnt}人局 · 1号为房主，真人进房自动替换AI)", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                    Spacer(Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        seats.forEach { s ->
                            Column(modifier = Modifier.weight(1f).clip(RoundedCornerShape(7.dp)).background(Color.White.copy(alpha = 0.09f))
                                .border(1.dp, if (s.isAI) Color.White.copy(alpha = 0.2f) else Color(0xFF00E676), RoundedCornerShape(7.dp)).padding(vertical = 4.dp),
                                horizontalAlignment = Alignment.CenterHorizontally) {
                                allFrames[s.characterId]?.let { bmp -> Image(bitmap = bmp.asImageBitmap(), contentDescription = null, modifier = Modifier.size(26.dp)) }
                                Text(s.name, color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(if (s.isAI) "🤖 AI补位" else "📱 真人玩家", color = if (s.isAI) MjGold else Color(0xFF00E676), fontSize = 7.sp, fontWeight = FontWeight.Bold)
                                Text("${s.score}分", color = Color.White.copy(alpha = 0.8f), fontSize = 8.sp)
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
            val guestWait = isConn && !isAuth
            Box(modifier = Modifier.fillMaxWidth().height(42.dp).clip(RoundedCornerShape(10.dp)).background(if (guestWait) Color.Gray else Color(0xFFFB8C00))
                .border(1.5.dp, MjGold, RoundedCornerShape(10.dp)).clickable(enabled = !guestWait) { rmk.startNewRound() }, contentAlignment = Alignment.Center) {
                Text(if (guestWait) "⏳ 等待 1 号房主开始拉密数字牌..." else "🔢 立即开始拉密数字牌 (${playerCnt}人局 · 30分破冰)", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black)
            }
        }
    } else {
        val myTurn = (turnSeat == mySeat && phase == RmkGamePhase.PLAYING)
        val dispMelds = if (isEditing) workingMelds else tableMelds
        val cols = maxOf(10, rackCols)
        var dragSlotIdx by remember { mutableStateOf<Int?>(null) }
        var dragOffsetX by remember { mutableStateOf(0f) }
        var dragOffsetY by remember { mutableStateOf(0f) }
        var dragTableTileKey by remember { mutableStateOf<Pair<String, String>?>(null) }
        var dragTableOffX by remember { mutableStateOf(0f) }
        var dragTableOffY by remember { mutableStateOf(0f) }
        val meldBoundsMap = remember { mutableStateMapOf<String, Rect>() }
        var tableAreaBounds by remember { mutableStateOf<Rect?>(null) }
        var rackAreaBounds by remember { mutableStateOf<Rect?>(null) }
        val drawAnimProg by animateFloatAsState(targetValue = if (isDrawing) 1f else 0f, animationSpec = spring())

        // Order seats so opponents are at top-left and local player (me) is anchored at bottom-left next to the rack (1:1 like video!)
        val orderedSeats = remember(seats, mySeat) {
            val opps = seats.filter { it.id != mySeat }
            val me = seats.firstOrNull { it.id == mySeat }
            if (me != null) opps + me else opps
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF0E3266))
        ) {
            // Subtle K-ON! HTT Watermark in Center of Table
            Column(
                modifier = Modifier.align(Alignment.Center).offset(y = (-42).dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("放課後ティータイム", color = Color.White.copy(alpha = 0.07f), fontSize = 13.sp, fontWeight = FontWeight.Black)
                Text("K-ON! Rummikub", color = Color.White.copy(alpha = 0.08f), fontSize = 26.sp, fontWeight = FontWeight.Black)
            }

            // Main 3-Column Video Layout: [Left Vertical Player Column] + [Center Full-Height Table & Bottom Rack] + [Right Action Column]
            Row(
                modifier = Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                // 1. LEFT VERTICAL PLAYER COLUMN (1:1 like Video: Circular Avatar + Countdown Ring + Star Badge + Name + Tile Count)
                Column(
                    modifier = Modifier.width(76.dp).fillMaxHeight().padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    orderedSeats.forEach { s ->
                        val iturn = (turnSeat == s.id && phase == RmkGamePhase.PLAYING)
                        val isMe = (s.id == mySeat)
                        val prog = (remSec.toFloat() / 60f).coerceIn(0f, 1f)

                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(modifier = Modifier.size(52.dp), contentAlignment = Alignment.Center) {
                                Box(
                                    modifier = Modifier
                                        .size(46.dp)
                                        .clip(CircleShape)
                                        .background(if (iturn) Color(0xFF1E5096) else Color(0xFF091B38)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    allFrames[s.characterId]?.let { bmp ->
                                        Image(
                                            bitmap = bmp.asImageBitmap(),
                                            contentDescription = null,
                                            modifier = Modifier.size(36.dp).clip(CircleShape)
                                        )
                                    }
                                    if (iturn) {
                                        Box(
                                            modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.38f)),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Text("${remSec}", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                }
                                CircularProgressIndicator(
                                    progress = if (iturn) prog else 1f,
                                    modifier = Modifier.size(50.dp),
                                    color = if (iturn) {
                                        if (remSec <= 10) Color.Red else Color(0xFF59F573)
                                    } else Color.White.copy(alpha = 0.22f),
                                    strokeWidth = if (iturn) 3.8.dp else 2.dp
                                )
                                // Top-Right Star / Icebreak Badge
                                Box(
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .size(16.dp)
                                        .clip(CircleShape)
                                        .background(if (s.hasBrokenIce) Color(0xFFFB8C00) else Color(0xFF284878)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(if (s.hasBrokenIce) "★" else "❄", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
                                }
                            }
                            Spacer(Modifier.height(2.dp))
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Text(
                                    s.name.replace("👑房主 ", "").replace(" (AI)", ""),
                                    color = if (isMe) MjGold else Color.White,
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Black,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.widthIn(max = 44.dp)
                                )
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(4.dp))
                                        .background(Color.Black.copy(alpha = 0.45f))
                                        .padding(horizontal = 4.dp, vertical = 1.dp)
                                ) {
                                    Text("🃏${s.hand.size}", color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }
                }

                // 2. CENTER COLUMN: Full-Height Large-Tile Table + Bottom Fixed 2-Row Wooden Rack
                Column(
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    // Compact Floating Status Bar at Top of Table
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color.Black.copy(alpha = 0.32f))
                            .padding(horizontal = 10.dp, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(banner, color = MjGold, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.weight(1f))
                        if (myTurn) {
                            Spacer(Modifier.width(6.dp))
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(Color(0xFF7B1FA2))
                                    .clickable { rmk.smartHint() }
                                    .padding(horizontal = 8.dp, vertical = 3.dp)
                            ) {
                                Text("💡提示", color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black)
                            }
                            if (selIds.isNotEmpty()) {
                                Spacer(Modifier.width(6.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(Color(0xFFFB8C00))
                                        .clickable {
                                            val brokenIce = seats.getOrNull(mySeat)?.hasBrokenIce == true
                                            if (selectedTableTile != null && brokenIce) {
                                                rmk.combineSelectedRackTilesWithTableTile()
                                            } else {
                                                rmk.placeSelectedAsNewMeld()
                                            }
                                        }
                                        .padding(horizontal = 8.dp, vertical = 3.dp)
                                ) {
                                    Text("⬆️出到桌面", color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }

                    // Full-Height Table Melds Area with LARGE K-ON! Tiles (40x56.dp!)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .onGloballyPositioned { tableAreaBounds = it.boundsInRoot() }
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.Black.copy(alpha = 0.16f))
                            .clickable(enabled = myTurn && selIds.isNotEmpty()) {
                                val brokenIce = seats.getOrNull(mySeat)?.hasBrokenIce == true
                                if (selectedTableTile != null && brokenIce) {
                                    rmk.combineSelectedRackTilesWithTableTile()
                                } else {
                                    rmk.placeSelectedAsNewMeld()
                                }
                            }
                            .padding(6.dp)
                    ) {
                        if (dispMelds.isEmpty()) {
                            Column(
                                modifier = Modifier.align(Alignment.Center),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    "桌面暂无牌组 · 首次破冰需从牌架拖出 ≥30 分牌组",
                                    color = Color.White.copy(alpha = 0.75f),
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    "💡 长按牌架上的牌可自动连选整组顺子/群组，向上拖到桌面即可出牌；破冰后可任意点选/拆解桌面牌重组",
                                    color = MjGold.copy(alpha = 0.90f),
                                    fontSize = 10.sp,
                                    textAlign = TextAlign.Center
                                )
                            }
                        } else {
                            Column(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .verticalScroll(rememberScrollState())
                                    .horizontalScroll(rememberScrollState()),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                dispMelds.chunked(3).forEach { rowMelds ->
                                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                        rowMelds.forEach { meld ->
                                            val ok = RmkEvaluator.evaluateMeld(meld.tiles) != null
                                            Row(
                                                modifier = Modifier
                                                    .onGloballyPositioned { meldBoundsMap[meld.id] = it.boundsInRoot() }
                                                    .clip(RoundedCornerShape(8.dp))
                                                    .background(Color.Black.copy(alpha = 0.28f))
                                                    .border(if (ok) 1.dp else 2.5.dp, if (ok) Color.White.copy(alpha = 0.18f) else Color.Red, RoundedCornerShape(8.dp))
                                                    .padding(4.dp),
                                                horizontalArrangement = Arrangement.spacedBy(2.dp)
                                            ) {
                                                meld.tiles.forEach { t ->
                                                    val isPickedTable = (selectedTableTile?.first == meld.id && selectedTableTile?.second == t.id)
                                                    val isDragTbl = (dragTableTileKey?.first == meld.id && dragTableTileKey?.second == t.id)
                                                    val isHigh = highlightedIds.contains(t.id)
                                                    var tileRootPos by remember { mutableStateOf(Offset.Zero) }
                                                    Box(
                                                        modifier = Modifier
                                                            .onGloballyPositioned { tileRootPos = it.boundsInRoot().center }
                                                            .offset { if (isDragTbl) IntOffset(dragTableOffX.roundToInt(), dragTableOffY.roundToInt()) else IntOffset.Zero }
                                                            .pointerInput(meld.id, t.id, myTurn) {
                                                                if (!myTurn) return@pointerInput
                                                                detectDragGestures(
                                                                    onDragStart = {
                                                                        dragTableTileKey = meld.id to t.id
                                                                        dragTableOffX = 0f
                                                                        dragTableOffY = 0f
                                                                    },
                                                                    onDrag = { change, dragAmount ->
                                                                        change.consume()
                                                                        dragTableOffX += dragAmount.x
                                                                        dragTableOffY += dragAmount.y
                                                                    },
                                                                    onDragEnd = {
                                                                        val dropPt = Offset(tileRootPos.x + dragTableOffX, tileRootPos.y + dragTableOffY)
                                                                        if (rackAreaBounds?.contains(dropPt) == true) {
                                                                            rmk.returnTableTileToRackIfFromThisTurn(meld.id, t.id)
                                                                        } else {
                                                                            val targetMeld = meldBoundsMap.entries.firstOrNull { it.key != meld.id && it.value.inflate(18f).contains(dropPt) }?.key
                                                                            if (targetMeld != null) {
                                                                                rmk.moveTableTile(meld.id, t.id, targetMeld)
                                                                            } else if (tableAreaBounds?.contains(dropPt) == true) {
                                                                                rmk.moveTableTile(meld.id, t.id, null)
                                                                            }
                                                                        }
                                                                        dragTableTileKey = null
                                                                        dragTableOffX = 0f
                                                                        dragTableOffY = 0f
                                                                    },
                                                                    onDragCancel = {
                                                                        dragTableTileKey = null
                                                                        dragTableOffX = 0f
                                                                        dragTableOffY = 0f
                                                                    }
                                                                )
                                                            }
                                                    ) {
                                                        RmkTileCard(
                                                            tile = t,
                                                            selected = isPickedTable || isDragTbl,
                                                            highlighted = isHigh,
                                                            compact = true,
                                                            customW = 38.dp,
                                                            customH = 54.dp,
                                                            onClick = if (myTurn) {
                                                                { rmk.handleTableTileTapOrMove(meld.id, t.id) }
                                                            } else null
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Bottom Fixed 2-Row × 10-Column Wooden Rack (1:1 like Video!)
                    BoxWithConstraints(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(104.dp)
                            .onGloballyPositioned { rackAreaBounds = it.boundsInRoot() }
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFFB57C44))
                            .border(2.dp, Color(0xFFE0AC63), RoundedCornerShape(10.dp))
                            .padding(horizontal = 7.dp, vertical = 4.dp)
                    ) {
                        val slotW = ((maxWidth - 8.dp - 4.dp * (cols - 1)) / cols).coerceIn(26.dp, 50.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth()) {
                            for (row in 0..1) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(if (row == 0) Color(0xFF945E2E) else Color(0xFF825024))
                                        .padding(horizontal = 4.dp, vertical = 2.dp)
                                ) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                        for (col in 0 until cols) {
                                            val slotIdx = row * cols + col
                                            val tileOpt = rackSlots.getOrNull(slotIdx)
                                            var ordinal = 0
                                            for (k in 0..minOf(slotIdx, rackSlots.size - 1)) {
                                                if (rackSlots[k] != null) ordinal++
                                            }
                                            val isDealtVis = !isDealing || ordinal <= dealVisCnt
                                            val isLifted = (liftedIdx == slotIdx) || (dragSlotIdx == slotIdx)

                                            Box(
                                                modifier = Modifier
                                                    .size(width = slotW, height = 43.dp)
                                                    .clip(RoundedCornerShape(5.dp))
                                                    .background(if (liftedIdx != null && tileOpt == null) Color.Yellow.copy(alpha = 0.16f) else Color.Black.copy(alpha = 0.10f))
                                                    .border(1.dp, if (liftedIdx != null) Color.Yellow.copy(alpha = 0.55f) else Color.Black.copy(alpha = 0.20f), RoundedCornerShape(5.dp))
                                                    .pointerInput(slotIdx, cols) {
                                                        detectDragGestures(
                                                            onDragStart = {
                                                                if (rackSlots.getOrNull(slotIdx) != null) {
                                                                    dragSlotIdx = slotIdx
                                                                    dragOffsetX = 0f
                                                                    dragOffsetY = 0f
                                                                }
                                                            },
                                                            onDrag = { change, dragAmount ->
                                                                change.consume()
                                                                dragOffsetX += dragAmount.x
                                                                dragOffsetY += dragAmount.y
                                                            },
                                                            onDragEnd = {
                                                                val curDrag = dragSlotIdx
                                                                if (curDrag != null) {
                                                                    if (dragOffsetY < -85f && tileOpt != null) {
                                                                        val estDrop = tableAreaBounds?.let { tb ->
                                                                            Offset(tb.left + tb.width * ((col + 0.5f) / cols) + dragOffsetX, tb.bottom + dragOffsetY)
                                                                        }
                                                                        val targetMeld = if (estDrop != null) meldBoundsMap.entries.firstOrNull { it.value.inflate(22f).contains(estDrop) }?.key else null
                                                                        rmk.dropRackTilesToTable(tileOpt.id, targetMeld)
                                                                    } else {
                                                                        val stepPx = (size.width + 10).coerceAtLeast(38)
                                                                        val colShift = (dragOffsetX / stepPx).roundToInt()
                                                                        val rowShift = (dragOffsetY / 105f).roundToInt()
                                                                        val dstRow = (row + rowShift).coerceIn(0, 1)
                                                                        val dstCol = (col + colShift).coerceIn(0, cols - 1)
                                                                        rmk.moveRackSlot(curDrag, dstRow * cols + dstCol)
                                                                    }
                                                                }
                                                                dragSlotIdx = null
                                                                dragOffsetX = 0f
                                                                dragOffsetY = 0f
                                                            },
                                                            onDragCancel = {
                                                                dragSlotIdx = null
                                                                dragOffsetX = 0f
                                                                dragOffsetY = 0f
                                                            }
                                                        )
                                                    }
                                                    .combinedClickable(
                                                        onLongClick = {
                                                            if (tileOpt != null) rmk.startLongPressCascadeSelect(slotIdx)
                                                        },
                                                        onClick = {
                                                            val curLifted = liftedIdx
                                                            if (curLifted != null) {
                                                                if (curLifted == slotIdx) {
                                                                    rmk.setLiftedSlot(null)
                                                                    if (tileOpt != null && myTurn) rmk.toggleSelectTile(tileOpt.id)
                                                                } else {
                                                                    rmk.moveRackSlot(curLifted, slotIdx)
                                                                }
                                                            } else if (tileOpt != null) {
                                                                rmk.toggleSelectTile(tileOpt.id)
                                                                rmk.setLiftedSlot(slotIdx)
                                                            }
                                                        }
                                                    ),
                                                contentAlignment = Alignment.Center
                                            ) {
                                                if (tileOpt != null && isDealtVis) {
                                                    val sel = selIds.contains(tileOpt.id) || isLifted
                                                    Box(
                                                        modifier = if (dragSlotIdx == slotIdx) {
                                                            Modifier.offset { IntOffset(dragOffsetX.roundToInt(), dragOffsetY.roundToInt()) }
                                                        } else Modifier
                                                    ) {
                                                        RmkTileCard(
                                                            tile = tileOpt,
                                                            selected = sel,
                                                            highlighted = highlightedIds.contains(tileOpt.id),
                                                            compact = true,
                                                            customW = (slotW - 2.dp).coerceAtLeast(24.dp),
                                                            customH = 41.dp
                                                        )
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

                // 3. RIGHT VERTICAL CONTROL COLUMN (1:1 like Video: Top `«` Exit, Middle `789`/`777`, Bottom Dynamic `+` ⇄ `↺` + `✓`)
                Column(
                    modifier = Modifier.width(60.dp).fillMaxHeight().padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Top-Right `«` Exit Room Button
                    Box(
                        modifier = Modifier
                            .size(width = 46.dp, height = 34.dp)
                            .clip(RoundedCornerShape(17.dp))
                            .background(Color.White.copy(alpha = 0.14f))
                            .border(1.dp, Color.White.copy(alpha = 0.28f), RoundedCornerShape(17.dp))
                            .clickable { rmk.leaveRoomAndResetLobby() },
                        contentAlignment = Alignment.Center
                    ) {
                        Text("«", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Black)
                    }

                    // Middle-Right Unified `789` / `777` Capsule (1:1 like Video!)
                    Column(
                        modifier = Modifier
                            .width(58.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .border(1.5.dp, Color.Cyan.copy(alpha = 0.7f), RoundedCornerShape(12.dp))
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(36.dp)
                                .background(if (sortCol) Color(0xFF2874EA) else Color(0xFF1C3566))
                                .clickable { rmk.organizeRack(preferRuns = true) },
                            contentAlignment = Alignment.Center
                        ) {
                            Text("789", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black)
                        }
                        Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.25f)))
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(36.dp)
                                .background(if (!sortCol) Color(0xFF2874EA) else Color(0xFF1C3566))
                                .clickable { rmk.organizeRack(preferRuns = false) },
                            contentAlignment = Alignment.Center
                        ) {
                            Text("777", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black)
                        }
                    }

                    // Bottom-Right Dynamic Action Area (`+` Draw when not editing table; transforms into Circular `↺` + Tall Green `✓` when editing table!)
                    if (isEditing && myTurn) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            // Circular Red/Orange Undo `↺` Button
                            Box(
                                modifier = Modifier
                                    .size(46.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFF1E3868))
                                    .border(2.dp, Color(0xFFFF5C47), CircleShape)
                                    .clickable { rmk.restoreWorkspaceSnapshot() },
                                contentAlignment = Alignment.Center
                            ) {
                                Text("↺", color = Color(0xFFFF5C47), fontSize = 22.sp, fontWeight = FontWeight.Black)
                            }
                            // Tall Green Confirm `✓` Button
                            Box(
                                modifier = Modifier
                                    .size(width = 56.dp, height = 72.dp)
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(Color(0xFF1B4568))
                                    .border(2.dp, Color(0xFF47F285), RoundedCornerShape(14.dp))
                                    .clickable { rmk.commitMyTurn() },
                                contentAlignment = Alignment.Center
                            ) {
                                Text("✓", color = Color(0xFF47F285), fontSize = 28.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    } else {
                        // Tall `+` Draw Tile Button with Remaining Pool Count (1:1 like Video!)
                        Box(
                            modifier = Modifier
                                .size(width = 56.dp, height = 86.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(if (myTurn) Color(0xFF2A4A7C) else Color(0xFF182C4F))
                                .border(if (myTurn) 2.2.dp else 1.dp, if (myTurn) Color(0xFFFB8C00) else Color.White.copy(alpha = 0.25f), RoundedCornerShape(14.dp))
                                .clickable(enabled = myTurn && !isDrawing) { rmk.drawTilePassTapped() },
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text("+", color = if (myTurn) Color(0xFFFB8C00) else Color.White.copy(alpha = 0.45f), fontSize = 30.sp, fontWeight = FontWeight.Black)
                                Text("🃏$poolCount", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    }
                }
            }

            // End-of-Round Scoreboard Modal Overlay (1:1 like Video 02:45: `游戏结束` + Ranked Players + `再玩一次` / `返回菜单`)
            if (phase == RmkGamePhase.ROUND_OVER) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.58f)),
                    contentAlignment = Alignment.Center
                ) {
                    val ranked = seats.sortedWith(Comparator { a, b ->
                        if (a.hand.size != b.hand.size) a.hand.size - b.hand.size else b.score - a.score
                    })
                    Column(
                        modifier = Modifier
                            .width(360.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xFF142952))
                            .border(1.5.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
                            .padding(18.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text("游戏结束", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
                        ranked.forEachIndexed { idx, s ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (idx == 0) Color.White.copy(alpha = 0.14f) else Color.Black.copy(alpha = 0.28f))
                                    .padding(horizontal = 12.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("${idx + 1}", color = if (idx == 0) MjGold else Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black, modifier = Modifier.width(24.dp))
                                allFrames[s.characterId]?.let { bmp ->
                                    Image(bitmap = bmp.asImageBitmap(), contentDescription = null, modifier = Modifier.size(24.dp))
                                    Spacer(Modifier.width(8.dp))
                                }
                                Text(s.name, color = if (idx == 0) Color(0xFF59F573) else Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.weight(1f))
                                Text("${s.score} 分 (余${s.hand.size}张)", color = if (idx == 0) MjGold else Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            Box(
                                modifier = Modifier
                                    .size(width = 130.dp, height = 38.dp)
                                    .clip(RoundedCornerShape(19.dp))
                                    .background(Color(0xFF288E5F))
                                    .border(1.5.dp, Color(0xFF59F573), RoundedCornerShape(19.dp))
                                    .clickable { rmk.nextRound() },
                                contentAlignment = Alignment.Center
                            ) {
                                Text("再玩一次", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black)
                            }
                            Box(
                                modifier = Modifier
                                    .size(width = 130.dp, height = 38.dp)
                                    .clip(RoundedCornerShape(19.dp))
                                    .background(Color(0xFF2B4B7E))
                                    .border(1.5.dp, Color.Cyan, RoundedCornerShape(19.dp))
                                    .clickable { rmk.leaveRoomAndResetLobby() },
                                contentAlignment = Alignment.Center
                            ) {
                                Text("返回菜单", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    }
                }
            }

            // 1.5s Flying Draw Tile Animation Overlay
            if (isDrawing && drawAnimTile != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .offset(
                            x = (-40 - (drawAnimProg * 180)).dp,
                            y = (-140 + (drawAnimProg * 80)).dp
                        )
                ) {
                    RmkTileCard(tile = drawAnimTile!!, selected = true, compact = false)
                }
            }
        }
    }
}
