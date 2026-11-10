package com.tomy.httnavicompanion.audio

import android.content.Context
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.data.AssetDecryptor
import com.tomy.httnavicompanion.data.LatLng
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.io.FileOutputStream
import kotlin.random.Random

enum class AppLanguage(val label: String) {
    ZH_HANS("简体中文"),
    ZH_HANT("繁體中文"),
    EN("English")
}

enum class CharacterFilter(
    val id: String,
    val charId: Int,
    val mainSheetName: String,
    val cakeSheetName: String,
    val navBaseId: Int,
    val menuStartId: Int,
    val bonusId: Int
) {
    ALL("all", 0, "yui01", "yui00", 157, 877, 1112),
    YUI("yui", 1, "yui01", "yui00", 157, 877, 1112),
    MIO("mio", 2, "mio01", "mio00", 301, 924, 1113),
    RITSU("ritsu", 3, "ritsu01", "ritsu00", 445, 971, 1114),
    MUGI("mugi", 4, "tsumugi01", "tsumugi00", 589, 1018, 1115),
    AZUSA("azusa", 5, "azusa01", "azusa00", 733, 1065, 1116);

    fun displayName(lang: AppLanguage): String = when (this) {
        ALL -> when (lang) {
            AppLanguage.ZH_HANS, AppLanguage.ZH_HANT -> "五人同台"
            AppLanguage.EN -> "All 5 HTT"
        }
        YUI -> if (lang == AppLanguage.EN) "Yui" else "平泽唯"
        MIO -> if (lang == AppLanguage.EN) "Mio" else "秋山澪"
        RITSU -> if (lang == AppLanguage.EN) "Ritsu" else "田井中律"
        MUGI -> if (lang == AppLanguage.EN) "Mugi" else "琴吹紬"
        AZUSA -> if (lang == AppLanguage.EN) "Azusa" else "中野梓"
    }

    fun roleTag(lang: AppLanguage): String = when (this) {
        YUI -> when (lang) {
            AppLanguage.ZH_HANS -> "平泽唯 · 主音吉他 (CV: 丰崎爱生)"
            AppLanguage.ZH_HANT -> "平澤唯 · 主音吉他 (CV: 豐崎愛生)"
            AppLanguage.EN -> "Yui Hirasawa · Lead Guitar"
        }
        MIO -> when (lang) {
            AppLanguage.ZH_HANS -> "秋山澪 · 贝斯手 (CV: 日笠阳子)"
            AppLanguage.ZH_HANT -> "秋山澪 · 貝斯手 (CV: 日笠陽子)"
            AppLanguage.EN -> "Mio Akiyama · Bass"
        }
        RITSU -> when (lang) {
            AppLanguage.ZH_HANS -> "田井中律 · 架子鼓部长 (CV: 佐藤聪美)"
            AppLanguage.ZH_HANT -> "田井中律 · 爵士鼓部長 (CV: 佐藤聰美)"
            AppLanguage.EN -> "Ritsu Tainaka · Drums"
        }
        MUGI -> when (lang) {
            AppLanguage.ZH_HANS -> "琴吹紬 · 键盘手 (CV: 寿美菜子)"
            AppLanguage.ZH_HANT -> "琴吹紬 · 鍵盤手 (CV: 壽美菜子)"
            AppLanguage.EN -> "Tsumugi Kotobuki · Keyboard"
        }
        AZUSA -> when (lang) {
            AppLanguage.ZH_HANS -> "中野梓 · 节奏吉他 (CV: 竹达彩奈)"
            AppLanguage.ZH_HANT -> "中野梓 · 節奏吉他 (CV: 竹達彩奈)"
            AppLanguage.EN -> "Azusa Nakano · Rhythm Guitar"
        }
        ALL -> when (lang) {
            AppLanguage.ZH_HANS -> "放课后茶会 (HTT 全员同台模式)"
            AppLanguage.ZH_HANT -> "放課後茶會 (HTT 全員同台模式)"
            AppLanguage.EN -> "Ho-kago Tea Time (All 5 Members)"
        }
    }

    val verifiedVoiceIds: List<Int>
        get() = if (this == ALL) {
            (157..1122).toList()
        } else {
            (navBaseId..(navBaseId + 143)).toList() + (menuStartId..(menuStartId + 46)).toList() + listOf(bonusId)
        }

    companion object {
        val fiveIndividuals = listOf(YUI, MIO, RITSU, MUGI, AZUSA)
    }
}

enum class MascotActionState {
    IDLE, WALK_LEFT, WALK_RIGHT, SPECIAL, GRABBED, PANIC, TEA_CAKE;

    fun localizedTitle(lang: AppLanguage): String = when (this) {
        IDLE -> when (lang) {
            AppLanguage.ZH_HANS -> "待机互动"
            AppLanguage.ZH_HANT -> "待機互動"
            AppLanguage.EN -> "Idle"
        }
        WALK_LEFT, WALK_RIGHT -> when (lang) {
            AppLanguage.ZH_HANS, AppLanguage.ZH_HANT -> "散步中"
            AppLanguage.EN -> "Walking"
        }
        SPECIAL -> when (lang) {
            AppLanguage.ZH_HANS -> "招牌动作"
            AppLanguage.ZH_HANT -> "招牌動作"
            AppLanguage.EN -> "Dance"
        }
        GRABBED -> when (lang) {
            AppLanguage.ZH_HANS -> "提起挣扎"
            AppLanguage.ZH_HANT -> "提起掙扎"
            AppLanguage.EN -> "Lifted!"
        }
        PANIC -> when (lang) {
            AppLanguage.ZH_HANS -> "超速惊慌"
            AppLanguage.ZH_HANT -> "超速驚慌"
            AppLanguage.EN -> "Overspeed!"
        }
        TEA_CAKE -> when (lang) {
            AppLanguage.ZH_HANS -> "顶蛋糕下午茶"
            AppLanguage.ZH_HANT -> "頂蛋糕下午茶"
            AppLanguage.EN -> "Tea & Cake"
        }
    }
}

enum class RM500ArrowOutfit(val rawValue: Int) {
    WINTER_UNIFORM(0),
    SUMMER_UNIFORM(1),
    MAID(2),
    HTT_SHIRT(3),
    KIGURUMI(4),
    TONCHAN(5),
    CLASSIC_3D(6);

    fun title(lang: AppLanguage): String = when (this) {
        WINTER_UNIFORM -> if (lang == AppLanguage.EN) "Winter Uniform" else "冬季制服"
        SUMMER_UNIFORM -> if (lang == AppLanguage.EN) "Summer Uniform" else "夏季制服"
        MAID -> when (lang) {
            AppLanguage.ZH_HANS -> "女仆装"
            AppLanguage.ZH_HANT -> "女僕裝"
            AppLanguage.EN -> "Maid Outfit"
        }
        HTT_SHIRT -> if (lang == AppLanguage.EN) "HTT T-Shirt" else "HTT文化衫"
        KIGURUMI -> when (lang) {
            AppLanguage.ZH_HANS -> "布偶装"
            AppLanguage.ZH_HANT -> "布偶裝"
            AppLanguage.EN -> "Animal Suit"
        }
        TONCHAN -> when (lang) {
            AppLanguage.ZH_HANS -> "豚骨(乌龟)"
            AppLanguage.ZH_HANT -> "豚骨(烏龜)"
            AppLanguage.EN -> "Ton-chan"
        }
        CLASSIC_3D -> when (lang) {
            AppLanguage.ZH_HANS -> "经典3D箭头"
            AppLanguage.ZH_HANT -> "經典3D箭頭"
            AppLanguage.EN -> "3D Arrow"
        }
    }
}

enum class NavigationTravelMode {
    DRIVING, EBIKE, WALKING, TRANSIT;

    fun title(lang: AppLanguage): String = when (this) {
        DRIVING -> when (lang) {
            AppLanguage.ZH_HANS -> "开车"
            AppLanguage.ZH_HANT -> "開車"
            AppLanguage.EN -> "Drive"
        }
        EBIKE -> when (lang) {
            AppLanguage.ZH_HANS -> "电动车"
            AppLanguage.ZH_HANT -> "電動車"
            AppLanguage.EN -> "e-Bike"
        }
        WALKING -> if (lang == AppLanguage.EN) "Walk" else "步行"
        TRANSIT -> when (lang) {
            AppLanguage.ZH_HANS -> "公交/地铁"
            AppLanguage.ZH_HANT -> "公車/地鐵"
            AppLanguage.EN -> "Transit"
        }
    }

    val defaultSpeedLimit: Int
        get() = when (this) {
            DRIVING -> 80
            EBIKE -> 25
            WALKING -> 10
            TRANSIT -> 80
        }
}

enum class NavigationCameraMode {
    HEADING_UP, NORTH_UP;

    fun title(lang: AppLanguage): String = when (this) {
        HEADING_UP -> when (lang) {
            AppLanguage.ZH_HANS -> "车头朝上(地图动)"
            AppLanguage.ZH_HANT -> "車頭朝上(地圖動)"
            AppLanguage.EN -> "Heading Up"
        }
        NORTH_UP -> when (lang) {
            AppLanguage.ZH_HANS -> "正北朝上(车标动)"
            AppLanguage.ZH_HANT -> "正北朝上(車標動)"
            AppLanguage.EN -> "North Up"
        }
    }

    fun shortTitle(lang: AppLanguage): String = when (this) {
        HEADING_UP -> when (lang) {
            AppLanguage.ZH_HANS -> "地图动"
            AppLanguage.ZH_HANT -> "地圖動"
            AppLanguage.EN -> "Map Rot"
        }
        NORTH_UP -> when (lang) {
            AppLanguage.ZH_HANS -> "车标动"
            AppLanguage.ZH_HANT -> "車標動"
            AppLanguage.EN -> "Icon Mov"
        }
    }
}

data class PlaceSearchItem(
    val name: String,
    val address: String,
    val distanceKm: Double,
    val coordinate: LatLng,
    val category: String
)

class AudioPlayerManager(
    private val context: Context,
    val assetDecryptor: AssetDecryptor
) {
    private val TAG = "AudioPlayerManager"
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var mediaPlayer: MediaPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // App & Language State
    private val _language = MutableStateFlow(AppLanguage.ZH_HANS)
    val language: StateFlow<AppLanguage> = _language

    private val _showMapMode = MutableStateFlow(false)
    val showMapMode: StateFlow<Boolean> = _showMapMode

    private val _isMapEnlarged = MutableStateFlow(false)
    val isMapEnlarged: StateFlow<Boolean> = _isMapEnlarged

    private val _isHUDMirrored = MutableStateFlow(false)
    val isHUDMirrored: StateFlow<Boolean> = _isHUDMirrored

    // Character & Mascot State
    private val _selectedCharacter = MutableStateFlow(CharacterFilter.ALL)
    val selectedCharacter: StateFlow<CharacterFilter> = _selectedCharacter

    private val _activeAllMemberChar = MutableStateFlow(CharacterFilter.YUI)
    val activeAllMemberChar: StateFlow<CharacterFilter> = _activeAllMemberChar

    private val _mascotAction = MutableStateFlow(MascotActionState.IDLE)
    val mascotAction: StateFlow<MascotActionState> = _mascotAction

    private val _mascotOffsetX = MutableStateFlow(0f)
    val mascotOffsetX: StateFlow<Float> = _mascotOffsetX

    private val _currentSpeechBubble = MutableStateFlow("[五人同台] 放课后茶会 (HTT) 专属导航与桌面伴侣已就绪♪")
    val currentSpeechBubble: StateFlow<String> = _currentSpeechBubble

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying

    private val _currentPlayingId = MutableStateFlow<Int?>(null)
    val currentPlayingId: StateFlow<Int?> = _currentPlayingId

    // Sprites State
    private val _allMemberFrames = MutableStateFlow<Map<Int, Bitmap>>(emptyMap())
    val allMemberFrames: StateFlow<Map<Int, Bitmap>> = _allMemberFrames

    private val _currentSpriteFrame = MutableStateFlow<Bitmap?>(null)
    val currentSpriteFrame: StateFlow<Bitmap?> = _currentSpriteFrame

    private val _currentNavArrowBitmap = MutableStateFlow<Bitmap?>(null)
    val currentNavArrowBitmap: StateFlow<Bitmap?> = _currentNavArrowBitmap

    private val _themeBackgroundBitmap = MutableStateFlow<Bitmap?>(null)
    val themeBackgroundBitmap: StateFlow<Bitmap?> = _themeBackgroundBitmap

    // Outfit & Camera
    private val _arrowOutfit = MutableStateFlow(RM500ArrowOutfit.WINTER_UNIFORM)
    val arrowOutfit: StateFlow<RM500ArrowOutfit> = _arrowOutfit

    private val _travelMode = MutableStateFlow(NavigationTravelMode.DRIVING)
    val travelMode: StateFlow<NavigationTravelMode> = _travelMode

    private val _cameraMode = MutableStateFlow(NavigationCameraMode.HEADING_UP)
    val cameraMode: StateFlow<NavigationCameraMode> = _cameraMode

    // Speed, Telemetry & Navigation
    private val _currentSpeedKmh = MutableStateFlow(0)
    val currentSpeedKmh: StateFlow<Int> = _currentSpeedKmh

    private val _maxSpeedKmh = MutableStateFlow(0)
    val maxSpeedKmh: StateFlow<Int> = _maxSpeedKmh

    private val _speedLimitKmh = MutableStateFlow(80)
    val speedLimitKmh: StateFlow<Int> = _speedLimitKmh

    private val _isGPSSignalPoor = MutableStateFlow(false)
    val isGPSSignalPoor: StateFlow<Boolean> = _isGPSSignalPoor

    private val _tripDistanceKm = MutableStateFlow(0.0)
    val tripDistanceKm: StateFlow<Double> = _tripDistanceKm

    private val _drivingSeconds = MutableStateFlow(0)
    val drivingSeconds: StateFlow<Int> = _drivingSeconds

    private val _headingDegrees = MutableStateFlow(0.0)
    val headingDegrees: StateFlow<Double> = _headingDegrees

    // Cruise Mode
    private val _isCruiseModeActive = MutableStateFlow(false)
    val isCruiseModeActive: StateFlow<Boolean> = _isCruiseModeActive

    private val _cruiseIntervalMinutes = MutableStateFlow(10)
    val cruiseIntervalMinutes: StateFlow<Int> = _cruiseIntervalMinutes

    private val _cruiseRemainingSeconds = MutableStateFlow(600)
    val cruiseRemainingSeconds: StateFlow<Int> = _cruiseRemainingSeconds

    // Navigation & Demo State
    private val _isDemoSimulating = MutableStateFlow(false)
    val isDemoSimulating: StateFlow<Boolean> = _isDemoSimulating

    private val _hasActiveNavigation = MutableStateFlow(false)
    val hasActiveNavigation: StateFlow<Boolean> = _hasActiveNavigation

    private val _destinationName = MutableStateFlow("")
    val destinationName: StateFlow<String> = _destinationName

    private val _currentStepInstruction = MutableStateFlow("准备出发 · 请选择目的地或开启巡航")
    val currentStepInstruction: StateFlow<String> = _currentStepInstruction

    private val _distanceToNextStepMeters = MutableStateFlow(0)
    val distanceToNextStepMeters: StateFlow<Int> = _distanceToNextStepMeters

    private val _trafficLightCountdown = MutableStateFlow(18)
    val trafficLightCountdown: StateFlow<Int> = _trafficLightCountdown

    private val _trafficLightColor = MutableStateFlow(2) // 0=Red, 1=Yellow, 2=Green
    val trafficLightColor: StateFlow<Int> = _trafficLightColor

    private val _upcomingCameraDistance = MutableStateFlow(350)
    val upcomingCameraDistance: StateFlow<Int> = _upcomingCameraDistance

    private val _upcomingServiceAreaDist = MutableStateFlow(2400)
    val upcomingServiceAreaDist: StateFlow<Int> = _upcomingServiceAreaDist

    private val _upcomingServiceAreaName = MutableStateFlow("樱丘高速服务区(SA)")
    val upcomingServiceAreaName: StateFlow<String> = _upcomingServiceAreaName

    private var animTick = 0
    private var walkStepFrame = 0
    private var nextAllMemberSwitchTick = 45
    private val voiceQueue = ArrayList<Pair<Int, String>>()
    private var demoStepCounter = 0

    val appVersion = "1.0.8"

    fun appAuthorLabel(): String = when (_language.value) {
        AppLanguage.ZH_HANS -> "制作作者: 君殇"
        AppLanguage.ZH_HANT -> "製作作者: Tomy"
        AppLanguage.EN -> "Author: Tomy"
    }

    fun compassDirectionString(): String {
        val h = ((_headingDegrees.value % 360.0) + 360.0) % 360.0
        return when {
            h < 22.5 || h >= 337.5 -> "北 N"
            h < 67.5 -> "东北 NE"
            h < 112.5 -> "东 E"
            h < 157.5 -> "东南 SE"
            h < 202.5 -> "南 S"
            h < 247.5 -> "西南 SW"
            h < 292.5 -> "西 W"
            else -> "西北 NW"
        }
    }

    fun formattedDrivingTime(): String {
        val hrs = _drivingSeconds.value / 3600
        val mins = (_drivingSeconds.value % 3600) / 60
        val secs = _drivingSeconds.value % 60
        return if (hrs > 0) String.format("%d:%02d:%02d", hrs, mins, secs)
        else String.format("%02d:%02d", mins, secs)
    }

    fun formattedCruiseCountdown(): String {
        val m = _cruiseRemainingSeconds.value / 60
        val s = _cruiseRemainingSeconds.value % 60
        return String.format("%02d:%02d", m, s)
    }

    fun initVoicePackage() {
        refreshThemeBackground()
        updateAllSpriteFrames()
        mainHandler.post {
            startSpriteAnimatorLoop()
            startMasterClockLoop()
        }
    }

    private fun startSpriteAnimatorLoop() {
        val runnable = object : Runnable {
            override fun run() {
                animTick += 1
                stepMascotBehavior()
                updateAllSpriteFrames()
                mainHandler.postDelayed(this, 160L)
            }
        }
        mainHandler.post(runnable)
    }

    private fun startMasterClockLoop() {
        val runnable = object : Runnable {
            override fun run() {
                _drivingSeconds.value += 1

                // Traffic light countdown simulation
                if (_trafficLightCountdown.value > 1) {
                    _trafficLightCountdown.value -= 1
                } else {
                    _trafficLightColor.value = (_trafficLightColor.value + 1) % 3
                    _trafficLightCountdown.value = when (_trafficLightColor.value) {
                        0 -> 22 // Red
                        1 -> 4  // Yellow
                        else -> 26 // Green
                    }
                }

                // Cruise countdown
                if (_isCruiseModeActive.value) {
                    if (_cruiseRemainingSeconds.value > 1) {
                        _cruiseRemainingSeconds.value -= 1
                    } else {
                        _cruiseRemainingSeconds.value = _cruiseIntervalMinutes.value * 60
                        playRandomCruiseVoice()
                    }
                }

                // Demo simulation step progression every 8 seconds
                if (_isDemoSimulating.value && _drivingSeconds.value % 8 == 0) {
                    advanceDemoSimulationStep()
                }

                mainHandler.postDelayed(this, 1000L)
            }
        }
        mainHandler.postDelayed(runnable, 1000L)
    }

    private fun stepMascotBehavior() {
        if (_currentSpeedKmh.value > _speedLimitKmh.value) {
            _mascotAction.value = MascotActionState.PANIC
            return
        }
        val act = _mascotAction.value
        if (act == MascotActionState.WALK_LEFT) {
            _mascotOffsetX.value -= 4.5f
            if (_mascotOffsetX.value < -65f) _mascotAction.value = MascotActionState.WALK_RIGHT
        } else if (act == MascotActionState.WALK_RIGHT) {
            _mascotOffsetX.value += 4.5f
            if (_mascotOffsetX.value > 65f) _mascotAction.value = MascotActionState.WALK_LEFT
        }
    }

    private fun updateAllSpriteFrames() {
        if (!assetDecryptor.isInitialized) return
        val newFrames = HashMap<Int, Bitmap>()
        val isPlay = _isPlaying.value
        val curAction = if (_hasActiveNavigation.value && _currentSpeedKmh.value > 3) {
            MascotActionState.WALK_RIGHT
        } else {
            _mascotAction.value
        }

        for (member in CharacterFilter.fiveIndividuals) {
            val phaseTick = animTick + (member.charId * 3)
            val bmp = assetDecryptor.sliceMascotFrame(member, curAction, phaseTick, isPlay)
            if (bmp != null) {
                newFrames[member.charId] = bmp
                if (member == _selectedCharacter.value) {
                    _currentSpriteFrame.value = bmp
                }
            }
        }
        _allMemberFrames.value = newFrames

        if (_selectedCharacter.value == CharacterFilter.ALL) {
            if (animTick >= nextAllMemberSwitchTick && !isPlay) {
                val others = CharacterFilter.fiveIndividuals.filter { it != _activeAllMemberChar.value }
                _activeAllMemberChar.value = others.random()
                nextAllMemberSwitchTick = animTick + Random.nextInt(46, 138)
                refreshThemeBackground()
            }
            _currentSpriteFrame.value = newFrames[_activeAllMemberChar.value.charId] ?: newFrames[1]
        }

        walkStepFrame = (animTick / 2) % 2
        val camHeading = if (_cameraMode.value == NavigationCameraMode.HEADING_UP) _headingDegrees.value else 0.0
        _currentNavArrowBitmap.value = assetDecryptor.getRM500NavigationArrowFrame(
            selectedChar = _selectedCharacter.value,
            activeAllChar = _activeAllMemberChar.value,
            outfit = _arrowOutfit.value,
            walkStep = walkStepFrame,
            headingDeg = _headingDegrees.value,
            cameraHeadingDeg = camHeading
        )
    }

    fun refreshThemeBackground() {
        val eff = if (_selectedCharacter.value == CharacterFilter.ALL) _activeAllMemberChar.value else _selectedCharacter.value
        val bgName = when (eff) {
            CharacterFilter.YUI, CharacterFilter.ALL -> "rm_bg_yui"
            CharacterFilter.MIO -> "rm_bg_mio"
            CharacterFilter.RITSU -> "rm_bg_ritsu"
            CharacterFilter.MUGI -> "rm_bg_mugi"
            CharacterFilter.AZUSA -> "rm_bg_azusa"
        }
        _themeBackgroundBitmap.value = assetDecryptor.getSpriteBitmap(bgName)
    }

    fun setLanguage(lang: AppLanguage) {
        _language.value = lang
    }

    fun toggleMapMode() {
        _showMapMode.value = !_showMapMode.value
    }

    fun setMapEnlarged(enlarged: Boolean) {
        _isMapEnlarged.value = enlarged
    }

    fun toggleHUDMirror() {
        _isHUDMirrored.value = !_isHUDMirrored.value
    }

    fun setMascotPose(pose: MascotActionState) {
        _mascotAction.value = pose
        if (pose == MascotActionState.TEA_CAKE) {
            triggerTeaTimeReminder()
        } else {
            triggerCharacterTap(null)
        }
    }

    fun resetPositions() {
        _mascotOffsetX.value = 0f
        _mascotAction.value = MascotActionState.IDLE
    }

    fun selectCharacter(char: CharacterFilter) {
        _selectedCharacter.value = char
        _mascotOffsetX.value = 0f
        refreshThemeBackground()
        triggerCharacterTap(char)
    }

    fun setSpeedLimit(limit: Int) {
        if (_speedLimitKmh.value == limit) {
            triggerSpeedLimitPrompt()
        } else {
            _speedLimitKmh.value = limit
            triggerSpeedLimitPrompt()
        }
    }

    fun setTravelMode(mode: NavigationTravelMode) {
        _travelMode.value = mode
        _speedLimitKmh.value = mode.defaultSpeedLimit
        val base = activeBaseId()
        val msg = "[${mode.title(_language.value)}] モード切替完了！制限速度: ${mode.defaultSpeedLimit} km/h"
        playVoice(base + 39, msg)
    }

    fun toggleCameraMode() {
        _cameraMode.value = if (_cameraMode.value == NavigationCameraMode.HEADING_UP) {
            NavigationCameraMode.NORTH_UP
        } else {
            NavigationCameraMode.HEADING_UP
        }
    }

    fun cycleNextArrowOutfit() {
        val all = RM500ArrowOutfit.values()
        val nextIdx = (_arrowOutfit.value.ordinal + 1) % all.size
        _arrowOutfit.value = all[nextIdx]
        triggerCharacterTap(null)
    }

    fun selectArrowOutfit(outfit: RM500ArrowOutfit) {
        _arrowOutfit.value = outfit
        triggerCharacterTap(null)
    }

    fun toggleCruiseMode() {
        _isCruiseModeActive.value = !_isCruiseModeActive.value
        if (_isCruiseModeActive.value) {
            _cruiseRemainingSeconds.value = _cruiseIntervalMinutes.value * 60
            playRandomCruiseVoice()
        }
    }

    fun setCruiseInterval(mins: Int) {
        _cruiseIntervalMinutes.value = mins
        _cruiseRemainingSeconds.value = mins * 60
    }

    private fun playRandomCruiseVoice() {
        val base = activeBaseId()
        val offsets = listOf(1, 5, 12, 28, 39, 67, 73, 84, 94)
        playVoice(base + offsets.random(), "🚗 巡航陪伴播报 · 注意保持安全车距哦♪")
    }

    // Voice Trigger Actions matching iOS
    fun triggerCharacterTap(member: CharacterFilter? = null) {
        _mascotAction.value = MascotActionState.SPECIAL
        val target = member ?: if (_selectedCharacter.value == CharacterFilter.ALL) _activeAllMemberChar.value else _selectedCharacter.value
        playMascotVoice(target)
    }

    fun triggerDepartureGreeting() {
        _mascotAction.value = MascotActionState.SPECIAL
        val base = activeBaseId()
        val offsets = if (_selectedCharacter.value == CharacterFilter.ALL) listOf(135, 142) else listOf(39, 87, 94)
        val msg = when (_language.value) {
            AppLanguage.ZH_HANS -> "ルート案内を始めるよ！出発進行～！(开始路线引导，出发咯！)"
            AppLanguage.ZH_HANT -> "ルート案内を始めるよ！出発進行～！(開始路線引導，出發囉！)"
            AppLanguage.EN -> "Starting route guidance! Let's roll!"
        }
        playVoice(base + offsets.random(), msg)
    }

    fun triggerBanter() {
        _mascotAction.value = MascotActionState.SPECIAL
        val base = activeBaseId()
        val banterOffsets = listOf(67, 68, 69, 70, 73, 84, 85, 86, 87, 91, 94, 95, 115, 116, 118, 121, 132, 135, 140, 142, 143)
        val chosenId = if (Random.nextInt(5) == 0) (1112..1122).random() else (base + banterOffsets.random())
        val msg = when (_language.value) {
            AppLanguage.ZH_HANS -> "【放課後掛け合い】轻音部多人互动对话彩蛋♪"
            AppLanguage.ZH_HANT -> "【放課後掛け合い】輕音部多人互動對話彩蛋♪"
            AppLanguage.EN -> "[HTT Banter] K-ON! Multi-Character Dialogue Event ♪"
        }
        playVoice(chosenId, msg)
    }

    fun triggerTeaTimeReminder() {
        _mascotAction.value = MascotActionState.TEA_CAKE
        val base = activeBaseId()
        val offset = listOf(73, 121).random()
        val msg = when (_language.value) {
            AppLanguage.ZH_HANS -> "🍰 疲れてるなら休憩しよう♪ (放课后下午茶时间，吃块蛋糕休息一下吧！)"
            AppLanguage.ZH_HANT -> "🍰 疲れてるなら休憩しよう♪ (放學後下午茶時間，吃塊蛋糕休息一下吧！)"
            AppLanguage.EN -> "🍰 Tired from driving? Let's take a Tea & Cake break ♪"
        }
        playVoice(base + offset, msg)
    }

    fun triggerBirthdaySpecialVoice() {
        _mascotAction.value = MascotActionState.SPECIAL
        val chosenId = (1112..1122).random()
        val msg = when (_language.value) {
            AppLanguage.ZH_HANS -> "🎂 【RM-500HTT 生日与全员纪念特典】放课后茶会特别祝福原声♪"
            AppLanguage.ZH_HANT -> "🎂 【RM-500HTT 生日與全員紀念特典】放學後茶會特別祝福原聲♪"
            AppLanguage.EN -> "🎂 [RM-500HTT Special Event] K-ON! Birthday & Celebration Voice ♪"
        }
        playVoice(chosenId, msg)
    }

    fun triggerGPSSignalAlert() {
        val base = activeBaseId()
        val offset = if (_selectedCharacter.value == CharacterFilter.ALL) 140 else listOf(44, 92, 140).random()
        val msg = when (_language.value) {
            AppLanguage.ZH_HANS -> "📡 えっと、GPS信号が… (GPS信号状态播报，请检查卫星接收！)"
            AppLanguage.ZH_HANT -> "📡 えっと、GPS信号が… (GPS訊號狀態播報，請檢查衛星接收！)"
            AppLanguage.EN -> "📡 Checking GPS satellite signal reception...!"
        }
        playVoice(base + offset, msg)
    }

    fun triggerSpeedLimitPrompt() {
        val base = activeBaseId()
        val msg = "⚠️ 制限速度は ${_speedLimitKmh.value} km/h です！安全運転でいこう♪"
        playVoice(base + 42, msg)
    }

    // Demo Navigation Simulation
    fun toggleDemoSimulation() {
        if (_isDemoSimulating.value) {
            stopDemoSimulation()
        } else {
            startDemoSimulation()
        }
    }

    fun startRouteToDestination(destName: String) {
        _destinationName.value = destName
        _hasActiveNavigation.value = true
        _showMapMode.value = true
        startDemoSimulation(customDest = destName)
    }

    fun startDemoSimulation(customDest: String? = null) {
        _isDemoSimulating.value = true
        _hasActiveNavigation.value = true
        _destinationName.value = customDest ?: if (_language.value == AppLanguage.EN) "Sakuragaoka High Music Room" else "樱丘高中轻音部部室 (模拟导航)"
        _currentStepInstruction.value = "前方 300 米右转进入樱高大道"
        _distanceToNextStepMeters.value = 300
        _currentSpeedKmh.value = 52
        if (_maxSpeedKmh.value < 52) _maxSpeedKmh.value = 52
        _upcomingCameraDistance.value = 280
        _upcomingServiceAreaDist.value = 2400
        demoStepCounter = 0

        val base = activeBaseId()
        enqueueVoiceCombo(
            listOf(
                Pair(base + 39, "🚗 ルート案内を始めるよ！ドライブ楽しみだな〜"),
                Pair(base + 12, "📍 およそ 300m先 (前方300米)"),
                Pair(base + 28, "↪️ 右方向に行きまーす！対向車に注意してね！")
            )
        )
    }

    fun stopDemoSimulation() {
        _isDemoSimulating.value = false
        _hasActiveNavigation.value = false
        _currentSpeedKmh.value = 0
        _currentStepInstruction.value = "导航已结束 · 放课后茶会伴侣待机中"
        stopAudio()
    }

    private fun advanceDemoSimulationStep() {
        demoStepCounter = (demoStepCounter + 1) % 4
        val b = activeBaseId()
        _headingDegrees.value = (_headingDegrees.value + 35.0) % 360.0
        _tripDistanceKm.value += 0.15
        _currentSpeedKmh.value = Random.nextInt(42, 76)
        if (_currentSpeedKmh.value > _maxSpeedKmh.value) {
            _maxSpeedKmh.value = _currentSpeedKmh.value
        }

        when (demoStepCounter) {
            1 -> {
                _distanceToNextStepMeters.value = 100
                _currentStepInstruction.value = "前方 100 米左转进入商业街"
                _upcomingCameraDistance.value = 160
                enqueueVoiceCombo(
                    listOf(
                        Pair(b + 14, "📍 およそ 100m先 (前方100米)"),
                        Pair(b + 29, "↩️ 左方向に行きまーす！巻き込みに注意してね！")
                    )
                )
            }
            2 -> {
                _distanceToNextStepMeters.value = 30
                _currentStepInstruction.value = "即将驶入高速道路入口 (靠右)"
                _upcomingCameraDistance.value = 90
                enqueueVoiceCombo(
                    listOf(
                        Pair(b + 15, "📍 まもなく (即将到达路口)"),
                        Pair(b + 19, "🛣️ 高速入口だよ！合流に注意してね！")
                    )
                )
            }
            3 -> {
                _distanceToNextStepMeters.value = 0
                _currentStepInstruction.value = "已到达终点：${_destinationName.value}！"
                enqueueVoiceCombo(
                    listOf(
                        Pair(b + 37, "🎉 目的地周辺に到着したよ！"),
                        Pair(b + 38, "✨ これで音声案内は終了だよ！お疲れ様♪")
                    )
                )
            }
            0 -> {
                _distanceToNextStepMeters.value = 300
                _currentStepInstruction.value = "前方 300 米直行通过樱花十字路口"
                playVoice(b + 12, "📍 およそ 300m先 直進だよ♪")
            }
        }
    }

    private fun enqueueVoiceCombo(items: List<Pair<Int, String>>) {
        if (items.isEmpty()) return
        voiceQueue.clear()
        for (i in 1 until items.size) {
            voiceQueue.add(items[i])
        }
        playVoice(items[0].first, items[0].second, clearQueue = false)
    }

    fun activeBaseId(): Int {
        return if (_selectedCharacter.value == CharacterFilter.ALL) {
            CharacterFilter.fiveIndividuals.random().navBaseId
        } else {
            _selectedCharacter.value.navBaseId
        }
    }

    fun characterForVoiceId(id: Int): CharacterFilter = when (id) {
        in 157..300, in 877..923, 1112 -> CharacterFilter.YUI
        in 301..444, in 924..970, 1113 -> CharacterFilter.MIO
        in 445..588, in 971..1017, 1114 -> CharacterFilter.RITSU
        in 589..732, in 1018..1064, 1115 -> CharacterFilter.MUGI
        in 733..876, in 1065..1111, 1116 -> CharacterFilter.AZUSA
        else -> CharacterFilter.ALL
    }

    fun playVoice(id: Int, customQuote: String? = null, clearQueue: Boolean = true) {
        if (clearQueue) voiceQueue.clear()
        val safeId = if (id < 157) (157 + (id % 144)) else id
        val audioBytes = assetDecryptor.decryptVoiceChunk(safeId) ?: return

        val spk = characterForVoiceId(safeId)
        if (spk != CharacterFilter.ALL) {
            _activeAllMemberChar.value = spk
            refreshThemeBackground()
        }
        val quote = customQuote ?: "放课后茶会原版导航语音播报中♪"
        _currentPlayingId.value = safeId
        _currentSpeechBubble.value = "[${spk.displayName(_language.value)}] $quote (#$safeId)"
        playAudioData(audioBytes)
    }

    fun playMascotVoice(character: CharacterFilter? = null) {
        voiceQueue.clear()
        val target = character ?: if (_selectedCharacter.value == CharacterFilter.ALL) _activeAllMemberChar.value else _selectedCharacter.value
        val entries = if (target == CharacterFilter.ALL) {
            assetDecryptor.mascotVoiceEntries
        } else {
            assetDecryptor.mascotVoiceEntries.filter { it.charId == target.charId }
        }

        if (entries.isEmpty()) {
            playVoice(target.navBaseId + 39)
            return
        }
        val chosen = entries.random()
        val audioBytes = assetDecryptor.decryptMascotVoice(chosen) ?: return
        val speakerChar = CharacterFilter.fiveIndividuals.find { it.charId == chosen.charId } ?: CharacterFilter.YUI
        _activeAllMemberChar.value = speakerChar
        refreshThemeBackground()

        val quote = when (chosen.charId) {
            1 -> "うんたん♪ 今日も楽しくドライブしようね！(平泽唯桌宠原声)"
            2 -> "もう、急に触るなよ…安全運転で行こう！(秋山澪桌宠原声)"
            3 -> "よっしゃー！ノリノリで出発だぜ～！(田井中律桌宠原声)"
            4 -> "ふふっ、紅茶とケーキを用意しましたよ♪ (琴吹紬桌宠原声)"
            else -> "先輩！ちゃんと前を見て運転してくださいね！(中野梓桌宠原声)"
        }
        _currentSpeechBubble.value = "[${speakerChar.displayName(_language.value)}] $quote"
        playAudioData(audioBytes)
    }

    fun stopAudio() {
        voiceQueue.clear()
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {}
        _isPlaying.value = false
        _currentPlayingId.value = null
        HTTNaviApp.instance.musicManager.duckForVoice(false)
    }

    private fun playAudioData(audioBytes: ByteArray) {
        try {
            requestAudioFocus()
            HTTNaviApp.instance.musicManager.duckForVoice(true)

            val tempFile = File.createTempFile("htt_voice_", ".mp3", context.cacheDir)
            FileOutputStream(tempFile).use { it.write(audioBytes) }

            mediaPlayer?.release()
            mediaPlayer = MediaPlayer().apply {
                setDataSource(tempFile.absolutePath)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setOnCompletionListener {
                    tempFile.delete()
                    if (voiceQueue.isNotEmpty()) {
                        val next = voiceQueue.removeAt(0)
                        playVoice(next.first, next.second, clearQueue = false)
                    } else {
                        _isPlaying.value = false
                        _currentPlayingId.value = null
                        HTTNaviApp.instance.musicManager.duckForVoice(false)
                    }
                }
                prepare()
                start()
            }
            _isPlaying.value = true
        } catch (e: Exception) {
            Log.e(TAG, "Error playing voice audio", e)
            _isPlaying.value = false
            HTTNaviApp.instance.musicManager.duckForVoice(false)
        }
    }

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .build()
            audioManager.requestAudioFocus(req)
        }
    }
}
