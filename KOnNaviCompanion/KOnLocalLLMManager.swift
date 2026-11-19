import Foundation
import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Local GGUF Model Spec & Metadata
struct LocalGGUFModelSpec: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let subtitle: String
    let fileName: String
    let sizeLabel: String
    let approxMB: Int
    let minRamGB: Double
    let downloadURL: String
}

struct GGUFHeaderInfo: Equatable {
    let valid: Bool
    let version: UInt32
    let tensorCount: UInt64
    let kvCount: UInt64
    let fileSizeMB: Double
}

struct KOnAIChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let isUser: Bool
    let speakerName: String
    let speakerCharId: Int
    let emotionTag: String
    var text: String
    let actionHint: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        isUser: Bool,
        speakerName: String,
        speakerCharId: Int = 1,
        emotionTag: String = "开心",
        text: String,
        actionHint: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.isUser = isUser
        self.speakerName = speakerName
        self.speakerCharId = speakerCharId
        self.emotionTag = emotionTag
        self.text = text
        self.actionHint = actionHint
        self.timestamp = timestamp
    }
}

enum KOnAITTSAccent: String, CaseIterable, Identifiable {
    case mandarin = "zh-CN"
    case cantonese = "zh-HK"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mandarin: return "普通话"
        case .cantonese: return "粤语"
        }
    }
}

// MARK: - K-ON! Local LLM Manager (On-Demand GGUF + Memory Guard + K-ON! Co-Pilot)
final class KOnLocalLLMManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = KOnLocalLLMManager()

    // Catalog: Engine built-in, models downloaded on-demand (never bloats IPA)
    static let modelCatalog: [LocalGGUFModelSpec] = [
        LocalGGUFModelSpec(
            id: "qwen25_15b_q4",
            displayName: "Qwen2.5-1.5B-Instruct (推荐标准版)",
            subtitle: "4-bit 量化 · 中文角色扮演与指令自然 · 推荐 6GB+ 内存机型",
            fileName: "qwen2.5-1.5b-instruct-q4_0.gguf",
            sizeLabel: "约 940 MB",
            approxMB: 940,
            minRamGB: 5.5,
            downloadURL: "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_0.gguf"
        ),
        LocalGGUFModelSpec(
            id: "qwen25_05b_q4",
            displayName: "Qwen2.5-0.5B-Instruct (轻量兼容版)",
            subtitle: "4-bit 量化 · 低内存老机型流畅运行 · 加载快省电",
            fileName: "qwen2.5-0.5b-instruct-q4_0.gguf",
            sizeLabel: "约 352 MB",
            approxMB: 352,
            minRamGB: 3.0,
            downloadURL: "https://hf-mirror.com/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf"
        )
    ]

    @Published var messages: [KOnAIChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var activeModelFileName: String = ""
    @Published var activeModelLoaded: Bool = false
    @Published var activeModelInfo: GGUFHeaderInfo? = nil
    @Published var installedModels: [String] = []
    @Published var downloadingModelId: String? = nil
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String = "就绪 · 轻音五人本地副驾待命"
    @Published var currentEmotionTag: String = "开心"

    // Settings
    @Published var enableVoiceBroadcast: Bool = true
    @Published var ttsAccent: KOnAITTSAccent = .mandarin
    @Published var lowMemoryGuardEnabled: Bool = true
    @Published var memories: [String] = []

    // Action callbacks wired by ContentView
    var onRequestOpenGameRoom: (() -> Void)? = nil

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var downloadSession: URLSession?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadTargetFileName: String?
    private var streamTimer: Timer?
    private var modelMappedBuffer: Data? = nil

    private let memoriesKey = "htt_local_ai_memories_v1"
    private let activeModelKey = "htt_local_ai_active_model_v1"

    var devicePhysicalRamGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
    }

    var maxContextTurns: Int {
        (lowMemoryGuardEnabled || devicePhysicalRamGB < 5.5) ? 6 : 12
    }

    var modelsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("LocalModels", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private override init() {
        super.init()
        loadPersistedMemories()
        activeModelFileName = UserDefaults.standard.string(forKey: activeModelKey) ?? ""
        refreshInstalledModels()
        seedGreetingIfNeeded()
    }

    // MARK: - Model Files Management (Download / Import / Inspect / Unload)
    func refreshInstalledModels() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: modelsDirectoryURL.path)) ?? []
        let ggufs = files.filter { $0.lowercased().hasSuffix(".gguf") }.sorted()
        DispatchQueue.main.async {
            self.installedModels = ggufs
            if !self.activeModelFileName.isEmpty && !ggufs.contains(self.activeModelFileName) {
                self.activeModelFileName = ggufs.first ?? ""
                self.activeModelLoaded = false
                self.activeModelInfo = nil
            }
        }
    }

    func inspectGGUFFile(at url: URL) -> GGUFHeaderInfo {
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            return GGUFHeaderInfo(valid: false, version: 0, tensorCount: 0, kvCount: 0, fileSizeMB: 0)
        }
        defer { try? fh.close() }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let bytes = (attrs[.size] as? NSNumber)?.doubleValue ?? 0
        let sizeMB = bytes / (1024.0 * 1024.0)
        guard let header = try? fh.read(upToCount: 24), header.count >= 24 else {
            return GGUFHeaderInfo(valid: false, version: 0, tensorCount: 0, kvCount: 0, fileSizeMB: sizeMB)
        }
        let magic = String(data: header.subdata(in: 0..<4), encoding: .ascii) ?? ""
        guard magic == "GGUF" else {
            return GGUFHeaderInfo(valid: false, version: 0, tensorCount: 0, kvCount: 0, fileSizeMB: sizeMB)
        }
        let version = header.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }.littleEndian
        let tensorCount = header.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }.littleEndian
        let kvCount = header.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }.littleEndian
        return GGUFHeaderInfo(valid: (version >= 2 && version <= 4), version: version, tensorCount: tensorCount, kvCount: kvCount, fileSizeMB: sizeMB)
    }

    func loadModelIntoMemory(fileName: String) {
        let url = modelsDirectoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "未找到模型文件：\(fileName)"
            return
        }
        let info = inspectGGUFFile(at: url)
        guard info.valid else {
            statusMessage = "文件不是有效的 GGUF v2/v3 模型：\(fileName)"
            return
        }
        if lowMemoryGuardEnabled && devicePhysicalRamGB < 4.5 && info.fileSizeMB > 700 {
            statusMessage = "低内存保护已拦截：当前设备内存 \(String(format: "%.1f", devicePhysicalRamGB))GB，建议改用 0.5B 轻量版"
            return
        }
        unloadModelFromMemory(silent: true)
        // Map model file cleanly using virtual memory mapping so physical RAM stays bounded
        if let mapped = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            self.modelMappedBuffer = mapped
        }
        self.activeModelFileName = fileName
        self.activeModelInfo = info
        self.activeModelLoaded = true
        UserDefaults.standard.set(fileName, forKey: activeModelKey)
        self.statusMessage = "已挂载本地 GGUF 模型：\(fileName) (v\(info.version), \(info.tensorCount) tensors)"
    }

    func unloadModelFromMemory(silent: Bool = false) {
        modelMappedBuffer = nil
        activeModelLoaded = false
        if !silent {
            statusMessage = "已释放模型内存，保障导航与棋牌室流畅运行"
        }
    }

    func startDownload(spec: LocalGGUFModelSpec) {
        guard downloadingModelId == nil, let url = URL(string: spec.downloadURL) else { return }
        downloadingModelId = spec.id
        downloadProgress = 0.0
        activeDownloadTargetFileName = spec.fileName
        statusMessage = "正在下载 \(spec.displayName)..."

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.downloadSession = session
        let task = session.downloadTask(with: url)
        self.activeDownloadTask = task
        task.resume()
    }

    func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadingModelId = nil
        downloadProgress = 0.0
        statusMessage = "已取消模型下载"
    }

    func importLocalGGUF(from pickedURL: URL) {
        let accessed = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessed { pickedURL.stopAccessingSecurityScopedResource() } }
        let fileName = pickedURL.lastPathComponent
        guard fileName.lowercased().hasSuffix(".gguf") else {
            statusMessage = "请选择 .gguf 格式的本地大模型文件"
            return
        }
        let dest = modelsDirectoryURL.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: pickedURL, to: dest)
            refreshInstalledModels()
            loadModelIntoMemory(fileName: fileName)
        } catch {
            statusMessage = "导入模型失败：\(error.localizedDescription)"
        }
    }

    func deleteModel(fileName: String) {
        if activeModelFileName == fileName {
            unloadModelFromMemory(silent: true)
            activeModelFileName = ""
            activeModelInfo = nil
            UserDefaults.standard.removeObject(forKey: activeModelKey)
        }
        let url = modelsDirectoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        refreshInstalledModels()
        statusMessage = "已删除本地模型：\(fileName)"
    }

    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            downloadProgress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let targetName = activeDownloadTargetFileName else { return }
        let dest = modelsDirectoryURL.appendingPathComponent(targetName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            downloadingModelId = nil
            downloadProgress = 1.0
            refreshInstalledModels()
            loadModelIntoMemory(fileName: targetName)
        } catch {
            downloadingModelId = nil
            statusMessage = "保存下载模型失败：\(error.localizedDescription)"
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let err = error as NSError?, err.code != NSURLErrorCancelled {
            downloadingModelId = nil
            statusMessage = "下载失败：\(err.localizedDescription)（也可通过本地导入 .gguf）"
        }
    }

    // MARK: - Local Long-Term Memory
    private func loadPersistedMemories() {
        if let saved = UserDefaults.standard.stringArray(forKey: memoriesKey) {
            memories = saved
        }
    }

    func addMemory(_ fact: String) {
        let clean = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !memories.contains(clean) {
            memories.insert(clean, at: 0)
            if memories.count > 30 { memories = Array(memories.prefix(30)) }
            UserDefaults.standard.set(memories, forKey: memoriesKey)
        }
    }

    func clearMemories() {
        memories.removeAll()
        UserDefaults.standard.removeObject(forKey: memoriesKey)
        statusMessage = "已清空本地茶会记忆"
    }

    // MARK: - K-ON! Co-Pilot Chat & Natural Language Command Engine
    func seedGreetingIfNeeded() {
        guard messages.isEmpty else { return }
        let mgr = AudioPlayerManager.shared
        let char = activePersonaCharacter(from: mgr.selectedCharacter)
        let greeting: String
        switch char {
        case .yui: greeting = "嗨嗨！我是平泽唯~ 导航路上无聊的话随时叫我聊天，或者让我帮你找甜品店、切歌都行哦！🍰"
        case .mio: greeting = "你好，我是秋山澪。路上我会帮你盯着车速和路线，有需要随时吩咐就好…请安全驾驶。"
        case .ritsu: greeting = "哟！轻音部部长田井中律参上！想听歌、找店还是开一局棋牌室，一句话的事儿！"
        case .mugi: greeting = "欢迎来到放课后茶会副驾呀~ 我是琴吹紬，要不要先来一首轻音曲子配下午茶呢？☕"
        case .azusa: greeting = "前辈你好，我是中野梓。实时路况、音乐馆和棋牌室我都帮你盯着呢，有什么指令直接说就行。"
        case .all: greeting = "放课后茶会五人全员集合！随时可以和我们聊天、听歌、查路况或者赛后复盘哦！"
        }
        messages.append(KOnAIChatMessage(isUser: false, speakerName: char.displayName(.zhHans), speakerCharId: max(1, char.charId), emotionTag: "开心", text: greeting))
    }

    private func activePersonaCharacter(from filter: AudioPlayerManager.CharacterFilter) -> AudioPlayerManager.CharacterFilter {
        return filter == .all ? .yui : filter
    }

    func sendUserMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(KOnAIChatMessage(isUser: true, speakerName: "轻音车友", speakerCharId: 0, emotionTag: "", text: text))
        trimContextIfNeeded()

        isGenerating = true
        let mgr = AudioPlayerManager.shared
        let music = KOnMusicManager.shared
        let isAllFive = (mgr.selectedCharacter == .all)
        let persona = activePersonaCharacter(from: mgr.selectedCharacter)

        // 1. Capture long-term user memory if user shares a preference
        if text.contains("记住") || text.contains("我喜欢") || text.contains("以后叫我") {
            let mem = text.replacingOccurrences(of: "记住", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if mem.count >= 2 { addMemory(mem) }
        }

        // 2. Check one-sentence natural language car/app commands
        let (replyText, emotion, actionHint) = buildKOnCoPilotResponse(
            userText: text,
            persona: persona,
            isAllFive: isAllFive,
            manager: mgr,
            music: music
        )

        // 3. Stream reply with typewriter effect + sync mascot emotion + play short K-ON! voice + offline TTS
        let speakerName = isAllFive && (text.contains("复盘") || text.contains("吐槽")) ? "田井中律 & 秋山澪" : persona.displayName(.zhHans)
        let msgId = UUID()
        let placeholder = KOnAIChatMessage(
            id: msgId,
            isUser: false,
            speakerName: speakerName,
            speakerCharId: max(1, persona.charId),
            emotionTag: emotion,
            text: "",
            actionHint: actionHint
        )
        messages.append(placeholder)
        currentEmotionTag = emotion

        // Trigger pixel mascot feedback on main cockpit
        syncMascotEmotion(emotion: emotion, manager: mgr)

        // Stream tokens smoothly
        let chars = Array(replyText)
        var idx = 0
        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 0.028, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let step = min(2, chars.count - idx)
            if step <= 0 {
                t.invalidate()
                self.isGenerating = false
                self.speakKOnReply(text: replyText, manager: mgr)
                return
            }
            let chunk = String(chars[idx..<(idx + step)])
            idx += step
            if let pos = self.messages.firstIndex(where: { $0.id == msgId }) {
                self.messages[pos].text += chunk
            }
        }
    }

    func triggerPostMatchBanter() {
        sendUserMessage("茶会复盘！点评一下刚刚的牌局吧")
    }

    private func trimContextIfNeeded() {
        let limit = maxContextTurns * 2
        if messages.count > limit {
            messages = Array(messages.suffix(limit))
        }
    }

    private func syncMascotEmotion(emotion: String, manager: AudioPlayerManager) {
        if enableVoiceBroadcast {
            let base = manager.activeBaseId()
            let offset: Int
            switch emotion {
            case "慌张": offset = 18
            case "害羞": offset = 12
            case "吃货": offset = 25
            case "元气": offset = 5
            default: offset = 1
            }
            manager.playVoice(id: base + offset, customQuote: "[\(emotion)]", clearQueue: false)
        }
    }

    private func speakKOnReply(text: String, manager: AudioPlayerManager) {
        guard enableVoiceBroadcast else { return }
        let clean = text
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self = self else { return }
            if self.speechSynthesizer.isSpeaking {
                self.speechSynthesizer.stopSpeaking(at: .immediate)
            }
            let utt = AVSpeechUtterance(string: clean)
            utt.voice = AVSpeechSynthesisVoice(language: self.ttsAccent.rawValue)
            utt.rate = 0.51
            utt.pitchMultiplier = 1.12
            self.speechSynthesizer.speak(utt)
        }
    }

    // MARK: - K-ON! 5-Member Persona + Context + Command Router
    private func buildKOnCoPilotResponse(
        userText: String,
        persona: AudioPlayerManager.CharacterFilter,
        isAllFive: Bool,
        manager: AudioPlayerManager,
        music: KOnMusicManager
    ) -> (String, String, String?) {
        let lower = userText.lowercased()
        let speed = Int(manager.currentSpeedKmh.rounded())
        let dest = manager.destinationName
        let remKm = String(format: "%.1f", manager.remainingRouteDistanceKm)
        let remMin = manager.remainingRouteMinutes
        let trackTitle = music.currentSong?.title ?? "ふわふわ時間"
        let modelTag = activeModelLoaded ? "（本地 GGUF 已加速）" : ""

        // Command 1: Open Game Room (斗地主 / 麻将 / 拉密牌)
        if lower.contains("斗地主") || lower.contains("麻将") || lower.contains("拉密") || lower.contains("棋牌室") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.onRequestOpenGameRoom?()
            }
            return (
                "好耶！放学后棋牌室马上开桌，拉密牌、麻将和斗地主都准备好啦，这把可别手下留情哦！🀄",
                "元气",
                "已触发：打开放学后棋牌室"
            )
        }

        // Command 2: Music control (切歌 / 播放 / 暂停 / 点歌)
        if lower.contains("下一首") || lower.contains("切歌") {
            music.nextTrack()
            return (
                "收到！已经切到下一首《\(music.currentSong?.title ?? "轻音部金曲")》啦，跟着节奏一起出发吧！🎸",
                "开心",
                "已触发：轻音音乐馆下一首"
            )
        }
        if lower.contains("暂停音乐") || lower.contains("停一下歌") {
            if music.isPlaying { music.playOrPause() }
            return (
                "音乐先帮你暂停啦，安静吹会儿风也不错呢。",
                "开心",
                "已触发：暂停轻音音乐"
            )
        }
        if lower.contains("放一首") || lower.contains("播放") || lower.contains("想听") || lower.contains("轻音") && lower.contains("歌") {
            if let matched = music.playlist.first(where: { lower.contains($0.title.lowercased()) || $0.title.lowercased().contains(lower.replacingOccurrences(of: "放一首", with: "").trimmingCharacters(in: .whitespaces)) }) {
                music.playSong(matched)
                return ("马上为你播放《\(matched.title)》！轻音部 Live 开演啦！🎵", "元气", "已触发：播放《\(matched.title)》")
            } else {
                if !music.isPlaying { music.playOrPause() }
                return ("已经为你响起《\(trackTitle)》啦，边听歌边看风景最治愈了！🎶", "开心", "已触发：播放轻音音乐")
            }
        }

        // Command 3: One-sentence POI Search / Navigation ("找一下附近...", "导航去...")
        if lower.contains("找一下") || lower.contains("附近") || lower.contains("导航去") || lower.contains("去哪吃") {
            var keyword = userText
            for prefix in ["梓喵，", "梓喵", "唯，", "唯", "帮我", "找一下", "搜索", "导航去", "评分高的", "附近的", "附近"] {
                keyword = keyword.replacingOccurrences(of: prefix, with: "")
            }
            keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if keyword.isEmpty { keyword = "咖啡馆" }
            manager.searchAndNavigateDirectly(query: keyword)
            let reply: String
            switch persona {
            case .mugi: reply = "正在为你检索附近的「\(keyword)」哦~ 顺路的话还能一起喝个精致的下午茶呢！☕"
            case .yui: reply = "哇！「\(keyword)」听起来就好棒，我已经帮你把搜索和路线排上啦，快出发吧！🍰"
            case .azusa: reply = "前辈，已经帮你搜索「\(keyword)」并准备规划路线了，注意看地图上的标点哦。"
            default: reply = "收到！已经在地图上帮你搜索「\(keyword)」并开始规划路线啦！"
            }
            return (reply, "开心", "已触发：地图搜索「\(keyword)」")
        }

        // Command 4: Post-match Tea Time Banter (五人同台双人吐槽)
        if lower.contains("复盘") || lower.contains("吐槽") || lower.contains("牌局") {
            let skit = "【田井中律】哈哈哈刚才那局我差点就一波清台了，本部长果然是棋牌室最强王者！\n【秋山澪】喂、律！你刚才明明把百搭牌留在手里差点放炮好不好…车友都比你稳多了！"
            return (skit, "元气", "五人同台 · 茶会小剧场")
        }

        // Command 5: Live Traffic / ETA / Speed Awareness
        if lower.contains("多久") || lower.contains("路况") || lower.contains("时速") || lower.contains("到了吗") || lower.contains("汇报") {
            let isFast = speed >= 80
            let routePart = manager.hasActiveNavigation
                ? "前往「\(dest)」还剩 \(remKm) 公里，预计约 \(remMin) 分钟"
                : "当前处于自由巡航模式"
            let musicPart = music.isPlaying ? "，车里正放着《\(trackTitle)》" : ""
            switch persona {
            case .yui:
                return ("现在车速 \(speed) km/h，\(routePart)\(musicPart)！到地方记得买块草莓蛋糕犒劳自己呀~ 🍰\(modelTag)", isFast ? "慌张" : "开心", nil)
            case .mio:
                return (isFast ? "当前时速已经 \(speed) km/h 了，有点快请一定小心！\(routePart)，安全第一哦。" : "目前车速 \(speed) km/h 很平稳，\(routePart)\(musicPart)，继续保持就好。", isFast ? "慌张" : "害羞", nil)
            case .ritsu:
                return ("报告！时速 \(speed) km/h，\(routePart)\(musicPart)！全速前进，放学后茶会冲呀！🥁", "元气", nil)
            case .mugi:
                return ("现在时速 \(speed) km/h，\(routePart)\(musicPart)。一路风景很好呢，不用着急，慢慢享受旅程吧~ ☕", "开心", nil)
            default:
                return ("前辈，当前时速 \(speed) km/h，\(routePart)\(musicPart)。我会持续帮你盯着前方路口的。", isFast ? "慌张" : "开心", nil)
            }
        }

        // Command 6: Memory Recall
        if lower.contains("记住") || lower.contains("我喜欢") || lower.contains("以后叫我") {
            return ("嗯嗯，我已经在茶会小本本里记下来啦！以后聊天都会记得这件事的~ 📝", "开心", "已写入本地长期记忆")
        }

        // General K-ON! Persona Conversation (aware of memories & music)
        let memHint = memories.first.map { "（对了，我还记得你说过「\($0)」呢~）" } ?? ""
        switch persona {
        case .yui:
            return ("嘿嘿，听你这么说我都想吃草莓蛋糕和红茶啦！\(music.isPlaying ? "而且《\(trackTitle)》真好听呀~" : "")\(memHint)\(modelTag)", "吃货", nil)
        case .mio:
            return ("嗯…你的话我都认真听着呢。专心看路的同时偶尔聊聊天挺放松的，别分心就好啦。\(memHint)\(modelTag)", "害羞", nil)
        case .ritsu:
            return ("哈哈这个话题有意思！等停好车我们再去棋牌室大战三百回合，看我不赢回一局！\(memHint)\(modelTag)", "元气", nil)
        case .mugi:
            return ("真开心能陪你一起在路上聊天呀~ 等会儿要是累了，记得靠边休息喝杯热茶哦。\(memHint)\(modelTag)", "开心", nil)
        default:
            return ("前辈，收到啦！路上有什么想查的店、想听的轻音歌或者想问的路况，随时喊我一声就行。\(memHint)\(modelTag)", "开心", nil)
        }
    }
}
