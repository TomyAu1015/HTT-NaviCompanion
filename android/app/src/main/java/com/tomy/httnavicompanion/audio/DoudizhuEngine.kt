package com.tomy.httnavicompanion.audio

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.*
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
            val id = obj.optString("id")
            val rank = obj.optInt("rank")
            val sSym = obj.optString("suit", "♠")
            val suit = CardSuit.values().firstOrNull { it.symbol == sSym } ?: CardSuit.SPADE
            return DoudizhuCard(id, rank, suit)
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
    val isBluetooth: Boolean = false
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
    private val tcpPort = 47789
    private val udpBroadcastPort = 47788

    // Network Mode & Server Settings (matches iOS v1.6.3)
    private val _networkMode = MutableStateFlow(DoudizhuNetworkMode.FACE_TO_FACE_P2P)
    val networkMode: StateFlow<DoudizhuNetworkMode> = _networkMode

    private val _serverUrl = MutableStateFlow("ws://psp.azusa.online")
    val serverUrl: StateFlow<String> = _serverUrl

    private val _roomCode = MutableStateFlow("8888")
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

    private val _statusBanner = MutableStateFlow("欢迎来到放课后茶会斗地主！可面对面蓝牙/Wi-Fi开房或连在线服务器")
    val statusBanner: StateFlow<String> = _statusBanner

    private val _playedCardsHistory = MutableStateFlow<List<DoudizhuCard>>(emptyList())
    val playedCardsHistory: StateFlow<List<DoudizhuCard>> = _playedCardsHistory

    // Transport handles
    private var tcpServerSocket: ServerSocket? = null
    private val clientWriters = CopyOnWriteArrayList<PrintWriter>()
    private var clientSocket: Socket? = null
    private var udpSocket: DatagramSocket? = null
    private var btServerSocket: BluetoothServerSocket? = null
    private var btClientSocket: BluetoothSocket? = null
    private var nsdManager: NsdManager? = null
    private var nsdRegListener: NsdManager.RegistrationListener? = null
    private var nsdDiscListener: NsdManager.DiscoveryListener? = null
    private var webSocket: WebSocket? = null
    private val okHttpClient = OkHttpClient()
    private var timerRunnable: Runnable? = null

    init {
        rebuildLobbySeats()
        startTurnTimerLoop()
    }

    private fun startTurnTimerLoop() {
        val r = object : Runnable {
            override fun run() {
                if ((_phase.value == DoudizhuGamePhase.BIDDING || _phase.value == DoudizhuGamePhase.PLAYING) && _turnTimeLimit.value > 0) {
                    if (_turnRemainingSeconds.value > 0) {
                        _turnRemainingSeconds.value -= 1
                    }
                }
                mainHandler.postDelayed(this, 1000L)
            }
        }
        timerRunnable = r
        mainHandler.postDelayed(r, 1000L)
    }

    fun setNetworkMode(mode: DoudizhuNetworkMode) { _networkMode.value = mode }
    fun setServerUrl(url: String) { _serverUrl.value = url }
    fun setRoomCode(code: String) { _roomCode.value = code }
    fun setMyNickname(name: String) { _myNickname.value = name; rebuildLobbySeats() }
    fun setMyCharacter(char: CharacterFilter) {
        _myChar.value = if (char == CharacterFilter.ALL) CharacterFilter.YUI else char
        rebuildLobbySeats()
    }
    fun setTotalRounds(rounds: Int) { _totalRounds.value = rounds }
    fun setBaseScore(score: Int) { _baseScore.value = score }
    fun setMaxMultiplier(maxM: Int) { _maxMultiplier.value = maxM }
    fun setTurnTimeLimit(secs: Int) { _turnTimeLimit.value = secs; _turnRemainingSeconds.value = secs }
    fun setAllowCardCounter(allow: Boolean) { _allowCardCounter.value = allow }
    fun setAIDifficulty(diff: DoudizhuAIDifficulty) { _aiDifficulty.value = diff }

    private fun currentLang(): AppLanguage {
        return try {
            currentLang()
        } catch (_: Throwable) {
            AppLanguage.ZH_HANS
        }
    }

    private fun rebuildLobbySeats() {
        if (_phase.value != DoudizhuGamePhase.LOBBY) return
        val lang = currentLang()
        val aiPool = CharacterFilter.fiveIndividuals.filter { it != _myChar.value }
        val existingPeers = _seats.value.filter { !it.isAI && it.seatIndex != 0 }
        val s0 = DoudizhuPlayerSeat(0, "${_myNickname.value} (${_myChar.value.displayName(lang)})", _myChar.value, isAI = false, peerDisplayName = _myNickname.value)
        val s1 = existingPeers.getOrNull(0) ?: DoudizhuPlayerSeat(1, "${aiPool[0].displayName(lang)} (AI)", aiPool[0], isAI = true)
        val s2 = existingPeers.getOrNull(1) ?: DoudizhuPlayerSeat(2, "${aiPool[1].displayName(lang)} (AI)", aiPool[1], isAI = true)
        _seats.value = listOf(s0, s1, s2)
    }

    // =========================================================================
    // 1. Face-to-Face P2P (Bluetooth RFCOMM + Wi-Fi Direct / LAN NSD + UDP/TCP)
    // =========================================================================
    @SuppressLint("MissingPermission")
    fun startHostingFaceToFaceRoom() {
        stopNetworking()
        _isHostingRoom.value = true
        _isScanningRooms.value = false
        _mySeatIndex.value = 0
        rebuildLobbySeats()

        // A. Start TCP Server for Wi-Fi / Hotspot / P2P Wi-Fi Direct
        Thread {
            try {
                val srv = ServerSocket(tcpPort)
                tcpServerSocket = srv
                while (_isHostingRoom.value && !srv.isClosed) {
                    val sock = srv.accept()
                    handleIncomingSocket(sock)
                }
            } catch (e: Exception) {
                Log.w(TAG, "TCP Server stopped: ${e.message}")
            }
        }.start()

        // B. Start UDP Broadcast Advertiser (every 1.5s so Android & iOS on same Wi-Fi/Hotspot discover instantly)
        Thread {
            try {
                val ds = DatagramSocket()
                ds.broadcast = true
                udpSocket = ds
                val payload = JSONObject().apply {
                    put("type", "kon_ddz_room")
                    put("code", _roomCode.value)
                    put("host", _myNickname.value)
                    put("char", _myChar.value.charId)
                    put("port", tcpPort)
                }.toString().toByteArray(Charsets.UTF_8)
                val bcastAddr = InetAddress.getByName("255.255.255.255")
                while (_isHostingRoom.value && !ds.isClosed) {
                    try {
                        ds.send(DatagramPacket(payload, payload.size, bcastAddr, udpBroadcastPort))
                    } catch (_: Exception) {}
                    Thread.sleep(1500)
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

        // D. Start Bluetooth RFCOMM Server for pure Bluetooth face-to-face play
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
                Log.w(TAG, "Bluetooth server note: ${e.message}")
            }
        }.start()

        _statusBanner.value = "📡 房间 [${_roomCode.value}] 已创建！附近好友通过蓝牙或 P2P Wi-Fi 即可加入"
        audioMgr.playMascotVoice(_myChar.value)
    }

    @SuppressLint("MissingPermission")
    fun startScanningFaceToFaceRooms() {
        stopNetworking()
        _isHostingRoom.value = false
        _isScanningRooms.value = true
        _discoveredRooms.value = emptyList()

        // A. Listen for UDP Broadcasts
        Thread {
            try {
                val ds = DatagramSocket(udpBroadcastPort)
                ds.soTimeout = 2000
                udpSocket = ds
                val buf = ByteArray(1024)
                while (_isScanningRooms.value && !ds.isClosed) {
                    try {
                        val pkt = DatagramPacket(buf, buf.size)
                        ds.receive(pkt)
                        val json = JSONObject(String(pkt.data, 0, pkt.length, Charsets.UTF_8))
                        if (json.optString("type") == "kon_ddz_room") {
                            val room = DiscoveredP2PRoom(
                                id = "${pkt.address.hostAddress}:${json.optInt("port", tcpPort)}",
                                roomCode = json.optString("code", "8888"),
                                hostName = json.optString("host", "房主"),
                                hostCharId = json.optInt("char", 1),
                                hostAddress = pkt.address.hostAddress ?: "",
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
                                val r = DiscoveredP2PRoom(
                                    id = "$hostIp:${resolved.port}",
                                    roomCode = resolved.serviceName.substringAfter("HTT-").substringBefore("-").ifBlank { "8888" },
                                    hostName = resolved.serviceName,
                                    hostCharId = 1,
                                    hostAddress = hostIp,
                                    port = resolved.port
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

        // C. Check Paired Bluetooth Devices as Bluetooth P2P Candidates
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

        _statusBanner.value = "🔍 正在通过蓝牙与 P2P Wi-Fi 扫描附近房间..."
    }

    private fun addDiscoveredRoom(room: DiscoveredP2PRoom) {
        val cur = _discoveredRooms.value.toMutableList()
        if (cur.none { it.id == room.id }) {
            cur.add(room)
            _discoveredRooms.value = cur
        }
    }

    @SuppressLint("MissingPermission")
    fun joinDiscoveredRoom(room: DiscoveredP2PRoom) {
        _isScanningRooms.value = false
        _statusBanner.value = "🔗 正在加入 [${room.hostName}] 的房间 (${room.roomCode})..."
        Thread {
            try {
                if (room.isBluetooth) {
                    val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                    val dev = btMgr?.adapter?.getRemoteDevice(room.hostAddress)
                    val sock = dev?.createRfcommSocketToServiceRecord(btSppUuid)
                    sock?.connect()
                    if (sock != null) {
                        btClientSocket = sock
                        val pw = PrintWriter(sock.outputStream, true)
                        clientWriters.add(pw)
                        sendJoinRequestPacket()
                        listenStream(BufferedReader(InputStreamReader(sock.inputStream)))
                    }
                } else {
                    val sock = Socket(room.hostAddress, room.port)
                    clientSocket = sock
                    val pw = PrintWriter(sock.outputStream, true)
                    clientWriters.add(pw)
                    sendJoinRequestPacket()
                    listenStream(BufferedReader(InputStreamReader(sock.inputStream)))
                }
            } catch (e: Exception) {
                mainHandler.post {
                    _statusBanner.value = "⚠️ 加入房间失败: ${e.message}"
                }
            }
        }.start()
    }

    // =========================================================================
    // 2. Reserved Online WebSocket Server (`ws://psp.azusa.online`)
    // =========================================================================
    fun connectOnlineServerRoom() {
        val url = _serverUrl.value.trim()
        if (!url.startsWith("ws://") && !url.startsWith("wss://")) {
            _statusBanner.value = "⚠️ 服务器地址无效，请使用 ws:// 或 wss:// 开头"
            return
        }
        stopNetworking()
        _statusBanner.value = "🌐 正在连接在线服务器 ($url) 房间 [${_roomCode.value}]..."

        val req = Request.Builder().url(url).build()
        webSocket = okHttpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                mainHandler.post {
                    _isServerConnected.value = true
                    _statusBanner.value = "✅ 已连接在线服务器 ($url)，房间号：${_roomCode.value}"
                    sendJoinRequestPacket()
                }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                mainHandler.post { handleReceivedPacketJson(text) }
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                mainHandler.post {
                    _isServerConnected.value = false
                    _statusBanner.value = "⚠️ 在线服务器连接失败 (${t.message ?: "网络异常"})，可使用面对面联机或AI陪打"
                }
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                mainHandler.post { _isServerConnected.value = false }
            }
        })
    }

    fun leaveRoomAndResetLobby() {
        stopNetworking()
        _phase.value = DoudizhuGamePhase.LOBBY
        _mySeatIndex.value = 0
        rebuildLobbySeats()
        _statusBanner.value = "✨ 🏠 您已离开并关闭当前房间，返回房间大厅"
    }

    fun stopNetworking() {
        _isHostingRoom.value = false
        _isScanningRooms.value = false
        _isServerConnected.value = false
        _connectedPeerNames.value = emptyList()
        try { tcpServerSocket?.close() } catch (_: Exception) {}
        try { clientSocket?.close() } catch (_: Exception) {}
        try { udpSocket?.close() } catch (_: Exception) {}
        try { btServerSocket?.close() } catch (_: Exception) {}
        try { btClientSocket?.close() } catch (_: Exception) {}
        try { webSocket?.close(1000, "Leave") } catch (_: Exception) {}
        clientWriters.clear()
        try { nsdRegListener?.let { nsdManager?.unregisterService(it) } } catch (_: Exception) {}
        try { nsdDiscListener?.let { nsdManager?.stopServiceDiscovery(it) } } catch (_: Exception) {}
        nsdRegListener = null
        nsdDiscListener = null
    }

    private fun handleIncomingSocket(sock: Socket) {
        Thread {
            try {
                val pw = PrintWriter(sock.outputStream, true)
                clientWriters.add(pw)
                listenStream(BufferedReader(InputStreamReader(sock.inputStream)))
            } catch (_: Exception) {}
        }.start()
    }

    private fun handleIncomingBluetoothSocket(sock: BluetoothSocket) {
        Thread {
            try {
                val pw = PrintWriter(sock.outputStream, true)
                clientWriters.add(pw)
                listenStream(BufferedReader(InputStreamReader(sock.inputStream)))
            } catch (_: Exception) {}
        }.start()
    }

    private fun listenStream(reader: BufferedReader) {
        try {
            while (true) {
                val line = reader.readLine() ?: break
                mainHandler.post { handleReceivedPacketJson(line) }
            }
        } catch (_: Exception) {}
    }

    private fun sendPacketJson(pkt: JSONObject) {
        val raw = pkt.toString()
        Thread {
            clientWriters.forEach { pw ->
                try { pw.println(raw) } catch (_: Exception) {}
            }
            try { webSocket?.send(raw) } catch (_: Exception) {}
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

    private fun broadcastFullStateSync() {
        if (!_isHostingRoom.value && _mySeatIndex.value != 0) return
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
        }
        sendPacketJson(pkt)
    }

    private fun handleReceivedPacketJson(raw: String) {
        try {
            val obj = JSONObject(raw)
            if (obj.optString("roomCode") != _roomCode.value) return
            val kind = obj.optString("kind")
            val senderName = obj.optString("senderPeerName", "玩家")
            val senderCid = obj.optInt("senderCharId", 1)

            when (kind) {
                "joinRequest" -> {
                    val peers = _connectedPeerNames.value.toMutableList()
                    if (!peers.contains(senderName)) {
                        peers.add(senderName)
                        _connectedPeerNames.value = peers
                    }
                    // Assign to seat 1 or 2 if currently AI
                    val curSeats = _seats.value.toMutableList()
                    val aiSlot = curSeats.indexOfFirst { it.isAI && it.seatIndex > 0 }
                    if (aiSlot != -1) {
                        val ch = CharacterFilter.fiveIndividuals.firstOrNull { it.charId == senderCid } ?: CharacterFilter.MIO
                        curSeats[aiSlot] = DoudizhuPlayerSeat(
                            seatIndex = aiSlot,
                            name = "$senderName (${ch.displayName(currentLang())})",
                            character = ch,
                            isAI = false,
                            peerDisplayName = senderName
                        )
                        _seats.value = curSeats
                        _statusBanner.value = "🎉 [$senderName] 已加入房间！"
                        broadcastFullStateSync()
                    }
                }
                "stateSync" -> {
                    val sArr = obj.optJSONArray("seats")
                    if (sArr != null) {
                        val parsed = (0 until sArr.length()).map { DoudizhuPlayerSeat.fromJson(sArr.getJSONObject(it)) }
                        _seats.value = parsed
                        val myIdx = parsed.indexOfFirst { it.peerDisplayName == _myNickname.value }
                        if (myIdx >= 0) _mySeatIndex.value = myIdx
                    }
                    val hArr = obj.optJSONArray("holeCards")
                    if (hArr != null) {
                        _holeCards.value = (0 until hArr.length()).map { DoudizhuCard.fromJson(hArr.getJSONObject(it)) }
                    }
                    val phStr = obj.optString("phase", "lobby")
                    _phase.value = DoudizhuGamePhase.values().firstOrNull { it.wireName == phStr } ?: DoudizhuGamePhase.LOBBY
                    _currentTurnSeat.value = obj.optInt("currentTurnSeat", 0)
                    _highestBid.value = obj.optInt("highestBid", 0)
                    _highestBidderSeat.value = obj.optInt("highestBidderSeat", -1)
                    _multiplier.value = obj.optInt("multiplier", 1)
                    _lastValidHand.value = EvaluatedDoudizhuHand.fromJson(obj.optJSONObject("lastValidHand"))
                    _lastPlaySeat.value = obj.optInt("lastPlaySeat", -1)
                    if (obj.has("winnerSeat")) _winnerSeat.value = obj.optInt("winnerSeat")
                    _statusBanner.value = obj.optString("statusBanner", _statusBanner.value)
                }
                "bidAction" -> {
                    if (_isHostingRoom.value || _mySeatIndex.value == 0) {
                        val seatIdx = _seats.value.indexOfFirst { it.peerDisplayName == senderName }
                        if (seatIdx >= 0) processBid(seatIdx, obj.optInt("bidScore", 0))
                    }
                }
                "playCardsAction" -> {
                    if (_isHostingRoom.value || _mySeatIndex.value == 0) {
                        val seatIdx = _seats.value.indexOfFirst { it.peerDisplayName == senderName }
                        val cArr = obj.optJSONArray("playedCards")
                        if (seatIdx >= 0 && cArr != null) {
                            val cards = (0 until cArr.length()).map { DoudizhuCard.fromJson(cArr.getJSONObject(it)) }
                            executePlay(seatIdx, evaluateHand(cards))
                        }
                    }
                }
                "passAction" -> {
                    if (_isHostingRoom.value || _mySeatIndex.value == 0) {
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
    // 3. Game Play & Rules Engine
    // =========================================================================
    fun startNewGame() {
        val deck = createShuffledDeck()
        val p0 = deck.subList(0, 17).sortedByDescending { it.rank * 10 + it.suit.ordinal }
        val p1 = deck.subList(17, 34).sortedByDescending { it.rank * 10 + it.suit.ordinal }
        val p2 = deck.subList(34, 51).sortedByDescending { it.rank * 10 + it.suit.ordinal }
        val hole = deck.subList(51, 54)

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
        _currentTurnSeat.value = 0
        _turnRemainingSeconds.value = _turnTimeLimit.value
        _phase.value = DoudizhuGamePhase.BIDDING
        _statusBanner.value = "✨ 轮到 [${s0.name}] 叫分"
        broadcastFullStateSync()
    }

    fun submitBid(bid: Int) {
        val myIdx = _mySeatIndex.value
        if (_phase.value != DoudizhuGamePhase.BIDDING || _currentTurnSeat.value != myIdx) return
        if (myIdx != 0) {
            sendPacketJson(JSONObject().apply {
                put("kind", "bidAction")
                put("roomCode", _roomCode.value)
                put("senderPeerName", _myNickname.value)
                put("senderCharId", _myChar.value.charId)
                put("bidScore", bid)
            })
            return
        }
        processBid(0, bid)
    }

    private fun processBid(seatIdx: Int, bid: Int) {
        val curSeats = _seats.value.toMutableList()
        curSeats[seatIdx] = curSeats[seatIdx].copy(lastActionText = if (bid == 0) "不叫" else "叫 $bid 分")
        _seats.value = curSeats

        if (bid > _highestBid.value) {
            _highestBid.value = bid
            _highestBidderSeat.value = seatIdx
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
                    val aiScore = evaluateHandStrength(nextSeat.hand)
                    val aiBid = when {
                        aiScore >= 80 && _highestBid.value < 3 -> 3
                        aiScore >= 55 && _highestBid.value < 2 -> 2
                        aiScore >= 35 && _highestBid.value < 1 -> 1
                        else -> 0
                    }
                    processBid(next, aiBid)
                }, 650L)
            }
        }
    }

    private fun assignLandlord(landlordIdx: Int) {
        val updated = _seats.value.map { s ->
            if (s.seatIndex == landlordIdx) {
                val combined = (s.hand + _holeCards.value).sortedByDescending { it.rank * 10 + it.suit.ordinal }
                s.copy(isLandlord = true, hand = combined, lastActionText = "地主")
            } else {
                s.copy(isLandlord = false, lastActionText = "")
            }
        }
        _seats.value = updated
        _currentTurnSeat.value = landlordIdx
        _turnRemainingSeconds.value = _turnTimeLimit.value
        _phase.value = DoudizhuGamePhase.PLAYING
        _statusBanner.value = "👑 地主 [${updated[landlordIdx].name}] 亮底牌出牌！"
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
        val eval = evaluateHand(chosen)
        if (eval.type == DoudizhuHandType.INVALID) {
            _statusBanner.value = "⚠️ 所选牌型不合法，请重新选择！"
            return
        }
        val prev = if (_lastPlaySeat.value == myIdx) null else _lastValidHand.value
        if (prev != null && !canBeat(eval, prev)) {
            _statusBanner.value = "⚠️ 所选牌型打不过上家！"
            return
        }
        if (myIdx != 0) {
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
        executePlay(0, eval)
    }

    fun passTurn() {
        val myIdx = _mySeatIndex.value
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != myIdx) return
        if (_lastPlaySeat.value == -1 || _lastPlaySeat.value == myIdx) {
            _statusBanner.value = "⚠️ 当前你是首家出牌，不能不出！"
            return
        }
        if (myIdx != 0) {
            sendPacketJson(JSONObject().apply {
                put("kind", "passAction")
                put("roomCode", _roomCode.value)
                put("senderPeerName", _myNickname.value)
                put("senderCharId", _myChar.value.charId)
            })
            return
        }
        executePass(0)
    }

    fun hintCards() {
        val myIdx = _mySeatIndex.value
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != myIdx) return
        val myHand = _seats.value[myIdx].hand
        val target = if (_lastPlaySeat.value == myIdx || _lastPlaySeat.value == -1) null else _lastValidHand.value
        val candidate = findBestPlayableHand(myHand, target)
        if (candidate != null) {
            _selectedCardIds.value = candidate.cards.map { it.id }.toSet()
        } else {
            _statusBanner.value = "没有能大过上家的牌，请点击【不出】"
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

        val winner = updated[seatIdx]
        if (winner.hand.isEmpty()) {
            _winnerSeat.value = seatIdx
            _phase.value = DoudizhuGamePhase.FINISHED
            val winPts = _baseScore.value * _multiplier.value * _highestBid.value.coerceAtLeast(1)
            val settled = updated.map { s ->
                val isWinSide = (s.isLandlord == winner.isLandlord)
                val delta = if (s.isLandlord) winPts * 2 else winPts
                s.copy(score = s.score + if (isWinSide) delta else -delta)
            }
            _seats.value = settled
            _statusBanner.value = "🎉 本局结束！${winner.name} (${if (winner.isLandlord) "地主" else "农民"}) 获胜！"
            audioMgr.triggerBirthdaySpecialVoice()
            broadcastFullStateSync()
            return
        }

        val next = (seatIdx + 1) % 3
        _currentTurnSeat.value = next
        _turnRemainingSeconds.value = _turnTimeLimit.value
        _statusBanner.value = "✨ 轮到 [${updated[next].name}] 出牌"
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
        _statusBanner.value = "✨ 轮到 [${_seats.value[next].name}] 出牌"
        broadcastFullStateSync()
        runAITurnsIfNeeded()
    }

    private fun runAITurnsIfNeeded() {
        val cur = _currentTurnSeat.value
        val seat = _seats.value.getOrNull(cur) ?: return
        if (_phase.value != DoudizhuGamePhase.PLAYING || !seat.isAI) return

        mainHandler.postDelayed({
            if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != cur) return@postDelayed
            val target = if (_lastPlaySeat.value == cur || _lastPlaySeat.value == -1) null else _lastValidHand.value
            val play = findBestPlayableHand(seat.hand, target)
            if (play != null) {
                executePlay(cur, play)
            } else {
                executePass(cur)
            }
        }, 700L)
    }

    private fun findBestPlayableHand(hand: List<DoudizhuCard>, target: EvaluatedDoudizhuHand?): EvaluatedDoudizhuHand? {
        val sorted = hand.sortedBy { it.rank }
        if (target == null) {
            val groups = sorted.groupBy { it.rank }
            val pair = groups.values.firstOrNull { it.size == 2 }
            if (pair != null) return evaluateHand(pair)
            return sorted.firstOrNull()?.let { evaluateHand(listOf(it)) }
        }

        val groups = sorted.groupBy { it.rank }
        when (target.type) {
            DoudizhuHandType.SINGLE -> {
                val card = sorted.firstOrNull { it.rank > target.mainRank }
                if (card != null) return evaluateHand(listOf(card))
            }
            DoudizhuHandType.PAIR -> {
                val pair = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 2 }?.value?.take(2)
                if (pair != null) return evaluateHand(pair)
            }
            DoudizhuHandType.TRIPLE -> {
                val tri = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 3 }?.value?.take(3)
                if (tri != null) return evaluateHand(tri)
            }
            DoudizhuHandType.TRIPLE_ONE -> {
                val tri = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 3 }?.value?.take(3)
                val kicker = sorted.firstOrNull { c -> tri != null && c.rank != tri[0].rank }
                if (tri != null && kicker != null) return evaluateHand(tri + kicker)
            }
            DoudizhuHandType.TRIPLE_PAIR -> {
                val tri = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 3 }?.value?.take(3)
                val kickerPair = groups.entries.firstOrNull { it.value.size >= 2 && (tri == null || it.key != tri[0].rank) }?.value?.take(2)
                if (tri != null && kickerPair != null) return evaluateHand(tri + kickerPair)
            }
            else -> {}
        }

        if (target.type != DoudizhuHandType.ROCKET) {
            val minBombRank = if (target.type == DoudizhuHandType.BOMB) target.mainRank else 0
            val bomb = groups.entries.firstOrNull { it.key > minBombRank && it.value.size == 4 }?.value
            if (bomb != null) return evaluateHand(bomb)
            val sj = sorted.firstOrNull { it.rank == 16 }
            val bj = sorted.firstOrNull { it.rank == 17 }
            if (sj != null && bj != null) return evaluateHand(listOf(sj, bj))
        }
        return null
    }

    private fun evaluateHandStrength(hand: List<DoudizhuCard>): Int {
        var s = 0
        hand.forEach {
            if (it.rank == 17) s += 20
            else if (it.rank == 16) s += 15
            else if (it.rank == 15) s += 10
            else if (it.rank == 14) s += 5
        }
        s += hand.groupBy { it.rank }.count { it.value.size == 4 } * 25
        return s
    }

    fun evaluateHand(cards: List<DoudizhuCard>): EvaluatedDoudizhuHand {
        if (cards.isEmpty()) return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, 0, cards)
        val sorted = cards.sortedBy { it.rank }
        val n = sorted.size
        val counts = sorted.groupingBy { it.rank }.eachCount()

        if (n == 2 && sorted[0].rank == 16 && sorted[1].rank == 17) return EvaluatedDoudizhuHand(DoudizhuHandType.ROCKET, 99, 2, sorted)
        if (n == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.SINGLE, sorted[0].rank, 1, sorted)
        if (n == 2 && counts.size == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.PAIR, sorted[0].rank, 2, sorted)
        if (n == 3 && counts.size == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE, sorted[0].rank, 3, sorted)
        if (n == 4 && counts.size == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.BOMB, sorted[0].rank, 4, sorted)
        if (n == 4 && counts.containsValue(3)) {
            val main = counts.entries.first { it.value == 3 }.key
            return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE_ONE, main, 4, sorted)
        }
        if (n == 5 && counts.containsValue(3) && counts.containsValue(2)) {
            val main = counts.entries.first { it.value == 3 }.key
            return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE_PAIR, main, 5, sorted)
        }
        if (n >= 5 && counts.size == n && sorted.last().rank <= 14) {
            if ((0 until n - 1).all { sorted[it + 1].rank == sorted[it].rank + 1 }) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.STRAIGHT, sorted.first().rank, n, sorted)
            }
        }
        if (n >= 6 && n % 2 == 0 && counts.all { it.value == 2 }) {
            val ranks = counts.keys.sorted()
            if (ranks.last() <= 14 && (0 until ranks.size - 1).all { ranks[it + 1] == ranks[it] + 1 }) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.DOUBLE_STRAIGHT, ranks.first(), n, sorted)
            }
        }
        return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, n, sorted)
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
                list.add(DoudizhuCard("${s.name}_$r", r, s))
            }
        }
        list.add(DoudizhuCard("JOKER_16", 16, CardSuit.JOKER))
        list.add(DoudizhuCard("JOKER_17", 17, CardSuit.JOKER))
        list.shuffle()
        return list
    }
}
