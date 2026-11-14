package com.tomy.httnavicompanion.audio

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.*
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

enum class CardSuit(val symbol: String, val isRed: Boolean) {
    SPADE("♠", false),
    HEART("♥", true),
    CLUB("♣", false),
    DIAMOND("♦", true),
    JOKER("🃏", true)
}

data class DoudizhuCard(
    val id: String,
    val rank: Int, // 3..15 (11=J,12=Q,13=K,14=A,15=2), 16=SmallJoker, 17=BigJoker
    val suit: CardSuit
) {
    val rankLabel: String
        get() = when (rank) {
            11 -> "J"
            12 -> "Q"
            13 -> "K"
            14 -> "A"
            15 -> "2"
            16 -> "小王"
            17 -> "大王"
            else -> rank.toString()
        }

    val isRedCard: Boolean
        get() = when (rank) {
            17 -> true
            16 -> false
            else -> suit.isRed
        }

    val cardImageKey: String
        get() = when (rank) {
            16 -> "joker_16"
            17 -> "joker_17"
            else -> "${suit.symbol}_$rank"
        }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("rank", rank)
        put("suit", suit.symbol)
    }

    companion object {
        fun fromJson(obj: JSONObject): DoudizhuCard {
            val rank = obj.optInt("rank")
            val sSym = obj.optString("suit", "♠")
            val suit = CardSuit.values().firstOrNull { it.symbol == sSym }
                ?: if (rank >= 16) CardSuit.JOKER else CardSuit.SPADE
            val defaultId = if (rank >= 16) "joker_$rank" else "${suit.symbol}_$rank"
            val rawId = obj.optString("id").ifBlank { defaultId }
            return DoudizhuCard(rawId, rank, suit)
        }
    }
}

enum class DoudizhuHandType(val wireName: String, val label: String) {
    INVALID("invalid", "无效牌型"),
    SINGLE("single", "单张"),
    PAIR("pair", "对子"),
    TRIPLE("triple", "三张"),
    TRIPLE_ONE("tripleWithOne", "三带一"),
    TRIPLE_PAIR("tripleWithPair", "三带二"),
    STRAIGHT("straight", "顺子"),
    DOUBLE_STRAIGHT("consecutivePairs", "连对"),
    AIRPLANE("airplane", "飞机"),
    FOUR_WITH_TWO("fourWithTwo", "四带二"),
    BOMB("bomb", "💥 炸弹!"),
    ROCKET("rocket", "🚀 王炸!!")
}

data class EvaluatedDoudizhuHand(
    val type: DoudizhuHandType,
    val mainRank: Int,
    val length: Int,
    val cards: List<DoudizhuCard>
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("category", type.wireName)
        put("primaryRank", mainRank)
        put("length", length)
        put("cards", JSONArray().apply { cards.forEach { put(it.toJson()) } })
    }

    companion object {
        fun fromJson(obj: JSONObject?): EvaluatedDoudizhuHand? {
            if (obj == null) return null
            val catStr = obj.optString("category", "invalid")
            val t = DoudizhuHandType.values().firstOrNull { it.wireName == catStr } ?: DoudizhuHandType.INVALID
            if (t == DoudizhuHandType.INVALID) return null
            val pRank = obj.optInt("primaryRank")
            val len = obj.optInt("length")
            val arr = obj.optJSONArray("cards") ?: JSONArray()
            val list = (0 until arr.length()).map { DoudizhuCard.fromJson(arr.getJSONObject(it)) }
            return EvaluatedDoudizhuHand(t, pRank, len, list)
        }
    }
}

enum class DoudizhuGamePhase(val wireName: String) {
    LOBBY("lobby"),
    BIDDING("bidding"),
    PLAYING("playing"),
    FINISHED("roundOver")
}

enum class DoudizhuNetworkMode {
    FACE_TO_FACE_P2P,
    ONLINE_SERVER
}

enum class DoudizhuAIDifficulty(val label: String) {
    CASUAL("休闲 AI"),
    STANDARD("标准 AI"),
    MASTER("大师 AI")
}

data class DiscoveredP2PRoom(
    val id: String,
    val roomCode: String,
    val hostName: String,
    val hostCharId: Int,
    val hostAddress: String,
    val port: Int,
    val isBluetooth: Boolean = false,
    val isBle: Boolean = false,
    val bleDevice: BluetoothDevice? = null
)

data class DoudizhuPlayerSeat(
    val seatIndex: Int,
    val name: String,
    val character: CharacterFilter,
    val isAI: Boolean,
    val peerDisplayName: String = "",
    val isLandlord: Boolean = false,
    val hand: List<DoudizhuCard> = emptyList(),
    val lastPlayed: List<DoudizhuCard> = emptyList(),
    val lastActionText: String = "",
    val passedLast: Boolean = false,
    val score: Int = 1000
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", seatIndex)
        put("name", name)
        put("characterId", character.charId)
        put("isAI", isAI)
        put("peerDisplayName", peerDisplayName)
        put("isLandlord", isLandlord)
        put("lastActionText", lastActionText)
        put("score", score)
        put("hand", JSONArray().apply { hand.forEach { put(it.toJson()) } })
        put("lastPlayedCards", JSONArray().apply { lastPlayed.forEach { put(it.toJson()) } })
    }

    companion object {
        fun fromJson(obj: JSONObject): DoudizhuPlayerSeat {
            val sid = obj.optInt("id")
            val name = obj.optString("name")
            val cid = obj.optInt("characterId", 1)
            val ch = CharacterFilter.fiveIndividuals.firstOrNull { it.charId == cid } ?: CharacterFilter.YUI
            val isAI = obj.optBoolean("isAI", false)
            val peer = obj.optString("peerDisplayName", "")
            val isL = obj.optBoolean("isLandlord", false)
            val lastAct = obj.optString("lastActionText", "")
            val score = obj.optInt("score", 1000)
            val hArr = obj.optJSONArray("hand") ?: JSONArray()
            val hand = (0 until hArr.length()).map { DoudizhuCard.fromJson(hArr.getJSONObject(it)) }
            val lpArr = obj.optJSONArray("lastPlayedCards") ?: JSONArray()
            val lastPlayed = (0 until lpArr.length()).map { DoudizhuCard.fromJson(lpArr.getJSONObject(it)) }
            return DoudizhuPlayerSeat(sid, name, ch, isAI, peer, isL, hand, lastPlayed, lastAct, lastAct == "不出", score)
        }
    }
}

class DoudizhuEngine(private val context: Context, private val audioMgr: AudioPlayerManager) {
    private val TAG = "DoudizhuEngine"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val btSppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val bleServiceUuid: UUID = UUID.fromString("E0B86100-3510-4B2C-9000-4B4F4E44445A")
    private val bleCharUuid: UUID = UUID.fromString("E0B86101-3510-4B2C-9000-4B4F4E44445A")
    private val tcpPort = 47789
    private val wsPort = 47790
    private val udpBroadcastPort = 47788

    // Network Mode & Server Settings (matches iOS v1.6.3)
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

    private val _myNickname = MutableStateFlow(Build.MODEL.ifBlank { "轻音车友" })
    val myNickname: StateFlow<String> = _myNickname

    private val _myChar = MutableStateFlow(CharacterFilter.YUI)
    val myChar: StateFlow<CharacterFilter> = _myChar

    private val _isHostingRoom = MutableStateFlow(false)
    val isHostingRoom: StateFlow<Boolean> = _isHostingRoom

    private val _isScanningRooms = MutableStateFlow(false)
    val isScanningRooms: StateFlow<Boolean> = _isScanningRooms

    private val _isServerConnected = MutableStateFlow(false)
    val isServerConnected: StateFlow<Boolean> = _isServerConnected

    private val _connectedPeerNames = MutableStateFlow<List<String>>(emptyList())
    val connectedPeerNames: StateFlow<List<String>> = _connectedPeerNames

    private val _discoveredRooms = MutableStateFlow<List<DiscoveredP2PRoom>>(emptyList())
    val discoveredRooms: StateFlow<List<DiscoveredP2PRoom>> = _discoveredRooms

    private val _mySeatIndex = MutableStateFlow(0)
    val mySeatIndex: StateFlow<Int> = _mySeatIndex

    // Room Rules (1:1 match with iOS screenshots)
    private val _totalRounds = MutableStateFlow(3) // 3, 5, 10, 0=无限局
    val totalRounds: StateFlow<Int> = _totalRounds

    private val _currentRound = MutableStateFlow(1)
    val currentRound: StateFlow<Int> = _currentRound

    private val _baseScore = MutableStateFlow(100) // 50, 100, 200, 500
    val baseScore: StateFlow<Int> = _baseScore

    private val _maxMultiplier = MutableStateFlow(32) // 16, 32, 64, 0=不封顶
    val maxMultiplier: StateFlow<Int> = _maxMultiplier

    private val _turnTimeLimit = MutableStateFlow(25) // 15, 25, 30, 0=不限时
    val turnTimeLimit: StateFlow<Int> = _turnTimeLimit

    private val _turnRemainingSeconds = MutableStateFlow(25)
    val turnRemainingSeconds: StateFlow<Int> = _turnRemainingSeconds

    private val _allowCardCounter = MutableStateFlow(true)
    val allowCardCounter: StateFlow<Boolean> = _allowCardCounter

    private val _aiDifficulty = MutableStateFlow(DoudizhuAIDifficulty.STANDARD)
    val aiDifficulty: StateFlow<DoudizhuAIDifficulty> = _aiDifficulty

    // Game State
    private val _phase = MutableStateFlow(DoudizhuGamePhase.LOBBY)
    val phase: StateFlow<DoudizhuGamePhase> = _phase

    private val _seats = MutableStateFlow<List<DoudizhuPlayerSeat>>(emptyList())
    val seats: StateFlow<List<DoudizhuPlayerSeat>> = _seats

    private val _holeCards = MutableStateFlow<List<DoudizhuCard>>(emptyList())
    val holeCards: StateFlow<List<DoudizhuCard>> = _holeCards

    private val _selectedCardIds = MutableStateFlow<Set<String>>(emptySet())
    val selectedCardIds: StateFlow<Set<String>> = _selectedCardIds

    private val _currentTurnSeat = MutableStateFlow(0)
    val currentTurnSeat: StateFlow<Int> = _currentTurnSeat

    private val _highestBid = MutableStateFlow(0)
    val highestBid: StateFlow<Int> = _highestBid

    private val _highestBidderSeat = MutableStateFlow(-1)
    val highestBidderSeat: StateFlow<Int> = _highestBidderSeat

    private val _bidsCount = MutableStateFlow(0)
    val bidsCount: StateFlow<Int> = _bidsCount

    private val _multiplier = MutableStateFlow(1)
    val multiplier: StateFlow<Int> = _multiplier

    private val _lastValidHand = MutableStateFlow<EvaluatedDoudizhuHand?>(null)
    val lastValidHand: StateFlow<EvaluatedDoudizhuHand?> = _lastValidHand

    private val _lastPlaySeat = MutableStateFlow(-1)
    val lastPlaySeat: StateFlow<Int> = _lastPlaySeat

    private val _winnerSeat = MutableStateFlow<Int?>(null)
    val winnerSeat: StateFlow<Int?> = _winnerSeat

    private val _statusBanner = MutableStateFlow("欢迎来到放课后茶会斗地主！支持与 iOS / 安卓面对面或局域网联机")
    val statusBanner: StateFlow<String> = _statusBanner

    private val _playedCardsHistory = MutableStateFlow<List<DoudizhuCard>>(emptyList())
    val playedCardsHistory: StateFlow<List<DoudizhuCard>> = _playedCardsHistory

    private var hintIndex = 0
    private var hasUnmodifiedIosWsPeer = false
    private val _isRoomAuthority = MutableStateFlow(true)
    val isRoomAuthority: StateFlow<Boolean> = _isRoomAuthority
    private val isRoomAuthorityVal: Boolean get() = _isRoomAuthority.value

    // Transport handles
    private interface PeerChannel {
        fun sendJson(raw: String)
        fun close()
    }

    private val activeChannels = CopyOnWriteArrayList<PeerChannel>()
    private var tcpServerSocket: ServerSocket? = null
    private var wsServerSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var udpSocket: DatagramSocket? = null
    private var btServerSocket: BluetoothServerSocket? = null
    private var btClientSocket: BluetoothSocket? = null
    private var gattServer: BluetoothGattServer? = null
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleScanner: BluetoothLeScanner? = null
    private var bleClientGatt: BluetoothGatt? = null
    private val bleConnectedDevices = CopyOnWriteArrayList<BluetoothDevice>()
    private var bleCharacteristic: BluetoothGattCharacteristic? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var nsdManager: NsdManager? = null
    private var nsdRegListener: NsdManager.RegistrationListener? = null
    private var nsdDiscListener: NsdManager.DiscoveryListener? = null
    private var webSocket: WebSocket? = null
    private val okHttpClient = OkHttpClient()
    private var timerRunnable: Runnable? = null

    init {
        refreshLocalIpAddress()
        rebuildLobbySeats()
        startTurnTimerLoop()
    }

    private fun startTurnTimerLoop() {
        val r = object : Runnable {
            override fun run() {
                if ((_phase.value == DoudizhuGamePhase.BIDDING || _phase.value == DoudizhuGamePhase.PLAYING) && _turnTimeLimit.value > 0) {
                    if (_turnRemainingSeconds.value > 0) {
                        _turnRemainingSeconds.value -= 1
                    } else if (isRoomAuthorityVal) {
                        handleTurnTimeout()
                    }
                }
                mainHandler.postDelayed(this, 1000L)
            }
        }
        timerRunnable = r
        mainHandler.postDelayed(r, 1000L)
    }

    fun refreshLocalIpAddress(): String {
        var bestIp = "127.0.0.1"
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces != null && interfaces.hasMoreElements()) {
                val nif = interfaces.nextElement()
                if (!nif.isUp || nif.isLoopback) continue
                val addrs = nif.inetAddresses
                while (addrs.hasMoreElements()) {
                    val addr = addrs.nextElement()
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        if (ip.startsWith("192.168.") || ip.startsWith("172.20.") || ip.startsWith("10.")) {
                            bestIp = ip
                            break
                        } else if (bestIp == "127.0.0.1") {
                            bestIp = ip
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        _localIpAddress.value = bestIp
        return bestIp
    }

    private fun getAllBroadcastAddresses(): List<InetAddress> {
        val list = mutableListOf<InetAddress>()
        try {
            list.add(InetAddress.getByName("255.255.255.255"))
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces != null && interfaces.hasMoreElements()) {
                val nif = interfaces.nextElement()
                if (!nif.isUp || nif.isLoopback) continue
                for (ia in nif.interfaceAddresses) {
                    val bcast = ia.broadcast
                    if (bcast != null && !list.contains(bcast)) {
                        list.add(bcast)
                    }
                }
            }
        } catch (_: Exception) {}
        return list
    }

    fun setNetworkMode(mode: DoudizhuNetworkMode) { _networkMode.value = mode }
    fun setServerUrl(url: String) { _serverUrl.value = url }
    fun setDirectConnectIp(ip: String) { _directConnectIp.value = ip }
    fun setRoomCode(code: String) { _roomCode.value = code }
    fun setMyNickname(name: String) { _myNickname.value = name; rebuildLobbySeats() }
    fun setMyCharacter(char: CharacterFilter) {
        _myChar.value = if (char == CharacterFilter.ALL) CharacterFilter.YUI else char
        rebuildLobbySeats()
    }
    fun setTotalRounds(rounds: Int) { _totalRounds.value = rounds ; syncRulesIfHost() }
    fun setBaseScore(score: Int) { _baseScore.value = score ; syncRulesIfHost() }
    fun setMaxMultiplier(maxM: Int) { _maxMultiplier.value = maxM ; syncRulesIfHost() }
    fun setTurnTimeLimit(secs: Int) { _turnTimeLimit.value = secs; _turnRemainingSeconds.value = secs ; syncRulesIfHost() }
    fun setAllowCardCounter(allow: Boolean) { _allowCardCounter.value = allow ; syncRulesIfHost() }
    fun setAIDifficulty(diff: DoudizhuAIDifficulty) { _aiDifficulty.value = diff ; syncRulesIfHost() }

    private fun currentLang(): AppLanguage {
        return try {
            audioMgr.language.value
        } catch (_: Throwable) {
            AppLanguage.ZH_HANS
        }
    }

    private fun rebuildLobbySeats() {
        if (_phase.value != DoudizhuGamePhase.LOBBY) return
        val lang = currentLang()
        val aiPool = CharacterFilter.fiveIndividuals.filter { it != _myChar.value }
        if (hasUnmodifiedIosWsPeer) {
            val iosChar = aiPool.firstOrNull() ?: CharacterFilter.MIO
            val aiChar = aiPool.getOrNull(1) ?: CharacterFilter.RITSU
            val s0 = DoudizhuPlayerSeat(0, "iOS 玩家 (${iosChar.displayName(lang)})", iosChar, isAI = false, peerDisplayName = "iOS_Host")
            val s1 = DoudizhuPlayerSeat(1, "${_myNickname.value} (${_myChar.value.displayName(lang)})", _myChar.value, isAI = false, peerDisplayName = _myNickname.value)
            val s2 = DoudizhuPlayerSeat(2, "${aiChar.displayName(lang)} (AI)", aiChar, isAI = true, peerDisplayName = "AI_2")
            _mySeatIndex.value = 1
            _seats.value = listOf(s0, s1, s2)
            return
        }
        val existingPeers = _seats.value.filter { !it.isAI && it.seatIndex != 0 }
        val s0 = DoudizhuPlayerSeat(0, "${_myNickname.value} (${_myChar.value.displayName(lang)})", _myChar.value, isAI = false, peerDisplayName = _myNickname.value)
        val s1 = existingPeers.getOrNull(0)?.copy(seatIndex = 1)
            ?: DoudizhuPlayerSeat(1, "${aiPool[0].displayName(lang)} (AI)", aiPool[0], isAI = true, peerDisplayName = "AI_1")
        val s2 = existingPeers.getOrNull(1)?.copy(seatIndex = 2)
            ?: DoudizhuPlayerSeat(2, "${aiPool[1].displayName(lang)} (AI)", aiPool[1], isAI = true, peerDisplayName = "AI_2")
        _mySeatIndex.value = 0
        _seats.value = listOf(s0, s1, s2)
    }

    // =========================================================================
    // 1. Face-to-Face P2P (BLE + Bluetooth RFCOMM + Wi-Fi UDP/TCP + Embedded iOS WS)
    // =========================================================================
    @SuppressLint("MissingPermission")
    fun startHostingFaceToFaceRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) {
            _statusBanner.value = "⚠️ 请先填写房号，未填写无法创建房间！"
            return
        }
        _roomCode.value = code
        stopNetworking()
        val ip = refreshLocalIpAddress()
        _isHostingRoom.value = true
        _isRoomAuthority.value = true
        _isScanningRooms.value = false
        _mySeatIndex.value = 0
        rebuildLobbySeats()
        acquireWifiMulticastLock()

        // A1. Start Dual-Protocol Server on tcpPort (47789) - accepts both raw JSON lines AND WebSocket upgrades!
        Thread {
            try {
                val srv = ServerSocket()
                srv.reuseAddress = true
                srv.bind(InetSocketAddress(tcpPort))
                tcpServerSocket = srv
                while (_isHostingRoom.value && !srv.isClosed) {
                    val sock = srv.accept()
                    handleAcceptedSocket(sock)
                }
            } catch (e: Exception) {
                Log.w(TAG, "TCP Server 47789 stopped: ${e.message}")
            }
        }.start()

        // A2. Start Dedicated Embedded WebSocket Server on wsPort (47790) for unmodified iOS App compatibility
        Thread {
            try {
                val wsSrv = ServerSocket()
                wsSrv.reuseAddress = true
                wsSrv.bind(InetSocketAddress(wsPort))
                wsServerSocket = wsSrv
                while (_isHostingRoom.value && !wsSrv.isClosed) {
                    val sock = wsSrv.accept()
                    handleAcceptedSocket(sock)
                }
            } catch (e: Exception) {
                Log.w(TAG, "WS Server 47790 stopped: ${e.message}")
            }
        }.start()

        // B. Start UDP Broadcast Advertiser (every 1.2s across 255.255.255.255 + all subnet broadcast IPs)
        Thread {
            try {
                val ds = DatagramSocket()
                ds.broadcast = true
                udpSocket = ds
                while (_isHostingRoom.value && !ds.isClosed) {
                    try {
                        val curIp = refreshLocalIpAddress()
                        val payload = JSONObject().apply {
                            put("type", "kon_ddz_room")
                            put("code", _roomCode.value)
                            put("host", _myNickname.value)
                            put("char", _myChar.value.charId)
                            put("ip", curIp)
                            put("port", tcpPort)
                            put("wsPort", wsPort)
                        }.toString().toByteArray(Charsets.UTF_8)
                        for (bcastAddr in getAllBroadcastAddresses()) {
                            try {
                                ds.send(DatagramPacket(payload, payload.size, bcastAddr, udpBroadcastPort))
                            } catch (_: Exception) {}
                        }
                    } catch (_: Exception) {}
                    Thread.sleep(1200)
                }
            } catch (_: Exception) {}
        }.start()

        // C. Register NSD Bonjour Service (_kon-ddz._tcp.) for cross-platform iOS/Android discovery
        try {
            val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
            nsdManager = nsd
            val info = NsdServiceInfo().apply {
                serviceName = "HTT-${_roomCode.value}-${_myNickname.value.take(8)}"
                serviceType = "_kon-ddz._tcp."
                port = tcpPort
                setAttribute("code", _roomCode.value)
                setAttribute("host", _myNickname.value)
                setAttribute("char", "${_myChar.value.charId}")
                setAttribute("wsPort", "$wsPort")
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

        // D. Start Bluetooth RFCOMM Server + BLE GATT Server for pure Bluetooth face-to-face play
        Thread {
            try {
                val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                val adapter = btMgr?.adapter
                if (adapter != null && adapter.isEnabled) {
                    val bSrv = adapter.listenUsingRfcommWithServiceRecord("KOnDoudizhu_${_roomCode.value}", btSppUuid)
                    btServerSocket = bSrv
                    while (_isHostingRoom.value) {
                        val bSock = bSrv.accept()
                        handleIncomingBluetoothSocket(bSock)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Bluetooth RFCOMM server note: ${e.message}")
            }
        }.start()

        startBleGattServerAndAdvertising()

        _statusBanner.value = "📡 房间 [${_roomCode.value}] 已创建！本机IP: $ip | iOS免重装联机可填 ws://$ip:$wsPort"
        audioMgr.playMascotVoice(_myChar.value)
    }

    @SuppressLint("MissingPermission")
    private fun startBleGattServerAndAdvertising() {
        try {
            val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return
            val adapter = btMgr.adapter ?: return
            if (!adapter.isEnabled) return

            val rxBuffers = mutableMapOf<String, ByteArrayOutputStream>()
            val gattCallback = object : BluetoothGattServerCallback() {
                override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                    if (newState == BluetoothProfile.STATE_CONNECTED) {
                        if (!bleConnectedDevices.contains(device)) bleConnectedDevices.add(device)
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        bleConnectedDevices.remove(device)
                    }
                }

                override fun onCharacteristicWriteRequest(
                    device: BluetoothDevice,
                    requestId: Int,
                    characteristic: BluetoothGattCharacteristic,
                    preparedWrite: Boolean,
                    responseNeeded: Boolean,
                    offset: Int,
                    value: ByteArray?
                ) {
                    if (responseNeeded) {
                        try { gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null) } catch (_: Exception) {}
                    }
                    if (value != null && characteristic.uuid == bleCharUuid) {
                        val buf = rxBuffers.getOrPut(device.address) { ByteArrayOutputStream() }
                        for (b in value) {
                            if (b == '\n'.code.toByte()) {
                                val line = buf.toString("UTF-8").trim()
                                buf.reset()
                                if (line.isNotEmpty()) {
                                    mainHandler.post { handleReceivedPacketJson(line) }
                                }
                            } else {
                                buf.write(b.toInt())
                            }
                        }
                    }
                }
            }

            val server = btMgr.openGattServer(context, gattCallback) ?: return
            val service = BluetoothGattService(bleServiceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val char = BluetoothGattCharacteristic(
                bleCharUuid,
                BluetoothGattCharacteristic.PROPERTY_READ or
                    BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE
            )
            service.addCharacteristic(char)
            server.addService(service)
            gattServer = server
            bleCharacteristic = char

            val advertiser = adapter.bluetoothLeAdvertiser ?: return
            bleAdvertiser = advertiser
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(bleServiceUuid))
                .build()
            advertiser.startAdvertising(settings, data, bleAdvCallback)
        } catch (e: Exception) {
            Log.w(TAG, "BLE GATT server warning: ${e.message}")
        }
    }

    private val bleAdvCallback = object : AdvertiseCallback() {}

    @SuppressLint("MissingPermission")
    fun startScanningFaceToFaceRooms() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) {
            _statusBanner.value = "⚠️ 请先填写房号，未填写无法扫描加入房间！"
            return
        }
        _roomCode.value = code
        stopNetworking()
        refreshLocalIpAddress()
        _isHostingRoom.value = false
        _isScanningRooms.value = true
        _discoveredRooms.value = emptyList()
        acquireWifiMulticastLock()

        // A. Listen for UDP Broadcasts on port 47788
        Thread {
            try {
                val ds = DatagramSocket(null)
                ds.reuseAddress = true
                ds.bind(InetSocketAddress(udpBroadcastPort))
                ds.soTimeout = 1500
                udpSocket = ds
                val buf = ByteArray(2048)
                while (_isScanningRooms.value && !ds.isClosed) {
                    try {
                        val pkt = DatagramPacket(buf, buf.size)
                        ds.receive(pkt)
                        val json = JSONObject(String(pkt.data, 0, pkt.length, Charsets.UTF_8))
                        if (json.optString("type") == "kon_ddz_room") {
                            val hostIp = json.optString("ip").ifBlank { pkt.address.hostAddress ?: "" }
                            val room = DiscoveredP2PRoom(
                                id = "$hostIp:${json.optInt("port", tcpPort)}",
                                roomCode = json.optString("code", "8888"),
                                hostName = "${json.optString("host", "房主")} ($hostIp)",
                                hostCharId = json.optInt("char", 1),
                                hostAddress = hostIp,
                                port = json.optInt("port", tcpPort)
                            )
                            mainHandler.post { addDiscoveredRoom(room) }
                        }
                    } catch (_: SocketTimeoutException) {}
                }
            } catch (e: Exception) {
                Log.w(TAG, "UDP scan note: ${e.message}")
            }
        }.start()

        // B. NSD Bonjour Discovery (_kon-ddz._tcp.) to discover iOS & Android hosts
        try {
            val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
            nsdManager = nsd
            val discL = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(regType: String) {}
                override fun onServiceFound(service: NsdServiceInfo) {
                    if (service.serviceType.contains("kon-ddz")) {
                        nsd.resolveService(service, object : NsdManager.ResolveListener {
                            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                            override fun onServiceResolved(resolved: NsdServiceInfo) {
                                val hostIp = resolved.host?.hostAddress ?: return
                                // If resolved port is dynamic (iOS MCSession), also offer port 47789 cross-play port
                                val targetPort = if (resolved.port == tcpPort) tcpPort else resolved.port
                                val r = DiscoveredP2PRoom(
                                    id = "$hostIp:$targetPort",
                                    roomCode = resolved.serviceName.substringAfter("HTT-").substringBefore("-").ifBlank { _roomCode.value },
                                    hostName = "${resolved.serviceName} ($hostIp)",
                                    hostCharId = 1,
                                    hostAddress = hostIp,
                                    port = targetPort
                                )
                                mainHandler.post { addDiscoveredRoom(r) }
                            }
                        })
                    }
                }
                override fun onServiceLost(service: NsdServiceInfo) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            }
            nsdDiscListener = discL
            nsd.discoverServices("_kon-ddz._tcp.", NsdManager.PROTOCOL_DNS_SD, discL)
        } catch (_: Exception) {}

        // C. Scan BLE GATT Rooms (iOS & Android BLE advertisers)
        try {
            val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val scanner = btMgr?.adapter?.bluetoothLeScanner
            if (scanner != null && btMgr.adapter.isEnabled) {
                bleScanner = scanner
                val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(bleServiceUuid)).build()
                val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
                scanner.startScan(listOf(filter), settings, bleScanCallback)
            }
        } catch (_: Exception) {}

        // D. Also list Paired Bluetooth Devices as Bluetooth P2P Candidates
        try {
            val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = btMgr?.adapter
            if (adapter != null && adapter.isEnabled) {
                adapter.bondedDevices?.forEach { dev ->
                    addDiscoveredRoom(
                        DiscoveredP2PRoom(
                            id = "bt_${dev.address}",
                            roomCode = _roomCode.value,
                            hostName = "${dev.name ?: "蓝牙设备"} (蓝牙直连)",
                            hostCharId = 2,
                            hostAddress = dev.address,
                            port = 0,
                            isBluetooth = true
                        )
                    )
                }
            }
        } catch (_: Exception) {}

        _statusBanner.value = "🔍 正在通过蓝牙 BLE + P2P Wi-Fi 扫描附近房间（也可直接输入房主IP连接）..."
    }

    private val bleScanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val dev = result.device ?: return
            val name = dev.name ?: result.scanRecord?.deviceName ?: "轻音蓝牙房主"
            val room = DiscoveredP2PRoom(
                id = "ble_${dev.address}",
                roomCode = _roomCode.value,
                hostName = "$name (BLE蓝牙免配对)",
                hostCharId = 1,
                hostAddress = dev.address,
                port = 0,
                isBle = true,
                bleDevice = dev
            )
            mainHandler.post { addDiscoveredRoom(room) }
        }
    }

    private fun addDiscoveredRoom(room: DiscoveredP2PRoom) {
        val cur = _discoveredRooms.value.toMutableList()
        if (cur.none { it.id == room.id }) {
            cur.add(room)
            _discoveredRooms.value = cur
        }
    }

    fun connectDirectToHostIp() {
        val raw = _directConnectIp.value.trim()
        if (raw.isEmpty()) {
            _statusBanner.value = "⚠️ 请先输入房主局域网/热点 IP 地址（例如 192.168.1.100）"
            return
        }
        if (raw.startsWith("ws://") || raw.startsWith("wss://")) {
            _serverUrl.value = raw
            connectOnlineServerRoom()
            return
        }
        val host = raw.substringBefore(":")
        val port = raw.substringAfter(":", "$tcpPort").toIntOrNull() ?: tcpPort
        joinDiscoveredRoom(
            DiscoveredP2PRoom(
                id = "$host:$port",
                roomCode = _roomCode.value,
                hostName = "IP直连 ($host)",
                hostCharId = 1,
                hostAddress = host,
                port = port
            )
        )
    }

    @SuppressLint("MissingPermission")
    fun joinDiscoveredRoom(room: DiscoveredP2PRoom) {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) {
            _statusBanner.value = "⚠️ 请先填写房号再加入房间！"
            return
        }
        if (!room.isBle && !room.isBluetooth && room.roomCode != code) {
            _statusBanner.value = "⚠️ 房号不匹配（您填写的是 $code，该房间房号为 ${room.roomCode}）！"
            return
        }
        _isScanningRooms.value = false
        _isRoomAuthority.value = false
        _statusBanner.value = "🔗 正在加入 [${room.hostName}] 的房间 (${room.roomCode})..."
        Thread {
            try {
                if (room.isBle && room.bleDevice != null) {
                    connectToBleRoom(room.bleDevice)
                } else if (room.isBluetooth) {
                    val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                    val dev = btMgr?.adapter?.getRemoteDevice(room.hostAddress)
                    val sock = dev?.createRfcommSocketToServiceRecord(btSppUuid)
                    sock?.connect()
                    if (sock != null) {
                        btClientSocket = sock
                        attachRawLineChannel(sock.inputStream, sock.outputStream)
                        sendJoinRequestPacket()
                    }
                } else {
                    val sock = Socket()
                    sock.connect(InetSocketAddress(room.hostAddress, room.port), 5000)
                    clientSocket = sock
                    attachRawLineChannel(sock.inputStream, sock.outputStream)
                    sendJoinRequestPacket()
                }
            } catch (e: Exception) {
                mainHandler.post {
                    _statusBanner.value = "⚠️ 加入房间失败 (${e.message})，若对方为原版iOS请在iOS端填本机 ws://${_localIpAddress.value}:$wsPort"
                }
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    private fun connectToBleRoom(device: BluetoothDevice) {
        val rxBuf = ByteArrayOutputStream()
        val gatt = device.connectGatt(context, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    g.requestMtu(247)
                    g.discoverServices()
                }
            }

            override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
                g.discoverServices()
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                val svc = g.getService(bleServiceUuid) ?: return
                val ch = svc.getCharacteristic(bleCharUuid) ?: return
                g.setCharacteristicNotification(ch, true)
                val channel = object : PeerChannel {
                    override fun sendJson(raw: String) {
                        val bytes = (raw + "\n").toByteArray(Charsets.UTF_8)
                        var offset = 0
                        while (offset < bytes.size) {
                            val end = minOf(offset + 180, bytes.size)
                            ch.value = bytes.copyOfRange(offset, end)
                            g.writeCharacteristic(ch)
                            offset = end
                            Thread.sleep(18)
                        }
                    }
                    override fun close() {
                        try { g.close() } catch (_: Exception) {}
                    }
                }
                activeChannels.add(channel)
                sendJoinRequestPacket()
            }

            @Deprecated("Deprecated in Java")
            override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                val value = characteristic.value ?: return
                for (b in value) {
                    if (b == '\n'.code.toByte()) {
                        val line = rxBuf.toString("UTF-8").trim()
                        rxBuf.reset()
                        if (line.isNotEmpty()) {
                            mainHandler.post { handleReceivedPacketJson(line) }
                        }
                    } else {
                        rxBuf.write(b.toInt())
                    }
                }
            }
        })
        bleClientGatt = gatt
    }

    // =========================================================================
    // 2. Dual-Protocol Socket Handler (Raw JSON Line + RFC-6455 WebSocket Server for iOS)
    // =========================================================================
    private fun handleAcceptedSocket(sock: Socket) {
        Thread {
            try {
                val ins = BufferedInputStream(sock.getInputStream())
                val outs = BufferedOutputStream(sock.getOutputStream())
                ins.mark(16)
                val firstBytes = ByteArray(4)
                val n = ins.read(firstBytes)
                ins.reset()
                if (n >= 4 && String(firstBytes, 0, 4, Charsets.US_ASCII) == "GET ") {
                    handleIncomingWebSocketUpgrade(sock, ins, outs)
                } else {
                    attachRawLineChannel(ins, outs)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Accepted socket error: ${e.message}")
            }
        }.start()
    }

    private fun attachRawLineChannel(ins: InputStream, outs: OutputStream) {
        val channel = object : PeerChannel {
            override fun sendJson(raw: String) {
                synchronized(outs) {
                    outs.write((raw + "\n").toByteArray(Charsets.UTF_8))
                    outs.flush()
                }
            }
            override fun close() {
                try { ins.close() } catch (_: Exception) {}
                try { outs.close() } catch (_: Exception) {}
            }
        }
        activeChannels.add(channel)
        Thread {
            try {
                val reader = ins.bufferedReader(Charsets.UTF_8)
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.isNotBlank()) {
                        mainHandler.post { handleReceivedPacketJson(line) }
                    }
                }
            } catch (_: Exception) {
            } finally {
                activeChannels.remove(channel)
            }
        }.start()
    }

    private fun handleIncomingWebSocketUpgrade(sock: Socket, ins: InputStream, outs: OutputStream) {
        try {
            // Read HTTP Upgrade headers byte-by-byte until \r\n\r\n so we never over-read WebSocket frames!
            val headerBuf = ByteArrayOutputStream()
            var state = 0
            while (state < 4) {
                val b = ins.read()
                if (b == -1) return
                headerBuf.write(b)
                state = when {
                    state == 0 && b == '\r'.code -> 1
                    state == 1 && b == '\n'.code -> 2
                    state == 2 && b == '\r'.code -> 3
                    state == 3 && b == '\n'.code -> 4
                    b == '\r'.code -> 1
                    else -> 0
                }
            }
            val headersText = headerBuf.toString("UTF-8")
            var secKey = ""
            for (line in headersText.split("\r\n")) {
                if (line.startsWith("Sec-WebSocket-Key:", ignoreCase = true)) {
                    secKey = line.substringAfter(":").trim()
                }
            }
            if (secKey.isEmpty()) return

            val acceptSeed = secKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
            val sha1 = MessageDigest.getInstance("SHA-1").digest(acceptSeed.toByteArray(Charsets.US_ASCII))
            val acceptKey = Base64.encodeToString(sha1, Base64.NO_WRAP)

            val response = "HTTP/1.1 101 Switching Protocols\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Accept: $acceptKey\r\n\r\n"
            synchronized(outs) {
                outs.write(response.toByteArray(Charsets.US_ASCII))
                outs.flush()
            }

            val wsChannel = object : PeerChannel {
                override fun sendJson(raw: String) {
                    val payload = raw.toByteArray(Charsets.UTF_8)
                    synchronized(outs) {
                        // Send as unmasked Text Frame (0x81) which URLSessionWebSocketTask & OkHttp both decode
                        outs.write(0x81)
                        when {
                            payload.size <= 125 -> {
                                outs.write(payload.size)
                            }
                            payload.size <= 65535 -> {
                                outs.write(126)
                                outs.write((payload.size shr 8) and 0xFF)
                                outs.write(payload.size and 0xFF)
                            }
                            else -> {
                                outs.write(127)
                                val len = payload.size.toLong()
                                for (shift in 56 downTo 0 step 8) {
                                    outs.write(((len shr shift) and 0xFF).toInt())
                                }
                            }
                        }
                        outs.write(payload)
                        outs.flush()
                    }
                }
                override fun close() {
                    try { sock.close() } catch (_: Exception) {}
                }
            }
            activeChannels.add(wsChannel)

            // Unmodified iOS KOnDoudizhuManager connects via WebSocket without sending joinRequest.
            // Register iOS peer immediately so iOS <-> Android works with zero iOS modifications!
            mainHandler.postDelayed({
                if (_isHostingRoom.value && _connectedPeerNames.value.isEmpty()) {
                    hasUnmodifiedIosWsPeer = true
                    _connectedPeerNames.value = listOf("iOS 玩家")
                    rebuildLobbySeats()
                    _statusBanner.value = "🎉 iOS 玩家已连入房间！点击下方【立即开始牌局】即可与 iOS 端同步对战"
                    broadcastFullStateSync()
                }
            }, 400L)

            // Read incoming RFC-6455 frames from iOS / Android WebSocket client
            while (!sock.isClosed) {
                val b0 = ins.read()
                val b1 = ins.read()
                if (b0 == -1 || b1 == -1) break
                val opcode = b0 and 0x0F
                if (opcode == 0x08) break // Close frame
                val isMasked = (b1 and 0x80) != 0
                var payloadLen = (b1 and 0x7F).toLong()
                if (payloadLen == 126L) {
                    payloadLen = (((ins.read() and 0xFF) shl 8) or (ins.read() and 0xFF)).toLong()
                } else if (payloadLen == 127L) {
                    payloadLen = 0L
                    for (i in 0 until 8) {
                        payloadLen = (payloadLen shl 8) or (ins.read() and 0xFF).toLong()
                    }
                }
                val maskKey = ByteArray(4)
                if (isMasked) {
                    var readM = 0
                    while (readM < 4) {
                        val r = ins.read(maskKey, readM, 4 - readM)
                        if (r == -1) break
                        readM += r
                    }
                }
                val payload = ByteArray(payloadLen.toInt())
                var readP = 0
                while (readP < payload.size) {
                    val r = ins.read(payload, readP, payload.size - readP)
                    if (r == -1) break
                    readP += r
                }
                if (isMasked) {
                    for (i in payload.indices) {
                        payload[i] = (payload[i].toInt() xor maskKey[i % 4].toInt()).toByte()
                    }
                }
                if (opcode == 0x01 || opcode == 0x02) {
                    val text = String(payload, Charsets.UTF_8).trim()
                    if (text.isNotEmpty()) {
                        mainHandler.post { handleReceivedPacketJson(text) }
                    }
                } else if (opcode == 0x09) {
                    // Reply Pong (0x8A)
                    synchronized(outs) {
                        outs.write(0x8A)
                        outs.write(payload.size)
                        outs.write(payload)
                        outs.flush()
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "WS client disconnected: ${e.message}")
        }
    }

    // =========================================================================
    // 3. Online WebSocket Client (`ws://` or `wss://`)
    // =========================================================================
    fun connectOnlineServerRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) {
            _statusBanner.value = "⚠️ 请先填写房间号，不填写无法进入在线房间！"
            return
        }
        _roomCode.value = code
        val url = _serverUrl.value.trim()
        if (!url.startsWith("ws://") && !url.startsWith("wss://")) {
            _statusBanner.value = "⚠️ 服务器地址无效，请使用 ws:// 或 wss:// 开头"
            return
        }
        stopNetworking()
        _isRoomAuthority.value = true
        _statusBanner.value = "🌐 正在连接服务器 ($url) 房间 [${_roomCode.value}]..."

        val req = Request.Builder().url(url).build()
        webSocket = okHttpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                mainHandler.post {
                    _isServerConnected.value = true
                    _statusBanner.value = "✅ 已连接服务器 ($url)，房间号：${_roomCode.value}"
                    sendJoinRequestPacket()
                }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                mainHandler.post { handleReceivedPacketJson(text) }
            }

            override fun onMessage(ws: WebSocket, bytes: okio.ByteString) {
                mainHandler.post { handleReceivedPacketJson(bytes.utf8()) }
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                mainHandler.post {
                    _isServerConnected.value = false
                    _statusBanner.value = "⚠️ 在线服务器暂未响应，建议在面对面模式创建房间并在iOS端填 ws://${_localIpAddress.value}:$wsPort"
                }
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                mainHandler.post { _isServerConnected.value = false }
            }
        })
    }

    private fun acquireWifiMulticastLock() {
        try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
            if (multicastLock == null) {
                multicastLock = wm.createMulticastLock("kon_ddz_multicast_lock").apply {
                    setReferenceCounted(false)
                }
            }
            if (multicastLock?.isHeld == false) {
                multicastLock?.acquire()
            }
        } catch (_: Exception) {}
    }

    fun leaveRoomAndResetLobby() {
        stopNetworking()
        _phase.value = DoudizhuGamePhase.LOBBY
        _mySeatIndex.value = 0
        rebuildLobbySeats()
        _statusBanner.value = "✨ 🏠 您已离开并关闭当前房间，返回房间大厅"
    }

    @SuppressLint("MissingPermission")
    fun stopNetworking() {
        _isHostingRoom.value = false
        _isScanningRooms.value = false
        _isServerConnected.value = false
        hasUnmodifiedIosWsPeer = false
        _connectedPeerNames.value = emptyList()
        try { tcpServerSocket?.close() } catch (_: Exception) {}
        try { wsServerSocket?.close() } catch (_: Exception) {}
        try { clientSocket?.close() } catch (_: Exception) {}
        try { udpSocket?.close() } catch (_: Exception) {}
        try { btServerSocket?.close() } catch (_: Exception) {}
        try { btClientSocket?.close() } catch (_: Exception) {}
        try { bleAdvertiser?.stopAdvertising(bleAdvCallback) } catch (_: Exception) {}
        try { bleScanner?.stopScan(bleScanCallback) } catch (_: Exception) {}
        try { gattServer?.close() } catch (_: Exception) {}
        try { bleClientGatt?.close() } catch (_: Exception) {}
        try { webSocket?.close(1000, "Leave") } catch (_: Exception) {}
        try { if (multicastLock?.isHeld == true) multicastLock?.release() } catch (_: Exception) {}
        activeChannels.forEach { try { it.close() } catch (_: Exception) {} }
        activeChannels.clear()
        bleConnectedDevices.clear()
        try { nsdRegListener?.let { nsdManager?.unregisterService(it) } } catch (_: Exception) {}
        try { nsdDiscListener?.let { nsdManager?.stopServiceDiscovery(it) } } catch (_: Exception) {}
        nsdRegListener = null
        nsdDiscListener = null
    }

    private fun handleIncomingBluetoothSocket(sock: BluetoothSocket) {
        attachRawLineChannel(sock.inputStream, sock.outputStream)
    }

    @SuppressLint("MissingPermission")
    private fun sendPacketJson(pkt: JSONObject) {
        val raw = pkt.toString()
        Thread {
            activeChannels.forEach { ch ->
                try { ch.sendJson(raw) } catch (_: Exception) {}
            }
            try { webSocket?.send(raw) } catch (_: Exception) {}
            val gSrv = gattServer
            val gChar = bleCharacteristic
            if (gSrv != null && gChar != null && bleConnectedDevices.isNotEmpty()) {
                val bytes = (raw + "\n").toByteArray(Charsets.UTF_8)
                for (dev in bleConnectedDevices) {
                    var offset = 0
                    while (offset < bytes.size) {
                        val end = minOf(offset + 180, bytes.size)
                        gChar.value = bytes.copyOfRange(offset, end)
                        try { gSrv.notifyCharacteristicChanged(dev, gChar, false) } catch (_: Exception) {}
                        offset = end
                        Thread.sleep(15)
                    }
                }
            }
        }.start()
    }

    private fun sendJoinRequestPacket() {
        val pkt = JSONObject().apply {
            put("kind", "joinRequest")
            put("roomCode", _roomCode.value)
            put("senderPeerName", _myNickname.value)
            put("senderCharId", _myChar.value.charId)
        }
        sendPacketJson(pkt)
    }

    private fun syncRulesIfHost() {
        if (isRoomAuthorityVal && (_isHostingRoom.value || _isServerConnected.value)) {
            broadcastFullStateSync()
        }
    }

    private fun broadcastFullStateSync() {
        val pkt = JSONObject().apply {
            put("kind", "stateSync")
            put("roomCode", _roomCode.value)
            put("senderPeerName", _myNickname.value)
            put("senderCharId", _myChar.value.charId)
            put("seats", JSONArray().apply { _seats.value.forEach { put(it.toJson()) } })
            put("holeCards", JSONArray().apply { _holeCards.value.forEach { put(it.toJson()) } })
            put("phase", _phase.value.wireName)
            put("currentTurnSeat", _currentTurnSeat.value)
            put("highestBid", _highestBid.value)
            put("highestBidderSeat", _highestBidderSeat.value)
            put("multiplier", _multiplier.value)
            _lastValidHand.value?.let { put("lastValidHand", it.toJson()) }
            put("lastPlaySeat", _lastPlaySeat.value)
            _winnerSeat.value?.let { put("winnerSeat", it) }
            put("statusBanner", _statusBanner.value)
            put("totalRounds", _totalRounds.value)
            put("currentRound", _currentRound.value)
            put("baseScore", _baseScore.value)
            put("maxMultiplier", _maxMultiplier.value)
            put("turnTimeLimit", _turnTimeLimit.value)
            put("allowCardCounter", _allowCardCounter.value)
            put("aiDifficulty", _aiDifficulty.value.label)
        }
        sendPacketJson(pkt)
    }

    private fun handleReceivedPacketJson(raw: String) {
        try {
            val obj = JSONObject(raw)
            val pktRoom = obj.optString("roomCode").trim()
            val myCode = _roomCode.value.trim()
            if (myCode.isEmpty() || pktRoom != myCode) return
            val kind = obj.optString("kind")
            val senderName = obj.optString("senderPeerName", "玩家")
            val senderCid = obj.optInt("senderCharId", 1)

            when (kind) {
                "joinRequest" -> {
                    if (senderName == _myNickname.value) return
                    hasUnmodifiedIosWsPeer = false
                    val peers = _connectedPeerNames.value.toMutableList()
                    val isNew = !peers.contains(senderName)
                    if (isNew) {
                        peers.add(senderName)
                        _connectedPeerNames.value = peers
                    }
                    val curSeats = _seats.value.toMutableList()
                    val existingSlot = curSeats.indexOfFirst { it.peerDisplayName == senderName }
                    val targetSlot = if (existingSlot != -1) existingSlot else curSeats.indexOfFirst { it.isAI && it.seatIndex > 0 }
                    if (targetSlot != -1) {
                        val ch = CharacterFilter.fiveIndividuals.firstOrNull { it.charId == senderCid } ?: CharacterFilter.MIO
                        curSeats[targetSlot] = DoudizhuPlayerSeat(
                            seatIndex = targetSlot,
                            name = "$senderName (${ch.displayName(currentLang())})",
                            character = ch,
                            isAI = false,
                            peerDisplayName = senderName
                        )
                        _seats.value = curSeats
                        _statusBanner.value = "🎉 [$senderName] 已加入房间！"
                        if (isNew) {
                            sendJoinRequestPacket()
                            if (isRoomAuthorityVal) {
                                mainHandler.postDelayed({ broadcastFullStateSync() }, 150L)
                            }
                        }
                    }
                }
                "stateSync" -> {
                    _isRoomAuthority.value = false
                    val sArr = obj.optJSONArray("seats")
                    var parsedSeats: List<DoudizhuPlayerSeat> = emptyList()
                    if (sArr != null) {
                        parsedSeats = (0 until sArr.length()).map { DoudizhuPlayerSeat.fromJson(sArr.getJSONObject(it)) }
                    }
                    val hArr = obj.optJSONArray("holeCards")
                    if (hArr != null) {
                        _holeCards.value = (0 until hArr.length()).map { DoudizhuCard.fromJson(hArr.getJSONObject(it)) }
                    }
                    val phStr = obj.optString("phase", "lobby")
                    val newPhase = DoudizhuGamePhase.values().firstOrNull { it.wireName == phStr } ?: DoudizhuGamePhase.LOBBY
                    var newTurn = obj.optInt("currentTurnSeat", 0)
                    _highestBid.value = obj.optInt("highestBid", 0)
                    _highestBidderSeat.value = obj.optInt("highestBidderSeat", -1)
                    _multiplier.value = obj.optInt("multiplier", 1)
                    _lastValidHand.value = EvaluatedDoudizhuHand.fromJson(obj.optJSONObject("lastValidHand"))
                    _lastPlaySeat.value = obj.optInt("lastPlaySeat", -1)
                    _winnerSeat.value = if (obj.has("winnerSeat") && !obj.isNull("winnerSeat")) obj.optInt("winnerSeat") else null
                    _statusBanner.value = obj.optString("statusBanner", _statusBanner.value)
                    if (obj.has("totalRounds")) _totalRounds.value = obj.optInt("totalRounds", _totalRounds.value)
                    if (obj.has("currentRound")) _currentRound.value = obj.optInt("currentRound", _currentRound.value)
                    if (obj.has("baseScore")) _baseScore.value = obj.optInt("baseScore", _baseScore.value)
                    if (obj.has("maxMultiplier")) _maxMultiplier.value = obj.optInt("maxMultiplier", _maxMultiplier.value)
                    if (obj.has("turnTimeLimit")) {
                        val ttl = obj.optInt("turnTimeLimit", _turnTimeLimit.value)
                        _turnTimeLimit.value = ttl
                        _turnRemainingSeconds.value = ttl
                    }
                    if (obj.has("allowCardCounter")) _allowCardCounter.value = obj.optBoolean("allowCardCounter", _allowCardCounter.value)
                    if (obj.has("aiDifficulty")) {
                        val lbl = obj.optString("aiDifficulty")
                        DoudizhuAIDifficulty.values().firstOrNull { it.label == lbl }?.let { _aiDifficulty.value = it }
                    }

                    if (hasUnmodifiedIosWsPeer && parsedSeats.size == 3) {
                        // Unmodified iOS sent stateSync (either after starting a round or making a move at Seat 0)
                        val mut = parsedSeats.toMutableList()
                        val wasAndroidOverwrittenByIosLobbyRebuild = mut[1].isAI
                        if (wasAndroidOverwrittenByIosLobbyRebuild) {
                            mut[1] = mut[1].copy(
                                name = "${_myNickname.value} (${_myChar.value.displayName(currentLang())})",
                                character = _myChar.value,
                                isAI = false,
                                peerDisplayName = _myNickname.value
                            )
                            if (newTurn == 1 && newPhase == DoudizhuGamePhase.BIDDING) {
                                newTurn = 0
                            }
                        }
                        _mySeatIndex.value = 1
                        _seats.value = mut
                        _phase.value = newPhase
                        _currentTurnSeat.value = newTurn
                        _turnRemainingSeconds.value = _turnTimeLimit.value
                        if (wasAndroidOverwrittenByIosLobbyRebuild) {
                            broadcastFullStateSync()
                        }
                        return
                    }

                    if (parsedSeats.isNotEmpty()) {
                        _seats.value = parsedSeats
                        val myIdx = parsedSeats.indexOfFirst { it.peerDisplayName == _myNickname.value }
                        if (myIdx >= 0) _mySeatIndex.value = myIdx
                    }
                    _phase.value = newPhase
                    _currentTurnSeat.value = newTurn
                    _turnRemainingSeconds.value = _turnTimeLimit.value
                }
                "bidAction" -> {
                    if (isRoomAuthorityVal) {
                        val seatIdx = _seats.value.indexOfFirst { it.peerDisplayName == senderName }
                        if (seatIdx >= 0) processBid(seatIdx, obj.optInt("bidScore", 0))
                    }
                }
                "playCardsAction" -> {
                    if (isRoomAuthorityVal) {
                        val seatIdx = _seats.value.indexOfFirst { it.peerDisplayName == senderName }
                        val cArr = obj.optJSONArray("playedCards")
                        if (seatIdx >= 0 && cArr != null) {
                            val cards = (0 until cArr.length()).map { DoudizhuCard.fromJson(cArr.getJSONObject(it)) }
                            executePlay(seatIdx, evaluateHand(cards))
                        }
                    }
                }
                "passAction" -> {
                    if (isRoomAuthorityVal) {
                        val seatIdx = _seats.value.indexOfFirst { it.peerDisplayName == senderName }
                        if (seatIdx >= 0) executePass(seatIdx)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Packet parse error: ${e.message}")
        }
    }

    // =========================================================================
    // 4. Game Play & Complete Doudizhu Rules Engine (1:1 with iOS)
    // =========================================================================
    private fun handleTurnTimeout() {
        val actor = _currentTurnSeat.value
        val seat = _seats.value.getOrNull(actor) ?: return
        if (_phase.value == DoudizhuGamePhase.BIDDING) {
            processBid(actor, 0)
        } else if (_phase.value == DoudizhuGamePhase.PLAYING) {
            if (_lastPlaySeat.value == actor || _lastPlaySeat.value == -1) {
                seat.hand.lastOrNull()?.let { c -> executePlay(actor, evaluateHand(listOf(c))) }
            } else {
                executePass(actor)
            }
        }
    }

    fun startNewGame() {
        _isRoomAuthority.value = true
        val deck = createShuffledDeck()
        val p0 = deck.subList(0, 17).sortedWith(compareByDescending<DoudizhuCard> { it.rank }.thenBy { it.suit.ordinal })
        val p1 = deck.subList(17, 34).sortedWith(compareByDescending<DoudizhuCard> { it.rank }.thenBy { it.suit.ordinal })
        val p2 = deck.subList(34, 51).sortedWith(compareByDescending<DoudizhuCard> { it.rank }.thenBy { it.suit.ordinal })
        val hole = deck.subList(51, 54).sortedWith(compareByDescending<DoudizhuCard> { it.rank }.thenBy { it.suit.ordinal })

        val cur = _seats.value
        val s0 = cur.getOrNull(0)?.copy(hand = p0, isLandlord = false, lastPlayed = emptyList(), lastActionText = "", passedLast = false)
            ?: DoudizhuPlayerSeat(0, "${_myNickname.value} (${_myChar.value.displayName(currentLang())})", _myChar.value, false, _myNickname.value, hand = p0)
        val s1 = cur.getOrNull(1)?.copy(hand = p1, isLandlord = false, lastPlayed = emptyList(), lastActionText = "", passedLast = false)
            ?: DoudizhuPlayerSeat(1, "秋山澪 (AI)", CharacterFilter.MIO, true, hand = p1)
        val s2 = cur.getOrNull(2)?.copy(hand = p2, isLandlord = false, lastPlayed = emptyList(), lastActionText = "", passedLast = false)
            ?: DoudizhuPlayerSeat(2, "田井中律 (AI)", CharacterFilter.RITSU, true, hand = p2)

        _seats.value = listOf(s0, s1, s2)
        _holeCards.value = hole
        _selectedCardIds.value = emptySet()
        _highestBid.value = 0
        _highestBidderSeat.value = -1
        _bidsCount.value = 0
        _multiplier.value = 1
        _lastValidHand.value = null
        _lastPlaySeat.value = -1
        _winnerSeat.value = null
        _playedCardsHistory.value = emptyList()
        hintIndex = 0
        // If connected with unmodified iOS peer, start bidding at Android seat (1) or iOS seat (0)
        _currentTurnSeat.value = if (hasUnmodifiedIosWsPeer) 1 else 0
        _turnRemainingSeconds.value = _turnTimeLimit.value
        _phase.value = DoudizhuGamePhase.BIDDING
        _statusBanner.value = "🃏 发牌完成！轮到 [${_seats.value[_currentTurnSeat.value].name}] 叫地主"
        broadcastFullStateSync()
    }

    fun submitBid(bid: Int) {
        val myIdx = _mySeatIndex.value
        if (_phase.value != DoudizhuGamePhase.BIDDING || _currentTurnSeat.value != myIdx) return
        if (myIdx != 0 && !hasUnmodifiedIosWsPeer) {
            sendPacketJson(JSONObject().apply {
                put("kind", "bidAction")
                put("roomCode", _roomCode.value)
                put("senderPeerName", _myNickname.value)
                put("senderCharId", _myChar.value.charId)
                put("bidScore", bid)
            })
            return
        }
        processBid(myIdx, bid)
    }

    private fun processBid(seatIdx: Int, bid: Int) {
        val curSeats = _seats.value.toMutableList()
        curSeats[seatIdx] = curSeats[seatIdx].copy(lastActionText = if (bid == 0) "不叫" else "叫 $bid 分")
        _seats.value = curSeats

        if (bid > _highestBid.value) {
            _highestBid.value = bid
            _highestBidderSeat.value = seatIdx
            _multiplier.value = maxOf(1, bid)
        }
        _bidsCount.value += 1

        if (_highestBid.value == 3 || _bidsCount.value >= 3) {
            val landlord = if (_highestBidderSeat.value >= 0) _highestBidderSeat.value else 0
            assignLandlord(landlord)
        } else {
            val next = (seatIdx + 1) % 3
            _currentTurnSeat.value = next
            _turnRemainingSeconds.value = _turnTimeLimit.value
            val nextSeat = _seats.value[next]
            _statusBanner.value = "✨ 轮到 [${nextSeat.name}] 叫分 (当前最高: ${_highestBid.value}分)"
            broadcastFullStateSync()

            if (nextSeat.isAI) {
                mainHandler.postDelayed({
                    if (_phase.value != DoudizhuGamePhase.BIDDING || _currentTurnSeat.value != next) return@postDelayed
                    val aiScore = evaluateHandStrength(nextSeat.hand)
                    val aiBid = when {
                        aiScore >= 80 && _highestBid.value < 3 -> 3
                        aiScore >= 55 && _highestBid.value < 2 -> 2
                        aiScore >= 35 && _highestBid.value < 1 -> 1
                        else -> 0
                    }
                    processBid(next, aiBid)
                }, 700L)
            }
        }
    }

    private fun assignLandlord(landlordIdx: Int) {
        val updated = _seats.value.map { s ->
            if (s.seatIndex == landlordIdx) {
                val combined = (s.hand + _holeCards.value).sortedWith(compareByDescending<DoudizhuCard> { it.rank }.thenBy { it.suit.ordinal })
                s.copy(isLandlord = true, hand = combined, lastActionText = "🎩 地主")
            } else {
                s.copy(isLandlord = false, lastActionText = "🌾 农民")
            }
        }
        _seats.value = updated
        _currentTurnSeat.value = landlordIdx
        _turnRemainingSeconds.value = _turnTimeLimit.value
        _lastValidHand.value = null
        _lastPlaySeat.value = landlordIdx
        _phase.value = DoudizhuGamePhase.PLAYING
        _statusBanner.value = "👑 [${updated[landlordIdx].name}] 成为地主！获得三张底牌并优先出牌"
        broadcastFullStateSync()

        if (updated[landlordIdx].isAI) {
            runAITurnsIfNeeded()
        }
    }

    fun toggleSelectCard(cardId: String) {
        val cur = _selectedCardIds.value.toMutableSet()
        if (cur.contains(cardId)) cur.remove(cardId) else cur.add(cardId)
        _selectedCardIds.value = cur
    }

    fun clearSelection() {
        _selectedCardIds.value = emptySet()
    }

    fun playSelectedCards() {
        val myIdx = _mySeatIndex.value
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != myIdx) return
        val mySeat = _seats.value[myIdx]
        val chosen = mySeat.hand.filter { _selectedCardIds.value.contains(it.id) }
        if (chosen.isEmpty()) {
            _statusBanner.value = "⚠️ 请先点选要出的扑克牌！"
            return
        }
        val eval = evaluateHand(chosen)
        if (eval.type == DoudizhuHandType.INVALID) {
            _statusBanner.value = "⚠️ 所选牌型不合法（支持单张/对子/三带一/三带二/顺子/连对/飞机/四带二/炸弹/王炸）"
            return
        }
        val prev = if (_lastPlaySeat.value == myIdx || _lastPlaySeat.value == -1) null else _lastValidHand.value
        if (prev != null && !canBeat(eval, prev)) {
            _statusBanner.value = "⚠️ 所选牌型无法大过上家的 [${prev.type.label}]！"
            return
        }
        if (myIdx != 0 && !hasUnmodifiedIosWsPeer) {
            sendPacketJson(JSONObject().apply {
                put("kind", "playCardsAction")
                put("roomCode", _roomCode.value)
                put("senderPeerName", _myNickname.value)
                put("senderCharId", _myChar.value.charId)
                put("playedCards", JSONArray().apply { chosen.forEach { put(it.toJson()) } })
            })
            _selectedCardIds.value = emptySet()
            return
        }
        executePlay(myIdx, eval)
    }

    fun passTurn() {
        val myIdx = _mySeatIndex.value
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != myIdx) return
        if (_lastPlaySeat.value == -1 || _lastPlaySeat.value == myIdx) {
            _statusBanner.value = "⚠️ 当前由您自由领出，不能选择【不出】！"
            return
        }
        if (myIdx != 0 && !hasUnmodifiedIosWsPeer) {
            sendPacketJson(JSONObject().apply {
                put("kind", "passAction")
                put("roomCode", _roomCode.value)
                put("senderPeerName", _myNickname.value)
                put("senderCharId", _myChar.value.charId)
            })
            return
        }
        executePass(myIdx)
    }

    fun hintCards() {
        val myIdx = _mySeatIndex.value
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != myIdx) return
        val myHand = _seats.value[myIdx].hand
        val target = if (_lastPlaySeat.value == myIdx || _lastPlaySeat.value == -1) null else _lastValidHand.value
        val candidates = findHints(myHand, target)
        if (candidates.isNotEmpty()) {
            val chosen = candidates[hintIndex % candidates.size]
            hintIndex += 1
            _selectedCardIds.value = chosen.map { it.id }.toSet()
        } else {
            _statusBanner.value = "💡 没有能大过上家的牌，建议点击【不出】"
        }
    }

    private fun executePlay(seatIdx: Int, eval: EvaluatedDoudizhuHand) {
        if (eval.type == DoudizhuHandType.BOMB || eval.type == DoudizhuHandType.ROCKET) {
            val nextM = _multiplier.value * 2
            _multiplier.value = if (_maxMultiplier.value > 0) minOf(nextM, _maxMultiplier.value) else nextM
        }
        _lastValidHand.value = eval
        _lastPlaySeat.value = seatIdx
        _playedCardsHistory.value = _playedCardsHistory.value + eval.cards
        hintIndex = 0

        val updated = _seats.value.map { s ->
            if (s.seatIndex == seatIdx) {
                val rem = s.hand.filterNot { c -> eval.cards.any { it.id == c.id } }
                s.copy(hand = rem, lastPlayed = eval.cards, lastActionText = eval.type.label, passedLast = false)
            } else {
                s
            }
        }
        _seats.value = updated
        if (seatIdx == _mySeatIndex.value) _selectedCardIds.value = emptySet()

        audioMgr.playMascotVoice(updated[seatIdx].character)

        val winner = updated[seatIdx]
        if (winner.hand.isEmpty()) {
            _winnerSeat.value = seatIdx
            _phase.value = DoudizhuGamePhase.FINISHED
            val winPts = _baseScore.value * _multiplier.value
            val settled = updated.map { s ->
                val isWinSide = (s.isLandlord == winner.isLandlord)
                val delta = if (s.isLandlord) winPts * 2 else winPts
                s.copy(score = s.score + if (isWinSide) delta else -delta)
            }
            _seats.value = settled
            _statusBanner.value = "🎉 本局结束！[${winner.name}] (${if (winner.isLandlord) "🎩 地主" else "🌾 农民"}) 获胜！(倍数 x${_multiplier.value})"
            audioMgr.triggerBirthdaySpecialVoice()
            broadcastFullStateSync()
            return
        }

        val next = (seatIdx + 1) % 3
        _currentTurnSeat.value = next
        _turnRemainingSeconds.value = _turnTimeLimit.value
        _statusBanner.value = "[${updated[seatIdx].name}] 打出 ${eval.type.label}，轮到 [${updated[next].name}]"
        broadcastFullStateSync()
        runAITurnsIfNeeded()
    }

    private fun executePass(seatIdx: Int) {
        val updated = _seats.value.map { s ->
            if (s.seatIndex == seatIdx) s.copy(lastPlayed = emptyList(), lastActionText = "不出", passedLast = true) else s
        }
        _seats.value = updated
        val next = (seatIdx + 1) % 3
        _currentTurnSeat.value = next
        _turnRemainingSeconds.value = _turnTimeLimit.value
        if (_lastPlaySeat.value == next) {
            _lastValidHand.value = null
            _seats.value = _seats.value.map { it.copy(lastPlayed = emptyList(), lastActionText = "", passedLast = false) }
        }
        _statusBanner.value = "[${updated[seatIdx].name}] 选择不出，轮到 [${_seats.value[next].name}] 出牌"
        broadcastFullStateSync()
        runAITurnsIfNeeded()
    }

    private fun runAITurnsIfNeeded() {
        val cur = _currentTurnSeat.value
        val seat = _seats.value.getOrNull(cur) ?: return
        if (_phase.value != DoudizhuGamePhase.PLAYING || !seat.isAI) return

        val delayMs = if (hasUnmodifiedIosWsPeer) 1150L else 750L
        mainHandler.postDelayed({
            if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != cur) return@postDelayed
            val activeSeat = _seats.value.getOrNull(cur) ?: return@postDelayed
            if (!activeSeat.isAI) return@postDelayed
            val target = if (_lastPlaySeat.value == cur || _lastPlaySeat.value == -1) null else _lastValidHand.value
            val hints = findHints(activeSeat.hand, target)
            val chosen = hints.firstOrNull()
            if (chosen != null) {
                val ev = evaluateHand(chosen)
                // Farmer cooperation: don't bomb teammate farmer's high hand
                if (target != null && _lastPlaySeat.value >= 0 && !activeSeat.isLandlord && !_seats.value[_lastPlaySeat.value].isLandlord) {
                    if (ev.type == DoudizhuHandType.BOMB || ev.type == DoudizhuHandType.ROCKET || target.mainRank >= 13) {
                        executePass(cur)
                        return@postDelayed
                    }
                }
                executePlay(cur, ev)
            } else {
                executePass(cur)
            }
        }, delayMs)
    }

    // Complete 1:1 Hint Finder matching iOS DoudizhuHandEvaluator.findHints
    private fun findHints(hand: List<DoudizhuCard>, target: EvaluatedDoudizhuHand?): List<List<DoudizhuCard>> {
        val asc = hand.sortedBy { it.rank }
        if (asc.isEmpty()) return emptyList()
        val byRank = asc.groupBy { it.rank }
        val uniqueRanks = byRank.keys.sorted()
        val hints = mutableListOf<List<DoudizhuCard>>()

        if (target == null || target.type == DoudizhuHandType.INVALID) {
            for (r in uniqueRanks) {
                val arr = byRank[r] ?: continue
                when (arr.size) {
                    1 -> hints.add(arr)
                    2 -> hints.add(arr)
                    3 -> {
                        val kickerR = uniqueRanks.firstOrNull { it != r && (byRank[it]?.isNotEmpty() == true) }
                        if (kickerR != null) hints.add(arr + byRank[kickerR]!!.first()) else hints.add(arr)
                    }
                }
            }
            if (hints.isEmpty()) hints.add(listOf(asc.first()))
            return hints
        }

        if (target.type == DoudizhuHandType.ROCKET) return emptyList()

        when (target.type) {
            DoudizhuHandType.SINGLE -> {
                for (r in uniqueRanks) {
                    if (r > target.mainRank) {
                        byRank[r]?.firstOrNull()?.let { hints.add(listOf(it)) }
                    }
                }
            }
            DoudizhuHandType.PAIR -> {
                for (r in uniqueRanks) {
                    val arr = byRank[r] ?: continue
                    if (r > target.mainRank && arr.size >= 2) hints.add(arr.take(2))
                }
            }
            DoudizhuHandType.TRIPLE -> {
                for (r in uniqueRanks) {
                    val arr = byRank[r] ?: continue
                    if (r > target.mainRank && arr.size >= 3) hints.add(arr.take(3))
                }
            }
            DoudizhuHandType.TRIPLE_ONE -> {
                for (r in uniqueRanks) {
                    val arr = byRank[r] ?: continue
                    if (r > target.mainRank && arr.size >= 3) {
                        val kickerR = uniqueRanks.firstOrNull { it != r }
                        if (kickerR != null) hints.add(arr.take(3) + byRank[kickerR]!!.first())
                    }
                }
            }
            DoudizhuHandType.TRIPLE_PAIR -> {
                for (r in uniqueRanks) {
                    val arr = byRank[r] ?: continue
                    if (r > target.mainRank && arr.size >= 3) {
                        val kickerR = uniqueRanks.firstOrNull { it != r && (byRank[it]?.size ?: 0) >= 2 }
                        if (kickerR != null) hints.add(arr.take(3) + byRank[kickerR]!!.take(2))
                    }
                }
            }
            DoudizhuHandType.STRAIGHT -> {
                val len = target.length
                val validSingleRanks = uniqueRanks.filter { it <= 14 }
                if (validSingleRanks.size >= len) {
                    for (startIdx in 0..(validSingleRanks.size - len)) {
                        val slice = validSingleRanks.subList(startIdx, startIdx + len)
                        if (slice.last() - slice.first() == len - 1 && slice.last() > target.mainRank) {
                            hints.add(slice.map { byRank[it]!!.first() })
                        }
                    }
                }
            }
            DoudizhuHandType.DOUBLE_STRAIGHT -> {
                val pairCount = target.length / 2
                val validPairRanks = uniqueRanks.filter { it <= 14 && (byRank[it]?.size ?: 0) >= 2 }
                if (validPairRanks.size >= pairCount) {
                    for (startIdx in 0..(validPairRanks.size - pairCount)) {
                        val slice = validPairRanks.subList(startIdx, startIdx + pairCount)
                        if (slice.last() - slice.first() == pairCount - 1 && slice.last() > target.mainRank) {
                            val combo = mutableListOf<DoudizhuCard>()
                            slice.forEach { r -> combo.addAll(byRank[r]!!.take(2)) }
                            hints.add(combo)
                        }
                    }
                }
            }
            else -> {}
        }

        for (r in uniqueRanks) {
            val arr = byRank[r] ?: continue
            if (arr.size == 4 && (target.type != DoudizhuHandType.BOMB || r > target.mainRank)) {
                hints.add(arr)
            }
        }
        val j1 = byRank[16]?.firstOrNull()
        val j2 = byRank[17]?.firstOrNull()
        if (j1 != null && j2 != null) {
            hints.add(listOf(j2, j1))
        }
        return hints
    }

    private fun evaluateHandStrength(hand: List<DoudizhuCard>): Int {
        var s = 0
        hand.forEach {
            when (it.rank) {
                17 -> s += 20
                16 -> s += 15
                15 -> s += 10
                14 -> s += 5
            }
        }
        s += hand.groupBy { it.rank }.count { it.value.size == 4 } * 25
        return s
    }

    // Complete 1:1 Hand Evaluator matching iOS DoudizhuHandEvaluator.evaluate
    fun evaluateHand(cards: List<DoudizhuCard>): EvaluatedDoudizhuHand {
        if (cards.isEmpty()) return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, 0, emptyList())
        val counts = cards.groupingBy { it.rank }.eachCount()
        // Order cards by (group frequency desc, rank desc, suit ordinal asc) so triples/quads appear before kickers
        val ordered = cards.sortedWith(
            compareByDescending<DoudizhuCard> { counts[it.rank] ?: 0 }
                .thenByDescending { it.rank }
                .thenBy { it.suit.ordinal }
        )
        val sortedByRankDesc = cards.sortedWith(compareByDescending<DoudizhuCard> { it.rank }.thenBy { it.suit.ordinal })
        val n = cards.size
        val groups = counts.entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenByDescending { it.key })

        if (n == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.SINGLE, sortedByRankDesc[0].rank, 1, ordered)
        if (n == 2) {
            if (sortedByRankDesc[0].rank == 17 && sortedByRankDesc[1].rank == 16) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.ROCKET, 99, 2, sortedByRankDesc)
            }
            if (groups.size == 1 && groups[0].value == 2) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.PAIR, groups[0].key, 2, ordered)
            }
            return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, n, ordered)
        }
        if (n == 3) {
            if (groups.size == 1 && groups[0].value == 3) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE, groups[0].key, 3, ordered)
            }
            return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, n, ordered)
        }
        if (n == 4) {
            if (groups.size == 1 && groups[0].value == 4) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.BOMB, groups[0].key, 4, ordered)
            }
            if (groups.size == 2 && groups[0].value == 3) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE_ONE, groups[0].key, 4, ordered)
            }
            return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, n, ordered)
        }
        if (n == 5 && groups.size == 2 && groups[0].value == 3 && groups[1].value == 2) {
            return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE_PAIR, groups[0].key, 5, ordered)
        }
        if (n == 6 && groups[0].value == 4) {
            return EvaluatedDoudizhuHand(DoudizhuHandType.FOUR_WITH_TWO, groups[0].key, 6, ordered)
        }
        if (n == 8 && groups[0].value == 4 && groups.size == 3 && groups[1].value == 2 && groups[2].value == 2) {
            return EvaluatedDoudizhuHand(DoudizhuHandType.FOUR_WITH_TWO, groups[0].key, 8, ordered)
        }
        if (n >= 5 && groups.size == n) {
            val maxR = sortedByRankDesc.first().rank
            val minR = sortedByRankDesc.last().rank
            if (maxR <= 14 && (maxR - minR == n - 1)) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.STRAIGHT, maxR, n, sortedByRankDesc)
            }
        }
        if (n >= 6 && n % 2 == 0 && groups.size == n / 2 && groups.all { it.value == 2 && it.key <= 14 }) {
            val pairRanks = groups.map { it.key }.sorted()
            if (pairRanks.last() - pairRanks.first() == (n / 2 - 1)) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.DOUBLE_STRAIGHT, pairRanks.last(), n, sortedByRankDesc)
            }
        }
        val tripleRanks = groups.filter { it.value >= 3 && it.key <= 14 }.map { it.key }.sorted()
        if (tripleRanks.size >= 2) {
            var maxConsec = 1
            var bestHigh = tripleRanks.last()
            var curConsec = 1
            for (i in 1 until tripleRanks.size) {
                if (tripleRanks[i] == tripleRanks[i - 1] + 1) {
                    curConsec += 1
                    if (curConsec >= maxConsec) {
                        maxConsec = curConsec
                        bestHigh = tripleRanks[i]
                    }
                } else {
                    curConsec = 1
                }
            }
            if (maxConsec >= 2) {
                if (n == maxConsec * 3 || n == maxConsec * 4 || (n == maxConsec * 5 && groups.count { it.value == 2 } >= maxConsec)) {
                    return EvaluatedDoudizhuHand(DoudizhuHandType.AIRPLANE, bestHigh, n, ordered)
                }
            }
        }
        return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, n, ordered)
    }

    private fun canBeat(challenger: EvaluatedDoudizhuHand, prev: EvaluatedDoudizhuHand): Boolean {
        if (challenger.type == DoudizhuHandType.ROCKET) return true
        if (prev.type == DoudizhuHandType.ROCKET) return false
        if (challenger.type == DoudizhuHandType.BOMB && prev.type != DoudizhuHandType.BOMB) return true
        if (challenger.type != DoudizhuHandType.BOMB && prev.type == DoudizhuHandType.BOMB) return false
        if (challenger.type == prev.type && challenger.length == prev.length) return challenger.mainRank > prev.mainRank
        return false
    }

    private fun createShuffledDeck(): List<DoudizhuCard> {
        val list = ArrayList<DoudizhuCard>(54)
        for (r in 3..15) {
            for (s in listOf(CardSuit.SPADE, CardSuit.HEART, CardSuit.CLUB, CardSuit.DIAMOND)) {
                list.add(DoudizhuCard("${s.symbol}_$r", r, s))
            }
        }
        list.add(DoudizhuCard("joker_16", 16, CardSuit.JOKER))
        list.add(DoudizhuCard("joker_17", 17, CardSuit.JOKER))
        list.shuffle()
        return list
    }
}
