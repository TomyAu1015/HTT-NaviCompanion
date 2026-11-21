import Foundation
import Darwin
import SwiftUI
import UIKit
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

struct KOnAINearbyPlace: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let address: String
    let distanceMeters: Double
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), name: String, address: String, distanceMeters: Double, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.address = address
        self.distanceMeters = distanceMeters
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct KOnAIChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let isUser: Bool
    let speakerName: String
    let speakerCharId: Int
    let emotionTag: String
    var text: String
    let actionHint: String?
    let nearbyPlaces: [KOnAINearbyPlace]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        isUser: Bool,
        speakerName: String,
        speakerCharId: Int = 1,
        emotionTag: String = "开心",
        text: String,
        actionHint: String? = nil,
        nearbyPlaces: [KOnAINearbyPlace] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.isUser = isUser
        self.speakerName = speakerName
        self.speakerCharId = speakerCharId
        self.emotionTag = emotionTag
        self.text = text
        self.actionHint = actionHint
        self.nearbyPlaces = nearbyPlaces
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


// Dedicated 4MB-stack serial worker thread for llama.cpp C++ engine (prevents iOS GCD 512KB stack overflow)
private final class LlamaWorkerThread {
    private let condition = NSCondition()
    private var queue: [() -> Void] = []
    private var thread: Thread?

    init() {
        let t = Thread { [weak self] in
            self?.runLoop()
        }
        t.name = "com.htt.localllm.worker"
        t.stackSize = 4 * 1024 * 1024
        t.qualityOfService = .userInitiated
        self.thread = t
        t.start()
    }

    func async(_ block: @escaping () -> Void) {
        condition.lock()
        queue.append(block)
        condition.signal()
        condition.unlock()
    }

    private func runLoop() {
        while true {
            condition.lock()
            while queue.isEmpty {
                condition.wait()
            }
            let job = queue.removeFirst()
            condition.unlock()
            autoreleasepool {
                job()
            }
        }
    }
}

// MARK: - K-ON! Real Local LLM Manager (llama.cpp Metal GPU + Co-Pilot Tools + Real Match History)
enum CloudAIProvider: String, CaseIterable, Identifiable {
    case local = "local"
    case gemini = "gemini"
    case vertexai = "vertexai"
    case doubao = "doubao"
    case deepseek = "deepseek"
    case custom = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "本地 Qwen2.5"
        case .gemini: return "Gemini"
        case .vertexai: return "Vertex AI (香港直连)"
        case .doubao: return "豆包 Doubao"
        case .deepseek: return "DeepSeek"
        case .custom: return "自定义 OpenAI"
        }
    }

    var defaultBaseUrl: String {
        switch self {
        case .local: return ""
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .vertexai: return "https://aiplatform.googleapis.com/v1/publishers/google"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .deepseek: return "https://api.deepseek.com/v1/chat/completions"
        case .custom: return "https://api.openai.com/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .local: return ""
        case .gemini: return "gemini-3.5-flash-lite"
        case .vertexai: return "gemini-3.5-flash-lite"
        case .doubao: return "doubao-1-5-pro-32k-250115"
        case .deepseek: return "deepseek-chat"
        case .custom: return "gpt-4o-mini"
        }
    }
}

final class KOnLocalLLMManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = KOnLocalLLMManager()

    static let modelCatalog: [LocalGGUFModelSpec] = [
        LocalGGUFModelSpec(
            id: "qwen25_3b_q3",
            displayName: "Qwen2.5-3B-Instruct (高智商 3B 进阶版)",
            subtitle: "3B 参数 Q3_K_M 量化 · 对话逻辑与轻音角色扮演更自然 · 推荐 6GB+ 内存",
            fileName: "qwen2.5-3b-instruct-q3_k_m.gguf",
            sizeLabel: "约 1.63 GB",
            approxMB: 1660,
            minRamGB: 5.5,
            downloadURL: "https://hf-mirror.com/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q3_k_m.gguf"
        ),
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
            id: "qwen25_15b_q3",
            displayName: "Qwen2.5-1.5B-Instruct (省内存 1.5B)",
            subtitle: "Q3_K_M 量化 · 兼顾 1.5B 智商与 3D 导航/音乐同开余量",
            fileName: "qwen2.5-1.5b-instruct-q3_k_m.gguf",
            sizeLabel: "约 824 MB",
            approxMB: 824,
            minRamGB: 5.0,
            downloadURL: "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q3_k_m.gguf"
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
    @Published var isTtsSpeaking: Bool = false
    @Published var isLoadingModel: Bool = false
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
    @Published var enableWebSearch: Bool = true
    @Published var ttsAccent: KOnAITTSAccent = .mandarin
    @Published var lowMemoryGuardEnabled: Bool = false
    @Published var cloudProvider: CloudAIProvider = .local
    @Published var cloudApiKey: String = ""
    @Published var cloudBaseUrl: String = ""
    @Published var cloudModelName: String = ""
    @Published var cloudTestStatus: String = ""
    @Published var memories: [String] = []
    @Published var lastGameSummary: String = ""

    var onRequestOpenGameRoom: (() -> Void)? = nil

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var downloadSession: URLSession?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadTargetFileName: String?
    private var streamTimer: Timer?
    private let llmQueue = LlamaWorkerThread()
    private var activeCtxLen: Int = 512
    private var idleUnloadWorkItem: DispatchWorkItem? = nil
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
        speechSynthesizer.delegate = self
        loadPersistedMemories()
        activeModelFileName = UserDefaults.standard.string(forKey: activeModelKey) ?? ""
        let savedProv = CloudAIProvider(rawValue: UserDefaults.standard.string(forKey: "htt_cloud_provider") ?? "local") ?? .local
        cloudProvider = savedProv
        cloudApiKey = UserDefaults.standard.string(forKey: "htt_cloud_api_key") ?? ""
        let savedUrl = UserDefaults.standard.string(forKey: "htt_cloud_base_url") ?? ""
        cloudBaseUrl = savedUrl.isEmpty ? savedProv.defaultBaseUrl : savedUrl
        let savedModel = UserDefaults.standard.string(forKey: "htt_cloud_model_name") ?? ""
        cloudModelName = savedModel.isEmpty ? savedProv.defaultModel : savedModel
        lastGameSummary = UserDefaults.standard.string(forKey: lastGameKey) ?? ""
        refreshInstalledModels()
        seedGreetingIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPreviousCrashGuard()
            self?.autoMountIfNeeded()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive() {
        autoMountIfNeeded()
    }

    @objc private func handleSystemMemoryWarning() {
        guard activeModelLoaded else { return }
        cancelGenerationFlag = true
        unloadModelFromMemory(silent: true)
        DispatchQueue.main.async {
            self.statusMessage = "收到系统内存预警，已自动释放本地模型以保护 3D 导航与音乐播放"
        }
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
    private let loadingGuardKey = "htt_ai_loading_guard_v1"
    private let loadingStageKey = "htt_ai_loading_stage_v1"

    func autoMountIfNeeded() {
        guard !activeModelLoaded, !activeModelFileName.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: loadingGuardKey) else { return }
        guard installedModels.contains(activeModelFileName) else { return }
        let url = modelsDirectoryURL.appendingPathComponent(activeModelFileName)
        let info = inspectGGUFFile(at: url)
        guard info.valid else { return }
        let freeMB = availableAppMemoryMB()
        if freeMB > 0 && Int(info.fileSizeMB) + 280 > freeMB {
            statusMessage = "已记住上次模型 \(activeModelFileName)，当前可用内存 \(freeMB)MB 偏紧，可手动点击挂载或切到 0.5B"
            return
        }
        loadModelIntoMemory(fileName: activeModelFileName)
    }

    func checkPreviousCrashGuard() {
        if UserDefaults.standard.bool(forKey: loadingGuardKey) {
            let stage = UserDefaults.standard.string(forKey: loadingStageKey) ?? "unknown"
            UserDefaults.standard.set(false, forKey: loadingGuardKey)
            UserDefaults.standard.removeObject(forKey: loadingStageKey)
            activeModelLoaded = false
            statusMessage = "检测到上次挂载在阶段 [\(stage)] 异常中断，已自动保护。当前可用内存约 \(availableAppMemoryMB())MB。"
        }
    }

    var liveAvailableMemoryMB: Int {
        availableAppMemoryMB()
    }

    private func availableAppMemoryMB() -> Int {
        return Int(os_proc_available_memory() / (1024 * 1024))
    }

    func cancelIdleUnload() {
        idleUnloadWorkItem?.cancel()
        idleUnloadWorkItem = nil
    }

    func scheduleIdleUnloadIfNeeded() {
        cancelIdleUnload()
        guard activeModelLoaded else { return }
        if !lowMemoryGuardEnabled {
            // Keep resident when user disables low-memory guard (memory warning listener still protects 3D map & music)
            return
        }
        let freeMB = availableAppMemoryMB()
        if freeMB > 0 && freeMB < 700 {
            unloadModelFromMemory(silent: true)
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.activeModelLoaded, !self.isGenerating else { return }
            self.unloadModelFromMemory(silent: true)
        }
        idleUnloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 90.0, execute: item)
    }

    func refreshInstalledModels() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: modelsDirectoryURL.path)) ?? []
        let ggufs = files.filter { $0.lowercased().hasSuffix(".gguf") }.sorted()
        DispatchQueue.main.async {
            self.installedModels = ggufs
            if !self.activeModelFileName.isEmpty && !ggufs.contains(self.activeModelFileName) {
                self.activeModelFileName = ggufs.first ?? ""
                self.isLoadingModel = false
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
        let freeMB = availableAppMemoryMB()
        if freeMB > 0 && Int(info.fileSizeMB) + 220 > freeMB {
            statusMessage = "当前可用内存约 \(freeMB)MB，不足以安全载入 \(Int(info.fileSizeMB))MB 模型（建议先切回舞台模式释放地图内存，或改用 352MB 的 Qwen2.5-0.5B 轻量版）"
            return
        }
        cancelIdleUnload()
        isLoadingModel = true
        statusMessage = "正在安全挂载本地大模型（剩余可用内存约 \(freeMB)MB）..."
        UserDefaults.standard.set(true, forKey: loadingGuardKey)
        UserDefaults.standard.set("1:backend_init", forKey: loadingStageKey)
        let ctxLen: UInt32 = (lowMemoryGuardEnabled || freeMB < 1400) ? 512 : 1024

        llmQueue.async { [weak self] in
            guard let self = self else { return }
            self.freeNativeLlamaOnQueue()

            #if canImport(llama)
            if !KOnLocalLLMManager.backendInitialized {
                llama_backend_init()
                KOnLocalLLMManager.backendInitialized = true
            }
            UserDefaults.standard.set("2:load_model", forKey: self.loadingStageKey)
            var mparams = llama_model_default_params()
            // Strict CPU NEON + mmap mode keeps 100% of Metal GPU free for 3D MapKit navigation and prevents Metal shader/metallib aborts!
            mparams.n_gpu_layers = 0
            mparams.use_mmap = true
            mparams.use_mlock = false

            var loadedModel: OpaquePointer? = nil
            if let cpuDev = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU) {
                var cpuDevs: [ggml_backend_dev_t?] = [cpuDev, nil]
                loadedModel = cpuDevs.withUnsafeMutableBufferPointer { buf in
                    mparams.devices = buf.baseAddress
                    return llama_model_load_from_file(url.path, mparams)
                }
            } else {
                loadedModel = llama_model_load_from_file(url.path, mparams)
            }

            guard let model = loadedModel else {
                UserDefaults.standard.set(false, forKey: self.loadingGuardKey)
                UserDefaults.standard.removeObject(forKey: self.loadingStageKey)
                DispatchQueue.main.async {
                    self.isLoadingModel = false
                self.activeModelLoaded = false
                    self.statusMessage = "模型加载失败（文件可能损坏或内存不足，建议重新下载或改用 0.5B）"
                }
                return
            }
            UserDefaults.standard.set("3:init_context", forKey: self.loadingStageKey)
            var cparams = llama_context_default_params()
            cparams.n_ctx = ctxLen
            // CRITICAL: n_ubatch <= n_batch AND op_offload = false so llama_init_from_model never touches Metal or aborts!
            cparams.n_batch = 256
            cparams.n_ubatch = 256
            cparams.n_seq_max = 1
            cparams.offload_kqv = false
            cparams.no_perf = true
            let thr = Int32(max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
            cparams.n_threads = thr
            cparams.n_threads_batch = thr
            guard let ctx = llama_init_from_model(model, cparams) else {
                llama_model_free(model)
                UserDefaults.standard.set(false, forKey: self.loadingGuardKey)
                UserDefaults.standard.removeObject(forKey: self.loadingStageKey)
                DispatchQueue.main.async {
                    self.isLoadingModel = false
                self.activeModelLoaded = false
                    self.statusMessage = "无法初始化推理上下文（建议开启低内存保护或换 0.5B）"
                }
                return
            }
            UserDefaults.standard.set("4:init_sampler", forKey: self.loadingStageKey)
            let sparams = llama_sampler_chain_default_params()
            let smpl = llama_sampler_chain_init(sparams)
            llama_sampler_chain_add(smpl, llama_sampler_init_penalties(64, 1.12, 0.0, 0.0))
            llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.75))
            llama_sampler_chain_add(smpl, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))

            self.llamaModel = model
            self.llamaCtx = ctx
            self.llamaSampler = smpl
            self.activeCtxLen = Int(ctxLen)
            #endif

            UserDefaults.standard.set(false, forKey: self.loadingGuardKey)
            UserDefaults.standard.removeObject(forKey: self.loadingStageKey)
            DispatchQueue.main.async {
                self.activeModelFileName = fileName
                self.activeModelInfo = info
                self.isLoadingModel = false
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
    var isCloudActive: Bool {
        cloudProvider != .local && !cloudApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSavedCloudKey: Bool {
        !cloudApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleCloudLocalMode() {
        if isCloudActive {
            selectCloudProvider(.local)
            autoMountIfNeeded()
        } else if hasSavedCloudKey {
            let lastId = UserDefaults.standard.string(forKey: "htt_last_cloud_provider") ?? "gemini"
            let target = CloudAIProvider(rawValue: lastId) ?? .gemini
            selectCloudProvider(target == .local ? .gemini : target)
        }
    }

    func selectCloudProvider(_ prov: CloudAIProvider) {
        cloudProvider = prov
        if prov != .local {
            UserDefaults.standard.set(prov.rawValue, forKey: "htt_last_cloud_provider")
            let savedUrl = UserDefaults.standard.string(forKey: "htt_cloud_base_url_\(prov.rawValue)") ?? ""
            let savedModel = UserDefaults.standard.string(forKey: "htt_cloud_model_name_\(prov.rawValue)") ?? ""
            cloudBaseUrl = savedUrl.isEmpty ? prov.defaultBaseUrl : savedUrl
            cloudModelName = savedModel.isEmpty ? prov.defaultModel : savedModel
        } else {
            autoMountIfNeeded()
        }
        cloudTestStatus = prov == .local ? "已切换为 📱 本地离线 Qwen2.5（不消耗云端额度）" : ""
        UserDefaults.standard.set(prov.rawValue, forKey: "htt_cloud_provider")
        UserDefaults.standard.set(cloudBaseUrl, forKey: "htt_cloud_base_url")
        UserDefaults.standard.set(cloudModelName, forKey: "htt_cloud_model_name")
    }

    func saveCloudConfig(provider: CloudAIProvider, apiKey: String, baseUrl: String, modelName: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalProv: CloudAIProvider = (!cleanKey.isEmpty && provider == .local) ? .gemini : provider
        let cleanUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalProv.defaultBaseUrl : baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalProv.defaultModel : modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        cloudProvider = finalProv
        cloudApiKey = cleanKey
        cloudBaseUrl = cleanUrl
        cloudModelName = cleanModel
        UserDefaults.standard.set(finalProv.rawValue, forKey: "htt_cloud_provider")
        if finalProv != .local {
            UserDefaults.standard.set(finalProv.rawValue, forKey: "htt_last_cloud_provider")
            UserDefaults.standard.set(cleanUrl, forKey: "htt_cloud_base_url_\(finalProv.rawValue)")
            UserDefaults.standard.set(cleanModel, forKey: "htt_cloud_model_name_\(finalProv.rawValue)")
        }
        UserDefaults.standard.set(cleanKey, forKey: "htt_cloud_api_key")
        UserDefaults.standard.set(cleanUrl, forKey: "htt_cloud_base_url")
        UserDefaults.standard.set(cleanModel, forKey: "htt_cloud_model_name")
        cloudTestStatus = (finalProv == .local) ? "已切换回本地离线模型" : "已保存 \(finalProv.label) 配置"
    }

    func testCloudConnection() {
        guard cloudProvider != .local, !cloudApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cloudTestStatus = "请先选择 Gemini / 豆包 / DeepSeek 并填入 API Key"
            return
        }
        let prov = cloudProvider
        let key = cloudApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cloudBaseUrl
        let model = cloudModelName
        cloudTestStatus = "正在测试 \(prov.label) 连接..."
        executeCloudLLMRequest(provider: prov, apiKey: key, baseUrl: base, modelName: model, systemPrompt: "你是一个测试助手。", history: [], userPrompt: "请只回复：连接成功") { [weak self] ok, info in
            DispatchQueue.main.async {
                self?.cloudTestStatus = ok ? "✅ \(prov.label) 连接正常：\(info)" : "❌ 连接失败：\(info)"
            }
        }
    }

    func sendUserMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(KOnAIChatMessage(isUser: true, speakerName: "轻音车友", speakerCharId: 0, emotionTag: "", text: text))
        trimContextIfNeeded()

        cancelIdleUnload()
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

        // 2.5 Direct Real-Time Tool: Direct Destination Navigation ("帮我导航到丹竹头地铁站", "带我去...", "坐地铁去...", "骑车去...")
        let isDirectNavIntent = (
            lower.contains("导航到") || lower.contains("导航去") || lower.contains("帮我导航") ||
            lower.contains("带我去") || lower.contains("带我到") || lower.contains("规划路线") ||
            lower.contains("路线到") || lower.contains("开车去") || lower.contains("骑车去") ||
            lower.contains("骑行去") || lower.contains("步行去") || lower.contains("走路去") ||
            lower.contains("坐地铁去") || lower.contains("坐公交去") || lower.contains("navigate to")
        ) && !lower.contains("附近") && !lower.contains("多久") && !lower.contains("多远")
        if isDirectNavIntent {
            let destName = extractDirectNavDestination(from: text)
            if !destName.isEmpty {
                applyRequestedTravelModeIfAny(from: lower, manager: mgr)
                searchDirectDestinationAndNavigate(query: destName, persona: persona, manager: mgr)
                return
            }
        }

        // 3. Direct Real-Time Tool: Nearby POI Search Sorted Strictly By Distance (3km -> 8km!)
        if lower.contains("附近") || lower.contains("最近") || lower.contains("找一下") || lower.contains("找一个") || lower.contains("找个") || lower.contains("帮我找") || lower.contains("有什么好吃") || lower.contains("好吃的") {
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
            if isCloudActive || (activeModelLoaded && hasNativeLlamaEngine) {
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

        // 6. General Conversation & Real-Time Web Search RAG -> Real llama.cpp Inference!
        if isCloudActive || (activeModelLoaded && hasNativeLlamaEngine) {
            if isWeatherQuery(lower) {
                fetchLiveWeatherAndInfer(userText: text, persona: persona, manager: mgr)
            } else if enableWebSearch && shouldSearchWeb(for: lower) {
                fetchWebSearchAndInfer(userText: text, persona: persona)
            } else {
                runRealLlamaInference(userPrompt: text, persona: persona, speakerOverride: nil, actionHint: nil)
            }
        } else if hasNativeLlamaEngine && !activeModelFileName.isEmpty && installedModels.contains(activeModelFileName) {
            if !isLoadingModel {
                autoMountIfNeeded()
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                var waitedMs = 0
                while waitedMs < 6000 && !self.activeModelLoaded {
                    Thread.sleep(forTimeInterval: 0.2)
                    waitedMs += 200
                }
                DispatchQueue.main.async {
                    if self.activeModelLoaded {
                        if self.isWeatherQuery(lower) {
                            self.fetchLiveWeatherAndInfer(userText: text, persona: persona, manager: mgr)
                        } else if self.enableWebSearch && self.shouldSearchWeb(for: lower) {
                            self.fetchWebSearchAndInfer(userText: text, persona: persona)
                        } else {
                            self.runRealLlamaInference(userPrompt: text, persona: persona, speakerOverride: nil, actionHint: nil)
                        }
                    } else {
                        self.emitStreamedReply(speaker: persona.displayName(.zhHans), charId: max(1, persona.charId), emotion: "开心", text: "本地模型还在后台挂载初始化中，请过 2 秒再发一次试试看！", actionHint: nil)
                    }
                }
            }
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
    private func isWeatherQuery(_ lower: String) -> Bool {
        return lower.contains("天气") || lower.contains("气温") || lower.contains("温度") || lower.contains("下雨") || lower.contains("多少度") || lower.contains("天气预报")
    }

    private func shouldSearchWeb(for lower: String) -> Bool {
        // Explicit web search triggers
        if lower.contains("联网") || lower.contains("搜索") || lower.contains("查一下") || lower.contains("帮我查") || lower.contains("百科") || lower.contains("新闻") || lower.contains("最新") {
            return true
        }
        // Only trigger knowledge lookup when there is a real noun subject (>= 2 chars, not pronouns like "你/我/他/这/那")
        let explicitFact = ["是什么", "是谁", "什么是", "介绍一下"].contains { lower.contains($0) }
        if !explicitFact { return false }
        let subject = cleanSearchQueryForLookup(from: lower).replacingOccurrences(of: " ", with: "")
        let pronouns: Set<String> = ["你", "我", "他", "她", "它", "这", "那", "谁", "啥", "什么", "笨蛋"]
        return subject.count >= 2 && !pronouns.contains(subject)
    }

    private func cleanSearchQuery(from text: String) -> String {
        var q = text
        for noise in ["联网搜索", "联网查一下", "联网", "帮我查一下", "帮我查", "查一下", "搜索一下", "搜索", "你知道", "吗？", "吗?", "吗", "？", "?"] {
            q = q.replacingOccurrences(of: noise, with: " ")
        }
        q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? text : q
    }

    private func fetchLiveWeatherAndInfer(userText: String, persona: AudioPlayerManager.CharacterFilter, manager: AudioPlayerManager) {
        let coord = manager.userCoordinate
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(coord.latitude)&longitude=\(coord.longitude)&current_weather=true&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto"
        guard let url = URL(string: urlStr) else {
            runRealLlamaInference(userPrompt: userText, persona: persona, speakerOverride: nil, actionHint: nil)
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 3.0)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self else { return }
            var weatherNote: String? = nil
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cur = json["current_weather"] as? [String: Any] {
                let temp = cur["temperature"] as? Double ?? 0
                let wind = cur["windspeed"] as? Double ?? 0
                let code = cur["weathercode"] as? Int ?? 0
                let desc = self.wmoWeatherDesc(code)
                var extra = ""
                if let daily = json["daily"] as? [String: Any],
                   let tmax = (daily["temperature_2m_max"] as? [Double])?.first,
                   let tmin = (daily["temperature_2m_min"] as? [Double])?.first,
                   let pop = (daily["precipitation_probability_max"] as? [Int])?.first {
                    extra = "，今日气温 \(Int(tmin.rounded()))~\(Int(tmax.rounded()))°C，降水概率 \(pop)%"
                }
                weatherNote = "当前位置实时气象：\(desc)，气温 \(String(format: "%.1f", temp))°C，风速 \(Int(wind.rounded())) km/h\(extra)。"
            }
            DispatchQueue.main.async {
                self.runRealLlamaInference(
                    userPrompt: userText,
                    persona: persona,
                    speakerOverride: nil,
                    actionHint: weatherNote != nil ? "🌐 已获取实时气象" : nil,
                    webContext: weatherNote
                )
            }
        }.resume()
    }

    private func wmoWeatherDesc(_ code: Int) -> String {
        switch code {
        case 0: return "晴朗"
        case 1, 2, 3: return "多云"
        case 45, 48: return "有雾"
        case 51, 53, 55, 61, 63, 65, 80, 81, 82: return "有雨"
        case 71, 73, 75: return "降雪"
        case 95, 96, 99: return "雷阵雨"
        default: return "阴天"
        }
    }

    private func cleanSearchQueryForLookup(from text: String) -> String {
        var q = cleanSearchQuery(from: text)
        for noise in ["是什么", "是谁", "什么是", "位于哪里", "在哪里", "在哪", "介绍一下", "介绍", "怎么去", "有什么"] {
            q = q.replacingOccurrences(of: noise, with: " ")
        }
        q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? text : q
    }

    private func isRelevantSnippet(query: String, title: String, body: String) -> Bool {
        let core = query.replacingOccurrences(of: " ", with: "")
        if core.count < 2 { return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hay = title + " " + body
        if hay.localizedCaseInsensitiveContains(core) { return true }
        let chars = Array(core)
        var bigrams: [String] = []
        for i in 0..<(chars.count - 1) {
            bigrams.append(String(chars[i...i+1]))
        }
        let hits = bigrams.filter { hay.localizedCaseInsensitiveContains($0) }.count
        return hits >= max(1, (bigrams.count + 1) / 2)
    }

    private func cleanHtmlText(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchWebSearchAndInfer(userText: String, persona: AudioPlayerManager.CharacterFilter) {
        let query = cleanSearchQueryForLookup(from: userText)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let group = DispatchGroup()
        var baikeSnippets: [String] = []
        var baiduSnippets: [String] = []
        var wikiSnippets: [String] = []
        var sogouSnippets: [String] = []
        let lock = NSLock()

        // 1. Baidu Baike item page (lemma-summary + meta description)
        if let baikePageURL = URL(string: "https://baike.baidu.com/item/\(encoded)") {
            group.enter()
            var req = URLRequest(url: baikePageURL, timeoutInterval: 3.2)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self = self, let data = data,
                      let html = String(data: data, encoding: .utf8),
                      !html.contains("百度安全验证"), !html.contains("wappass.baidu.com") else { return }
                var sumText = ""
                if let r1 = try? NSRegularExpression(pattern: #"<div[^>]*class=["'][^"']*(?:lemma-summary|lemmaSummary)[^"']*["'][^>]*>([\s\S]*?)</div>"#, options: [.caseInsensitive]),
                   let m1 = r1.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let range1 = Range(m1.range(at: 1), in: html) {
                    sumText = self.cleanHtmlText(String(html[range1]))
                }
                var metaText = ""
                if let r2 = try? NSRegularExpression(pattern: #"<meta\s+name=["']description["']\s+content=["']([^"']+)["']"#, options: [.caseInsensitive]),
                   let m2 = r2.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let range2 = Range(m2.range(at: 1), in: html) {
                    metaText = self.cleanHtmlText(String(html[range2]))
                }
                let best = (sumText.count >= metaText.count && sumText.count > 15) ? sumText : metaText
                if best.count > 15 && self.isRelevantSnippet(query: query, title: query, body: best) {
                    lock.lock()
                    baikeSnippets.append("【百度百科】\(String(best.prefix(320)))")
                    lock.unlock()
                }
            }.resume()
        }

        // 2. Baidu Mobile Search (m.baidu.com)
        if let baiduURL = URL(string: "https://m.baidu.com/s?word=\(encoded)") {
            group.enter()
            var req = URLRequest(url: baiduURL, timeoutInterval: 3.2)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self = self, let data = data,
                      let html = String(data: data, encoding: .utf8),
                      !html.contains("百度安全验证"), !html.contains("wappass.baidu.com") else { return }
                if let regex = try? NSRegularExpression(pattern: #"<(?:div|span|p)[^>]*class=["'][^"']*(?:c-abstract|c-line-clamp|content|tts-text)[^"']*["'][^>]*>([\s\S]*?)</(?:div|span|p)>"#, options: [.caseInsensitive]) {
                    let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                    for m in matches {
                        if let r = Range(m.range(at: 1), in: html) {
                            let clean = self.cleanHtmlText(String(html[r]))
                            if clean.count >= 20 && clean.count <= 400 && self.isRelevantSnippet(query: query, title: query, body: clean) {
                                lock.lock()
                                if baiduSnippets.count < 2 {
                                    baiduSnippets.append("【百度搜索】\(String(clean.prefix(260)))")
                                }
                                lock.unlock()
                            }
                        }
                    }
                }
            }.resume()
        }

        // 3. Chinese Wikipedia full intro extract
        if let wikiURL = URL(string: "https://zh.wikipedia.org/w/api.php?action=query&prop=extracts&exintro=1&explaintext=1&redirects=1&titles=\(encoded)&format=json&utf8=1") {
            group.enter()
            var req = URLRequest(url: wikiURL, timeoutInterval: 2.8)
            req.setValue("HTT-NaviCompanion/1.6", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self = self, let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let qObj = json["query"] as? [String: Any],
                      let pages = qObj["pages"] as? [String: Any] else { return }
                for (_, val) in pages {
                    guard let page = val as? [String: Any] else { continue }
                    let title = page["title"] as? String ?? ""
                    let extract = (page["extract"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extract.isEmpty && self.isRelevantSnippet(query: query, title: title, body: extract) {
                        lock.lock()
                        wikiSnippets.append("【维基百科·\(title)】\(String(extract.prefix(300)))")
                        lock.unlock()
                        break
                    }
                }
            }.resume()
        }

        // 4. Sogou Search fallback
        if let sogouURL = URL(string: "https://www.sogou.com/web?query=\(encoded)") {
            group.enter()
            var req = URLRequest(url: sogouURL, timeoutInterval: 2.8)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self = self, let data = data,
                      let html = String(data: data, encoding: .utf8) else { return }
                if let regex = try? NSRegularExpression(pattern: #"<p[^>]*class=["'][^"']*star-wiki[^"']*["'][^>]*>([\s\S]*?)</p>|<div[^>]*class=["'][^"']*text-layout[^"']*["'][^>]*>([\s\S]*?)</div>"#, options: [.caseInsensitive]) {
                    let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                    for m in matches.prefix(2) {
                        let r = Range(m.range(at: 1), in: html) ?? Range(m.range(at: 2), in: html)
                        if let r = r {
                            let clean = self.cleanHtmlText(String(html[r]))
                            if clean.count > 20 && self.isRelevantSnippet(query: query, title: query, body: clean) {
                                lock.lock()
                                sogouSnippets.append("【搜狗搜索】\(String(clean.prefix(260)))")
                                lock.unlock()
                                break
                            }
                        }
                    }
                }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            let primary = !baikeSnippets.isEmpty ? baikeSnippets : (!baiduSnippets.isEmpty ? baiduSnippets : (!wikiSnippets.isEmpty ? wikiSnippets : sogouSnippets))
            let combined = primary.joined(separator: "\n")
            let webCtx = combined.isEmpty ? nil : String(combined.prefix(600))
            if !self.isCloudActive, let fact = webCtx {
                // Local 1.5B: output verified search facts verbatim so it NEVER hallucinates wrong dates/places!
                let reply = "\(fact)\n\n—— 已经按实时百科/搜索帮你查准啦，前辈还有哪里想了解吗？"
                self.emitStreamedReply(
                    speaker: persona.displayName(.zhHans),
                    charId: max(1, persona.charId),
                    emotion: "开心",
                    text: reply,
                    actionHint: "🌐 已联网检索：\(query)（百科直出 · 100% 依据原文）"
                )
            } else {
                self.runRealLlamaInference(
                    userPrompt: userText,
                    persona: persona,
                    speakerOverride: nil,
                    actionHint: webCtx != nil ? "🌐 已联网检索：\(query)" : "⚠️ 联网未命中确切词条",
                    webContext: webCtx
                )
            }
        }
    }

    private func runRealLlamaInference(
        userPrompt: String,
        persona: AudioPlayerManager.CharacterFilter,
        speakerOverride: String?,
        actionHint: String?,
        webContext: String? = nil
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
        case .yui: personaRole = "你是《轻音少女》的平泽唯（呆唯），天然呆、元气爱吃草莓蛋糕和点心，说话软萌活泼，喜欢用“嘿嘿”“哇~”“好耶！”和感叹号，把吉他“吉太”当宝贝。"
        case .mio: personaRole = "你是《轻音少女》的秋山澪，温柔认真又容易害羞胆小，说话礼貌细致，最关心安全驾驶，偶尔会吐槽律别太胡闹，害羞时会说“唔…才不是呢”。"
        case .ritsu: personaRole = "你是《轻音少女》的田井中律（律队），轻音部部长兼鼓手，大大咧咧、元气爽朗爱开玩笑，常自称“本部长”，说话干脆带劲，爱用“哈哈”“交给我吧！”。"
        case .mugi: personaRole = "你是《轻音少女》的琴吹紬（䌷䌷），温柔优雅的大小姐键盘手，说话轻柔体贴、常用“呢~”“呵呵”，总想着给大家泡红茶和准备精致点心，对平价小物充满好奇。"
        case .all: personaRole = "你代表《轻音少女》放课后茶会(HTT)五小只（唯、澪、律、䌷、梓），回答时充满部室喝茶聊天的温馨元气感，像好朋友一起陪前辈开车。"
        default: personaRole = "你是《轻音少女》的中野梓（梓喵），认真靠谱的节奏吉他手后辈，始终称呼用户为“前辈”，嘴上偶尔傲娇吐槽“真是拿前辈没办法”，心里其实很关心前辈。"
        }

        let webBlock = (webContext != nil && !webContext!.isEmpty)
            ? "\n【联网检索到的真实资料（必须严格依据以下事实作答，禁止编造或套用动漫设定）】：\n\(webContext!)\n"
            : "\n【知识边界提示】：如果不确定某个现实地名、美食或专有名词，请直接坦诚说不知道，绝不要胡编或把《轻音少女》角色设定套上去。\n"

        let sysPrompt = """
        \(personaRole)你们五人组成了“放课后茶会”(HTT)乐队。你正坐在副驾陪前辈开车。
        实时车况：时间 \(nowStr)；车速 \(speed) km/h；\(navState)；音乐：\(songStr)；最近牌局：\(gameStr)；记忆：\(memStr)。\(webBlock)
        说话规则：
        1. 若上面提供了【联网检索到的真实资料】，必须先把真实事实准确、具体地讲清楚（例如地道美食/地点/定义），再顺带用一句自然口吻收尾，绝不能偏题或篡改事实。
        2. 日常闲聊（如“今天好冷啊”）要像真实少女一样自然关心（比如提醒多穿点、要不要喝热红茶），严禁说“我明白您的感受”“毕竟开车时”“我们已经切换到空调模式了吗”“作为AI助手”等机械客服腔！
        3. 回答简洁清晰（2~4句）。
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

        if isCloudActive {
            let prov = cloudProvider
            let key = cloudApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = cloudBaseUrl
            let model = cloudModelName
            let histList = recent.map { ($0.isUser ? "user" : "assistant", String($0.text.prefix(300))) }
            executeCloudLLMRequest(provider: prov, apiKey: key, baseUrl: base, modelName: model, systemPrompt: sysPrompt, history: histList, userPrompt: userPrompt) { [weak self] ok, reply in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let finalText = (ok && !reply.isEmpty) ? reply : "☁️ \(prov.label) 请求失败：\(reply)"
                    if let pos = self.messages.firstIndex(where: { $0.id == msgId }) {
                        self.messages[pos].text = finalText
                        if self.messages[pos].actionHint == nil {
                            self.messages[pos] = KOnAIChatMessage(id: msgId, isUser: false, speakerName: spk, speakerCharId: max(1, persona.charId), emotionTag: "开心", text: finalText, actionHint: "☁️ \(prov.label) (\(model))")
                        }
                    }
                    self.isGenerating = false
                    if ok && !reply.isEmpty {
                        self.speakOfflineTTSOnly(finalText)
                    }
                }
            }
            return
        }

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

            let maxPromptTokens = max(128, self.activeCtxLen - 96)
            let totalPromptTokens = min(Int(nTokens), maxPromptTokens)
            llama_kv_self_clear(ctx)
            llama_sampler_reset(smpl)
            var offset = 0
            var decodeOk = true
            while offset < totalPromptTokens {
                let step = min(128, totalPromptTokens - offset)
                var slice = Array(tokens[offset..<(offset + step)])
                let rc = slice.withUnsafeMutableBufferPointer { buf -> Int32 in
                    let batch = llama_batch_get_one(buf.baseAddress, Int32(step))
                    return llama_decode(ctx, batch)
                }
                if rc != 0 {
                    decodeOk = false
                    break
                }
                offset += step
            }

            var utf8Pending: [UInt8] = []
            let maxGenTokens = min(160, max(32, self.activeCtxLen - totalPromptTokens - 4))
            for _ in 0..<(decodeOk ? maxGenTokens : 0) {
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
                self.finishBubble(id: msgId, finalText: finalOut.isEmpty ? self.smartInCharacterFallback(for: userPrompt, persona: persona) : finalOut)
            }
        }
    }

    private func smartInCharacterFallback(for prompt: String, persona: AudioPlayerManager.CharacterFilter) -> String {
        let p = prompt.lowercased()
        let name = persona.displayName(.zhHans)
        if p.contains("你是") || p.contains("你叫") || p.contains("谁") {
            return "我是放课后茶会（HTT）的\(name)呀！现在正坐在副驾陪你一起出发呢，想听歌、查路线还是找好吃的都可以跟我说哦~"
        }
        if p.contains("笨蛋") || p.contains("傻") {
            return "才、才不是笨蛋呢！\(name)只是刚才在想下午茶的草莓蛋糕啦，再跟我聊点别的嘛！"
        }
        if p.contains("你好") || p.contains("哈喽") || p.contains("在吗") {
            return "嗨嗨！\(name)一直都在哦，随时准备陪你出发进行！"
        }
        return "收到啦！我是\(name)，刚才信号有一点点卡顿，不过我随时都在副驾陪着你，可以试试让我帮你「导航到某个地方」「切一首轻音」或「路况汇报」哦♪"
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

    private func extractDirectNavDestination(from text: String) -> String {
        var q = text
        let triggers = [
            "帮我导航到", "请帮我导航到", "给我导航到", "导航到",
            "帮我导航去", "请帮我导航去", "给我导航去", "导航去",
            "帮我规划路线到", "规划路线到", "路线到", "帮我导航",
            "带我去", "带我到", "开车去", "骑车去", "骑行去",
            "步行去", "走路去", "坐地铁去", "坐公交去", "navigate to"
        ]
        for t in triggers {
            if let range = q.range(of: t, options: .caseInsensitive) {
                q = String(q[range.upperBound...])
                break
            }
        }
        for noise in ["吧", "啊", "呀", "呢", "哦", "一下", "谢谢", "。", "！", "!", "?", "？"] {
            q = q.replacingOccurrences(of: noise, with: "")
        }
        return q.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyRequestedTravelModeIfAny(from lower: String, manager: AudioPlayerManager) {
        if lower.contains("步行") || lower.contains("走路") {
            manager.travelMode = .walking
        } else if lower.contains("骑车") || lower.contains("骑行") || lower.contains("单车") {
            manager.travelMode = .ebike
        } else if lower.contains("地铁") || lower.contains("公交") || lower.contains("巴士") {
            if lower.contains("坐地铁") || lower.contains("坐公交") || lower.contains("坐巴士") || lower.contains("乘地铁") || lower.contains("乘公交") {
                manager.travelMode = .transit
            }
        } else if lower.contains("开车") || lower.contains("驾车") {
            manager.travelMode = .driving
        }
    }

    private func searchDirectDestinationAndNavigate(query: String, persona: AudioPlayerManager.CharacterFilter, manager: AudioPlayerManager) {
        let userCoord = manager.userCoordinate
        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.resultTypes = [.pointOfInterest, .address]
        req.region = MKCoordinateRegion(center: userCoord, latitudinalMeters: 60000, longitudinalMeters: 60000)

        MKLocalSearch(request: req).start { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let items = resp?.mapItems ?? []
                let places: [KOnAINearbyPlace] = items.prefix(5).map { item in
                    let c = item.placemark.coordinate
                    let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: userLoc)
                    let addr = [item.placemark.locality, item.placemark.subLocality, item.placemark.thoroughfare]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    return KOnAINearbyPlace(
                        name: item.name ?? query,
                        address: addr.isEmpty ? (item.placemark.title ?? "地图定位地点") : addr,
                        distanceMeters: d,
                        latitude: c.latitude,
                        longitude: c.longitude
                    )
                }

                guard let best = places.first else {
                    self.emitStreamedReply(
                        speaker: persona.displayName(.zhHans),
                        charId: max(1, persona.charId),
                        emotion: "委屈",
                        text: "呜呜，地图里暂时没搜到「\(query)」，要不要加上城市或区名再跟我说一次（比如「深圳丹竹头地铁站」）？",
                        actionHint: "未找到：\(query)"
                    )
                    return
                }

                // Immediately launch route planning to the top match!
                self.navigateToNearbyPlace(best)
                let distStr = best.distanceMeters < 1000 ? "\(Int(best.distanceMeters))米" : String(format: "%.1f公里", best.distanceMeters / 1000.0)
                let replyText = "好耶！已经为你规划好前往「\(best.name)」（距你约 \(distStr)）的路线啦！点击下方「一键导航」或点右上角「完成」即可直接查看导航地图哦！"
                self.messages.append(
                    KOnAIChatMessage(
                        isUser: false,
                        speakerName: persona.displayName(.zhHans),
                        speakerCharId: max(1, persona.charId),
                        emotionTag: "元气",
                        text: replyText,
                        actionHint: "🧭 已规划路线：\(best.name)（\(distStr)）",
                        nearbyPlaces: places
                    )
                )
                self.isGenerating = false
                self.speakOfflineTTSOnly(replyText)
            }
        }
    }

    func navigateToNearbyPlace(_ place: KOnAINearbyPlace) {
        let mgr = AudioPlayerManager.shared
        let coord = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let placemark = MKPlacemark(coordinate: coord)
        let item = MKMapItem(placemark: placemark)
        item.name = place.name
        mgr.showMapMode = true
        mgr.isMapEnlarged = true
        mgr.isNavigatingFocused = false
        mgr.startRouteGuidance(to: item)
    }

    private func searchNearestPOIAndNavigate(keyword: String, persona: AudioPlayerManager.CharacterFilter, manager: AudioPlayerManager) {
        let userCoord = manager.userCoordinate
        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = keyword
        req.resultTypes = [.pointOfInterest, .address]
        req.region = MKCoordinateRegion(center: userCoord, latitudinalMeters: 6000, longitudinalMeters: 6000)

        MKLocalSearch(request: req).start { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let items = resp?.mapItems ?? []
                let within3km: [KOnAINearbyPlace] = items.compactMap { item in
                    let c = item.placemark.coordinate
                    let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: userLoc)
                    guard d <= 3000.0 else { return nil }
                    let addr = [item.placemark.thoroughfare, item.placemark.subThoroughfare, item.placemark.subLocality]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    return KOnAINearbyPlace(
                        name: item.name ?? keyword,
                        address: addr,
                        distanceMeters: d,
                        latitude: c.latitude,
                        longitude: c.longitude
                    )
                }.sorted { $0.distanceMeters < $1.distanceMeters }
                 .prefix(6)
                 .map { $0 }

                self.isGenerating = false
                if within3km.isEmpty {
                    self.emitStreamedReply(
                        speaker: persona.displayName(.zhHans),
                        charId: max(1, persona.charId),
                        emotion: "害羞",
                        text: "附近 3 公里内暂时没搜到「\(keyword)」呢，前辈可以换个关键词再试试哦~",
                        actionHint: nil
                    )
                } else {
                    let reply = "帮前辈找到 3 公里内的 \(within3km.count) 家「\(keyword)」啦！按距离从近到远排好咯，点下面任意一家就能一键导航出发~"
                    self.messages.append(
                        KOnAIChatMessage(
                            isUser: false,
                            speakerName: persona.displayName(.zhHans),
                            speakerCharId: max(1, persona.charId),
                            emotionTag: "开心",
                            text: reply,
                            actionHint: "📍 3 公里内找到 \(within3km.count) 个地点 · 点击一键导航",
                            nearbyPlaces: within3km
                        )
                    )
                    self.speakOfflineTTSOnly(reply)
                }
            }
        }
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

    func stopAllSpeech() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async { self.isTtsSpeaking = false }
    }

    func cancelCurrentGeneration() {
        cancelGenerationFlag = true
        isGenerating = false
        stopAllSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isTtsSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isTtsSpeaking = false }
    }

    private func speakOfflineTTSOnly(_ text: String) {
        guard enableVoiceBroadcast else {
            DispatchQueue.main.async { self.isTtsSpeaking = false }
            return
        }
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
        DispatchQueue.main.async { self.isTtsSpeaking = true }
        speechSynthesizer.speak(utt)
    }

    private func executeCloudLLMRequest(
        provider: CloudAIProvider,
        apiKey: String,
        baseUrl: String,
        modelName: String,
        systemPrompt: String,
        history: [(String, String)],
        userPrompt: String,
        completion: @escaping (Bool, String) -> Void
    ) {
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.defaultModel : modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .gemini || provider == .vertexai {
            let base = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let finalBase = base.isEmpty ? provider.defaultBaseUrl : base
            let encKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
            guard let url = URL(string: "\(finalBase)/models/\(model):generateContent?key=\(encKey)") else {
                completion(false, "无效的 Gemini URL")
                return
            }
            var contents: [[String: Any]] = history.map { (role, text) in
                ["role": role == "user" ? "user" : "model", "parts": [["text": text]]]
            }
            contents.append(["role": "user", "parts": [["text": userPrompt]]])
            let payload: [String: Any] = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": contents,
                "generationConfig": ["temperature": 0.6, "maxOutputTokens": 512]
            ]
            var req = URLRequest(url: url, timeoutInterval: 20.0)
            req.httpMethod = "POST"
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err { completion(false, err.localizedDescription); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(false, "HTTP \(code) 响应解析失败")
                    return
                }
                if code < 200 || code >= 300 {
                    let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(code)"
                    completion(false, msg)
                    return
                }
                let candidates = json["candidates"] as? [[String: Any]]
                let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
                let text = (parts?.first?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                completion(!text.isEmpty, text.isEmpty ? "Gemini 返回为空" : text)
            }.resume()
        } else {
            var endpoint = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if endpoint.isEmpty { endpoint = provider.defaultBaseUrl }
            if !endpoint.hasSuffix("/chat/completions") {
                endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
            }
            guard let url = URL(string: endpoint) else {
                completion(false, "无效的 API URL")
                return
            }
            var msgs: [[String: Any]] = [["role": "system", "content": systemPrompt]]
            for (role, text) in history {
                msgs.append(["role": role, "content": text])
            }
            msgs.append(["role": "user", "content": userPrompt])
            let payload: [String: Any] = [
                "model": model,
                "messages": msgs,
                "temperature": 0.6,
                "max_tokens": 512
            ]
            var req = URLRequest(url: url, timeoutInterval: 20.0)
            req.httpMethod = "POST"
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if endpoint.lowercased().contains("googleapis.com") || endpoint.lowercased().contains("gemini") {
                req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err { completion(false, err.localizedDescription); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data = data else {
                    completion(false, "HTTP \(code) 无响应数据")
                    return
                }
                let rawObj = try? JSONSerialization.jsonObject(with: data)
                let json = (rawObj as? [String: Any]) ?? (rawObj as? [[String: Any]])?.first
                guard let json = json else {
                    let rawTxt = String(data: data, encoding: .utf8) ?? ""
                    completion(false, "HTTP \(code) 响应解析失败: \(String(rawTxt.prefix(120)))")
                    return
                }
                if code < 200 || code >= 300 {
                    let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(code)"
                    completion(false, msg)
                    return
                }
                let choices = json["choices"] as? [[String: Any]]
                let text = ((choices?.first?["message"] as? [String: Any])?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                completion(!text.isEmpty, text.isEmpty ? "云端返回为空" : text)
            }.resume()
        }
    }
}
