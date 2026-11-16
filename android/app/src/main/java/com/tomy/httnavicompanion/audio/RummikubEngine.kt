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
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.Collections
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.zip.ZipInputStream
import kotlin.random.Random

enum class RmkColor(val code: String, val labelZh: String) {
    RED("R", "红"), BLUE("B", "蓝"), YELLOW("Y", "黄"), BLACK("K", "绿"), JOKER("J", "百搭");
    companion object {
        fun fromCode(c: String): RmkColor = values().firstOrNull { it.code == c } ?: RED
    }
}

data class RmkTile(val id: String, val color: RmkColor, val number: Int) {
    val isJoker: Boolean get() = color == RmkColor.JOKER

    val assetFileName: String
        get() {
            if (isJoker) return "rmk_joker.png"
            val cIdx = when (color) {
                RmkColor.RED -> 1
                RmkColor.BLUE -> 2
                RmkColor.YELLOW -> 3
                RmkColor.BLACK -> 4
                RmkColor.JOKER -> 5
            }
            val n = number.coerceIn(1, 13)
            return "rmk_${cIdx}_${n}.png"
        }
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
enum class RmkNetworkMode { LOCAL_LAN, ONLINE_SERVER }

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

    fun organizeHandIntoGroups(hand: List<RmkTile>, preferRuns: Boolean): Pair<List<List<RmkTile>>, List<RmkTile>> {
        val remaining = hand.toMutableList()
        val melds = ArrayList<List<RmkTile>>()

        fun extractRuns() {
            var changed = true
            while (changed) {
                changed = false
                val byCol = remaining.filter { !it.isJoker }.groupBy { it.color }
                for (col in listOf(RmkColor.RED, RmkColor.BLUE, RmkColor.YELLOW, RmkColor.BLACK)) {
                    val grp = byCol[col] ?: continue
                    val uniq = ArrayList<RmkTile>()
                    val seen = HashSet<Int>()
                    for (t in grp.sortedBy { it.number }) if (seen.add(t.number)) uniq.add(t)
                    val run = ArrayList<RmkTile>()
                    for (t in uniq) {
                        if (run.isEmpty() || t.number == run.last().number + 1) run.add(t)
                        else {
                            if (run.size >= 3) break
                            run.clear(); run.add(t)
                        }
                    }
                    if (run.size >= 3) {
                        val copy = run.toList()
                        melds.add(copy)
                        val ids = copy.map { it.id }.toSet()
                        remaining.removeAll { ids.contains(it.id) }
                        changed = true
                        break
                    }
                }
            }
        }

        fun extractGroups() {
            var changed = true
            while (changed) {
                changed = false
                val byNum = remaining.filter { !it.isJoker }.groupBy { it.number }
                for (num in 13 downTo 1) {
                    val grp = byNum[num] ?: continue
                    val uniq = ArrayList<RmkTile>()
                    val seen = HashSet<RmkColor>()
                    for (t in grp) if (seen.add(t.color)) uniq.add(t)
                    if (uniq.size >= 3) {
                        val pick = uniq.take(4)
                        melds.add(pick)
                        val ids = pick.map { it.id }.toSet()
                        remaining.removeAll { ids.contains(it.id) }
                        changed = true
                        break
                    }
                }
            }
        }

        if (preferRuns) { extractRuns(); extractGroups() }
        else { extractGroups(); extractRuns() }

        while (true) {
            val jIdx = remaining.indexOfFirst { it.isJoker }
            if (jIdx < 0) break
            val joker = remaining[jIdx]
            var paired: List<RmkTile>? = null
            if (preferRuns) {
                val byCol = remaining.filter { !it.isJoker }.groupBy { it.color }
                for (col in listOf(RmkColor.RED, RmkColor.BLUE, RmkColor.YELLOW, RmkColor.BLACK)) {
                    val s = (byCol[col] ?: emptyList()).sortedBy { it.number }
                    if (s.size >= 2) {
                        for (i in 0 until s.size - 1) {
                            if (s[i + 1].number - s[i].number in 1..2) {
                                paired = listOf(s[i], s[i + 1], joker)
                                break
                            }
                        }
                    }
                    if (paired != null) break
                }
            }
            if (paired == null) {
                val byNum = remaining.filter { !it.isJoker }.groupBy { it.number }
                for (num in 13 downTo 1) {
                    val uniq = ArrayList<RmkTile>()
                    val seen = HashSet<RmkColor>()
                    for (t in (byNum[num] ?: emptyList())) if (seen.add(t.color)) uniq.add(t)
                    if (uniq.size == 2) { paired = listOf(uniq[0], uniq[1], joker); break }
                }
            }
            if (paired != null) {
                melds.add(paired)
                val ids = paired.map { it.id }.toSet()
                remaining.removeAll { ids.contains(it.id) }
            } else break
        }

        val sortedLeft = remaining.sortedWith(Comparator { a, b ->
            if (a.isJoker != b.isJoker) return@Comparator if (a.isJoker) 1 else -1
            if (preferRuns) {
                if (a.color != b.color) a.color.code.compareTo(b.color.code) else a.number - b.number
            } else {
                if (a.number != b.number) a.number - b.number else a.color.code.compareTo(b.color.code)
            }
        })
        return melds to sortedLeft
    }
}

class RummikubEngine(
    private val context: Context,
    private val audioManager: AudioPlayerManager
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val prefs = context.getSharedPreferences("HTT_Rmk", Context.MODE_PRIVATE)
    private val httpClient = OkHttpClient()
    private val rmkBitmaps = HashMap<String, Bitmap>()

    private val _phase = MutableStateFlow(RmkGamePhase.LOBBY)
    val phase: StateFlow<RmkGamePhase> = _phase.asStateFlow()

    private val _roomPlayerCount = MutableStateFlow(4)
    val roomPlayerCount: StateFlow<Int> = _roomPlayerCount.asStateFlow()

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

    private val _statusBanner = MutableStateFlow("欢迎来到轻音拉密数字牌 (2~4人自由开房 · 30分破冰 · 60秒限时)")
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

    private val _networkMode = MutableStateFlow(RmkNetworkMode.ONLINE_SERVER)
    val networkMode: StateFlow<RmkNetworkMode> = _networkMode.asStateFlow()

    private val _isHostingRoom = MutableStateFlow(false)
    val isHostingRoom: StateFlow<Boolean> = _isHostingRoom.asStateFlow()

    private val _isScanningRooms = MutableStateFlow(false)
    val isScanningRooms: StateFlow<Boolean> = _isScanningRooms.asStateFlow()

    private val _discoveredRooms = MutableStateFlow<List<DiscoveredP2PRoom>>(emptyList())
    val discoveredRooms: StateFlow<List<DiscoveredP2PRoom>> = _discoveredRooms.asStateFlow()

    private val _directConnectIp = MutableStateFlow("")
    val directConnectIp: StateFlow<String> = _directConnectIp.asStateFlow()

    private val _localIpAddress = MutableStateFlow("192.168.43.1")
    val localIpAddress: StateFlow<String> = _localIpAddress.asStateFlow()

    private val _isServerConnected = MutableStateFlow(false)
    val isServerConnected: StateFlow<Boolean> = _isServerConnected.asStateFlow()

    private val _isRoomAuthority = MutableStateFlow(true)
    val isRoomAuthority: StateFlow<Boolean> = _isRoomAuthority.asStateFlow()

    private val tcpPort = 19193
    private val udpPort = 19194
    private var tcpServerSocket: ServerSocket? = null
    private var udpSocket: DatagramSocket? = null
    private val lanWriters = CopyOnWriteArrayList<BufferedWriter>()

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

    private val _rackCols = MutableStateFlow(10)
    val rackCols: StateFlow<Int> = _rackCols.asStateFlow()

    private val _rackSlots = MutableStateFlow<List<RmkTile?>>(List(20) { null })
    val rackSlots: StateFlow<List<RmkTile?>> = _rackSlots.asStateFlow()

    private val _liftedSlotIndex = MutableStateFlow<Int?>(null)
    val liftedSlotIndex: StateFlow<Int?> = _liftedSlotIndex.asStateFlow()

    private val _dealingVisibleCount = MutableStateFlow(99)
    val dealingVisibleCount: StateFlow<Int> = _dealingVisibleCount.asStateFlow()

    private val _isDealingAnimation = MutableStateFlow(false)
    val isDealingAnimation: StateFlow<Boolean> = _isDealingAnimation.asStateFlow()

    private val _isDrawingAnimation = MutableStateFlow(false)
    val isDrawingAnimation: StateFlow<Boolean> = _isDrawingAnimation.asStateFlow()

    private val _drawingAnimatedTile = MutableStateFlow<RmkTile?>(null)
    val drawingAnimatedTile: StateFlow<RmkTile?> = _drawingAnimatedTile.asStateFlow()

    private var snapshotMelds: List<RmkMeld> = emptyList()
    private var snapshotHand: List<RmkTile> = emptyList()
    private var snapshotRackSlots: List<RmkTile?> = emptyList()
    private val pool = ArrayList<RmkTile>()
    private var myPeerName: String = ""
    private var orderedRoomPeers = mutableListOf<Triple<String, Int, String>>()
    private var webSocket: WebSocket? = null
    private var aiRunnable: Runnable? = null
    private var timerRunnable: Runnable? = null

    init {
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        loadRmkAssets()
        rebuildLobbySeats()
    }

    private fun loadRmkAssets() {
        Thread {
            try {
                context.assets.open("doudizhu_cards.zip").use { fis ->
                    ZipInputStream(fis).use { zis ->
                        var entry = zis.nextEntry
                        while (entry != null) {
                            val name = entry.name.substringAfterLast("/")
                            if (name.startsWith("rmk_") || name == "icon_rummikub.png") {
                                val bytes = zis.readBytes()
                                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bmp ->
                                    synchronized(rmkBitmaps) { rmkBitmaps[name] = bmp }
                                }
                            }
                            zis.closeEntry()
                            entry = zis.nextEntry
                        }
                    }
                }
            } catch (_: Exception) {}
        }.start()
    }

    fun getAssetBitmap(name: String): Bitmap? = synchronized(rmkBitmaps) { rmkBitmaps[name] }

    private fun cleanNick(): String = _myNickname.value.trim().ifEmpty { "轻音车友" }
    private fun cleanPeer(raw: String): String = raw.substringBeforeLast("#").trim().ifEmpty { raw }
    fun wireRoomCode(): String = _roomCode.value.trim().let { if (it.isEmpty()) "" else "RMK_$it" }

    fun setNickname(n: String) { _myNickname.value = n; prefs.edit().putString("nick", n).apply(); rebuildLobbySeats() }
    fun setCharacter(c: CharacterFilter) { _myCharacter.value = c; rebuildLobbySeats() }
    fun setNetworkMode(m: RmkNetworkMode) { _networkMode.value = m }
    fun setDirectConnectIp(ip: String) { _directConnectIp.value = ip }
    fun setRoomCode(c: String) { _roomCode.value = c }
    fun setServerUrl(u: String) { _serverUrl.value = u }
    fun setRoomPlayerCount(cnt: Int) {
        val c = cnt.coerceIn(2, 4)
        if (_roomPlayerCount.value != c && _phase.value == RmkGamePhase.LOBBY) {
            _roomPlayerCount.value = c
            rebuildLobbySeats()
            if ((_isServerConnected.value || _isHostingRoom.value || lanWriters.isNotEmpty()) && _isRoomAuthority.value) {
                broadcastRoster()
                broadcastFullState()
            }
        }
    }

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

    fun syncRackFromHand(tiles: List<RmkTile>, preserveExistingPositions: Boolean = true) {
        val minCols = maxOf(10, (tiles.size + 1) / 2 + 2)
        if (!preserveExistingPositions || _rackSlots.value.isEmpty()) {
            _rackCols.value = minCols
            val next = MutableList<RmkTile?>(minCols * 2) { null }
            val topCnt = minOf(minCols, (tiles.size + 1) / 2)
            for (i in tiles.indices) {
                if (i < topCnt) next[i] = tiles[i]
                else {
                    val bIdx = minCols + (i - topCnt)
                    if (bIdx < next.size) next[bIdx] = tiles[i]
                }
            }
            _rackSlots.value = next
            return
        }
        val handMap = tiles.associateBy { it.id }
        val placedIds = HashSet<String>()
        var updated = _rackSlots.value.map { slot ->
            val keep = slot?.let { handMap[it.id] }
            if (keep != null) placedIds.add(keep.id)
            keep
        }.toMutableList()

        val missing = tiles.filterNot { placedIds.contains(it.id) }
        for (m in missing) {
            var emptyIdx = updated.indexOfFirst { it == null }
            if (emptyIdx < 0) {
                updated = extendRackColumnsInternal(2, updated)
                emptyIdx = updated.indexOfFirst { it == null }
            }
            if (emptyIdx >= 0) updated[emptyIdx] = m
        }
        if (updated.count { it == null } < 2) {
            updated = extendRackColumnsInternal(2, updated)
        }
        _rackSlots.value = updated
    }

    private fun extendRackColumnsInternal(extraCols: Int, cur: MutableList<RmkTile?>): MutableList<RmkTile?> {
        val oldCols = maxOf(1, cur.size / 2)
        val newCols = oldCols + extraCols
        val next = MutableList<RmkTile?>(newCols * 2) { null }
        for (c in 0 until oldCols) {
            next[c] = cur[c]
            next[newCols + c] = cur[oldCols + c]
        }
        _rackCols.value = newCols
        return next
    }

    fun setLiftedSlot(idx: Int?) { _liftedSlotIndex.value = idx }

    fun moveRackSlot(srcIdx: Int, dstIdx: Int) {
        val cur = _rackSlots.value.toMutableList()
        if (srcIdx !in cur.indices || dstIdx !in cur.indices || srcIdx == dstIdx) return
        val tmp = cur[dstIdx]
        cur[dstIdx] = cur[srcIdx]
        cur[srcIdx] = tmp
        _liftedSlotIndex.value = null
        val cols = _rackCols.value
        val finalSlots = if (dstIdx == cols - 1 || dstIdx == cols * 2 - 1 || cur.count { it == null } < 2) {
            extendRackColumnsInternal(1, cur)
        } else cur
        _rackSlots.value = finalSlots
    }

    fun shuffleRackRandomly() {
        val active = _rackSlots.value.filterNotNull().shuffled()
        syncRackFromHand(active, preserveExistingPositions = false)
        _selectedTileIds.value = emptySet()
        _liftedSlotIndex.value = null
        _statusBanner.value = "🎲 已随机打乱牌架顺序（可点击或拖拽任意牌自由移动位置）"
    }

    fun organizeRack(preferRuns: Boolean) {
        _sortByColor.value = preferRuns
        val active = _rackSlots.value.filterNotNull()
        val (melds, leftovers) = RmkEvaluator.organizeHandIntoGroups(active, preferRuns)
        val row0 = ArrayList<RmkTile?>()
        val row1 = ArrayList<RmkTile?>()
        for (meld in melds) {
            if (row0.size <= row1.size) {
                if (row0.isNotEmpty()) row0.add(null)
                row0.addAll(meld)
            } else {
                if (row1.isNotEmpty()) row1.add(null)
                row1.addAll(meld)
            }
        }
        if (melds.isNotEmpty()) {
            if (row0.isNotEmpty()) row0.add(null)
            if (row1.isNotEmpty()) row1.add(null)
        }
        for (t in leftovers) {
            if (row0.size <= row1.size) row0.add(t) else row1.add(t)
        }
        val neededCols = maxOf(10, maxOf(row0.size, row1.size) + 2)
        _rackCols.value = neededCols
        val next = MutableList<RmkTile?>(neededCols * 2) { null }
        for (i in row0.indices) if (i < neededCols) next[i] = row0[i]
        for (i in row1.indices) if (i < neededCols) next[neededCols + i] = row1[i]
        _rackSlots.value = next
        _liftedSlotIndex.value = null
        _statusBanner.value = if (melds.isNotEmpty()) {
            "✨ 已按【${if (preferRuns) "789顺组" else "777群组"}】整理牌架：共识别 ${melds.size} 组可出牌型（已自动留空隔开）"
        } else {
            if (preferRuns) "🔢 已按 789 同色顺子方向整理牌架" else "🔢 已按 777 同数群组方向整理牌架"
        }
    }

    fun toggleSortMode() {
        organizeRack(!_sortByColor.value)
    }

    fun rebuildLobbySeats() {
        val cap = _roomPlayerCount.value.coerceIn(2, 4)
        if (orderedRoomPeers.isEmpty()) orderedRoomPeers.add(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        else {
            val idx = orderedRoomPeers.indexOfFirst { it.first == myPeerName }
            if (idx >= 0) orderedRoomPeers[idx] = Triple(myPeerName, _myCharacter.value.charId, cleanNick())
        }
        _isRoomAuthority.value = (orderedRoomPeers.first().first == myPeerName)
        val used = HashSet<Int>()
        val list = ArrayList<RmkSeat>(cap)
        val old = _seats.value
        for (i in 0 until cap) {
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

    private fun refreshLocalIpAddress(): String {
        try {
            val ifaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in ifaces) {
                if (!intf.isUp || intf.isLoopback) continue
                for (addr in Collections.list(intf.inetAddresses)) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        _localIpAddress.value = ip
                        return ip
                    }
                }
            }
        } catch (_: Exception) {}
        return _localIpAddress.value
    }

    private fun sendPacketText(jsonStr: String) {
        if (_isServerConnected.value) {
            sendPacketText(jsonStr)
        }
        if (lanWriters.isNotEmpty()) {
            Thread {
                for (w in lanWriters) {
                    try {
                        synchronized(w) { w.write(jsonStr); w.newLine(); w.flush() }
                    } catch (_: Exception) {
                        lanWriters.remove(w)
                    }
                }
            }.start()
        }
    }

    private fun attachLanSocket(sock: Socket) {
        Thread {
            try {
                val writer = BufferedWriter(OutputStreamWriter(sock.getOutputStream(), Charsets.UTF_8))
                lanWriters.add(writer)
                if (!_isRoomAuthority.value) {
                    val joinJson = JSONObject().apply {
                        put("kind", "joinRequest"); put("roomCode", wireRoomCode())
                        put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                        put("maxPlayers", _roomPlayerCount.value); put("gameType", "rummikub")
                    }.toString()
                    synchronized(writer) { writer.write(joinJson); writer.newLine(); writer.flush() }
                }
                val reader = BufferedReader(InputStreamReader(sock.getInputStream(), Charsets.UTF_8))
                while (!sock.isClosed) {
                    val line = reader.readLine() ?: break
                    if (line.isNotBlank()) mainHandler.post { handleIncomingJson(line) }
                }
            } catch (_: Exception) {
            } finally {
                try { sock.close() } catch (_: Exception) {}
            }
        }.start()
    }

    fun startHostingFaceToFaceRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号再创建面对面房间！"; return }
        stopNetworking()
        _roomCode.value = code
        _currentRound.value = 1
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        orderedRoomPeers = mutableListOf(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        val ip = refreshLocalIpAddress()
        _isHostingRoom.value = true
        _isRoomAuthority.value = true
        _isScanningRooms.value = false
        _mySeatIndex.value = 0
        rebuildLobbySeats()

        Thread {
            try {
                val srv = ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(tcpPort)) }
                tcpServerSocket = srv
                while (_isHostingRoom.value && !srv.isClosed) {
                    val sock = srv.accept()
                    attachLanSocket(sock)
                }
            } catch (_: Exception) {}
        }.start()

        Thread {
            try {
                val ds = DatagramSocket().apply { broadcast = true }
                udpSocket = ds
                while (_isHostingRoom.value && !ds.isClosed) {
                    val payload = JSONObject().apply {
                        put("type", "kon_rmk_room")
                        put("code", _roomCode.value)
                        put("host", cleanNick())
                        put("char", _myCharacter.value.charId)
                        put("ip", refreshLocalIpAddress())
                        put("port", tcpPort)
                    }.toString().toByteArray(Charsets.UTF_8)
                    try { ds.send(DatagramPacket(payload, payload.size, InetAddress.getByName("255.255.255.255"), udpPort)) } catch (_: Exception) {}
                    Thread.sleep(1200)
                }
            } catch (_: Exception) {}
        }.start()

        _statusBanner.value = "🔢 面对面拉密房间 [$code] 已创建！本机IP: $ip (${_roomPlayerCount.value}人局 · 仅限安卓直连)"
        audioManager.playMascotVoice(_myCharacter.value)
    }

    fun startScanningFaceToFaceRooms() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号再扫描！"; return }
        stopNetworking()
        _roomCode.value = code
        _isHostingRoom.value = false
        _isScanningRooms.value = true
        _discoveredRooms.value = emptyList()
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"

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
                        if (json.optString("type") == "kon_rmk_room" && json.optString("code").trim() == _roomCode.value.trim()) {
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
        _statusBanner.value = "🔍 正在扫描房号 [$code] 的面对面拉密房间..."
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
                attachLanSocket(sock)
                mainHandler.post { _statusBanner.value = "✅ 已直连到 [${room.hostName}] 的面对面拉密房间" }
            } catch (e: Exception) {
                mainHandler.post { _statusBanner.value = "⚠️ 连接失败: ${e.message}" }
            }
        }.start()
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
        sendPacketText(JSONObject().apply {
            put("kind", "joinRequest"); put("roomCode", wc)
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", _roomPlayerCount.value); put("gameType", "rummikub")
        }.toString())
        _statusBanner.value = "✅ 已连接拉密数字牌房间 [${_roomCode.value}] (${_roomPlayerCount.value}人局 · 真人进房自动替换AI)"
    }

    private fun broadcastRoster() {
        val inRoom = _isServerConnected.value || _isHostingRoom.value || lanWriters.isNotEmpty()
        if (!inRoom || !_isRoomAuthority.value || wireRoomCode().isEmpty()) return
        val peersArr = JSONArray()
        orderedRoomPeers.forEach { rp -> peersArr.put(JSONObject().apply { put("name", rp.first); put("charId", rp.second); put("displayName", rp.third) }) }
        sendPacketText(JSONObject().apply {
            put("kind", "roomRoster"); put("roomCode", wireRoomCode())
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", _roomPlayerCount.value)
            put("hostPeerName", myPeerName); put("roomPeers", peersArr)
        }.toString())
    }

    fun leaveRoomAndResetLobby() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        val wc = wireRoomCode()
        if ((_isServerConnected.value || _isHostingRoom.value || lanWriters.isNotEmpty()) && wc.isNotEmpty()) {
            sendPacketText(JSONObject().apply {
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
        try { tcpServerSocket?.close() } catch (_: Exception) {}; tcpServerSocket = null
        try { udpSocket?.close() } catch (_: Exception) {}; udpSocket = null
        lanWriters.clear()
        _isServerConnected.value = false; _isHostingRoom.value = false; _isScanningRooms.value = false
        _discoveredRooms.value = emptyList(); _connectedPeerNames.value = emptyList(); orderedRoomPeers.clear()
    }

    private fun tileToJson(t: RmkTile) = JSONObject().apply { put("id", t.id); put("color", t.color.code); put("number", t.number) }
    private fun tileFromJson(o: JSONObject) = RmkTile(o.optString("id"), RmkColor.fromCode(o.optString("color", "R")), o.optInt("number", 1))

    private fun broadcastFullState() {
        if ((!_isServerConnected.value && !_isHostingRoom.value && lanWriters.isEmpty()) || !_isRoomAuthority.value || wireRoomCode().isEmpty()) return
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
        sendPacketText(JSONObject().apply {
            put("kind", "stateSync"); put("roomCode", wireRoomCode())
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", _roomPlayerCount.value); put("gameType", "rummikub")
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
                    val mp = obj.optInt("maxPlayers", 0)
                    if (mp in 2..4) _roomPlayerCount.value = mp
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
                    val cap = _roomPlayerCount.value.coerceIn(2, 4)
                    if (_isRoomAuthority.value && orderedRoomPeers.none { it.first == sender } && orderedRoomPeers.size < cap) {
                        orderedRoomPeers.add(Triple(sender, sChar, cleanPeer(sender)))
                        rebuildLobbySeats()
                        _statusBanner.value = "🎉 跨平台玩家 [${cleanPeer(sender)}] 加入房间 (已自动替换 AI 座位)"
                        broadcastRoster()
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
                    val mp = obj.optInt("maxPlayers", 0)
                    if (mp in 2..4) _roomPlayerCount.value = mp
                    _isRoomAuthority.value = (obj.optString("hostPeerName") == myPeerName)
                    val sArr = obj.optJSONArray("seats")
                    if (sArr != null) {
                        if (sArr.length() in 2..4) _roomPlayerCount.value = sArr.length()
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
                                val tArr = mo.optJSONArray("tiles")
                                val ts = ArrayList<RmkTile>()
                                if (tArr != null) for (k in 0 until tArr.length()) ts.add(tileFromJson(tArr.getJSONObject(k)))
                                ms.add(RmkMeld(mo.optString("id"), ts))
                            }
                            val pArr = obj.optJSONArray("committedHandIds") ?: return
                            val pids = HashSet<String>()
                            for (i in 0 until pArr.length()) pids.add(pArr.getString(i))
                            executeCommitTurn(idx, ms, pids)
                        }
                    }
                }
            }
        } catch (_: Exception) {}
    }

    fun startNewRound() {
        if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) return
        rebuildLobbySeats()
        val pCnt = _seats.value.size.coerceIn(2, 4)
        pool.clear()
        pool.addAll(build106Deck())
        val list = _seats.value.toMutableList()
        for (i in 0 until pCnt) {
            val dealt = pool.take(14)
            repeat(14) { pool.removeAt(0) }
            list[i] = list[i].copy(hand = dealt, hasBrokenIce = false)
        }
        _seats.value = list
        _poolCount.value = pool.size
        _tableMelds.value = emptyList()
        _currentTurnSeat.value = (_currentRound.value - 1) % pCnt
        _phase.value = RmkGamePhase.PLAYING
        resetWorkspaceForNewTurn(preserveRackLayout = false)
        trigger15sDealAnimation()
        _statusBanner.value = "🔢 正在派发 14 张初始手牌 (1.5秒发牌动画)... 轮到 [${list[_currentTurnSeat.value].name}] 出牌 (需≥30分破冰)"
        startTurnTimer()
        broadcastFullState()
        scheduleAiTurnIfNeeded()
    }

    fun nextRound() {
        _currentRound.value += 1
        startNewRound()
    }

    private fun startTurnTimer() {
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        _turnRemainingSeconds.value = 60
        val r = object : Runnable {
            override fun run() {
                if (_phase.value != RmkGamePhase.PLAYING) return
                if (_turnRemainingSeconds.value > 0) {
                    _turnRemainingSeconds.value -= 1
                    mainHandler.postDelayed(this, 1000L)
                } else if (!_isServerConnected.value || _isRoomAuthority.value) {
                    restoreWorkspaceSnapshot()
                    executeDrawAndAdvance(_currentTurnSeat.value, "⏰ 60秒超时复原桌面并罚抽1张")
                }
            }
        }
        timerRunnable = r
        mainHandler.postDelayed(r, 1000L)
    }

    fun trigger15sDealAnimation() {
        _isDealingAnimation.value = true
        _dealingVisibleCount.value = 0
        for (step in 1..14) {
            mainHandler.postDelayed({
                _dealingVisibleCount.value = step
                if (step == 14) {
                    _dealingVisibleCount.value = 99
                    _isDealingAnimation.value = false
                }
            }, (step * 105).toLong())
        }
    }

    fun resetWorkspaceForNewTurn(preserveRackLayout: Boolean = true) {
        _selectedTileIds.value = emptySet()
        _liftedSlotIndex.value = null
        _isEditingTable.value = false
        val myHand = _seats.value.getOrNull(_mySeatIndex.value)?.hand ?: emptyList()
        snapshotHand = myHand
        _workingHand.value = myHand
        syncRackFromHand(myHand, preserveExistingPositions = preserveRackLayout)
        snapshotRackSlots = _rackSlots.value
        snapshotMelds = _tableMelds.value
        _workingMelds.value = _tableMelds.value
    }

    private fun ensureWorkspace() {
        if (!_isEditingTable.value) {
            val myHand = _seats.value.getOrNull(_mySeatIndex.value)?.hand ?: emptyList()
            snapshotHand = myHand
            _workingHand.value = myHand
            snapshotMelds = _tableMelds.value
            _workingMelds.value = _tableMelds.value
            snapshotRackSlots = _rackSlots.value
            _isEditingTable.value = true
        }
    }

    fun restoreWorkspaceSnapshot() {
        if (_isEditingTable.value) {
            _workingHand.value = snapshotHand
            _workingMelds.value = snapshotMelds
            _rackSlots.value = snapshotRackSlots
            _selectedTileIds.value = emptySet()
            _liftedSlotIndex.value = null
            _isEditingTable.value = false
            _statusBanner.value = "↩️ 已复原到本回合初始牌面与牌架位置"
        }
    }

    fun toggleSelectTile(id: String) {
        val cur = _selectedTileIds.value.toMutableSet()
        if (!cur.add(id)) cur.remove(id)
        _selectedTileIds.value = cur
    }

    fun placeSelectedAsNewMeld() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        val sel = _selectedTileIds.value
        if (sel.isEmpty()) return
        ensureWorkspace()
        val picked = _workingHand.value.filter { sel.contains(it.id) }
        if (RmkEvaluator.evaluateMeld(picked) == null) {
            _statusBanner.value = "⚠️ 所选牌未能组成有效顺组或群组 (需≥3张)"
            return
        }
        _workingHand.value = _workingHand.value.filterNot { sel.contains(it.id) }
        _rackSlots.value = _rackSlots.value.map { if (it != null && sel.contains(it.id)) null else it }
        _workingMelds.value = _workingMelds.value + RmkMeld(UUID.randomUUID().toString(), picked)
        _selectedTileIds.value = emptySet()
        _statusBanner.value = "✅ 已暂放牌组到桌面（点击【确认出牌】完成回合）"
    }

    fun addSelectedToTableMeld(meldId: String) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        val sel = _selectedTileIds.value
        if (sel.isEmpty()) return
        if (_seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce != true) {
            _statusBanner.value = "⚠️ 尚未破冰！首次出牌只能使用自己牌架的牌且总和 ≥30 分"
            return
        }
        ensureWorkspace()
        val idx = _workingMelds.value.indexOfFirst { it.id == meldId }
        if (idx < 0) return
        val picked = _workingHand.value.filter { sel.contains(it.id) }
        val comb = _workingMelds.value[idx].tiles + picked
        if (RmkEvaluator.evaluateMeld(comb) == null) {
            _statusBanner.value = "⚠️ 添牌后该牌组不符合群组或顺组规则"
            return
        }
        _workingHand.value = _workingHand.value.filterNot { sel.contains(it.id) }
        _rackSlots.value = _rackSlots.value.map { if (it != null && sel.contains(it.id)) null else it }
        val ms = _workingMelds.value.toMutableList()
        ms[idx] = ms[idx].copy(tiles = comb.sortedBy { it.number })
        _workingMelds.value = ms
        _selectedTileIds.value = emptySet()
        _statusBanner.value = "✅ 已将选牌并入桌面牌组（点击【确认出牌】完成回合）"
    }

    fun splitMeldToWorkspace(meldId: String) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        if (_seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce != true) {
            _statusBanner.value = "⚠️ 尚未破冰，不能拆解桌面牌组！"
            return
        }
        ensureWorkspace()
        val idx = _workingMelds.value.indexOfFirst { it.id == meldId }
        if (idx < 0 || _workingMelds.value[idx].tiles.size < 4) {
            _statusBanner.value = "⚠️ 只有 ≥4 张的牌组才可直接拆出端牌重组"
            return
        }
        val ms = _workingMelds.value.toMutableList()
        val popped = ms[idx].tiles.last()
        ms[idx] = ms[idx].copy(tiles = ms[idx].tiles.dropLast(1))
        _workingMelds.value = ms
        _workingHand.value = _workingHand.value + popped
        syncRackFromHand(_workingHand.value, preserveExistingPositions = true)
        _selectedTileIds.value = _selectedTileIds.value + popped.id
        _statusBanner.value = "🔄 已从牌组拆出 1 张牌，请配合手牌组成新牌组后【确认出牌】"
    }

    fun smartHint() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        ensureWorkspace()
        val best = RmkEvaluator.findBestMeld(_workingHand.value)
        if (best != null) {
            _selectedTileIds.value = best.map { it.id }.toSet()
            _statusBanner.value = "💡 已为您选中推荐牌组（点【放上桌面】即可出牌）"
        } else {
            _statusBanner.value = "💡 暂无可直出牌组，可尝试拆解桌面 ≥4 张牌组或摸牌"
        }
    }

    fun commitMyTurn() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        ensureWorkspace()
        val remIds = _workingHand.value.map { it.id }.toSet()
        val playedIds = snapshotHand.map { it.id }.filterNot { remIds.contains(it) }.toSet()
        if (playedIds.isEmpty()) {
            _statusBanner.value = "⚠️ 本回合尚未打出任何牌架上的牌（若不出请点【摸牌过】）"
            return
        }
        for (m in _workingMelds.value) {
            if (RmkEvaluator.evaluateMeld(m.tiles) == null) {
                _statusBanner.value = "⚠️ 桌面存在无效牌组，请继续重组或点【复原】"
                return
            }
        }
        if (_seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce != true) {
            if (_workingMelds.value.size <= snapshotMelds.size) {
                _statusBanner.value = "⚠️ 首次破冰只能出自己牌架的牌组！"
                return
            }
            var pts = 0
            for (i in snapshotMelds.size until _workingMelds.value.size) {
                pts += RmkEvaluator.evaluateMeld(_workingMelds.value[i].tiles) ?: 0
            }
            if (pts < 30) {
                _statusBanner.value = "⚠️ 破冰总分仅 $pts 分，必须 ≥30 分才能首次出牌！"
                return
            }
        }

        if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) {
            val mArr = JSONArray()
            _workingMelds.value.forEach { m ->
                val tArr = JSONArray()
                m.tiles.forEach { tArr.put(tileToJson(it)) }
                mArr.put(JSONObject().apply { put("id", m.id); put("tiles", tArr) })
            }
            val pArr = JSONArray()
            playedIds.forEach { pArr.put(it) }
            sendPacketText(JSONObject().apply {
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
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING || _isDrawingAnimation.value) return
        restoreWorkspaceSnapshot()
        _isDrawingAnimation.value = true
        _drawingAnimatedTile.value = pool.firstOrNull() ?: RmkTile("anim_draw", RmkColor.RED, 7)
        _statusBanner.value = "🃏 正在从牌堆摸取 1 张新牌 (1.5秒摸牌动画)..."
        mainHandler.postDelayed({
            _isDrawingAnimation.value = false
            _drawingAnimatedTile.value = null
            if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) {
                sendPacketText(JSONObject().apply {
                    put("kind", "drawTileAction"); put("roomCode", wireRoomCode())
                    put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                }.toString())
            } else {
                executeDrawAndAdvance(_mySeatIndex.value, "摸牌结束回合")
            }
        }, 1500L)
    }

    private fun executeCommitTurn(seatIdx: Int, newMelds: List<RmkMeld>, playedIds: Set<String>) {
        val pCnt = _seats.value.size.coerceAtLeast(2)
        _tableMelds.value = newMelds
        val list = _seats.value.toMutableList()
        val remHand = list[seatIdx].hand.filterNot { playedIds.contains(it.id) }
        list[seatIdx] = list[seatIdx].copy(hand = remHand, hasBrokenIce = true)
        _seats.value = list
        _isEditingTable.value = false

        if (remHand.isEmpty()) {
            finishRound(seatIdx)
            return
        }
        _currentTurnSeat.value = (seatIdx + 1) % pCnt
        resetWorkspaceForNewTurn()
        _turnRemainingSeconds.value = 60
        _statusBanner.value = "✅ [${list[seatIdx].name}] 出牌 ${playedIds.size} 张！轮到 [${list[_currentTurnSeat.value].name}]"
        broadcastFullState()
        scheduleAiTurnIfNeeded()
    }

    private fun executeDrawAndAdvance(seatIdx: Int, reason: String) {
        val pCnt = _seats.value.size.coerceAtLeast(2)
        val list = _seats.value.toMutableList()
        if (pool.isNotEmpty()) {
            val t = pool.removeAt(0)
            list[seatIdx] = list[seatIdx].copy(hand = list[seatIdx].hand + t)
            _seats.value = list
            _poolCount.value = pool.size
        }
        _isEditingTable.value = false
        _currentTurnSeat.value = (seatIdx + 1) % pCnt
        resetWorkspaceForNewTurn()
        _turnRemainingSeconds.value = 60
        _statusBanner.value = "[${list[seatIdx].name}] $reason · 轮到 [${list[_currentTurnSeat.value].name}]"
        broadcastFullState()
        scheduleAiTurnIfNeeded()
    }

    private fun finishRound(winner: Int) {
        val pCnt = _seats.value.size.coerceAtLeast(2)
        _phase.value = RmkGamePhase.ROUND_OVER
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        val list = _seats.value.toMutableList()
        var gain = 0
        for (i in 0 until pCnt) {
            if (i == winner) continue
            val pen = list[i].hand.sumOf { if (it.isJoker) 30 else it.number }
            list[i] = list[i].copy(score = list[i].score - pen)
            gain += pen
        }
        list[winner] = list[winner].copy(score = list[winner].score + gain)
        _seats.value = list
        _statusBanner.value = "🏆 [${list[winner].name}] 清空牌架获胜！(赢得 +$gain 分)"
        broadcastFullState()
    }

    private fun scheduleAiTurnIfNeeded() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) return
        val cur = _currentTurnSeat.value
        if (_phase.value == RmkGamePhase.PLAYING && _seats.value.getOrNull(cur)?.isAI == true) {
            val r = Runnable {
                if (_phase.value == RmkGamePhase.PLAYING && _currentTurnSeat.value == cur) {
                    val s = _seats.value[cur]
                    val best = RmkEvaluator.findBestMeld(s.hand)
                    val pts = if (best != null) RmkEvaluator.evaluateMeld(best) ?: 0 else 0
                    if (best != null && (s.hasBrokenIce || pts >= 30)) {
                        val nm = _tableMelds.value + RmkMeld(UUID.randomUUID().toString(), best)
                        executeCommitTurn(cur, nm, best.map { it.id }.toSet())
                    } else {
                        executeDrawAndAdvance(cur, "从共用牌堆摸1张牌")
                    }
                }
            }
            aiRunnable = r
            mainHandler.postDelayed(r, 1500L)
        }
    }
}
