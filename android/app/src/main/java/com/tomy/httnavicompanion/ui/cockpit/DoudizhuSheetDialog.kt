package com.tomy.httnavicompanion.ui.cockpit

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.zIndex
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.*
import kotlinx.coroutines.launch

private val DdzBgGreen = Color(0xFF104B2C)
private val DdzCardGreen = Color(0xFF0A331D)
private val DdzGold = Color(0xFFE0B861)
private val DdzRed = Color(0xFFCC2D34)
private val DdzBlue = Color(0xFF1877F2)
private val DdzCream = Color(0xFFFAF2E0)
private val CardRedColor = Color(0xFFD91924)

@Composable
fun KOnDoudizhuSheetDialog(onDismiss: () -> Unit, embeddedInGameRoom: Boolean = false) {
    val context = LocalContext.current
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val engine = manager.doudizhuEngine
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
    val maxMult by engine.maxMultiplier.collectAsState()
    val turnLimit by engine.turnTimeLimit.collectAsState()
    val turnRem by engine.turnRemainingSeconds.collectAsState()
    val allowCounter by engine.allowCardCounter.collectAsState()
    val aiDiff by engine.aiDifficulty.collectAsState()

    val seats by engine.seats.collectAsState()
    val mySeatIdx by engine.mySeatIndex.collectAsState()
    val holeCards by engine.holeCards.collectAsState()
    val selectedIds by engine.selectedCardIds.collectAsState()
    val currentTurn by engine.currentTurnSeat.collectAsState()
    val highestBid by engine.highestBid.collectAsState()
    val multiplier by engine.multiplier.collectAsState()
    val lastValidHand by engine.lastValidHand.collectAsState()
    val lastPlaySeat by engine.lastPlaySeat.collectAsState()
    val statusBanner by engine.statusBanner.collectAsState()
    val playedHistory by engine.playedCardsHistory.collectAsState()

    var showCardCounter by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        launch { while (true) { QQCoinBinder.refreshCoins(context); kotlinx.coroutines.delay(12000) } }
        engine.refreshLocalIpAddress()
    }

    DisposableEffect(Unit) {
        onDispose {
            engine.leaveRoomAndResetLobby()
        }
    }

    val contentBody: @Composable () -> Unit = {
            Column(modifier = Modifier.fillMaxSize().padding(8.dp)) {
                if (!embeddedInGameRoom) {
                // Top Bar (matches iOS 1:1)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(DdzCardGreen)
                            .clickable {
                                engine.leaveRoomAndResetLobby()
                            }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        val canLeaveRoom = (phase != DoudizhuGamePhase.LOBBY || isHosting || isServerConn || connectedPeers.isNotEmpty())
                        Text(
                            if (canLeaveRoom) "< 退出房间" else "♠ 房间大厅",
                            color = DdzGold,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    Text(
                        HTTGameRoomLocalizer.localize("放课后茶会 · 面对面斗地主", lang),
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Black,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )

                    val qqScope = rememberCoroutineScope()
                    val qqUidState by QQCoinBinder.qqUid.collectAsState()
                    val qqCoinsState by QQCoinBinder.coins.collectAsState()
                    val qqStatusState by QQCoinBinder.status.collectAsState()
                    var showQqDialog by remember { mutableStateOf(false) }
                    var qqInput by remember { mutableStateOf(qqUidState) }
                    var qqCode by remember { mutableStateOf("") }
                    LaunchedEffect(Unit) { QQCoinBinder.init(context); QQCoinBinder.refreshCoins(context) }

                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(16.dp))
                                .background(DdzGold)
                                .clickable { qqInput = qqUidState; showQqDialog = true }
                                .padding(horizontal = 8.dp, vertical = 5.dp)
                        ) {
                            Text(if (QQCoinBinder.isBound) "🪙 $qqCoinsState" else "🪙 绑定QQ", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black)
                        }
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(16.dp))
                                .background(DdzCardGreen)
                                .clickable {
                                    engine.leaveRoomAndResetLobby()
                                    onDismiss()
                                }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        ) {
                            Text("✕ 关闭", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    }

                    if (showQqDialog) {
                        AlertDialog(
                            onDismissRequest = { showQqDialog = false },
                            title = { Text("🪙 绑定 QQ 群金币", fontWeight = FontWeight.Bold) },
                            text = {
                                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("仅在线服务器联机且 ≥2 位真人增减 QQ 群金币；金币不足自动按练习局不扣不加。", fontSize = 12.sp)
                                    val anteState by QQCoinBinder.coinAnte.collectAsState()
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Text("底注:", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                        listOf(5, 10, 20, 50).forEach { amt ->
                                            OutlinedButton(
                                                onClick = { QQCoinBinder.setAnte(context, amt) },
                                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp)
                                            ) { Text(if (anteState == amt) "✓${amt}🪙" else "${amt}🪙", fontSize = 11.sp) }
                                        }
                                    }
                                    if (QQCoinBinder.isBound) {
                                        Text("已绑定 QQ：$qqUidState · 当前群金币：$qqCoinsState", fontSize = 12.sp, color = Color(0xFFD97706), fontWeight = FontWeight.Bold)
                                    }
                                    OutlinedTextField(value = qqInput, onValueChange = { qqInput = it }, label = { Text("QQ 号") }, singleLine = true)
                                    Button(onClick = { qqScope.launch { QQCoinBinder.requestCode(qqInput) } }) { Text("发送群机器人验证码") }
                                    OutlinedTextField(value = qqCode, onValueChange = { qqCode = it }, label = { Text("6位私聊验证码") }, singleLine = true)
                                    if (qqStatusState.isNotEmpty()) Text(qqStatusState, fontSize = 12.sp, color = Color(0xFFD97706))
                                }
                            },
                            confirmButton = {
                                TextButton(onClick = {
                                    qqScope.launch {
                                        if (QQCoinBinder.verifyCode(context, qqInput, qqCode)) {
                                            qqCode = ""; showQqDialog = false
                                        }
                                    }
                                }) { Text("确认绑定") }
                            },
                            dismissButton = {
                                TextButton(onClick = { showQqDialog = false }) { Text("关闭") }
                            }
                        )
                    }
                }
                }

                Spacer(Modifier.height(5.dp))

                // Status Banner
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(DdzCardGreen)
                        .border(1.dp, DdzGold.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                ) {
                    Text(HTTGameRoomLocalizer.localize(statusBanner, lang), color = DdzCream, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                }

                Spacer(Modifier.height(6.dp))

                if (phase == DoudizhuGamePhase.LOBBY) {
                    // =====================================================
                    // LOBBY VIEW (1:1 match with iOS + iOS Cross-Play Helper)
                    // =====================================================
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // Mode Switcher Tabs
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val isP2P = networkMode == DoudizhuNetworkMode.FACE_TO_FACE_P2P
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (isP2P) DdzRed else DdzCardGreen)
                                    .border(1.5.dp, if (isP2P) DdzGold else Color.Transparent, RoundedCornerShape(10.dp))
                                    .clickable { engine.setNetworkMode(DoudizhuNetworkMode.FACE_TO_FACE_P2P) }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("📡 面对面开房联机 (免流量)", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (!isP2P) DdzBlue else DdzCardGreen)
                                    .border(1.5.dp, if (!isP2P) DdzGold else Color.Transparent, RoundedCornerShape(10.dp))
                                    .clickable { engine.setNetworkMode(DoudizhuNetworkMode.ONLINE_SERVER) }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("☁️ 在线服务器联机", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                        }
                        Text(
                            "💡 联机说明：面对面(免流量)仅限安卓设备之间局域网/蓝牙直连；与 iOS / Switch 跨平台同桌请用【在线服务器联机】(可开热点共享网络)",
                            color = DdzGold.copy(alpha = 0.95f),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(7.dp)).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 8.dp, vertical = 5.dp)
                        )

                        // 1. Personal Nickname & Character Selection
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text("1. 个人昵称与出战轻音角色选择", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Black)
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text("昵称:", color = Color.LightGray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                OutlinedTextField(
                                    value = nickname,
                                    onValueChange = { engine.setMyNickname(it) },
                                    singleLine = true,
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedTextColor = Color.White,
                                        unfocusedTextColor = Color.White,
                                        focusedBorderColor = DdzGold,
                                        unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                    ),
                                    modifier = Modifier.weight(1f)
                                )
                            }
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                CharacterFilter.fiveIndividuals.forEach { ch ->
                                    val sel = myChar == ch
                                    Column(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(if (sel) DdzRed else Color.Black.copy(alpha = 0.25f))
                                            .border(1.5.dp, if (sel) DdzGold else Color.White.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                                            .clickable { engine.setMyCharacter(ch) }
                                            .padding(vertical = 6.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        allMemberFrames[ch.charId]?.let { bmp ->
                                            Image(
                                                bitmap = bmp.asImageBitmap(),
                                                contentDescription = null,
                                                filterQuality = FilterQuality.None,
                                                modifier = Modifier.size(40.dp)
                                            )
                                        }
                                        Text(ch.displayName(lang), color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                    }
                                }
                            }
                        }

                        // 2. Network Section (P2P Bluetooth+Wi-Fi+iOS Bridge OR Online Server)
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (networkMode == DoudizhuNetworkMode.FACE_TO_FACE_P2P) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text("2. 面对面开房联机 (蓝牙 BLE + P2P Wi-Fi 直连)", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text("房号:", color = Color.LightGray, fontSize = 11.sp)
                                        OutlinedTextField(
                                            value = roomCode,
                                            onValueChange = { engine.setRoomCode(it) },
                                            placeholder = { Text("必填", color = Color.Gray, fontSize = 10.sp) },
                                            singleLine = true,
                                            colors = OutlinedTextFieldDefaults.colors(
                                                focusedTextColor = DdzGold,
                                                unfocusedTextColor = DdzGold,
                                                focusedBorderColor = DdzGold,
                                                unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                            ),
                                            modifier = Modifier.width(80.dp)
                                        )
                                    }
                                }

                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(
                                        onClick = { engine.startHostingFaceToFaceRoom() },
                                        colors = ButtonDefaults.buttonColors(containerColor = if (isHosting) Color(0xFF2E7D32) else DdzRed),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f),
                                        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 8.dp)
                                    ) {
                                        Text(if (isHosting) "📡 房间已开启" else "🏠 创建面对面房间(房主)", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black, maxLines = 1)
                                    }
                                    Button(
                                        onClick = { engine.startScanningFaceToFaceRooms() },
                                        colors = ButtonDefaults.buttonColors(containerColor = if (isScanning) DdzBlue else Color(0xFF1B5E20)),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f),
                                        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 8.dp)
                                    ) {
                                        Text(if (isScanning) "🔍 正在扫描中..." else "📡 扫描并加入附近房间", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black, maxLines = 1)
                                    }
                                }

                                // Cross-platform iOS / Hotspot Quick Connect Bar
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(Color.Black.copy(alpha = 0.32f))
                                        .border(1.dp, DdzGold.copy(alpha = 0.45f), RoundedCornerShape(8.dp))
                                        .padding(8.dp),
                                    verticalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    val wsBridgeAddr = "ws://$localIp:47790"
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(
                                            "📱 本机IP: $localIp  |  原版iOS直连地址: $wsBridgeAddr",
                                            color = DdzGold,
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold,
                                            modifier = Modifier.weight(1f)
                                        )
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(6.dp))
                                                .background(DdzGold)
                                                .clickable {
                                                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                                                    cm?.setPrimaryClip(ClipData.newPlainText("ws_url", wsBridgeAddr))
                                                    Toast.makeText(context, "已复制 $wsBridgeAddr", Toast.LENGTH_SHORT).show()
                                                }
                                                .padding(horizontal = 6.dp, vertical = 3.dp)
                                        ) {
                                            Text("复制地址", color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                    Text(
                                        "💡 与 iOS 联机说明：①若 iOS 为未更新原版，在本机点击【创建面对面房间】后，在 iOS 切到【在线服务器联机】输入 $wsBridgeAddr 点连接即可免流量直连；②若已更新双端，直接扫描或下方输入房主 IP 即可秒连。",
                                        color = Color.LightGray,
                                        fontSize = 9.sp
                                    )
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        OutlinedTextField(
                                            value = directIp,
                                            onValueChange = { engine.setDirectConnectIp(it) },
                                            placeholder = { Text("输入房主IP直连 (如 192.168.1.x 或 172.20.10.1)", color = Color.Gray, fontSize = 10.sp) },
                                            singleLine = true,
                                            colors = OutlinedTextFieldDefaults.colors(
                                                focusedTextColor = Color.White,
                                                unfocusedTextColor = Color.White,
                                                focusedBorderColor = DdzGold,
                                                unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                            ),
                                            modifier = Modifier.weight(1f)
                                        )
                                        Button(
                                            onClick = { engine.connectDirectToHostIp() },
                                            colors = ButtonDefaults.buttonColors(containerColor = DdzBlue),
                                            shape = RoundedCornerShape(8.dp),
                                            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp)
                                        ) {
                                            Text("IP直连", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                }

                                if (connectedPeers.isNotEmpty()) {
                                    Text("✅ 已连入玩家: ${connectedPeers.joinToString(", ")}", color = Color(0xFF00E676), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }

                                if (discoveredRooms.isNotEmpty()) {
                                    discoveredRooms.forEach { room ->
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(8.dp))
                                                .background(Color.Black.copy(alpha = 0.35f))
                                                .border(1.dp, DdzGold, RoundedCornerShape(8.dp))
                                                .clickable { engine.joinDiscoveredRoom(room) }
                                                .padding(horizontal = 10.dp, vertical = 7.dp),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text("${room.hostName} (房号:${room.roomCode})", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                            Text("点击加入 >", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                }
                            } else {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text("2. 在线服务器联机配置", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text("房号:", color = Color.LightGray, fontSize = 11.sp)
                                        OutlinedTextField(
                                            value = roomCode,
                                            onValueChange = { engine.setRoomCode(it) },
                                            placeholder = { Text("必填", color = Color.Gray, fontSize = 10.sp) },
                                            singleLine = true,
                                            colors = OutlinedTextFieldDefaults.colors(
                                                focusedTextColor = DdzGold,
                                                unfocusedTextColor = DdzGold,
                                                focusedBorderColor = DdzGold,
                                                unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                            ),
                                            modifier = Modifier.width(80.dp)
                                        )
                                    }
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    OutlinedTextField(
                                        value = serverUrl,
                                        onValueChange = { engine.setServerUrl(it) },
                                        singleLine = true,
                                        colors = OutlinedTextFieldDefaults.colors(
                                            focusedTextColor = Color.White,
                                            unfocusedTextColor = Color.White,
                                            focusedBorderColor = DdzGold,
                                            unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                        ),
                                        modifier = Modifier.weight(1f)
                                    )
                                    Button(
                                        onClick = { engine.connectOnlineServerRoom() },
                                        colors = ButtonDefaults.buttonColors(containerColor = if (isServerConn) Color(0xFF2E7D32) else DdzBlue),
                                        shape = RoundedCornerShape(10.dp)
                                    ) {
                                        Text(if (isServerConn) "已连($roomCode)" else "连接服务器", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    }
                                    if (isServerConn || connectedPeers.isNotEmpty()) {
                                        Button(
                                            onClick = { engine.leaveRoomAndResetLobby() },
                                            colors = ButtonDefaults.buttonColors(containerColor = DdzRed),
                                            shape = RoundedCornerShape(10.dp)
                                        ) {
                                            Text("断开", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Host Room Rules Settings
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                val canEditRules = isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())
                                Text("3. 房主房间规则设置 (局数/底分/封顶/倒计时/AI难度)", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                Text(if (canEditRules) "第 $currentRound / ${if (totalRounds == 0) "∞" else totalRounds} 局" else "🔒 仅房主可改", color = if (canEditRules) Color(0xFF00E676) else Color(0xFFFFB74D), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            }

                            RuleOptionRow("对局局数:", listOf(3 to "3局", 5 to "5局", 10 to "10局", 0 to "无限局"), totalRounds, DdzRed) { if (isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())) engine.setTotalRounds(it) }
                            RuleOptionRow("倍数封顶:", listOf(16 to "16倍", 32 to "32倍", 64 to "64倍", 0 to "不封顶"), maxMult, Color(0xFF9C27B0)) { if (isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())) engine.setMaxMultiplier(it) }
                            RuleOptionRow("出牌限时:", listOf(15 to "15秒", 25 to "25秒", 30 to "30秒", 0 to "不限时"), turnLimit, DdzBlue) { if (isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())) engine.setTurnTimeLimit(it) }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                Text("辅助与AI:", color = Color.LightGray, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(56.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(7.dp))
                                        .background(if (allowCounter) Color(0xFF2E7D32) else Color.Black.copy(alpha = 0.35f))
                                        .clickable { if (isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())) engine.setAllowCardCounter(!allowCounter) }
                                        .padding(horizontal = 7.dp, vertical = 5.dp)
                                ) {
                                    Text(if (allowCounter) "✓ 记牌器" else "记牌器", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                }
                                DoudizhuAIDifficulty.values().forEach { diff ->
                                    val sel = aiDiff == diff
                                    Box(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(7.dp))
                                            .background(if (sel) Color(0xFFD99426) else Color.Black.copy(alpha = 0.35f))
                                            .clickable { if (isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())) engine.setAIDifficulty(diff) }
                                            .padding(vertical = 5.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(diff.label, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                    }
                                }
                            }
                        }

                        // 4. Current Table Seat Preview
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text("4. 当前牌桌座位预览 (不足3人将由轻音少女 AI 自动补位)", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                seats.forEach { seat ->
                                    Column(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(10.dp))
                                            .background(Color.Black.copy(alpha = 0.28f))
                                            .border(1.dp, if (!seat.isAI) Color(0xFF00E676) else Color.White.copy(alpha = 0.15f), RoundedCornerShape(10.dp))
                                            .padding(8.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        allMemberFrames[seat.character.charId]?.let { bmp ->
                                            Image(
                                                bitmap = bmp.asImageBitmap(),
                                                contentDescription = null,
                                                filterQuality = FilterQuality.None,
                                                modifier = Modifier.size(44.dp)
                                            )
                                        }
                                        Text(seat.name, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(if (seat.isAI) "🤖 轻音AI补位" else "📱 真机玩家", color = if (seat.isAI) Color(0xFF64B5F6) else Color(0xFF00E676), fontSize = 9.sp)
                                        Text("金币: ${seat.score}", color = Color.LightGray, fontSize = 9.sp)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Bottom Start Button (Guest waits for Host)
                    val isGuestWaiting = !isRoomAuthority && (isServerConn || connectedPeers.isNotEmpty())
                    Button(
                        onClick = { if (!isGuestWaiting) engine.startNewGame() },
                        enabled = !isGuestWaiting,
                        colors = ButtonDefaults.buttonColors(containerColor = if (isGuestWaiting) Color.DarkGray else DdzRed),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth().height(44.dp)
                    ) {
                        val roundTxt = if (totalRounds == 0) "无限局" else "${totalRounds}局制"
                        Text(
                            if (isGuestWaiting) "⏳ 等待房主开始牌局 ($roundTxt)..." else "▶ 立即开始牌局 ($roundTxt)",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Black
                        )
                    }
                } else {
                    // =====================================================
                    // ACTIVE GAME TABLE VIEW (1:1 match with iOS ContentView.swift)
                    // =====================================================
                    // Top Hole Cards + Multiplier + Round + Timer + Card Counter Toggle
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        // 3 Hole Cards with top-left rank & suit index badge
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("底牌", color = DdzGold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            val showHole = phase != DoudizhuGamePhase.BIDDING
                            holeCards.forEach { card ->
                                MiniPokerCardView(card = card, faceUp = showHole, app = app)
                            }
                        }

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(DdzRed)
                                .padding(horizontal = 7.dp, vertical = 4.dp)
                        ) {
                            Text("倍数 x$multiplier", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                        }

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(DdzCardGreen)
                                .padding(horizontal = 7.dp, vertical = 4.dp)
                        ) {
                            Text("第$currentRound/${if (totalRounds == 0) "∞" else totalRounds}局", color = DdzCream, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(DdzCardGreen)
                                .padding(horizontal = 7.dp, vertical = 4.dp)
                        ) {
                            Text(if (turnLimit == 0) "⏱ ∞" else "⏱ ${turnRem}s", color = DdzGold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }

                        if (allowCounter) {
                            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(if (showCardCounter) DdzGold else DdzCardGreen)
                                        .clickable { showCardCounter = !showCardCounter }
                                        .padding(horizontal = 7.dp, vertical = 4.dp)
                                ) {
                                    Text("记牌器", color = if (showCardCounter) Color.Black else Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                                }
                                if (isRoomAuthority || (!isHosting && !isServerConn && connectedPeers.isEmpty())) {
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(DdzGold)
                                            .clickable { engine.startNewGame() }
                                            .padding(horizontal = 7.dp, vertical = 4.dp)
                                    ) {
                                        Text("↻", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    }
                                }
                            }
                        }
                    }

                    // Card Counter Strip (ultra-compact in landscape so played cards are NEVER clipped!)
                    if (allowCounter && showCardCounter) {
                        Spacer(Modifier.height(2.dp))
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(6.dp))
                                .background(Color.Black.copy(alpha = 0.42f))
                                .padding(horizontal = 4.dp, vertical = 1.dp),
                            horizontalArrangement = Arrangement.SpaceEvenly
                        ) {
                            (17 downTo 3).forEach { r ->
                                val otherHandsCount = seats.filterIndexed { idx, _ -> idx != mySeatIdx }.sumOf { s -> s.hand.count { it.rank == r } }
                                val holeCount = if (phase == DoudizhuGamePhase.BIDDING) holeCards.count { it.rank == r } else 0
                                val rem = (otherHandsCount + holeCount).coerceAtLeast(0)
                                val lbl = when (r) {
                                    17 -> if (lang == AppLanguage.EN) "BG" else "大王"
                                    16 -> if (lang == AppLanguage.EN) "SM" else "小王"
                                    15 -> "2"; 14 -> "A"; 13 -> "K"; 12 -> "Q"; 11 -> "J"; else -> r.toString()
                                }
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(lbl, color = if (r >= 15) DdzGold else Color.LightGray, fontSize = 7.5.sp, fontWeight = FontWeight.Bold, lineHeight = 8.sp)
                                    Text("$rem", color = if (rem > 0) Color.White else Color.Gray.copy(alpha = 0.4f), fontSize = 9.sp, fontWeight = FontWeight.Black, lineHeight = 10.sp)
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(3.dp))

                    // Opponents Row + Center Table Played Combination Stage
                    if (seats.size == 3) {
                        val prevIdx = (mySeatIdx + 2) % 3
                        val nextIdx = (mySeatIdx + 1) % 3
                        val leftSeat = seats[prevIdx]
                        val rightSeat = seats[nextIdx]

                        Row(
                            modifier = Modifier.fillMaxWidth().weight(1f),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            OpponentSeatBox(
                                seat = leftSeat,
                                isTurn = (currentTurn == prevIdx && phase != DoudizhuGamePhase.FINISHED),
                                phase = phase,
                                spriteBmp = allMemberFrames[leftSeat.character.charId],
                                app = app
                            )

                            // Wide Center Stage: Single-Row 3-Zone Horizontal Arena (上家 | 我方 | 下家) matching iOS 1:1 — zero vertical clipping!
                            val mySeatNow = seats.getOrNull(mySeatIdx)
                            Row(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                                    .padding(horizontal = 4.dp)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(Color.Black.copy(alpha = 0.20f))
                                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                                    .padding(horizontal = 6.dp, vertical = 3.dp),
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                // Left Opponent Played Cards (上家)
                                Box(modifier = Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.CenterStart) {
                                    AnimatedContent(
                                        targetState = leftSeat.lastPlayed.map { it.id } to leftSeat.lastActionText,
                                        transitionSpec = {
                                            (scaleIn(initialScale = 0.76f, animationSpec = spring(dampingRatio = 0.72f, stiffness = 420f)) + fadeIn(tween(160))) togetherWith fadeOut(tween(110))
                                        },
                                        label = "ddz_left_play"
                                    ) { _ ->
                                        if (leftSeat.lastPlayed.isNotEmpty()) {
                                            FittedTablePlayedCardsView(cards = leftSeat.lastPlayed, app = app, compact = true)
                                        } else {
                                            ActionBadge(HTTGameRoomLocalizer.localize("⬅ 上家", lang), HTTGameRoomLocalizer.localize(leftSeat.lastActionText.ifBlank { "等待" }, lang))
                                        }
                                    }
                                }

                                // My Own Played Cards / Status (Center)
                                Box(modifier = Modifier.weight(1.15f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                                    AnimatedContent(
                                        targetState = (mySeatNow?.lastPlayed?.map { it.id } ?: emptyList()) to (mySeatNow?.lastActionText ?: ""),
                                        transitionSpec = {
                                            (scaleIn(initialScale = 0.76f, animationSpec = spring(dampingRatio = 0.72f, stiffness = 420f)) + fadeIn(tween(160))) togetherWith fadeOut(tween(110))
                                        },
                                        label = "ddz_my_play"
                                    ) { _ ->
                                        if (mySeatNow != null && mySeatNow.lastPlayed.isNotEmpty()) {
                                            FittedTablePlayedCardsView(cards = mySeatNow.lastPlayed, app = app, compact = true)
                                        } else if (phase == DoudizhuGamePhase.BIDDING) {
                                            Text("📢 叫地主阶段", color = Color.White.copy(alpha = 0.72f), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                        } else if (mySeatNow != null && mySeatNow.lastActionText.isNotEmpty()) {
                                            Box(
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(8.dp))
                                                    .background(Color.Black.copy(alpha = 0.45f))
                                                    .padding(horizontal = 8.dp, vertical = 3.dp)
                                            ) {
                                                Text(HTTGameRoomLocalizer.localize("我方: ${mySeatNow.lastActionText}", lang), color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                            }
                                        }
                                    }
                                }

                                // Right Opponent Played Cards (下家)
                                Box(modifier = Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.CenterEnd) {
                                    AnimatedContent(
                                        targetState = rightSeat.lastPlayed.map { it.id } to rightSeat.lastActionText,
                                        transitionSpec = {
                                            (scaleIn(initialScale = 0.76f, animationSpec = spring(dampingRatio = 0.72f, stiffness = 420f)) + fadeIn(tween(160))) togetherWith fadeOut(tween(110))
                                        },
                                        label = "ddz_right_play"
                                    ) { _ ->
                                        if (rightSeat.lastPlayed.isNotEmpty()) {
                                            FittedTablePlayedCardsView(cards = rightSeat.lastPlayed, app = app, compact = true)
                                        } else {
                                            ActionBadge(HTTGameRoomLocalizer.localize("下家 ➡", lang), HTTGameRoomLocalizer.localize(rightSeat.lastActionText.ifBlank { "等待" }, lang))
                                        }
                                    }
                                }
                            }

                            OpponentSeatBox(
                                seat = rightSeat,
                                isTurn = (currentTurn == nextIdx && phase != DoudizhuGamePhase.FINISHED),
                                phase = phase,
                                spriteBmp = allMemberFrames[rightSeat.character.charId],
                                app = app
                            )
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Compact Single-Row My Info Badge + Action Buttons, followed by Full-Height Hand Cards
                    val mySeat = seats.getOrNull(mySeatIdx)
                    if (mySeat != null) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(DdzCardGreen)
                                    .border(1.dp, DdzGold.copy(alpha = 0.6f), RoundedCornerShape(8.dp))
                                    .padding(horizontal = 8.dp, vertical = 3.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                allMemberFrames[mySeat.character.charId]?.let { bmp ->
                                    Image(
                                        bitmap = bmp.asImageBitmap(),
                                        contentDescription = null,
                                        filterQuality = FilterQuality.None,
                                        modifier = Modifier.size(22.dp)
                                    )
                                }
                                val roleTag = if (phase == DoudizhuGamePhase.BIDDING) "" else if (mySeat.isLandlord) " 🎩地主" else " 🌾农民"
                                Text(
                                    "${mySeat.name}$roleTag · 余${mySeat.hand.size} · ${mySeat.score}分",
                                    color = Color.White,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Black,
                                    maxLines = 1
                                )
                            }

                            Row(
                                modifier = Modifier.weight(1f),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                when (phase) {
                                    DoudizhuGamePhase.BIDDING -> {
                                        if (currentTurn == mySeatIdx) {
                                            listOf(0 to "不叫", 1 to "1分", 2 to "2分", 3 to "3分").forEach { (b, lbl) ->
                                                val enabled = (b == 0 || b > highestBid)
                                                Button(
                                                    onClick = { if (enabled) engine.submitBid(b) },
                                                    enabled = enabled,
                                                    colors = ButtonDefaults.buttonColors(
                                                        containerColor = when (b) {
                                                            0 -> Color(0xFF424242)
                                                            3 -> DdzRed
                                                            else -> Color(0xFFD99426)
                                                        }
                                                    ),
                                                    shape = RoundedCornerShape(8.dp),
                                                    contentPadding = PaddingValues(vertical = 4.dp),
                                                    modifier = Modifier.weight(1f).height(32.dp)
                                                ) {
                                                    Text(lbl, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                                }
                                            }
                                        } else {
                                            Text(
                                                "⏳ 等待 [${seats.getOrNull(currentTurn)?.name ?: "其他玩家"}] 叫分...",
                                                color = DdzGold,
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                    DoudizhuGamePhase.PLAYING -> {
                                        if (currentTurn == mySeatIdx) {
                                            val canPass = (lastPlaySeat != mySeatIdx && lastPlaySeat != -1)
                                            if (canPass) {
                                                Button(
                                                    onClick = { engine.passTurn() },
                                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF424242)),
                                                    shape = RoundedCornerShape(8.dp),
                                                    contentPadding = PaddingValues(vertical = 4.dp),
                                                    modifier = Modifier.weight(1f).height(32.dp)
                                                ) { Text("不出", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
                                            }
                                            Button(
                                                onClick = { engine.hintCards() },
                                                colors = ButtonDefaults.buttonColors(containerColor = DdzBlue),
                                                shape = RoundedCornerShape(8.dp),
                                                contentPadding = PaddingValues(vertical = 4.dp),
                                                modifier = Modifier.weight(1f).height(32.dp)
                                            ) { Text("提示", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
                                            Button(
                                                onClick = { engine.clearSelection() },
                                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF455A64)),
                                                shape = RoundedCornerShape(8.dp),
                                                contentPadding = PaddingValues(vertical = 4.dp),
                                                modifier = Modifier.weight(1f).height(32.dp)
                                            ) { Text("重选", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
                                            Button(
                                                onClick = { engine.playSelectedCards() },
                                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)),
                                                shape = RoundedCornerShape(8.dp),
                                                contentPadding = PaddingValues(vertical = 4.dp),
                                                modifier = Modifier.weight(1.3f).height(32.dp)
                                            ) { Text("出牌 (${selectedIds.size})", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black) }
                                        } else {
                                            Text(
                                                "⏳ 等待 [${seats.getOrNull(currentTurn)?.name ?: "对手"}] 出牌...",
                                                color = DdzGold,
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                    DoudizhuGamePhase.FINISHED -> {
                                        val inRoom = isServerConn || isHosting || connectedPeers.isNotEmpty()
                                        val isGuestWaiting = inRoom && !isRoomAuthority
                                        Button(
                                            onClick = { if (!isGuestWaiting) engine.startNewGame() },
                                            enabled = !isGuestWaiting,
                                            colors = ButtonDefaults.buttonColors(containerColor = if (isGuestWaiting) Color.DarkGray else DdzRed),
                                            shape = RoundedCornerShape(8.dp),
                                            contentPadding = PaddingValues(vertical = 4.dp),
                                            modifier = Modifier.weight(1f).height(32.dp)
                                        ) {
                                            Text(
                                                if (isGuestWaiting) "⏳ 等待房主..." else "▶ 再来一局",
                                                color = Color.White,
                                                fontSize = 12.sp,
                                                fontWeight = FontWeight.Black
                                            )
                                        }
                                        if (inRoom && isRoomAuthority) {
                                            Button(
                                                onClick = { engine.returnRoomToLobby() },
                                                colors = ButtonDefaults.buttonColors(containerColor = DdzCardGreen),
                                                shape = RoundedCornerShape(8.dp),
                                                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
                                                modifier = Modifier.height(32.dp)
                                            ) { Text("房间设置", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
                                        } else {
                                            Button(
                                                onClick = { engine.leaveRoomAndResetLobby() },
                                                colors = ButtonDefaults.buttonColors(containerColor = DdzCardGreen),
                                                shape = RoundedCornerShape(8.dp),
                                                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
                                                modifier = Modifier.height(32.dp)
                                            ) { Text("退出房间", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
                                        }
                                    }
                                    else -> {}
                                }
                            }
                        }

                        Spacer(Modifier.height(4.dp))

                        var ddzDealtCount by remember(currentRound) { mutableIntStateOf(mySeat.hand.size) }
                        var ddzDealingOrder by remember(currentRound) { mutableStateOf<List<DoudizhuCard>>(emptyList()) }
                        var isDdzDealing by remember(currentRound) { mutableStateOf(false) }
                        LaunchedEffect(phase, currentRound) {
                            if (phase == DoudizhuGamePhase.BIDDING && mySeat.hand.isNotEmpty() && ddzDealingOrder.isEmpty()) {
                                ddzDealingOrder = mySeat.hand.shuffled()
                                isDdzDealing = true
                                ddzDealtCount = 0
                                for (i in 1..mySeat.hand.size) {
                                    kotlinx.coroutines.delay(38L)
                                    ddzDealtCount = i
                                }
                                kotlinx.coroutines.delay(160L)
                                isDdzDealing = false
                            } else if (phase == DoudizhuGamePhase.LOBBY) {
                                isDdzDealing = false
                                ddzDealingOrder = emptyList()
                            }
                        }
                        AdaptivePlayerHandView(
                            hand = if (isDdzDealing) ddzDealingOrder.take(ddzDealtCount) else mySeat.hand,
                            selectedIds = selectedIds,
                            app = app,
                            onToggle = { engine.toggleSelectCard(it) }
                        )
                    }
                }
            }
    }
    if (embeddedInGameRoom) {
        contentBody()
    } else {
        Dialog(
            onDismissRequest = onDismiss,
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth(0.98f)
                    .fillMaxHeight(0.96f)
                    .clip(RoundedCornerShape(18.dp))
                    .border(2.dp, DdzGold, RoundedCornerShape(18.dp)),
                color = DdzBgGreen
            ) {
                contentBody()
            }
        }
    }
}

// ============================================================================
// Adaptive Player Hand View & Center Played Cards View (1:1 with iOS ContentView.swift)
// ============================================================================
@Composable
private fun AdaptivePlayerHandView(
    hand: List<DoudizhuCard>,
    selectedIds: Set<String>,
    app: HTTNaviApp,
    onToggle: (String) -> Unit
) {
    BoxWithConstraints(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        val usableWidth = (maxWidth - 4.dp).coerceAtLeast(240.dp)
        FittedHandCardRow(
            cards = hand,
            selectedIds = selectedIds,
            usableWidth = usableWidth,
            app = app,
            onToggle = onToggle
        )
    }
}

@Composable
private fun FittedHandCardRow(
    cards: List<DoudizhuCard>,
    selectedIds: Set<String>,
    usableWidth: Dp,
    app: HTTNaviApp,
    onToggle: (String) -> Unit
) {
    val count = cards.size
    if (count == 0) return
    val cardW = if (count > 14) ((usableWidth / (count * 0.54f + 0.46f)).coerceIn(32.dp, 46.dp)) else 48.dp
    val cardH = (cardW * 1.38f).coerceIn(48.dp, 68.dp)

    val rawStep = if (count > 1) (usableWidth - cardW) / (count - 1) else 0.dp
    val step = if (count > 1) rawStep.coerceIn(16.dp, 32.dp) else 0.dp
    val totalRowWidth = if (count > 1) cardW + step * (count - 1) else cardW

    Box(
        modifier = Modifier
            .width(totalRowWidth)
            .height(cardH + 10.dp),
        contentAlignment = Alignment.TopStart
    ) {
        cards.forEachIndexed { idx, card ->
            val isSel = selectedIds.contains(card.id)
            Box(
                modifier = Modifier
                    .offset(x = step * idx, y = if (isSel) 0.dp else 10.dp)
                    .zIndex(idx.toFloat())
            ) {
                HandPokerCardView(
                    card = card,
                    isSelected = isSel,
                    cardW = cardW,
                    cardH = cardH,
                    app = app,
                    onClick = { onToggle(card.id) }
                )
            }
        }
    }
}

@Composable
private fun FittedTablePlayedCardsView(
    cards: List<DoudizhuCard>,
    app: HTTNaviApp,
    compact: Boolean = false
) {
    BoxWithConstraints(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        val usableW = (maxWidth - 4.dp).coerceAtLeast(120.dp)
        if (cards.size > 7 && maxWidth < 320.dp) {
            val topCount = (cards.size + 1) / 2
            val r1 = cards.subList(0, topCount)
            val r2 = cards.subList(topCount, cards.size)
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy((-14).dp)
            ) {
                SingleFittedTableRow(r1, usableW, app, compact)
                SingleFittedTableRow(r2, usableW, app, compact)
            }
        } else {
            SingleFittedTableRow(cards, usableW, app, compact)
        }
    }
}

@Composable
private fun SingleFittedTableRow(
    cards: List<DoudizhuCard>,
    usableW: Dp,
    app: HTTNaviApp,
    compact: Boolean = false
) {
    val cardW = if (compact) 39.dp else 44.dp
    val cardH = if (compact) 54.dp else 62.dp
    val count = cards.size
    if (count == 0) return

    val rawStep = if (count > 1) (usableW - cardW) / (count - 1) else 0.dp
    val step = if (count > 1) rawStep.coerceIn(15.dp, 26.dp) else 0.dp
    val totalW = if (count > 1) cardW + step * (count - 1) else cardW

    Box(
        modifier = Modifier
            .width(totalW)
            .height(cardH),
        contentAlignment = Alignment.TopStart
    ) {
        cards.forEachIndexed { idx, card ->
            Box(
                modifier = Modifier
                    .offset(x = step * idx)
                    .zIndex(idx.toFloat())
            ) {
                TablePokerCardView(card = card, cardW = cardW, cardH = cardH, app = app)
            }
        }
    }
}

// ============================================================================
// Poker Card Components with Crisp Top-Left Rank & Suit Index Badges (1:1 iOS)
// ============================================================================
@Composable
private fun HandPokerCardView(
    card: DoudizhuCard,
    isSelected: Boolean,
    cardW: Dp,
    cardH: Dp,
    app: HTTNaviApp,
    onClick: () -> Unit
) {
    val bmp = app.assetDecryptor.getDoudizhuCardBitmap(card.cardImageKey)
    val indexColor = if (card.isRedCard) CardRedColor else Color.Black

    Column(
        modifier = Modifier
            .size(cardW, cardH)
            .shadow(3.dp, RoundedCornerShape(7.dp))
            .clip(RoundedCornerShape(7.dp))
            .background(Color.White)
            .border(
                width = if (isSelected) 2.5.dp else 1.dp,
                color = if (isSelected) DdzGold else Color.White.copy(alpha = 0.88f),
                shape = RoundedCornerShape(7.dp)
            )
            .clickable { onClick() }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(16.dp)
                .background(Color.White)
                .padding(horizontal = 3.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(1.5.dp)
        ) {
            Text(
                text = card.rankLabel,
                color = indexColor,
                fontSize = if (card.rank >= 16) 8.5.sp else 11.sp,
                fontWeight = FontWeight.Black,
                lineHeight = 11.sp
            )
            if (card.rank < 16) {
                Text(
                    text = card.suit.symbol,
                    color = indexColor,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Bold,
                    lineHeight = 10.sp
                )
            }
        }
        if (bmp != null) {
            Image(
                bitmap = bmp.asImageBitmap(),
                contentDescription = card.rankLabel,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().weight(1f)
            )
        } else {
            Spacer(modifier = Modifier.fillMaxWidth().weight(1f))
        }
    }
}

@Composable
private fun TablePokerCardView(
    card: DoudizhuCard,
    cardW: Dp,
    cardH: Dp,
    app: HTTNaviApp
) {
    val bmp = app.assetDecryptor.getDoudizhuCardBitmap(card.cardImageKey)
    val indexColor = if (card.isRedCard) CardRedColor else Color.Black

    Column(
        modifier = Modifier
            .size(cardW, cardH)
            .shadow(2.dp, RoundedCornerShape(6.dp))
            .clip(RoundedCornerShape(6.dp))
            .background(Color.White)
            .border(1.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(6.dp))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(14.dp)
                .background(Color.White)
                .padding(horizontal = 2.5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(1.dp)
        ) {
            Text(
                text = card.rankLabel,
                color = indexColor,
                fontSize = if (card.rank >= 16) 7.5.sp else 9.5.sp,
                fontWeight = FontWeight.Black,
                lineHeight = 10.sp
            )
            if (card.rank < 16) {
                Text(
                    text = card.suit.symbol,
                    color = indexColor,
                    fontSize = 8.5.sp,
                    fontWeight = FontWeight.Bold,
                    lineHeight = 9.sp
                )
            }
        }
        if (bmp != null) {
            Image(
                bitmap = bmp.asImageBitmap(),
                contentDescription = card.rankLabel,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().weight(1f)
            )
        } else {
            Spacer(modifier = Modifier.fillMaxWidth().weight(1f))
        }
    }
}

@Composable
private fun MiniPokerCardView(
    card: DoudizhuCard,
    faceUp: Boolean,
    app: HTTNaviApp
) {
    val bmp = app.assetDecryptor.getDoudizhuCardBitmap(if (faceUp) card.cardImageKey else "back")
    val indexColor = if (card.isRedCard) CardRedColor else Color.Black

    Column(
        modifier = Modifier
            .size(32.dp, 44.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(Color.White)
            .border(1.dp, DdzGold, RoundedCornerShape(4.dp))
    ) {
        if (faceUp) {
            Row(
                modifier = Modifier.fillMaxWidth().height(11.dp).background(Color.White).padding(horizontal = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (card.rank >= 16) card.rankLabel else "${card.rankLabel}${card.suit.symbol}",
                    color = indexColor,
                    fontSize = if (card.rank >= 16) 6.sp else 7.sp,
                    fontWeight = FontWeight.Black,
                    lineHeight = 9.sp
                )
            }
        }
        if (bmp != null) {
            Image(
                bitmap = bmp.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().weight(1f)
            )
        } else {
            Spacer(modifier = Modifier.fillMaxWidth().weight(1f))
        }
    }
}

@Composable
private fun RuleOptionRow(
    label: String,
    options: List<Pair<Int, String>>,
    selectedVal: Int,
    activeColor: Color,
    onSelect: (Int) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(label, color = Color.LightGray, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(56.dp))
        options.forEach { (v, txt) ->
            val sel = v == selectedVal
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(7.dp))
                    .background(if (sel) activeColor else Color.Black.copy(alpha = 0.35f))
                    .clickable { onSelect(v) }
                    .padding(vertical = 5.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(txt, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
    }
}

@Composable
private fun OpponentSeatBox(
    seat: DoudizhuPlayerSeat,
    isTurn: Boolean,
    phase: DoudizhuGamePhase,
    spriteBmp: android.graphics.Bitmap?,
    app: HTTNaviApp
) {
    val backBmp = app.assetDecryptor.getDoudizhuCardBitmap("back")
    val stackCount = minOf(6, maxOf(1, (seat.hand.size + 2) / 3))
    Column(
        modifier = Modifier
            .width(114.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color.Black.copy(alpha = 0.52f))
            .border(if (isTurn) 2.dp else 1.dp, if (isTurn) Color(0xFF00E676) else Color.White.copy(alpha = 0.22f), RoundedCornerShape(12.dp))
            .padding(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(contentAlignment = Alignment.TopEnd) {
                if (spriteBmp != null) {
                    Image(
                        bitmap = spriteBmp.asImageBitmap(),
                        contentDescription = null,
                        filterQuality = FilterQuality.None,
                        modifier = Modifier.size(32.dp, 36.dp)
                    )
                }
                if (phase != DoudizhuGamePhase.BIDDING) {
                    Text(if (seat.isLandlord) "🎩" else "🌾", fontSize = 12.sp)
                }
            }
            Column {
                Text(
                    seat.name,
                    color = Color.White,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text("金币:${seat.score}", color = Color.LightGray, fontSize = 9.sp)
            }
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (seat.hand.isNotEmpty()) {
                Box(modifier = Modifier.width((16 + (stackCount - 1) * 5).dp).height(23.dp)) {
                    for (idx in 0 until stackCount) {
                        if (backBmp != null) {
                            Image(
                                bitmap = backBmp.asImageBitmap(),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .offset(x = (idx * 5).dp)
                                    .size(20.dp, 29.dp)
                                    .clip(RoundedCornerShape(3.dp))
                                    .border(0.9.dp, DdzGold, RoundedCornerShape(3.dp))
                            )
                        } else {
                            Box(
                                modifier = Modifier
                                    .offset(x = (idx * 6).dp)
                                    .size(20.dp, 29.dp)
                                    .clip(RoundedCornerShape(3.dp))
                                    .background(DdzRed)
                                    .border(0.9.dp, DdzGold, RoundedCornerShape(3.dp))
                            )
                        }
                    }
                }
            }
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(if (seat.hand.size <= 2) Color(0xFFD32F2F) else Color.Black.copy(alpha = 0.65f))
                    .border(0.8.dp, DdzGold.copy(alpha = 0.5f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 5.dp, vertical = 2.dp)
            ) {
                Text(
                    "余${seat.hand.size}张",
                    color = if (seat.hand.size <= 2) Color.White else DdzGold,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Black,
                    maxLines = 1,
                    softWrap = false
                )
            }
        }
    }
}

@Composable
private fun ActionBadge(direction: String, action: String) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(DdzCardGreen)
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(direction, color = Color.LightGray, fontSize = 9.sp)
        Text(action, color = DdzGold, fontSize = 10.sp, fontWeight = FontWeight.Black, maxLines = 1)
    }
}
