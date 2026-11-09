//
//  KOnMusicManager.swift
//  KOnNaviCompanion
//
//  放课后茶会专属轻音音乐库 (K-ON! Music Library Engine & UI)
//  独立于导航语音系统的专属轻音音乐播放器，支持本地扫描、文件导入、自动避让导航语音 (Auto-Ducking)
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - HTT Theme Colors
private let httCrimson = Color(red: 0.65, green: 0.12, blue: 0.18)
private let httGold = Color(red: 0.88, green: 0.72, blue: 0.38)
private let httCream = Color(red: 0.98, green: 0.95, blue: 0.88)
private let httDarkPanel = Color(red: 0.12, green: 0.12, blue: 0.14)

// MARK: - Music Categories
enum MusicCategoryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case oped = "OP/ED"
    case insert = "剧中歌"
    case character = "角色歌"
    case ready = "已就绪"
    
    var id: String { rawValue }
}

// MARK: - Playback Mode
enum MusicPlayMode: String, CaseIterable {
    case loopAll = "列表循环"
    case loopSingle = "单曲循环"
    case shuffle = "随机播放"
    
    var iconName: String {
        switch self {
        case .loopAll: return "repeat"
        case .loopSingle: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}

// MARK: - K-ON! Song Item Model
struct KOnSongItem: Identifiable, Equatable, Hashable {
    let id: UUID
    var trackNumber: Int
    var title: String
    var titleRomaji: String
    var artist: String
    var album: String
    var category: MusicCategoryFilter
    var vocalistChar: String
    var durationFormatted: String
    var approxDurationSeconds: Double
    var fileURL: URL?
    var isCustomImport: Bool
    var encryptedDataBlock: Data?
    
    var isAvailable: Bool { fileURL != nil || encryptedDataBlock != nil }
    
    init(
        id: UUID = UUID(),
        trackNumber: Int,
        title: String,
        titleRomaji: String,
        artist: String,
        album: String,
        category: MusicCategoryFilter,
        vocalistChar: String,
        durationFormatted: String,
        approxDurationSeconds: Double = 240,
        fileURL: URL? = nil,
        isCustomImport: Bool = false,
        encryptedDataBlock: Data? = nil
    ) {
        self.id = id
        self.trackNumber = trackNumber
        self.title = title
        self.titleRomaji = titleRomaji
        self.artist = artist
        self.album = album
        self.category = category
        self.vocalistChar = vocalistChar
        self.durationFormatted = durationFormatted
        self.approxDurationSeconds = approxDurationSeconds
        self.fileURL = fileURL
        self.isCustomImport = isCustomImport
        self.encryptedDataBlock = encryptedDataBlock
    }
}

// MARK: - Dedicated K-ON! Music Player Manager
class KOnMusicManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = KOnMusicManager()
    
    // Published UI states
    @Published var playlist: [KOnSongItem] = []
    @Published var currentSong: KOnSongItem? = nil
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var progress: Double = 0.0
    @Published var volume: Float = 0.85
    @Published var playMode: MusicPlayMode = .loopAll
    @Published var autoDuckEnabled: Bool = true
    @Published var showMusicSheet: Bool = false
    @Published var showDocumentPicker: Bool = false
    @Published var searchKeyword: String = ""
    @Published var selectedCategory: MusicCategoryFilter = .all
    @Published var discRotationDegrees: Double = 0.0
    @Published var libraryStatusMessage: String = ""
    
    // Internal audio engine
    private var audioPlayer: AVAudioPlayer? = nil
    private var playbackTimer: Timer? = nil
    private var rotationTimer: Timer? = nil
    private var isDucked: Bool = false
    private var baseVolume: Float = 0.85
    
    override init() {
        super.init()
        setupAudioSession()
        setupAndScanLibrary()
        startRotationLoop()
    }
    
    // MARK: - Audio Session Configuration
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true)
        } catch {
            print("KOnMusicManager audio session init error: \(error)")
        }
    }
    
    // MARK: - Built-in Canonical K-ON! Discography Index
    private static let canonicalKOnSongs: [KOnSongItem] = [
        // 1. OP & ED
        KOnSongItem(trackNumber: 1, title: "Cagayake! GIRLS", titleRomaji: "Cagayake! GIRLS", artist: "放课后茶会 / 平泽唯", album: "K-ON! 1st Season OP", category: .oped, vocalistChar: "平泽唯", durationFormatted: "04:10", approxDurationSeconds: 250),
        KOnSongItem(trackNumber: 2, title: "Don't say \"lazy\"", titleRomaji: "Don't say lazy", artist: "放课后茶会 / 秋山澪", album: "K-ON! 1st Season ED", category: .oped, vocalistChar: "秋山澪", durationFormatted: "04:24", approxDurationSeconds: 264),
        KOnSongItem(trackNumber: 3, title: "GO! GO! MANIAC", titleRomaji: "GO! GO! MANIAC", artist: "放课后茶会 / 平泽唯", album: "K-ON!! 2nd Season OP1", category: .oped, vocalistChar: "平泽唯", durationFormatted: "04:11", approxDurationSeconds: 251),
        KOnSongItem(trackNumber: 4, title: "Listen!!", titleRomaji: "Listen!!", artist: "放课后茶会 / 秋山澪", album: "K-ON!! 2nd Season ED1", category: .oped, vocalistChar: "秋山澪", durationFormatted: "03:47", approxDurationSeconds: 227),
        KOnSongItem(trackNumber: 5, title: "Utauyo!!MIRACLE", titleRomaji: "Utauyo!! MIRACLE", artist: "放课后茶会 / 平泽唯", album: "K-ON!! 2nd Season OP2", category: .oped, vocalistChar: "平泽唯", durationFormatted: "04:02", approxDurationSeconds: 242),
        KOnSongItem(trackNumber: 6, title: "NO,Thank You!", titleRomaji: "NO, Thank You!", artist: "放课后茶会 / 秋山澪", album: "K-ON!! 2nd Season ED2", category: .oped, vocalistChar: "秋山澪", durationFormatted: "04:17", approxDurationSeconds: 257),
        KOnSongItem(trackNumber: 7, title: "Singing!", titleRomaji: "Singing!", artist: "放课后茶会 / 秋山澪", album: "K-ON! 电影版 ED", category: .oped, vocalistChar: "秋山澪", durationFormatted: "03:54", approxDurationSeconds: 234),
        KOnSongItem(trackNumber: 8, title: "Unmei♪wa♪Endless!", titleRomaji: "Unmei wa Endless!", artist: "放课后茶会 / 平泽唯", album: "K-ON! 电影版 OP", category: .oped, vocalistChar: "平泽唯", durationFormatted: "03:52", approxDurationSeconds: 232),
        
        // 2. Insert Songs (剧中歌)
        KOnSongItem(trackNumber: 9, title: "ふわふわ時間 (Fuwa Fuwa Time)", titleRomaji: "Fuwa Fuwa Time", artist: "放课后茶会 / 秋山澪·平泽唯", album: "放课后茶会 经典舞台曲", category: .insert, vocalistChar: "放课后茶会", durationFormatted: "03:59", approxDurationSeconds: 239),
        KOnSongItem(trackNumber: 10, title: "わたしの恋はホッチキス (My Love is a Stapler)", titleRomaji: "Watashi no Koi wa Hotchkiss", artist: "放课后茶会 / 平泽唯·秋山澪", album: "放课后茶会 I", category: .insert, vocalistChar: "平泽唯·秋山澪", durationFormatted: "04:24", approxDurationSeconds: 264),
        KOnSongItem(trackNumber: 11, title: "ふでペン 〜ボールペン〜", titleRomaji: "Fude Pen ~Ballpoint Pen~", artist: "放课后茶会 / 秋山澪·平泽唯", album: "放课后茶会 I", category: .insert, vocalistChar: "秋山澪", durationFormatted: "03:58", approxDurationSeconds: 238),
        KOnSongItem(trackNumber: 12, title: "ぴゅあぴゅあはーと (Pure Pure Heart)", titleRomaji: "Pure Pure Heart", artist: "放课后茶会 / 秋山澪", album: "放课后茶会 II", category: .insert, vocalistChar: "秋山澪", durationFormatted: "04:35", approxDurationSeconds: 275),
        KOnSongItem(trackNumber: 13, title: "ごはんはおかず (米饭是小菜)", titleRomaji: "Gohan wa Okazu", artist: "放课后茶会 / 平泽唯", album: "放课后茶会 II", category: .insert, vocalistChar: "平泽唯", durationFormatted: "03:12", approxDurationSeconds: 192),
        KOnSongItem(trackNumber: 14, title: "U&I", titleRomaji: "U and I", artist: "放课后茶会 / 平泽唯", album: "放课后茶会 II (献给妹妹忧)", category: .insert, vocalistChar: "平泽唯", durationFormatted: "04:36", approxDurationSeconds: 276),
        KOnSongItem(trackNumber: 15, title: "天使にふれたよ! (相遇天使)", titleRomaji: "Tenshi ni Fureta yo!", artist: "放课后茶会 (给梓喵的毕业赠歌)", album: "放课后茶会 II 最终话", category: .insert, vocalistChar: "放课后茶会四人", durationFormatted: "04:42", approxDurationSeconds: 282),
        KOnSongItem(trackNumber: 16, title: "カレーのちライス (咖喱之后是米饭)", titleRomaji: "Curry Nochi Rice", artist: "放课后茶会 / 平泽唯", album: "放课后茶会 I", category: .insert, vocalistChar: "平泽唯", durationFormatted: "03:16", approxDurationSeconds: 196),
        KOnSongItem(trackNumber: 17, title: "いちばんいっぱい", titleRomaji: "Ichiban Ippai", artist: "平泽唯", album: "K-ON! 剧场版 主题曲", category: .insert, vocalistChar: "平泽唯", durationFormatted: "03:10", approxDurationSeconds: 190),
        
        // 3. Character Image Songs (角色歌)
        KOnSongItem(trackNumber: 18, title: "ギー太に首ったけ", titleRomaji: "Giita ni Kubittake", artist: "平泽唯 (CV: 丰崎爱生)", album: "平泽唯 Character Single", category: .character, vocalistChar: "平泽唯", durationFormatted: "03:33", approxDurationSeconds: 213),
        KOnSongItem(trackNumber: 19, title: "Sunday Siesta", titleRomaji: "Sunday Siesta", artist: "平泽唯 (CV: 丰崎爱生)", album: "平泽唯 Character Single", category: .character, vocalistChar: "平泽唯", durationFormatted: "03:38", approxDurationSeconds: 218),
        KOnSongItem(trackNumber: 20, title: "Heart Goes Boom!!", titleRomaji: "Heart Goes Boom!!", artist: "秋山澪 (CV: 日笠阳子)", album: "秋山澪 Character Single", category: .character, vocalistChar: "秋山澪", durationFormatted: "03:56", approxDurationSeconds: 236),
        KOnSongItem(trackNumber: 21, title: "Hello Little Girl", titleRomaji: "Hello Little Girl", artist: "秋山澪 (CV: 日笠阳子)", album: "秋山澪 Character Single", category: .character, vocalistChar: "秋山澪", durationFormatted: "04:42", approxDurationSeconds: 282),
        KOnSongItem(trackNumber: 22, title: "Girly Storm 疾走 Style", titleRomaji: "Girly Storm Shissou Style", artist: "田井中律 (CV: 佐藤聪美)", album: "田井中律 Character Single", category: .character, vocalistChar: "田井中律", durationFormatted: "03:52", approxDurationSeconds: 232),
        KOnSongItem(trackNumber: 23, title: "目指せハッピー100%↑↑↑", titleRomaji: "Mezase Happy 100%", artist: "田井中律 (CV: 佐藤聪美)", album: "田井中律 Character Single", category: .character, vocalistChar: "田井中律", durationFormatted: "03:17", approxDurationSeconds: 197),
        KOnSongItem(trackNumber: 24, title: "Dear My Keys 〜鍵盤の魔法〜", titleRomaji: "Dear My Keys", artist: "琴吹紬 (CV: 寿美菜子)", album: "琴吹紬 Character Single", category: .character, vocalistChar: "琴吹紬", durationFormatted: "04:39", approxDurationSeconds: 279),
        KOnSongItem(trackNumber: 25, title: "Humming Bird", titleRomaji: "Humming Bird", artist: "琴吹紬 (CV: 寿美菜子)", album: "琴吹紬 Character Single", category: .character, vocalistChar: "琴吹紬", durationFormatted: "03:48", approxDurationSeconds: 228),
        KOnSongItem(trackNumber: 26, title: "じゃじゃ馬Way To Go", titleRomaji: "Jajauma Way To Go", artist: "中野梓 (CV: 竹达彩奈)", album: "中野梓 Character Single", category: .character, vocalistChar: "中野梓", durationFormatted: "04:29", approxDurationSeconds: 269),
        KOnSongItem(trackNumber: 27, title: "私は私の道を行く", titleRomaji: "Watashi wa Watashi no Michi wo Yuku", artist: "中野梓 (CV: 竹达彩奈)", album: "中野梓 Character Single", category: .character, vocalistChar: "中野梓", durationFormatted: "03:18", approxDurationSeconds: 198)
    ]
    
    // MARK: - Library Directory Paths
    var musicDocumentsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let musicDir = docs.appendingPathComponent("Music", isDirectory: true)
        if !FileManager.default.fileExists(atPath: musicDir.path) {
            try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true, attributes: nil)
        }
        return musicDir
    }
    
    // MARK: - Scan & Load Music Library
    func setupAndScanLibrary() {
        var baseList = KOnMusicManager.canonicalKOnSongs
        let fm = FileManager.default
        
        // 0. Load Anti-Extract Encrypted Music Container (music_assets.dat)
        let encContainerName = "music_assets.dat"
        var containerURL: URL? = nil
        if let bundleContainer = Bundle.main.url(forResource: "music_assets", withExtension: "dat", subdirectory: "Music") {
            containerURL = bundleContainer
        } else if let bundleContainerRoot = Bundle.main.url(forResource: "music_assets", withExtension: "dat") {
            containerURL = bundleContainerRoot
        } else {
            let docContainer = musicDocumentsDirectory.appendingPathComponent(encContainerName)
            if fm.fileExists(atPath: docContainer.path) {
                containerURL = docContainer
            }
        }
        
        if let cURL = containerURL, let containerData = try? Data(contentsOf: cURL) {
            parseAndLoadEncryptedContainer(containerData, baseList: &baseList)
        }
        let audioExtensions = ["mp3", "m4a", "mp4", "m4b", "m4r", "flac", "wav", "aac", "caf", "aiff"]
        
        var foundFiles: [URL] = []
        
        // 1. Scan Documents/Music directory (Accessible via iOS Files App)
        let docMusic = musicDocumentsDirectory
        if let docContents = try? fm.contentsOfDirectory(at: docMusic, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for file in docContents {
                if audioExtensions.contains(file.pathExtension.lowercased()) {
                    foundFiles.append(file)
                }
            }
        }
        
        // 2. Scan App Bundle Music/ or Root
        if let bundleUrls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "Music") {
            for file in bundleUrls {
                if audioExtensions.contains(file.pathExtension.lowercased()) && !foundFiles.contains(where: { $0.lastPathComponent == file.lastPathComponent }) {
                    foundFiles.append(file)
                }
            }
        }
        for ext in audioExtensions {
            if let rootBundle = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for file in rootBundle {
                    if !foundFiles.contains(where: { $0.lastPathComponent == file.lastPathComponent }) {
                        foundFiles.append(file)
                    }
                }
            }
        }
        
        // Match found files to canonical songs
        var matchedURLs: Set<URL> = []
        for i in 0..<baseList.count {
            let title = baseList[i].title.lowercased()
            let romaji = baseList[i].titleRomaji.lowercased()
            
            if let match = foundFiles.first(where: { url in
                let fname = url.deletingPathExtension().lastPathComponent.lowercased()
                return fname.contains(title) || fname.contains(romaji) ||
                       (title.contains("cagayake") && fname.contains("cagayake")) ||
                       (title.contains("lazy") && fname.contains("lazy")) ||
                       (title.contains("fuwa") && fname.contains("fuwa")) ||
                       (title.contains("ふわふわ") && fname.contains("ふわふわ")) ||
                       (title.contains("maniac") && fname.contains("maniac")) ||
                       (title.contains("listen") && fname.contains("listen")) ||
                       (title.contains("miracle") && fname.contains("miracle")) ||
                       (title.contains("thank you") && fname.contains("thank you")) ||
                       (title.contains("u&i") && (fname.contains("u&i") || fname.contains("u and i"))) ||
                       (title.contains("相遇天使") && (fname.contains("相遇天使") || fname.contains("天使")))
            }) {
                baseList[i].fileURL = match
                matchedURLs.insert(match)
            }
        }
        
        // Append any extra non-canonical custom tracks found in the folder
        var customIndex = baseList.count + 1
        for extra in foundFiles where !matchedURLs.contains(extra) {
            let cleanTitle = extra.deletingPathExtension().lastPathComponent
            var customDurFormatted = "--:--"
            var customApproxSecs: Double = 240.0
            let asset = AVURLAsset(url: extra)
            let durationSecs = CMTimeGetSeconds(asset.duration)
            if !durationSecs.isNaN && durationSecs > 0 {
                customApproxSecs = durationSecs
                let mins = Int(durationSecs) / 60
                let secs = Int(durationSecs) % 60
                customDurFormatted = String(format: "%02d:%02d", mins, secs)
            }
            let customItem = KOnSongItem(
                trackNumber: customIndex,
                title: cleanTitle,
                titleRomaji: cleanTitle,
                artist: "放课后茶会 / 自定义导入",
                album: "轻音少女导入曲库",
                category: .insert,
                vocalistChar: "放课后茶会",
                durationFormatted: customDurFormatted,
                approxDurationSeconds: customApproxSecs,
                fileURL: extra,
                isCustomImport: true
            )
            baseList.append(customItem)
            customIndex += 1
        }
        
        self.playlist = baseList
        let availableCount = baseList.filter { $0.isAvailable }.count
        if availableCount > 0 {
            self.libraryStatusMessage = "轻音音乐库已载入 \(availableCount) 首可播放曲目"
        } else {
            self.libraryStatusMessage = "轻音音乐库已建立 (27首名曲索引，可通过文件App放入音频)"
        }
        
        if currentSong == nil, let firstAvailable = playlist.first(where: { $0.isAvailable }) {
            self.currentSong = firstAvailable
        } else if currentSong == nil, let first = playlist.first {
            self.currentSong = first
        }
    }
    
    // MARK: - Playback Controls
    func playSong(_ song: KOnSongItem) {
        self.currentSong = song
        
        // 1. Play from encrypted in-memory data if available (Anti-Extract Protected)
        if let encData = song.encryptedDataBlock {
            let key = Array("K-On!AfterSchoolTeaTimeNavi2026".utf8)
            var decBytes = [UInt8](encData)
            for i in 0..<decBytes.count {
                decBytes[i] ^= key[i % key.count]
            }
            let decData = Data(decBytes)
            do {
                audioPlayer?.stop()
                audioPlayer = try AVAudioPlayer(data: decData)
                audioPlayer?.delegate = self
                audioPlayer?.volume = isDucked ? duckVolume : volume
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                
                self.isPlaying = true
                self.duration = audioPlayer?.duration ?? song.approxDurationSeconds
                self.currentTime = 0.0
                self.progress = 0.0
                self.libraryStatusMessage = "正在播放: \(song.title)"
                startProgressTimer()
                return
            } catch {
                print("Failed to play encrypted audio: \(error)")
            }
        }
        
        guard let url = song.fileURL else {
            self.libraryStatusMessage = "【\(song.title)】音频文件尚未放入，请通过文件 App 或「+ 导入」放入歌曲"
            return
        }
        
        do {
            audioPlayer?.stop()
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
            } catch {
                let ext = url.pathExtension.lowercased()
                var hint: AVFileType? = nil
                if ext == "mp4" || ext == "m4v" {
                    hint = .mp4
                } else if ext == "m4a" || ext == "m4b" || ext == "m4r" || ext == "aac" {
                    hint = .m4a
                }
                if let hint = hint {
                    audioPlayer = try AVAudioPlayer(contentsOf: url, fileTypeHint: hint.rawValue)
                } else {
                    throw error
                }
            }
            audioPlayer?.delegate = self
            audioPlayer?.volume = isDucked ? duckVolume : volume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            self.isPlaying = true
            self.duration = audioPlayer?.duration ?? song.approxDurationSeconds
            self.currentTime = 0.0
            self.progress = 0.0
            self.libraryStatusMessage = "正在播放: \(song.title)"
            
            startProgressTimer()
        } catch {
            print("Failed to play song \(song.title): \(error)")
            self.libraryStatusMessage = "播放失败: \(error.localizedDescription)"
        }
    }
    
    func playOrPause() {
        guard let player = audioPlayer else {
            if let song = currentSong, song.isAvailable {
                playSong(song)
            } else if let firstAvail = playlist.first(where: { $0.isAvailable }) {
                playSong(firstAvail)
            } else {
                self.libraryStatusMessage = "请先点击右上角「+ 导入」或通过文件 App 放入轻音音乐"
            }
            return
        }
        
        if player.isPlaying {
            player.pause()
            self.isPlaying = false
            playbackTimer?.invalidate()
            self.libraryStatusMessage = "已暂停播放"
        } else {
            player.play()
            self.isPlaying = true
            startProgressTimer()
            self.libraryStatusMessage = "正在播放: \(currentSong?.title ?? "")"
        }
    }
    
    func nextTrack() {
        let availList = playlist.filter { $0.isAvailable }
        guard !availList.isEmpty else {
            self.libraryStatusMessage = "暂无本地歌曲可播放，请先导入音频"
            return
        }
        
        if playMode == .shuffle {
            if let randomSong = availList.randomElement() {
                playSong(randomSong)
            }
            return
        }
        
        if let cur = currentSong, let curIdx = availList.firstIndex(of: cur) {
            let nextIdx = (curIdx + 1) % availList.count
            playSong(availList[nextIdx])
        } else if let first = availList.first {
            playSong(first)
        }
    }
    
    func previousTrack() {
        let availList = playlist.filter { $0.isAvailable }
        guard !availList.isEmpty else { return }
        
        if let cur = currentSong, let curIdx = availList.firstIndex(of: cur) {
            let prevIdx = (curIdx - 1 + availList.count) % availList.count
            playSong(availList[prevIdx])
        } else if let first = availList.first {
            playSong(first)
        }
    }
    
    func seek(to targetProgress: Double) {
        guard let player = audioPlayer, duration > 0 else { return }
        let clamped = max(0.0, min(1.0, targetProgress))
        let targetTime = clamped * duration
        player.currentTime = targetTime
        self.currentTime = targetTime
        self.progress = clamped
    }
    
    func setVolume(_ newVol: Float) {
        let clamped = max(0.0, min(1.0, newVol))
        self.volume = clamped
        self.baseVolume = clamped
        if !isDucked {
            audioPlayer?.volume = clamped
        }
    }
    
    func togglePlayMode() {
        switch playMode {
        case .loopAll: playMode = .loopSingle
        case .loopSingle: playMode = .shuffle
        case .shuffle: playMode = .loopAll
        }
    }
    
    // MARK: - Auto-Ducking for Navigation Voice
    private var duckVolume: Float { volume * 0.25 }
    
    func duckForVoice(duck: Bool) {
        guard autoDuckEnabled, let player = audioPlayer, isPlaying else { return }
        self.isDucked = duck
        
        let targetVol: Float = duck ? (volume * 0.25) : volume
        player.volume = targetVol
    }
    
    // MARK: - Audio Player Delegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if playMode == .loopSingle, let cur = currentSong {
            playSong(cur)
        } else {
            nextTrack()
        }
    }
    
    // MARK: - Timer Loops
    private func startProgressTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.audioPlayer else { return }
            self.currentTime = p.currentTime
            if p.duration > 0 {
                self.progress = p.currentTime / p.duration
            }
        }
    }
    
    private func startRotationLoop() {
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isPlaying {
                self.discRotationDegrees = (self.discRotationDegrees + 1.2).truncatingRemainder(dividingBy: 360)
            }
        }
    }
    
    // MARK: - Import Audio Files
    func importAudioFiles(from urls: [URL]) {
        let destDir = musicDocumentsDirectory
        var importCount = 0
        
        for url in urls {
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStop { url.stopAccessingSecurityScopedResource() }
            }
            
            let filename = url.lastPathComponent
            let targetURL = destDir.appendingPathComponent(filename)
            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.copyItem(at: url, to: targetURL)
                importCount += 1
            } catch {
                print("Error copying imported audio file \(filename): \(error)")
            }
        }
        
        setupAndScanLibrary()
        self.libraryStatusMessage = "成功导入 \(importCount) 首轻音音乐！"
    }
    
    func deleteSongFile(_ song: KOnSongItem) {
        guard let url = song.fileURL else { return }
        if song == currentSong && isPlaying {
            audioPlayer?.stop()
            isPlaying = false
        }
        try? FileManager.default.removeItem(at: url)
        setupAndScanLibrary()
        self.libraryStatusMessage = "已移除歌曲: \(song.title)"
    }
    
    func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let mins = s / 60
        let secs = s % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Audio Document Picker for SwiftUI
struct AudioDocumentPicker: UIViewControllerRepresentable {
    @ObservedObject var musicManager: KOnMusicManager
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie]
        if let mp4Type = UTType(filenameExtension: "mp4") { types.append(mp4Type) }
        if let m4aType = UTType(filenameExtension: "m4a") { types.append(m4aType) }
        if let m4bType = UTType(filenameExtension: "m4b") { types.append(m4bType) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioDocumentPicker
        
        init(_ parent: AudioDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.musicManager.importAudioFiles(from: urls)
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - K-ON! Music Library Full Sheet View
struct KOnMusicLibraryView: View {
    @ObservedObject var musicManager: KOnMusicManager
    @Environment(\.presentationMode) var presentationMode
    @State private var showingDeleteAlert = false
    @State private var songToDelete: KOnSongItem? = nil
    
    var filteredPlaylist: [KOnSongItem] {
        var list = musicManager.playlist
        if musicManager.selectedCategory == .ready {
            list = list.filter { $0.isAvailable }
        } else if musicManager.selectedCategory != .all {
            list = list.filter { $0.category == musicManager.selectedCategory }
        }
        
        let kw = musicManager.searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !kw.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(kw) ||
                $0.titleRomaji.lowercased().contains(kw) ||
                $0.artist.lowercased().contains(kw) ||
                $0.vocalistChar.lowercased().contains(kw) ||
                $0.album.lowercased().contains(kw)
            }
        }
        return list
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. Navigation Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(httGold)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("放课后茶会 · 轻音音乐馆")
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(httCream)
                            Text("K-ON! 专属独立音乐库 (与导航音频独立)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Import Audio Files Button
                    Button(action: {
                        musicManager.showDocumentPicker = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("导入音乐")
                                .font(.system(size: 11, weight: .black))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(httGold)
                        .cornerRadius(8)
                    }
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 6)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(httDarkPanel)
                
                Divider().background(Color.white.opacity(0.15))
                
                // 2. Vinyl Turntable Player Top Area
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        // Spinning Vinyl Record
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 86, height: 86)
                                .overlay(Circle().stroke(httGold.opacity(0.8), lineWidth: 2))
                                .shadow(color: httGold.opacity(0.3), radius: 6)
                            
                            // Grooves
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                .frame(width: 72, height: 72)
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                .frame(width: 58, height: 58)
                            
                            // Center label
                            Circle()
                                .fill(httCrimson)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(httGold, lineWidth: 1.5))
                            
                            Image(systemName: "music.note")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(httCream)
                        }
                        .rotationEffect(.degrees(musicManager.discRotationDegrees))
                        
                        // Current song metadata & status
                        VStack(alignment: .leading, spacing: 3) {
                            Text(musicManager.currentSong?.title ?? "放课后茶会音乐全集")
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(httCream)
                                .lineLimit(1)
                            
                            Text(musicManager.currentSong?.artist ?? "放课后茶会 / HTT")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(httGold)
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                if let cur = musicManager.currentSong {
                                    Text(cur.album)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                    
                                    Text(cur.isAvailable ? "● 已就绪" : "○ 待导入")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(cur.isAvailable ? .green : .orange)
                                }
                            }
                            
                            if !musicManager.libraryStatusMessage.isEmpty {
                                Text(musicManager.libraryStatusMessage)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(httGold.opacity(0.9))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    
                    // Scrubber progress slider
                    VStack(spacing: 2) {
                        Slider(value: Binding(
                            get: { musicManager.progress },
                            set: { musicManager.seek(to: $0) }
                        ), in: 0...1)
                        .accentColor(httGold)
                        
                        HStack {
                            Text(musicManager.formatTime(musicManager.currentTime))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(musicManager.formatTime(musicManager.duration))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 14)
                    
                    // Playback Controls Row
                    HStack(spacing: 24) {
                        // Play Mode
                        Button(action: {
                            musicManager.togglePlayMode()
                        }) {
                            Image(systemName: musicManager.playMode.iconName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(httGold)
                        }
                        
                        // Previous
                        Button(action: {
                            musicManager.previousTrack()
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(httCream)
                        }
                        
                        // Big Play / Pause
                        Button(action: {
                            musicManager.playOrPause()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(httCrimson)
                                    .frame(width: 48, height: 48)
                                    .overlay(Circle().stroke(httGold, lineWidth: 2))
                                    .shadow(color: httGold.opacity(0.4), radius: 5)
                                
                                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundColor(httCream)
                            }
                        }
                        
                        // Next
                        Button(action: {
                            musicManager.nextTrack()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(httCream)
                        }
                        
                        // Auto-ducking toggle
                        Button(action: {
                            musicManager.autoDuckEnabled.toggle()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: musicManager.autoDuckEnabled ? "speaker.slash.fill" : "speaker.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(musicManager.autoDuckEnabled ? "避让开" : "避让关")
                                    .font(.system(size: 9, weight: .heavy))
                            }
                            .foregroundColor(musicManager.autoDuckEnabled ? .green : .gray)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .background(Color.black.opacity(0.85))
                
                Divider().background(Color.white.opacity(0.15))
                
                // 3. Search and Category Filter
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("搜索轻音名曲 / 角色 / 专辑...", text: $musicManager.searchKeyword)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        if !musicManager.searchKeyword.isEmpty {
                            Button(action: { musicManager.searchKeyword = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    
                    // Filter tabs
                    HStack(spacing: 6) {
                        ForEach(MusicCategoryFilter.allCases) { cat in
                            Button(action: {
                                musicManager.selectedCategory = cat
                            }) {
                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(musicManager.selectedCategory == cat ? httCrimson : Color.white.opacity(0.08))
                                    .foregroundColor(musicManager.selectedCategory == cat ? httGold : .gray)
                                    .cornerRadius(6)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 6)
                .background(httDarkPanel)
                
                // 4. Playlist
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredPlaylist) { song in
                            HStack(spacing: 10) {
                                Text(String(format: "%02d", song.trackNumber))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(song == musicManager.currentSong ? httGold : .gray)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(song == musicManager.currentSong ? httGold : httCream)
                                        .lineLimit(1)
                                    Text("\(song.artist) · \(song.album)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if song.isAvailable {
                                    Text(song.durationFormatted)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.gray)
                                    
                                    Button(action: {
                                        musicManager.playSong(song)
                                    }) {
                                        Image(systemName: (song == musicManager.currentSong && musicManager.isPlaying) ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(httGold)
                                    }
                                } else {
                                    Text("待放入")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.08))
                                        .foregroundColor(.gray)
                                        .cornerRadius(4)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(song == musicManager.currentSong ? httCrimson.opacity(0.3) : Color.black.opacity(0.3))
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if song.isAvailable {
                                    musicManager.playSong(song)
                                } else {
                                    musicManager.libraryStatusMessage = "【\(song.title)】请先放入音频文件"
                                }
                            }
                        }
                        
                        // 5. Help banner at bottom of list
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(httGold)
                                Text("如何将「轻音音乐.7z」导入 App：")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(httGold)
                            }
                            Text("① 解压电脑或手机上的「轻音音乐.7z」获得音频文件（.mp3 / .flac / .m4a）。\n② 打开手机「文件」App →「我的 iPhone」→ 找到「放课后茶会伴侣」目录，将解压后的音乐放入「Music」文件夹内。\n③ 或直接点击本页右上角「导入音乐」按钮，批量选择解压出的歌曲文件即可秒级载入！")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                                .lineSpacing(2)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 25)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(isPresented: $musicManager.showDocumentPicker) {
            AudioDocumentPicker(musicManager: musicManager)
        }
    }
}

// MARK: - Floating Mini-Player Bar (Displayed on HUD/Cockpit)
struct KOnMusicMiniPlayerBar: View {
    @ObservedObject var musicManager = KOnMusicManager.shared
    
    var body: some View {
        Button(action: {
            musicManager.showMusicSheet = true
        }) {
            HStack(spacing: 10) {
                // Spinning vinyl mini icon
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(httGold, lineWidth: 1.5))
                    
                    Circle()
                        .fill(httCrimson)
                        .frame(width: 12, height: 12)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(httCream)
                }
                .rotationEffect(.degrees(musicManager.discRotationDegrees))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(musicManager.currentSong?.title ?? "放课后茶会音乐库")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(httCream)
                        .lineLimit(1)
                    Text("\(musicManager.currentSong?.vocalistChar ?? "HTT") · \(musicManager.formatTime(musicManager.currentTime)) / \(musicManager.formatTime(musicManager.duration))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(httGold)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Play / Pause button
                Button(action: {
                    musicManager.playOrPause()
                }) {
                    Image(systemName: musicManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(httGold)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                // Next track button
                Button(action: {
                    musicManager.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(httCream)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                // Expand sheet icon
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(httGold.opacity(0.8), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.5), radius: 6)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func parseAndLoadEncryptedContainer(_ data: Data, baseList: inout [KOnSongItem]) {
        guard let headerEnd = data.range(of: Data("HEADER_END
".utf8)) else { return }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return }
        let lines = headerStr.components(separatedBy: "
")
        guard lines.first == "KON_ENC_MUSIC_V1", lines.count >= 2 else { return }
        let jsonStr = lines[1]
        guard let jsonData = jsonStr.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return }
        
        let binaryBaseOffset = headerEnd.upperBound
        for entry in items {
            guard let fname = entry["filename"] as? String,
                  let offset = entry["offset"] as? Int,
                  let length = entry["length"] as? Int else { continue }
            let absStart = binaryBaseOffset + offset
            let absEnd = absStart + length
            guard absEnd <= data.count else { continue }
            let trackEncData = data.subdata(in: absStart..<absEnd)
            
            let lowerFname = fname.lowercased()
            if let idx = baseList.firstIndex(where: {
                let t = /usr/bin/bash.title.lowercased()
                let r = /usr/bin/bash.titleRomaji.lowercased()
                return lowerFname.contains(t) || lowerFname.contains(r) ||
                       (t.contains("cagayake") && lowerFname.contains("cagayake")) ||
                       (t.contains("lazy") && lowerFname.contains("lazy")) ||
                       (t.contains("fuwa") && lowerFname.contains("fuwa")) ||
                       (t.contains("maniac") && lowerFname.contains("maniac")) ||
                       (t.contains("listen") && lowerFname.contains("listen")) ||
                       (t.contains("miracle") && lowerFname.contains("miracle")) ||
                       (t.contains("thank you") && lowerFname.contains("thank you")) ||
                       (t.contains("u&i") && lowerFname.contains("u&i")) ||
                       (t.contains("相遇天使") && (lowerFname.contains("相遇天使") || lowerFname.contains("天使")))
            }) {
                baseList[idx].encryptedDataBlock = trackEncData
            } else {
                let cleanTitle = (fname as NSString).deletingPathExtension
                let customItem = KOnSongItem(
                    trackNumber: baseList.count + 1,
                    title: cleanTitle,
                    titleRomaji: cleanTitle,
                    artist: "放课后茶会 / 内置曲库",
                    album: "放课后茶会 独立音乐馆",
                    category: .insert,
                    vocalistChar: "放课后茶会",
                    durationFormatted: "--:--",
                    encryptedDataBlock: trackEncData
                )
                baseList.append(customItem)
            }
        }
    }

}
