import Foundation
import AVFoundation
import CryptoKit
import CoreLocation
import MapKit
import UIKit
import CoreGraphics

struct VoiceEntry {
    let offset: UInt32
    let length: UInt32
}

struct MascotVoiceEntry {
    let charId: Int
    let offset: UInt32
    let length: UInt32
}

struct QueuedVoiceItem {
    let id: Int
    let bubbleText: String
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "简体"
    case zhHant = "繁體"
    case en = "EN"
    
    var id: String { self.rawValue }
}

enum MascotActionState: String, CaseIterable {
    case idle = "idle"
    case walkLeft = "walkLeft"
    case walkRight = "walkRight"
    case special = "special"
    case grabbed = "grabbed"
    case panic = "panic"
    case teaCake = "teaCake"
    
    func localizedTitle(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.idle, .zhHans): return "待机互动"
        case (.idle, .zhHant): return "待機互動"
        case (.idle, .en): return "Idle"
        case (.walkLeft, .zhHans), (.walkRight, .zhHans): return "散步中"
        case (.walkLeft, .zhHant), (.walkRight, .zhHant): return "散步中"
        case (.walkLeft, .en), (.walkRight, .en): return "Walking"
        case (.special, .zhHans): return "招牌动作"
        case (.special, .zhHant): return "招牌動作"
        case (.special, .en): return "Signature"
        case (.grabbed, .zhHans): return "提起挣扎"
        case (.grabbed, .zhHant): return "提起掙扎"
        case (.grabbed, .en): return "Lifted!"
        case (.panic, .zhHans): return "超速惊慌"
        case (.panic, .zhHant): return "超速驚慌"
        case (.panic, .en): return "Overspeed!"
        case (.teaCake, .zhHans): return "顶蛋糕下午茶"
        case (.teaCake, .zhHant): return "頂蛋糕下午茶"
        case (.teaCake, .en): return "Tea & Cake"
        }
    }
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate, CLLocationManagerDelegate {
    static let shared = AudioPlayerManager()
    
    @Published var language: AppLanguage = .zhHans
    
    // Playback & Voice Queue State (Supports sequential "[300m ahead] + [Turn Right]" combos!)
    @Published var isPlaying: Bool = false
    @Published var currentPlayingId: Int? = nil
    @Published var currentSpeechBubble: String = "準備OK！出発進行～！"
    private var voiceQueue: [(id: Int, quote: String)] = []
    
    // Mascot Animation State
    @Published var mascotAction: MascotActionState = .idle
    @Published var currentSpriteFrame: UIImage? = nil
    @Published var allMemberFrames: [Int: UIImage] = [:]
    @Published var deskSpriteFrame: UIImage? = nil
    @Published var mascotOffsetX: CGFloat = 0.0
    @Published var mascotOffsetY: CGFloat = 0.0
    @Published var stageWalkBound: CGFloat = 65.0
    @Published var memberPositions: [Int: CGSize] = [:]
    @Published var isDraggingMascot: Bool = false
    @Published var draggedMemberId: Int? = nil
    private var animTick: Int = 0
    private var animTimer: Timer?
    private var spriteSheets: [String: CGImage] = [:]
    
    // Cruise & Companion State
    @Published var isCruiseModeActive: Bool = false
    @Published var cruiseIntervalMinutes: Double = 10.0 {
        didSet {
            if isCruiseModeActive { resetCruiseCountdown() }
        }
    }
    @Published var cruiseRemainingSeconds: Int = 600
    @Published var selectedCharacter: CharacterFilter = .all
    @Published var enableBanter: Bool = true
    
    // GPS & HUD Speedometer State
    @Published var userCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
    @Published var currentSpeedKmh: Double = 0.0
    @Published var maxSpeedKmh: Double = 0.0
    @Published var tripDistanceKm: Double = 0.0
    @Published var headingDegrees: Double = 0.0
    @Published var speedLimitKmh: Double = 80.0 {
        didSet {
            if oldValue != speedLimitKmh { triggerSpeedLimitPrompt() }
        }
    }
    @Published var isOverspeeding: Bool = false
    @Published var isGPSSignalPoor: Bool = false
    @Published var gpsAccuracyMeters: Double = -1.0
    @Published var isHUDMirrored: Bool = false
    @Published var drivingSeconds: Int = 0
    
    // Built-In Real-Time Map Navigation State (AutoNavi/MapKit)
    @Published var showMapMode: Bool = true
    @Published var searchQuery: String = ""
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching: Bool = false
    @Published var activeRoute: MKRoute? = nil
    @Published var destinationName: String = ""
    @Published var destinationCoord: CLLocationCoordinate2D? = nil
    @Published var currentStepIndex: Int = 0
    @Published var currentStepInstruction: String = ""
    @Published var distanceToNextStepMeters: Double = 0.0
    @Published var remainingRouteDistanceKm: Double = 0.0
    @Published var remainingRouteMinutes: Int = 0
    @Published var mapTrackingUser: Bool = true
    private var announcedStepThresholds: Set<String> = []
    private var isRecalculatingRoute: Bool = false
    private var demoSimTimer: Timer?
    @Published var isDemoSimulating: Bool = false
    
    enum CharacterFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case yui = "yui"
        case mio = "mio"
        case ritsu = "ritsu"
        case mugi = "mugi"
        case azusa = "azusa"
        
        var id: String { self.rawValue }
        static let fiveIndividuals: [CharacterFilter] = [.yui, .mio, .ritsu, .mugi, .azusa]
        
        var charId: Int {
            switch self {
            case .yui: return 1
            case .mio: return 2
            case .ritsu: return 3
            case .mugi: return 4
            case .azusa: return 5
            case .all: return 0
            }
        }
        
        func displayName(_ lang: AppLanguage) -> String {
            switch (self, lang) {
            case (.all, .zhHans): return "五人同台"
            case (.all, .zhHant): return "五人同台"
            case (.all, .en): return "All 5 HTT"
            case (.yui, .zhHans), (.yui, .zhHant): return "平泽唯"
            case (.yui, .en): return "Yui"
            case (.mio, .zhHans), (.mio, .zhHant): return "秋山澪"
            case (.mio, .en): return "Mio"
            case (.ritsu, .zhHans), (.ritsu, .zhHant): return "田井中律"
            case (.ritsu, .en): return "Ritsu"
            case (.mugi, .zhHans), (.mugi, .zhHant): return "琴吹紬"
            case (.mugi, .en): return "Mugi"
            case (.azusa, .zhHans), (.azusa, .zhHant): return "中野梓"
            case (.azusa, .en): return "Azusa"
            }
        }
        
        var mainSheetName: String {
            switch self {
            case .yui, .all: return "yui01"
            case .mio: return "mio01"
            case .ritsu: return "ritsu01"
            case .mugi: return "tsumugi01"
            case .azusa: return "azusa01"
            }
        }
        
        var cakeSheetName: String {
            switch self {
            case .yui, .all: return "yui00"
            case .mio: return "mio00"
            case .ritsu: return "ritsu00"
            case .mugi: return "tsumugi00"
            case .azusa: return "azusa00"
            }
        }
        
        var navBaseId: Int {
            switch self {
            case .yui, .all: return 157
            case .mio: return 301
            case .ritsu: return 445
            case .mugi: return 589
            case .azusa: return 733
            }
        }
        
        var navRange: ClosedRange<Int> {
            let base = navBaseId
            return base...(base + 143)
        }
        
        var menuRange: ClosedRange<Int> {
            switch self {
            case .yui, .all: return 877...923
            case .mio: return 924...970
            case .ritsu: return 971...1017
            case .mugi: return 1018...1064
            case .azusa: return 1065...1111
            }
        }
        
        var bonusId: Int {
            switch self {
            case .yui, .all: return 1112
            case .mio: return 1113
            case .ritsu: return 1114
            case .mugi: return 1115
            case .azusa: return 1116
            }
        }
        
        var verifiedVoiceIds: [Int] {
            if self == .all { return Array(157...1122) }
            return Array(navRange) + Array(menuRange) + [bonusId]
        }
        
        func roleTag(_ lang: AppLanguage) -> String {
            switch (self, lang) {
            case (.yui, .zhHans): return "平泽唯 · 主音吉他 (CV: 丰崎爱生)"
            case (.yui, .zhHant): return "平澤唯 · 主音吉他 (CV: 豐崎愛生)"
            case (.yui, .en): return "Yui Hirasawa · Lead Guitar"
            case (.mio, .zhHans): return "秋山澪 · 贝斯手 (CV: 日笠阳子)"
            case (.mio, .zhHant): return "秋山澪 · 貝斯手 (CV: 日笠陽子)"
            case (.mio, .en): return "Mio Akiyama · Bass"
            case (.ritsu, .zhHans): return "田井中律 · 鼓手部长 (CV: 佐藤聪美)"
            case (.ritsu, .zhHant): return "田井中律 · 鼓手部長 (CV: 佐藤聰美)"
            case (.ritsu, .en): return "Ritsu Tainaka · Drums"
            case (.mugi, .zhHans): return "琴吹紬 · 键盘手 (CV: 寿美菜子)"
            case (.mugi, .zhHant): return "琴吹紬 · 鍵盤手 (CV: 壽美菜子)"
            case (.mugi, .en): return "Tsumugi Kotobuki · Keyboard"
            case (.azusa, .zhHans): return "中野梓 · 节奏吉他 (CV: 竹达彩奈)"
            case (.azusa, .zhHant): return "中野梓 · 節奏吉他 (CV: 竹達彩奈)"
            case (.azusa, .en): return "Azusa Nakano · Rhythm Guitar"
            case (.all, .zhHans): return "放课后茶会 (HTT 五人全员同台)"
            case (.all, .zhHant): return "放學後茶會 (HTT 五人全員同台)"
            case (.all, .en): return "Houkago Tea Time (All 5 Members)"
            }
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var keepAlivePlayer: AVAudioPlayer?
    private var navFileHandle: FileHandle?
    private var navIndexTable: [VoiceEntry] = []
    private var navPayloadStart: UInt64 = 0
    
    private var mascotFileHandle: FileHandle?
    private var mascotVoices: [MascotVoiceEntry] = []
    private var mascotPayloadStart: UInt64 = 0
    
    private var symmetricKey: SymmetricKey
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastValidGPSTime: Date = Date()
    private var lastOverspeedAlertTime: Date = .distantPast
    private var lastGPSAlertTime: Date = .distantPast
    private var drivingTimer: Timer?
    
    override init() {
        let keyBytes = KeyConfig.keyBytes
        self.symmetricKey = SymmetricKey(data: Data(keyBytes))
        super.init()
        loadNavPackageIndex()
        loadMascotAssetsInMemory()
        setupBackgroundKeepAliveAudio()
        setupLocationManager()
        startMasterClock()
        startSpriteAnimator()
    }
    
    func resetPositions() {
        mascotOffsetX = 0.0
        mascotOffsetY = 0.0
        memberPositions.removeAll()
    }
    
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    private func setupBackgroundKeepAliveAudio() {
        let sampleRate: Int32 = 8000
        let numSamples: Int32 = 8000
        let dataSize = numSamples * 2
        let fileSize = 36 + dataSize
        
        var wavHeader = Data()
        wavHeader.append("RIFF".data(using: .ascii)!)
        wavHeader.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavHeader.append("WAVEfmt ".data(using: .ascii)!)
        let fmtChunkSize: Int32 = 16
        let audioFormat: Int16 = 1
        let numChannels: Int16 = 1
        let byteRate: Int32 = sampleRate * 2
        let blockAlign: Int16 = 2
        let bitsPerSample: Int16 = 16
        wavHeader.append(withUnsafeBytes(of: fmtChunkSize.littleEndian) { Data($0) })
        wavHeader.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        wavHeader.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        wavHeader.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavHeader.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavHeader.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavHeader.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        wavHeader.append("data".data(using: .ascii)!)
        wavHeader.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavHeader.append(Data(count: Int(dataSize)))
        
        do {
            keepAlivePlayer = try AVAudioPlayer(data: wavHeader)
            keepAlivePlayer?.numberOfLoops = -1
            keepAlivePlayer?.volume = 0.01
            keepAlivePlayer?.prepareToPlay()
        } catch {
            print("Failed to init keepAlivePlayer: \(error)")
        }
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    private func startMasterClock() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.drivingSeconds += 1
            
            if self.drivingSeconds > 0 && self.drivingSeconds % 2700 == 0 {
                self.triggerTeaTimeReminder()
            }
            
            if self.isCruiseModeActive || self.activeRoute != nil {
                if self.keepAlivePlayer?.isPlaying == false {
                    self.keepAlivePlayer?.play()
                }
            }
            
            if self.isCruiseModeActive {
                if self.cruiseRemainingSeconds > 1 {
                    self.cruiseRemainingSeconds -= 1
                } else {
                    self.cruiseRemainingSeconds = max(10, Int(self.cruiseIntervalMinutes * 60.0))
                    self.playRandomCruiseVoice()
                }
            }
            
            if Date().timeIntervalSince(self.lastValidGPSTime) > 18.0 && !self.isDemoSimulating {
                if !self.isGPSSignalPoor {
                    self.isGPSSignalPoor = true
                    if Date().timeIntervalSince(self.lastGPSAlertTime) > 60.0 {
                        self.lastGPSAlertTime = Date()
                        self.triggerGPSSignalPoorAlert()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.drivingTimer = timer
    }
    
    // MARK: - 1. Load Encrypted RM-500HTT Navigation Voices
    private func loadNavPackageIndex() {
        guard let url = Bundle.main.url(forResource: "voice_assets", withExtension: "dat") else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            self.navFileHandle = handle
            guard let magicData = try handle.read(upToCount: 8), magicData.count == 8 else { return }
            guard let countData = try handle.read(upToCount: 4), countData.count == 4 else { return }
            let count = countData.withUnsafeBytes { $0.load(as: UInt32.self) }
            
            let tableByteCount = Int(count) * 8
            guard let tableData = try handle.read(upToCount: tableByteCount), tableData.count == tableByteCount else { return }
            
            tableData.withUnsafeBytes { buffer in
                var ptr = buffer.baseAddress!
                for _ in 0..<count {
                    let offset = ptr.load(as: UInt32.self)
                    let length = (ptr + 4).load(as: UInt32.self)
                    self.navIndexTable.append(VoiceEntry(offset: offset, length: length))
                    ptr += 8
                }
            }
            self.navPayloadStart = UInt64(8 + 4 + count * 8)
        } catch {
            print("Error loading voice_assets.dat: \(error)")
        }
    }
    
    // MARK: - 2. Load Encrypted Windows Desktop Pet Sprites & Voices
    private func loadMascotAssetsInMemory() {
        guard let url = Bundle.main.url(forResource: "mascot_assets", withExtension: "dat") else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            self.mascotFileHandle = handle
            guard let magic = try handle.read(upToCount: 8), magic.count == 8 else { return }
            guard let counts = try handle.read(upToCount: 8), counts.count == 8 else { return }
            let spriteCount = counts.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
            let voiceCount = counts.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            
            var spriteMeta: [(String, UInt32, UInt32)] = []
            for _ in 0..<spriteCount {
                guard let entryData = try handle.read(upToCount: 40), entryData.count == 40 else { return }
                let nameData = entryData.subdata(in: 0..<32)
                let name = String(bytes: nameData.prefix(while: { $0 != 0 }), encoding: .ascii) ?? ""
                let off = entryData.withUnsafeBytes { $0.load(fromByteOffset: 32, as: UInt32.self) }
                let len = entryData.withUnsafeBytes { $0.load(fromByteOffset: 36, as: UInt32.self) }
                spriteMeta.append((name, off, len))
            }
            
            for _ in 0..<voiceCount {
                guard let vData = try handle.read(upToCount: 12), vData.count == 12 else { return }
                let cid = vData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
                let off = vData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
                let len = vData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
                self.mascotVoices.append(MascotVoiceEntry(charId: Int(cid), offset: off, length: len))
            }
            
            self.mascotPayloadStart = UInt64(16 + spriteCount * 40 + voiceCount * 12)
            
            for (name, off, len) in spriteMeta {
                try handle.seek(toOffset: self.mascotPayloadStart + UInt64(off))
                if let chunk = try handle.read(upToCount: Int(len)), chunk.count == Int(len) {
                    let box = try AES.GCM.SealedBox(combined: chunk)
                    let pngData = try AES.GCM.open(box, using: self.symmetricKey)
                    if let uiImg = UIImage(data: pngData), let cgImg = uiImg.cgImage {
                        self.spriteSheets[name] = cgImg
                    }
                }
            }
            
            if let deskSheet = self.spriteSheets["desk00"],
               let croppedDesk = deskSheet.cropping(to: CGRect(x: 96, y: 0, width: 192, height: 110)) {
                self.deskSpriteFrame = UIImage(cgImage: croppedDesk)
            }
        } catch {
            print("Error decrypting mascot_assets.dat: \(error)")
        }
    }
    
    // MARK: - 3. Real-Time Official K-ON Desktop Pet Sprite Animator
    private func startSpriteAnimator() {
        updateAllSpriteFrames()
        let timer = Timer(timeInterval: 0.16, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animTick += 1
            self.stepMascotBehavior()
            self.updateAllSpriteFrames()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.animTimer = timer
    }
    
    private func stepMascotBehavior() {
        if isDraggingMascot {
            mascotAction = .grabbed
            return
        }
        if isOverspeeding {
            mascotAction = .panic
            return
        }
        
        if mascotAction == .walkLeft {
            mascotOffsetX -= 4.5
            if mascotOffsetX < -stageWalkBound { mascotAction = .walkRight }
        } else if mascotAction == .walkRight {
            mascotOffsetX += 4.5
            if mascotOffsetX > stageWalkBound { mascotAction = .walkLeft }
        }
        
        if animTick % 36 == 0 && mascotAction != .teaCake {
            let choices: [MascotActionState] = [.idle, .walkLeft, .walkRight, .special]
            mascotAction = choices.randomElement() ?? .idle
        }
    }
    
    private func updateAllSpriteFrames() {
        for member in CharacterFilter.fiveIndividuals {
            let phaseTick = animTick + (member.charId * 3)
            let memberAction: MascotActionState
            if isDraggingMascot && (draggedMemberId == nil || draggedMemberId == member.charId) {
                memberAction = .grabbed
            } else if activeRoute != nil && currentSpeedKmh > 3.0 {
                memberAction = .walkRight
            } else {
                memberAction = mascotAction
            }
            if let img = sliceFrame(for: member, action: memberAction, tick: phaseTick) {
                allMemberFrames[member.charId] = img
                if member == selectedCharacter {
                    currentSpriteFrame = img
                }
            }
        }
        if selectedCharacter == .all {
            currentSpriteFrame = allMemberFrames[1]
        }
    }
    
    private func sliceFrame(for char: CharacterFilter, action: MascotActionState, tick: Int) -> UIImage? {
        if action == .teaCake {
            guard let sheet = spriteSheets[char.cakeSheetName] else { return nil }
            let fw = (char == .ritsu) ? 80 : 64
            let fh = 128
            let row: Int
            let col: Int
            switch char {
            case .yui, .mugi, .all: row = 1; col = tick % 4
            case .ritsu: row = 1; col = tick % 2
            case .mio, .azusa: row = 0; col = 0
            }
            if let cropped = sheet.cropping(to: CGRect(x: col * fw, y: row * fh, width: fw, height: fh)) {
                return UIImage(cgImage: cropped)
            }
            return nil
        }
        
        guard let sheet = spriteSheets[char.mainSheetName] else { return nil }
        let fw = (char == .mugi || char == .azusa) ? 112 : 96
        let fh = 96
        var row = 0
        var col = 0
        
        switch action {
        case .idle:
            row = 0; col = isPlaying ? (tick % 4) : ((tick / 2) % 4)
        case .walkLeft:
            row = 1; col = tick % 6
        case .walkRight:
            row = 2; col = tick % 6
        case .grabbed:
            row = 4
            let maxCols = (char == .mio) ? 1 : ((char == .azusa) ? 2 : 4)
            col = tick % maxCols
        case .panic:
            switch char {
            case .yui, .all: row = 4; col = tick % 4
            case .mio: row = 5; col = tick % 2
            case .ritsu: row = 4; col = tick % 4
            case .mugi: row = 3; col = tick % 2
            case .azusa: row = 3; col = tick % 6
            }
        case .special, .teaCake:
            switch char {
            case .yui, .all: row = 6; col = tick % 6
            case .mio: row = 3; col = tick % 2
            case .ritsu: row = 5; col = tick % 4
            case .mugi: row = 5; col = tick % 6
            case .azusa: row = 5; col = tick % 3
            }
        }
        
        if let cropped = sheet.cropping(to: CGRect(x: col * fw, y: row * fh, width: fw, height: fh)) {
            return UIImage(cgImage: cropped)
        }
        return nil
    }
    
    // MARK: - 4. Built-In Destination Search & Real-Time Turn-by-Turn Route Engine
    func searchPlaces(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        req.region = MKCoordinateRegion(center: userCoordinate, latitudinalMeters: 50000, longitudinalMeters: 50000)
        
        MKLocalSearch(request: req).start { [weak self] response, _ in
            DispatchQueue.main.async {
                self?.isSearching = false
                self?.searchResults = response?.mapItems ?? []
            }
        }
    }
    
    func startRouteGuidance(to item: MKMapItem) {
        stopDemoSimulation()
        let destCoord = item.placemark.coordinate
        let destTitle = item.name ?? "目的地"
        calculateAndStartRoute(to: destCoord, title: destTitle)
    }
    
    func calculateAndStartRoute(to destCoord: CLLocationCoordinate2D, title: String, isReroute: Bool = false) {
        destinationCoord = destCoord
        destinationName = title
        
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: userCoordinate))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        req.transportType = .automobile
        req.requestsAlternateRoutes = false
        
        MKDirections(request: req).calculate { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isRecalculatingRoute = false
                guard let route = response?.routes.first else {
                    self.triggerDepartureGreeting()
                    return
                }
                self.activeRoute = route
                self.announcedStepThresholds.removeAll()
                self.keepAlivePlayer?.play()
                
                // Find first meaningful step
                let steps = route.steps
                self.currentStepIndex = steps.count > 1 ? 1 : 0
                if self.currentStepIndex < steps.count {
                    let step = steps[self.currentStepIndex]
                    self.currentStepInstruction = step.instructions.isEmpty ? title : step.instructions
                    self.distanceToNextStepMeters = step.distance
                }
                self.remainingRouteDistanceKm = route.distance / 1000.0
                self.remainingRouteMinutes = max(1, Int(route.expectedTravelTime / 60.0))
                
                if isReroute {
                    let base = self.activeBaseId()
                    let modeOff = self.activeModeOffset()
                    self.playVoice(id: base + modeOff + 43, customQuote: "🔄 リルート完了！新しいルートで案内するよ！")
                } else {
                    // Play Start Route Guidance (m=39) + Traffic Rules (m=47) combo!
                    let base = self.activeBaseId()
                    let modeOff = self.activeModeOffset()
                    self.enqueueVoiceCombo([
                        (base + modeOff + 39, "🗺️ ルート案内を始めるよ！目的地: \(title)"),
                        (base + modeOff + 47, "🚦 実際の交通規制に従って、安全運転してね！")
                    ])
                }
            }
        }
    }
    
    func stopRouteGuidance() {
        stopDemoSimulation()
        activeRoute = nil
        destinationCoord = nil
        destinationName = ""
        currentStepInstruction = ""
        announcedStepThresholds.removeAll()
        let base = activeBaseId()
        let modeOff = activeModeOffset()
        playVoice(id: base + modeOff + 38, customQuote: "🏁 これで音声案内は終了だよ！運転お疲れ様♪")
    }
    
    // Real-Time Turn-by-Turn GPS Step Evaluation
    private func updateNavigationProgress(location: CLLocation) {
        guard let route = activeRoute, !route.steps.isEmpty else { return }
        let steps = route.steps
        guard currentStepIndex < steps.count else { return }
        
        let step = steps[currentStepIndex]
        let stepEndCoord = step.polyline.points()[max(0, step.polyline.pointCount - 1)].coordinate
        let stepEndLoc = CLLocation(latitude: stepEndCoord.latitude, longitude: stepEndCoord.longitude)
        let dist = location.distance(from: stepEndLoc)
        
        self.distanceToNextStepMeters = dist
        self.currentStepInstruction = step.instructions
        
        // Check Final Destination Arrival
        if currentStepIndex == steps.count - 1 && dist <= 40.0 {
            let base = activeBaseId()
            let modeOff = activeModeOffset()
            enqueueVoiceCombo([
                (base + modeOff + 37, "🎉 目的地周辺に到着したよ！(\(destinationName))"),
                (base + modeOff + 38, "✨ これで音声案内は終了だよ！お疲れ様でした♪")
            ])
            activeRoute = nil
            return
        }
        
        // Evaluate Distance Thresholds (1000m -> m=5, 500m -> m=10, 300m -> m=12, 100m -> m=14, 35m -> m=15)
        let thresholds: [(limit: Double, tol: Double, distM: Int, label: String)] = [
            (1000, 90, 5, "およそ1km先"),
            (500, 60, 10, "およそ500m先"),
            (300, 50, 12, "およそ300m先"),
            (100, 35, 14, "およそ100m先"),
            (35, 25, 15, "まもなく")
        ]
        
        for th in thresholds {
            let key = "\(currentStepIndex)_\(th.distM)"
            if abs(dist - th.limit) <= th.tol && !announcedStepThresholds.contains(key) {
                announcedStepThresholds.insert(key)
                let turnM = classifyTurnOffsetM(from: step.instructions)
                let base = activeBaseId()
                let modeOff = activeModeOffset()
                enqueueVoiceCombo([
                    (base + th.distM, "📍 \(th.label) (\(Int(dist))m)"),
                    (base + modeOff + turnM, "↪️ \(step.instructions)")
                ])
                break
            }
        }
        
        // Advance to next step when within 22m of maneuver point
        if dist <= 22.0 && currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
            let nextStep = steps[currentStepIndex]
            currentStepInstruction = nextStep.instructions
        }
        
        // Check Off-Route deviation (>110m from active step end and increasing)
        if dist > step.distance + 140.0 && !isRecalculatingRoute, let dest = destinationCoord {
            isRecalculatingRoute = true
            let base = activeBaseId()
            let modeOff = activeModeOffset()
            playVoice(id: base + modeOff + 36, customQuote: "💦 ルートを外れちゃったよ…リルートするね！")
            calculateAndStartRoute(to: dest, title: destinationName, isReroute: true)
        }
    }
    
    // Map step instruction string (Chinese/English/Japanese) to RM-500HTT exact turn offset m (16..35)
    private func classifyTurnOffsetM(from text: String) -> Int {
        let lower = text.lowercased()
        if lower.contains("调头") || lower.contains("掉头") || lower.contains("u-turn") || lower.contains("u turn") {
            return 21 // Uターンだよ！
        }
        if lower.contains("出口") || lower.contains("驶出") || lower.contains("exit") {
            return 20 // 出口だよ！
        }
        if lower.contains("入口") || lower.contains("驶入") || lower.contains("匯入") || lower.contains("汇入") || lower.contains("merge") || lower.contains("ramp") {
            return 19 // 入口だよ！
        }
        if lower.contains("稍向右") || lower.contains("靠右") || lower.contains("右前方") || lower.contains("slight right") || lower.contains("keep right") {
            return 30 // 斜め右方向だよ！
        }
        if lower.contains("稍向左") || lower.contains("靠左") || lower.contains("左前方") || lower.contains("slight left") || lower.contains("keep left") {
            return 31 // 斜め左方向だよ！
        }
        if lower.contains("右后") || lower.contains("sharp right") {
            return 32 // 斜め右手前方向だよ！
        }
        if lower.contains("左后") || lower.contains("sharp left") {
            return 33 // 斜め左手前方向だよ！
        }
        if lower.contains("右") || lower.contains("right") {
            return 28 // 右方向に行きまーす！
        }
        if lower.contains("左") || lower.contains("left") {
            return 29 // 左方向に行きまーす！
        }
        return 16 // 直進だよ！
    }
    
    // MARK: - 1-Tap Live Demo Navigation Simulator (Works indoors without moving!)
    func toggleDemoSimulation() {
        if isDemoSimulating {
            stopDemoSimulation()
        } else {
            startDemoSimulation()
        }
    }
    
    func startDemoSimulation() {
        stopDemoSimulation()
        isDemoSimulating = true
        destinationName = language == .en ? "Sakuragaoka High Music Room" : "樱丘高中轻音部部室 (模拟导航)"
        currentStepInstruction = language == .en ? "In 300m, Turn Right" : "前方 300 米右转进入樱高大道"
        distanceToNextStepMeters = 300
        currentSpeedKmh = 48.0
        
        let base = activeBaseId()
        let modeOff = activeModeOffset()
        
        // Step 0: Start Route Guidance
        enqueueVoiceCombo([
            (base + modeOff + 39, "🚗 ルート案内を始めるよ！ドライブ楽しみだな〜"),
            (base + 12, "📍 およそ 300m先 (前方300米)"),
            (base + modeOff + 28, "↪️ 右方向に行きまーす！対向車に注意してね！")
        ])
        
        var stepCounter = 0
        let timer = Timer(timeInterval: 9.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isDemoSimulating else { return }
            stepCounter += 1
            let b = self.activeBaseId()
            let mOff = self.activeModeOffset()
            
            // Move simulated coordinate slightly forward
            self.userCoordinate = CLLocationCoordinate2D(
                latitude: self.userCoordinate.latitude + 0.0006,
                longitude: self.userCoordinate.longitude + 0.0006
            )
            self.tripDistanceKm += 0.1
            
            switch stepCounter {
            case 1:
                self.distanceToNextStepMeters = 100
                self.currentStepInstruction = self.language == .en ? "In 100m, Turn Left" : "前方 100 米左转进入商业街"
                self.enqueueVoiceCombo([
                    (b + 14, "📍 およそ 100m先 (前方100米)"),
                    (b + mOff + 29, "↩️ 左方向に行きまーす！巻き込みに注意してね！")
                ])
            case 2:
                self.distanceToNextStepMeters = 30
                self.currentStepInstruction = self.language == .en ? "Soon, Enter Expressway" : "即将驶入高速道路入口"
                self.enqueueVoiceCombo([
                    (b + 15, "📍 まもなく (即将到达路口)"),
                    (b + mOff + 19, "🛣️ 入口だよ！合流に注意してね！")
                ])
            case 3:
                self.distanceToNextStepMeters = 0
                self.currentStepInstruction = self.language == .en ? "Arrived at Destination!" : "已到达终点：轻音部部室！"
                self.enqueueVoiceCombo([
                    (b + mOff + 37, "🎉 目的地周辺に到着したよ！"),
                    (b + mOff + 38, "✨ これで音声案内は終了だよ！お疲れ様♪")
                ])
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                    self.stopDemoSimulation()
                }
            default:
                break
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.demoSimTimer = timer
    }
    
    func stopDemoSimulation() {
        isDemoSimulating = false
        demoSimTimer?.invalidate()
        demoSimTimer = nil
        if activeRoute == nil {
            currentStepInstruction = ""
            distanceToNextStepMeters = 0
            currentSpeedKmh = 0
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        
        DispatchQueue.main.async {
            if !self.isDemoSimulating {
                self.userCoordinate = loc.coordinate
            }
            self.gpsAccuracyMeters = loc.horizontalAccuracy
            
            if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 65.0 {
                if !self.isGPSSignalPoor {
                    self.isGPSSignalPoor = true
                    if Date().timeIntervalSince(self.lastGPSAlertTime) > 45.0 {
                        self.lastGPSAlertTime = Date()
                        self.triggerGPSSignalPoorAlert()
                    }
                }
                return
            } else {
                if self.isGPSSignalPoor {
                    self.isGPSSignalPoor = false
                    self.triggerGPSSignalRecovered()
                }
                self.lastValidGPSTime = Date()
            }
            
            if let prev = self.lastLocation, prev.horizontalAccuracy >= 0 && prev.horizontalAccuracy <= 50 {
                let delta = loc.distance(from: prev)
                if delta > 0.5 && delta < 500 {
                    self.tripDistanceKm += delta / 1000.0
                }
            }
            self.lastLocation = loc
            
            let rawSpeed = max(0.0, loc.speed * 3.6)
            if !self.isDemoSimulating {
                self.currentSpeedKmh = rawSpeed
            }
            if rawSpeed > self.maxSpeedKmh {
                self.maxSpeedKmh = rawSpeed
            }
            
            if rawSpeed > self.speedLimitKmh {
                self.isOverspeeding = true
                if Date().timeIntervalSince(self.lastOverspeedAlertTime) > 20.0 {
                    self.lastOverspeedAlertTime = Date()
                    self.triggerOverspeedAlert()
                }
            } else {
                self.isOverspeeding = false
            }
            
            // Update Real-Time Turn-by-Turn Navigation
            self.updateNavigationProgress(location: loc)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if !self.isGPSSignalPoor && !self.isDemoSimulating {
                self.isGPSSignalPoor = true
                if Date().timeIntervalSince(self.lastGPSAlertTime) > 45.0 {
                    self.lastGPSAlertTime = Date()
                    self.triggerGPSSignalPoorAlert()
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    // MARK: - Sequential Voice Combo Queue & Playback
    func enqueueVoiceCombo(_ items: [(id: Int, quote: String)]) {
        guard !items.isEmpty else { return }
        voiceQueue = Array(items.dropFirst())
        playVoice(id: items[0].id, customQuote: items[0].quote, clearQueue: false)
    }
    
    func playVoice(id: Int, customQuote: String? = nil, clearQueue: Bool = true) {
        if clearQueue { voiceQueue.removeAll() }
        let safeId = (id < 157) ? (157 + (id % 144)) : id
        guard safeId >= 1 && safeId <= navIndexTable.count else { return }
        guard let handle = navFileHandle else { return }
        
        let entry = navIndexTable[safeId - 1]
        let absoluteOffset = navPayloadStart + UInt64(entry.offset)
        
        do {
            try handle.seek(toOffset: absoluteOffset)
            guard let combinedChunk = try handle.read(upToCount: Int(entry.length)), combinedChunk.count == Int(entry.length) else { return }
            let sealedBox = try AES.GCM.SealedBox(combined: combinedChunk)
            let decryptedAudioData = try AES.GCM.open(sealedBox, using: self.symmetricKey)
            
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(data: decryptedAudioData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            let speaker = characterForVoiceId(safeId).displayName(language)
            let text = customQuote ?? defaultQuoteForVoiceId(safeId)
            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentPlayingId = safeId
                self.currentSpeechBubble = "[\(speaker)] \(text) (#\(safeId))"
            }
        } catch {
            print("Failed to play nav voice \(safeId): \(error)")
        }
    }
    
    func playMascotVoice(for character: CharacterFilter? = nil, customQuote: String? = nil) {
        voiceQueue.removeAll()
        guard let handle = mascotFileHandle, !mascotVoices.isEmpty else { return }
        let targetChar = character ?? selectedCharacter
        let matching: [MascotVoiceEntry]
        if targetChar == .all {
            matching = mascotVoices
        } else {
            matching = mascotVoices.filter { $0.charId == targetChar.charId }
        }
        guard let chosen = matching.randomElement() else { return }
        
        do {
            try handle.seek(toOffset: mascotPayloadStart + UInt64(chosen.offset))
            guard let chunk = try handle.read(upToCount: Int(chosen.length)), chunk.count == Int(chosen.length) else { return }
            let box = try AES.GCM.SealedBox(combined: chunk)
            let audioData = try AES.GCM.open(box, using: self.symmetricKey)
            
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            let speakerName = CharacterFilter.fiveIndividuals.first(where: { $0.charId == chosen.charId })?.displayName(language) ?? targetChar.displayName(language)
            let quote = customQuote ?? localizedMascotQuote(for: chosen.charId)
            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentSpeechBubble = "[\(speakerName)] \(quote)"
            }
        } catch {
            print("Error playing mascot voice: \(error)")
        }
    }
    
    func characterForVoiceId(_ id: Int) -> CharacterFilter {
        switch id {
        case 157...300, 877...923, 1112, 1117: return .yui
        case 301...444, 924...970, 1113, 1118: return .mio
        case 445...588, 971...1017, 1114, 1119: return .ritsu
        case 589...732, 1018...1064, 1115, 1120: return .mugi
        case 733...876, 1065...1111, 1116, 1121: return .azusa
        default: return .all
        }
    }
    
    private func defaultQuoteForVoiceId(_ id: Int) -> String {
        switch language {
        case .zhHans: return "放课后茶会原版导航语音播报中♪"
        case .zhHant: return "放學後茶會原版導航語音播報中♪"
        case .en: return "Playing HTT Original Navigation Voice ♪"
        }
    }
    
    private func localizedMascotQuote(for charId: Int) -> String {
        switch (charId, language) {
        case (1, .zhHans): return "うんたん♪ 今日も楽しくドライブしようね！(平泽唯桌宠原声)"
        case (1, .zhHant): return "うんたん♪ 今日も楽しくドライブしようね！(平澤唯桌寵原聲)"
        case (1, .en): return "Untan ♪ Let's have a fun drive today! (Yui Mascot)"
        case (2, .zhHans): return "もう、急に触るなよ…安全運転で行こう！(秋山澪桌宠原声)"
        case (2, .zhHant): return "もう、急に触るなよ…安全運転で行こう！(秋山澪桌寵原聲)"
        case (2, .en): return "H-Hey, don't poke me suddenly... Drive safely! (Mio Mascot)"
        case (3, .zhHans): return "よっしゃー！ノリノリで出発だぜ～！(田井中律桌宠原声)"
        case (3, .zhHant): return "よっしゃー！ノリノリで出発だぜ～！(田井中律桌寵原聲)"
        case (3, .en): return "Alright! Let's hit the road in high spirits! (Ritsu Mascot)"
        case (4, .zhHans): return "ふふっ、紅茶とケーキを用意しましたよ♪ (琴吹紬桌宠原声)"
        case (4, .zhHant): return "ふふっ、紅茶とケーキを用意しましたよ♪ (琴吹紬桌寵原聲)"
        case (4, .en): return "Fufu, I've prepared tea and cake for us ♪ (Mugi Mascot)"
        default:
            switch language {
            case .zhHans: return "先輩！ちゃんと前を見て運転してくださいね！(中野梓桌宠原声)"
            case .zhHant: return "先輩！ちゃんと前を見て運転してくださいね！(中野梓桌寵原聲)"
            case .en: return "Senpai! Please keep your eyes on the road! (Azusa Mascot)"
            }
        }
    }
    
    func stop() {
        voiceQueue.removeAll()
        audioPlayer?.stop()
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if !voiceQueue.isEmpty {
            let nextItem = voiceQueue.removeFirst()
            playVoice(id: nextItem.id, customQuote: nextItem.quote, clearQueue: false)
        } else {
            DispatchQueue.main.async {
                self.isPlaying = false
                self.currentPlayingId = nil
            }
        }
    }
    
    // MARK: - Verified Built-in RM-500HTT Navigation Event Triggers
    private func activeBaseId() -> Int {
        if selectedCharacter == .all {
            return CharacterFilter.fiveIndividuals.randomElement()!.navBaseId
        }
        return selectedCharacter.navBaseId
    }
    
    private func activeModeOffset() -> Int {
        if selectedCharacter == .all { return 96 } // 5-Member Group mode (k=96..143)
        return enableBanter ? 48 : 0               // Duo mode (k=48..95) or Solo mode (k=0..47)
    }
    
    func triggerCharacterTap(member: CharacterFilter? = nil) {
        mascotAction = .special
        playMascotVoice(for: member ?? selectedCharacter)
    }
    
    func triggerDepartureGreeting() {
        mascotAction = .special
        let base = activeBaseId()
        let offsets = (selectedCharacter == .all) ? [135, 142] : [39, 87, 94]
        let chosenId = base + offsets.randomElement()!
        let msg: String
        switch language {
        case .zhHans: msg = "ルート案内を始めるよ！出発進行～！(开始路线引导，出发咯！)"
        case .zhHant: msg = "ルート案内を始めるよ！出発進行～！(開始路線引導，出發囉！)"
        case .en: msg = "Starting route guidance! Let's roll!"
        }
        playVoice(id: chosenId, customQuote: msg)
    }
    
    func triggerBanter() {
        mascotAction = .special
        let base = activeBaseId()
        let banterOffsets = [67, 68, 69, 70, 73, 84, 85, 86, 87, 91, 94, 95, 115, 116, 118, 121, 132, 135, 140, 142, 143]
        let chosenId = Int.random(in: 1...5) == 1 ? Int.random(in: 1112...1122) : (base + banterOffsets.randomElement()!)
        let msg: String
        switch language {
        case .zhHans: msg = "【放課後掛け合い】轻音部多人互动对话彩蛋♪"
        case .zhHant: msg = "【放課後掛け合い】輕音部多人互動對話彩蛋♪"
        case .en: msg = "[HTT Banter] K-ON! Multi-Character Dialogue Event ♪"
        }
        playVoice(id: chosenId, customQuote: msg)
    }
    
    func triggerGPSSignalPoorAlert() {
        let base = activeBaseId()
        let offset = (selectedCharacter == .all) ? 140 : ([44, 92, 140].randomElement()!)
        let msg: String
        switch language {
        case .zhHans: msg = "📡 えっと、GPS信号が… (GPS信号弱/丢失，请检查卫星接收！)"
        case .zhHant: msg = "📡 えっと、GPS信号が… (GPS訊號弱/丟失，請檢查衛星接收！)"
        case .en: msg = "📡 Um, the GPS signal is weak/lost...!"
        }
        playVoice(id: base + offset, customQuote: msg)
    }
    
    func triggerGPSSignalRecovered() {
        let base = activeBaseId()
        let offset = (selectedCharacter == .all) ? 142 : 94
        let msg: String
        switch language {
        case .zhHans: msg = "🛰️ おお！GPS信号、受信しました！(GPS卫星信号已恢复正常！)"
        case .zhHant: msg = "🛰️ おお！GPS信号、受信しました！(GPS衛星訊號已恢復正常！)"
        case .en: msg = "🛰️ GPS signal acquired! Ready to go!"
        }
        playVoice(id: base + offset, customQuote: msg)
    }
    
    func triggerSpeedLimitPrompt() {
        let base = activeBaseId()
        let offset = (selectedCharacter == .all) ? 143 : ([47, 95, 143].randomElement()!)
        let limitInt = Int(speedLimitKmh)
        let msg: String
        switch language {
        case .zhHans: msg = "🚦 実際の交通規制に従って安全運転してね！(当前限速提示: \(limitInt) km/h)"
        case .zhHant: msg = "🚦 実際の交通規制に従って安全運転してね！(當前限速提示: \(limitInt) km/h)"
        case .en: msg = "🚦 Follow traffic rules & speed limit (\(limitInt) km/h)!"
        }
        playVoice(id: base + offset, customQuote: msg)
    }
    
    func triggerOverspeedAlert() {
        mascotAction = .panic
        let base = activeBaseId()
        let offset = [22, 70, 118, 95, 143].randomElement()!
        let limitInt = Int(speedLimitKmh)
        let msg: String
        switch language {
        case .zhHans: msg = "⚠️ 安全運転！スピード注意！(已超速 >\(limitInt) km/h，请减速慢行！)"
        case .zhHant: msg = "⚠️ 安全運転！スピード注意！(已超速 >\(limitInt) km/h，請減速慢行！)"
        case .en: msg = "⚠️ OVERSPEED (> \(limitInt) km/h)! Please slow down!"
        }
        playVoice(id: base + offset, customQuote: msg)
    }
    
    func triggerTeaTimeReminder() {
        mascotAction = .teaCake
        let base = activeBaseId()
        let offset = [73, 121].randomElement()!
        let msg: String
        switch language {
        case .zhHans: msg = "🍰 疲れてるなら休憩しよう♪ (放课后下午茶时间，吃块蛋糕休息一下吧！)"
        case .zhHant: msg = "🍰 疲れてるなら休憩しよう♪ (放學後下午茶時間，吃塊蛋糕休息一下吧！)"
        case .en: msg = "🍰 Tired from driving? Let's take a Tea & Cake break ♪"
        }
        playVoice(id: base + offset, customQuote: msg)
    }
    
    func openGaodeMap() {
        triggerDepartureGreeting()
        if let url = URL(string: "iosamap://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else if let webUrl = URL(string: "https://ditu.amap.com/") {
            UIApplication.shared.open(webUrl, options: [:], completionHandler: nil)
        }
    }
    
    func toggleCruiseMode() {
        if isCruiseModeActive { stopCruiseMode() } else { startCruiseMode() }
    }
    
    func startCruiseMode() {
        configureAudioSession()
        keepAlivePlayer?.play()
        isCruiseModeActive = true
        resetCruiseCountdown()
        playRandomCruiseVoice()
    }
    
    func stopCruiseMode() {
        isCruiseModeActive = false
        if activeRoute == nil {
            keepAlivePlayer?.stop()
        }
    }
    
    func resetCruiseCountdown() {
        cruiseRemainingSeconds = max(10, Int(cruiseIntervalMinutes * 60.0))
    }
    
    func playRandomCruiseVoice() {
        let roll = Int.random(in: 1...4)
        if enableBanter && roll == 1 {
            triggerBanter()
        } else if roll == 2 {
            playMascotVoice()
        } else {
            let pool = selectedCharacter.verifiedVoiceIds
            if let randomId = pool.randomElement() {
                playVoice(id: randomId)
            }
        }
    }
    
    var formattedCruiseCountdown: String {
        let mins = cruiseRemainingSeconds / 60
        let secs = cruiseRemainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    var compassDirectionString: String {
        let dirsZh = ["北 N", "东北 NE", "东 E", "东南 SE", "南 S", "西南 SW", "西 W", "西北 NW"]
        let dirsEn = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((headingDegrees + 22.5) / 45.0) & 7
        return language == .en ? dirsEn[index] : dirsZh[index]
    }
    
    var formattedDrivingTime: String {
        let hrs = drivingSeconds / 3600
        let mins = (drivingSeconds % 3600) / 60
        let secs = drivingSeconds % 60
        return String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }
}
