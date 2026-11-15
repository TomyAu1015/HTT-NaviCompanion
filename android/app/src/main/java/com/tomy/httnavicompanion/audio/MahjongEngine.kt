package com.tomy.httnavicompanion.audio

import android.annotation.SuppressLint
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit

enum class MahjongSuit(val code: String, val unit: String, val sortOrder: Int) {
    ZHONG("Z", "中", 0),
    WAN("W", "万", 1),
    TIAO("T", "条", 2),
    TONG("D", "筒", 3),
    HONOR("H", "字", 4);

    companion object {
        fun fromCode(code: String): MahjongSuit = values().firstOrNull { it.code == code } ?: WAN
    }
}

data class MahjongTile(
    val id: String,
    val suit: MahjongSuit,
    val rank: Int
) {
    val isLaizi: Boolean get() = suit == MahjongSuit.ZHONG
    val typeKey: Int
        get() = when (suit) {
            MahjongSuit.WAN -> rank - 1
            MahjongSuit.TIAO -> 9 + (rank - 1)
            MahjongSuit.TONG -> 18 + (rank - 1)
            MahjongSuit.HONOR -> 27 + (rank - 1)
            MahjongSuit.ZHONG -> 33
        }
    val shortLabel: String
        get() {
            if (suit == MahjongSuit.ZHONG) return "中"
            if (suit == MahjongSuit.HONOR) {
                val honors = listOf("", "东", "南", "西", "北", "发", "白")
                return if (rank in 1..6) honors[rank] else "字"
            }
            val nums = listOf("", "一", "二", "三", "四", "五", "六", "七", "八", "九")
            return if (suit == MahjongSuit.WAN && rank in 1..9) nums[rank] else rank.toString()
        }
    val fullName: String get() = when (suit) {
        MahjongSuit.ZHONG -> "红中"
        MahjongSuit.HONOR -> shortLabel
        else -> "$rank${suit.unit}"
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("suit", suit.code)
        put("rank", rank)
    }

    companion object {
        fun fromJson(obj: JSONObject): MahjongTile = MahjongTile(
            id = obj.optString("id"),
            suit = MahjongSuit.fromCode(obj.optString("suit", "W")),
            rank = obj.optInt("rank", 1)
        )
    }
}

enum class MahjongMeldKind(val label: String) {
    PONG("碰"),
    EXPOSED_KONG("明杠"),
    CONCEALED_KONG("暗杠");

    companion object {
        fun fromLabel(lbl: String): MahjongMeldKind = values().firstOrNull { it.label == lbl } ?: PONG
    }
}

data class MahjongMeld(
    val id: String,
    val kind: MahjongMeldKind,
    val tile: MahjongTile
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("kind", kind.label)
        put("tile", tile.toJson())
    }

    companion object {
        fun fromJson(obj: JSONObject): MahjongMeld = MahjongMeld(
            id = obj.optString("id", UUID.randomUUID().toString()),
            kind = MahjongMeldKind.fromLabel(obj.optString("kind", "碰")),
            tile = MahjongTile.fromJson(obj.optJSONObject("tile") ?: JSONObject())
        )
    }
}

data class MahjongSeat(
    val id: Int,
    val name: String,
    val character: CharacterFilter,
    val isAI: Boolean,
    val peerDisplayName: String,
    val hand: List<MahjongTile> = emptyList(),
    val melds: List<MahjongMeld> = emptyList(),
    val discards: List<MahjongTile> = emptyList(),
    val score: Int = 1000,
    val isDealer: Boolean = false,
    val lastActionText: String = ""
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("characterId", character.charId)
        put("isAI", isAI)
        put("peerDisplayName", peerDisplayName)
        put("hand", JSONArray().apply { hand.forEach { put(it.toJson()) } })
        put("melds", JSONArray().apply { melds.forEach { put(it.toJson()) } })
        put("discards", JSONArray().apply { discards.forEach { put(it.toJson()) } })
        put("score", score)
        put("isDealer", isDealer)
        put("lastActionText", lastActionText)
    }

    companion object {
        fun fromJson(obj: JSONObject): MahjongSeat {
            val cid = obj.optInt("characterId", 1)
            val ch = CharacterFilter.fiveIndividuals.firstOrNull { it.charId == cid } ?: CharacterFilter.YUI
            val hArr = obj.optJSONArray("hand") ?: JSONArray()
            val mArr = obj.optJSONArray("melds") ?: JSONArray()
            val dArr = obj.optJSONArray("discards") ?: JSONArray()
            return MahjongSeat(
                id = obj.optInt("id", 0),
                name = obj.optString("name", "玩家"),
                character = ch,
                isAI = obj.optBoolean("isAI", false),
                peerDisplayName = obj.optString("peerDisplayName", ""),
                hand = (0 until hArr.length()).map { MahjongTile.fromJson(hArr.getJSONObject(it)) },
                melds = (0 until mArr.length()).map { MahjongMeld.fromJson(mArr.getJSONObject(it)) },
                discards = (0 until dArr.length()).map { MahjongTile.fromJson(dArr.getJSONObject(it)) },
                score = obj.optInt("score", 1000),
                isDealer = obj.optBoolean("isDealer", false),
                lastActionText = obj.optString("lastActionText", "")
            )
        }
    }
}

enum class MahjongGamePhase(val wire: String) {
    LOBBY("lobby"),
    PLAYING("playing"),
    CLAIM_WINDOW("claimWindow"),
    ROUND_OVER("roundOver")
}

data class MahjongPendingClaim(
    val discarderSeat: Int,
    val tile: MahjongTile,
    val eligibleHuSeats: List<Int>,
    val eligibleKongSeats: List<Int>,
    val eligiblePongSeats: List<Int>,
    val passedSeats: List<Int>
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("discarderSeat", discarderSeat)
        put("tile", tile.toJson())
        put("eligibleHuSeats", JSONArray(eligibleHuSeats))
        put("eligibleKongSeats", JSONArray(eligibleKongSeats))
        put("eligiblePongSeats", JSONArray(eligiblePongSeats))
        put("passedSeats", JSONArray(passedSeats))
    }

    companion object {
        private fun arrToInts(a: JSONArray?): List<Int> =
            if (a == null) emptyList() else (0 until a.length()).map { a.getInt(it) }

        fun fromJson(obj: JSONObject?): MahjongPendingClaim? {
            if (obj == null) return null
            return MahjongPendingClaim(
                discarderSeat = obj.optInt("discarderSeat", 0),
                tile = MahjongTile.fromJson(obj.optJSONObject("tile") ?: return null),
                eligibleHuSeats = arrToInts(obj.optJSONArray("eligibleHuSeats")),
                eligibleKongSeats = arrToInts(obj.optJSONArray("eligibleKongSeats")),
                eligiblePongSeats = arrToInts(obj.optJSONArray("eligiblePongSeats")),
                passedSeats = arrToInts(obj.optJSONArray("passedSeats"))
            )
        }
    }
}

object MahjongEvaluator {
    fun sortHand(tiles: List<MahjongTile>): List<MahjongTile> =
        tiles.sortedWith(compareBy<MahjongTile> { it.suit.sortOrder }.thenBy { it.rank }.thenBy { it.id })

    fun canWin(hand: List<MahjongTile>, meldsCount: Int, extraTile: MahjongTile? = null): Boolean {
        val all = if (extraTile != null) hand + extraTile else hand
        if (all.size != 14 - meldsCount * 3) return false
        val counts = IntArray(33)
        var laizi = 0
        for (t in all) {
            if (t.isLaizi) laizi += 1 else if (t.typeKey in 0 until 33) counts[t.typeKey] += 1
        }
        if (laizi >= 4) return true
        if (meldsCount == 0 && all.size == 14) {
            var singles = 0
            for (c in counts) if (c % 2 == 1) singles += 1
            if (laizi >= singles && (laizi - singles) % 2 == 0) return true
        }
        if (laizi >= 2 && canFormMelds(counts, laizi - 2)) return true
        if (laizi >= 1) {
            for (i in 0 until 33) {
                if (counts[i] >= 1) {
                    counts[i] -= 1
                    val ok = canFormMelds(counts, laizi - 1)
                    counts[i] += 1
                    if (ok) return true
                }
            }
        }
        for (i in 0 until 33) {
            if (counts[i] >= 2) {
                counts[i] -= 2
                val ok = canFormMelds(counts, laizi)
                counts[i] += 2
                if (ok) return true
            }
        }
        return false
    }

    private fun canFormMelds(counts: IntArray, laizi: Int): Boolean {
        val firstIdx = counts.indexOfFirst { it > 0 }
        if (firstIdx == -1) return laizi % 3 == 0
        val c = counts[firstIdx]
        if (c >= 3) {
            counts[firstIdx] -= 3
            val ok = canFormMelds(counts, laizi)
            counts[firstIdx] += 3
            if (ok) return true
        } else if (c == 2 && laizi >= 1) {
            counts[firstIdx] -= 2
            val ok = canFormMelds(counts, laizi - 1)
            counts[firstIdx] += 2
            if (ok) return true
        } else if (c == 1 && laizi >= 2) {
            counts[firstIdx] -= 1
            val ok = canFormMelds(counts, laizi - 2)
            counts[firstIdx] += 1
            if (ok) return true
        }
        if (firstIdx < 27) {
            val suitBase = (firstIdx / 9) * 9
            val pos = firstIdx - suitBase
            if (pos <= 6) {
                val need2 = if (counts[firstIdx + 1] > 0) 0 else 1
                val need3 = if (counts[firstIdx + 2] > 0) 0 else 1
                val need = need2 + need3
                if (laizi >= need) {
                    counts[firstIdx] -= 1
                    if (need2 == 0) counts[firstIdx + 1] -= 1
                    if (need3 == 0) counts[firstIdx + 2] -= 1
                    val ok = canFormMelds(counts, laizi - need)
                    counts[firstIdx] += 1
                    if (need2 == 0) counts[firstIdx + 1] += 1
                    if (need3 == 0) counts[firstIdx + 2] += 1
                    if (ok) return true
                }
            }
        }
        return false
    }

    fun readyTiles(hand: List<MahjongTile>, meldsCount: Int): List<MahjongTile> {
        if (hand.size != 13 - meldsCount * 3) return emptyList()
        val res = mutableListOf<MahjongTile>()
        for (s in listOf(MahjongSuit.WAN, MahjongSuit.TIAO, MahjongSuit.TONG)) {
            for (r in 1..9) {
                val cand = MahjongTile("ting_${s.code}_$r", s, r)
                if (canWin(hand, meldsCount, cand)) res.add(cand)
            }
        }
        for (r in 1..6) {
            val cand = MahjongTile("ting_H_$r", MahjongSuit.HONOR, r)
            if (canWin(hand, meldsCount, cand)) res.add(cand)
        }
        val z = MahjongTile("ting_Z_0", MahjongSuit.ZHONG, 0)
        if (canWin(hand, meldsCount, z)) res.add(z)
        return res
    }

    fun bestAIDiscard(hand: List<MahjongTile>): MahjongTile {
        val nonLaizi = hand.filter { !it.isLaizi }
        if (nonLaizi.isEmpty()) return hand.last()
        val counts = IntArray(33)
        nonLaizi.forEach { if (it.typeKey in 0 until 33) counts[it.typeKey] += 1 }
        var best = nonLaizi[0]
        var lowest = Int.MAX_VALUE
        for (t in nonLaizi) {
            val k = t.typeKey
            var score = (counts[k] - 1) * 14
            if (k < 27) {
                val pos = k % 9
                if (pos > 0 && counts[k - 1] > 0) score += 7
                if (pos < 8 && counts[k + 1] > 0) score += 7
                if (pos > 1 && counts[k - 2] > 0) score += 3
                if (pos < 7 && counts[k + 2] > 0) score += 3
                if (pos == 0 || pos == 8) score -= 2
            } else {
                score -= 3
            }
            if (score < lowest) {
                lowest = score
                best = t
            }
        }
        return best
    }
}

class MahjongEngine(private val context: Context, private val audioMgr: AudioPlayerManager) {
    private val TAG = "MahjongEngine"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val tcpPort = 47791
    private val udpPort = 47792

    private val _networkMode = MutableStateFlow(DoudizhuNetworkMode.FACE_TO_FACE_P2P)
    val networkMode: StateFlow<DoudizhuNetworkMode> = _networkMode

    private val _serverUrl = MutableStateFlow("wss://azusa.online/ddz")
    val serverUrl: StateFlow<String> = _serverUrl

    private val _directConnectIp = MutableStateFlow("")
    val directConnectIp: StateFlow<String> = _directConnectIp

    private val _localIpAddress = MutableStateFlow("127.0.0.1")
    val localIpAddress: StateFlow<String> = _localIpAddress

    private val _roomCode = MutableStateFlow("")
    val roomCode: StateFlow<String> = _roomCode

    private val _myNickname = MutableStateFlow(Build.MODEL.ifBlank { "轻音雀友" })
    val myNickname: StateFlow<String> = _myNickname

    private val _myChar = MutableStateFlow(CharacterFilter.YUI)
    val myChar: StateFlow<CharacterFilter> = _myChar

    private val _isHostingRoom = MutableStateFlow(false)
    val isHostingRoom: StateFlow<Boolean> = _isHostingRoom

    private val _isScanningRooms = MutableStateFlow(false)
    val isScanningRooms: StateFlow<Boolean> = _isScanningRooms

    private val _isServerConnected = MutableStateFlow(false)
    val isServerConnected: StateFlow<Boolean> = _isServerConnected

    private val _isRoomAuthority = MutableStateFlow(true)
    val isRoomAuthority: StateFlow<Boolean> = _isRoomAuthority
    private val isRoomAuthorityVal: Boolean get() = _isRoomAuthority.value

    private val _discoveredRooms = MutableStateFlow<List<DiscoveredP2PRoom>>(emptyList())
    val discoveredRooms: StateFlow<List<DiscoveredP2PRoom>> = _discoveredRooms

    private val _connectedPeerNames = MutableStateFlow<List<String>>(emptyList())
    val connectedPeerNames: StateFlow<List<String>> = _connectedPeerNames

    private val _totalRounds = MutableStateFlow(4)
    val totalRounds: StateFlow<Int> = _totalRounds

    private val _currentRound = MutableStateFlow(1)
    val currentRound: StateFlow<Int> = _currentRound

    private val _baseScore = MutableStateFlow(100)
    val baseScore: StateFlow<Int> = _baseScore

    private val _turnTimeLimit = MutableStateFlow(20)
    val turnTimeLimit: StateFlow<Int> = _turnTimeLimit

    private val _turnRemainingSeconds = MutableStateFlow(20)
    val turnRemainingSeconds: StateFlow<Int> = _turnRemainingSeconds

    private val _statusBanner = MutableStateFlow("欢迎来到广东红中麻将！红中为赖子，不能吃，可碰杠胡")
    val statusBanner: StateFlow<String> = _statusBanner

    private val _phase = MutableStateFlow(MahjongGamePhase.LOBBY)
    val phase: StateFlow<MahjongGamePhase> = _phase

    private val _seats = MutableStateFlow<List<MahjongSeat>>(emptyList())
    val seats: StateFlow<List<MahjongSeat>> = _seats

    private val _mySeatIndex = MutableStateFlow(0)
    val mySeatIndex: StateFlow<Int> = _mySeatIndex

    private val _wallCount = MutableStateFlow(0)
    val wallCount: StateFlow<Int> = _wallCount

    private val _currentTurnSeat = MutableStateFlow(0)
    val currentTurnSeat: StateFlow<Int> = _currentTurnSeat

    private val _selectedTileId = MutableStateFlow<String?>(null)
    val selectedTileId: StateFlow<String?> = _selectedTileId

    private val _drawnTileId = MutableStateFlow<String?>(null)
    val drawnTileId: StateFlow<String?> = _drawnTileId

    private val _pendingClaim = MutableStateFlow<MahjongPendingClaim?>(null)
    val pendingClaim: StateFlow<MahjongPendingClaim?> = _pendingClaim

    private val _winnerSeat = MutableStateFlow<Int?>(null)
    val winnerSeat: StateFlow<Int?> = _winnerSeat

    private val _winReason = MutableStateFlow("")
    val winReason: StateFlow<String> = _winReason

    private val deviceShortTag: String by lazy {
        val prefs = context.getSharedPreferences("kon_mj_prefs", Context.MODE_PRIVATE)
        val saved = prefs.getString("device_tag", null)
        if (!saved.isNullOrBlank()) saved else {
            val g = (100..999).random().toString()
            prefs.edit().putString("device_tag", g).apply()
            g
        }
    }
    private fun cleanNickname(): String = _myNickname.value.trim().ifBlank { "轻音雀友" }
    private fun myPeerKey(): String = "${cleanNickname()}#$deviceShortTag"
    private fun cleanPeerLabel(raw: String): String {
        val idx = raw.lastIndexOf("#")
        return if (idx > 0) raw.substring(0, idx).trim().ifBlank { raw } else raw
    }
    private fun wireRoomCode(): String {
        val c = _roomCode.value.trim()
        return if (c.isEmpty()) "" else "MJ_$c"
    }

    private var activeConnectedRoomCode = ""
    private val peerCharMap = mutableMapOf<String, CharacterFilter>()
    private val orderedRoomPeers = mutableListOf<Pair<String, Int>>()
    private val wall = mutableListOf<MahjongTile>()

    private interface PeerChannel {
        fun sendJson(raw: String)
        fun close()
    }
    private val activeChannels = CopyOnWriteArrayList<PeerChannel>()
    private var tcpServerSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var udpSocket: DatagramSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var nsdManager: NsdManager? = null
    private var nsdRegListener: NsdManager.RegistrationListener? = null
    private var nsdDiscListener: NsdManager.DiscoveryListener? = null
    private var webSocket: WebSocket? = null
    private val okHttpClient = OkHttpClient.Builder().pingInterval(15, TimeUnit.SECONDS).build()

    init {
        refreshLocalIpAddress()
        rebuildLobbySeats(forceRebuild = true)
        startTimerLoop()
    }

    private fun startTimerLoop() {
        val r = object : Runnable {
            override fun run() {
                if ((_phase.value == MahjongGamePhase.PLAYING || _phase.value == MahjongGamePhase.CLAIM_WINDOW) && _turnTimeLimit.value > 0) {
                    if (_turnRemainingSeconds.value > 0) {
                        _turnRemainingSeconds.value -= 1
                    } else {
                        _turnRemainingSeconds.value = _turnTimeLimit.value
                        if (isRoomAuthorityVal) handleTimeout()
                    }
                }
                mainHandler.postDelayed(this, 1000L)
            }
        }
        mainHandler.postDelayed(r, 1000L)
    }

    fun refreshLocalIpAddress(): String {
        var bestIp = "127.0.0.1"
        try {
            val ifaces = NetworkInterface.getNetworkInterfaces()
            while (ifaces != null && ifaces.hasMoreElements()) {
                val nif = ifaces.nextElement()
                if (!nif.isUp || nif.isLoopback) continue
                val addrs = nif.inetAddresses
                while (addrs.hasMoreElements()) {
                    val addr = addrs.nextElement()
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        if (ip.startsWith("192.168.") || ip.startsWith("172.20.") || ip.startsWith("10.")) {
                            bestIp = ip; break
                        } else if (bestIp == "127.0.0.1") bestIp = ip
                    }
                }
            }
        } catch (_: Exception) {}
        _localIpAddress.value = bestIp
        return bestIp
    }

    fun setNetworkMode(mode: DoudizhuNetworkMode) {
        if (_networkMode.value != mode) {
            leaveRoomAndResetLobby()
            _networkMode.value = mode
        }
    }
    fun setServerUrl(url: String) { _serverUrl.value = url }
    fun setDirectConnectIp(ip: String) { _directConnectIp.value = ip }
    fun setRoomCode(code: String) {
        val trimmed = code.trim()
        if (trimmed != activeConnectedRoomCode && (_isHostingRoom.value || _isServerConnected.value || _isScanningRooms.value || _connectedPeerNames.value.isNotEmpty())) {
            leaveRoomAndResetLobby()
        }
        _roomCode.value = code
    }
    fun setMyNickname(name: String) {
        _myNickname.value = name
        val idx = orderedRoomPeers.indexOfFirst { cleanPeerLabel(it.first) == cleanNickname() || it.first == myPeerKey() }
        if (idx >= 0) orderedRoomPeers[idx] = myPeerKey() to _myChar.value.charId
        rebuildLobbySeats()
        if (_phase.value == MahjongGamePhase.LOBBY) {
            if (_isServerConnected.value) sendJoinRequestPacket()
            else if (_isHostingRoom.value && isRoomAuthorityVal) broadcastFullStateSync()
        }
    }
    fun setMyCharacter(char: CharacterFilter) {
        _myChar.value = if (char == CharacterFilter.ALL) CharacterFilter.YUI else char
        val key = myPeerKey()
        val idx = orderedRoomPeers.indexOfFirst { it.first == key }
        if (idx >= 0) orderedRoomPeers[idx] = key to _myChar.value.charId
        rebuildLobbySeats()
        if (_phase.value == MahjongGamePhase.LOBBY) {
            if (_isServerConnected.value) sendJoinRequestPacket()
            else if (_isHostingRoom.value && isRoomAuthorityVal) broadcastFullStateSync()
        }
    }
    fun setTotalRounds(r: Int) { _totalRounds.value = r; syncRulesIfHost() }
    fun setBaseScore(b: Int) { _baseScore.value = b; syncRulesIfHost() }
    fun setTurnTimeLimit(t: Int) { _turnTimeLimit.value = t; _turnRemainingSeconds.value = t; syncRulesIfHost() }

    private fun syncRulesIfHost() {
        if (isRoomAuthorityVal && (_isHostingRoom.value || _isServerConnected.value)) broadcastFullStateSync()
    }

    private fun currentLang(): AppLanguage = try { audioMgr.language.value } catch (_: Throwable) { AppLanguage.ZH_HANS }

    private fun rebuildLobbySeats(forceRebuild: Boolean = false) {
        if (!forceRebuild && _phase.value != MahjongGamePhase.LOBBY && _phase.value != MahjongGamePhase.ROUND_OVER) return
        val lang = currentLang()
        val myKey = myPeerKey()
        val aiPool = CharacterFilter.fiveIndividuals.filter { it != _myChar.value }
        val prevScores = _seats.value.associate { it.peerDisplayName to it.score }
        val roster = if (orderedRoomPeers.isNotEmpty()) orderedRoomPeers.toList() else listOf(myKey to _myChar.value.charId)
        val winds = listOf("东", "南", "西", "北")
        val built = (0..3).map { slot ->
            val rp = roster.getOrNull(slot)
            if (rp != null) {
                val isMe = (rp.first == myKey || rp.first == _myNickname.value)
                val ch = if (isMe) _myChar.value else (CharacterFilter.fiveIndividuals.firstOrNull { it.charId == rp.second } ?: aiPool[slot % aiPool.size])
                val role = if (slot == 0) "👑房主" else "🎮${slot + 1}号"
                if (isMe) _mySeatIndex.value = slot
                MahjongSeat(slot, "$role ${cleanPeerLabel(rp.first)}", ch, false, rp.first, score = prevScores[rp.first] ?: 1000, isDealer = slot == 0, lastActionText = "${winds[slot]}家")
            } else {
                val aiCh = aiPool[slot % aiPool.size]
                val aiKey = "MJ_AI_$slot"
                MahjongSeat(slot, "${aiCh.displayName(lang)}(AI)", aiCh, true, aiKey, score = prevScores[aiKey] ?: 1000, isDealer = slot == 0, lastActionText = "${winds[slot]}家")
            }
        }
        _seats.value = built
    }

    // MARK: - Networking
    fun startHostingFaceToFaceRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号，未填写无法创建麻将房间！"; return }
        stopNetworking()
        activeConnectedRoomCode = code
        _roomCode.value = code
        _currentRound.value = 1
        val ip = refreshLocalIpAddress()
        _isHostingRoom.value = true
        _isRoomAuthority.value = true
        orderedRoomPeers.clear()
        orderedRoomPeers.add(myPeerKey() to _myChar.value.charId)
        _isScanningRooms.value = false
        _mySeatIndex.value = 0
        rebuildLobbySeats(forceRebuild = true)

        Thread {
            try {
                val srv = ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(tcpPort)) }
                tcpServerSocket = srv
                while (_isHostingRoom.value && !srv.isClosed) {
                    val sock = srv.accept()
                    attachRawLineChannel(sock.getInputStream(), sock.getOutputStream())
                }
            } catch (_: Exception) {}
        }.start()

        Thread {
            try {
                val ds = DatagramSocket().apply { broadcast = true }
                udpSocket = ds
                while (_isHostingRoom.value && !ds.isClosed) {
                    val payload = JSONObject().apply {
                        put("type", "kon_mj_room")
                        put("code", _roomCode.value)
                        put("host", cleanNickname())
                        put("char", _myChar.value.charId)
                        put("ip", refreshLocalIpAddress())
                        put("port", tcpPort)
                    }.toString().toByteArray(Charsets.UTF_8)
                    try { ds.send(DatagramPacket(payload, payload.size, InetAddress.getByName("255.255.255.255"), udpPort)) } catch (_: Exception) {}
                    Thread.sleep(1200)
                }
            } catch (_: Exception) {}
        }.start()

        try {
            val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
            nsdManager = nsd
            val info = NsdServiceInfo().apply {
                serviceName = "HTTMJ-${_roomCode.value}-${cleanNickname().take(8)}"
                serviceType = "_kon-mj._tcp."
                port = tcpPort
            }
            val regL = object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(NsdServiceInfo: NsdServiceInfo) {}
                override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                override fun onServiceUnregistered(arg0: NsdServiceInfo) {}
                override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            }
            nsdRegListener = regL
            nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, regL)
        } catch (_: Exception) {}

        _statusBanner.value = "🀄 麻将房间 [$code] 已创建！本机IP: $ip (最多4人)"
        audioMgr.playMascotVoice(_myChar.value)
    }

    fun startScanningFaceToFaceRooms() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号再扫描！"; return }
        stopNetworking()
        activeConnectedRoomCode = code
        _roomCode.value = code
        _isHostingRoom.value = false
        _isScanningRooms.value = true
        _discoveredRooms.value = emptyList()

        Thread {
            try {
                val ds = DatagramSocket(null).apply { reuseAddress = true; bind(InetSocketAddress(udpPort)); soTimeout = 1500 }
                udpSocket = ds
                val buf = ByteArray(2048)
                while (_isScanningRooms.value && !ds.isClosed) {
                    try {
                        val pkt = DatagramPacket(buf, buf.size)
                        ds.receive(pkt)
                        val json = JSONObject(String(pkt.data, 0, pkt.length, Charsets.UTF_8))
                        if (json.optString("type") == "kon_mj_room" && json.optString("code").trim() == _roomCode.value.trim()) {
                            val ip = json.optString("ip").ifBlank { pkt.address.hostAddress ?: "" }
                            val r = DiscoveredP2PRoom("$ip:$tcpPort", json.optString("code"), "${json.optString("host")} ($ip)", json.optInt("char", 1), ip, tcpPort)
                            mainHandler.post {
                                val cur = _discoveredRooms.value.toMutableList()
                                if (cur.none { it.id == r.id }) { cur.add(r); _discoveredRooms.value = cur }
                            }
                        }
                    } catch (_: SocketTimeoutException) {}
                }
            } catch (_: Exception) {}
        }.start()
        _statusBanner.value = "🔍 正在扫描房号 [$code] 的面对面麻将房间..."
    }

    fun connectDirectToHostIp() {
        val raw = _directConnectIp.value.trim()
        if (raw.isEmpty()) { _statusBanner.value = "⚠️ 请输入房主 IP"; return }
        val host = raw.substringBefore(":")
        val port = raw.substringAfter(":", "$tcpPort").toIntOrNull() ?: tcpPort
        joinDiscoveredRoom(DiscoveredP2PRoom("$host:$port", _roomCode.value, "IP直连($host)", 1, host, port))
    }

    fun joinDiscoveredRoom(room: DiscoveredP2PRoom) {
        val code = _roomCode.value.trim()
        if (code.isEmpty() || room.roomCode != code) { _statusBanner.value = "⚠️ 房号不匹配！"; return }
        _isScanningRooms.value = false
        _isRoomAuthority.value = false
        Thread {
            try {
                val sock = Socket()
                sock.connect(InetSocketAddress(room.hostAddress, room.port), 5000)
                clientSocket = sock
                attachRawLineChannel(sock.getInputStream(), sock.getOutputStream())
                sendJoinRequestPacket()
            } catch (e: Exception) {
                mainHandler.post { _statusBanner.value = "⚠️ 加入失败: ${e.message}" }
            }
        }.start()
    }

    private fun attachRawLineChannel(ins: InputStream, outs: OutputStream) {
        val ch = object : PeerChannel {
            override fun sendJson(raw: String) {
                synchronized(outs) { outs.write((raw + "\n").toByteArray(Charsets.UTF_8)); outs.flush() }
            }
            override fun close() {
                try { ins.close() } catch (_: Exception) {}
                try { outs.close() } catch (_: Exception) {}
            }
        }
        activeChannels.add(ch)
        Thread {
            try {
                val r = ins.bufferedReader(Charsets.UTF_8)
                while (true) {
                    val line = r.readLine() ?: break
                    if (line.isNotBlank()) mainHandler.post { handleReceivedPacketJson(line) }
                }
            } catch (_: Exception) {} finally { activeChannels.remove(ch) }
        }.start()
    }

    fun connectOnlineServerRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号！"; return }
        val url = _serverUrl.value.trim()
        stopNetworking()
        activeConnectedRoomCode = code
        _currentRound.value = 1
        orderedRoomPeers.clear()
        orderedRoomPeers.add(myPeerKey() to _myChar.value.charId)
        _isRoomAuthority.value = false
        _statusBanner.value = "🌐 正在连接麻将房间 [$code]..."
        webSocket = okHttpClient.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                mainHandler.post { _isServerConnected.value = true; sendJoinRequestPacket() }
            }
            override fun onMessage(ws: WebSocket, text: String) { mainHandler.post { handleReceivedPacketJson(text) } }
            override fun onMessage(ws: WebSocket, bytes: okio.ByteString) { mainHandler.post { handleReceivedPacketJson(bytes.utf8()) } }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) { mainHandler.post { _isServerConnected.value = false; _statusBanner.value = "⚠️ 服务器连接失败" } }
            override fun onClosed(ws: WebSocket, code: Int, reason: String) { mainHandler.post { _isServerConnected.value = false } }
        })
    }

    fun returnRoomToLobby() {
        val inRoom = _isHostingRoom.value || _isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || orderedRoomPeers.size > 1
        if (inRoom && isRoomAuthorityVal) {
            _phase.value = MahjongGamePhase.LOBBY
            rebuildLobbySeats(forceRebuild = true)
            _statusBanner.value = "⚙️ 房主已返回麻将大厅设置"
            broadcastFullStateSync()
        } else leaveRoomAndResetLobby()
    }

    fun leaveRoomAndResetLobby() {
        stopNetworking()
        _phase.value = MahjongGamePhase.LOBBY
        _currentRound.value = 1
        _mySeatIndex.value = 0
        _pendingClaim.value = null
        _drawnTileId.value = null
        _selectedTileId.value = null
        _winnerSeat.value = null
        _winReason.value = ""
        _wallCount.value = 0
        rebuildLobbySeats(forceRebuild = true)
        _statusBanner.value = "✨ 已退出麻将房间，返回大厅"
    }

    @SuppressLint("MissingPermission")
    fun stopNetworking() {
        if (activeConnectedRoomCode.isNotEmpty() && (_isHostingRoom.value || _isServerConnected.value || _connectedPeerNames.value.isNotEmpty())) {
            val raw = JSONObject().apply {
                put("kind", "leaveRoom"); put("roomCode", "MJ_$activeConnectedRoomCode")
                put("senderPeerName", myPeerKey()); put("senderCharId", _myChar.value.charId)
            }.toString()
            try { webSocket?.send(raw) } catch (_: Exception) {}
            Thread { activeChannels.forEach { try { it.sendJson(raw) } catch (_: Exception) {} } }.start()
        }
        activeConnectedRoomCode = ""
        peerCharMap.clear()
        orderedRoomPeers.clear()
        _isHostingRoom.value = false
        _isScanningRooms.value = false
        _isServerConnected.value = false
        _isRoomAuthority.value = true
        _mySeatIndex.value = 0
        _connectedPeerNames.value = emptyList()
        try { tcpServerSocket?.close() } catch (_: Exception) {}
        try { clientSocket?.close() } catch (_: Exception) {}
        try { udpSocket?.close() } catch (_: Exception) {}
        try { webSocket?.close(1000, "Leave") } catch (_: Exception) {}
        activeChannels.forEach { try { it.close() } catch (_: Exception) {} }
        activeChannels.clear()
        try { nsdRegListener?.let { nsdManager?.unregisterService(it) } } catch (_: Exception) {}
        try { nsdDiscListener?.let { nsdManager?.stopServiceDiscovery(it) } } catch (_: Exception) {}
        rebuildLobbySeats(forceRebuild = true)
    }

    private fun sendPacketJson(pkt: JSONObject) {
        val raw = pkt.toString()
        Thread {
            activeChannels.forEach { try { it.sendJson(raw) } catch (_: Exception) {} }
            try { webSocket?.send(raw) } catch (_: Exception) {}
        }.start()
    }

    private fun sendJoinRequestPacket() {
        sendPacketJson(JSONObject().apply {
            put("kind", "joinRequest")
            put("roomCode", wireRoomCode())
            put("senderPeerName", myPeerKey())
            put("senderCharId", _myChar.value.charId)
            put("maxPlayers", 4)
            put("gameType", "mahjong")
        })
    }

    private fun broadcastFullStateSync() {
        if (!isRoomAuthorityVal) return
        val myKey = myPeerKey()
        val pkt = JSONObject().apply {
            put("kind", "stateSync")
            put("roomCode", wireRoomCode())
            put("senderPeerName", myKey)
            put("senderCharId", _myChar.value.charId)
            put("maxPlayers", 4)
            put("gameType", "mahjong")
            put("hostPeerName", myKey)
            if (orderedRoomPeers.isNotEmpty()) {
                put("roomPeers", JSONArray().apply {
                    orderedRoomPeers.forEach { (n, cid) ->
                        put(JSONObject().apply { put("name", n); put("charId", cid); put("displayName", cleanPeerLabel(n)) })
                    }
                })
            }
            put("seats", JSONArray().apply { _seats.value.forEach { put(it.toJson()) } })
            put("wallCount", _wallCount.value)
            put("phase", _phase.value.wire)
            put("currentTurnSeat", _currentTurnSeat.value)
            _drawnTileId.value?.let { put("drawnTileId", it) }
            _pendingClaim.value?.let { put("pendingClaim", it.toJson()) }
            _winnerSeat.value?.let { put("winnerSeat", it) }
            put("winReason", _winReason.value)
            put("statusBanner", _statusBanner.value)
            put("totalRounds", _totalRounds.value)
            put("currentRound", _currentRound.value)
            put("baseScore", _baseScore.value)
            put("turnTimeLimit", _turnTimeLimit.value)
        }
        sendPacketJson(pkt)
    }

    private fun promoteAuthorityIfNeeded() {
        val prev = isRoomAuthorityVal
        val myKey = myPeerKey()
        val newAuth = when {
            orderedRoomPeers.isNotEmpty() -> orderedRoomPeers.first().first == myKey || orderedRoomPeers.first().first == _myNickname.value
            _seats.value.any { !it.isAI } -> _seats.value.indexOfFirst { !it.isAI } == _mySeatIndex.value
            else -> true
        }
        _isRoomAuthority.value = newAuth
        if (newAuth) {
            if (!prev) _statusBanner.value = "👑 原房主已离开，您已自动接任麻将房主！"
            if (_phase.value == MahjongGamePhase.PLAYING || _phase.value == MahjongGamePhase.CLAIM_WINDOW) {
                broadcastFullStateSync(); scheduleAIActionIfNeeded(); scheduleAIClaimIfNeeded()
            } else if (_phase.value == MahjongGamePhase.LOBBY) {
                rebuildLobbySeats(forceRebuild = true); broadcastFullStateSync()
            }
        }
    }

    private fun handleReceivedPacketJson(raw: String) {
        try {
            val obj = JSONObject(raw)
            val wCode = wireRoomCode()
            if (wCode.isEmpty() || obj.optString("roomCode").trim() != wCode) return
            val kind = obj.optString("kind")
            val senderName = obj.optString("senderPeerName", "玩家")
            val senderCid = obj.optInt("senderCharId", 1)
            val myKey = myPeerKey()

            when (kind) {
                "roomFull" -> {
                    stopNetworking()
                    _phase.value = MahjongGamePhase.LOBBY
                    _statusBanner.value = obj.optString("statusBanner").ifBlank { "⚠️ 麻将房间已满 (4/4人)" }
                }
                "roomRoster" -> {
                    val rArr = obj.optJSONArray("roomPeers") ?: return
                    if (rArr.length() == 0) return
                    orderedRoomPeers.clear()
                    for (i in 0 until rArr.length()) {
                        val it = rArr.getJSONObject(i)
                        orderedRoomPeers.add(it.optString("name") to it.optInt("charId", 1))
                    }
                    _connectedPeerNames.value = orderedRoomPeers.map { it.first }.filter { it != myKey && it != _myNickname.value }
                    val prev = isRoomAuthorityVal
                    val newAuth = orderedRoomPeers.first().first == myKey || orderedRoomPeers.first().first == _myNickname.value
                    _isRoomAuthority.value = newAuth
                    if (_phase.value == MahjongGamePhase.LOBBY || _phase.value == MahjongGamePhase.ROUND_OVER) {
                        if (_phase.value == MahjongGamePhase.LOBBY) rebuildLobbySeats(forceRebuild = true)
                        if (newAuth && (!prev || orderedRoomPeers.size > 1)) broadcastFullStateSync()
                    } else {
                        val activeSet = orderedRoomPeers.map { it.first }.toSet()
                        var changed = false
                        _seats.value = _seats.value.map { s ->
                            if (!s.isAI && !activeSet.contains(s.peerDisplayName)) {
                                changed = true; s.copy(isAI = true, name = "${s.character.displayName(currentLang())}(AI接管)")
                            } else s
                        }
                        if (changed || (!prev && newAuth)) promoteAuthorityIfNeeded()
                    }
                }
                "leaveRoom" -> {
                    orderedRoomPeers.removeAll { it.first == senderName }
                    _connectedPeerNames.value = _connectedPeerNames.value.filter { it != senderName }
                    if (_phase.value == MahjongGamePhase.LOBBY || _phase.value == MahjongGamePhase.ROUND_OVER) {
                        promoteAuthorityIfNeeded()
                        if (_phase.value == MahjongGamePhase.LOBBY) rebuildLobbySeats(forceRebuild = true)
                    } else {
                        _seats.value = _seats.value.map { s ->
                            if (s.peerDisplayName == senderName) s.copy(isAI = true, name = "${s.character.displayName(currentLang())}(AI接管)") else s
                        }
                        promoteAuthorityIfNeeded()
                    }
                }
                "joinRequest" -> {
                    if (senderName == myKey) return
                    if (_isHostingRoom.value && isRoomAuthorityVal) {
                        val already = orderedRoomPeers.any { it.first == senderName }
                        if (!already && orderedRoomPeers.size >= 4) {
                            sendPacketJson(JSONObject().apply {
                                put("kind", "roomFull"); put("roomCode", wCode); put("senderPeerName", myKey); put("senderCharId", _myChar.value.charId)
                                put("statusBanner", "⚠️ 麻将房间已满 (4/4人)，无法加入！")
                            })
                            return
                        }
                        if (!already) orderedRoomPeers.add(senderName to senderCid)
                        rebuildLobbySeats(forceRebuild = true)
                        sendPacketJson(JSONObject().apply {
                            put("kind", "roomRoster"); put("roomCode", wCode); put("senderPeerName", myKey); put("senderCharId", _myChar.value.charId)
                            put("hostPeerName", myKey)
                            put("roomPeers", JSONArray().apply {
                                orderedRoomPeers.forEach { (n, cid) ->
                                    put(JSONObject().apply { put("name", n); put("charId", cid); put("displayName", cleanPeerLabel(n)) })
                                }
                            })
                        })
                        broadcastFullStateSync()
                    }
                }
                "stateSync" -> {
                    if (senderName == myKey) return
                    val rArr = obj.optJSONArray("roomPeers")
                    if (rArr != null && rArr.length() > 0) {
                        orderedRoomPeers.clear()
                        for (i in 0 until rArr.length()) {
                            val it = rArr.getJSONObject(i)
                            orderedRoomPeers.add(it.optString("name") to it.optInt("charId", 1))
                        }
                        _connectedPeerNames.value = orderedRoomPeers.map { it.first }.filter { it != myKey && it != _myNickname.value }
                    }
                    val hName = obj.optString("hostPeerName")
                    _isRoomAuthority.value = hName.isNotEmpty() && (hName == myKey || hName == _myNickname.value)
                    val sArr = obj.optJSONArray("seats")
                    if (sArr != null) {
                        val parsed = (0 until sArr.length()).map { MahjongSeat.fromJson(sArr.getJSONObject(it)) }
                        _seats.value = parsed
                        val idx = parsed.indexOfFirst { it.peerDisplayName == myKey || cleanPeerLabel(it.peerDisplayName) == cleanNickname() }
                        if (idx >= 0) _mySeatIndex.value = idx
                    }
                    _wallCount.value = obj.optInt("wallCount", _wallCount.value)
                    _phase.value = MahjongGamePhase.values().firstOrNull { it.wire == obj.optString("phase") } ?: _phase.value
                    _currentTurnSeat.value = obj.optInt("currentTurnSeat", _currentTurnSeat.value)
                    _drawnTileId.value = if (obj.has("drawnTileId")) obj.optString("drawnTileId") else null
                    _pendingClaim.value = MahjongPendingClaim.fromJson(obj.optJSONObject("pendingClaim"))
                    _winnerSeat.value = if (obj.has("winnerSeat") && !obj.isNull("winnerSeat")) obj.optInt("winnerSeat") else null
                    _winReason.value = obj.optString("winReason", _winReason.value)
                    _statusBanner.value = obj.optString("statusBanner", _statusBanner.value)
                    if (obj.has("totalRounds")) _totalRounds.value = obj.optInt("totalRounds")
                    if (obj.has("currentRound")) _currentRound.value = obj.optInt("currentRound")
                    if (obj.has("baseScore")) _baseScore.value = obj.optInt("baseScore")
                    if (obj.has("turnTimeLimit")) {
                        val t = obj.optInt("turnTimeLimit")
                        _turnTimeLimit.value = t; _turnRemainingSeconds.value = t
                    }
                }
                "discardAction" -> {
                    if (isRoomAuthorityVal) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == senderName || cleanPeerLabel(it.peerDisplayName) == cleanPeerLabel(senderName) }
                        if (idx >= 0) executeDiscard(obj.optString("tileId"), idx)
                    }
                }
                "claimAction" -> {
                    if (isRoomAuthorityVal) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == senderName || cleanPeerLabel(it.peerDisplayName) == cleanPeerLabel(senderName) }
                        if (idx >= 0) handleClaimResponse(obj.optString("actionType"), idx)
                    }
                }
                "selfAction" -> {
                    if (isRoomAuthorityVal) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == senderName || cleanPeerLabel(it.peerDisplayName) == cleanPeerLabel(senderName) }
                        if (idx >= 0) {
                            val act = obj.optString("actionType")
                            if (act == "selfHu" && canDeclareSelfHu(idx)) executeWin(idx, null, null, true)
                            else if (act == "selfKong") {
                                val tile = _seats.value[idx].hand.firstOrNull { it.id == obj.optString("tileId") }
                                if (tile != null) executeSelfKong(tile, idx)
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Mahjong packet error: ${e.message}")
        }
    }

    // MARK: - Game Play
    fun startNewGame() {
        val inRoom = _isHostingRoom.value || _isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || orderedRoomPeers.size > 1
        if (inRoom && !isRoomAuthorityVal) { _statusBanner.value = "⏳ 只有1号房主可以开启下一局"; return }
        if (!inRoom) { _isRoomAuthority.value = true; _mySeatIndex.value = 0 }
        if (_phase.value == MahjongGamePhase.ROUND_OVER) {
            if (_totalRounds.value > 0 && _currentRound.value >= _totalRounds.value) {
                _currentRound.value = 1
                _seats.value = _seats.value.map { it.copy(score = 1000) }
            } else _currentRound.value += 1
        }
        rebuildLobbySeats(forceRebuild = true)

        val deck = mutableListOf<MahjongTile>()
        for (s in listOf(MahjongSuit.WAN, MahjongSuit.TIAO, MahjongSuit.TONG)) {
            for (r in 1..9) for (c in 0 until 4) deck.add(MahjongTile("${s.code}_${r}_$c", s, r))
        }
        for (r in 1..6) for (c in 0 until 4) deck.add(MahjongTile("H_${r}_$c", MahjongSuit.HONOR, r))
        for (c in 0 until 4) deck.add(MahjongTile("Z_0_$c", MahjongSuit.ZHONG, 0))
        deck.shuffle()

        val dealerIdx = (_currentRound.value - 1) % 4
        var ptr = 0
        val dealtSeats = _seats.value.mapIndexed { idx, s ->
            val cnt = if (idx == dealerIdx) 14 else 13
            val h = MahjongEvaluator.sortHand(deck.subList(ptr, ptr + cnt))
            ptr += cnt
            s.copy(hand = h, melds = emptyList(), discards = emptyList(), isDealer = idx == dealerIdx, lastActionText = "")
        }
        wall.clear()
        wall.addAll(deck.subList(ptr, deck.size))
        _wallCount.value = wall.size
        _seats.value = dealtSeats
        _selectedTileId.value = null
        _drawnTileId.value = dealtSeats[dealerIdx].hand.lastOrNull()?.id
        _pendingClaim.value = null
        _winnerSeat.value = null
        _winReason.value = ""
        _phase.value = MahjongGamePhase.PLAYING
        _currentTurnSeat.value = dealerIdx
        _turnRemainingSeconds.value = if (_turnTimeLimit.value > 0) _turnTimeLimit.value else 20
        _statusBanner.value = "🀄 第 ${_currentRound.value} 局开始！[${dealtSeats[dealerIdx].name}] 坐庄先出牌 (红中=赖子)"
        audioMgr.playMascotVoice(dealtSeats[dealerIdx].character)
        broadcastFullStateSync()
        scheduleAIActionIfNeeded()
    }

    fun selectOrDiscardTile(tile: MahjongTile) {
        if (_phase.value != MahjongGamePhase.PLAYING || _currentTurnSeat.value != _mySeatIndex.value) return
        if (_selectedTileId.value == tile.id) _selectedTileId.value = null else _selectedTileId.value = tile.id
    }

    fun discardTile(tile: MahjongTile) {
        if (_phase.value != MahjongGamePhase.PLAYING || _currentTurnSeat.value != _mySeatIndex.value) return
        if (!isRoomAuthorityVal) {
            sendPacketJson(JSONObject().apply {
                put("kind", "discardAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerKey()); put("senderCharId", _myChar.value.charId); put("tileId", tile.id)
            })
            _selectedTileId.value = null
            return
        }
        executeDiscard(tile.id, _mySeatIndex.value)
        _selectedTileId.value = null
    }

    fun canDeclareSelfHu(seatIdx: Int = _mySeatIndex.value): Boolean {
        if (_phase.value != MahjongGamePhase.PLAYING || _currentTurnSeat.value != seatIdx) return false
        val s = _seats.value.getOrNull(seatIdx) ?: return false
        return MahjongEvaluator.canWin(s.hand, s.melds.size)
    }

    fun selfKongOptions(seatIdx: Int = _mySeatIndex.value): List<MahjongTile> {
        if (_phase.value != MahjongGamePhase.PLAYING || _currentTurnSeat.value != seatIdx) return emptyList()
        val s = _seats.value.getOrNull(seatIdx) ?: return emptyList()
        val res = mutableListOf<MahjongTile>()
        s.hand.filter { !it.isLaizi }.groupBy { "${it.suit.code}_${it.rank}" }.values.forEach { if (it.size == 4) res.add(it[0]) }
        s.melds.filter { it.kind == MahjongMeldKind.PONG }.forEach { m ->
            s.hand.firstOrNull { it.suit == m.tile.suit && it.rank == m.tile.rank }?.let { res.add(it) }
        }
        return res
    }

    fun declareSelfHu() {
        if (!canDeclareSelfHu(_mySeatIndex.value)) return
        if (!isRoomAuthorityVal) {
            sendPacketJson(JSONObject().apply {
                put("kind", "selfAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerKey()); put("senderCharId", _myChar.value.charId); put("actionType", "selfHu")
            })
            return
        }
        executeWin(_mySeatIndex.value, null, null, true)
    }

    fun declareSelfKong(tile: MahjongTile) {
        if (_phase.value != MahjongGamePhase.PLAYING || _currentTurnSeat.value != _mySeatIndex.value) return
        if (!isRoomAuthorityVal) {
            sendPacketJson(JSONObject().apply {
                put("kind", "selfAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerKey()); put("senderCharId", _myChar.value.charId); put("tileId", tile.id); put("actionType", "selfKong")
            })
            return
        }
        executeSelfKong(tile, _mySeatIndex.value)
    }

    fun sendClaimResponse(action: String) {
        if (_phase.value != MahjongGamePhase.CLAIM_WINDOW) return
        if (!isRoomAuthorityVal) {
            sendPacketJson(JSONObject().apply {
                put("kind", "claimAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerKey()); put("senderCharId", _myChar.value.charId); put("actionType", action)
            })
            return
        }
        handleClaimResponse(action, _mySeatIndex.value)
    }

    private fun handleTimeout() {
        if (_phase.value == MahjongGamePhase.CLAIM_WINDOW) resolveClaimAsAllPass()
        else if (_phase.value == MahjongGamePhase.PLAYING) {
            val actor = _currentTurnSeat.value
            val s = _seats.value.getOrNull(actor) ?: return
            if (s.hand.isNotEmpty()) executeDiscard(MahjongEvaluator.bestAIDiscard(s.hand).id, actor)
        }
    }

    private fun executeSelfKong(tile: MahjongTile, actor: Int) {
        val cur = _seats.value.toMutableList()
        val s = cur.getOrNull(actor) ?: return
        val inHand = s.hand.filter { it.suit == tile.suit && it.rank == tile.rank }
        val newSeats = if (inHand.size == 4) {
            val rem = s.hand.filterNot { it.suit == tile.suit && it.rank == tile.rank }
            val melds = s.melds + MahjongMeld(UUID.randomUUID().toString(), MahjongMeldKind.CONCEALED_KONG, tile)
            cur.mapIndexed { idx, seat ->
                val sc = seat.score + if (idx == actor) _baseScore.value * 3 else -_baseScore.value
                if (idx == actor) seat.copy(hand = rem, melds = melds, score = sc, lastActionText = "暗杠 ${tile.fullName}") else seat.copy(score = sc)
            }
        } else {
            val rem = s.hand.toMutableList()
            val hIdx = rem.indexOfFirst { it.suit == tile.suit && it.rank == tile.rank }
            if (hIdx >= 0) rem.removeAt(hIdx)
            val melds = s.melds.map { if (it.kind == MahjongMeldKind.PONG && it.tile.suit == tile.suit && it.tile.rank == tile.rank) it.copy(kind = MahjongMeldKind.EXPOSED_KONG) else it }
            cur.mapIndexed { idx, seat ->
                val sc = seat.score + if (idx == actor) _baseScore.value * 3 else -_baseScore.value
                if (idx == actor) seat.copy(hand = rem, melds = melds, score = sc, lastActionText = "补杠 ${tile.fullName}") else seat.copy(score = sc)
            }
        }
        _seats.value = newSeats
        audioMgr.playMascotVoice(s.character)
        drawTileForSeat(actor, "🔥 [${s.name}] 杠牌补摸")
    }

    private fun executeDiscard(tileId: String, actor: Int) {
        if (_phase.value != MahjongGamePhase.PLAYING || _currentTurnSeat.value != actor) return
        val cur = _seats.value.toMutableList()
        val s = cur.getOrNull(actor) ?: return
        val tile = s.hand.firstOrNull { it.id == tileId } ?: return
        val newHand = MahjongEvaluator.sortHand(s.hand.filterNot { it.id == tileId })
        cur[actor] = s.copy(hand = newHand, discards = s.discards + tile, lastActionText = "打出 ${tile.fullName}")
        _seats.value = cur
        _drawnTileId.value = null
        audioMgr.playMascotVoice(s.character)

        val huSeats = mutableListOf<Int>()
        val kongSeats = mutableListOf<Int>()
        val pongSeats = mutableListOf<Int>()
        if (!tile.isLaizi) {
            for (off in 1..3) {
                val sIdx = (actor + off) % 4
                val cand = cur[sIdx]
                if (MahjongEvaluator.canWin(cand.hand, cand.melds.size, tile)) huSeats.add(sIdx)
                val same = cand.hand.count { it.suit == tile.suit && it.rank == tile.rank }
                if (same >= 3) kongSeats.add(sIdx)
                if (same >= 2) pongSeats.add(sIdx)
            }
        }
        if (huSeats.isNotEmpty() || kongSeats.isNotEmpty() || pongSeats.isNotEmpty()) {
            _pendingClaim.value = MahjongPendingClaim(actor, tile, huSeats, kongSeats, pongSeats, emptyList())
            _phase.value = MahjongGamePhase.CLAIM_WINDOW
            _turnRemainingSeconds.value = minOf(12, if (_turnTimeLimit.value > 0) _turnTimeLimit.value else 12)
            _statusBanner.value = "⚡ [${s.name}] 打出 ${tile.fullName}！等待响应 胡/杠/碰"
            broadcastFullStateSync()
            scheduleAIClaimIfNeeded()
        } else {
            drawTileForSeat((actor + 1) % 4)
        }
    }

    private fun handleClaimResponse(action: String, seatIdx: Int) {
        val cl = _pendingClaim.value ?: return
        if (action == "hu" && cl.eligibleHuSeats.contains(seatIdx)) {
            val cur = _seats.value.toMutableList()
            cur[cl.discarderSeat] = cur[cl.discarderSeat].copy(discards = cur[cl.discarderSeat].discards.dropLast(1))
            _seats.value = cur
            executeWin(seatIdx, cl.discarderSeat, cl.tile, false)
            return
        }
        if (action == "kong" && cl.eligibleKongSeats.contains(seatIdx)) {
            if (cl.eligibleHuSeats.any { !cl.passedSeats.contains(it) && it != seatIdx }) return
            val cur = _seats.value.toMutableList()
            cur[cl.discarderSeat] = cur[cl.discarderSeat].copy(discards = cur[cl.discarderSeat].discards.dropLast(1), score = cur[cl.discarderSeat].score - _baseScore.value * 3)
            val s = cur[seatIdx]
            cur[seatIdx] = s.copy(
                hand = s.hand.filterNot { it.suit == cl.tile.suit && it.rank == cl.tile.rank },
                melds = s.melds + MahjongMeld(UUID.randomUUID().toString(), MahjongMeldKind.EXPOSED_KONG, cl.tile),
                score = s.score + _baseScore.value * 3,
                lastActionText = "明杠 ${cl.tile.fullName}"
            )
            _seats.value = cur
            _pendingClaim.value = null
            _phase.value = MahjongGamePhase.PLAYING
            audioMgr.playMascotVoice(s.character)
            drawTileForSeat(seatIdx, "🔥 [${s.name}] 明杠 ${cl.tile.fullName} 补牌")
            return
        }
        if (action == "pong" && cl.eligiblePongSeats.contains(seatIdx)) {
            if (cl.eligibleHuSeats.any { !cl.passedSeats.contains(it) && it != seatIdx }) return
            val cur = _seats.value.toMutableList()
            cur[cl.discarderSeat] = cur[cl.discarderSeat].copy(discards = cur[cl.discarderSeat].discards.dropLast(1))
            val s = cur[seatIdx]
            var remCnt = 0
            val newH = s.hand.filterNot {
                if (remCnt < 2 && it.suit == cl.tile.suit && it.rank == cl.tile.rank) { remCnt++; true } else false
            }
            cur[seatIdx] = s.copy(hand = newH, melds = s.melds + MahjongMeld(UUID.randomUUID().toString(), MahjongMeldKind.PONG, cl.tile), lastActionText = "碰 ${cl.tile.fullName}")
            _seats.value = cur
            _pendingClaim.value = null
            _phase.value = MahjongGamePhase.PLAYING
            _currentTurnSeat.value = seatIdx
            _turnRemainingSeconds.value = if (_turnTimeLimit.value > 0) _turnTimeLimit.value else 20
            _statusBanner.value = "💥 [${s.name}] 碰了 ${cl.tile.fullName}！请出牌"
            audioMgr.playMascotVoice(s.character)
            broadcastFullStateSync()
            scheduleAIActionIfNeeded()
            return
        }
        if (action == "pass") {
            val newPassed = (cl.passedSeats + seatIdx).distinct()
            val updated = cl.copy(passedSeats = newPassed)
            _pendingClaim.value = updated
            val rem = (cl.eligibleHuSeats + cl.eligibleKongSeats + cl.eligiblePongSeats).toSet() - newPassed.toSet()
            if (rem.isEmpty()) resolveClaimAsAllPass() else { broadcastFullStateSync(); scheduleAIClaimIfNeeded() }
        }
    }

    private fun resolveClaimAsAllPass() {
        val cl = _pendingClaim.value ?: return
        _pendingClaim.value = null
        drawTileForSeat((cl.discarderSeat + 1) % 4)
    }

    private fun drawTileForSeat(seatIdx: Int, bannerPrefix: String? = null) {
        if (wall.isEmpty()) {
            _phase.value = MahjongGamePhase.ROUND_OVER
            _winnerSeat.value = null
            _winReason.value = "荒庄流局（牌墙已摸完）"
            _statusBanner.value = "🌊 本局流局，无人胡牌！"
            broadcastFullStateSync()
            return
        }
        val drawn = wall.removeAt(0)
        _wallCount.value = wall.size
        val cur = _seats.value.toMutableList()
        val s = cur[seatIdx]
        cur[seatIdx] = s.copy(hand = MahjongEvaluator.sortHand(s.hand + drawn))
        _seats.value = cur
        _drawnTileId.value = drawn.id
        _phase.value = MahjongGamePhase.PLAYING
        _currentTurnSeat.value = seatIdx
        _turnRemainingSeconds.value = if (_turnTimeLimit.value > 0) _turnTimeLimit.value else 20
        _statusBanner.value = bannerPrefix ?: "🀄 轮到 [${s.name}] 摸牌出牌 (余 ${wall.size} 张)"
        broadcastFullStateSync()
        scheduleAIActionIfNeeded()
    }

    private fun executeWin(winner: Int, loser: Int?, winningTile: MahjongTile?, isSelfDrawn: Boolean) {
        val cur = _seats.value.toMutableList()
        if (winningTile != null) {
            cur[winner] = cur[winner].copy(hand = MahjongEvaluator.sortHand(cur[winner].hand + winningTile))
        }
        val laizi = cur[winner].hand.count { it.isLaizi }
        val mult = (if (isSelfDrawn) 2 else 1) * (if (laizi >= 4) 2 else 1)
        val pts = _baseScore.value * mult
        val settled = cur.mapIndexed { idx, s ->
            val delta = when {
                isSelfDrawn -> if (idx == winner) pts * 3 else -pts
                idx == winner -> pts * 2
                idx == loser -> -pts * 2
                else -> 0
            }
            if (idx == winner) s.copy(score = s.score + delta, lastActionText = "🎉 胡牌!") else s.copy(score = s.score + delta)
        }
        _seats.value = settled
        _pendingClaim.value = null
        _winnerSeat.value = winner
        _winReason.value = if (isSelfDrawn) "自摸胡牌 (x$mult)" else "点炮胡牌 (x$mult)"
        _phase.value = MahjongGamePhase.ROUND_OVER
        _statusBanner.value = "🎉 恭喜 [${settled[winner].name}] ${_winReason.value}！"
        audioMgr.triggerBirthdaySpecialVoice()
        broadcastFullStateSync()
    }

    private fun scheduleAIActionIfNeeded() {
        if (!isRoomAuthorityVal || _phase.value != MahjongGamePhase.PLAYING) return
        val turn = _currentTurnSeat.value
        val s = _seats.value.getOrNull(turn) ?: return
        if (!s.isAI) return
        mainHandler.postDelayed({
            if (!isRoomAuthorityVal || _phase.value != MahjongGamePhase.PLAYING || _currentTurnSeat.value != turn) return@postDelayed
            if (canDeclareSelfHu(turn)) { executeWin(turn, null, null, true); return@postDelayed }
            val k = selfKongOptions(turn).firstOrNull()
            if (k != null) { executeSelfKong(k, turn); return@postDelayed }
            val d = MahjongEvaluator.bestAIDiscard(_seats.value[turn].hand)
            executeDiscard(d.id, turn)
        }, 850L)
    }

    private fun scheduleAIClaimIfNeeded() {
        if (!isRoomAuthorityVal || _phase.value != MahjongGamePhase.CLAIM_WINDOW) return
        val cl = _pendingClaim.value ?: return
        val humanPending = (cl.eligibleHuSeats + cl.eligibleKongSeats + cl.eligiblePongSeats).toSet() - cl.passedSeats.toSet()
        if (humanPending.any { _seats.value.getOrNull(it)?.isAI == false }) return
        mainHandler.postDelayed({
            val c = _pendingClaim.value ?: return@postDelayed
            if (!isRoomAuthorityVal || _phase.value != MahjongGamePhase.CLAIM_WINDOW) return@postDelayed
            val hu = c.eligibleHuSeats.firstOrNull { _seats.value.getOrNull(it)?.isAI == true && !c.passedSeats.contains(it) }
            val kong = c.eligibleKongSeats.firstOrNull { _seats.value.getOrNull(it)?.isAI == true && !c.passedSeats.contains(it) }
            val pong = c.eligiblePongSeats.firstOrNull { _seats.value.getOrNull(it)?.isAI == true && !c.passedSeats.contains(it) }
            when {
                hu != null -> handleClaimResponse("hu", hu)
                kong != null -> handleClaimResponse("kong", kong)
                pong != null -> handleClaimResponse("pong", pong)
                else -> resolveClaimAsAllPass()
            }
        }, 750L)
    }
}
