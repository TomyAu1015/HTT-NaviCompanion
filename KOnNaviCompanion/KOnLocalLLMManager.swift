import Foundation
import SwiftUI
import AVFoundation
import MapKit
import CoreLocation
#if canImport(llama)
import llama
#endif

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

// MARK: - K-ON! Real Local LLM Manager (llama.cpp Metal GPU + Co-Pilot Tools + Real Match History)
final class KOnLocalLLMManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = KOnLocalLLMManager()

    static let modelCatalog: [LocalGGUFModelSpec] = [
        LocalGGUFModelSpec(
            id: "qwen25_15b_q4",
            displayName: "Qwen2.5-1.5B-Instruct (推荐标准版)",
            subtitle: "4-bit 量化 · 中文理解与角色扮演自然 · 推荐 6GB+ 内存机型",
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

    // Settings & State
    @Published var enableVoiceBroadcast: Bool = true
    @Published var ttsAccent: KOnAITTSAccent = .mandarin
    @Published var lowMemoryGuardEnabled: Bool = true
    @Published var memories: [String] = []
    @Published var lastGameSummary: String = ""

    var onRequestOpenGameRoom: (() -> Void)? = nil

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var downloadSession: URLSession?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadTargetFileName: String?
    private var streamTimer: Timer?
    private let llmQueue = DispatchQueue(label: "com.htt.localllm.inference", qos: .userInitiated)
    private var cancelGenerationFlag: Bool = false

    #if canImport(llama)
    private var llamaModel: OpaquePointer? = nil
    private var llamaCtx: OpaquePointer? = nil
    private var llamaSampler: UnsafeMutablePointer<llama_sampler>? = nil
    private static var backendInitialized: Bool = false
    #endif

    private let memoriesKey = "htt_local_ai_memories_v1"
    private let activeModelKey = "htt_local_ai_active_model_v1"
    private let lastGameKey = "htt_local_ai_last_game_v1"

    var hasNativeLlamaEngine: Bool {
        #if canImport(llama)
        return true
        #else
        return false
        #endif
    }

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
        lastGameSummary = UserDefaults.standard.string(forKey: lastGameKey) ?? ""
        refreshInstalledModels()
        seedGreetingIfNeeded()
    }

    private func todayDateKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func loadTodayStats() -> [String: Int] {
        let k = "htt_daily_stats_" + todayDateKey()
        return (UserDefaults.standard.dictionary(forKey: k) as? [String: Int]) ?? [:]
    }

    private func saveTodayStats(_ dict: [String: Int]) {
        let k = "htt_daily_stats_" + todayDateKey()
        UserDefaults.standard.set(dict, forKey: k)
    }

    func todaySummaryText() -> String {
        let st = loadTodayStats()
        var parts: [String] = []
        let games = [("斗地主", "ddz"), ("广东红中麻将", "mj"), ("拉密数字牌", "rmk")]
        for (label, code) in games {
            let w = st["\(code)_w"] ?? 0
            let l = st["\(code)_l"] ?? 0
            if w + l > 0 {
                parts.append("\(label) \(w)胜\(l)负")
            }
        }
        return parts.isEmpty ? "今日暂无已结算牌局" : parts.joined(separator: "，")
    }

    // Called by Mahjong / Doudizhu / Rummikub engines when a round finishes
    func recordGameOutcome(gameName: String, didWin: Bool, detail: String) {
        let outcome = didWin ? "你赢了！" : "惜败"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let summary = "[\(tf.string(from: Date()))] \(gameName)（\(outcome) · \(detail)）"
        DispatchQueue.main.async {
            self.lastGameSummary = summary
            UserDefaults.standard.set(summary, forKey: self.lastGameKey)
            var st = self.loadTodayStats()
            let code = gameName.contains("斗地主") ? "ddz" : (gameName.contains("麻将") ? "mj" : "rmk")
            let key = didWin ? "\(code)_w" : "\(code)_l"
            st[key] = (st[key] ?? 0) + 1
            self.saveTodayStats(st)
        }
    }

    // MARK: - Model Files Management (Download / Import / Inspect / Native llama.cpp Load & Unload)
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
        statusMessage = "正在安全挂载本地大模型..."
        let ctxLen: UInt32 = (lowMemoryGuardEnabled || devicePhysicalRamGB < 5.5) ? 512 : 1024

        llmQueue.async { [weak self] in
            guard let self = self else { return }
            self.freeNativeLlamaOnQueue()

            #if canImport(llama)
            if !KOnLocalLLMManager.backendInitialized {
                llama_backend_init()
                KOnLocalLLMManager.backendInitialized = true
            }
            var mparams = llama_model_default_params()
            // Use ARM64 NEON + Accelerate CPU with mmap (0 GPU layers) to avoid Metal shader abort & iOS Jetsam OOM crashes!
            mparams.n_gpu_layers = 0
            mparams.use_mmap = true
            guard let model = llama_model_load_from_file(url.path, mparams) else {
                DispatchQueue.main.async {
                    self.activeModelLoaded = false
                    self.statusMessage = "模型加载失败（内存不足或文件损坏，建议改用 0.5B 轻量版）"
                }
                return
            }
            var cparams = llama_context_default_params()
            cparams.n_ctx = ctxLen
            cparams.n_batch = 128
            let thr = Int32(max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
            cparams.n_threads = thr
            cparams.n_threads_batch = thr
            guard let ctx = llama_init_from_model(model, cparams) else {
                llama_model_free(model)
                DispatchQueue.main.async {
                    self.activeModelLoaded = false
                    self.statusMessage = "无法初始化上下文（建议开启低内存保护或换 0.5B）"
                }
                return
            }
            let sparams = llama_sampler_chain_default_params()
            let smpl = llama_sampler_chain_init(sparams)
            llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.75))
            llama_sampler_chain_add(smpl, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))

            self.llamaModel = model
            self.llamaCtx = ctx
            self.llamaSampler = smpl
            #endif

            DispatchQueue.main.async {
                self.activeModelFileName = fileName
                self.activeModelInfo = info
                self.activeModelLoaded = true
                UserDefaults.standard.set(fileName, forKey: self.activeModelKey)
                let engineTag = self.hasNativeLlamaEngine ? "llama.cpp 本地引擎已就绪" : "GGUF 已挂载"
                self.statusMessage = "\(engineTag)：\(fileName) (v\(info.version), \(info.tensorCount) tensors)"
            }
        }
    }

    private func freeNativeLlamaOnQueue() {
        #if canImport(llama)
        if let s = llamaSampler {
            llama_sampler_free(s)
            llamaSampler = nil
        }
        if let c = llamaCtx {
            llama_free(c)
            llamaCtx = nil
        }
        if let m = llamaModel {
            llama_model_free(m)
            llamaModel = nil
        }
        #endif
    }

    func unloadModelFromMemory(silent: Bool = false) {
        cancelGenerationFlag = true
        llmQueue.async { [weak self] in
            self?.freeNativeLlamaOnQueue()
            DispatchQueue.main.async {
                self?.activeModelLoaded = false
                if !silent {
                    self?.statusMessage = "已释放模型内存，保障导航与棋牌室流畅运行"
                }
            }
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

    // MARK: - Greeting & Persona
    func seedGreetingIfNeeded() {
        guard messages.isEmpty else { return }
        let mgr = AudioPlayerManager.shared
        let char = activePersonaCharacter(from: mgr.selectedCharacter)
        let greeting: String
        switch char {
        case .yui: greeting = "嗨嗨！我是平泽唯~ 导航路上无聊的话随时找我聊天，查时间、问路线、找附近咖啡馆或者切歌都行哦！"
        case .mio: greeting = "你好，我是秋山澪。路上我会帮你盯着车速和路线，有需要随时吩咐就好，请安全驾驶。"
        case .ritsu: greeting = "哟！轻音部部长田井中律参上！想听歌、找附近美食还是开一局棋牌室，一句话的事儿！"
        case .mugi: greeting = "欢迎来到放课后茶会副驾呀~ 我是琴吹紬，要不要先听首轻音曲子配下午茶呢？"
        case .azusa: greeting = "前辈你好，我是中野梓。实时路况、音乐馆和棋牌室我都帮你盯着呢，有什么问题直接问就行。"
        case .all: greeting = "放课后茶会五人全员集合！随时可以和我们聊天、听歌、查路况或者赛后复盘哦！"
        }
        messages.append(KOnAIChatMessage(isUser: false, speakerName: char.displayName(.zhHans), speakerCharId: max(1, char.charId), emotionTag: "开心", text: greeting))
    }

    private func activePersonaCharacter(from filter: AudioPlayerManager.CharacterFilter) -> AudioPlayerManager.CharacterFilter {
        return filter == .all ? .yui : filter
    }

    private func currentTimeString() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return fmt.string(from: Date())
    }

    // MARK: - Main Chat Entry Point (Real Tools + Real llama.cpp Inference!)
    func sendUserMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(KOnAIChatMessage(isUser: true, speakerName: "轻音车友", speakerCharId: 0, emotionTag: "", text: text))
        trimContextIfNeeded()

        isGenerating = true
        cancelGenerationFlag = false
        let mgr = AudioPlayerManager.shared
        let music = KOnMusicManager.shared
        let isAllFive = (mgr.selectedCharacter == .all)
        let persona = activePersonaCharacter(from: mgr.selectedCharacter)
        let lower = text.lowercased()

        if text.contains("记住") || text.contains("我喜欢") || text.contains("以后叫我") {
            let mem = text.replacingOccurrences(of: "记住", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if mem.count >= 2 { addMemory(mem) }
        }

        // 1. Direct Real-Time Tool: Current Time / Date ("现在几点", "今天几号")
        if lower.contains("几点") || lower.contains("时间") && (lower.contains("现在") || lower.contains("当前")) || lower.contains("几号") || lower.contains("星期几") {
            let nowStr = currentTimeString()
            emitStreamedReply(
                speaker: persona.displayName(.zhHans),
                charId: max(1, persona.charId),
                emotion: "开心",
                text: "现在是 \(nowStr) 哦！路上注意安排好时间，别太赶啦~",
                actionHint: "实时系统时钟"
            )
            return
        }

        // 1.5 Direct Real-Time Tool: Active Navigation & Traffic Status Report ("路况汇报", "当前路况") — MUST come BEFORE "到XX要多久"!
        if lower.contains("路况") || lower.contains("汇报") || lower.contains("当前路线") || lower.contains("时速") {
            let speed = Int(mgr.currentSpeedKmh.rounded())
            let musicPart = music.isPlaying ? "，车里正放着《\(music.currentSong?.title ?? "轻音歌曲")》" : ""
            if mgr.hasActiveNavigation {
                let remKm = String(format: "%.1f", mgr.remainingRouteDistanceKm)
                let remMin = mgr.remainingRouteMinutes
                emitStreamedReply(
                    speaker: persona.displayName(.zhHans),
                    charId: max(1, persona.charId),
                    emotion: speed >= 80 ? "慌张" : "开心",
                    text: "正在前往「\(mgr.destinationName)」，还剩 \(remKm) 公里，预计约 \(remMin) 分钟到达。当前车速 \(speed) km/h\(musicPart)。",
                    actionHint: "实时导航：\(mgr.destinationName) · 剩 \(remKm) km · \(remMin) 分钟"
                )
            } else {
                emitStreamedReply(
                    speaker: persona.displayName(.zhHans),
                    charId: max(1, persona.charId),
                    emotion: "开心",
                    text: "当前未开启导航（自由巡航模式），实时车速 \(speed) km/h\(musicPart)。如果想查去某个地方要多久，可以直接问我「到XX要多久」哦！",
                    actionHint: "自由巡航 · \(speed) km/h"
                )
            }
            return
        }

        // 2. Direct Real-Time Tool: Specific Destination ETA ("到丹竹头地铁站要多久", "去香港石硖尾要多久")
        if (lower.contains("到") || lower.contains("去")) && (lower.contains("多久") || lower.contains("多远") || lower.contains("几公里") || lower.contains("几分钟")) {
            let destQuery = extractDestinationFromETAQuery(text)
            if !destQuery.isEmpty && !destQuery.contains("汇报") && !destQuery.contains("路况") {
                queryRealDestinationETA(destQuery: destQuery, persona: persona, manager: mgr)
                return
            }
        }

        // 3. Direct Real-Time Tool: Nearby POI Search Sorted Strictly By Distance (3km -> 8km!)
        if lower.contains("附近") || lower.contains("最近") || lower.contains("找一下") || lower.contains("找一个") || lower.contains("找个") || lower.contains("帮我找") || lower.contains("导航去") || lower.contains("有什么好吃") || lower.contains("好吃的") {
            let keyword = extractNearbyKeyword(from: text)
            searchNearestPOIAndNavigate(keyword: keyword, persona: persona, manager: mgr)
            return
        }

        // 4. Direct App Controls: Game Room / Music
        if lower.contains("斗地主") || lower.contains("麻将") || lower.contains("拉密") || lower.contains("棋牌室") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onRequestOpenGameRoom?()
            }
            emitStreamedReply(
                speaker: persona.displayName(.zhHans),
                charId: max(1, persona.charId),
                emotion: "元气",
                text: "好耶！放学后棋牌室马上开桌，拉密牌、广东红中麻将和斗地主都准备好啦，这把可别手下留情哦！",
                actionHint: "已触发：打开放学后棋牌室"
            )
            return
        }

        if lower.contains("下一首") || lower.contains("切歌") {
            music.nextTrack()
            let t = music.currentSong?.title ?? "轻音部金曲"
            emitStreamedReply(speaker: persona.displayName(.zhHans), charId: max(1, persona.charId), emotion: "开心", text: "收到！已经切到下一首《\(t)》啦，跟着节奏一起出发吧！", actionHint: "已触发：轻音音乐馆下一首")
            return
        }
        if lower.contains("暂停音乐") || lower.contains("停一下歌") || lower.contains("停止音乐") {
            if music.isPlaying { music.playOrPause() }
            emitStreamedReply(speaker: persona.displayName(.zhHans), charId: max(1, persona.charId), emotion: "开心", text: "音乐先帮你暂停啦，安静吹会儿风也不错呢。", actionHint: "已触发：暂停轻音音乐")
            return
        }
        if lower.contains("放一首") || lower.contains("播放音乐") || lower.contains("想听") {
            if let matched = music.playlist.first(where: { lower.contains($0.title.lowercased()) }) {
                music.playSong(matched)
                emitStreamedReply(speaker: persona.displayName(.zhHans), charId: max(1, persona.charId), emotion: "元气", text: "马上为你播放《\(matched.title)》！轻音部 Live 开演啦！", actionHint: "已触发：播放《\(matched.title)》")
            } else {
                if !music.isPlaying { music.playOrPause() }
                let t = music.currentSong?.title ?? "Cagayake! GIRLS"
                emitStreamedReply(speaker: persona.displayName(.zhHans), charId: max(1, persona.charId), emotion: "开心", text: "已经为你响起《\(t)》啦，边听歌边看风景最治愈了！", actionHint: "已触发：播放轻音音乐")
            }
            return
        }

        // 5. Real Post-Match Recap: Today's 3-game summary (斗地主 + 麻将 + 拉密牌) + Last Game Result!
        if lower.contains("复盘") || lower.contains("吐槽") || lower.contains("牌局") || lower.contains("战绩") {
            let speakerName = isAllFive ? "田井中律 & 秋山澪" : persona.displayName(.zhHans)
            let todaySum = todaySummaryText()
            let lastLine = lastGameSummary.isEmpty ? "暂无最近一局记录" : lastGameSummary
            let headerHint = "今日汇总：\(todaySum)"
            if activeModelLoaded && hasNativeLlamaEngine {
                let recapPrompt = "今日放学后棋牌室战绩汇总：【\(todaySum)】；最近一局战绩：【\(lastLine)】。请先简明报出今日汇总和最后一局战绩，再用田井中律和秋山澪一唱一和的口吻点评两句（如果车友赢了就夸奖车友）。"
                runRealLlamaInference(userPrompt: recapPrompt, persona: persona, speakerOverride: speakerName, actionHint: headerHint)
            } else {
                let comment: String
                if !lastGameSummary.isEmpty && lastGameSummary.contains("你赢了") {
                    comment = "【田井中律】哇！最后一局赢得太帅啦，本部长甘拜下风！\n【秋山澪】节奏非常稳，律你可得好好向车友学学呢！"
                } else if !lastGameSummary.isEmpty {
                    comment = "【田井中律】最后那局就差一点点翻盘，再来一把肯定赢回来！\n【秋山澪】喝口红茶放松一下，下局一定手气爆棚。"
                } else {
                    comment = "【田井中律】今天还没开张呢，快去棋牌室搓一把，打完我给你激情复盘！\n【秋山澪】赢了的话我请大家喝红茶哦。"
                }
                let fullRecap = "📊 今日棋牌汇总：\(todaySum)\n🏁 最近一局：\(lastLine)\n\(comment)"
                emitStreamedReply(speaker: speakerName, charId: max(1, persona.charId), emotion: "元气", text: fullRecap, actionHint: headerHint)
            }
            return
        }

        // 6. General Conversation & Knowledge Questions -> REAL llama.cpp Metal GPU Inference!
        if activeModelLoaded && hasNativeLlamaEngine {
            runRealLlamaInference(userPrompt: text, persona: persona, speakerOverride: nil, actionHint: nil)
        } else {
            // Honest prompt when no GGUF is loaded yet
            let speed = Int(mgr.currentSpeedKmh.rounded())
            let fallback: String
            if lower.contains("路况") || lower.contains("时速") || lower.contains("汇报") {
                let routePart = mgr.hasActiveNavigation
                    ? "前往「\(mgr.destinationName)」还剩 \(String(format: "%.1f", mgr.remainingRouteDistanceKm)) 公里，约 \(mgr.remainingRouteMinutes) 分钟"
                    : "当前处于自由巡航模式"
                fallback = "现在是 \(currentTimeString())，当前车速 \(speed) km/h，\(routePart)。"
            } else {
                if activeModelLoaded && !hasNativeLlamaEngine {
                    fallback = "已检测到本地模型（\(activeModelFileName)），但当前 IPA 尚未链接原生 llama.cpp 引擎。请用最新更新包里的 .github/workflows/build-ipa.yml 重新构建安装即可启用真本地推理！"
                } else {
                    fallback = "当前还未加载本地大模型文件，请点击上方「本地模型与记忆」挂载已下载的 Qwen2.5 模型，这样我就能自由回答你的各种问题啦！"
                }
            }
            emitStreamedReply(speaker: persona.displayName(.zhHans), charId: max(1, persona.charId), emotion: "开心", text: fallback, actionHint: nil)
        }
    }

    // MARK: - Real llama.cpp Metal GPU Autoregressive Generation
    private func runRealLlamaInference(
        userPrompt: String,
        persona: AudioPlayerManager.CharacterFilter,
        speakerOverride: String?,
        actionHint: String?
    ) {
        let mgr = AudioPlayerManager.shared
        let music = KOnMusicManager.shared
        let nowStr = currentTimeString()
        let speed = Int(mgr.currentSpeedKmh.rounded())
        let navState = mgr.hasActiveNavigation
            ? "正在导航去「\(mgr.destinationName)」，剩余\(String(format: "%.1f", mgr.remainingRouteDistanceKm))公里、约\(mgr.remainingRouteMinutes)分钟"
            : "当前未开启导航（自由巡航）"
        let songStr = music.isPlaying ? (music.currentSong?.title ?? "轻音歌曲") : "未播放"
        let memStr = memories.isEmpty ? "无" : memories.prefix(5).joined(separator: "；")
        let gameStr = lastGameSummary.isEmpty ? "暂无" : lastGameSummary

        let personaRole: String
        switch persona {
        case .yui: personaRole = "你是《轻音少女》的平泽唯，性格开朗天然、喜欢草莓蛋糕和下午茶。"
        case .mio: personaRole = "你是《轻音少女》的秋山澪，认真温柔略带害羞，关心行车安全。"
        case .ritsu: personaRole = "你是《轻音少女》的田井中律，元气爽朗爱开玩笑，是轻音部部长。"
        case .mugi: personaRole = "你是《轻音少女》的琴吹紬，温柔体贴的大小姐，喜欢红茶和美食。"
        default: personaRole = "你是《轻音少女》的中野梓，认真靠谱的后辈，称呼用户为前辈。"
        }

        let sysPrompt = """
        \(personaRole)你正在作为车载副驾助手陪伴用户。
        实时信息：当前时间 \(nowStr)；车速 \(speed) km/h；\(navState)；音乐：\(songStr)；最近牌局：\(gameStr)；用户记忆：\(memStr)。
        要求：用自然简短的中文口语（2~4句话以内）准确回答用户的问题，贴合角色性格，不要编造不存在的系统提示，不要输出“本地GGUF”字样。
        """

        // Build Qwen2.5 ChatML prompt with recent turns
        var fullPrompt = "<|im_start|>system\n\(sysPrompt)<|im_end|>\n"
        let recent = messages.dropLast().suffix(4)
        for m in recent {
            let role = m.isUser ? "user" : "assistant"
            let snippet = String(m.text.prefix(120))
            fullPrompt += "<|im_start|>\(role)\n\(snippet)<|im_end|>\n"
        }
        fullPrompt += "<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n"

        let msgId = UUID()
        let spk = speakerOverride ?? persona.displayName(.zhHans)
        messages.append(KOnAIChatMessage(id: msgId, isUser: false, speakerName: spk, speakerCharId: max(1, persona.charId), emotionTag: "开心", text: "", actionHint: actionHint))
        currentEmotionTag = "开心"

        llmQueue.async { [weak self] in
            guard let self = self else { return }
            var accumulated = ""

            #if canImport(llama)
            guard let model = self.llamaModel, let ctx = self.llamaCtx, let smpl = self.llamaSampler else {
                DispatchQueue.main.async {
                    self.finishBubble(id: msgId, finalText: "本地模型尚未完成加载，请在「本地模型与记忆」中重新点击挂载。")
                }
                return
            }
            let vocab = llama_model_get_vocab(model)
            let utf8Count = fullPrompt.utf8.count
            let maxToks = utf8Count + 64
            var tokens = [llama_token](repeating: 0, count: maxToks)
            let nTokens = fullPrompt.withCString { cstr in
                llama_tokenize(vocab, cstr, Int32(utf8Count), &tokens, Int32(maxToks), true, true)
            }
            guard nTokens > 0 else {
                DispatchQueue.main.async {
                    self.finishBubble(id: msgId, finalText: "模型分词失败，请尝试换一句简短的话问我。")
                }
                return
            }

            llama_kv_cache_clear(ctx)
            var offset = 0
            while offset < Int(nTokens) {
                let step = min(200, Int(nTokens) - offset)
                var slice = Array(tokens[offset..<(offset + step)])
                let rc = slice.withUnsafeMutableBufferPointer { buf -> Int32 in
                    let batch = llama_batch_get_one(buf.baseAddress, Int32(step))
                    return llama_decode(ctx, batch)
                }
                if rc != 0 { break }
                offset += step
            }

            var utf8Pending: [UInt8] = []
            for _ in 0..<180 {
                if self.cancelGenerationFlag { break }
                let newTok = llama_sampler_sample(smpl, ctx, -1)
                if llama_vocab_is_eog(vocab, newTok) { break }

                var pieceBuf = [CChar](repeating: 0, count: 64)
                let n = llama_token_to_piece(vocab, newTok, &pieceBuf, Int32(pieceBuf.count), 0, true)
                if n > 0 {
                    for i in 0..<Int(n) {
                        utf8Pending.append(UInt8(bitPattern: pieceBuf[i]))
                    }
                    if let piece = String(bytes: utf8Pending, encoding: .utf8) {
                        utf8Pending.removeAll()
                        if piece.contains("<|im_end|>") || piece.contains("<|endoftext|>") { break }
                        accumulated += piece
                        let snapshot = accumulated
                        DispatchQueue.main.async {
                            if let idx = self.messages.firstIndex(where: { $0.id == msgId }) {
                                self.messages[idx].text = snapshot
                            }
                        }
                    }
                }

                var nextTok = newTok
                let rc = withUnsafeMutablePointer(to: &nextTok) { ptr -> Int32 in
                    let batch = llama_batch_get_one(ptr, 1)
                    return llama_decode(ctx, batch)
                }
                if rc != 0 { break }
            }
            #endif

            let finalOut = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.finishBubble(id: msgId, finalText: finalOut.isEmpty ? "嗯…我刚刚走神了一下，可以再问我一次吗？" : finalOut)
            }
        }
    }

    private func finishBubble(id: UUID, finalText: String) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].text = finalText
        }
        isGenerating = false
        speakOfflineTTSOnly(finalText)
    }

    // MARK: - Real Nearby Search (Strictly 3km -> 8km Radius & Sorted by Distance!)
    private func extractNearbyKeyword(from text: String) -> String {
        var kw = text
        for noise in ["梓喵，", "梓喵", "唯，", "唯", "帮我找", "帮我", "找一下", "找一个", "找个", "找找", "搜索", "导航去", "评分高的", "最近的", "最近", "附近的", "附近", "一个", "有什么好吃的", "有什么好吃", "好吃的", "想吃", "去哪吃"] {
            kw = kw.replacingOccurrences(of: noise, with: "")
        }
        kw = kw.trimmingCharacters(in: .whitespacesAndNewlines)
        if kw.isEmpty {
            return text.contains("咖啡") ? "咖啡" : "美食"
        }
        return kw
    }

    private func searchNearestPOIAndNavigate(keyword: String, persona: AudioPlayerManager.CharacterFilter, manager: AudioPlayerManager) {
        let userCoord = manager.userCoordinate
        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)

        func runSearch(radiusMeters: CLLocationDistance, allowExpand: Bool) {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = keyword
            req.resultTypes = [.pointOfInterest, .address]
            req.region = MKCoordinateRegion(center: userCoord, latitudinalMeters: radiusMeters * 2, longitudinalMeters: radiusMeters * 2)

            MKLocalSearch(request: req).start { [weak self] resp, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let items = resp?.mapItems ?? []
                    let sorted = items.sorted { a, b in
                        let la = CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)
                        let lb = CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude)
                        return la.distance(from: userLoc) < lb.distance(from: userLoc)
                    }
                    if let nearest = sorted.first {
                        let dMeters = CLLocation(latitude: nearest.placemark.coordinate.latitude, longitude: nearest.placemark.coordinate.longitude).distance(from: userLoc)
                        if dMeters > 12000 && allowExpand {
                            // Never jump 32km across the border if we can retry tight keyword
                            runSearch(radiusMeters: 2500, allowExpand: false)
                            return
                        }
                        let distStr = dMeters < 1000 ? "\(Int(dMeters)) 米" : String(format: "%.1f 公里", dMeters / 1000.0)
                        let shopName = nearest.name ?? keyword
                        manager.showMapMode = true
                        manager.isMapEnlarged = true
                        manager.isNavigatingFocused = false
                        manager.startRouteGuidance(to: nearest)
                        self.emitStreamedReply(
                            speaker: persona.displayName(.zhHans),
                            charId: max(1, persona.charId),
                            emotion: "开心",
                            text: "找到离你最近的「\(shopName)」啦，直线距离约 \(distStr)，已经帮你规划好路线咯！",
                            actionHint: "最近地点：\(shopName)（\(distStr)）"
                        )
                    } else if allowExpand {
                        runSearch(radiusMeters: 8000, allowExpand: false)
                    } else {
                        self.emitStreamedReply(
                            speaker: persona.displayName(.zhHans),
                            charId: max(1, persona.charId),
                            emotion: "害羞",
                            text: "附近 8 公里内暂时没搜到「\(keyword)」，可以换个关键词试试哦。",
                            actionHint: nil
                        )
                    }
                }
            }
        }
        runSearch(radiusMeters: 3000, allowExpand: true)
    }

    // MARK: - Real Destination ETA Query ("到丹竹头地铁站要多久", "到香港石硖尾要多久")
    private func extractDestinationFromETAQuery(_ text: String) -> String {
        var s = text
        for prefix in ["请问", "帮我查一下", "帮我查", "现在", "从这里", "从这", "开车", "步行", "坐地铁", "坐公交", "到", "去"] {
            if let r = s.range(of: prefix), r.lowerBound == s.startIndex {
                s = String(s[r.upperBound...])
            }
        }
        for suffix in ["要多久", "需要多久", "要多长时间", "要几分钟", "有多远", "几公里", "怎么走", "多久", "多远", "？", "?"] {
            if let r = s.range(of: suffix) {
                s = String(s[..<r.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queryRealDestinationETA(destQuery: String, persona: AudioPlayerManager.CharacterFilter, manager: AudioPlayerManager) {
        let userCoord = manager.userCoordinate
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = destQuery
        req.region = MKCoordinateRegion(center: userCoord, latitudinalMeters: 80000, longitudinalMeters: 80000)

        MKLocalSearch(request: req).start { [weak self] resp, _ in
            guard let self = self else { return }
            guard let item = resp?.mapItems.first else {
                DispatchQueue.main.async {
                    self.emitStreamedReply(speaker: persona.displayName(.zhHans), charId: max(1, persona.charId), emotion: "害羞", text: "暂时没在地图上找到「\(destQuery)」，可以加上城市名再问我一次哦。", actionHint: nil)
                }
                return
            }
            let dirReq = MKDirections.Request()
            dirReq.source = MKMapItem(placemark: MKPlacemark(coordinate: userCoord))
            dirReq.destination = item
            dirReq.transportType = (manager.travelMode == .walking) ? .walking : .automobile
            MKDirections(request: dirReq).calculate { dResp, _ in
                DispatchQueue.main.async {
                    let placeName = item.name ?? destQuery
                    if let r = dResp?.routes.first {
                        let km = String(format: "%.1f", r.distance / 1000.0)
                        let mins = max(1, Int((r.expectedTravelTime / 60.0).rounded()))
                        let modeName = (manager.travelMode == .walking) ? "步行" : "驾车"
                        self.emitStreamedReply(
                            speaker: persona.displayName(.zhHans),
                            charId: max(1, persona.charId),
                            emotion: "开心",
                            text: "查到啦！从当前位置到「\(placeName)」大约 \(km) 公里，\(modeName)预计需要 \(mins) 分钟左右哦。需要我直接帮你开启导航吗？",
                            actionHint: "实时测算：\(placeName) · \(km) km · 约 \(mins) 分钟"
                        )
                    } else {
                        let dKm = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude).distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)) / 1000.0
                        self.emitStreamedReply(
                            speaker: persona.displayName(.zhHans),
                            charId: max(1, persona.charId),
                            emotion: "开心",
                            text: "「\(placeName)」距离你直线约 \(String(format: "%.1f", dKm)) 公里，目前跨区路线暂时无法直连测算，可以直接在地图里查看换乘方案哦。",
                            actionHint: "直线距离约 \(String(format: "%.1f", dKm)) km"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Smooth Typewriter & Clean Offline TTS (No wrong nav-distance voice, no "GGUF" readout!)
    private func emitStreamedReply(speaker: String, charId: Int, emotion: String, text: String, actionHint: String?) {
        let msgId = UUID()
        messages.append(KOnAIChatMessage(id: msgId, isUser: false, speakerName: speaker, speakerCharId: charId, emotionTag: emotion, text: "", actionHint: actionHint))
        currentEmotionTag = emotion

        let chars = Array(text)
        var idx = 0
        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let step = min(2, chars.count - idx)
            if step <= 0 {
                t.invalidate()
                self.isGenerating = false
                self.speakOfflineTTSOnly(text)
                return
            }
            let chunk = String(chars[idx..<(idx + step)])
            idx += step
            if let pos = self.messages.firstIndex(where: { $0.id == msgId }) {
                self.messages[pos].text += chunk
            }
        }
    }

    private func trimContextIfNeeded() {
        let limit = maxContextTurns * 2
        if messages.count > limit {
            messages = Array(messages.suffix(limit))
        }
    }

    private func speakOfflineTTSOnly(_ text: String) {
        guard enableVoiceBroadcast else { return }
        // Strip bracket tags and emojis so TTS speaks natural clean Mandarin/Cantonese only!
        var clean = text.replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"【[^】]+】"#, with: "", options: .regularExpression)
        clean = clean.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.map { String($0) }.joined()
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utt = AVSpeechUtterance(string: clean)
        utt.voice = AVSpeechSynthesisVoice(language: ttsAccent.rawValue)
        utt.rate = 0.51
        utt.pitchMultiplier = 1.12
        speechSynthesizer.speak(utt)
    }
}
