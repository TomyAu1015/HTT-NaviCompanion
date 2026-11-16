package com.tomy.httnavicompanion.audio

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject
import java.util.zip.ZipInputStream
import kotlin.random.Random

data class LudoBoardConfig(
    val mapId: String = "kon_5p_pentagon",
    val displayName: String = "轻音部五人茶会飞行棋 (60步)",
    val playerCount: Int = 5,
    val outerRingCount: Int = 55,
    val sectorLength: Int = 11,
    val outerTravelSteps: Int = 53,
    val homeStretchSteps: Int = 7,
    val totalStepsToFinish: Int = 60
) {
    companion object {
        val reservedMapCounts = listOf(5, 4, 3, 2)
    }
}

enum class LudoGamePhase { LOBBY, ROLLING, CHOOSING, ROUND_OVER }

data class LudoSeat(
    val id: Int,
    val name: String,
    val characterId: Int,
    val isAI: Boolean,
    val peerDisplayName: String,
    val planes: List<Int> = listOf(-1, -1, -1, -1),
    val score: Int = 1000,
    val colorName: String = "樱桃红"
)

class AeroplaneChessEngine(
    private val context: Context,
    private val audioManager: AudioPlayerManager
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val prefs = context.getSharedPreferences("HTT_Ludo", Context.MODE_PRIVATE)
    private val httpClient = OkHttpClient()

    val config = LudoBoardConfig()
    private val _phase = MutableStateFlow(LudoGamePhase.LOBBY)
    val phase: StateFlow<LudoGamePhase> = _phase.asStateFlow()

    private val _seats = MutableStateFlow<List<LudoSeat>>(emptyList())
    val seats: StateFlow<List<LudoSeat>> = _seats.asStateFlow()

    private val _mySeatIndex = MutableStateFlow(0)
    val mySeatIndex: StateFlow<Int> = _mySeatIndex.asStateFlow()

    private val _currentTurnSeat = MutableStateFlow(0)
    val currentTurnSeat: StateFlow<Int> = _currentTurnSeat.asStateFlow()

    private val _lastDice = MutableStateFlow(6)
    val lastDice: StateFlow<Int> = _lastDice.asStateFlow()

    private val _consecutiveSixes = MutableStateFlow(0)
    val consecutiveSixes: StateFlow<Int> = _consecutiveSixes.asStateFlow()

    private val _winnerSeat = MutableStateFlow<Int?>(null)
    val winnerSeat: StateFlow<Int?> = _winnerSeat.asStateFlow()

    private val _statusBanner = MutableStateFlow("欢迎来到轻音部 3D 五人飞行棋！琴吹紬为专属草莓粉色")
    val statusBanner: StateFlow<String> = _statusBanner.asStateFlow()

    private val _myNickname = MutableStateFlow(prefs.getString("nick", "轻音车友") ?: "轻音车友")
    val myNickname: StateFlow<String> = _myNickname.asStateFlow()

    private val _myCharacter = MutableStateFlow(CharacterFilter.YUI)
    val myCharacter: StateFlow<CharacterFilter> = _myCharacter.asStateFlow()

    private val _roomCode = MutableStateFlow("")
    val roomCode: StateFlow<String> = _roomCode.asStateFlow()

    private val _serverUrl = MutableStateFlow("wss://azusa.online/ddz")
    val serverUrl: StateFlow<String> = _serverUrl.asStateFlow()

    private val _isServerConnected = MutableStateFlow(false)
    val isServerConnected: StateFlow<Boolean> = _isServerConnected.asStateFlow()

    private val _isRoomAuthority = MutableStateFlow(true)
    val isRoomAuthority: StateFlow<Boolean> = _isRoomAuthority.asStateFlow()

    private val _connectedPeerNames = MutableStateFlow<List<String>>(emptyList())
    val connectedPeerNames: StateFlow<List<String>> = _connectedPeerNames.asStateFlow()

    private val _currentRound = MutableStateFlow(1)
    val currentRound: StateFlow<Int> = _currentRound.asStateFlow()

    private val _enableKonEvents = MutableStateFlow(true)
    val enableKonEvents: StateFlow<Boolean> = _enableKonEvents.asStateFlow()

    private var myPeerName: String = ""
    private var orderedRoomPeers = mutableListOf<Triple<String, Int, String>>()
    private var webSocket: WebSocket? = null
    private var aiRunnable: Runnable? = null
    private val bitmapCache = HashMap<String, Bitmap>()

    companion object {
        val outerCoords: List<Pair<Float, Float>> = listOf(
            Pair(0.5f, 0.1767f),
            Pair(0.5369f, 0.1788f),
            Pair(0.5719f, 0.1906f),
            Pair(0.6025f, 0.2128f),
            Pair(0.631f, 0.2336f),
            Pair(0.6584f, 0.2535f),
            Pair(0.6855f, 0.2732f),
            Pair(0.7129f, 0.2931f),
            Pair(0.7415f, 0.3138f),
            Pair(0.772f, 0.336f),
            Pair(0.7941f, 0.3657f),
            Pair(0.8075f, 0.4001f),
            Pair(0.8169f, 0.4358f),
            Pair(0.8164f, 0.4728f),
            Pair(0.8048f, 0.5087f),
            Pair(0.7939f, 0.5423f),
            Pair(0.7834f, 0.5745f),
            Pair(0.7731f, 0.6063f),
            Pair(0.7626f, 0.6386f),
            Pair(0.7517f, 0.6721f),
            Pair(0.74f, 0.708f),
            Pair(0.7186f, 0.7382f),
            Pair(0.6901f, 0.7616f),
            Pair(0.659f, 0.7815f),
            Pair(0.6236f, 0.7926f),
            Pair(0.5859f, 0.7926f),
            Pair(0.5506f, 0.7926f),
            Pair(0.5167f, 0.7926f),
            Pair(0.4833f, 0.7926f),
            Pair(0.4494f, 0.7926f),
            Pair(0.4141f, 0.7926f),
            Pair(0.3764f, 0.7926f),
            Pair(0.341f, 0.7815f),
            Pair(0.3099f, 0.7616f),
            Pair(0.2814f, 0.7382f),
            Pair(0.26f, 0.708f),
            Pair(0.2483f, 0.6721f),
            Pair(0.2374f, 0.6386f),
            Pair(0.2269f, 0.6063f),
            Pair(0.2166f, 0.5745f),
            Pair(0.2061f, 0.5423f),
            Pair(0.1952f, 0.5087f),
            Pair(0.1836f, 0.4728f),
            Pair(0.1831f, 0.4358f),
            Pair(0.1925f, 0.4001f),
            Pair(0.2059f, 0.3657f),
            Pair(0.228f, 0.336f),
            Pair(0.2585f, 0.3138f),
            Pair(0.2871f, 0.2931f),
            Pair(0.3145f, 0.2732f),
            Pair(0.3416f, 0.2535f),
            Pair(0.369f, 0.2336f),
            Pair(0.3975f, 0.2128f),
            Pair(0.4281f, 0.1906f),
            Pair(0.4631f, 0.1788f)
        )
        val homeCoords: List<List<Pair<Float, Float>>> = listOf(
            listOf(Pair(0.4083f, 0.2388f), Pair(0.4192f, 0.2647f), Pair(0.43f, 0.2907f), Pair(0.4408f, 0.3166f), Pair(0.4516f, 0.3426f), Pair(0.4624f, 0.3685f), Pair(0.4732f, 0.3945f)),
            listOf(Pair(0.7201f, 0.3321f), Pair(0.6988f, 0.3504f), Pair(0.6774f, 0.3687f), Pair(0.6561f, 0.387f), Pair(0.6348f, 0.4053f), Pair(0.6134f, 0.4236f), Pair(0.5921f, 0.4419f)),
            listOf(Pair(0.7277f, 0.6575f), Pair(0.7037f, 0.6428f), Pair(0.6797f, 0.6282f), Pair(0.6557f, 0.6136f), Pair(0.6317f, 0.5989f), Pair(0.6077f, 0.5843f), Pair(0.5837f, 0.5696f)),
            listOf(Pair(0.4206f, 0.7652f), Pair(0.4271f, 0.7379f), Pair(0.4336f, 0.7105f), Pair(0.4401f, 0.6832f), Pair(0.4466f, 0.6558f), Pair(0.4531f, 0.6285f), Pair(0.4596f, 0.6011f)),
            listOf(Pair(0.2232f, 0.5064f), Pair(0.2513f, 0.5042f), Pair(0.2793f, 0.5019f), Pair(0.3073f, 0.4996f), Pair(0.3353f, 0.4974f), Pair(0.3633f, 0.4951f), Pair(0.3914f, 0.4929f))
        )
        val hangarCoords: List<List<Pair<Float, Float>>> = listOf(
            listOf(Pair(0.6032f, 0.0803f), Pair(0.6532f, 0.0803f), Pair(0.6032f, 0.127f), Pair(0.6532f, 0.127f)),
            listOf(Pair(0.89f, 0.475f), Pair(0.94f, 0.475f), Pair(0.89f, 0.5217f), Pair(0.94f, 0.5217f)),
            listOf(Pair(0.6032f, 0.8697f), Pair(0.6532f, 0.8697f), Pair(0.6032f, 0.9164f), Pair(0.6532f, 0.9164f)),
            listOf(Pair(0.1393f, 0.7189f), Pair(0.1893f, 0.7189f), Pair(0.1393f, 0.7656f), Pair(0.1893f, 0.7656f)),
            listOf(Pair(0.1393f, 0.2311f), Pair(0.1893f, 0.2311f), Pair(0.1393f, 0.2777f), Pair(0.1893f, 0.2777f))
        )
    }

    init {
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        loadLudoAssets()
        rebuildLobbySeats()
    }

    private fun loadLudoAssets() {
        try {
            context.assets.open("doudizhu_cards.zip").use { stream ->
                ZipInputStream(stream).use { zis ->
                    var entry = zis.nextEntry
                    while (entry != null) {
                        if (entry.name.startsWith("ludo_")) {
                            val bytes = zis.readBytes()
                            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bmp ->
                                bitmapCache[entry.name] = bmp
                            }
                        }
                        entry = zis.nextEntry
                    }
                }
            }
        } catch (_: Exception) {}
    }

    fun getAssetBitmap(name: String): Bitmap? = bitmapCache[name]

    private fun cleanNick(): String = _myNickname.value.trim().ifEmpty { "轻音车友" }
    private fun cleanPeer(raw: String): String = raw.substringBeforeLast("#").trim().ifEmpty { raw }
    fun wireRoomCode(): String = _roomCode.value.trim().let { if (it.isEmpty()) "" else "FXQ_$it" }

    fun seatColorName(charId: Int): String = when (charId) {
        1 -> "樱桃红"
        2 -> "皇家蓝"
        3 -> "柠檬黄"
        4 -> "草莓粉"
        else -> "薄荷绿"
    }

    private fun charOrder(charId: Int): Int = when (charId) {
        1 -> 0; 2 -> 1; 3 -> 2; 4 -> 3; else -> 4
    }

    fun setNickname(name: String) {
        _myNickname.value = name
        prefs.edit().putString("nick", name).apply()
        rebuildLobbySeats()
    }

    fun setCharacter(char: CharacterFilter) {
        _myCharacter.value = char
        rebuildLobbySeats()
    }

    fun setRoomCode(code: String) { _roomCode.value = code }
    fun setServerUrl(url: String) { _serverUrl.value = url }
    fun setEnableKonEvents(enabled: Boolean) { _enableKonEvents.value = enabled }

    fun rebuildLobbySeats() {
        val n = config.playerCount
        if (orderedRoomPeers.isEmpty()) {
            orderedRoomPeers.add(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        } else {
            val idx = orderedRoomPeers.indexOfFirst { it.first == myPeerName }
            if (idx >= 0) orderedRoomPeers[idx] = Triple(myPeerName, _myCharacter.value.charId, cleanNick())
        }
        _isRoomAuthority.value = (orderedRoomPeers.first().first == myPeerName)

        val used = HashSet<Int>()
        val list = ArrayList<LudoSeat>(n)
        val oldSeats = _seats.value
        for (i in 0 until n) {
            val prevScore = oldSeats.getOrNull(i)?.score ?: 1000
            if (i < orderedRoomPeers.size) {
                val rp = orderedRoomPeers[i]
                if (rp.first == myPeerName) _mySeatIndex.value = i
                used.add(rp.second)
                val tag = if (i == 0) "👑房主 " else "${i + 1}号 "
                list.add(LudoSeat(i, tag + cleanPeer(rp.third), rp.second, false, rp.first, listOf(-1,-1,-1,-1), prevScore, seatColorName(rp.second)))
            } else {
                val aiChar = CharacterFilter.fiveIndividuals.firstOrNull { !used.contains(it.charId) }?.charId ?: ((i % 5) + 1)
                used.add(aiChar)
                val aiName = CharacterFilter.fiveIndividuals.firstOrNull { it.charId == aiChar }?.displayName(audioManager.language.value) ?: "轻音AI"
                list.add(LudoSeat(i, "$aiName (AI)", aiChar, true, "AI_$i", listOf(-1,-1,-1,-1), prevScore, seatColorName(aiChar)))
            }
        }
        _seats.value = list
    }

    fun connectOnlineServerRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) {
            _statusBanner.value = "⚠️ 请先填写房号，未填写无法连接！"
            return
        }
        stopNetworking()
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        orderedRoomPeers = mutableListOf(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        _isRoomAuthority.value = false
        _isServerConnected.value = true
        val req = Request.Builder().url(_serverUrl.value.trim()).build()
        webSocket = httpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                mainHandler.post { sendJoinRequest() }
            }
            override fun onMessage(ws: WebSocket, text: String) {
                mainHandler.post { handleIncomingJson(text) }
            }
            override fun onMessage(ws: WebSocket, bytes: ByteString) {
                mainHandler.post { handleIncomingJson(bytes.utf8()) }
            }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                mainHandler.post { _isServerConnected.value = false }
            }
        })
    }

    private fun sendJoinRequest() {
        val wc = wireRoomCode()
        if (wc.isEmpty()) return
        val obj = JSONObject().apply {
            put("kind", "joinRequest")
            put("roomCode", wc)
            put("senderPeerName", myPeerName)
            put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", config.playerCount)
            put("gameType", "ludo")
        }
        webSocket?.send(obj.toString())
        _statusBanner.value = "✅ 已连接 3D 五人飞行棋房间 [${_roomCode.value}]"
    }

    fun leaveRoomAndResetLobby() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        val wc = wireRoomCode()
        if (_isServerConnected.value && wc.isNotEmpty()) {
            val obj = JSONObject().apply {
                put("kind", "leaveRoom")
                put("roomCode", wc)
                put("senderPeerName", myPeerName)
                put("senderCharId", _myCharacter.value.charId)
            }
            webSocket?.send(obj.toString())
        }
        stopNetworking()
        _phase.value = LudoGamePhase.LOBBY
        _currentRound.value = 1
        rebuildLobbySeats()
        _statusBanner.value = "已退出飞行棋房间"
    }

    private fun stopNetworking() {
        webSocket?.close(1000, "leave")
        webSocket = null
        _isServerConnected.value = false
        _connectedPeerNames.value = emptyList()
        orderedRoomPeers.clear()
    }

    private fun broadcastFullState() {
        if (!_isServerConnected.value || !_isRoomAuthority.value || wireRoomCode().isEmpty()) return
        val peersArr = JSONArray()
        orderedRoomPeers.forEach { rp ->
            peersArr.put(JSONObject().apply {
                put("name", rp.first); put("charId", rp.second); put("displayName", rp.third)
            })
        }
        val seatsArr = JSONArray()
        _seats.value.forEach { s ->
            val pArr = JSONArray()
            s.planes.forEach { pArr.put(it) }
            seatsArr.put(JSONObject().apply {
                put("id", s.id); put("name", s.name); put("characterId", s.characterId)
                put("isAI", s.isAI); put("peerDisplayName", s.peerDisplayName)
                put("planes", pArr); put("score", s.score); put("colorName", s.colorName)
            })
        }
        val pkt = JSONObject().apply {
            put("kind", "stateSync")
            put("roomCode", wireRoomCode())
            put("senderPeerName", myPeerName)
            put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", config.playerCount)
            put("gameType", "ludo")
            put("hostPeerName", myPeerName)
            put("roomPeers", peersArr)
            put("seats", seatsArr)
            put("phase", when(_phase.value) {
                LudoGamePhase.LOBBY -> "lobby"
                LudoGamePhase.ROLLING -> "rolling"
                LudoGamePhase.CHOOSING -> "choosing"
                LudoGamePhase.ROUND_OVER -> "roundOver"
            })
            put("currentTurnSeat", _currentTurnSeat.value)
            put("lastDice", _lastDice.value)
            put("consecutiveSixes", _consecutiveSixes.value)
            _winnerSeat.value?.let { put("winnerSeat", it) }
            put("currentRound", _currentRound.value)
            put("statusBanner", _statusBanner.value)
        }
        webSocket?.send(pkt.toString())
    }

    private fun handleIncomingJson(raw: String) {
        try {
            val obj = JSONObject(raw)
            if (obj.optString("roomCode") != wireRoomCode() || wireRoomCode().isEmpty()) return
            val kind = obj.optString("kind")
            val sender = obj.optString("senderPeerName")
            val sChar = obj.optInt("senderCharId", 1)
            when (kind) {
                "roomRoster" -> {
                    val rpArr = obj.optJSONArray("roomPeers") ?: return
                    val list = mutableListOf<Triple<String, Int, String>>()
                    for (i in 0 until rpArr.length()) {
                        val ro = rpArr.getJSONObject(i)
                        list.add(Triple(ro.getString("name"), ro.optInt("charId", 1), ro.optString("displayName", ro.getString("name"))))
                    }
                    if (list.isNotEmpty()) {
                        orderedRoomPeers = list
                        _connectedPeerNames.value = list.map { it.first }.filter { it != myPeerName }
                        _isRoomAuthority.value = (list.first().first == myPeerName)
                        if (_phase.value == LudoGamePhase.LOBBY) rebuildLobbySeats()
                    }
                }
                "joinRequest" -> {
                    if (sender == myPeerName) return
                    if (_isRoomAuthority.value && orderedRoomPeers.none { it.first == sender } && orderedRoomPeers.size < config.playerCount) {
                        orderedRoomPeers.add(Triple(sender, sChar, cleanPeer(sender)))
                        rebuildLobbySeats()
                        val peersArr = JSONArray()
                        orderedRoomPeers.forEach { rp -> peersArr.put(JSONObject().apply { put("name", rp.first); put("charId", rp.second); put("displayName", rp.third) }) }
                        webSocket?.send(JSONObject().apply {
                            put("kind", "roomRoster"); put("roomCode", wireRoomCode())
                            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                            put("hostPeerName", myPeerName); put("roomPeers", peersArr)
                        }.toString())
                        broadcastFullState()
                    }
                }
                "leaveRoom" -> {
                    orderedRoomPeers.removeAll { it.first == sender }
                    _connectedPeerNames.value = orderedRoomPeers.map { it.first }.filter { it != myPeerName }
                    _isRoomAuthority.value = orderedRoomPeers.isEmpty() || orderedRoomPeers.first().first == myPeerName
                    if (_phase.value == LudoGamePhase.LOBBY) rebuildLobbySeats()
                }
                "stateSync" -> {
                    if (sender == myPeerName) return
                    _isRoomAuthority.value = (obj.optString("hostPeerName") == myPeerName)
                    val sArr = obj.optJSONArray("seats")
                    if (sArr != null) {
                        val list = ArrayList<LudoSeat>()
                        for (i in 0 until sArr.length()) {
                            val so = sArr.getJSONObject(i)
                            val pArr = so.optJSONArray("planes")
                            val planes = (0 until 4).map { idx -> pArr?.optInt(idx, -1) ?: -1 }
                            val pd = so.optString("peerDisplayName", "")
                            if (pd == myPeerName) _mySeatIndex.value = i
                            list.add(LudoSeat(so.optInt("id", i), so.optString("name", ""), so.optInt("characterId", 1), so.optBoolean("isAI", false), pd, planes, so.optInt("score", 1000), so.optString("colorName", "樱桃红")))
                        }
                        _seats.value = list
                    }
                    _phase.value = when (obj.optString("phase")) {
                        "rolling" -> LudoGamePhase.ROLLING
                        "choosing" -> LudoGamePhase.CHOOSING
                        "roundOver" -> LudoGamePhase.ROUND_OVER
                        else -> LudoGamePhase.LOBBY
                    }
                    _currentTurnSeat.value = obj.optInt("currentTurnSeat", _currentTurnSeat.value)
                    _lastDice.value = obj.optInt("lastDice", _lastDice.value)
                    _consecutiveSixes.value = obj.optInt("consecutiveSixes", 0)
                    _winnerSeat.value = if (obj.has("winnerSeat")) obj.optInt("winnerSeat") else null
                    _currentRound.value = obj.optInt("currentRound", _currentRound.value)
                    obj.optString("statusBanner", "").takeIf { it.isNotEmpty() }?.let { _statusBanner.value = it }
                }
                "rollDiceAction" -> {
                    if (_isRoomAuthority.value) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == sender }
                        if (idx == _currentTurnSeat.value) executeRollDice(idx)
                    }
                }
                "movePlaneAction" -> {
                    if (_isRoomAuthority.value) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == sender }
                        if (idx == _currentTurnSeat.value) executeMovePlane(idx, obj.optInt("planeIndex", 0))
                    }
                }
            }
        } catch (_: Exception) {}
    }

    fun startNewRound() {
        if (_isServerConnected.value && !_isRoomAuthority.value) return
        rebuildLobbySeats()
        _seats.value = _seats.value.map { it.copy(planes = listOf(-1, -1, -1, -1)) }
        _currentTurnSeat.value = (_currentRound.value - 1) % _seats.value.size
        _lastDice.value = 6
        _consecutiveSixes.value = 0
        _winnerSeat.value = null
        _phase.value = LudoGamePhase.ROLLING
        _statusBanner.value = "✈️ 3D 五人飞行棋第 ${_currentRound.value} 局开始！轮到 [${_seats.value[_currentTurnSeat.value].name}] 掷骰子"
        broadcastFullState()
        scheduleAIIfNeeded()
    }

    fun rollDiceTapped() {
        if (_phase.value != LudoGamePhase.ROLLING || _currentTurnSeat.value != _mySeatIndex.value) return
        if (_isServerConnected.value && !_isRoomAuthority.value) {
            webSocket?.send(JSONObject().apply {
                put("kind", "rollDiceAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            }.toString())
            return
        }
        executeRollDice(_mySeatIndex.value)
    }

    fun movePlaneTapped(planeIdx: Int) {
        if (_phase.value != LudoGamePhase.CHOOSING || _currentTurnSeat.value != _mySeatIndex.value) return
        if (!canMovePlane(_mySeatIndex.value, planeIdx, _lastDice.value)) return
        if (_isServerConnected.value && !_isRoomAuthority.value) {
            webSocket?.send(JSONObject().apply {
                put("kind", "movePlaneAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                put("planeIndex", planeIdx)
            }.toString())
            return
        }
        executeMovePlane(_mySeatIndex.value, planeIdx)
    }

    fun canMovePlane(seatIdx: Int, planeIdx: Int, dice: Int): Boolean {
        val s = _seats.value.getOrNull(seatIdx) ?: return false
        val prog = s.planes.getOrNull(planeIdx) ?: return false
        if (prog >= config.totalStepsToFinish) return false
        return if (prog == -1) dice == 6 else true
    }

    fun planeCoordinate(seatIdx: Int, planeIdx: Int): Pair<Float, Float> {
        val s = _seats.value.getOrNull(seatIdx) ?: return Pair(0.5f, 0.5f)
        val prog = s.planes.getOrNull(planeIdx) ?: -1
        val co = charOrder(s.characterId)
        if (prog < 0) return hangarCoords[co][planeIdx]
        if (prog >= config.totalStepsToFinish) return Pair(0.5f, 0.5f)
        if (prog < config.outerTravelSteps) {
            val oIdx = (co * config.sectorLength + prog) % config.outerRingCount
            return outerCoords[oIdx]
        }
        val hIdx = (prog - config.outerTravelSteps).coerceAtMost(config.homeStretchSteps - 1)
        return homeCoords[co][hIdx]
    }

    private fun outerIndex(seatIdx: Int, prog: Int): Int? {
        if (prog < 0 || prog >= config.outerTravelSteps) return null
        val co = charOrder(_seats.value[seatIdx].characterId)
        return (co * config.sectorLength + prog) % config.outerRingCount
    }

    private fun executeRollDice(seatIdx: Int) {
        if (_phase.value != LudoGamePhase.ROLLING || seatIdx != _currentTurnSeat.value) return
        val d = Random.nextInt(1, 7)
        _lastDice.value = d
        _consecutiveSixes.value = if (d == 6) _consecutiveSixes.value + 1 else 0
        if (_consecutiveSixes.value >= 3) {
            _statusBanner.value = "🎲 [${_seats.value[seatIdx].name}] 连续3个6！换下一位"
            _consecutiveSixes.value = 0
            advanceTurn()
            return
        }
        val movable = (0 until 4).filter { canMovePlane(seatIdx, it, d) }
        if (movable.isEmpty()) {
            _statusBanner.value = "🎲 [${_seats.value[seatIdx].name}] 掷出 $d 点，暂无可飞飞机"
            if (d == 6) {
                _phase.value = LudoGamePhase.ROLLING
                broadcastFullState()
                scheduleAIIfNeeded()
            } else advanceTurn()
        } else if (movable.size == 1 || _seats.value[seatIdx].isAI) {
            val pick = if (d == 6) (movable.firstOrNull { _seats.value[seatIdx].planes[it] == -1 } ?: movable.maxByOrNull { _seats.value[seatIdx].planes[it] } ?: movable[0]) else (movable.maxByOrNull { _seats.value[seatIdx].planes[it] } ?: movable[0])
            if (_seats.value[seatIdx].isAI) {
                _phase.value = LudoGamePhase.CHOOSING
                _statusBanner.value = "🎲 [${_seats.value[seatIdx].name}] 掷出 $d 点，正在飞行..."
                broadcastFullState()
                val r = Runnable { executeMovePlane(seatIdx, pick) }
                aiRunnable = r
                mainHandler.postDelayed(r, 1100L)
            } else executeMovePlane(seatIdx, pick)
        } else {
            _phase.value = LudoGamePhase.CHOOSING
            _statusBanner.value = "🎲 [${_seats.value[seatIdx].name}] 掷出 $d 点！请点选高亮飞机"
            broadcastFullState()
        }
    }

    private fun executeMovePlane(seatIdx: Int, planeIdx: Int) {
        val list = _seats.value.toMutableList()
        val s = list.getOrNull(seatIdx) ?: return
        val planes = s.planes.toMutableList()
        var prog = planes[planeIdx]
        var bonus = (_lastDice.value == 6)
        var msg = ""

        if (prog == -1) {
            prog = 0
            msg = "✈️ [${s.name}] 掷出 6 点成功起飞！"
        } else {
            prog += _lastDice.value
            if (prog > config.totalStepsToFinish) {
                prog = config.totalStepsToFinish - (prog - config.totalStepsToFinish)
                msg = "↩️ [${s.name}] 反弹回第 $prog 格"
            } else if (prog == config.totalStepsToFinish) {
                msg = "🍵 [${s.name}] 1架飞机抵达茶室终点！"
            } else {
                msg = "✈️ [${s.name}] 前进 ${_lastDice.value} 步"
            }
            if (prog < config.outerTravelSteps) {
                if (prog == 17) { prog = 29; msg += " · ⚡轻音超级航线！" }
                else if (prog > 0 && prog % 5 == 0 && prog + 5 < config.outerTravelSteps) { prog += 5; msg += " · ✨连跳+5！" }
                if (_enableKonEvents.value && prog % 11 == 5) { bonus = true; msg += " · 🍰紬的草莓蛋糕(再投一次)！" }
            }
        }
        planes[planeIdx] = prog
        list[seatIdx] = s.copy(planes = planes)

        val myOuter = outerIndex(seatIdx, prog)
        if (myOuter != null) {
            for (other in list.indices) {
                if (other == seatIdx) continue
                val op = list[other].planes.toMutableList()
                var hit = false
                for (k in 0 until 4) {
                    if (outerIndex(other, op[k]) == myOuter) { op[k] = -1; hit = true }
                }
                if (hit) {
                    list[other] = list[other].copy(planes = op)
                    msg += " · 💥撞回 [${list[other].name}]！"
                }
            }
        }

        if (list[seatIdx].planes.all { it >= config.totalStepsToFinish }) {
            for (i in list.indices) {
                val ns = if (i == seatIdx) list[i].score + 100 * (list.size - 1) else list[i].score - 100
                list[i] = list[i].copy(score = ns)
            }
            _seats.value = list
            _phase.value = LudoGamePhase.ROUND_OVER
            _winnerSeat.value = seatIdx
            _statusBanner.value = "🏆 [${list[seatIdx].name}] 四机齐入茶室获胜！"
            broadcastFullState()
            return
        }

        _seats.value = list
        _statusBanner.value = msg
        if (bonus) {
            _phase.value = LudoGamePhase.ROLLING
            broadcastFullState()
            scheduleAIIfNeeded()
        } else advanceTurn()
    }

    private fun advanceTurn() {
        _currentTurnSeat.value = (_currentTurnSeat.value + 1) % _seats.value.size
        _consecutiveSixes.value = 0
        _phase.value = LudoGamePhase.ROLLING
        _statusBanner.value = "${_statusBanner.value} · 轮到 [${_seats.value[_currentTurnSeat.value].name}]"
        broadcastFullState()
        scheduleAIIfNeeded()
    }

    private fun scheduleAIIfNeeded() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        if (_isServerConnected.value && !_isRoomAuthority.value) return
        val cur = _currentTurnSeat.value
        if (_phase.value == LudoGamePhase.ROLLING && _seats.value.getOrNull(cur)?.isAI == true) {
            val r = Runnable { executeRollDice(cur) }
            aiRunnable = r
            mainHandler.postDelayed(r, 1400L)
        }
    }

    fun nextRound() {
        _currentRound.value += 1
        startNewRound()
    }
}


