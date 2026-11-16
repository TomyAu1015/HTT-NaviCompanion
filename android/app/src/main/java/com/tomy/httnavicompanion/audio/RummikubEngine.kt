package com.tomy.httnavicompanion.audio

import android.content.Context
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.random.Random

enum class RmkColor(val code: String, val labelZh: String) {
    RED("R", "红"), BLUE("B", "蓝"), YELLOW("Y", "黄"), BLACK("K", "黑"), JOKER("J", "鬼");
    companion object {
        fun fromCode(c: String): RmkColor = values().firstOrNull { it.code == c } ?: RED
    }
}

data class RmkTile(val id: String, val color: RmkColor, val number: Int) {
    val isJoker: Boolean get() = color == RmkColor.JOKER
}

data class RmkMeld(val id: String, val tiles: List<RmkTile>)

data class RmkSeat(
    val id: Int,
    val name: String,
    val characterId: Int,
    val isAI: Boolean,
    val peerDisplayName: String,
    val hand: List<RmkTile> = emptyList(),
    val hasBrokenIce: Boolean = false,
    val score: Int = 1000
)

enum class RmkGamePhase { LOBBY, PLAYING, ROUND_OVER }

object RmkEvaluator {
    fun evaluateMeld(tiles: List<RmkTile>): Int? {
        if (tiles.size < 3) return null
        val jokers = tiles.filter { it.isJoker }
        val normals = tiles.filter { !it.isJoker }
        if (normals.isEmpty()) return null

        // Group: same number, distinct colors, max 4
        if (tiles.size <= 4) {
            val num = normals[0].number
            val sameNum = normals.all { it.number == num }
            val cols = normals.map { it.color }.toSet()
            if (sameNum && cols.size == normals.size) return num * tiles.size
        }

        // Run: same color, strictly consecutive 1..13
        val col = normals[0].color
        if (normals.all { it.color == col }) {
            val nums = normals.map { it.number }.sorted()
            if (nums.toSet().size != nums.size) return null
            val span = nums.last() - nums.first() + 1
            val gaps = span - nums.size
            if (gaps <= jokers.size && tiles.size <= 13) {
                var remJ = jokers.size - gaps
                var low = nums.first()
                var high = nums.last()
                while (remJ > 0 && high < 13) { high++; remJ-- }
                while (remJ > 0 && low > 1) { low--; remJ-- }
                if (high - low + 1 == tiles.size && low >= 1 && high <= 13) {
                    return (low + high) * tiles.size / 2
                }
            }
        }
        return null
    }

    fun findBestMeld(hand: List<RmkTile>): List<RmkTile>? {
        val normals = hand.filter { !it.isJoker }
        val jokers = hand.filter { it.isJoker }
        var best: List<RmkTile>? = null
        var bestPts = 0

        for ((_, grp) in normals.groupBy { it.number }) {
            val uniq = ArrayList<RmkTile>()
            val seen = HashSet<RmkColor>()
            for (t in grp) if (seen.add(t.color)) uniq.add(t)
            if (uniq.size >= 3) {
                val pts = evaluateMeld(uniq) ?: 0
                if (pts > bestPts) { bestPts = pts; best = uniq }
            } else if (uniq.size == 2 && jokers.isNotEmpty()) {
                val cand = uniq + jokers[0]
                val pts = evaluateMeld(cand) ?: 0
                if (pts > bestPts) { bestPts = pts; best = cand }
            }
        }

        for ((_, grp) in normals.groupBy { it.color }) {
            val uniq = ArrayList<RmkTile>()
            val seen = HashSet<Int>()
            for (t in grp.sortedBy { it.number }) if (seen.add(t.number)) uniq.add(t)
            val cur = ArrayList<RmkTile>()
            for (t in uniq) {
                if (cur.isEmpty() || t.number == cur.last().number + 1) {
                    cur.add(t)
                } else {
                    if (cur.size >= 3) {
                        val pts = evaluateMeld(cur) ?: 0
                        if (pts > bestPts) { bestPts = pts; best = cur.toList() }
                    }
                    cur.clear(); cur.add(t)
                }
            }
            if (cur.size >= 3) {
                val pts = evaluateMeld(cur) ?: 0
                if (pts > bestPts) { bestPts = pts; best = cur.toList() }
            }
        }
        return best
    }
}

class RummikubEngine(
    private val context: Context,
    private val audioManager: AudioPlayerManager
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val prefs = context.getSharedPreferences("HTT_Rmk", Context.MODE_PRIVATE)
    private val httpClient = OkHttpClient()

    private val _phase = MutableStateFlow(RmkGamePhase.LOBBY)
    val phase: StateFlow<RmkGamePhase> = _phase.asStateFlow()

    private val _seats = MutableStateFlow<List<RmkSeat>>(emptyList())
    val seats: StateFlow<List<RmkSeat>> = _seats.asStateFlow()

    private val _tableMelds = MutableStateFlow<List<RmkMeld>>(emptyList())
    val tableMelds: StateFlow<List<RmkMeld>> = _tableMelds.asStateFlow()

    private val _poolCount = MutableStateFlow(0)
    val poolCount: StateFlow<Int> = _poolCount.asStateFlow()

    private val _mySeatIndex = MutableStateFlow(0)
    val mySeatIndex: StateFlow<Int> = _mySeatIndex.asStateFlow()

    private val _currentTurnSeat = MutableStateFlow(0)
    val currentTurnSeat: StateFlow<Int> = _currentTurnSeat.asStateFlow()

    private val _selectedTileIds = MutableStateFlow<Set<String>>(emptySet())
    val selectedTileIds: StateFlow<Set<String>> = _selectedTileIds.asStateFlow()

    private val _turnRemainingSeconds = MutableStateFlow(60)
    val turnRemainingSeconds: StateFlow<Int> = _turnRemainingSeconds.asStateFlow()

    private val _statusBanner = MutableStateFlow("欢迎来到拉密数字牌 (106张 · 30分破冰 · 60秒限时)")
    val statusBanner: StateFlow<String> = _statusBanner.asStateFlow()

    private val _sortByColor = MutableStateFlow(false)
    val sortByColor: StateFlow<Boolean> = _sortByColor.asStateFlow()

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

    private val _isEditingTable = MutableStateFlow(false)
    val isEditingTable: StateFlow<Boolean> = _isEditingTable.asStateFlow()

    private val _workingMelds = MutableStateFlow<List<RmkMeld>>(emptyList())
    val workingMelds: StateFlow<List<RmkMeld>> = _workingMelds.asStateFlow()

    private val _workingHand = MutableStateFlow<List<RmkTile>>(emptyList())
    val workingHand: StateFlow<List<RmkTile>> = _workingHand.asStateFlow()

    private var snapshotMelds: List<RmkMeld> = emptyList()
    private var snapshotHand: List<RmkTile> = emptyList()
    private val pool = ArrayList<RmkTile>()
    private var myPeerName: String = ""
    private var orderedRoomPeers = mutableListOf<Triple<String, Int, String>>()
    private var webSocket: WebSocket? = null
    private var aiRunnable: Runnable? = null
    private var timerRunnable: Runnable? = null

    init {
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        rebuildLobbySeats()
    }

    private fun cleanNick(): String = _myNickname.value.trim().ifEmpty { "轻音车友" }
    private fun cleanPeer(raw: String): String = raw.substringBeforeLast("#").trim().ifEmpty { raw }
    fun wireRoomCode(): String = _roomCode.value.trim().let { if (it.isEmpty()) "" else "RMK_$it" }

    fun setNickname(n: String) { _myNickname.value = n; prefs.edit().putString("nick", n).apply(); rebuildLobbySeats() }
    fun setCharacter(c: CharacterFilter) { _myCharacter.value = c; rebuildLobbySeats() }
    fun setRoomCode(c: String) { _roomCode.value = c }
    fun setServerUrl(u: String) { _serverUrl.value = u }

    private fun build106Deck(): List<RmkTile> {
        val deck = ArrayList<RmkTile>(106)
        for (copy in 1..2) {
            for (col in listOf(RmkColor.RED, RmkColor.BLUE, RmkColor.YELLOW, RmkColor.BLACK)) {
                for (num in 1..13) deck.add(RmkTile("${col.code}_${num}_$copy", col, num))
            }
        }
        deck.add(RmkTile("J_1", RmkColor.JOKER, 0))
        deck.add(RmkTile("J_2", RmkColor.JOKER, 0))
        deck.shuffle()
        return deck
    }

    private fun sortHand(tiles: List<RmkTile>): List<RmkTile> = tiles.sortedWith(Comparator { a, b ->
        if (a.isJoker != b.isJoker) return@Comparator if (a.isJoker) 1 else -1
        if (_sortByColor.value) {
            if (a.color != b.color) a.color.code.compareTo(b.color.code) else a.number - b.number
        } else {
            if (a.number != b.number) a.number - b.number else a.color.code.compareTo(b.color.code)
        }
    })

    fun toggleSortMode() {
        _sortByColor.value = !_sortByColor.value
        val curSeats = _seats.value.toMutableList()
        val idx = _mySeatIndex.value
        if (idx < curSeats.size) {
            curSeats[idx] = curSeats[idx].copy(hand = sortHand(curSeats[idx].hand))
            _seats.value = curSeats
            if (_isEditingTable.value) _workingHand.value = sortHand(_workingHand.value)
        }
    }

    fun rebuildLobbySeats() {
        if (orderedRoomPeers.isEmpty()) orderedRoomPeers.add(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        else {
            val idx = orderedRoomPeers.indexOfFirst { it.first == myPeerName }
            if (idx >= 0) orderedRoomPeers[idx] = Triple(myPeerName, _myCharacter.value.charId, cleanNick())
        }
        _isRoomAuthority.value = (orderedRoomPeers.first().first == myPeerName)
        val used = HashSet<Int>()
        val list = ArrayList<RmkSeat>(4)
        val old = _seats.value
        for (i in 0 until 4) {
            val ps = old.getOrNull(i)?.score ?: 1000
            if (i < orderedRoomPeers.size) {
                val rp = orderedRoomPeers[i]
                if (rp.first == myPeerName) _mySeatIndex.value = i
                used.add(rp.second)
                val tag = if (i == 0) "👑房主 " else "${i + 1}号 "
                list.add(RmkSeat(i, tag + cleanPeer(rp.third), rp.second, false, rp.first, emptyList(), false, ps))
            } else {
                val ac = CharacterFilter.fiveIndividuals.firstOrNull { !used.contains(it.charId) }?.charId ?: ((i % 5) + 1)
                used.add(ac)
                val an = CharacterFilter.fiveIndividuals.firstOrNull { it.charId == ac }?.displayName(audioManager.language.value) ?: "轻音AI"
                list.add(RmkSeat(i, "$an (AI)", ac, true, "AI_$i", emptyList(), false, ps))
            }
        }
        _seats.value = list
    }

    fun connectOnlineServerRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号！"; return }
        stopNetworking()
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        orderedRoomPeers = mutableListOf(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        _isRoomAuthority.value = false
        _isServerConnected.value = true
        val req = Request.Builder().url(_serverUrl.value.trim()).build()
        webSocket = httpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) { mainHandler.post { sendJoinRequest() } }
            override fun onMessage(ws: WebSocket, text: String) { mainHandler.post { handleIncomingJson(text) } }
            override fun onMessage(ws: WebSocket, bytes: ByteString) { mainHandler.post { handleIncomingJson(bytes.utf8()) } }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) { mainHandler.post { _isServerConnected.value = false } }
        })
    }

    private fun sendJoinRequest() {
        val wc = wireRoomCode()
        if (wc.isEmpty()) return
        webSocket?.send(JSONObject().apply {
            put("kind", "joinRequest"); put("roomCode", wc)
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", 4); put("gameType", "rummikub")
        }.toString())
        _statusBanner.value = "✅ 已连接拉密数字牌房间 [${_roomCode.value}]"
    }

    fun leaveRoomAndResetLobby() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        val wc = wireRoomCode()
        if (_isServerConnected.value && wc.isNotEmpty()) {
            webSocket?.send(JSONObject().apply {
                put("kind", "leaveRoom"); put("roomCode", wc)
                put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            }.toString())
        }
        stopNetworking()
        _phase.value = RmkGamePhase.LOBBY
        _currentRound.value = 1
        rebuildLobbySeats()
        _statusBanner.value = "已退出拉密数字牌房间"
    }

    private fun stopNetworking() {
        webSocket?.close(1000, "leave"); webSocket = null
        _isServerConnected.value = false; _connectedPeerNames.value = emptyList(); orderedRoomPeers.clear()
    }

    private fun tileToJson(t: RmkTile) = JSONObject().apply { put("id", t.id); put("color", t.color.code); put("number", t.number) }
    private fun tileFromJson(o: JSONObject) = RmkTile(o.optString("id"), RmkColor.fromCode(o.optString("color", "R")), o.optInt("number", 1))

    private fun broadcastFullState() {
        if (!_isServerConnected.value || !_isRoomAuthority.value || wireRoomCode().isEmpty()) return
        val peersArr = JSONArray()
        orderedRoomPeers.forEach { rp -> peersArr.put(JSONObject().apply { put("name", rp.first); put("charId", rp.second); put("displayName", rp.third) }) }
        val seatsArr = JSONArray()
        _seats.value.forEach { s ->
            val hArr = JSONArray()
            s.hand.forEach { hArr.put(tileToJson(it)) }
            seatsArr.put(JSONObject().apply {
                put("id", s.id); put("name", s.name); put("characterId", s.characterId); put("isAI", s.isAI)
                put("peerDisplayName", s.peerDisplayName); put("hand", hArr); put("hasBrokenIce", s.hasBrokenIce); put("score", s.score)
            })
        }
        val meldsArr = JSONArray()
        _tableMelds.value.forEach { m ->
            val tArr = JSONArray()
            m.tiles.forEach { tArr.put(tileToJson(it)) }
            meldsArr.put(JSONObject().apply { put("id", m.id); put("tiles", tArr) })
        }
        webSocket?.send(JSONObject().apply {
            put("kind", "stateSync"); put("roomCode", wireRoomCode())
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("hostPeerName", myPeerName); put("roomPeers", peersArr); put("seats", seatsArr); put("tableMelds", meldsArr)
            put("poolCount", _poolCount.value)
            put("phase", when (_phase.value) { RmkGamePhase.LOBBY -> "lobby"; RmkGamePhase.PLAYING -> "playing"; RmkGamePhase.ROUND_OVER -> "roundOver" })
            put("currentTurnSeat", _currentTurnSeat.value); put("currentRound", _currentRound.value); put("statusBanner", _statusBanner.value)
        }.toString())
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
                        orderedRoomPeers = list; _connectedPeerNames.value = list.map { it.first }.filter { it != myPeerName }
                        _isRoomAuthority.value = (list.first().first == myPeerName)
                        if (_phase.value == RmkGamePhase.LOBBY) rebuildLobbySeats()
                    }
                }
                "joinRequest" -> {
                    if (sender == myPeerName) return
                    if (_isRoomAuthority.value && orderedRoomPeers.none { it.first == sender } && orderedRoomPeers.size < 4) {
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
                    if (_phase.value == RmkGamePhase.LOBBY) rebuildLobbySeats()
                }
                "stateSync" -> {
                    if (sender == myPeerName) return
                    _isRoomAuthority.value = (obj.optString("hostPeerName") == myPeerName)
                    val sArr = obj.optJSONArray("seats")
                    if (sArr != null) {
                        val list = ArrayList<RmkSeat>()
                        for (i in 0 until sArr.length()) {
                            val so = sArr.getJSONObject(i)
                            val hArr = so.optJSONArray("hand")
                            val hand = ArrayList<RmkTile>()
                            if (hArr != null) for (k in 0 until hArr.length()) hand.add(tileFromJson(hArr.getJSONObject(k)))
                            val pd = so.optString("peerDisplayName", "")
                            if (pd == myPeerName) _mySeatIndex.value = i
                            list.add(RmkSeat(so.optInt("id", i), so.optString("name", ""), so.optInt("characterId", 1), so.optBoolean("isAI", false), pd, hand, so.optBoolean("hasBrokenIce", false), so.optInt("score", 1000)))
                        }
                        _seats.value = list
                    }
                    val mArr = obj.optJSONArray("tableMelds")
                    if (mArr != null) {
                        val ms = ArrayList<RmkMeld>()
                        for (i in 0 until mArr.length()) {
                            val mo = mArr.getJSONObject(i)
                            val tArr = mo.optJSONArray("tiles")
                            val ts = ArrayList<RmkTile>()
                            if (tArr != null) for (k in 0 until tArr.length()) ts.add(tileFromJson(tArr.getJSONObject(k)))
                            ms.add(RmkMeld(mo.optString("id"), ts))
                        }
                        _tableMelds.value = ms
                    }
                    _poolCount.value = obj.optInt("poolCount", _poolCount.value)
                    _phase.value = when (obj.optString("phase")) {
                        "playing" -> RmkGamePhase.PLAYING
                        "roundOver" -> RmkGamePhase.ROUND_OVER
                        else -> RmkGamePhase.LOBBY
                    }
                    val ct = obj.optInt("currentTurnSeat", _currentTurnSeat.value)
                    if (ct != _currentTurnSeat.value) resetWorkspaceForNewTurn()
                    _currentTurnSeat.value = ct
                    _currentRound.value = obj.optInt("currentRound", _currentRound.value)
                    obj.optString("statusBanner", "").takeIf { it.isNotEmpty() }?.let { _statusBanner.value = it }
                    if (_phase.value == RmkGamePhase.PLAYING) startTurnTimer()
                }
                "drawTileAction" -> {
                    if (_isRoomAuthority.value) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == sender }
                        if (idx == _currentTurnSeat.value) executeDrawAndAdvance(idx, "摸牌过")
                    }
                }
                "commitTurnAction" -> {
                    if (_isRoomAuthority.value) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == sender }
                        if (idx == _currentTurnSeat.value) {
                            val mArr = obj.optJSONArray("tableMelds") ?: return
                            val ms = ArrayList<RmkMeld>()
                            for (i in 0 until mArr.length()) {
                                val mo = mArr.getJSONObject(i)
                                val tArr = mo.optJSONArray("tiles") ?: continue
                                val ts = (0 until tArr.length()).map { tileFromJson(tArr.getJSONObject(it)) }
                                ms.add(RmkMeld(mo.optString("id"), ts))
                            }
                            val pArr = obj.optJSONArray("committedHandIds") ?: return
                            val ids = (0 until pArr.length()).map { pArr.getString(it) }
                            executeCommitTurn(idx, ms, ids)
                        }
                    }
                }
            }
        } catch (_: Exception) {}
    }

    fun startNewRound() {
        if (_isServerConnected.value && !_isRoomAuthority.value) return
        rebuildLobbySeats()
        pool.clear()
        pool.addAll(build106Deck())
        val list = _seats.value.toMutableList()
        for (i in 0 until 4) {
            val dealt = pool.take(14)
            repeat(14) { pool.removeAt(0) }
            list[i] = list[i].copy(hand = sortHand(dealt), hasBrokenIce = false)
        }
        _seats.value = list
        _poolCount.value = pool.size
        _tableMelds.value = emptyList()
        _currentTurnSeat.value = (_currentRound.value - 1) % 4
        _phase.value = RmkGamePhase.PLAYING
        resetWorkspaceForNewTurn()
        _statusBanner.value = "🔢 第 ${_currentRound.value} 局发牌完成！轮到 [${list[_currentTurnSeat.value].name}] 出牌 (≥30分破冰)"
        startTurnTimer()
        broadcastFullState()
        scheduleAIIfNeeded()
    }

    private fun startTurnTimer() {
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        _turnRemainingSeconds.value = 60
        val tick = object : Runnable {
            override fun run() {
                if (_phase.value != RmkGamePhase.PLAYING) return
                if (_turnRemainingSeconds.value > 0) {
                    _turnRemainingSeconds.value -= 1
                    mainHandler.postDelayed(this, 1000L)
                } else if (!_isServerConnected.value || _isRoomAuthority.value) {
                    restoreWorkspaceSnapshot()
                    executeDrawAndAdvance(_currentTurnSeat.value, "⏰ 60秒超时复原并罚抽1张")
                }
            }
        }
        timerRunnable = tick
        mainHandler.postDelayed(tick, 1000L)
    }

    private fun resetWorkspaceForNewTurn() {
        _selectedTileIds.value = emptySet()
        _isEditingTable.value = false
        val myHand = _seats.value.getOrNull(_mySeatIndex.value)?.hand ?: emptyList()
        snapshotHand = myHand
        _workingHand.value = myHand
        snapshotMelds = _tableMelds.value
        _workingMelds.value = _tableMelds.value
    }

    private fun beginOrEnsureWorkspace() {
        if (!_isEditingTable.value) {
            snapshotHand = _seats.value.getOrNull(_mySeatIndex.value)?.hand ?: emptyList()
            _workingHand.value = snapshotHand
            snapshotMelds = _tableMelds.value
            _workingMelds.value = snapshotMelds
            _isEditingTable.value = true
        }
    }

    fun restoreWorkspaceSnapshot() {
        if (_isEditingTable.value) {
            _workingHand.value = snapshotHand
            _workingMelds.value = snapshotMelds
            _selectedTileIds.value = emptySet()
            _isEditingTable.value = false
            _statusBanner.value = "↩️ 已复原到本回合初始牌面"
        }
    }

    fun toggleSelectTile(id: String) {
        val cur = _selectedTileIds.value.toMutableSet()
        if (!cur.add(id)) cur.remove(id)
        _selectedTileIds.value = cur
    }

    fun placeSelectedAsNewMeld() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING || _selectedTileIds.value.isEmpty()) return
        beginOrEnsureWorkspace()
        val sel = _selectedTileIds.value
        val picked = _workingHand.value.filter { sel.contains(it.id) }
        if (RmkEvaluator.evaluateMeld(picked) == null) {
            _statusBanner.value = "⚠️ 所选牌未能组成有效顺组或群组 (需≥3张)"
            return
        }
        _workingHand.value = _workingHand.value.filterNot { sel.contains(it.id) }
        _workingMelds.value = _workingMelds.value + RmkMeld(UUID.randomUUID().toString(), picked)
        _selectedTileIds.value = emptySet()
        _statusBanner.value = "✅ 已暂放牌组到桌面（点击【确认出牌】完成回合）"
    }

    fun addSelectedToTableMeld(meldId: String) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING || _selectedTileIds.value.isEmpty()) return
        if (!_seats.value[_mySeatIndex.value].hasBrokenIce) {
            _statusBanner.value = "⚠️ 尚未破冰！首次出牌只能出自己牌架的牌且 ≥30 分"
            return
        }
        beginOrEnsureWorkspace()
        val ms = _workingMelds.value.toMutableList()
        val idx = ms.indexOfFirst { it.id == meldId }
        if (idx < 0) return
        val sel = _selectedTileIds.value
        val picked = _workingHand.value.filter { sel.contains(it.id) }
        val combined = ms[idx].tiles + picked
        if (RmkEvaluator.evaluateMeld(combined) == null) {
            _statusBanner.value = "⚠️ 添牌后不符合群组或顺组规则"
            return
        }
        _workingHand.value = _workingHand.value.filterNot { sel.contains(it.id) }
        ms[idx] = ms[idx].copy(tiles = combined.sortedBy { it.number })
        _workingMelds.value = ms
        _selectedTileIds.value = emptySet()
        _statusBanner.value = "✅ 已并入桌面牌组（点击【确认出牌】完成回合）"
    }

    fun splitMeldToWorkspace(meldId: String) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        if (!_seats.value[_mySeatIndex.value].hasBrokenIce) {
            _statusBanner.value = "⚠️ 尚未破冰，不能拆解桌面牌组！"
            return
        }
        beginOrEnsureWorkspace()
        val ms = _workingMelds.value.toMutableList()
        val idx = ms.indexOfFirst { it.id == meldId }
        if (idx < 0 || ms[idx].tiles.size < 4) {
            _statusBanner.value = "⚠️ 只有 ≥4 张的牌组才可拆出端牌重组"
            return
        }
        val popped = ms[idx].tiles.last()
        ms[idx] = ms[idx].copy(tiles = ms[idx].tiles.dropLast(1))
        _workingMelds.value = ms
        _workingHand.value = _workingHand.value + popped
        _selectedTileIds.value = _selectedTileIds.value + popped.id
        _statusBanner.value = "🔄 已拆出 1 张端牌，请配合手牌重组后【确认出牌】"
    }

    fun smartHint() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        beginOrEnsureWorkspace()
        val best = RmkEvaluator.findBestMeld(_workingHand.value)
        if (best != null) {
            _selectedTileIds.value = best.map { it.id }.toSet()
            _statusBanner.value = "💡 已选中推荐牌组（点【放上桌面】即可出牌）"
        } else {
            _statusBanner.value = "💡 暂无直出牌组，可拆解桌面或摸牌过"
        }
    }

    fun commitMyTurn() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        beginOrEnsureWorkspace()
        val remIds = _workingHand.value.map { it.id }.toSet()
        val playedIds = snapshotHand.map { it.id }.filter { !remIds.contains(it) }
        if (playedIds.isEmpty()) { _statusBanner.value = "⚠️ 尚未打出牌架上的牌"; return }
        for (m in _workingMelds.value) {
            if (RmkEvaluator.evaluateMeld(m.tiles) == null) {
                _statusBanner.value = "⚠️ 桌面存在无效牌组，请继续重组或点【复原】"
                return
            }
        }
        if (!_seats.value[_mySeatIndex.value].hasBrokenIce) {
            if (_workingMelds.value.size <= snapshotMelds.size) {
                _statusBanner.value = "⚠️ 首次破冰只能出自己牌架的牌组！"
                return
            }
            var icePts = 0
            for (i in snapshotMelds.size until _workingMelds.value.size) {
                icePts += RmkEvaluator.evaluateMeld(_workingMelds.value[i].tiles) ?: 0
            }
            if (icePts < 30) {
                _statusBanner.value = "⚠️ 破冰总分仅 $icePts 分，必须 ≥30 分！"
                return
            }
        }
        if (_isServerConnected.value && !_isRoomAuthority.value) {
            val mArr = JSONArray()
            _workingMelds.value.forEach { m ->
                val tArr = JSONArray(); m.tiles.forEach { tArr.put(tileToJson(it)) }
                mArr.put(JSONObject().apply { put("id", m.id); put("tiles", tArr) })
            }
            val pArr = JSONArray().apply { playedIds.forEach { put(it) } }
            webSocket?.send(JSONObject().apply {
                put("kind", "commitTurnAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                put("tableMelds", mArr); put("committedHandIds", pArr)
            }.toString())
            _isEditingTable.value = false
            return
        }
        executeCommitTurn(_mySeatIndex.value, _workingMelds.value, playedIds)
    }

    fun drawTilePassTapped() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        restoreWorkspaceSnapshot()
        if (_isServerConnected.value && !_isRoomAuthority.value) {
            webSocket?.send(JSONObject().apply {
                put("kind", "drawTileAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            }.toString())
            return
        }
        executeDrawAndAdvance(_mySeatIndex.value, "摸牌结束回合")
    }

    private fun executeCommitTurn(seatIdx: Int, newMelds: List<RmkMeld>, playedIds: List<String>) {
        _tableMelds.value = newMelds
        val list = _seats.value.toMutableList()
        val pSet = playedIds.toSet()
        list[seatIdx] = list[seatIdx].copy(hand = list[seatIdx].hand.filterNot { pSet.contains(it.id) }, hasBrokenIce = true)
        _seats.value = list
        _isEditingTable.value = false
        if (list[seatIdx].hand.isEmpty()) { finishRound(seatIdx); return }
        _currentTurnSeat.value = (seatIdx + 1) % 4
        resetWorkspaceForNewTurn()
        _turnRemainingSeconds.value = 60
        _statusBanner.value = "✅ [${list[seatIdx].name}] 出牌 ${playedIds.size} 张！轮到 [${list[_currentTurnSeat.value].name}]"
        broadcastFullState()
        scheduleAIIfNeeded()
    }

    private fun executeDrawAndAdvance(seatIdx: Int, reason: String) {
        val list = _seats.value.toMutableList()
        if (pool.isNotEmpty()) {
            val t = pool.removeAt(0)
            list[seatIdx] = list[seatIdx].copy(hand = sortHand(list[seatIdx].hand + t))
            _seats.value = list
            _poolCount.value = pool.size
        }
        _isEditingTable.value = false
        _currentTurnSeat.value = (seatIdx + 1) % 4
        resetWorkspaceForNewTurn()
        _turnRemainingSeconds.value = 60
        _statusBanner.value = "[${list[seatIdx].name}] $reason · 轮到 [${list[_currentTurnSeat.value].name}]"
        broadcastFullState()
        scheduleAIIfNeeded()
    }

    private fun finishRound(winner: Int) {
        _phase.value = RmkGamePhase.ROUND_OVER
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        val list = _seats.value.toMutableList()
        var gain = 0
        for (i in 0 until 4) {
            if (i == winner) continue
            val pen = list[i].hand.sumOf { if (it.isJoker) 30 else it.number }
            list[i] = list[i].copy(score = list[i].score - pen)
            gain += pen
        }
        list[winner] = list[winner].copy(score = list[winner].score + gain)
        _seats.value = list
        _statusBanner.value = "🏆 [${list[winner].name}] 清空牌架获胜！(+$gain 分)"
        broadcastFullState()
    }

    private fun scheduleAIIfNeeded() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        if (_isServerConnected.value && !_isRoomAuthority.value) return
        val sIdx = _currentTurnSeat.value
        if (_phase.value != RmkGamePhase.PLAYING || _seats.value.getOrNull(sIdx)?.isAI != true) return
        val r = Runnable {
            val seat = _seats.value.getOrNull(sIdx) ?: return@Runnable
            val best = RmkEvaluator.findBestMeld(seat.hand)
            val pts = best?.let { RmkEvaluator.evaluateMeld(it) } ?: 0
            if (best != null && (seat.hasBrokenIce || pts >= 30)) {
                val nm = _tableMelds.value + RmkMeld(UUID.randomUUID().toString(), best)
                executeCommitTurn(sIdx, nm, best.map { it.id })
            } else {
                executeDrawAndAdvance(sIdx, "从共用牌堆摸1张牌")
            }
        }
        aiRunnable = r
        mainHandler.postDelayed(r, 1500L)
    }

    fun nextRound() { _currentRound.value += 1; startNewRound() }
}
