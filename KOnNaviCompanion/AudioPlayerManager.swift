import Foundation
import AVFoundation
import CryptoKit

struct VoiceEntry {
    let offset: UInt32
    let length: UInt32
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerManager()
    
    @Published var isPlaying: Bool = false
    @Published var currentPlayingId: Int? = nil
    @Published var isCruiseModeActive: Bool = false
    @Published var cruiseIntervalMinutes: Double = 15.0
    @Published var selectedCruiseCharacter: CharacterFilter = .all
    
    enum CharacterFilter: String, CaseIterable, Identifiable {
        case all = "全员随机"
        case yui = "平泽唯"
        case mio = "秋山澪"
        case ritsu = "田井中律"
        case mugi = "琴吹紬"
        case azusa = "中野梓"
        
        var id: String { self.rawValue }
        
        var idRange: ClosedRange<Int> {
            switch self {
            case .all: return 1...1122
            case .yui: return 1...196
            case .mio: return 197...392
            case .ritsu: return 393...588
            case .mugi: return 589...784
            case .azusa: return 785...980
            }
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var fileHandle: FileHandle?
    private var indexTable: [VoiceEntry] = []
    private var payloadStartOffset: UInt64 = 0
    private var symmetricKey: SymmetricKey
    private var cruiseTimer: Timer?
    
    override init() {
        // Obfuscated key reconstruction
        let keyBytes = KeyConfig.keyBytes
        self.symmetricKey = SymmetricKey(data: Data(keyBytes))
        super.init()
        loadPackageIndex()
    }
    
    // Configure audio session for background playback and mixing with navigation/music
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    private func loadPackageIndex() {
        guard let url = Bundle.main.url(forResource: "voice_assets", withExtension: "dat") else {
            print("Error: voice_assets.dat not found in app bundle")
            return
        }
        
        do {
            let handle = try FileHandle(forReadingFrom: url)
            self.fileHandle = handle
            
            // Read Magic
            guard let magicData = try handle.read(upToCount: 8), magicData.count == 8 else { return }
            
            // Read Count
            guard let countData = try handle.read(upToCount: 4), countData.count == 4 else { return }
            let count = countData.withUnsafeBytes { $0.load(as: UInt32.self) }
            
            // Read Index Table
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
            print("Successfully loaded \(self.indexTable.count) encrypted voice entries.")
        } catch {
            print("Error loading voice package: \(error)")
        }
    }
    
    // In-memory zero-disk-write decryption and playback
    func playVoice(id: Int) {
        guard id >= 1 && id <= indexTable.count else { return }
        guard let handle = fileHandle else { return }
        
        let entry = indexTable[id - 1]
        let absoluteOffset = payloadStartOffset + UInt64(entry.offset)
        
        do {
            try handle.seek(toOffset: absoluteOffset)
            guard let combinedChunk = try handle.read(upToCount: Int(entry.length)), combinedChunk.count == Int(entry.length) else {
                return
            }
            
            // Decrypt with hardware-accelerated CryptoKit AES-GCM
            let sealedBox = try AES.GCM.SealedBox(combined: combinedChunk)
            let decryptedAudioData = try AES.GCM.open(sealedBox, using: self.symmetricKey)
            
            // Play directly from RAM - NO file written to filesystem
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(data: decryptedAudioData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentPlayingId = id
            }
        } catch {
            print("Failed to decrypt or play voice ID \(id): \(error)")
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
        }
    }
    
    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
        }
    }
    
    // Cruise Mode (Driving Companion)
    func toggleCruiseMode() {
        if isCruiseModeActive {
            stopCruiseMode()
        } else {
            startCruiseMode()
        }
    }
    
    func startCruiseMode() {
        isCruiseModeActive = true
        // Play departure sound immediately
        playRandomVoice()
        
        cruiseTimer?.invalidate()
        let intervalSeconds = cruiseIntervalMinutes * 60.0
        cruiseTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.playRandomVoice()
        }
    }
    
    func stopCruiseMode() {
        isCruiseModeActive = false
        cruiseTimer?.invalidate()
        cruiseTimer = nil
    }
    
    func playRandomVoice() {
        let range = selectedCruiseCharacter.idRange
        let randomId = Int.random(in: range)
        playVoice(id: randomId)
    }
}
