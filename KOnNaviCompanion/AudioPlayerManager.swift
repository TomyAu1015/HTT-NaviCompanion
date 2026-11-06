import Foundation
import AVFoundation
import CryptoKit
import CoreLocation
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

enum MascotActionState: String, CaseIterable {
    case idle = "待机互动"
    case walkLeft = "向左散步"
    case walkRight = "向右散步"
    case special = "招牌动作"
    case grabbed = "提起挣扎"
    case panic = "超速惊慌"
    case teaCake = "顶蛋糕下午茶"
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate, CLLocationManagerDelegate {
    static let shared = AudioPlayerManager()
    
    // Playback State
    @Published var isPlaying: Bool = false
    @Published var currentPlayingId: Int? = nil
    @Published var currentSpeechBubble: String = "準備OK！出発進行～！(轻点或拖拽桌宠互动)"
    
    // Mascot Animation State
    @Published var mascotAction: MascotActionState = .idle
    @Published var currentSpriteFrame: UIImage? = nil
    @Published var deskSpriteFrame: UIImage? = nil
    @Published var mascotOffsetX: CGFloat = 0.0
    @Published var isDraggingMascot: Bool = false
    private var walkDirection: CGFloat = 1.0
    private var animTick: Int = 0
    private var animTimer: Timer?
    
    // Decrypted Sprite Sheet Cache in RAM (Never written to disk)
    private var spriteSheets: [String: CGImage] = [:]
    
    // Cruise & Companion State
    @Published var isCruiseModeActive: Bool = false
    @Published var cruiseIntervalMinutes: Double = 10.0
    @Published var selectedCharacter: CharacterFilter = .yui
    @Published var enableBanter: Bool = true
    
    // GPS & HUD Speedometer State
    @Published var currentSpeedKmh: Double = 0.0
    @Published var maxSpeedKmh: Double = 0.0
    @Published var tripDistanceKm: Double = 0.0
    @Published var headingDegrees: Double = 0.0
    @Published var speedLimitKmh: Double = 80.0
    @Published var isOverspeeding: Bool = false
    @Published var isHUDMirrored: Bool = false
    @Published var drivingSeconds: Int = 0
    
    enum CharacterFilter: String, CaseIterable, Identifiable {
        case yui = "平泽唯"
        case mio = "秋山澪"
        case ritsu = "田井中律"
        case mugi = "琴吹紬"
        case azusa = "中野梓"
        case all = "全员随机"
        
        var id: String { self.rawValue }
        
        var charId: Int {
            switch self {
            case .yui: return 1
            case .mio: return 2
            case .ritsu: return 3
            case .mugi: return 4
            case .azusa: return 5
            case .all: return 1
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
        
        var idRange: ClosedRange<Int> {
            switch self {
            case .yui: return 1...196
            case .mio: return 197...392
            case .ritsu: return 393...588
            case .mugi: return 589...784
            case .azusa: return 785...980
            case .all: return 1...1122
            }
        }
        
        var roleTag: String {
            switch self {
            case .yui: return "主音吉他 · 丰崎爱生"
            case .mio: return "贝斯手 · 日笠阳子"
            case .ritsu: return "架子鼓 · 佐藤聪美"
            case .mugi: return "键盘手 · 寿美菜子"
            case .azusa: return "节奏吉他 · 竹达彩奈"
            case .all: return "放课后茶会 · 全员合奏"
            }
        }
        
        var sampleQuotes: [String] {
            switch self {
            case .yui:
                return ["出発進行～！今日も楽しく行こうね！", "うんたん♪ うんたん♪ 安全運転だよ～！", "わぁ～！引っ張らないでよ～くすぐったい！", "わぁ～！スピード出しすぎだよ、危ないよ～！"]
            case .mio:
                return ["よし、ルート確認完了。安全運転で行こう。", "こら！急に触るな、びっくりするだろ…！", "もうすぐ右折だ。ウィンカーを忘れるなよ。", "スピード出しすぎだ！少し落とせってば！"]
            case .ritsu:
                return ["よっしゃー！ドライブスタートだぜ！", "おっ、なんだなんだ？構ってほしいのか～？", "澪、そんなに怖がるなって～！", "おっと、スピード注意だぞ！安全第一！"]
            case .mugi:
                return ["ふふっ、ドライブとっても楽しみですね♪", "そろそろ休憩しませんか？紅茶とケーキを用意しましたよ。", "うふふ、くすぐったいですよ～♪", "あの…少しスピードが速いみたいです…！"]
            case .azusa:
                return ["先輩！ちゃんと前を見て運転してくださいね！", "ひゃっ！急に持ち上げないでくださいっ！", "もう、唯先輩ったらまたお菓子食べて…", "スピード超過です！安全運転をお願いしますっ！"]
            case .all:
                return ["放課後ティータイムナビ、スタート！", "みんなでドライブ、最高だね～！", "安全運転で目的地までレッツゴー！", "お茶とケーキの準備もバッチリだよ♪"]
            }
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var navFileHandle: FileHandle?
    private var navIndexTable: [VoiceEntry] = []
    private var navPayloadStart: UInt64 = 0
    
    private var mascotFileHandle: FileHandle?
    private var mascotVoices: [MascotVoiceEntry] = []
    private var mascotPayloadStart: UInt64 = 0
    
    private var symmetricKey: SymmetricKey
    private var cruiseTimer: Timer?
    private var drivingTimer: Timer?
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastOverspeedAlertTime: Date = .distantPast
    
    override init() {
        let keyBytes = KeyConfig.keyBytes
        self.symmetricKey = SymmetricKey(data: Data(keyBytes))
        super.init()
        loadNavPackageIndex()
        loadMascotAssetsInMemory()
        setupLocationManager()
        startDrivingClock()
        startSpriteAnimator()
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
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 2.0
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    private func startDrivingClock() {
        drivingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.drivingSeconds += 1
            if self.drivingSeconds > 0 && self.drivingSeconds % 2700 == 0 {
                self.triggerTeaTimeReminder()
            }
        }
    }
    
    // MARK: - 1. Load Encrypted RM-500HTT Navigation Voices (1,122 voices)
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
    
    // MARK: - 2. Load Encrypted Windows Desktop Pet Sprites (14 sheets) & Voices (137 voices)
    private func loadMascotAssetsInMemory() {
        guard let url = Bundle.main.url(forResource: "mascot_assets", withExtension: "dat") else {
            print("mascot_assets.dat not found")
            return
        }
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
            
            // Decrypt all 14 sprite sheets purely in RAM
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
            
            // Slice initial desk image
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
        updateCurrentSpriteFrame()
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animTick += 1
            self.stepMascotBehavior()
            self.updateCurrentSpriteFrame()
        }
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
        
        // Autonomous desktop pet movement when walking
        if mascotAction == .walkLeft {
            mascotOffsetX -= 5.0
            if mascotOffsetX < -65.0 {
                mascotAction = .walkRight
            }
        } else if mascotAction == .walkRight {
            mascotOffsetX += 5.0
            if mascotOffsetX > 65.0 {
                mascotAction = .walkLeft
            }
        }
        
        // Periodically switch autonomous states every ~35 ticks (~5.5 seconds) if not locked in tea/panic
        if animTick % 36 == 0 && mascotAction != .teaCake {
            if currentSpeedKmh > 5.0 {
                // While driving, alternate between walking and energetic special pose
                let choices: [MascotActionState] = [.walkLeft, .walkRight, .special, .idle]
                mascotAction = choices.randomElement() ?? .idle
            } else {
                let choices: [MascotActionState] = [.idle, .walkLeft, .walkRight, .special]
                mascotAction = choices.randomElement() ?? .idle
            }
        }
    }
    
    private func updateCurrentSpriteFrame() {
        let char = selectedCharacter == .all ? .yui : selectedCharacter
        
        if mascotAction == .teaCake {
            // Use cake-on-head sprite sheet (yui00, mio00, ritsu00, tsumugi00, azusa00)
            guard let sheet = spriteSheets[char.cakeSheetName] else { return }
            let fw = (char == .ritsu) ? 80 : 64
            let fh = 128
            let row: Int
            let col: Int
            switch char {
            case .yui, .mugi, .all:
                row = 1
                col = animTick % 4
            case .ritsu:
                row = 1
                col = animTick % 2
            case .mio, .azusa:
                row = 0
                col = 0
            }
            let rect = CGRect(x: col * fw, y: row * fh, width: fw, height: fh)
            if let cropped = sheet.cropping(to: rect) {
                self.currentSpriteFrame = UIImage(cgImage: cropped)
            }
            return
        }
        
        guard let sheet = spriteSheets[char.mainSheetName] else { return }
        let fw = (char == .mugi || char == .azusa) ? 112 : 96
        let fh = 96
        
        var row = 0
        var col = 0
        
        switch mascotAction {
        case .idle:
            row = 0
            col = isPlaying ? (animTick % 4) : ((animTick / 2) % 4)
        case .walkLeft:
            row = 1
            col = animTick % 6
        case .walkRight:
            row = 2
            col = animTick % 6
        case .grabbed:
            row = 4
            let maxCols = (char == .mio) ? 1 : ((char == .azusa) ? 2 : 4)
            col = animTick % maxCols
        case .panic:
            switch char {
            case .yui, .all:
                row = 4; col = animTick % 4
            case .mio:
                row = 5; col = animTick % 2 // Dizzy with halo!
            case .ritsu:
                row = 4; col = animTick % 4
            case .mugi:
                row = 3; col = animTick % 2
            case .azusa:
                row = 3; col = animTick % 6 // Panicked holding twin-tails!
            }
        case .special, .teaCake:
            switch char {
            case .yui, .all:
                row = 6; col = animTick % 6 // Untan castanets dance!
            case .mio:
                row = 3; col = animTick % 2 // Shy/shivering
            case .ritsu:
                row = 5; col = animTick % 4 // Cheering with both hands!
            case .mugi:
                row = 5; col = animTick % 6 // Happy swaying with pink hearts!
            case .azusa:
                row = 5; col = animTick % 3 // Sitting politely
            }
        }
        
        let rect = CGRect(x: col * fw, y: row * fh, width: fw, height: fh)
        if let cropped = sheet.cropping(to: rect) {
            self.currentSpriteFrame = UIImage(cgImage: cropped)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        if let prev = lastLocation {
            let delta = loc.distance(from: prev)
            if delta > 0 && delta < 500 {
                tripDistanceKm += delta / 1000.0
            }
        }
        lastLocation = loc
        
        let rawSpeed = max(0.0, loc.speed * 3.6)
        DispatchQueue.main.async {
            self.currentSpeedKmh = rawSpeed
            if rawSpeed > self.maxSpeedKmh {
                self.maxSpeedKmh = rawSpeed
            }
            if rawSpeed > self.speedLimitKmh {
                self.isOverspeeding = true
                if Date().timeIntervalSince(self.lastOverspeedAlertTime) > 25.0 {
                    self.lastOverspeedAlertTime = Date()
                    self.triggerOverspeedAlert()
                }
            } else {
                self.isOverspeeding = false
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    // MARK: - Play RM-500HTT Navigation Voice (1..1122)
    func playVoice(id: Int, customQuote: String? = nil) {
        guard id >= 1 && id <= navIndexTable.count else { return }
        guard let handle = navFileHandle else { return }
        
        let entry = navIndexTable[id - 1]
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
            
            let charQuote = customQuote ?? characterForVoiceId(id).sampleQuotes.randomElement() ?? "ナビ音声再生中"
            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentPlayingId = id
                self.currentSpeechBubble = "\(charQuote) [ナビNo.\(String(format: "%04d", id))]"
            }
        } catch {
            print("Failed to play nav voice \(id): \(error)")
        }
    }
    
    // MARK: - Play Official Windows Desktop Pet Voice (137 voices)
    func playMascotVoice(for character: CharacterFilter? = nil, customQuote: String? = nil) {
        guard let handle = mascotFileHandle, !mascotVoices.isEmpty else {
            triggerCharacterTap()
            return
        }
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
            
            let quote = customQuote ?? targetChar.sampleQuotes.randomElement() ?? "デスクトップマスコット音声♪"
            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentSpeechBubble = "【桌宠原声】\(quote)"
            }
        } catch {
            print("Error playing mascot voice: \(error)")
        }
    }
    
    func characterForVoiceId(_ id: Int) -> CharacterFilter {
        switch id {
        case 1...196: return .yui
        case 197...392: return .mio
        case 393...588: return .ritsu
        case 589...784: return .mugi
        case 785...980: return .azusa
        default: return .all
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
        }
    }
    
    // MARK: - Interactive Triggers
    func triggerCharacterTap() {
        mascotAction = .special
        playMascotVoice(customQuote: selectedCharacter.sampleQuotes.first)
    }
    
    func triggerBanter() {
        mascotAction = .special
        let randomId = Int.random(in: 981...1122)
        playVoice(id: randomId, customQuote: "【放課後掛け合い】メンバーの会話イベント発生♪")
    }
    
    func triggerOverspeedAlert() {
        mascotAction = .panic
        let baseOffset: Int
        switch selectedCharacter {
        case .yui: baseOffset = 145
        case .mio: baseOffset = 340
        case .ritsu: baseOffset = 535
        case .mugi: baseOffset = 730
        case .azusa: baseOffset = 925
        case .all: baseOffset = 340
        }
        let alertQuote = selectedCharacter.sampleQuotes.last ?? "スピード注意！"
        playVoice(id: baseOffset, customQuote: "⚠️ \(alertQuote)")
    }
    
    func triggerTeaTimeReminder() {
        mascotAction = .teaCake
        let mugiId = Int.random(in: 600...650)
        playVoice(id: mugiId, customQuote: "🍰 放課後ティータイム♪ ケーキと紅茶で少し休憩しませんか？")
    }
    
    func openGaodeMap() {
        let startId = selectedCharacter.idRange.lowerBound
        playVoice(id: startId, customQuote: "ナビ連携開始！バックグラウンドでサポートするよ♪")
        if let url = URL(string: "iosamap://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else if let webUrl = URL(string: "https://ditu.amap.com/") {
            UIApplication.shared.open(webUrl, options: [:], completionHandler: nil)
        }
    }
    
    // MARK: - Cruise Mode
    func toggleCruiseMode() {
        if isCruiseModeActive { stopCruiseMode() } else { startCruiseMode() }
    }
    
    func startCruiseMode() {
        isCruiseModeActive = true
        playRandomCruiseVoice()
        cruiseTimer?.invalidate()
        cruiseTimer = Timer.scheduledTimer(withTimeInterval: cruiseIntervalMinutes * 60.0, repeats: true) { [weak self] _ in
            self?.playRandomCruiseVoice()
        }
    }
    
    func stopCruiseMode() {
        isCruiseModeActive = false
        cruiseTimer?.invalidate()
        cruiseTimer = nil
    }
    
    func playRandomCruiseVoice() {
        let roll = Int.random(in: 1...4)
        if enableBanter && roll == 1 {
            triggerBanter()
        } else if roll == 2 {
            playMascotVoice()
        } else {
            let range = selectedCharacter.idRange
            playVoice(id: Int.random(in: range))
        }
    }
    
    var compassDirectionString: String {
        let directions = ["北 N", "东北 NE", "东 E", "东南 SE", "南 S", "西南 SW", "西 W", "西北 NW"]
        let index = Int((headingDegrees + 22.5) / 45.0) & 7
        return directions[index]
    }
    
    var formattedDrivingTime: String {
        let hrs = drivingSeconds / 3600
        let mins = (drivingSeconds % 3600) / 60
        let secs = drivingSeconds % 60
        return String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }
}
