import Foundation
import AVFoundation
import CryptoKit
import CoreLocation
import UIKit

struct VoiceEntry {
    let offset: UInt32
    let length: UInt32
}

enum CharacterMood: String {
    case happy = "开心"
    case excited = "元气"
    case alert = "惊慌提醒"
    case tea = "下午茶"
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate, CLLocationManagerDelegate {
    static let shared = AudioPlayerManager()
    
    // Playback State
    @Published var isPlaying: Bool = false
    @Published var currentPlayingId: Int? = nil
    @Published var currentSpeechBubble: String = "準備OK！出発進行～！"
    @Published var currentMood: CharacterMood = .happy
    
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
        
        var instrumentIcon: String {
            switch self {
            case .yui: return "guitars.fill"
            case .mio: return "music.mic"
            case .ritsu: return "Memories"
            case .mugi: return "pianokeys.inverse"
            case .azusa: return "cat.fill"
            case .all: return "sparkles"
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
                return ["出発進行～！今日も楽しく行こうね！", "あ、ケーキ屋さんかな？右に曲がろうよ～！", "うんたん♪ うんたん♪ 安全運転だよ～！", "わぁ～！スピード出しすぎだよ、危ないよ～！"]
            case .mio:
                return ["よし、ルート確認完了。安全運転で行こう。", "こら唯！よそ見するな、前を見て運転しろ！", "もうすぐ右折だ。ウィンカーを忘れるなよ。", "スピード出しすぎだ！少し落とせってば！"]
            case .ritsu:
                return ["よっしゃー！ドライブスタートだぜ！", "次、左ね！ノリノリで行こうぜ～！", "澪、そんなに怖がるなって～！", "おっと、スピード注意だぞ！安全第一！"]
            case .mugi:
                return ["ふふっ、ドライブとっても楽しみですね♪", "そろそろ休憩しませんか？紅茶とお菓子を用意しましたよ。", "この先、右折になります。お気をつけて♪", "あの…少しスピードが速いみたいです…！"]
            case .azusa:
                return ["先輩！ちゃんと前を見て運転してくださいね！", "この先、左折です。早めの合図をお願いします。", "もう、唯先輩ったらまたお菓子食べて…", "スピード超過です！安全運転をお願いしますっ！"]
            case .all:
                return ["放課後ティータイムナビ、スタート！", "みんなでドライブ、最高だね～！", "安全運転で目的地までレッツゴー！", "お茶とケーキの準備もバッチリだよ♪"]
            }
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var fileHandle: FileHandle?
    private var indexTable: [VoiceEntry] = []
    private var payloadStartOffset: UInt64 = 0
    private var symmetricKey: SymmetricKey
    private var cruiseTimer: Timer?
    private var drivingTimer: Timer?
    
    // CoreLocation
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastOverspeedAlertTime: Date = .distantPast
    
    override init() {
        let keyBytes = KeyConfig.keyBytes
        self.symmetricKey = SymmetricKey(data: Data(keyBytes))
        super.init()
        loadPackageIndex()
        setupLocationManager()
        startDrivingClock()
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
            // Fatigue reminder every 45 minutes (2700 seconds)
            if self.drivingSeconds > 0 && self.drivingSeconds % 2700 == 0 {
                self.triggerTeaTimeReminder()
            }
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
        
        let rawSpeed = max(0.0, loc.speed * 3.6) // m/s to km/h
        DispatchQueue.main.async {
            self.currentSpeedKmh = rawSpeed
            if rawSpeed > self.maxSpeedKmh {
                self.maxSpeedKmh = rawSpeed
            }
            
            // Check overspeed
            if rawSpeed > self.speedLimitKmh {
                if !self.isOverspeeding {
                    self.isOverspeeding = true
                }
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
    
    // MARK: - Voice Package Loading & In-Memory Decryption
    private func loadPackageIndex() {
        guard let url = Bundle.main.url(forResource: "voice_assets", withExtension: "dat") else {
            return
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            self.fileHandle = handle
            guard let magicData = try handle.read(upToCount: 8), magicData.count == 8 else { return }
            guard let countData = try handle.read(upToCount: 4), countData.count == 4 else { return }
            let count = countData.withUnsafeBytes { $0.load(as: UInt32.self) }
            
            self.indexTable.removeAll()
            let tableByteCount = Int(count) * 8
            guard let tableData = try handle.read(upToCount: tableByteCount), tableData.count == tableByteCount else { return }
            
            tableData.withUnsafeBytes { buffer in
                var ptr = buffer.baseAddress!
                for _ in 0..<count {
                    let offset = ptr.load(as: UInt32.self)
                    let length = (ptr + 4).load(as: UInt32.self)
                    self.indexTable.append(VoiceEntry(offset: offset, length: length))
                    ptr += 8
                }
            }
            self.payloadStartOffset = UInt64(8 + 4 + count * 8)
        } catch {
            print("Error loading voice package: \(error)")
        }
    }
    
    func playVoice(id: Int, customQuote: String? = nil, mood: CharacterMood = .happy) {
        guard id >= 1 && id <= indexTable.count else { return }
        guard let handle = fileHandle else { return }
        
        let entry = indexTable[id - 1]
        let absoluteOffset = payloadStartOffset + UInt64(entry.offset)
        
        do {
            try handle.seek(toOffset: absoluteOffset)
            guard let combinedChunk = try handle.read(upToCount: Int(entry.length)), combinedChunk.count == Int(entry.length) else {
                return
            }
            
            let sealedBox = try AES.GCM.SealedBox(combined: combinedChunk)
            let decryptedAudioData = try AES.GCM.open(sealedBox, using: self.symmetricKey)
            
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(data: decryptedAudioData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            let charQuote = customQuote ?? characterForVoiceId(id).sampleQuotes.randomElement() ?? "ボイス再生中 (#\(id))"
            
            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentPlayingId = id
                self.currentMood = mood
                self.currentSpeechBubble = "\(charQuote) [No.\(String(format: "%04d", id))]"
            }
        } catch {
            print("Failed to decrypt or play voice ID \(id): \(error)")
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
            self.currentMood = .happy
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
            if !self.isOverspeeding {
                self.currentMood = .happy
            }
        }
    }
    
    // MARK: - Interactive & Utility Triggers
    func triggerCharacterTap() {
        let range = selectedCharacter.idRange
        let randomId = Int.random(in: range)
        let quote = selectedCharacter.sampleQuotes.prefix(3).randomElement()
        playVoice(id: randomId, customQuote: quote, mood: .excited)
    }
    
    func triggerBanter() {
        let randomId = Int.random(in: 981...1122)
        playVoice(id: randomId, customQuote: "【放課後掛け合い】メンバーの会話イベント発生♪", mood: .excited)
    }
    
    func triggerOverspeedAlert() {
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
        playVoice(id: baseOffset, customQuote: "⚠️ \(alertQuote)", mood: .alert)
    }
    
    func triggerTeaTimeReminder() {
        // Mugi tea time voice range
        let mugiId = Int.random(in: 600...650)
        playVoice(id: mugiId, customQuote: "☕ 運転お疲れ様です♪ 紅茶とお菓子で少し休憩しませんか？", mood: .tea)
    }
    
    func openGaodeMap() {
        // Play departure voice first
        let startId = selectedCharacter.idRange.lowerBound
        playVoice(id: startId, customQuote: "ナビ連携開始！バックグラウンドでサポートするよ♪", mood: .excited)
        
        if let url = URL(string: "iosamap://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else if let webUrl = URL(string: "https://ditu.amap.com/") {
            UIApplication.shared.open(webUrl, options: [:], completionHandler: nil)
        }
    }
    
    // MARK: - Cruise Mode
    func toggleCruiseMode() {
        if isCruiseModeActive {
            stopCruiseMode()
        } else {
            startCruiseMode()
        }
    }
    
    func startCruiseMode() {
        isCruiseModeActive = true
        playRandomCruiseVoice()
        
        cruiseTimer?.invalidate()
        let intervalSeconds = cruiseIntervalMinutes * 60.0
        cruiseTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.playRandomCruiseVoice()
        }
    }
    
    func stopCruiseMode() {
        isCruiseModeActive = false
        cruiseTimer?.invalidate()
        cruiseTimer = nil
    }
    
    func playRandomCruiseVoice() {
        if enableBanter && Int.random(in: 1...3) == 1 {
            triggerBanter()
        } else {
            let range = selectedCharacter.idRange
            let randomId = Int.random(in: range)
            playVoice(id: randomId)
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
