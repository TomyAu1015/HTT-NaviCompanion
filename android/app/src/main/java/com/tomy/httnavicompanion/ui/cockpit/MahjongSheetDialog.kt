package com.tomy.httnavicompanion.ui.cockpit

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.ui.zIndex
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.os.Build
import android.view.ViewGroup
import android.view.WindowManager
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
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
import kotlinx.coroutines.launch
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


object HTTGameRoomLocalizer {
    private val enPhrases = listOf(
        "欢迎来到广东红中麻将！红中为赖子，不能吃，可碰杠胡" to "Welcome to Hongzhong Mahjong! Red Dragon is Wild, Pong/Kong/Self-Draw Win",
        "欢迎来到拉密数字牌！首次出牌需 ≥30 分破冰，支持 2~4 人跨平台同桌" to "Welcome to Rummikub! Initial icebreak requires ≥30 pts (2-4 Players)",
        "欢迎来到轻音拉密数字牌 (2~4人自由开房 · 30分破冰 · 60秒限时)" to "Welcome to K-ON! Rummikub (2-4P · 30pt Icebreak · 60s Timer)",
        "欢迎来到放课后茶会斗地主！支持面对面开房与在线联机" to "Welcome to HTT Doudizhu! Face-to-Face P2P & Online Multiplayer",
        "已退出拉密数字牌房间" to "Left Rummikub room",
        "已退出麻将房间，座位已重置为单人+AI补位" to "Left Mahjong room — reset to solo + AI",
        "已复原到本回合初始牌面与牌架位置" to "Restored table & rack to start of turn",
        "桌面存在无效牌组，请继续重组或点【复原】" to "Invalid table group(s) — complete ≥3 tiles per group or tap ↺",
        "尚未破冰！不能拆解其他玩家的桌面牌组" to "Not broken ice yet! Cannot split other players' table melds",
        "尚未破冰：请选中≥3张且总分≥30的牌组后再拖上桌面" to "Drag tiles to table to assemble ≥30 pts for initial icebreak",
        "已拆出单牌到桌面空位，可继续拖动组牌" to "Detached tile to table — drag other tiles onto it to combine",
        "已将桌面牌拖入目标牌组" to "Merged tile into target group",
        "正在派发 14 张初始手牌 (1.5秒发牌动画)... 轮到" to "Dealing 14 initial tiles... Turn:",
        "正在派发 14 张初始手牌 (1.5 秒发牌动画)... 轮到" to "Dealing 14 initial tiles... Turn:",
        "正在从摸牌区抽取 1 张新牌飞入牌架空位..." to "Drawing 1 tile into empty rack slot...",
        "正在从牌堆摸取 1 张新牌 (1.5秒摸牌动画)..." to "Drawing 1 tile into empty rack slot...",
        "正在从牌堆摸取 1 张新牌 (1.5 秒摸牌动画)..." to "Drawing 1 tile into empty rack slot...",
        "摸牌结束回合 · 轮到" to "drew 1 tile · Turn:",
        "从共用牌堆摸 1 张牌 · 轮到" to "drew 1 tile · Turn:",
        "(需≥30分破冰)" to "(Need ≥30 pts icebreak)",
        "当前暂无可出顺子（未混入同数群组）" to "No valid runs found (groups excluded)",
        "当前暂无可出同数群组（未混入顺子）" to "No valid groups found (runs excluded)",
        "789类型组合" to "789 Run Sort",
        "777(888)类型组合" to "777 Group Sort",
        "共识别" to "Found",
        "组可出牌型（已自动留空隔开，不混入其他类型）" to "valid meld(s) (auto-spaced)",
        "等待玩家响应 胡/杠/碰" to "Waiting for Win / Kong / Pong",
        "等待响应 胡/杠/碰" to "Waiting for Win / Kong / Pong",
        "坐庄先出牌 (红中为赖子)" to "starts as Dealer (Red Dragon Wild)",
        "坐庄先出牌 (红中=赖子)" to "starts as Dealer (Red Dragon Wild)",
        "摸牌出牌" to "Draw & Discard",
        "请出牌" to "Your turn to discard",
        "正在叫地主阶段..." to "Bidding for Landlord...",
        "等待其他玩家叫地主..." to "Waiting for other players to bid...",
        "等待其他玩家响应..." to "Waiting for other players...",
        "叫分 (当前最高:" to "bidding (Highest:",
        "成为地主！获得3张底牌，请先出牌" to "is Landlord! Received 3 hole cards",
        "地主胜利!" to "Landlord Wins!",
        "农民胜利!" to "Peasants Win!",
        "本局流局，无人胡牌！" to "Draw round — no winner!",
        "荒庄流局（牌墙已摸完）" to "Draw Round (Wall Empty)",
        "有红中摸4马" to "With Red Dragon: 4 Horses",
        "无红中摸6马" to "No Red Dragon: 6 Horses",
        "摸马中" to "Horses Hit: ",
        "四红中自摸" to "4 Red Dragons Self-Draw",
        "自摸胡牌" to "Self-Draw Win",
        "自摸胡!" to "Self-Draw Win!",
        "自摸胡" to "Self-Draw",
        "明杠" to "Exposed Kong",
        "暗杠" to "Concealed Kong",
        "补杠" to "Added Kong",
        "碰了" to "Ponged",
        "单张" to "Single",
        "单張" to "Single",
        "对子" to "Pair",
        "對子" to "Pair",
        "三不带" to "Triple",
        "三不帶" to "Triple",
        "三带一" to "Triple+1",
        "三帶一" to "Triple+1",
        "三带二" to "Triple+2",
        "三帶二" to "Triple+2",
        "顺子" to "Straight",
        "順子" to "Straight",
        "连对" to "Pairs Run",
        "連對" to "Pairs Run",
        "飞机带翅膀" to "Airplane+Wings",
        "飞机" to "Airplane",
        "飛機" to "Airplane",
        "四带二" to "Quad+2",
        "四帶二" to "Quad+2",
        "炸弹" to "Bomb",
        "炸彈" to "Bomb",
        "王炸" to "Rocket",
        "红中" to "Red Dragon",
        "发财" to "Green Dragon",
        "白板" to "White Dragon",
        "东风" to "East Wind",
        "南风" to "South Wind",
        "西风" to "West Wind",
        "北风" to "North Wind",
        "上家" to "Left",
        "下家" to "Right",
        "我方" to "Me",
        "等待中" to "Waiting",
        "打出" to "Play",
        "不叫" to "Pass",
        "不出" to "Pass",
        "要不起" to "Pass",
        "出牌" to "Play",
        "轮到" to "Turn:",
        "第 " to "Round ",
        "第" to "Round ",
        " 局开始！" to " Started!",
        "局开始！" to " Started!",
        "房主" to "Host",
        "轻音车友" to "HTT Driver",
        "轻音雀友" to "HTT Player",
        "平泽唯" to "Yui",
        "秋山澪" to "Mio",
        "田井中律" to "Ritsu",
        "琴吹紬" to "Mugi",
        "中野梓" to "Azusa",
        "万" to " Wan",
        "条" to " Bam",
        "筒" to " Dot",
        "余 " to "Left: ",
        "余" to "Left:",
        "张" to "",
        "匹" to "",
        "分" to " pts"
    )

    private val hantPhrases = listOf(
        "广东红中麻将" to "廣東紅中麻雀",
        "红中麻将" to "紅中麻雀",
        "麻将房间" to "麻雀房間",
        "麻将大厅" to "麻雀大廳",
        "麻将房主" to "麻雀房主",
        "开始麻将" to "開始麻雀",
        "麻将房" to "麻雀房",
        "4人麻将" to "4人麻雀",
        "麻将" to "麻雀",
        "麻將" to "麻雀",
        "放课后茶会" to "放課後茶會",
        "放课后棋牌室" to "放課後棋牌室",
        "放课后斗地主" to "放課後鬥地主",
        "面对面" to "面對面",
        "开房联机" to "開房聯機",
        "在线服务器" to "在線伺服器",
        "服务器" to "伺服器",
        "联机说明" to "聯機說明",
        "仅限" to "僅限",
        "之间直连" to "之間直連",
        "局域网" to "局域網",
        "蓝牙" to "藍牙",
        "直连" to "直連",
        "跨平台同桌请用" to "跨平台同桌請用",
        "可开热点共享网络" to "可開熱點共享網絡",
        "昵称与轻音角色" to "暱稱與輕音角色",
        "昵称与角色" to "暱稱與角色",
        "个人昵称与出战轻音角色选择" to "個人暱稱與出戰輕音角色選擇",
        "昵称" to "暱稱",
        "必填房号" to "必填房號",
        "房号" to "房號",
        "创建" to "創建",
        "房间" to "房間",
        "已退出拉密数字牌房间" to "已退出拉密數字牌房間",
        "拉密数字牌" to "拉密數字牌",
        "数字牌" to "數字牌",
        "已开房" to "已開房",
        "扫描" to "掃描",
        "连接" to "連接",
        "已连" to "已連",
        "规则" to "規則",
        "设置" to "設置",
        "局数" to "局數",
        "无限" to "無限",
        "封顶" to "封頂",
        "限时" to "限時",
        "辅助" to "輔助",
        "记牌器" to "記牌器",
        "休闲" to "休閒",
        "标准" to "標準",
        "大师" to "大師",
        "当前" to "當前",
        "预览" to "預覽",
        "1号为房主" to "1號為房主",
        "1号房主" to "1號房主",
        "不足4人由轻音AI补位" to "不足4人由輕音AI補位",
        "真人进房自动替换AI" to "真人進房自動替換AI",
        "轻音AI补位" to "輕音AI補位",
        "AI补位" to "AI補位",
        "真机玩家" to "真機玩家",
        "真人玩家" to "真人玩家",
        "金币" to "金幣",
        "立即开始" to "立即開始",
        "等待" to "等待",
        "开始" to "開始",
        "响应" to "響應",
        "红中为赖子" to "紅中為賴子",
        "红中赖子" to "紅中賴子",
        "四红中" to "四紅中",
        "有红中摸4马" to "有紅中摸4馬",
        "无红中摸6马" to "無紅中摸6馬",
        "摸马" to "摸馬",
        "中马" to "中馬",
        "马" to "馬",
        "红中" to "紅中",
        "赖子" to "賴子",
        "赖" to "賴",
        "轮到" to "輪到",
        "摸牌" to "摸牌",
        "出牌" to "出牌",
        "请出牌" to "請出牌",
        "点选" to "點選",
        "点击" to "點擊",
        "取消" to "取消",
        "听牌" to "聽牌",
        "提示" to "提示",
        "过" to "過",
        "杠" to "槓",
        "胡牌" to "糊牌",
        "自摸胡" to "自摸糊",
        "胡!" to "糊!",
        "荒庄流局" to "荒莊流局",
        "再来一局" to "再來一局",
        "整场金币排名" to "整場金幣排名",
        "地主胜利" to "地主勝利",
        "农民胜利" to "農民勝利",
        "农民" to "農民",
        "阶段" to "階段",
        "重选" to "重選",
        "单张" to "單張",
        "单張" to "單張",
        "对子" to "對子",
        "三不带" to "三不帶",
        "三带一" to "三帶一",
        "三带二" to "三帶二",
        "顺子" to "順子",
        "连对" to "連對",
        "飞机带翅膀" to "飛機帶翅膀",
        "飞机" to "飛機",
        "四带二" to "四帶二",
        "炸弹" to "炸彈",
        "万" to "萬",
        "条" to "條",
        "东" to "東",
        "发" to "發",
        "庄" to "莊",
        "余 " to "餘 ",
        "余" to "餘",
        "张" to "張",
        "秒" to "秒",
        "首次破冰需从牌架拖出" to "首次破冰需從牌架拖出",
        "桌面暂无牌组" to "桌面暫無牌組",
        "破冰后可任意" to "破冰後可任意",
        "尚未破冰" to "尚未破冰",
        "不能拆解其他玩家的桌面牌组" to "不能拆解其他玩家的桌面牌組",
        "已复原到本回合初始牌面与牌架位置" to "已復原到本回合初始牌面與牌架位置",
        "桌面存在无效牌组" to "桌面存在無效牌組",
        "复原" to "復原",
        "确认出牌" to "確認出牌",
        "已拆出单牌到桌面空位" to "已拆出單牌到桌面空位",
        "已将桌面牌拖入目标牌组" to "已將桌面牌拖入目標牌組",
        "已暂放牌组" to "已暫放牌組",
        "已暂放桌面" to "已暫放桌面",
        "类型组合" to "類型組合",
        "共识别" to "共識別",
        "组可出牌型" to "組可出牌型",
        "已自动留空隔开，不混入其他类型" to "已自動留空隔開，不混入其他類型",
        "当前暂无可出顺子" to "當前暫無可出順子",
        "未混入同数群组" to "未混入同數群組",
        "未混入顺子" to "未混入順子",
        "群组" to "群組",
        "牌组" to "牌組",
        "牌架" to "牌架",
        "牌堆" to "牌堆",
        "正在派发" to "正在派發",
        "初始手牌" to "初始手牌",
        "发牌动画" to "發牌動畫",
        "正在从摸牌区抽取" to "正在從摸牌區抽取",
        "飞入牌架空位" to "飛入牌架空位",
        "正在从牌堆摸取" to "正在從牌堆摸取",
        "摸牌动画" to "摸牌動畫",
        "结束回合" to "結束回合",
        "从共用牌堆摸" to "從共用牌堆摸",
        "轻音车友" to "輕音車友",
        "轻音雀友" to "輕音雀友",
        "平泽唯" to "平澤唯",
        "秋山澪" to "秋山澪",
        "琴吹紬" to "琴吹紬"
    )

    fun localize(text: String, lang: AppLanguage): String = when (lang) {
        AppLanguage.ZH_HANS -> text
        AppLanguage.ZH_HANT -> {
            var out = text
            for ((k, v) in hantPhrases) {
                out = out.replace(k, v)
            }
            out
        }
        AppLanguage.EN -> {
            var out = text
            for ((k, v) in enPhrases) {
                out = out.replace(k, v)
            }
            out
        }
    }
}

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
    val grScope = rememberCoroutineScope()
    val grQqCoins by QQCoinBinder.coins.collectAsState()
    val grQqToken by QQCoinBinder.qqToken.collectAsState()
    val grQqUid by QQCoinBinder.qqUid.collectAsState()
    val grQqBound = grQqToken.isNotEmpty() && grQqUid.isNotEmpty()
    val grQqAnte by QQCoinBinder.coinAnte.collectAsState()
    val grQqStatus by QQCoinBinder.status.collectAsState()
    var showGrQqDialog by remember { mutableStateOf(false) }
    var grQqInput by remember { mutableStateOf(grQqUid) }
    var grCodeInput by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        QQCoinBinder.init(context)
        grQqInput = QQCoinBinder.qqUid.value
        while (true) {
            QQCoinBinder.refreshCoins(context)
            kotlinx.coroutines.delay(12000)
        }
    }

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

    // True 100% edge-to-edge full-screen overlay (replaces Dialog so main cockpit NEVER peeks out on any Android aspect ratio!)
    val hostView = LocalView.current
    DisposableEffect(inLobbyNow) {
        val win = activity?.window
        if (win != null) {
            WindowCompat.setDecorFitsSystemWindows(win, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val lp = win.attributes
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                win.attributes = lp
            }
            val ctrl = WindowInsetsControllerCompat(win, hostView)
            if (!inLobbyNow) {
                ctrl.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                ctrl.hide(WindowInsetsCompat.Type.systemBars())
            } else {
                ctrl.show(WindowInsetsCompat.Type.systemBars())
            }
        }
        onDispose {
            val w = activity?.window
            if (w != null) {
                WindowCompat.setDecorFitsSystemWindows(w, true)
                WindowInsetsControllerCompat(w, hostView).show(WindowInsetsCompat.Type.systemBars())
            }
        }
    }

    BackHandler {
        if (!inLobbyNow) {
            if (selectedGame == 0) ddzEngine.leaveRoomAndResetLobby()
            else if (selectedGame == 1) mjEngine.leaveRoomAndResetLobby()
            else rmkEngine.leaveRoomAndResetLobby()
        } else {
            ddzEngine.leaveRoomAndResetLobby()
            mjEngine.leaveRoomAndResetLobby()
            rmkEngine.leaveRoomAndResetLobby()
            onDismiss()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .zIndex(100f)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = if (selectedGame == 0) Color(0xFF104B2C) else if (selectedGame == 2 && !inLobbyNow) Color(0xFF0E3266) else MjBgGreen
        ) {
            val containerMod = if (!inLobbyNow) {
                Modifier.fillMaxSize().displayCutoutPadding()
            } else {
                Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()
            }
            Column(modifier = containerMod) {
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
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(Color(0xFF2B220A))
                                    .border(1.dp, MjGold.copy(alpha = 0.7f), RoundedCornerShape(16.dp))
                                    .clickable {
                                        grQqInput = QQCoinBinder.qqUid.value
                                        grScope.launch { QQCoinBinder.refreshCoins(context, manual = true) }
                                        showGrQqDialog = true
                                    }
                                    .padding(horizontal = 9.dp, vertical = 5.dp)
                            ) {
                                Text(
                                    if (grQqBound) "🪙 $grQqCoins" else "🪙 绑定QQ",
                                    color = MjGold,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Black,
                                    maxLines = 1
                                )
                            }
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
                        }
                    } else {
                        Spacer(Modifier.width(72.dp))
                    }
                }
                }

                if (showGrQqDialog) {
                    AlertDialog(
                        onDismissRequest = { showGrQqDialog = false },
                        title = { Text("🪙 绑定 QQ 群金币", fontWeight = FontWeight.Black) },
                        text = {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("仅「在线服务器联机且 ≥2 名真人」增减 QQ 群金币；未登录仅可使用面对面或本地 AI。", fontSize = 12.sp)
                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text("底注:", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                    listOf(5, 10, 20, 50).forEach { amt ->
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(8.dp))
                                                .background(if (grQqAnte == amt) Color(0xFFF59E0B) else Color.Gray.copy(alpha = 0.25f))
                                                .clickable { QQCoinBinder.setAnte(context, amt) }
                                                .padding(horizontal = 8.dp, vertical = 4.dp)
                                        ) {
                                            Text("${amt}🪙", fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false, color = if (grQqAnte == amt) Color.Black else Color.Unspecified)
                                        }
                                    }
                                }
                                if (grQqBound) {
                                    Text("已绑定 QQ: $grQqUid · 当前群金币: $grQqCoins 🪙", color = Color(0xFFD97706), fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                }
                                OutlinedTextField(value = grQqInput, onValueChange = { grQqInput = it }, label = { Text("输入 QQ 号") }, singleLine = true)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(onClick = { grScope.launch { QQCoinBinder.requestCode(grQqInput) } }) { Text("发验证码") }
                                    if (grQqBound) {
                                        OutlinedButton(onClick = { grScope.launch { QQCoinBinder.refreshCoins(context, manual = true) } }) { Text("刷新") }
                                        OutlinedButton(onClick = { QQCoinBinder.unbind(context) }) { Text("解绑") }
                                    }
                                }
                                OutlinedTextField(value = grCodeInput, onValueChange = { grCodeInput = it }, label = { Text("6位私聊验证码") }, singleLine = true)
                                Button(onClick = {
                                    grScope.launch {
                                        if (QQCoinBinder.verifyCode(context, grQqInput, grCodeInput)) {
                                            grCodeInput = ""; showGrQqDialog = false
                                        }
                                    }
                                }) { Text("确认绑定") }
                                if (grQqStatus.isNotEmpty()) Text(grQqStatus, fontSize = 11.sp, color = Color(0xFFD97706))
                            }
                        },
                        confirmButton = { TextButton(onClick = { showGrQqDialog = false }) { Text("关闭") } }
                    )
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
                                tr("🃏 斗地主(3人)", "🃏 鬥地主(3人)", "🃏 Doudizhu"),
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
                                tr("🀄 红中麻将(4人)", "🀄 紅中麻雀(4人)", "🀄 Mahjong"),
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
                                tr("🔢 拉密牌 (2-4人)", "🔢 拉密牌 (2-4人)", "🔢 Rummikub"),
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
    val activeDiscardFlight by engine.activeDiscardFlight.collectAsState()
    val horseTiles by engine.horseTiles.collectAsState()
    val hitHorseIds by engine.hitHorseIds.collectAsState()
    val lastWinScoreDelta by engine.lastWinScoreDelta.collectAsState()
    val lastWinHasRedDragon by engine.lastWinHasRedDragon.collectAsState()
    val aiDifficulty by engine.aiDifficulty.collectAsState()
    val lastClaimEvent by engine.lastClaimEvent.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        launch { while (true) { QQCoinBinder.refreshCoins(context); kotlinx.coroutines.delay(12000) } }
        engine.refreshLocalIpAddress() }
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
                    Text(HTTGameRoomLocalizer.localize("放课后茶会 · 广东红中麻将", lang), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black, maxLines = 1)
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
                    Text(HTTGameRoomLocalizer.localize(statusBanner, lang), color = MjCream, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 2)
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
                                Text(HTTGameRoomLocalizer.localize("3. 广东红中麻将规则 (红中赖子·不能吃·可碰杠)", lang), color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
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
                        Text(HTTGameRoomLocalizer.localize(if (isGuestWaiting) "⏳ 等待1号房主开始麻将..." else "🀄 立即开始广东红中麻将 (底分 $baseScore)", lang), color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black)
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
                                Text(HTTGameRoomLocalizer.localize("余 $wallCount 张 · 第${currentRound}局 · ⏱${turnRem}s", lang), color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
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

                    Column(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                        verticalArrangement = Arrangement.SpaceBetween,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        seats.getOrNull(oppIdx)?.let { opp ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                MjSeatMelds(opp)
                                if (opp.melds.isNotEmpty() && opp.discards.isNotEmpty()) Spacer(Modifier.width(6.dp))
                                MjDiscardRiver(opp, maxCols = 12, isHorizontalSeat = true)
                            }
                        }

                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        // Left Seat with Standing Vertical Tile Wall
                        Row(modifier = Modifier.weight(0.35f), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
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
                            modifier = Modifier.weight(0.30f),
                            contentAlignment = Alignment.Center
                        ) {
                            val cl = pendingClaim
                            val ev = lastClaimEvent
                            val flight = activeDiscardFlight
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
                                        Text(HTTGameRoomLocalizer.localize(ev.seatName, lang), color = Color.White, fontSize = 9.sp, maxLines = 1)
                                        Text("💥 ${HTTGameRoomLocalizer.localize("${ev.actionLabel} ${ev.tile.fullName}", lang)}!", color = Color.Yellow, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                    }
                                    MjTileCard(ev.tile, 24.dp, 33.dp, isSelected = false, isHighlight = true)
                                }
                            } else if (flight != null) {
                                val rel = (flight.seatIndex - mySeatIdx + 4) % 4
                                val offX = when (rel) { 1 -> 34.dp; 3 -> (-34).dp; else -> 0.dp }
                                val offY = when (rel) { 0 -> 22.dp; 2 -> (-22).dp; else -> 0.dp }
                                Column(
                                    modifier = Modifier.offset(x = offX, y = offY),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Text(
                                        HTTGameRoomLocalizer.localize("${flight.seatName} 打出 ${flight.tile.fullName}", lang),
                                        color = Color.Yellow,
                                        fontSize = 9.5.sp,
                                        fontWeight = FontWeight.Black,
                                        modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(Color.Black.copy(alpha = 0.78f)).padding(horizontal = 6.dp, vertical = 2.dp)
                                    )
                                    Spacer(Modifier.height(2.dp))
                                    MjTileCard(flight.tile, 32.dp, 44.dp, isSelected = false, isHighlight = true)
                                }
                            } else when {
                                cl != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(HTTGameRoomLocalizer.localize("⚡ 响应牌", lang), color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    Spacer(Modifier.height(4.dp))
                                    MjTileCard(cl.tile, 36.dp, 50.dp, isSelected = false, isHighlight = true)
                                }
                                phase == MahjongGamePhase.ROUND_OVER -> Column(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(Color(0xFF0A2E1F).copy(alpha = 0.96f))
                                        .border(2.dp, MjGold, RoundedCornerShape(12.dp))
                                        .padding(horizontal = 10.dp, vertical = 6.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    val wSeat = winnerSeat?.let { seats.getOrNull(it) }
                                    if (wSeat != null) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            allMemberFrames[wSeat.character.charId]?.let { bmp ->
                                                Image(bitmap = bmp.asImageBitmap(), contentDescription = null, filterQuality = FilterQuality.None, modifier = Modifier.size(30.dp))
                                            }
                                            Column {
                                                Text(
                                                    "🎉 ${HTTGameRoomLocalizer.localize(wSeat.name, lang)} +${maxOf(baseScore * 2, lastWinScoreDelta)}",
                                                    color = Color.Yellow, fontSize = 11.sp, fontWeight = FontWeight.Black, maxLines = 1
                                                )
                                                Text(
                                                    HTTGameRoomLocalizer.localize(winReason, lang),
                                                    color = MjGold, fontSize = 8.5.sp, fontWeight = FontWeight.Bold, maxLines = 2
                                                )
                                            }
                                        }
                                        if (horseTiles.isNotEmpty()) {
                                            val hitCnt = horseTiles.count { hitHorseIds.contains(it.id) }
                                            Text(
                                                HTTGameRoomLocalizer.localize(
                                                    if (lastWinHasRedDragon) "🐎 有红中摸4马 · 中${hitCnt}马" else "🐎 无红中摸6马 · 中${hitCnt}马",
                                                    lang
                                                ),
                                                color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black
                                            )
                                            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                                horseTiles.forEach { ht ->
                                                    val isHit = hitHorseIds.contains(ht.id)
                                                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                                        MjTileCard(ht, 20.dp, 28.dp, isSelected = false, isHighlight = isHit)
                                                        if (isHit) {
                                                            Text(if (lang == AppLanguage.EN) "HIT" else if (lang == AppLanguage.ZH_HANT) "中馬" else "中马", color = Color.Yellow, fontSize = 7.sp, fontWeight = FontWeight.Black)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    } else {
                                        Text(HTTGameRoomLocalizer.localize("🌊 荒庄流局", lang), color = Color.Yellow, fontSize = 15.sp, fontWeight = FontWeight.Black)
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
                                            Text(if (lang == AppLanguage.EN) "N" else "北", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == oppIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == oppIdx) MjRed else Color.Transparent).padding(horizontal = 8.dp, vertical = 1.dp))
                                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                                Text(if (lang == AppLanguage.EN) "W" else "西", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == leftIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == leftIdx) MjRed else Color.Transparent).padding(horizontal = 3.dp, vertical = 4.dp))
                                                Box(
                                                    modifier = Modifier.size(32.dp).clip(RoundedCornerShape(16.dp)).background(Color(0xFF0A3A46)).border(1.5.dp, MjGold, RoundedCornerShape(16.dp)),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Text("$turnRem", color = if (turnRem <= 5) Color.Red else Color.Cyan, fontSize = 14.sp, fontWeight = FontWeight.Black)
                                                }
                                                Text(if (lang == AppLanguage.EN) "E" else if (lang == AppLanguage.ZH_HANT) "東" else "东", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == rightIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == rightIdx) MjRed else Color.Transparent).padding(horizontal = 3.dp, vertical = 4.dp))
                                            }
                                            Text(if (lang == AppLanguage.EN) "S" else "南", fontSize = 9.sp, fontWeight = FontWeight.Black, color = if (currentTurn == mySeatIdx) Color.Yellow else Color.White.copy(alpha = 0.45f), modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (currentTurn == mySeatIdx) MjRed else Color.Transparent).padding(horizontal = 8.dp, vertical = 1.dp))
                                        }
                                        if (ting.isNotEmpty()) {
                                            Box(
                                                modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(MjGold).clickable { showTingPopup = !showTingPopup }.padding(horizontal = 8.dp, vertical = 2.dp)
                                            ) {
                                                Text(HTTGameRoomLocalizer.localize("💡 听牌 (${ting.size})", lang), color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.Black)
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
                        Row(modifier = Modifier.weight(0.35f), horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                            seats.getOrNull(rightIdx)?.let { rSeat ->
                                Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    MjSeatBadge(rSeat, currentTurn == rightIdx, allMemberFrames[rSeat.character.charId])
                                    MjSeatMelds(rSeat)
                                    MjDiscardRiver(rSeat, maxCols = 6)
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

                        // My Own Discard River inside Middle Arena so it is NEVER clipped!
                        val meForRiver = seats.getOrNull(mySeatIdx)
                        if (meForRiver != null && meForRiver.discards.isNotEmpty()) {
                            MjDiscardRiver(meForRiver, maxCols = 12, isHorizontalSeat = true)
                        }
                    }

                    // Compact Single-Line My Info + Action Bar + Melds & Hand Row
                    val me = seats.getOrNull(mySeatIdx)
                    if (me != null) {
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
                                Text(HTTGameRoomLocalizer.localize("${me.name}${if (me.isDealer) "[庄]" else ""} · ${me.score}分", lang), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
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
                                        Text(HTTGameRoomLocalizer.localize("⏳ 等待其他玩家响应...", lang), color = MjGold, fontSize = 11.sp)
                                    }
                                } else if (phase == MahjongGamePhase.PLAYING && currentTurn == mySeatIdx) {
                                    if (engine.canDeclareSelfHu()) {
                                        Button(onClick = { engine.declareSelfHu() }, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = MjRed), modifier = Modifier.weight(1f).height(32.dp)) { Text(HTTGameRoomLocalizer.localize("🀄 自摸胡!", lang), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black) }
                                    }
                                    engine.selfKongOptions().firstOrNull()?.let { kt ->
                                        Button(onClick = { engine.declareSelfKong(kt) }, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD99426)), modifier = Modifier.height(32.dp)) { Text(HTTGameRoomLocalizer.localize("杠 ${kt.fullName}", lang), color = Color.White, fontSize = 11.sp) }
                                    }
                                    val selTile = me.hand.firstOrNull { it.id == selectedTileId }
                                    if (selTile != null) {
                                        Button(onClick = { engine.discardTile(selTile) }, contentPadding = PaddingValues(vertical = 4.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)), modifier = Modifier.weight(1f).height(32.dp)) {
                                            Text(HTTGameRoomLocalizer.localize("打出 ${selTile.fullName}", lang), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                        }
                                    } else {
                                        Text(HTTGameRoomLocalizer.localize("👉 点选后点击【打出】出牌（再点取消）", lang), color = Color(0xFF00E676), fontSize = 11.sp, fontWeight = FontWeight.Black)
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

                        // Melds + Hand Tiles side-by-side on bottom row so tiles are 100% visible and NEVER overlap!
                        BoxWithConstraints(modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                            val totalW = maxWidth
                            var meldCountUnits = 0
                            me.melds.forEach { meldCountUnits += if (it.kind == MahjongMeldKind.PONG) 3 else 4 }
                            val meldsReservedW = if (me.melds.isEmpty()) 0.dp else (meldCountUnits * 23 + me.melds.size * 8 + 10).dp
                            val availHandW = (totalW - meldsReservedW).coerceAtLeast(180.dp)
                            val handCount = me.hand.size.coerceAtLeast(13)
                            val tileW = ((availHandW - 22.dp) / handCount.toFloat()).coerceIn(22.dp, 36.dp)
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
private fun MjDiscardRiver(seat: MahjongSeat, maxCols: Int = 6, isHorizontalSeat: Boolean = false) {
    val latestId = seat.discards.lastOrNull()?.id
    val maxTiles = maxCols * 3
    val recentDiscards = if (seat.discards.size > maxTiles) seat.discards.takeLast(maxTiles) else seat.discards
    val multiRow = recentDiscards.size > maxCols
    val tileW = if (isHorizontalSeat) (if (multiRow) 18.dp else 21.dp) else (if (multiRow) 19.dp else 22.dp)
    val tileH = if (isHorizontalSeat) (if (multiRow) 24.dp else 28.dp) else (if (multiRow) 26.dp else 30.dp)
    Column(
        verticalArrangement = Arrangement.spacedBy(1.5.dp),
        horizontalAlignment = if (isHorizontalSeat) Alignment.CenterHorizontally else Alignment.Start
    ) {
        recentDiscards.chunked(maxCols).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(1.5.dp)) {
                row.forEach { t ->
                    val isLatest = (t.id == latestId)
                    val popScale by animateFloatAsState(
                        targetValue = if (isLatest) 1.06f else 1.0f,
                        animationSpec = spring(dampingRatio = 0.55f, stiffness = 420f),
                        label = "mj_discard_pop"
                    )
                    Box(modifier = Modifier.graphicsLayer(scaleX = popScale, scaleY = popScale)) {
                        MjTileCard(t, tileW, tileH, isSelected = false, isHighlight = isLatest)
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
                contentScale = ContentScale.Fit,
                filterQuality = FilterQuality.High,
                modifier = Modifier.fillMaxSize().padding(1.5.dp)
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
    val drawnTargetSlotIdx by rmk.drawnTargetSlotIndex.collectAsState()
    val highlightedIds by rmk.lastTurnHighlightedTileIds.collectAsState()
    val selectedTableTile by rmk.selectedTableTileSource.collectAsState()
    val oppDrawSeatIdx by rmk.opponentDrawingSeatIndex.collectAsState()
    val oppPlaySeatIdx by rmk.opponentPlayingSeatIndex.collectAsState()
    val oppPlayTile by rmk.opponentPlayingTile.collectAsState()
    val oppPlayTargetMeldId by rmk.opponentPlayingTargetMeldId.collectAsState()

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
                Text("🔢 ${HTTGameRoomLocalizer.localize(banner, lang)}", color = MjGold, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 2)
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
        var dragTableTileObj by remember { mutableStateOf<RmkTile?>(null) }
        var dragTableStartCenter by remember { mutableStateOf(Offset.Zero) }
        var dragTableOffX by remember { mutableStateOf(0f) }
        var dragTableOffY by remember { mutableStateOf(0f) }
        var dragRackStartCenter by remember { mutableStateOf(Offset.Zero) }
        val meldBoundsMap = remember { HashMap<String, Rect>() }
        val seatBoundsMap = remember { HashMap<Int, Rect>() }
        var drawBtnBounds by remember { mutableStateOf<Rect?>(null) }
        var tableAreaBounds by remember { mutableStateOf<Rect?>(null) }
        var rackAreaBounds by remember { mutableStateOf<Rect?>(null) }
        val drawAnimProg by animateFloatAsState(targetValue = if (isDrawing) 1f else 0f, animationSpec = spring())
        val oppDrawAnimProg by animateFloatAsState(targetValue = if (oppDrawSeatIdx != null) 1f else 0f, animationSpec = spring())
        val oppPlayAnimProg by animateFloatAsState(targetValue = if (oppPlayTile != null) 1f else 0f, animationSpec = spring())

        fun findMagneticMeldHit(
            pt: Offset,
            excludeMeldId: String? = null,
            draggingTiles: List<RmkTile> = emptyList()
        ): Triple<String?, Boolean, Int?> {
            var bestId: String? = null
            var bestPreferLeading = false
            var bestScore = Float.MAX_VALUE
            for (meld in dispMelds) {
                if (meld.id == excludeMeldId) continue
                val rect = meldBoundsMap[meld.id] ?: continue
                // Tight hit-box so open-space drops near a meld are never hijacked
                val expanded = Rect(
                    left = rect.left - 5f,
                    top = rect.top - 4f,
                    right = rect.right + 5f,
                    bottom = rect.bottom + 4f
                )
                if (!expanded.contains(pt)) continue
                val dx = pt.x - rect.center.x
                val dy = pt.y - rect.center.y
                var score = kotlin.math.hypot(dx, dy * 1.35f)
                if (rect.contains(pt)) score *= 0.45f
                if (draggingTiles.isNotEmpty()) {
                    val cand = meld.tiles + draggingTiles
                    val splitTest = RmkEvaluator.autoSplitMeldTiles(cand)
                    if (RmkEvaluator.evaluateMeld(cand) != null ||
                        (splitTest.size >= 2 && splitTest.all { RmkEvaluator.evaluateMeld(it) != null })
                    ) {
                        score *= 0.35f
                    } else {
                        val norms = cand.filter { !it.isJoker }
                        val sameNum = norms.all { it.number == (norms.firstOrNull()?.number ?: 0) } &&
                            norms.map { it.color }.distinct().size == norms.size
                        val sameCol = norms.all { it.color == norms.firstOrNull()?.color }
                        if (!sameNum && !sameCol) score *= 2.4f
                    }
                }
                if (score < bestScore) {
                    bestScore = score
                    bestId = meld.id
                    bestPreferLeading = pt.x < rect.center.x
                }
            }
            if (bestId != null) return Triple(bestId, bestPreferLeading, null)

            // Open-space drop: find the exact row & horizontal slot closest to pt so the tile stays where dropped
            data class IndexedRect(val idx: Int, val rect: Rect)
            val indexedRects = dispMelds.mapIndexedNotNull { idx, meld ->
                meldBoundsMap[meld.id]?.let { IndexedRect(idx, it) }
            }
            if (indexedRects.isEmpty()) return Triple(null, false, 0)

            val rowGroups = mutableListOf<MutableList<IndexedRect>>()
            for (item in indexedRects) {
                val lastGroup = rowGroups.lastOrNull()
                if (lastGroup != null && kotlin.math.abs(item.rect.center.y - lastGroup[0].rect.center.y) < 28f) {
                    lastGroup.add(item)
                } else {
                    rowGroups.add(mutableListOf(item))
                }
            }
            val firstRowTop = rowGroups.first().first().rect.top
            val lastRowBottom = rowGroups.last().first().rect.bottom
            if (pt.y < firstRowTop - 16f) return Triple(null, false, 0)
            if (pt.y > lastRowBottom + 24f) return Triple(null, false, dispMelds.size)

            val bestRow = rowGroups.minByOrNull { row ->
                val avgY = row.map { it.rect.center.y }.average().toFloat()
                kotlin.math.abs(pt.y - avgY)
            } ?: rowGroups.last()

            val sortedRow = bestRow.sortedBy { it.rect.center.x }
            for (item in sortedRow) {
                if (pt.x < item.rect.center.x) {
                    return Triple(null, false, item.idx)
                }
            }
            val afterIdx = (sortedRow.last().idx + 1).coerceAtMost(dispMelds.size)
            return Triple(null, false, afterIdx)
        }

        // Order seats so opponents are at top-left and local player (me) is anchored at bottom-left next to the rack (1:1 like video!)
        val orderedSeats = remember(seats, mySeat) {
            val opps = seats.filter { it.id != mySeat }
            val me = seats.firstOrNull { it.id == mySeat }
            if (me != null) opps + me else opps
        }

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF0E3266))
        ) {
            val screenH = maxHeight
            val adaptiveRackH = (screenH * 0.30f).coerceIn(82.dp, 108.dp)
            val adaptiveSlotH = ((adaptiveRackH - 16.dp) / 2f).coerceIn(33.dp, 46.dp)
            val adaptiveTileH = (adaptiveSlotH - 2.dp).coerceAtLeast(31.dp)
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
                            Box(
                                modifier = Modifier
                                    .size(52.dp)
                                    .onGloballyPositioned { if (it.isAttached) seatBoundsMap[s.id] = it.boundsInRoot() },
                                contentAlignment = Alignment.Center
                            ) {
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
                        Text(HTTGameRoomLocalizer.localize(banner, lang), color = MjGold, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.weight(1f))
                        if (myTurn) {
                            Spacer(Modifier.width(6.dp))
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(Color(0xFF7B1FA2))
                                    .clickable { rmk.smartHint() }
                                    .padding(horizontal = 8.dp, vertical = 3.dp)
                            ) {
                                Text(HTTGameRoomLocalizer.localize("💡提示", lang), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black)
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
                                    Text(HTTGameRoomLocalizer.localize("⬆️出到桌面", lang), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }

                    // Full-Height Auto-Scaling Non-Scrolling Table Melds Area (auto-shrinks tiles as more melds are played, NEVER overlaps!)
                    BoxWithConstraints(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .onGloballyPositioned { if (it.isAttached) tableAreaBounds = it.boundsInRoot() }
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
                        val availWVal = maxWidth.value.coerceAtLeast(300f)
                        val availHVal = maxHeight.value.coerceAtLeast(110f)
                        if (dispMelds.isEmpty()) {
                            Column(
                                modifier = Modifier.align(Alignment.Center),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    when (lang) {
                                        AppLanguage.ZH_HANS -> "桌面暂无牌组 · 首次破冰需从牌架拖出 ≥30 分牌组"
                                        AppLanguage.ZH_HANT -> "桌面暫無牌組 · 首次破冰需從牌架拖出 ≥30 分牌組"
                                        AppLanguage.EN -> "No table melds yet · Drag ≥30 pts from rack for initial icebreak"
                                    },
                                    color = Color.White.copy(alpha = 0.75f),
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    when (lang) {
                                        AppLanguage.ZH_HANS -> "💡 点选牌架上的牌可多选组合，长按可自动连选顺子/群组，向上拖到桌面即可出牌；破冰后可任意拖动桌面牌重组"
                                        AppLanguage.ZH_HANT -> "💡 點選牌架上的牌可多選組合，長按可自動連選順子/群組，向上拖到桌面即可出牌；破冰後可任意拖動桌面牌重組"
                                        AppLanguage.EN -> "💡 Tap rack tiles to multi-select, long-press to auto-select run/group, drag up to table to play"
                                    },
                                    color = MjGold.copy(alpha = 0.90f),
                                    fontSize = 10.sp,
                                    textAlign = TextAlign.Center
                                )
                            }
                        } else {
                            var chosenW = 38f
                            var chosenRows: List<List<RmkMeld>> = listOf(dispMelds)
                            for (step in 0..9) {
                                val cw = 38f - step * 2f
                                val ch = cw * 1.38f
                                val rows = mutableListOf<MutableList<RmkMeld>>()
                                var curRow = mutableListOf<RmkMeld>()
                                var curX = 0f
                                for (m in dispMelds) {
                                    val mw = m.tiles.size.coerceAtLeast(1) * (cw + 2f) + 8f
                                    if (curRow.isNotEmpty() && curX + mw > availWVal) {
                                        rows.add(curRow)
                                        curRow = mutableListOf(m)
                                        curX = mw + 8f
                                    } else {
                                        curRow.add(m)
                                        curX += mw + 8f
                                    }
                                }
                                if (curRow.isNotEmpty()) rows.add(curRow)
                                val totalH = rows.size * (ch + 8f) + (rows.size - 1).coerceAtLeast(0) * 6f
                                chosenW = cw
                                chosenRows = rows
                                if (totalH <= availHVal) break
                            }
                            val tileWDp = chosenW.dp
                            val tileHDp = (chosenW * 1.38f).dp

                            Column(
                                modifier = Modifier.fillMaxSize(),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                chosenRows.forEach { rowMelds ->
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        rowMelds.forEach { meld ->
                                            key(meld.id) {
                                            val ok = RmkEvaluator.evaluateMeld(meld.tiles) != null
                                            Row(
                                                modifier = Modifier
                                                    .onGloballyPositioned { if (it.isAttached) meldBoundsMap[meld.id] = it.boundsInRoot() }
                                                    .clip(RoundedCornerShape(7.dp))
                                                    .background(if (ok) Color.Transparent else Color.Red.copy(alpha = 0.16f))
                                                    .border(
                                                        width = if (ok) 0.dp else 2.2.dp,
                                                        color = if (ok) Color.Transparent else Color(0xFFFF5252),
                                                        shape = RoundedCornerShape(7.dp)
                                                    )
                                                    .padding(horizontal = 3.dp, vertical = 2.dp),
                                                horizontalArrangement = Arrangement.spacedBy(1.5.dp)
                                            ) {
                                                meld.tiles.forEach { t ->
                                                    key(t.id) {
                                                    val isPickedTable = (selectedTableTile?.first == meld.id && selectedTableTile?.second == t.id)
                                                    val isDragTbl = (dragTableTileKey?.first == meld.id && dragTableTileKey?.second == t.id)
                                                    val isHigh = highlightedIds.contains(t.id)
                                                    var tileRootPos by remember { mutableStateOf(Offset.Zero) }
                                                    Box(
                                                        modifier = Modifier
                                                            .onGloballyPositioned { if (it.isAttached) tileRootPos = it.boundsInRoot().center }
                                                            .pointerInput(meld.id, t.id, myTurn) {
                                                                if (!myTurn) return@pointerInput
                                                                detectDragGestures(
                                                                    onDragStart = {
                                                                        dragTableTileKey = meld.id to t.id
                                                                        dragTableTileObj = t
                                                                        dragTableStartCenter = tileRootPos
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
                                                                        val rb = rackAreaBounds
                                                                        if (rb != null && (rb.inflate(24f).contains(dropPt) || dropPt.y >= rb.top - 18f)) {
                                                                            val relX = (dropPt.x - rb.left).coerceIn(0f, rb.width.coerceAtLeast(1f))
                                                                            val dstCol = ((relX / rb.width.coerceAtLeast(1f)) * cols).toInt().coerceIn(0, cols - 1)
                                                                            val dstRow = if (dropPt.y >= rb.center.y) 1 else 0
                                                                            rmk.returnTableTileToRackIfFromThisTurn(meld.id, t.id, preferredRackSlot = dstRow * cols + dstCol)
                                                                        } else {
                                                                            val (targetMeld, preferLead, insIdx) = findMagneticMeldHit(dropPt, excludeMeldId = meld.id, draggingTiles = listOf(t))
                                                                            if (targetMeld != null) {
                                                                                rmk.moveTableTile(meld.id, t.id, targetMeld, preferLeading = preferLead)
                                                                            } else if (tableAreaBounds?.inflate(36f)?.contains(dropPt) == true) {
                                                                                rmk.moveTableTile(meld.id, t.id, null, preferLeading = false, insertAtMeldIndex = insIdx)
                                                                            }
                                                                        }
                                                                        dragTableTileKey = null
                                                                        dragTableTileObj = null
                                                                        dragTableOffX = 0f
                                                                        dragTableOffY = 0f
                                                                    },
                                                                    onDragCancel = {
                                                                        dragTableTileKey = null
                                                                        dragTableTileObj = null
                                                                        dragTableOffX = 0f
                                                                        dragTableOffY = 0f
                                                                    }
                                                                )
                                                            }
                                                    ) {
                                                        Box(modifier = Modifier.then(if (isDragTbl) Modifier.background(Color.Transparent) else Modifier)) {
                                                            if (!isDragTbl) {
                                                                RmkTileCard(
                                                                    tile = t,
                                                                    selected = false,
                                                                    highlighted = isHigh,
                                                                    compact = chosenW < 34f,
                                                                    customW = tileWDp,
                                                                    customH = tileHDp,
                                                                    onClick = if (myTurn) {
                                                                        { rmk.handleTableTileTapOrMove(meld.id, t.id) }
                                                                    } else null
                                                                )
                                                            } else {
                                                                Box(
                                                                    modifier = Modifier
                                                                        .size(width = tileWDp, height = tileHDp)
                                                                        .clip(RoundedCornerShape(6.dp))
                                                                        .border(1.5.dp, Color.Cyan.copy(alpha = 0.45f), RoundedCornerShape(6.dp))
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
                            }
                        }
                    }

                    // Bottom Adaptive 2-Row × 10-Column Wooden Rack (1:1 like iOS, never clipped on any Android ratio!)
                    BoxWithConstraints(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(adaptiveRackH)
                            .onGloballyPositioned { if (it.isAttached) rackAreaBounds = it.boundsInRoot() }
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
                                                    .size(width = slotW, height = adaptiveSlotH)
                                                    .clip(RoundedCornerShape(5.dp))
                                                    .background(if (liftedIdx != null && tileOpt == null) Color.Yellow.copy(alpha = 0.16f) else Color.Black.copy(alpha = 0.10f))
                                                    .border(1.dp, if (liftedIdx != null) Color.Yellow.copy(alpha = 0.55f) else Color.Black.copy(alpha = 0.20f), RoundedCornerShape(5.dp))
                                                    .pointerInput(slotIdx, cols, tileOpt?.id) {
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
                                                                    if (dragOffsetY < -35f && tileOpt != null) {
                                                                        val estDrop = tableAreaBounds?.let { tb ->
                                                                            Offset(tb.left + tb.width * ((col + 0.5f) / cols) + dragOffsetX, tb.bottom + dragOffsetY)
                                                                        }
                                                                        if (estDrop != null) {
                                                                            val movingList = if (selIds.contains(tileOpt.id) && selIds.size > 1) {
                                                                                rackSlots.filterNotNull().filter { selIds.contains(it.id) }
                                                                            } else listOf(tileOpt)
                                                                            val (targetMeld, preferLead, insIdx) = findMagneticMeldHit(estDrop, excludeMeldId = null, draggingTiles = movingList)
                                                                            rmk.dropRackTilesToTable(tileOpt.id, targetMeld, preferLeading = preferLead, insertAtMeldIndex = insIdx)
                                                                        } else {
                                                                            rmk.dropRackTilesToTable(tileOpt.id, null)
                                                                        }
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
                                                            if (tileOpt != null) {
                                                                rmk.toggleSelectTile(tileOpt.id)
                                                                if (!selIds.contains(tileOpt.id)) {
                                                                    rmk.setLiftedSlot(slotIdx)
                                                                } else if (liftedIdx == slotIdx) {
                                                                    rmk.setLiftedSlot(null)
                                                                }
                                                            } else if (liftedIdx != null) {
                                                                liftedIdx?.let { rmk.moveRackSlot(it, slotIdx) }
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
                                                            customH = adaptiveTileH
                                                        )
                                                        if (dragSlotIdx == slotIdx && selIds.size > 1 && selIds.contains(tileOpt.id)) {
                                                            Box(
                                                                modifier = Modifier
                                                                    .align(Alignment.TopEnd)
                                                                    .offset(x = 4.dp, y = (-8).dp)
                                                                    .clip(RoundedCornerShape(50))
                                                                    .background(Color(0xFFFF9800))
                                                                    .padding(horizontal = 4.dp, vertical = 1.dp)
                                                            ) {
                                                                Text("+${selIds.size - 1}", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
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

                    // Bottom-Right Dynamic Action Area: ONLY shows `↺` + `✓` when tiles have actually been moved to/on the table!
                    val hasTableChanges = isEditing && (workingMelds != tableMelds || workingHand.size != (seats.getOrNull(mySeat)?.hand?.size ?: 0))
                    if (hasTableChanges && myTurn) {
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
                                .onGloballyPositioned { if (it.isAttached) drawBtnBounds = it.boundsInRoot() }
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

            // Top-level Floating Table Drag Tile Overlay (never clipped inside meld row box!)
            if (dragTableTileKey != null && dragTableTileObj != null) {
                val curX = dragTableStartCenter.x + dragTableOffX
                val curY = dragTableStartCenter.y + dragTableOffY
                Box(
                    modifier = Modifier
                        .offset {
                            IntOffset(
                                (curX - 65f).roundToInt(),
                                (curY - 88f).roundToInt()
                            )
                        }
                ) {
                    RmkTileCard(
                        tile = dragTableTileObj ?: return@Box,
                        selected = true,
                        highlighted = true,
                        compact = false,
                        customW = 42.dp,
                        customH = 58.dp
                    )
                }
            }

            // 1. Player Draw Tile Flight Animation Overlay (From `+` button into target empty rack slot)
            if (isDrawing && drawAnimTile != null) {
                val targetCol = drawnTargetSlotIdx % cols
                val targetRow = drawnTargetSlotIdx / cols
                val targetX = -48f - ((cols - 1 - targetCol) * 32f)
                val targetY = if (targetRow == 0) -64f else -18f
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .offset(
                            x = (-24f + (targetX + 24f) * drawAnimProg).dp,
                            y = (-54f + (targetY + 54f) * drawAnimProg - kotlin.math.sin(drawAnimProg * Math.PI.toFloat()) * 42f).dp
                        )
                ) {
                    drawAnimTile?.let { RmkTileCard(tile = it, selected = true, compact = false) }
                }
            }

            // 2. Opponent Draw Tile Back Flight Animation Overlay (From `+` button across table to opponent avatar on left)
            if (oppDrawSeatIdx != null) {
                val oppPosIdx = orderedSeats.indexOfFirst { it.id == oppDrawSeatIdx }.coerceAtLeast(0)
                val endY = (-220f + oppPosIdx * 72f)
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .offset(
                            x = (-28f - oppDrawAnimProg * 560f).dp,
                            y = (-56f + (endY + 56f) * oppDrawAnimProg - kotlin.math.sin(oppDrawAnimProg * Math.PI.toFloat()) * 36f).dp
                        )
                        .size(width = 34.dp, height = 48.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFFCF8F2))
                        .border(1.5.dp, MjGold, RoundedCornerShape(6.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Text("R", color = Color(0xFF1E5096), fontSize = 13.sp, fontWeight = FontWeight.Black)
                }
            }

            // 3. Opponent Step-by-Step Play Tile Flight Animation Overlay (From opponent avatar on left to target meld on table)
            if (oppPlaySeatIdx != null && oppPlayTile != null) {
                val oppPosIdx = orderedSeats.indexOfFirst { it.id == oppPlaySeatIdx }.coerceAtLeast(0)
                val startY = 36f + oppPosIdx * 72f
                Box(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .offset(
                            x = (38f + oppPlayAnimProg * 240f).dp,
                            y = (startY + (110f - startY) * oppPlayAnimProg - kotlin.math.sin(oppPlayAnimProg * Math.PI.toFloat()) * 28f).dp
                        )
                ) {
                    RmkTileCard(
                        tile = oppPlayTile ?: return@Box,
                        selected = true,
                        highlighted = true,
                        compact = true,
                        customW = 38.dp,
                        customH = 52.dp
                    )
                }
            }
        }
    }
}
