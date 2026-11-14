package com.tomy.httnavicompanion.ui.cockpit

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
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

private val DdzBgGreen = Color(0xFF104B2C)
private val DdzCardGreen = Color(0xFF0A331D)
private val DdzGold = Color(0xFFE0B861)
private val DdzRed = Color(0xFFCC2D34)
private val DdzBlue = Color(0xFF1877F2)
private val DdzCream = Color(0xFFFAF2E0)
private val CardRedColor = Color(0xFFD91924)

@Composable
fun KOnDoudizhuSheetDialog(onDismiss: () -> Unit) {
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
        engine.refreshLocalIpAddress()
    }

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
            Column(modifier = Modifier.fillMaxSize().padding(8.dp)) {
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
                                if (phase != DoudizhuGamePhase.LOBBY) {
                                    engine.leaveRoomAndResetLobby()
                                }
                            }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text(
                            if (phase == DoudizhuGamePhase.LOBBY) "♠ 房间大厅" else "< 退出房间",
                            color = DdzGold,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    Text(
                        "放课后茶会 · 面对面斗地主",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Black,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )

                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(DdzCardGreen)
                            .clickable { onDismiss() }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text("✕ 关闭", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
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
                    Text(statusBanner, color = DdzCream, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 2)
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
                                        Text(if (isServerConn) "已连接" else "连接服务器", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
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
                                Text("3. 房主房间规则设置 (局数/底分/封顶/倒计时/AI难度)", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                Text("第 $currentRound / ${if (totalRounds == 0) "∞" else totalRounds} 局", color = Color(0xFF00E676), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            }

                            RuleOptionRow("对局局数:", listOf(3 to "3局", 5 to "5局", 10 to "10局", 0 to "无限局"), totalRounds, DdzRed) { engine.setTotalRounds(it) }
                            RuleOptionRow("每局底分:", listOf(50 to "50分", 100 to "100分", 200 to "200分", 500 to "500分"), baseScore, Color(0xFFD99426)) { engine.setBaseScore(it) }
                            RuleOptionRow("倍数封顶:", listOf(16 to "16倍", 32 to "32倍", 64 to "64倍", 0 to "不封顶"), maxMult, Color(0xFF9C27B0)) { engine.setMaxMultiplier(it) }
                            RuleOptionRow("出牌限时:", listOf(15 to "15秒", 25 to "25秒", 30 to "30秒", 0 to "不限时"), turnLimit, DdzBlue) { engine.setTurnTimeLimit(it) }

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
                                        .clickable { engine.setAllowCardCounter(!allowCounter) }
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
                                            .clickable { engine.setAIDifficulty(diff) }
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
                                        Text("积分: ${seat.score}", color = Color.LightGray, fontSize = 9.sp)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Bottom Start Button
                    Button(
                        onClick = { engine.startNewGame() },
                        colors = ButtonDefaults.buttonColors(containerColor = DdzRed),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth().height(44.dp)
                    ) {
                        val roundTxt = if (totalRounds == 0) "无限局" else "${totalRounds}局制"
                        Text("▶ 立即开始牌局 ($roundTxt · 底分 $baseScore)", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black)
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
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (showCardCounter) DdzGold else DdzCardGreen)
                                    .clickable { showCardCounter = !showCardCounter }
                                    .padding(horizontal = 7.dp, vertical = 4.dp)
                            ) {
                                Text("记牌器", color = if (showCardCounter) Color.Black else Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    }

                    // Card Counter Strip
                    if (allowCounter && showCardCounter) {
                        Spacer(Modifier.height(5.dp))
                        val myHand = seats.getOrNull(mySeatIdx)?.hand ?: emptyList()
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(Color.Black.copy(alpha = 0.42f))
                                .padding(horizontal = 4.dp, vertical = 3.dp),
                            horizontalArrangement = Arrangement.SpaceEvenly
                        ) {
                            (17 downTo 3).forEach { r ->
                                val total = if (r >= 16) 1 else 4
                                val played = playedHistory.count { it.rank == r }
                                val mine = myHand.count { it.rank == r }
                                val rem = (total - played - mine).coerceAtLeast(0)
                                val lbl = when (r) {
                                    17 -> "大王"; 16 -> "小王"; 15 -> "2"; 14 -> "A"; 13 -> "K"; 12 -> "Q"; 11 -> "J"; else -> r.toString()
                                }
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(lbl, color = if (r >= 15) DdzGold else Color.LightGray, fontSize = 8.sp, fontWeight = FontWeight.Bold)
                                    Text("$rem", color = if (rem > 0) Color.White else Color.Gray.copy(alpha = 0.4f), fontSize = 10.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

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

                            // Wide Center Stage for Played Card Combinations (100% visible, never clipped!)
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                                    .padding(horizontal = 6.dp)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(Color.Black.copy(alpha = 0.22f))
                                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                                    .padding(6.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    ActionBadge("⬅ 上家", leftSeat.lastActionText.ifBlank { "等待中" })
                                    ActionBadge("下家 ➡", rightSeat.lastActionText.ifBlank { "等待中" })
                                }

                                val activeHand = lastValidHand
                                if (activeHand != null && activeHand.cards.isNotEmpty()) {
                                    val playOwnerName = seats.getOrNull(lastPlaySeat)?.name ?: ""
                                    Column(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(4.dp)
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(10.dp))
                                                .background(DdzRed.copy(alpha = 0.88f))
                                                .border(1.dp, DdzGold, RoundedCornerShape(10.dp))
                                                .padding(horizontal = 8.dp, vertical = 2.dp)
                                        ) {
                                            Text(
                                                "$playOwnerName · ${activeHand.type.label} (${activeHand.cards.size}张)",
                                                color = Color.White,
                                                fontSize = 10.sp,
                                                fontWeight = FontWeight.Black,
                                                maxLines = 1
                                            )
                                        }

                                        FittedTablePlayedCardsView(cards = activeHand.cards, app = app)
                                    }
                                } else {
                                    Text(
                                        if (phase == DoudizhuGamePhase.BIDDING) "📢 叫地主阶段 · 请选择叫分" else "🃏 等待出牌...",
                                        color = Color.White.copy(alpha = 0.55f),
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }

                                val mySeatNow = seats.getOrNull(mySeatIdx)
                                Text(
                                    if (mySeatNow != null && mySeatNow.lastActionText.isNotEmpty()) "我的状态: ${mySeatNow.lastActionText}" else "",
                                    color = DdzGold,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                )
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

                    // Action Buttons Row (Bid / Play / Hint / Pass / Play Again)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        when (phase) {
                            DoudizhuGamePhase.BIDDING -> {
                                if (currentTurn == mySeatIdx) {
                                    listOf(0 to "不叫", 1 to "1 分", 2 to "2 分", 3 to "3 分").forEach { (b, lbl) ->
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
                                            shape = RoundedCornerShape(10.dp),
                                            contentPadding = PaddingValues(vertical = 8.dp),
                                            modifier = Modifier.weight(1f)
                                        ) {
                                            Text(lbl, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                } else {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(
                                            "等待 [${seats.getOrNull(currentTurn)?.name ?: "其他玩家"}] 叫分...",
                                            color = DdzGold,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                            DoudizhuGamePhase.PLAYING -> {
                                if (currentTurn == mySeatIdx) {
                                    val canPass = (lastPlaySeat != mySeatIdx && lastPlaySeat != -1)
                                    if (canPass) {
                                        Button(
                                            onClick = { engine.passTurn() },
                                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF424242)),
                                            shape = RoundedCornerShape(10.dp),
                                            contentPadding = PaddingValues(vertical = 8.dp),
                                            modifier = Modifier.weight(1f)
                                        ) { Text("不出", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                                    }
                                    Button(
                                        onClick = { engine.hintCards() },
                                        colors = ButtonDefaults.buttonColors(containerColor = DdzBlue),
                                        shape = RoundedCornerShape(10.dp),
                                        contentPadding = PaddingValues(vertical = 8.dp),
                                        modifier = Modifier.weight(1f)
                                    ) { Text("提示", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                                    Button(
                                        onClick = { engine.clearSelection() },
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF455A64)),
                                        shape = RoundedCornerShape(10.dp),
                                        contentPadding = PaddingValues(vertical = 8.dp),
                                        modifier = Modifier.weight(1f)
                                    ) { Text("重选", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                                    Button(
                                        onClick = { engine.playSelectedCards() },
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)),
                                        shape = RoundedCornerShape(10.dp),
                                        contentPadding = PaddingValues(vertical = 8.dp),
                                        modifier = Modifier.weight(1.3f)
                                    ) { Text("出牌 (${selectedIds.size})", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black) }
                                } else {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(
                                            "等待 [${seats.getOrNull(currentTurn)?.name ?: "对手"}] 出牌...",
                                            color = DdzGold,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                            DoudizhuGamePhase.FINISHED -> {
                                Button(
                                    onClick = { engine.startNewGame() },
                                    colors = ButtonDefaults.buttonColors(containerColor = DdzRed),
                                    shape = RoundedCornerShape(10.dp),
                                    modifier = Modifier.weight(1f)
                                ) { Text("▶ 再来一局", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black) }
                                Button(
                                    onClick = { engine.leaveRoomAndResetLobby() },
                                    colors = ButtonDefaults.buttonColors(containerColor = DdzCardGreen),
                                    shape = RoundedCornerShape(10.dp)
                                ) { Text("返回大厅", color = DdzGold, fontSize = 13.sp, fontWeight = FontWeight.Bold) }
                            }
                            else -> {}
                        }
                    }

                    Spacer(Modifier.height(4.dp))

                    // =====================================================
                    // Adaptive 1-Row / 2-Row Player Hand Area (100% visible, zero clipping!)
                    // =====================================================
                    val mySeat = seats.getOrNull(mySeatIdx)
                    if (mySeat != null) {
                        AdaptivePlayerHandView(
                            hand = mySeat.hand,
                            selectedIds = selectedIds,
                            app = app,
                            onToggle = { engine.toggleSelectCard(it) }
                        )

                        Spacer(Modifier.height(6.dp))

                        // Bottom Player Status Bar
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(DdzCardGreen)
                                .border(1.dp, DdzGold.copy(alpha = 0.6f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                allMemberFrames[mySeat.character.charId]?.let { bmp ->
                                    Image(
                                        bitmap = bmp.asImageBitmap(),
                                        contentDescription = null,
                                        filterQuality = FilterQuality.None,
                                        modifier = Modifier.size(30.dp)
                                    )
                                }
                                Text(
                                    "${mySeat.name} ${if (mySeat.isLandlord) "[🎩地主]" else "[🌾农民]"} · 手牌:${mySeat.hand.size}张 · 积分:${mySeat.score}",
                                    color = Color.White,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (currentTurn == mySeatIdx) Color(0xFF2E7D32) else Color.DarkGray)
                                    .padding(horizontal = 8.dp, vertical = 3.dp)
                            ) {
                                Text(
                                    if (currentTurn == mySeatIdx) "👉 轮到你" else "等待中",
                                    color = Color.White,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Black
                                )
                            }
                        }
                    }
                }
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
        val isPortraitTwoRows = maxWidth < 520.dp && hand.size > 10

        if (isPortraitTwoRows) {
            val topCount = (hand.size + 1) / 2
            val topCards = hand.subList(0, topCount)
            val bottomCards = hand.subList(topCount, hand.size)
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy((-20).dp)
            ) {
                FittedHandCardRow(
                    cards = topCards,
                    selectedIds = selectedIds,
                    usableWidth = usableWidth,
                    app = app,
                    onToggle = onToggle
                )
                FittedHandCardRow(
                    cards = bottomCards,
                    selectedIds = selectedIds,
                    usableWidth = usableWidth,
                    app = app,
                    onToggle = onToggle
                )
            }
        } else {
            FittedHandCardRow(
                cards = hand,
                selectedIds = selectedIds,
                usableWidth = usableWidth,
                app = app,
                onToggle = onToggle
            )
        }
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
    val cardW = 60.dp
    val cardH = 86.dp
    val count = cards.size
    if (count == 0) return

    val rawStep = if (count > 1) (usableWidth - cardW) / (count - 1) else 0.dp
    val step = if (count > 1) rawStep.coerceIn(19.dp, 36.dp) else 0.dp
    val totalRowWidth = if (count > 1) cardW + step * (count - 1) else cardW

    Box(
        modifier = Modifier
            .width(totalRowWidth)
            .height(cardH + 14.dp),
        contentAlignment = Alignment.TopStart
    ) {
        cards.forEachIndexed { idx, card ->
            val isSel = selectedIds.contains(card.id)
            Box(
                modifier = Modifier
                    .offset(x = step * idx, y = if (isSel) 0.dp else 14.dp)
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
    app: HTTNaviApp
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
                SingleFittedTableRow(r1, usableW, app)
                SingleFittedTableRow(r2, usableW, app)
            }
        } else {
            SingleFittedTableRow(cards, usableW, app)
        }
    }
}

@Composable
private fun SingleFittedTableRow(
    cards: List<DoudizhuCard>,
    usableW: Dp,
    app: HTTNaviApp
) {
    val cardW = 46.dp
    val cardH = 66.dp
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

    Box(
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
        if (bmp != null) {
            Image(
                bitmap = bmp.asImageBitmap(),
                contentDescription = card.rankLabel,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Crisp Top-Left Corner Index Badge so overlapped cards in a 20-card fan are 100% readable!
        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 2.5.dp, top = 2.5.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Color.White.copy(alpha = 0.92f))
                .padding(horizontal = 3.dp, vertical = 1.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = card.rankLabel,
                color = indexColor,
                fontSize = if (card.rank >= 16) 9.sp else 12.sp,
                fontWeight = FontWeight.Black,
                lineHeight = 12.sp
            )
            if (card.rank < 16) {
                Text(
                    text = card.suit.symbol,
                    color = indexColor,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    lineHeight = 10.sp
                )
            }
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

    Box(
        modifier = Modifier
            .size(cardW, cardH)
            .shadow(2.dp, RoundedCornerShape(6.dp))
            .clip(RoundedCornerShape(6.dp))
            .background(Color.White)
            .border(1.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(6.dp))
    ) {
        if (bmp != null) {
            Image(
                bitmap = bmp.asImageBitmap(),
                contentDescription = card.rankLabel,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 2.dp, top = 2.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Color.White.copy(alpha = 0.92f))
                .padding(horizontal = 2.5.dp, vertical = 1.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = card.rankLabel,
                color = indexColor,
                fontSize = if (card.rank >= 16) 8.sp else 10.sp,
                fontWeight = FontWeight.Black,
                lineHeight = 10.sp
            )
            if (card.rank < 16) {
                Text(
                    text = card.suit.symbol,
                    color = indexColor,
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    lineHeight = 8.sp
                )
            }
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

    Box(
        modifier = Modifier
            .size(32.dp, 44.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(Color.White)
            .border(1.dp, DdzGold, RoundedCornerShape(4.dp))
    ) {
        if (bmp != null) {
            Image(
                bitmap = bmp.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
        if (faceUp) {
            Text(
                text = if (card.rank >= 16) card.rankLabel else "${card.suit.symbol}${card.rankLabel}",
                color = indexColor,
                fontSize = if (card.rank >= 16) 6.sp else 7.sp,
                fontWeight = FontWeight.Black,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(1.5.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(Color.White.copy(alpha = 0.90f))
                    .padding(horizontal = 2.dp)
            )
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
    Column(
        modifier = Modifier
            .width(80.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color.Black.copy(alpha = 0.48f))
            .border(if (isTurn) 2.dp else 1.dp, if (isTurn) Color(0xFF00E676) else Color.White.copy(alpha = 0.18f), RoundedCornerShape(12.dp))
            .padding(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Box(contentAlignment = Alignment.TopEnd) {
            if (spriteBmp != null) {
                Image(
                    bitmap = spriteBmp.asImageBitmap(),
                    contentDescription = null,
                    filterQuality = FilterQuality.None,
                    modifier = Modifier.size(44.dp, 50.dp)
                )
            }
            if (phase != DoudizhuGamePhase.BIDDING) {
                Text(if (seat.isLandlord) "🎩" else "🌾", fontSize = 12.sp)
            }
        }
        Text(
            seat.name,
            color = Color.White,
            fontSize = 10.sp,
            fontWeight = FontWeight.Black,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            if (backBmp != null) {
                Image(
                    bitmap = backBmp.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(14.dp, 20.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .border(0.8.dp, DdzGold, RoundedCornerShape(2.dp))
                )
            }
            Text(
                "${seat.hand.size}",
                color = if (seat.hand.size <= 2) Color.Red else DdzGold,
                fontSize = 13.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Black
            )
        }
        Text("积分:${seat.score}", color = Color.LightGray, fontSize = 9.sp)
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
