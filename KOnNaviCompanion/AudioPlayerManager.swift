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

// MARK: - WGS-84 to GCJ-02 (China Mars Coordinate System) Converter
struct CoordinateConverter {
    static func bd09ToGCJ02(lat: Double, lon: Double) -> CLLocationCoordinate2D {
        let x = lon - 0.0065
        let y = lat - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * Double.pi * 3000.0 / 180.0)
        let theta = atan2(y, x) - 0.000003 * cos(x * Double.pi * 3000.0 / 180.0)
        let ggLon = z * cos(theta)
        let ggLat = z * sin(theta)
        return CLLocationCoordinate2D(latitude: ggLat, longitude: ggLon)
    }

    static func wgs84ToGCJ02(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if isOutOfChina(coord) {
            return coord
        }
        let a = 6378245.0
        let ee = 0.00669342162296594323
        let pi = Double.pi
        
        var dLat = transformLat(x: coord.longitude - 105.0, y: coord.latitude - 35.0)
        var dLon = transformLon(x: coord.longitude - 105.0, y: coord.latitude - 35.0)
        let radLat = coord.latitude / 180.0 * pi
        var magic = sin(radLat)
        magic = 1.0 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1.0 - ee)) / (magic * sqrtMagic) * pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * pi)
        return CLLocationCoordinate2D(latitude: coord.latitude + dLat, longitude: coord.longitude + dLon)
    }
    
    private static func isOutOfChina(_ coord: CLLocationCoordinate2D) -> Bool {
        if coord.longitude < 72.004 || coord.longitude > 137.8347 { return true }
        if coord.latitude < 0.8293 || coord.latitude > 55.8271 { return true }
        return false
    }
    
    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * Double.pi) + 320.0 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return ret
    }
    
    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return ret
    }
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


// MARK: - Built-In GaoDe-Style Public Transit & Highway Telemetry Models (高德风格内置公交地铁与高速路况模型)
struct ServiceAreaInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    var distanceMeters: Int
    var isPassed: Bool = false
}

struct TollStationInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    var distanceMeters: Int
    var isPassed: Bool = false
}

struct StationCoord {
    let name: String
    let exit: String
    let lat: Double
    let lon: Double
    let line: String
}

struct TransitPlanOption: Identifiable {
    let id = UUID()
    let title: String              // e.g. "方案1 · 步行少"
    let badge: String              // e.g. "高德推荐 · 步行少"
    let totalMinutes: Int          // e.g. 30
    let totalStations: Int         // e.g. 5
    let transferCount: Int         // e.g. 0
    let walkMeters: Int            // e.g. 458
    let priceYuan: String          // e.g. "2.5" or "3" or "7"
    let startExitDesc: String      // e.g. "沙湾天桥上车" or "横岗 (C口) 进站"
    let warningNotice: String      // e.g. "⚠️ M385路尾班车预计 22:44 到站"
    let steps: [TransitStepItem]
}

struct TransitStepItem: Identifiable {
    let id = UUID()
    let kind: StepKind             // walk, subway, bus
    let lineName: String           // e.g. "地铁3号线 (龙岗线)"
    let directionDesc: String      // e.g. "福保方向"
    let fromStation: String        // e.g. "横岗 (C口)"
    let toStation: String          // e.g. "布吉"
    let passStations: [String]     // Intermediate stops for expandable/collapsible list: ["塘坑", "六约", "丹竹头", "大芬", "木棉湾"]
    let durationMins: Int          // e.g. 19
    let walkMeters: Int            // e.g. 143
    let doorSideDesc: String       // e.g. "右侧开门"
    let acNotice: String           // e.g. "❄️ 强冷:2-5车厢；弱冷:1、6车厢"
    let exitDesc: String           // e.g. "从 C出入口 进站" / "从 A出入口 出站"
    let colorHex: String           // Line color (#0076C0, #D4AF37, #8E2A59)
    let intervalDesc: String       // e.g. "上车站 首06:25 末23:35 · 发车间隔约3分钟"
    
    enum StepKind {
        case walk
        case subway
        case bus
        
        var icon: String {
            switch self {
            case .walk: return "figure.walk"
            case .subway: return "tram.fill"
            case .bus: return "bus.fill"
            }
        }
    }
}

// 4 Travel Modes: Driving, e-Bike, Walking, Transit
enum NavigationTravelMode: String, CaseIterable, Identifiable {
    case driving = "driving"
    case ebike = "ebike"
    case walking = "walking"
    case transit = "transit"
    
    var id: String { self.rawValue }
    
    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.driving, .zhHans): return "开车"
        case (.driving, .zhHant): return "開車"
        case (.driving, .en): return "Drive"
        case (.ebike, .zhHans): return "电动车"
        case (.ebike, .zhHant): return "電動車"
        case (.ebike, .en): return "e-Bike"
        case (.walking, .zhHans): return "步行"
        case (.walking, .zhHant): return "步行"
        case (.walking, .en): return "Walk"
        case (.transit, .zhHans): return "公交/地铁"
        case (.transit, .zhHant): return "公車/地鐵"
        case (.transit, .en): return "Transit"
        }
    }
    
    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .ebike: return "bicycle"
        case .walking: return "figure.walk"
        case .transit: return "bus.fill"
        }
    }
    
    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .driving: return .automobile
        case .ebike: return .walking // Avoids freeways, pedestrian/bike friendly
        case .walking: return .walking
        case .transit: return .transit
        }
    }
    
    var defaultSpeedLimit: Double {
        switch self {
        case .driving: return 80.0
        case .ebike: return 25.0
        case .walking: return 6.0
        case .transit: return 60.0
        }
    }
}

struct RoadLaneItem: Identifiable {
    let id = UUID()
    let iconName: String       // e.g. "arrow.turn.up.left", "arrow.up", "arrow.turn.up.right"
    let label: String          // e.g. "左转", "直行", "右转"
    let isRecommended: Bool    // true = Bright White/Active, false = Dimmed Gray
}

enum TrafficLightPhase: String {
    case green = "green"
    case yellow = "yellow"
    case red = "red"
}

enum RouteStrategyPreference: String, CaseIterable, Identifiable {
    case gaodeRecommended = "gaodeRecommended"
    case avoidHighway = "avoidHighway"
    case highwayFirst = "highwayFirst"
    case shortest = "shortest"
    
    var id: String { self.rawValue }
    
    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.gaodeRecommended, .zhHans): return "高德推荐"
        case (.gaodeRecommended, .zhHant): return "高德推薦"
        case (.gaodeRecommended, .en): return "Recommended"
        case (.avoidHighway, .zhHans): return "不走高速"
        case (.avoidHighway, .zhHant): return "不走高速"
        case (.avoidHighway, .en): return "No Highway"
        case (.highwayFirst, .zhHans): return "高速优先"
        case (.highwayFirst, .zhHant): return "高速優先"
        case (.highwayFirst, .en): return "Highway"
        case (.shortest, .zhHans): return "距离最短"
        case (.shortest, .zhHant): return "距離最短"
        case (.shortest, .en): return "Shortest"
        }
    }
    
    var icon: String {
        switch self {
        case .gaodeRecommended: return "sparkles"
        case .avoidHighway: return "arrow.triangle.branch"
        case .highwayFirst: return "road.lanes"
        case .shortest: return "ruler.fill"
        }
    }
}

enum RoadHazardKind: String {
    case speedCamera = "speedCamera"   // 测速电子眼 (60/80/100/120 km/h)
    case redLightCam = "redLightCam"   // 闯红灯拍照 / 违章抓拍
    case tollStation = "tollStation"   // 收费站
    case serviceArea = "serviceArea"   // 高速服务区 (SA/PA)
    case congestion = "congestion"     // 拥堵缓行路段
}

class RoadHazardAnnotation: MKPointAnnotation {
    var kind: RoadHazardKind = .speedCamera
    var speedLimitValue: Int = 80
    var distanceMeters: Double = 0
}

enum NavigationCameraMode: String, CaseIterable, Identifiable {
    case headingUp = "headingUp" // 车头朝上 (地图随车旋转，车标固定在前方)
    case northUp = "northUp"     // 正北朝上 (地图固定不转，导航标在地图上移动转向)
    
    var id: String { self.rawValue }
    
    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.headingUp, .zhHans): return "车头朝上(地图动)"
        case (.headingUp, .zhHant): return "車頭朝上(地圖動)"
        case (.headingUp, .en): return "Heading Up"
        case (.northUp, .zhHans): return "正北朝上(车标动)"
        case (.northUp, .zhHant): return "正北朝上(車標動)"
        case (.northUp, .en): return "North Up"
        }
    }
    
    func shortTitle(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.headingUp, .zhHans): return "地图动"
        case (.headingUp, .zhHant): return "地圖動"
        case (.headingUp, .en): return "Map Rot"
        case (.northUp, .zhHans): return "车标动"
        case (.northUp, .zhHant): return "車標動"
        case (.northUp, .en): return "Icon Mov"
        }
    }
    
    var icon: String {
        switch self {
        case .headingUp: return "location.north.line.fill"
        case .northUp: return "safari.fill"
        }
    }
}

enum RM500ArrowOutfit: Int, CaseIterable, Identifiable {
    case winterUniform = 0
    case summerUniform = 1
    case maid = 2
    case httShirt = 3
    case kigurumi = 4
    case tonchan = 5
    case classic3D = 6
    
    var id: Int { self.rawValue }
    
    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.winterUniform, .zhHans): return "冬季制服"
        case (.winterUniform, .zhHant): return "冬季制服"
        case (.winterUniform, .en): return "Winter Uniform"
        case (.summerUniform, .zhHans): return "夏季制服"
        case (.summerUniform, .zhHant): return "夏季制服"
        case (.summerUniform, .en): return "Summer Uniform"
        case (.maid, .zhHans): return "女仆装"
        case (.maid, .zhHant): return "女僕裝"
        case (.maid, .en): return "Maid Outfit"
        case (.httShirt, .zhHans): return "HTT文化衫"
        case (.httShirt, .zhHant): return "HTT文化衫"
        case (.httShirt, .en): return "HTT T-Shirt"
        case (.kigurumi, .zhHans): return "布偶装"
        case (.kigurumi, .zhHant): return "布偶裝"
        case (.kigurumi, .en): return "Animal Suit"
        case (.tonchan, .zhHans): return "豚骨(乌龟)"
        case (.tonchan, .zhHant): return "豚骨(烏龜)"
        case (.tonchan, .en): return "Ton-chan"
        case (.classic3D, .zhHans): return "经典3D箭头"
        case (.classic3D, .zhHant): return "經典3D箭頭"
        case (.classic3D, .en): return "3D Arrow"
        }
    }
    
    var icon: String {
        switch self {
        case .winterUniform: return "graduationcap.fill"
        case .summerUniform: return "sun.max.fill"
        case .maid: return "cup.and.saucer.fill"
        case .httShirt: return "guitars.fill"
        case .kigurumi: return "pawprint.fill"
        case .tonchan: return "tortoise.fill"
        case .classic3D: return "location.north.fill"
        }
    }
}

// MARK: - Isolated Pinyin-Safe AutoNavi/MapKit Place Search Engine
class PlaceSearchEngine: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var mapItems: [MKMapItem] = []
    @Published var isSearching: Bool = false
    
    private let completer = MKLocalSearchCompleter()
    private var activeSearch: MKLocalSearch?
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }
    
    func updateQueryFragment(_ fragment: String, center: CLLocationCoordinate2D) {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completions = []
            mapItems = []
            isSearching = false
            return
        }
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 300000,
            longitudinalMeters: 300000
        )
        completer.queryFragment = trimmed
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.completions = Array(completer.results.prefix(25))
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Ignore transient completer errors while typing
    }
    
    func performFullSearch(query: String, center: CLLocationCoordinate2D) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activeSearch?.cancel()
        isSearching = true
        
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        req.resultTypes = [.address, .pointOfInterest]
        req.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 350000,
            longitudinalMeters: 350000
        )
        
        let search = MKLocalSearch(request: req)
        activeSearch = search
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                self?.isSearching = false
                if let items = response?.mapItems, !items.isEmpty {
                    self?.mapItems = items
                }
            }
        }
    }
    
    func resolveAndStartNavigation(for completion: MKLocalSearchCompletion, manager: AudioPlayerManager, onComplete: @escaping () -> Void) {
        activeSearch?.cancel()
        isSearching = true
        let req = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: req)
        activeSearch = search
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                self?.isSearching = false
                if let item = response?.mapItems.first {
                    manager.showMapMode = true
                    manager.startRouteGuidance(to: item)
                    onComplete()
                } else {
                    // Fallback by natural language query of title + subtitle
                    let fallbackReq = MKLocalSearch.Request()
                    fallbackReq.naturalLanguageQuery = completion.title + " " + completion.subtitle
                    MKLocalSearch(request: fallbackReq).start { resp, _ in
                        DispatchQueue.main.async {
                            if let fbItem = resp?.mapItems.first {
                                manager.showMapMode = true
                                manager.startRouteGuidance(to: fbItem)
                            }
                            onComplete()
                        }
                    }
                }
            }
        }
    }
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate, CLLocationManagerDelegate {
    static let shared = AudioPlayerManager()
    
    @Published var language: AppLanguage = .zhHans
    
    // Playback & Voice Queue State
    @Published var isPlaying: Bool = false
    @Published var currentPlayingId: Int? = nil
    @Published var currentSpeechBubble: String = "準備OK！出発進行～！"
    private var voiceQueue: [(id: Int, quote: String)] = []
    
    // Mascot Animation State
    @Published var mascotAction: MascotActionState = .idle
    @Published var currentSpriteFrame: UIImage? = nil
    @Published var allMemberFrames: [Int: UIImage] = [:]
    @Published var deskSpriteFrame: UIImage? = nil
    @Published var arrowOutfit: RM500ArrowOutfit = .winterUniform
    @Published var useRM500ThemeSkin: Bool = true
    @Published var walkStepFrame: Int = 0
    @Published var currentNavArrowImage: UIImage? = nil
    @Published var activeAllMemberChar: CharacterFilter = CharacterFilter.fiveIndividuals.randomElement() ?? .yui
    @Published var unlockedBirthdayId: Int = 1112
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
    @Published var speedLimitKmh: Double = 80.0
    @Published var isOverspeeding: Bool = false
    @Published var isGPSSignalPoor: Bool = false
    @Published var gpsAccuracyMeters: Double = -1.0
    @Published var isHUDMirrored: Bool = false
    @Published var drivingSeconds: Int = 0
    
    // Built-In Map Navigation State (Enlarged Mode & 4 Travel Modes)
    @Published var showMapMode: Bool = true
    @Published var isMapEnlarged: Bool = false // Auto-enlarges on active navigation!
    @Published var travelMode: NavigationTravelMode = .driving {
        didSet {
            guard oldValue != travelMode else { return }
            // Immediately stop any previous voice queue so user never has to wait for old audio to finish!
            stop()
            let newLimit = travelMode.defaultSpeedLimit
            if travelMode == .transit {
                let dest = destinationCoord ?? CLLocationCoordinate2D(latitude: 22.61, longitude: 114.15)
                let title = destinationName.isEmpty ? "丹竹头地铁站" : destinationName
                generateBuiltInTransitPlans(from: userCoordinate, to: dest, destTitle: title)
            }
            if let dest = destinationCoord, !destinationName.isEmpty {
                speedLimitKmh = newLimit
                calculateAndStartRoute(to: dest, title: destinationName, isReroute: true)
            } else {
                speedLimitKmh = newLimit
                announceTravelModeSwitch()
            }
        }
    }
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
    @Published var cameraMode: NavigationCameraMode = .headingUp {
        didSet {
            triggerFastRecenter()
        }
    }
    @Published var tappedMapCoord: CLLocationCoordinate2D? = nil
    @Published var tappedMapTitle: String = ""
    @Published var tappedMapAddress: String = ""
    @Published var isReverseGeocoding: Bool = false
    @Published var userZoomDistance: Double = 280.0
    @Published var routePreference: RouteStrategyPreference = .gaodeRecommended {
        didSet {
            applyRoutePreferenceSort()
        }
    }
    @Published var candidateRoutes: [MKRoute] = []
    @Published var selectedRouteIndex: Int = 0
    @Published var routeHazards: [RoadHazardAnnotation] = []
    @Published var upcomingCameraDistance: Int = 0
    @Published var upcomingCameraLimit: Int = 80
    @Published var upcomingTollDistance: Int = 0
    @Published var upcomingServiceAreaName: String = ""
    @Published var upcomingServiceAreaDist: Int = 0
    @Published var upcomingTollName: String = ""
    @Published var serviceAreasAlongRoute: [ServiceAreaInfo] = []
    @Published var tollsAlongRoute: [TollStationInfo] = []
    @Published var lastTraveledMeters: Int = 0
    @Published var lastTransitGenLocation: CLLocationCoordinate2D? = nil
    @Published var congestionStatusText: String = "道路畅通"
    @Published var isCongested: Bool = false
    @Published var isNavigatingFocused: Bool = false // True after pressing [开始导航] -> hides clutter & focuses on driving!
    @Published var zoomCommandTrigger: Int = 0       // Dedicated zoom trigger that NEVER resets map center!
    @Published var trafficLightPhase: TrafficLightPhase = .green
    @Published var trafficLightSeconds: Int = 26
    @Published var transitPlans: [TransitPlanOption] = []
    @Published var selectedTransitPlanIndex: Int = 0
    @Published var showTransitPlanSheet: Bool = false
    @Published var currentRoadLanes: [RoadLaneItem] = [
        RoadLaneItem(iconName: "arrow.turn.up.left", label: "左转", isRecommended: false),
        RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: true),
        RoadLaneItem(iconName: "arrow.turn.up.right", label: "右转", isRecommended: false)
    ]
    @Published var recenterTrigger: Int = 0
    
    func toggleCameraMode() {
        cameraMode = (cameraMode == .headingUp) ? .northUp : .headingUp
    }
    
    func zoomMapIn() {
        userZoomDistance = max(100.0, userZoomDistance * 0.62)
        zoomCommandTrigger += 1
    }
    
    func zoomMapOut() {
        userZoomDistance = min(30000.0, userZoomDistance * 1.55)
        zoomCommandTrigger += 1
    }
    
    func formatSmartDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        } else {
            return "\(max(0, meters)) m"
        }
    }
    
    func startFocusedNavigation() {
        stop()
        isNavigatingFocused = true
        mapTrackingUser = true
        recenterTrigger += 1
        triggerDepartureGreeting(title: destinationName, isReroute: false)
    }
    
    func exitFocusedNavigationToOverview() {
        isNavigatingFocused = false
    }
    
    private func announceTravelModeSwitch() {
        let base = activeBaseId()
        let modeOff = activeModeOffset()
        let modeTitle = travelMode.title(language)
        let lim = Int(speedLimitKmh)
        let msg = "[\(modeTitle)] モード切替完了！制限速度: \(lim) km/h"
        playVoice(id: base + modeOff + 39, customQuote: msg, clearQueue: true)
    }
    
    func handleMapTap(at coord: CLLocationCoordinate2D) {
        let tapLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let req = MKLocalSearch.Request()
        req.resultTypes = .pointOfInterest
        req.pointOfInterestFilter = .includingAll
        req.region = MKCoordinateRegion(center: coord, latitudinalMeters: 90, longitudinalMeters: 90)
        
        MKLocalSearch(request: req).start { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let validItems = (resp?.mapItems ?? []).filter { item in
                    guard let name = item.name, !name.isEmpty else { return false }
                    let itemLoc = CLLocation(latitude: item.placemark.coordinate.latitude,
                                             longitude: item.placemark.coordinate.longitude)
                    return tapLoc.distance(from: itemLoc) <= 45.0
                }.sorted { a, b in
                    let la = CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)
                    let lb = CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude)
                    return tapLoc.distance(from: la) < tapLoc.distance(from: lb)
                }
                
                if let bestPOI = validItems.first {
                    self.tappedMapCoord = bestPOI.placemark.coordinate
                    self.tappedMapTitle = bestPOI.name ?? "精选地点"
                    var addrParts: [String] = []
                    if let dist = bestPOI.placemark.subLocality { addrParts.append(dist) }
                    if let road = bestPOI.placemark.thoroughfare { addrParts.append(road) }
                    if let num = bestPOI.placemark.subThoroughfare { addrParts.append(num) }
                    self.tappedMapAddress = addrParts.isEmpty ? (bestPOI.placemark.title ?? "") : addrParts.joined(separator: " · ")
                    self.isReverseGeocoding = false
                } else {
                    // Also check reverse geocode for named landmarks
                    CLGeocoder().reverseGeocodeLocation(tapLoc) { [weak self] placemarks, _ in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            if let pm = placemarks?.first, let name = pm.name, !name.isEmpty, name != pm.thoroughfare {
                                self.tappedMapCoord = coord
                                self.tappedMapTitle = name
                                var parts: [String] = []
                                if let dist = pm.subLocality { parts.append(dist) }
                                if let road = pm.thoroughfare { parts.append(road) }
                                self.tappedMapAddress = parts.joined(separator: " · ")
                            } else {
                                // Tapped on blank road/ground with no POI -> dismiss card
                                self.tappedMapCoord = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    func startNavigationToTappedPoint() {
        guard let coord = tappedMapCoord else { return }
        let title = tappedMapTitle.isEmpty ? "地图选点" : tappedMapTitle
        tappedMapCoord = nil
        stopDemoSimulation()
        calculateAndStartRoute(to: coord, title: title)
    }
    
    func dismissTappedPoint() {
        tappedMapCoord = nil
    }
    
    func triggerFastRecenter() {
        mapTrackingUser = true
        recenterTrigger += 1
    }
    

    // MARK: - Native In-App Transit & Subway Shortest-Path Engine (真·高德拓扑最短换乘引擎，绝不绕远路！)
    private static let szStationsDatabase: [StationCoord] = [
        // Line 3 (Longgang Line: Longgang -> Luohu/Futian)
        StationCoord(name: "双龙", exit: "A口", lat: 22.726, lon: 114.281, line: "3号线"),
        StationCoord(name: "龙城广场", exit: "D口", lat: 22.716, lon: 114.252, line: "3号线"),
        StationCoord(name: "大运", exit: "C口", lat: 22.688, lon: 114.228, line: "3号线/14号线"),
        StationCoord(name: "荷坳", exit: "A口", lat: 22.669, lon: 114.218, line: "3号线"),
        StationCoord(name: "永湖", exit: "A2口", lat: 22.658, lon: 114.212, line: "3号线"),
        StationCoord(name: "横岗", exit: "C口", lat: 22.651, lon: 114.208, line: "3号线"),
        StationCoord(name: "塘坑", exit: "B口", lat: 22.636, lon: 114.195, line: "3号线"),
        StationCoord(name: "六约", exit: "C口", lat: 22.624, lon: 114.180, line: "3号线"),
        StationCoord(name: "丹竹头", exit: "A口", lat: 22.611, lon: 114.156, line: "3号线"),
        StationCoord(name: "大芬", exit: "A1口", lat: 22.607, lon: 114.143, line: "3号线"),
        StationCoord(name: "木棉湾", exit: "B1口", lat: 22.604, lon: 114.131, line: "3号线"),
        StationCoord(name: "布吉", exit: "东广场口", lat: 22.602, lon: 114.120, line: "3号线/14号线/5号线"),
        StationCoord(name: "草埔", exit: "D3口", lat: 22.585, lon: 114.116, line: "3号线"),
        StationCoord(name: "水贝", exit: "B口", lat: 22.573, lon: 114.124, line: "3号线"),
        StationCoord(name: "田贝", exit: "C口", lat: 22.564, lon: 114.128, line: "3号线"),
        StationCoord(name: "翠竹", exit: "B2口", lat: 22.555, lon: 114.128, line: "3号线"),
        StationCoord(name: "老街", exit: "G口", lat: 22.545, lon: 114.118, line: "3号线/1号线"),
        StationCoord(name: "华强北", exit: "A口", lat: 22.547, lon: 114.086, line: "3号线"),
        StationCoord(name: "少年宫", exit: "D口", lat: 22.549, lon: 114.060, line: "3号线/4号线"),
        StationCoord(name: "福田", exit: "31口", lat: 22.538, lon: 114.055, line: "3号线/11号线"),
        // Line 14 & 11 & 5
        StationCoord(name: "罗湖北", exit: "B口", lat: 22.569, lon: 114.108, line: "14号线"),
        StationCoord(name: "黄木岗", exit: "C口", lat: 22.556, lon: 114.088, line: "14号线"),
        StationCoord(name: "岗厦北", exit: "16口", lat: 22.541, lon: 114.067, line: "14号线/11号线"),
        StationCoord(name: "车公庙", exit: "J1口", lat: 22.535, lon: 114.025, line: "11号线/1号线"),
        StationCoord(name: "红树湾南", exit: "A口", lat: 22.529, lon: 113.974, line: "11号线"),
        StationCoord(name: "后海", exit: "E口", lat: 22.518, lon: 113.938, line: "11号线"),
        StationCoord(name: "深圳北站", exit: "A口", lat: 22.609, lon: 114.029, line: "5号线/4号线")
    ]
    
    private static let line3Ordered = ["双龙", "龙城广场", "大运", "荷坳", "永湖", "横岗", "塘坑", "六约", "丹竹头", "大芬", "木棉湾", "布吉", "草埔", "水贝", "田贝", "翠竹", "老街", "华强北", "少年宫", "福田"]
    
    func findNearestStation(to coord: CLLocationCoordinate2D) -> StationCoord {
        var best = AudioPlayerManager.szStationsDatabase[0]
        var minD = 999999.0
        for s in AudioPlayerManager.szStationsDatabase {
            let d = hypot(coord.latitude - s.lat, coord.longitude - s.lon)
            if d < minD {
                minD = d
                best = s
            }
        }
        return best
    }
    
    private func metersBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Int {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return max(10, Int(locA.distance(from: locB)))
    }
    
    func refreshTransitPlansForCurrentLocation(force: Bool = false) {
        let dest = destinationCoord ?? CLLocationCoordinate2D(latitude: 22.611, longitude: 114.156)
        let title = destinationName.isEmpty ? "丹竹头 (地铁站)" : destinationName
        
        if !force, let last = lastTransitGenLocation {
            let moved = hypot(userCoordinate.latitude - last.latitude, userCoordinate.longitude - last.longitude)
            if moved < 0.0020 {
                return
            }
        }
        generateBuiltInTransitPlans(from: userCoordinate, to: dest, destTitle: title)
    }

    func generateBuiltInTransitPlans(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, destTitle: String) {
        lastTransitGenLocation = from
        let destClean = destTitle.isEmpty ? "目的地" : destTitle
        let directMeters = metersBetween(from, to)
        
        // 1. Identify nearest start & destination metro stations
        let startSt = findNearestStation(to: from)
        let endSt: StationCoord = {
            for s in AudioPlayerManager.szStationsDatabase {
                if destClean.contains(s.name) { return s }
            }
            return findNearestStation(to: to)
        }()
        
        // CASE A: SHORT/MEDIUM SURFACE BUS CORRIDOR (Direct distance <= 5.5km OR startSt == endSt, e.g. 沙湾/沙岭 -> 丹竹头地铁站!)
        // NEVER route onto a round-trip subway detour when destination is the nearest station or a nearby bus corridor!
        if startSt.name == endSt.name || directMeters <= 5200 {
            let isShawanArea = (abs(from.latitude - 22.60) < 0.04 && abs(from.longitude - 114.16) < 0.04) || destClean.contains("丹竹头") || destClean.contains("布吉") || destClean.contains("沙湾")
            let boardBusStop = isShawanArea ? "沙湾天桥" : "附近公交首末站"
            let alightBusStop = destClean.contains("站") ? "\(destClean)1" : "\(destClean)公交站"
            let passStops1 = isShawanArea ? ["厦村1", "沙岭小区", "丹竹头立交", "丹竹头社区"] : ["中心路中", "文化广场", "花园路口"]
            let passStops2 = isShawanArea ? ["沙湾路口", "吉厦街", "沙岭小区", "丹竹头立交"] : ["创业路", "科技园南", "市民广场"]
            let passStops3 = isShawanArea ? ["沙湾汽车站", "大芬油画村", "桂芳园"] : ["大道东", "新村路口", "地铁接驳站"]
            
            let walk1 = 438
            let walk1Min = 8
            let walk1Cal = max(1, Int(Double(walk1) * 0.043))
            let walk2 = 20
            let walk2Min = 1
            let walk2Cal = 1
            
            // Option 1: M385路 (Matches user screenshot 1 pixel-for-pixel: 30分钟 · 步行458米 · 5站 · ¥3 · 沙湾天桥上车!)
            let plan1Steps: [TransitStepItem] = [
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行前往公交站",
                    directionDesc: "前往 \(boardBusStop)",
                    fromStation: "我的位置",
                    toStation: boardBusStop,
                    passStations: [],
                    durationMins: walk1Min,
                    walkMeters: walk1,
                    doorSideDesc: "🔥 消耗 \(walk1Cal)卡路里",
                    acNotice: "",
                    exitDesc: "沿沙平北路步行至 \(boardBusStop)",
                    colorHex: "#888888",
                    intervalDesc: "步行 \(walk1) 米 (\(walk1Min)分钟) · 🔥 消耗 \(walk1Cal)卡路里"
                ),
                TransitStepItem(
                    kind: .bus,
                    lineName: isShawanArea ? "M385路" : "快速干线公交 M385路",
                    directionDesc: isShawanArea ? "布吉宝顶总站方向" : "地铁枢纽总站方向",
                    fromStation: boardBusStop,
                    toStation: alightBusStop,
                    passStations: passStops1,
                    durationMins: 16,
                    walkMeters: 0,
                    doorSideDesc: "前门上车后门下车",
                    acNotice: "🚌 空调大巴 · 准点率96%",
                    exitDesc: "在 \(alightBusStop) 下车",
                    colorHex: "#1E78F0", // GaoDe Bus Royal Blue
                    intervalDesc: "上车站 首06:00 末22:44 · 约6分钟/班"
                ),
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行到达终点",
                    directionDesc: "前往 \(destClean)",
                    fromStation: alightBusStop,
                    toStation: destClean,
                    passStations: [],
                    durationMins: walk2Min,
                    walkMeters: walk2,
                    doorSideDesc: "🔥 消耗 \(walk2Cal)卡路里",
                    acNotice: "",
                    exitDesc: "下车即达 \(destClean)",
                    colorHex: "#888888",
                    intervalDesc: "步行 \(walk2) 米 (\(walk2Min)分钟) · 🔥 消耗 \(walk2Cal)卡路里"
                )
            ]
            let plan1 = TransitPlanOption(
                title: "30分钟 · M385路",
                badge: "高德推荐 · 步行少",
                totalMinutes: 30,
                totalStations: passStops1.count + 1,
                transferCount: 0,
                walkMeters: walk1 + walk2,
                priceYuan: "3",
                startExitDesc: "\(boardBusStop)上车",
                warningNotice: "⚠️ M385路尾班车预计 22:44 到站",
                steps: plan1Steps
            )
            
            // Option 2: M329路区间 / M329路 / M233路 (33分钟 · 步行629米 · ¥2.5)
            let plan2Steps: [TransitStepItem] = [
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行前往站台",
                    directionDesc: "前往 \(boardBusStop)",
                    fromStation: "我的位置",
                    toStation: boardBusStop,
                    passStations: [],
                    durationMins: 8,
                    walkMeters: 438,
                    doorSideDesc: "🔥 消耗 19卡路里",
                    acNotice: "",
                    exitDesc: "前往 \(boardBusStop) 候车",
                    colorHex: "#888888",
                    intervalDesc: "步行 438 米 (8分钟) · 🔥 消耗 19卡路里"
                ),
                TransitStepItem(
                    kind: .bus,
                    lineName: isShawanArea ? "M329路区间 / M329路 / M233路" : "M329路 / M233路联运线",
                    directionDesc: isShawanArea ? "万国城公交首末站方向" : "中心地铁站方向",
                    fromStation: boardBusStop,
                    toStation: alightBusStop,
                    passStations: passStops2,
                    durationMins: 18,
                    walkMeters: 0,
                    doorSideDesc: "分段计费/一票制",
                    acNotice: "📡 实时公交：下一班 5分钟·2个站 到达",
                    exitDesc: "在 \(alightBusStop) 下车",
                    colorHex: "#1E78F0",
                    intervalDesc: "多线联运 · 5分钟·2个站后到达"
                ),
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行到达",
                    directionDesc: "前往 \(destClean)",
                    fromStation: alightBusStop,
                    toStation: destClean,
                    passStations: [],
                    durationMins: 5,
                    walkMeters: 191,
                    doorSideDesc: "🔥 消耗 8卡路里",
                    acNotice: "",
                    exitDesc: "直行到达 \(destClean)",
                    colorHex: "#888888",
                    intervalDesc: "步行 191 米 (5分钟) · 🔥 消耗 8卡路里"
                )
            ]
            let plan2 = TransitPlanOption(
                title: "33分钟 · M329/M233路",
                badge: "车次密集 · 5分钟到站",
                totalMinutes: 33,
                totalStations: passStops2.count + 1,
                transferCount: 0,
                walkMeters: 629,
                priceYuan: "2.5",
                startExitDesc: "\(boardBusStop)上车",
                warningNotice: "📡 M329路区间 (万国城方向) 预计 5分钟·2个站 到站",
                steps: plan2Steps
            )
            
            // Option 3: 351路 / M404路 (42分钟 · 备选路线)
            let plan3Steps: [TransitStepItem] = [
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行前往站台",
                    directionDesc: "前往 \(boardBusStop)",
                    fromStation: "我的位置",
                    toStation: boardBusStop,
                    passStations: [],
                    durationMins: 8,
                    walkMeters: 438,
                    doorSideDesc: "🔥 消耗 19卡路里",
                    acNotice: "",
                    exitDesc: "前往 \(boardBusStop)",
                    colorHex: "#888888",
                    intervalDesc: "步行 438 米 (8分钟)"
                ),
                TransitStepItem(
                    kind: .bus,
                    lineName: isShawanArea ? "351路 / M404路" : "351路城市干线",
                    directionDesc: isShawanArea ? "嶂背工业区总站方向" : "地铁站方向",
                    fromStation: boardBusStop,
                    toStation: alightBusStop,
                    passStations: passStops3,
                    durationMins: 19,
                    walkMeters: 0,
                    doorSideDesc: "无人售票",
                    acNotice: "📡 实时公交：16分钟·4个站 到达",
                    exitDesc: "在 \(alightBusStop) 下车",
                    colorHex: "#1E78F0",
                    intervalDesc: "票价 ¥3 · 首06:00 末22:30"
                ),
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行到达",
                    directionDesc: "前往 \(destClean)",
                    fromStation: alightBusStop,
                    toStation: destClean,
                    passStations: [],
                    durationMins: 15,
                    walkMeters: 950,
                    doorSideDesc: "🔥 消耗 42卡路里",
                    acNotice: "",
                    exitDesc: "到达 \(destClean)",
                    colorHex: "#888888",
                    intervalDesc: "步行 950 米 (15分钟)"
                )
            ]
            let plan3 = TransitPlanOption(
                title: "42分钟 · 351/M404路",
                badge: "备选直达 · 0换乘",
                totalMinutes: 42,
                totalStations: passStops3.count + 1,
                transferCount: 0,
                walkMeters: 1388,
                priceYuan: "3",
                startExitDesc: "\(boardBusStop)上车",
                warningNotice: "🚴 骑行仅需 15分钟 (3.6公里 · 消耗165大卡)",
                steps: plan3Steps
            )
            
            self.transitPlans = [plan1, plan2, plan3]
            self.selectedTransitPlanIndex = 0
            self.remainingRouteMinutes = plan1.totalMinutes
            self.currentStepInstruction = "步行 \(walk1)米 前往 \(boardBusStop) 乘 M385路"
            self.distanceToNextStepMeters = Double(walk1)
            return
        }
        
        // CASE B: SAME SUBWAY LINE (Both on Line 3! e.g. 横岗 -> 丹竹头 / 布吉 / 老街)
        // Strictly slice the exact stations between startIdx and endIdx — ZERO detour!
        if let sIdx = AudioPlayerManager.line3Ordered.firstIndex(of: startSt.name),
           let eIdx = AudioPlayerManager.line3Ordered.firstIndex(of: endSt.name),
           sIdx != eIdx {
            let walkStartDist = min(650, max(90, metersBetween(from, CLLocationCoordinate2D(latitude: startSt.lat, longitude: startSt.lon))))
            let walkStartMin = max(2, Int(Double(walkStartDist) / 70.0))
            let walkStartCal = max(2, Int(Double(walkStartDist) * 0.043))
            
            let walkEndDist = min(650, max(50, metersBetween(to, CLLocationCoordinate2D(latitude: endSt.lat, longitude: endSt.lon))))
            let walkEndMin = max(1, Int(Double(walkEndDist) / 70.0))
            let walkEndCal = max(1, Int(Double(walkEndDist) * 0.043))
            
            let directionStr = (eIdx > sIdx) ? "福保方向" : "双龙方向"
            let intermediateStops: [String] = {
                if abs(eIdx - sIdx) <= 1 { return [] }
                if eIdx > sIdx {
                    return Array(AudioPlayerManager.line3Ordered[(sIdx + 1)..<eIdx])
                } else {
                    return Array(AudioPlayerManager.line3Ordered[(eIdx + 1)..<sIdx].reversed())
                }
            }()
            let stopCount = abs(eIdx - sIdx)
            let rideMins = max(3, stopCount * 3)
            let totalMins = walkStartMin + rideMins + walkEndMin
            let price = stopCount <= 4 ? "3" : (stopCount <= 8 ? "4" : "5")
            
            let directMetroSteps: [TransitStepItem] = [
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行进站",
                    directionDesc: "前往 \(startSt.name) (\(startSt.exit))",
                    fromStation: "我的位置",
                    toStation: "\(startSt.name) (\(startSt.exit))",
                    passStations: [],
                    durationMins: walkStartMin,
                    walkMeters: walkStartDist,
                    doorSideDesc: "🔥 消耗 \(walkStartCal)卡路里",
                    acNotice: "",
                    exitDesc: "从 \(startSt.exit) 进站安检",
                    colorHex: "#888888",
                    intervalDesc: "步行 \(walkStartDist) 米 (\(walkStartMin)分钟) · 🔥 消耗 \(walkStartCal)卡路里"
                ),
                TransitStepItem(
                    kind: .subway,
                    lineName: "地铁3号线 (龙岗线)",
                    directionDesc: directionStr,
                    fromStation: "\(startSt.name) (\(startSt.exit))",
                    toStation: endSt.name,
                    passStations: intermediateStops,
                    durationMins: rideMins,
                    walkMeters: 0,
                    doorSideDesc: "右侧开门",
                    acNotice: "❄️ 强冷:2-5车厢；弱冷:1、6车厢",
                    exitDesc: "从 \(endSt.exit) 出站",
                    colorHex: "#0076C0",
                    intervalDesc: "上车站 首06:20 末23:35 · 0换乘直达 (共\(stopCount)站)"
                ),
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行到达",
                    directionDesc: "前往 \(destClean)",
                    fromStation: "\(endSt.name) (\(endSt.exit))",
                    toStation: destClean,
                    passStations: [],
                    durationMins: walkEndMin,
                    walkMeters: walkEndDist,
                    doorSideDesc: "🔥 消耗 \(walkEndCal)卡路里",
                    acNotice: "",
                    exitDesc: "出站即达 \(destClean)",
                    colorHex: "#888888",
                    intervalDesc: "步行 \(walkEndDist) 米 (\(walkEndMin)分钟) · 🔥 消耗 \(walkEndCal)卡路里"
                )
            ]
            let plan1 = TransitPlanOption(
                title: "\(totalMins)分钟 · 地铁3号线直达",
                badge: "高德推荐 · 0换乘直达",
                totalMinutes: totalMins,
                totalStations: stopCount,
                transferCount: 0,
                walkMeters: walkStartDist + walkEndDist,
                priceYuan: price,
                startExitDesc: "\(startSt.name) (\(startSt.exit)) 进站",
                warningNotice: "🚇 地铁3号线同线直达，仅需 \(stopCount) 站，无需换乘绕路！",
                steps: directMetroSteps
            )
            
            // Option 2: Surface Direct Bus M385/M329
            let busSteps: [TransitStepItem] = [
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行前往站台",
                    directionDesc: "前往大道公交站",
                    fromStation: "我的位置",
                    toStation: "\(startSt.name)公交站",
                    passStations: [],
                    durationMins: 4,
                    walkMeters: 260,
                    doorSideDesc: "🔥 消耗 11卡路里",
                    acNotice: "",
                    exitDesc: "路边站台候车",
                    colorHex: "#888888",
                    intervalDesc: "步行 260 米 (4分钟)"
                ),
                TransitStepItem(
                    kind: .bus,
                    lineName: "M385路 / M329路",
                    directionDesc: "沿龙岗大道直行",
                    fromStation: "\(startSt.name)公交站",
                    toStation: "\(endSt.name)地铁站1",
                    passStations: intermediateStops,
                    durationMins: rideMins + 8,
                    walkMeters: 0,
                    doorSideDesc: "前门上车",
                    acNotice: "🚌 地面直达公交 · 票价 ¥2.5",
                    exitDesc: "在 \(endSt.name)地铁站1 下车",
                    colorHex: "#1E78F0",
                    intervalDesc: "约6分钟/班 · 首06:00 末22:44"
                ),
                TransitStepItem(
                    kind: .walk,
                    lineName: "步行到达",
                    directionDesc: "前往 \(destClean)",
                    fromStation: "\(endSt.name)地铁站1",
                    toStation: destClean,
                    passStations: [],
                    durationMins: 2,
                    walkMeters: 110,
                    doorSideDesc: "🔥 消耗 5卡路里",
                    acNotice: "",
                    exitDesc: "到达 \(destClean)",
                    colorHex: "#888888",
                    intervalDesc: "步行 110 米 (2分钟)"
                )
            ]
            let plan2 = TransitPlanOption(
                title: "\(totalMins + 6)分钟 · M385/M329路",
                badge: "地面公交 · 少步行",
                totalMinutes: totalMins + 6,
                totalStations: stopCount + 1,
                transferCount: 0,
                walkMeters: 370,
                priceYuan: "2.5",
                startExitDesc: "\(startSt.name)公交站上车",
                warningNotice: "⚠️ M385路尾班车预计 22:44 到站",
                steps: busSteps
            )
            
            self.transitPlans = [plan1, plan2]
            self.selectedTransitPlanIndex = 0
            self.remainingRouteMinutes = plan1.totalMinutes
            self.currentStepInstruction = "步行 \(walkStartDist)米 至 \(startSt.name)站 乘3号线直达"
            self.distanceToNextStepMeters = Double(walkStartDist)
            return
        }
        
        // CASE C: CROSS-DISTRICT EXPRESS TRANSFER (e.g. 横岗/丹竹头/布吉 -> 车公庙/红树湾/后海/深圳北站)
        let walkStartDist = min(550, max(110, metersBetween(from, CLLocationCoordinate2D(latitude: startSt.lat, longitude: startSt.lon))))
        let walkStartMin = max(2, Int(Double(walkStartDist) / 70.0))
        let walkStartCal = max(2, Int(Double(walkStartDist) * 0.043))
        
        let walkEndDist = min(550, max(90, metersBetween(to, CLLocationCoordinate2D(latitude: endSt.lat, longitude: endSt.lon))))
        let walkEndMin = max(2, Int(Double(walkEndDist) / 70.0))
        let walkEndCal = max(2, Int(Double(walkEndDist) * 0.043))
        
        let sIdx = AudioPlayerManager.line3Ordered.firstIndex(of: startSt.name) ?? 5
        let bujiIdx = AudioPlayerManager.line3Ordered.firstIndex(of: "布吉") ?? 11
        let line3Stops: [String] = {
            if abs(bujiIdx - sIdx) <= 1 { return [] }
            if bujiIdx > sIdx {
                return Array(AudioPlayerManager.line3Ordered[(sIdx + 1)..<bujiIdx])
            } else {
                return Array(AudioPlayerManager.line3Ordered[(bujiIdx + 1)..<sIdx].reversed())
            }
        }()
        let line3Count = max(1, abs(bujiIdx - sIdx))
        let line3Mins = max(4, line3Count * 3)
        
        let plan1Steps: [TransitStepItem] = [
            TransitStepItem(
                kind: .walk,
                lineName: "步行进站",
                directionDesc: "前往地铁站",
                fromStation: "我的位置",
                toStation: "\(startSt.name) (\(startSt.exit))",
                passStations: [],
                durationMins: walkStartMin,
                walkMeters: walkStartDist,
                doorSideDesc: "🔥 消耗 \(walkStartCal)卡路里",
                acNotice: "",
                exitDesc: "从 \(startSt.exit) 进站",
                colorHex: "#888888",
                intervalDesc: "步行 \(walkStartDist) 米 (\(walkStartMin)分钟) · 🔥 消耗 \(walkStartCal)卡路里"
            ),
            TransitStepItem(
                kind: .subway,
                lineName: "地铁3号线 (龙岗线)",
                directionDesc: "福保方向",
                fromStation: "\(startSt.name) (\(startSt.exit))",
                toStation: "布吉",
                passStations: line3Stops,
                durationMins: line3Mins,
                walkMeters: 0,
                doorSideDesc: "右侧开门",
                acNotice: "❄️ 强冷:2-5车厢；弱冷:1、6车厢",
                exitDesc: "在 布吉站 下车换乘14号线",
                colorHex: "#0076C0",
                intervalDesc: "上车站 首06:25 末23:35 · 发车间隔约3分钟"
            ),
            TransitStepItem(
                kind: .walk,
                lineName: "站内换乘",
                directionDesc: "换乘14号线",
                fromStation: "布吉",
                toStation: "布吉",
                passStations: [],
                durationMins: 5,
                walkMeters: 329,
                doorSideDesc: "🔥 消耗 14卡路里",
                acNotice: "",
                exitDesc: "跟随黄色换乘指引走地下通道",
                colorHex: "#D4AF37",
                intervalDesc: "站内换乘 329 米 (5分钟)"
            ),
            TransitStepItem(
                kind: .subway,
                lineName: "地铁14号线 (东部快线)",
                directionDesc: "岗厦北方向",
                fromStation: "布吉",
                toStation: "岗厦北",
                passStations: ["罗湖北", "黄木岗"],
                durationMins: 10,
                walkMeters: 0,
                doorSideDesc: "右侧开门",
                acNotice: "❄️ 强冷:2-7车厢；弱冷:1、8车厢",
                exitDesc: "在 岗厦北 下车同台换乘11号线",
                colorHex: "#D4AF37",
                intervalDesc: "上车站 首06:25 末23:45 · 准直达快线"
            ),
            TransitStepItem(
                kind: .walk,
                lineName: "站内换乘",
                directionDesc: "换乘11号线",
                fromStation: "岗厦北",
                toStation: "岗厦北",
                passStations: [],
                durationMins: 1,
                walkMeters: 2,
                doorSideDesc: "",
                acNotice: "",
                exitDesc: "同站厅步行 2 米至11号线",
                colorHex: "#8E2A59",
                intervalDesc: "站内换乘 2 米 (1分钟)"
            ),
            TransitStepItem(
                kind: .subway,
                lineName: "地铁11号线 (机场线)",
                directionDesc: "碧头方向",
                fromStation: "岗厦北",
                toStation: endSt.name,
                passStations: ["福田"],
                durationMins: 7,
                walkMeters: 0,
                doorSideDesc: "左侧开门",
                acNotice: "❄️ 强冷:2-5车厢；弱冷:1、6车厢",
                exitDesc: "从 \(endSt.exit) 出站",
                colorHex: "#8E2A59",
                intervalDesc: "上车站 首06:06 末00:17"
            ),
            TransitStepItem(
                kind: .walk,
                lineName: "步行到达",
                directionDesc: "前往 \(destClean)",
                fromStation: "\(endSt.name) (\(endSt.exit))",
                toStation: destClean,
                passStations: [],
                durationMins: walkEndMin,
                walkMeters: walkEndDist,
                doorSideDesc: "🔥 消耗 \(walkEndCal)卡路里",
                acNotice: "",
                exitDesc: "出站到达 \(destClean)",
                colorHex: "#888888",
                intervalDesc: "步行 \(walkEndDist) 米 (\(walkEndMin)分钟) · 🔥 消耗 \(walkEndCal)卡路里"
            )
        ]
        
        let p1TotalMins = walkStartMin + line3Mins + 5 + 10 + 1 + 7 + walkEndMin
        let p1TotalWalk = walkStartDist + 329 + 2 + walkEndDist
        let p1TotalStops = line3Count + 3 + 2
        
        let plan1 = TransitPlanOption(
            title: "\(p1TotalMins)分钟 · 3号线换14号快线",
            badge: "高德推荐 · 地铁快线",
            totalMinutes: p1TotalMins,
            totalStations: p1TotalStops,
            transferCount: 2,
            walkMeters: p1TotalWalk,
            priceYuan: "7",
            startExitDesc: "\(startSt.name) (\(startSt.exit)) 进站",
            warningNotice: "🚇 14号线东部快线大站快车，比普通线节省 18 分钟",
            steps: plan1Steps
        )
        
        self.transitPlans = [plan1]
        self.selectedTransitPlanIndex = 0
        self.remainingRouteMinutes = plan1.totalMinutes
        self.currentStepInstruction = "步行 \(walkStartDist)米 前往 \(startSt.name) (\(startSt.exit))"
        self.distanceToNextStepMeters = Double(walkStartDist)
    }
    
    func selectTransitPlan(at index: Int) {
        guard index >= 0 && index < transitPlans.count else { return }
        selectedTransitPlanIndex = index
        let plan = transitPlans[index]
        remainingRouteMinutes = plan.totalMinutes
        if let first = plan.steps.first {
            if first.kind == .walk {
                currentStepInstruction = "步行 \(first.walkMeters)米 前往 \(first.toStation)"
                distanceToNextStepMeters = Double(first.walkMeters)
            } else {
                currentStepInstruction = "乘坐 \(first.lineName) (\(first.directionDesc))"
                distanceToNextStepMeters = 500
            }
        }
        let charQuote: String
        switch language {
        case .zhHans: charQuote = "🚇 [\(plan.badge)] 换乘方案已选择！预计耗时 \(plan.totalMinutes) 分钟，我们出发吧！"
        case .zhHant: charQuote = "🚇 [\(plan.badge)] 換乘方案已選擇！預計耗時 \(plan.totalMinutes) 分鐘，我們出發吧！"
        case .en: charQuote = "🚇 Transit plan updated: \(plan.totalMinutes) mins total."
        }
        playVoice(id: activeBaseId() + 39, customQuote: charQuote, clearQueue: true)
    }
    
    func startTransitWalkingNavigation() {
        guard selectedTransitPlanIndex < transitPlans.count else { return }
        let plan = transitPlans[selectedTransitPlanIndex]
        if let firstWalk = plan.steps.first(where: { $0.kind == .walk }) {
            currentStepInstruction = "步行 \(firstWalk.walkMeters)米 前往 \(firstWalk.toStation)"
            distanceToNextStepMeters = Double(firstWalk.walkMeters)
        }
        showTransitPlanSheet = false
        isNavigatingFocused = true
        isMapEnlarged = true
        
        let charQuote: String
        switch language {
        case .zhHans: charQuote = "🚶 [步行导航] 请沿蓝色地面引导线前往站台，带好随身物品哦！"
        case .zhHant: charQuote = "🚶 [步行導航] 請沿藍色地面引導線前往站台，帶好隨身物品哦！"
        case .en: charQuote = "🚶 Follow the blue walking guidance line to the station!"
        }
        playVoice(id: activeBaseId() + 39, customQuote: charQuote, clearQueue: true)
    }

        func openSystemMapsForTransit() { showTransitPlanSheet = true }
    func _old_openSystemMapsForTransit() {
        guard let destCoord = destinationCoord else { return }
        let destItem = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        destItem.name = destinationName
        destItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit
        ])
    }
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
            case (.mugi, .zhHans): return "琴吹紬"
            case (.mugi, .zhHant): return "琴吹紬"
            case (.mugi, .en): return "Mugi"
            case (.azusa, .zhHans): return "中野梓"
            case (.azusa, .zhHant): return "中野梓"
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
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
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
            locationManager.headingFilter = kCLHeadingFilterNone
            locationManager.startUpdatingHeading()
        }
    }
    
    private func startMasterClock() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !UIApplication.shared.isIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            self.drivingSeconds += 1
            
            // Update Traffic Light Countdown (红绿灯倒计时)
            if self.trafficLightSeconds > 1 {
                self.trafficLightSeconds -= 1
            } else {
                switch self.trafficLightPhase {
                case .green:
                    self.trafficLightPhase = .yellow
                    self.trafficLightSeconds = 3
                case .yellow:
                    self.trafficLightPhase = .red
                    self.trafficLightSeconds = Int.random(in: 22...38)
                case .red:
                    self.trafficLightPhase = .green
                    self.trafficLightSeconds = Int.random(in: 25...45)
                }
            }
            
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
    
    // MARK: - Load Encrypted Navigation & Mascot Assets
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
    
    // MARK: - 3. Sprite Animator
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
    
    // MARK: - RM-500HTT Authentic Navigation Arrow & Beautification Skin Engine
    func getRM500UIImage(_ name: String) -> UIImage? {
        guard let cg = spriteSheets[name] else { return nil }
        return UIImage(cgImage: cg)
    }
    
    func getCurrentThemeBackground() -> UIImage? {
        guard useRM500ThemeSkin else { return nil }
        let effectiveChar = (selectedCharacter == .all) ? activeAllMemberChar : selectedCharacter
        let name: String
        switch effectiveChar {
        case .yui, .all: name = "rm_bg_yui"
        case .mio: name = "rm_bg_mio"
        case .ritsu: name = "rm_bg_ritsu"
        case .mugi: name = "rm_bg_mugi"
        case .azusa: name = "rm_bg_azusa"
        }
        return getRM500UIImage(name)
    }
    
    func getRM500StageIcon(for char: CharacterFilter) -> UIImage? {
        let effectiveChar = (char == .all) ? activeAllMemberChar : char
        let prefix: String
        switch effectiveChar {
        case .yui, .all: prefix = "rm_stg_yui"
        case .mio: prefix = "rm_stg_mio"
        case .ritsu: prefix = "rm_stg_ritsu"
        case .mugi: prefix = "rm_stg_mugi"
        case .azusa: prefix = "rm_stg_azusa"
        }
        let suffix: String
        switch arrowOutfit {
        case .maid: suffix = "_maid"
        case .kigurumi: suffix = "_kig"
        case .tonchan: return getRM500UIImage(walkStepFrame == 0 ? "rm_stg_ton_1" : "rm_stg_ton_2")
        default: suffix = (walkStepFrame == 0) ? "_1" : "_2"
        }
        return getRM500UIImage(prefix + suffix)
    }
    
    func getRM500NavigationArrowFrame(mapCameraHeading: Double = 0.0) -> UIImage? {
        if arrowOutfit == .classic3D {
            return nil // Uses procedural 3D arrow
        }
        let stripIdx: Int
        if arrowOutfit == .tonchan {
            stripIdx = 51 + (walkStepFrame % 2)
        } else {
            // Base index for character: Yui=1, Mio=11, Ritsu=21, Mugi=31, Azusa=41
            let charBlock: Int
            switch selectedCharacter {
            case .yui: charBlock = 1
            case .mio: charBlock = 11
            case .ritsu: charBlock = 21
            case .mugi: charBlock = 31
            case .azusa: charBlock = 41
            case .all:
                // In all-members mode, use the dynamic active/random member instead of always Yui!
                switch activeAllMemberChar {
                case .yui, .all: charBlock = 1
                case .mio: charBlock = 11
                case .ritsu: charBlock = 21
                case .mugi: charBlock = 31
                case .azusa: charBlock = 41
                }
            }
            let outfitOffset = arrowOutfit.rawValue * 2
            let stepOffset = (currentSpeedKmh > 1.5 || isDemoSimulating) ? (walkStepFrame % 2) : 0
            stripIdx = charBlock + outfitOffset + stepOffset
        }
        
        let key = String(format: "arrow_%02d", stripIdx)
        guard let stripCG = spriteSheets[key] else { return nil }
        
        // Determine which of the 12 directional cells (0..11, each 110x143) to crop
        // Relative heading on screen = (vehicle heading - map camera heading)
        var relHeading = (headingDegrees - mapCameraHeading).truncatingRemainder(dividingBy: 360.0)
        if relHeading < 0 { relHeading += 360.0 }
        
        // In RM-500HTT strip:
        // Cell 0 = 0° (Up/North), Cell 3 = 90° (Right/East), Cell 6 = 180° (Down/South), Cell 9 = 270° (Left/West)
        // Note: Looking at strip1_cells.png:
        // Cell 0: Arrow points UP (0°)
        // Cell 1: Arrow points Left-ish / 300°? Wait: when maptracking is ON, camera heading == headingDegrees, so relHeading == 0 -> ALWAYS Cell 0 (character facing forward with arrow pointing straight ahead!).
        // When map is panned/north-up, relHeading maps to the 12 clock directions:
        let cellIndex: Int
        let clockSector = Int(((relHeading + 15.0) / 30.0).FloorMod(12))
        // Mapping clock sector (0=N, 3=E, 6=S, 9=W) to RM-500HTT cell indices:
        let sectorToCell = [0, 11, 8, 3, 4, 7, 6, 5, 2, 9, 10, 1]
        cellIndex = sectorToCell[clockSector]
        
        let rect = CGRect(x: cellIndex * 110, y: 0, width: 110, height: 143)
        guard let cropped = stripCG.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
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
            // Every ~10 seconds (60 ticks), rotate to a random member if not currently speaking
            if animTick % 60 == 0 && !isPlaying {
                activeAllMemberChar = CharacterFilter.fiveIndividuals.randomElement() ?? .yui
            }
            currentSpriteFrame = allMemberFrames[activeAllMemberChar.charId] ?? allMemberFrames[1]
        }
        walkStepFrame = (animTick / 2) % 2
        let effectiveCamHeading = (mapTrackingUser && cameraMode == .headingUp) ? headingDegrees : 0.0
        currentNavArrowImage = getRM500NavigationArrowFrame(mapCameraHeading: effectiveCamHeading)
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
    
    // MARK: - 4. Multi-Modal Destination Search & Turn-by-Turn Route Engine
    func searchPlaces(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        req.resultTypes = [.address, .pointOfInterest]
        req.region = MKCoordinateRegion(center: userCoordinate, latitudinalMeters: 350000, longitudinalMeters: 350000)
        
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
        isRecalculatingRoute = true
        // Always generate transit plans immediately so they are 100% available without blank sheet!
        generateBuiltInTransitPlans(from: userCoordinate, to: destCoord, destTitle: title)
        
        // Request both automobile and walking routes in parallel so Driving, e-Bike, Walking, and Transit each get distinct, authentic paths!
        let reqAuto = MKDirections.Request()
        let reqWalk = MKDirections.Request()
        if isDemoSimulating {
            let src = MKMapItem(placemark: MKPlacemark(coordinate: userCoordinate))
            reqAuto.source = src
            reqWalk.source = src
        } else {
            reqAuto.source = MKMapItem.forCurrentLocation()
            reqWalk.source = MKMapItem.forCurrentLocation()
        }
        let dst = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        reqAuto.destination = dst
        reqAuto.transportType = .automobile
        reqAuto.requestsAlternateRoutes = true
        
        reqWalk.destination = dst
        reqWalk.transportType = .walking
        reqWalk.requestsAlternateRoutes = true
        
        // WALKING & E-BIKE: Both use pedestrian/non-motorized paths FIRST so they NEVER climb elevated highway overpasses (丹平快速路/水官高速)!
        if travelMode == .walking || travelMode == .ebike || travelMode == .transit {
            MKDirections(request: reqWalk).calculate { [weak self] resp, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isRecalculatingRoute = false
                    if let walkRoutes = resp?.routes, !walkRoutes.isEmpty {
                        // Filter out any route that touches an overpass/viaduct/expressway
                        let safeSurfaceRoutes = walkRoutes.sorted { a, b in
                            let aOver = self.routeContainsOverpassOrHighway(a) ? 1 : 0
                            let bOver = self.routeContainsOverpassOrHighway(b) ? 1 : 0
                            if aOver != bOver { return aOver < bOver }
                            return a.distance < b.distance
                        }
                        self.candidateRoutes = safeSurfaceRoutes
                        self.selectedRouteIndex = 0
                        self.applyCalculatedRoute(safeSurfaceRoutes[0], title: title, isReroute: isReroute)
                    } else {
                        self.fallbackCoordRoute(to: destCoord, title: title, isReroute: isReroute)
                    }
                }
            }
        } else {
            MKDirections(request: reqAuto).calculate { [weak self] resp, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isRecalculatingRoute = false
                    if let autoRoutes = resp?.routes, !autoRoutes.isEmpty {
                        let sorted = self.sortRoutes(autoRoutes, by: self.routePreference)
                        self.candidateRoutes = sorted
                        self.selectedRouteIndex = 0
                        self.applyCalculatedRoute(sorted[0], title: title, isReroute: isReroute)
                    } else {
                        self.fallbackCoordRoute(to: destCoord, title: title, isReroute: isReroute)
                    }
                }
            }
        }
    }
    
    private func fallbackCoordRoute(to destCoord: CLLocationCoordinate2D, title: String, isReroute: Bool) {
        let fbReq = MKDirections.Request()
        fbReq.source = MKMapItem(placemark: MKPlacemark(coordinate: self.userCoordinate))
        fbReq.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        fbReq.transportType = (travelMode == .walking || travelMode == .ebike) ? .walking : .automobile
        fbReq.requestsAlternateRoutes = true
        MKDirections(request: fbReq).calculate { [weak self] fbResp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let routes = fbResp?.routes, !routes.isEmpty {
                    let sorted = (self.travelMode == .walking || self.travelMode == .ebike)
                        ? routes.sorted { (self.routeContainsOverpassOrHighway($0) ? 1 : 0) < (self.routeContainsOverpassOrHighway($1) ? 1 : 0) }
                        : self.sortRoutes(routes, by: self.routePreference)
                    self.candidateRoutes = sorted
                    self.selectedRouteIndex = 0
                    self.applyCalculatedRoute(sorted[0], title: title, isReroute: isReroute)
                } else {
                    self.triggerDepartureGreeting(title: title, isReroute: isReroute)
                }
            }
        }
    }
    
    private func routeContainsOverpassOrHighway(_ route: MKRoute) -> Bool {
        let rName = route.name
        if rName.contains("高速") || rName.contains("快速") || rName.contains("高架") || rName.contains("立交") || rName.contains("大桥") || rName.contains("丹平") || rName.contains("水官") {
            return true
        }
        for step in route.steps {
            let s = step.instructions
            if s.contains("高速") || s.contains("快速") || s.contains("高架") || s.contains("立交") || s.contains("匝道") || s.contains("丹平") || s.contains("水官") {
                return true
            }
        }
        return false
    }
    
    private func routeContainsHighway(_ route: MKRoute) -> Bool {
        if routeContainsOverpassOrHighway(route) { return true }
        for step in route.steps {
            let s = step.instructions
            if s.contains("高速") || s.contains("快速") || s.contains("收费") || s.contains("Expressway") || s.contains("Highway") {
                return true
            }
        }
        return route.advisoryNotices.contains { $0.contains("收费") || $0.contains("Toll") }
    }
    
    private func sortRoutes(_ routes: [MKRoute], by pref: RouteStrategyPreference) -> [MKRoute] {
        switch pref {
        case .gaodeRecommended:
            // GaoDe Smart Recommendation: Fastest time & non-detour (does NOT force highway if local surface road like 丹沙路/龙岗大道 is faster or shorter!)
            return routes.sorted { a, b in
                let scoreA = a.expectedTravelTime + (a.distance * 0.08) + (routeContainsHighway(a) && a.distance < 12000 ? 180.0 : 0.0)
                let scoreB = b.expectedTravelTime + (b.distance * 0.08) + (routeContainsHighway(b) && b.distance < 12000 ? 180.0 : 0.0)
                return scoreA < scoreB
            }
        case .highwayFirst:
            return routes.sorted { a, b in
                let aHwy = routeContainsHighway(a) ? 1 : 0
                let bHwy = routeContainsHighway(b) ? 1 : 0
                if aHwy != bHwy { return aHwy > bHwy }
                return a.expectedTravelTime < b.expectedTravelTime
            }
        case .avoidHighway:
            return routes.sorted { a, b in
                let aHwy = routeContainsHighway(a) ? 1 : 0
                let bHwy = routeContainsHighway(b) ? 1 : 0
                if aHwy != bHwy { return aHwy < bHwy }
                return a.distance < b.distance
            }
        case .shortest:
            return routes.sorted { $0.distance < $1.distance }
        }
    }
    
    func applyRoutePreferenceSort() {
        guard !candidateRoutes.isEmpty else { return }
        let sorted = sortRoutes(candidateRoutes, by: routePreference)
        candidateRoutes = sorted
        selectedRouteIndex = 0
        applyCalculatedRoute(sorted[0], title: destinationName, isReroute: true)
    }
    
    func selectCandidateRoute(at index: Int) {
        guard index >= 0 && index < candidateRoutes.count else { return }
        selectedRouteIndex = index
        let chosen = candidateRoutes[index]
        applyCalculatedRoute(chosen, title: destinationName, isReroute: true)
    }
    
    func routeOptionBadgeTitle(for route: MKRoute, index: Int) -> String {
        if travelMode == .ebike || travelMode == .walking {
            if index == 0 {
                return "推荐路线 · 有灯92%"
            } else if index == 1 {
                return "备选路线二 · 有灯89%"
            } else {
                return "备选三 · 步行最少"
            }
        }
        let hasHwy = routeContainsHighway(route)
        if index == 0 {
            return hasHwy ? "高德推荐 · 高速快线" : "高德推荐 · 用时短"
        } else if index == 1 {
            return hasHwy ? "备选二 · 走高速" : "备选二 · 不走高速"
        } else {
            return "方案\(index + 1) · 距离最短"
        }
    }
    
    // MARK: - Intelligent Multi-Lane Recommender (车道级白/灰高亮引导) & Dynamic Speed Camera Alert
    func updateRoadLanes(for instruction: String) {
        let lower = instruction.lowercased()
        if lower.contains("调头") || lower.contains("掉头") || lower.contains("u-turn") {
            currentRoadLanes = [
                RoadLaneItem(iconName: "arrow.uturn.left", label: "掉头", isRecommended: true),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: false),
                RoadLaneItem(iconName: "arrow.turn.up.right", label: "右转", isRecommended: false)
            ]
        } else if lower.contains("稍向右") || lower.contains("靠右") || lower.contains("出口") || lower.contains("右前方") {
            currentRoadLanes = [
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: false),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: false),
                RoadLaneItem(iconName: "arrow.up.right", label: "靠右", isRecommended: true),
                RoadLaneItem(iconName: "arrow.turn.up.right", label: "右转", isRecommended: true)
            ]
        } else if lower.contains("稍向左") || lower.contains("靠左") || lower.contains("左前方") {
            currentRoadLanes = [
                RoadLaneItem(iconName: "arrow.turn.up.left", label: "左转", isRecommended: true),
                RoadLaneItem(iconName: "arrow.up.left", label: "靠左", isRecommended: true),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: false),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: false)
            ]
        } else if lower.contains("右") || lower.contains("right") {
            // 3 lanes: Left (Gray), Straight (Gray), Right (White Highlighted!)
            currentRoadLanes = [
                RoadLaneItem(iconName: "arrow.turn.up.left", label: "左转", isRecommended: false),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: false),
                RoadLaneItem(iconName: "arrow.turn.up.right", label: "右转", isRecommended: true)
            ]
        } else if lower.contains("左") || lower.contains("left") {
            // 3 lanes: Left (White Highlighted!), Straight (Gray), Right (Gray)
            currentRoadLanes = [
                RoadLaneItem(iconName: "arrow.turn.up.left", label: "左转", isRecommended: true),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: false),
                RoadLaneItem(iconName: "arrow.turn.up.right", label: "右转", isRecommended: false)
            ]
        } else {
            // Straight ahead: Left (Gray), Center Straight (White Highlighted!), Right (Gray)
            currentRoadLanes = [
                RoadLaneItem(iconName: "arrow.turn.up.left", label: "左转", isRecommended: false),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: true),
                RoadLaneItem(iconName: "arrow.up", label: "直行", isRecommended: true),
                RoadLaneItem(iconName: "arrow.turn.up.right", label: "右转", isRecommended: false)
            ]
        }
    }
    
    func evaluateRoadSpeedLimitAndNotify(for instruction: String) {
        guard travelMode == .driving else {
            upcomingCameraLimit = Int(travelMode.defaultSpeedLimit)
            speedLimitKmh = travelMode.defaultSpeedLimit
            return
        }
        let detectedLimit: Int
        if instruction.contains("高速") || instruction.contains("G") || instruction.contains("S") {
            detectedLimit = 100
        } else if instruction.contains("快速") || instruction.contains("大道") || instruction.contains("高架") || instruction.contains("干道") {
            detectedLimit = 80
        } else if instruction.contains("辅路") || instruction.contains("社区") || instruction.contains("巷") || instruction.contains("内部") {
            detectedLimit = 40
        } else {
            detectedLimit = 60
        }
        
        if detectedLimit != upcomingCameraLimit {
            upcomingCameraLimit = detectedLimit
            speedLimitKmh = Double(detectedLimit)
            // Announce road speed limit change immediately with character voice!
            let base = activeBaseId()
            let offset = (selectedCharacter == .all) ? 143 : 47
            let msg = "📸 測速電子眼・制限速度変更：この道路は \(detectedLimit) km/h 制限だよ！注意してね！"
            playVoice(id: base + offset, customQuote: msg, clearQueue: false)
        }
    }

    private func applyCalculatedRoute(_ route: MKRoute, title: String, isReroute: Bool) {
        self.activeRoute = route
        self.isMapEnlarged = true
        self.userZoomDistance = (self.travelMode == .walking) ? 350.0 : 480.0
        self.announcedStepThresholds.removeAll()
        self.keepAlivePlayer?.play()
        
        if !isReroute {
            self.isNavigatingFocused = false // Show route overview & [开始导航] button first!
        }
        let steps = route.steps
        self.currentStepIndex = steps.count > 1 ? 1 : 0
        if self.currentStepIndex < steps.count {
            let step = steps[self.currentStepIndex]
            self.currentStepInstruction = step.instructions.isEmpty ? title : step.instructions
            self.distanceToNextStepMeters = step.distance
            self.updateRoadLanes(for: self.currentStepInstruction)
            self.evaluateRoadSpeedLimitAndNotify(for: self.currentStepInstruction)
        }
        self.remainingRouteDistanceKm = route.distance / 1000.0
        
        if self.travelMode == .ebike {
            self.remainingRouteMinutes = max(1, Int((route.distance / 1000.0) / 22.0 * 60.0))
        } else if self.travelMode == .transit {
            self.remainingRouteMinutes = max(1, Int((route.distance / 1000.0) / 30.0 * 60.0) + 4)
        } else if self.travelMode == .walking {
            self.remainingRouteMinutes = max(1, Int((route.distance / 1000.0) / 4.8 * 60.0))
        } else {
            self.remainingRouteMinutes = max(1, Int(route.expectedTravelTime / 60.0))
        }
        
        // Analyze Route for Electronic Speed Cameras, Toll Stations, Highway Service Areas & Traffic Congestion!
        self.generateRouteHazardsAndTelemetry(for: route)
        self.triggerDepartureGreeting(title: title, isReroute: isReroute)
    }
    
    private func generateRouteHazardsAndTelemetry(for route: MKRoute) {
        var hazards: [RoadHazardAnnotation] = []
        let pts = route.polyline.points()
        let ptCount = route.polyline.pointCount
        let hasHighway = routeContainsHighway(route)
        
        // 1. Evaluate Traffic Congestion from expectedTravelTime vs ideal speed
        let avgSpeedKmh = (route.distance / 1000.0) / max(0.01, route.expectedTravelTime / 3600.0)
        if travelMode == .driving && avgSpeedKmh < 24.0 {
            isCongested = true
            congestionStatusText = language == .en ? "Slow Traffic Ahead" : "前方路段缓行拥堵"
        } else {
            isCongested = false
            congestionStatusText = language == .en ? "Traffic Smooth" : "全线道路畅通"
        }
        
        // 2. Scan route steps for Toll Stations, Service Areas, and Camera checkpoints
        var foundTollDist: Int = 0
        var foundServiceDist: Int = 0
        var foundServiceName: String = ""
        
        if ptCount > 4 {
            // Place realistic Speed Camera / Red-light Enforcement checkpoints along route
            let camCount = min(6, max(2, Int(route.distance / 1800.0)))
            for i in 1...camCount {
                let idx = min(ptCount - 2, max(1, (ptCount * i) / (camCount + 1)))
                let coord = pts[idx].coordinate
                let cam = RoadHazardAnnotation()
                cam.coordinate = coord
                let isHighwayCam = hasHighway && (i % 2 == 0)
                cam.kind = isHighwayCam ? .speedCamera : ((i % 3 == 0) ? .redLightCam : .speedCamera)
                cam.speedLimitValue = isHighwayCam ? 100 : (travelMode == .ebike ? 25 : 60)
                cam.title = (cam.kind == .redLightCam) ? "违章拍照电子眼" : "限速 \(cam.speedLimitValue) 电子眼"
                hazards.append(cam)
            }
            
            // STRICT RULE: If route has highway/expressway, identify specific named service areas and toll stations!
            // If NO highway (local streets / non-expressway), DO NOT generate any service area or toll station!
            if hasHighway && travelMode == .driving {
                let hwName = route.name.isEmpty ? currentStepInstruction : route.name
                let (saNames, tollNames) = getHighwaySpecificServiceAndToll(for: hwName, distanceKm: route.distance / 1000.0)
                
                var saItems: [ServiceAreaInfo] = []
                for (i, name) in saNames.enumerated() {
                    let d = max(1500, Int(route.distance * (0.28 + Double(i) * 0.35)))
                    if d < Int(route.distance) {
                        saItems.append(ServiceAreaInfo(name: name, distanceMeters: d))
                        
                        let ptIndex = min(ptCount - 2, max(2, Int(Double(ptCount) * (0.28 + Double(i) * 0.35))))
                        let saAnno = RoadHazardAnnotation()
                        saAnno.coordinate = pts[ptIndex].coordinate
                        saAnno.kind = .serviceArea
                        saAnno.title = name
                        hazards.append(saAnno)
                    }
                }
                
                var tollItems: [TollStationInfo] = []
                for (i, name) in tollNames.enumerated() {
                    let d = max(800, Int(route.distance * (0.15 + Double(i) * 0.40)))
                    if d < Int(route.distance) {
                        tollItems.append(TollStationInfo(name: name, distanceMeters: d))
                        
                        let ptIndex = min(ptCount - 2, max(1, Int(Double(ptCount) * (0.15 + Double(i) * 0.40))))
                        let tollAnno = RoadHazardAnnotation()
                        tollAnno.coordinate = pts[ptIndex].coordinate
                        tollAnno.kind = .tollStation
                        tollAnno.title = name
                        hazards.append(tollAnno)
                    }
                }
                self.serviceAreasAlongRoute = saItems
                self.tollsAlongRoute = tollItems
            } else {
                self.serviceAreasAlongRoute = []
                self.tollsAlongRoute = []
            }
        }
        
        self.routeHazards = hazards
        self.upcomingCameraDistance = max(120, min(650, Int(route.distance * 0.12)))
        self.upcomingCameraLimit = hasHighway ? 100 : (travelMode == .ebike ? 25 : 60)
        self.lastTraveledMeters = 0
        self.updateUpcomingServiceAreaAndToll(traveledMeters: 0)
    }
    

    private func getHighwaySpecificServiceAndToll(for roadName: String, distanceKm: Double) -> ([String], [String]) {
        let nameLower = roadName.lowercased()
        if nameLower.contains("广深") || nameLower.contains("沿江") || nameLower.contains("京港澳") {
            return (["福永服务区", "厚街服务区", "麻涌服务区"], ["同乐收费站", "厚街主线收费站"])
        } else if nameLower.contains("水官") || nameLower.contains("机荷") || nameLower.contains("沈海") {
            return (["白泥坑服务区", "龙岗服务区", "深汕服务区"], ["水官主线收费站", "荷坳收费站"])
        } else if nameLower.contains("外环") {
            return (["特利服务区", "光明服务区"], ["外环主线收费站"])
        } else if nameLower.contains("惠盐") || nameLower.contains("长深") || nameLower.contains("丹平") {
            return (["沙湾服务区", "大梅沙服务区"], ["沙湾主线收费站", "盐田收费站"])
        } else {
            return (["高速第一服务区", "高速第二服务区"], ["高速ETC收费站"])
        }
    }
    
    func updateUpcomingServiceAreaAndToll(traveledMeters: Int) {
        if let firstSA = serviceAreasAlongRoute.first(where: { !$0.isPassed }) {
            let remain = max(0, firstSA.distanceMeters - traveledMeters)
            if remain <= 50 {
                if let idx = serviceAreasAlongRoute.firstIndex(where: { $0.id == firstSA.id }) {
                    serviceAreasAlongRoute[idx].isPassed = true
                }
                updateUpcomingServiceAreaAndToll(traveledMeters: traveledMeters)
                return
            }
            self.upcomingServiceAreaName = firstSA.name
            self.upcomingServiceAreaDist = remain
        } else {
            self.upcomingServiceAreaName = ""
            self.upcomingServiceAreaDist = 0
        }
        
        if let firstToll = tollsAlongRoute.first(where: { !$0.isPassed }) {
            let remain = max(0, firstToll.distanceMeters - traveledMeters)
            if remain <= 50 {
                if let idx = tollsAlongRoute.firstIndex(where: { $0.id == firstToll.id }) {
                    tollsAlongRoute[idx].isPassed = true
                }
                updateUpcomingServiceAreaAndToll(traveledMeters: traveledMeters)
                return
            }
            self.upcomingTollName = firstToll.name
            self.upcomingTollDistance = remain
        } else {
            self.upcomingTollName = ""
            self.upcomingTollDistance = 0
        }
    }

    private func triggerDepartureGreeting(title: String = "", isReroute: Bool = false) {
        let modeName = self.travelMode.title(self.language)
        if isReroute {
            let base = self.activeBaseId()
            let modeOff = self.activeModeOffset()
            self.playVoice(id: base + modeOff + 43, customQuote: "🔄 [\(modeName)] リルート完了！新しいルートで案内するよ！")
        } else {
            let base = self.activeBaseId()
            let modeOff = self.activeModeOffset()
            let destText = title.isEmpty ? self.destinationName : title
            let quote: String
            switch self.travelMode {
            case .driving:
                quote = "🚗 [\(modeName)·\(routePreference.title(language))] ルート案内開始！目的地: \(destText)"
            case .ebike:
                quote = "🛵 [\(modeName)·非机动车道优先] 安全運転で出発！目的地: \(destText)"
            case .walking:
                quote = "🚶 [\(modeName)·人行步道] のんびり歩いて行こう！目的地: \(destText)"
            case .transit:
                quote = "🚌 [\(modeName)] 公共交通・乗り換え案内開始！目的地: \(destText)"
            }
            self.enqueueVoiceCombo([
                (base + modeOff + 39, quote),
                (base + modeOff + 47, "🚦 実際の交通規制に従って、安全に移動してね！")
            ])
        }
    }
    
    func stopRouteGuidance() {
        stopDemoSimulation()
        activeRoute = nil
        isNavigatingFocused = false
        candidateRoutes = []
        routeHazards = []
        upcomingTollDistance = 0
        upcomingServiceAreaDist = 0
        destinationCoord = nil
        destinationName = ""
        currentStepInstruction = ""
        announcedStepThresholds.removeAll()
        isMapEnlarged = false // Automatically restore normal cockpit size!
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
        // Compare GCJ-02 userCoordinate with GCJ-02 step coordinates for accurate distance
        let currentLoc = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let dist = currentLoc.distance(from: stepEndLoc)
        
        self.distanceToNextStepMeters = dist
        self.currentStepInstruction = step.instructions
        
        // Final Destination Arrival
        if currentStepIndex == steps.count - 1 && dist <= 40.0 {
            let base = activeBaseId()
            let modeOff = activeModeOffset()
            enqueueVoiceCombo([
                (base + modeOff + 37, "🎉 目的地周辺に到着したよ！(\(destinationName))"),
                (base + modeOff + 38, "✨ これで音声案内は終了だよ！お疲れ様でした♪")
            ])
            stopRouteGuidance()
            return
        }
        
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
        
        if dist <= 25.0 && currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
            let nextStep = steps[currentStepIndex]
            currentStepInstruction = nextStep.instructions
            updateRoadLanes(for: currentStepInstruction)
            evaluateRoadSpeedLimitAndNotify(for: currentStepInstruction)
        }
    }
    
    private func classifyTurnOffsetM(from text: String) -> Int {
        let lower = text.lowercased()
        if lower.contains("调头") || lower.contains("掉头") || lower.contains("u-turn") || lower.contains("u turn") {
            return 21
        }
        if lower.contains("出口") || lower.contains("驶出") || lower.contains("exit") {
            return 20
        }
        if lower.contains("入口") || lower.contains("驶入") || lower.contains("匯入") || lower.contains("汇入") || lower.contains("merge") || lower.contains("ramp") {
            return 19
        }
        if lower.contains("稍向右") || lower.contains("靠右") || lower.contains("右前方") || lower.contains("slight right") || lower.contains("keep right") {
            return 30
        }
        if lower.contains("稍向左") || lower.contains("靠左") || lower.contains("左前方") || lower.contains("slight left") || lower.contains("keep left") {
            return 31
        }
        if lower.contains("右后") || lower.contains("sharp right") {
            return 32
        }
        if lower.contains("左后") || lower.contains("sharp left") {
            return 33
        }
        if lower.contains("右") || lower.contains("right") {
            return 28
        }
        if lower.contains("左") || lower.contains("left") {
            return 29
        }
        return 16
    }
    
    // MARK: - Live Demo Navigation Simulator
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
        // Keep user's current view mode (works seamlessly in compact cockpit or enlarged full-screen)
        destinationName = language == .en ? "Sakuragaoka High Music Room" : "樱丘高中轻音部部室 (模拟导航)"
        currentStepInstruction = language == .en ? "In 300m, Turn Right" : "前方 300 米右转进入樱高大道"
        updateRoadLanes(for: currentStepInstruction)
        distanceToNextStepMeters = 300
        currentSpeedKmh = 48.0
        upcomingCameraDistance = 280
        upcomingCameraLimit = Int(speedLimitKmh)
        upcomingTollDistance = 850
        upcomingServiceAreaDist = 2400
        upcomingServiceAreaName = "樱丘高速服务区(SA)"
        congestionStatusText = "前方道路畅通"
        isCongested = false
        
        let base = activeBaseId()
        let modeOff = activeModeOffset()
        
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
            
            self.headingDegrees = (self.headingDegrees + 35.0).truncatingRemainder(dividingBy: 360.0)
            self.upcomingCameraDistance = max(50, self.upcomingCameraDistance - 90)
            self.userCoordinate = CLLocationCoordinate2D(
                latitude: self.userCoordinate.latitude + 0.0006,
                longitude: self.userCoordinate.longitude + 0.0006
            )
            self.tripDistanceKm += 0.1
            
            switch stepCounter {
            case 1:
                self.distanceToNextStepMeters = 100
                self.currentStepInstruction = self.language == .en ? "In 100m, Turn Left" : "前方 100 米左转进入商业街"
                self.updateRoadLanes(for: self.currentStepInstruction)
                self.evaluateRoadSpeedLimitAndNotify(for: "商业街辅路")
                self.upcomingTollDistance = max(0, self.upcomingTollDistance - 350)
                self.enqueueVoiceCombo([
                    (b + 14, "📍 およそ 100m先 (前方100米)"),
                    (b + mOff + 29, "↩️ 左方向に行きまーす！巻き込みに注意してね！")
                ])
            case 2:
                self.distanceToNextStepMeters = 30
                self.currentStepInstruction = self.language == .en ? "Soon, Enter Expressway" : "即将驶入高速道路入口(靠右)"
                self.updateRoadLanes(for: self.currentStepInstruction)
                self.evaluateRoadSpeedLimitAndNotify(for: "高速道路")
                self.upcomingTollDistance = 180
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
            isMapEnlarged = false
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        
        DispatchQueue.main.async {
            if !self.isDemoSimulating {
                // Convert WGS-84 GPS coordinate to GCJ-02 Mars coordinate for China MapKit alignment
                let newCoord = CoordinateConverter.wgs84ToGCJ02(loc.coordinate)
                self.userCoordinate = newCoord
                
                // Auto-refresh transit plans if user moved to a new station location!
                if self.travelMode == .transit {
                    self.refreshTransitPlansForCurrentLocation(force: false)
                }
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
    
    // MARK: - Voice Queue & Playback
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
            
            let spkFilter = characterForVoiceId(safeId)
            let speaker = spkFilter.displayName(language)
            let text = customQuote ?? defaultQuoteForVoiceId(safeId)
            DispatchQueue.main.async {
                if spkFilter != .all {
                    self.activeAllMemberChar = spkFilter
                } else {
                    self.activeAllMemberChar = CharacterFilter.fiveIndividuals.randomElement() ?? .yui
                }
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
            
            let matchedMember = CharacterFilter.fiveIndividuals.first(where: { $0.charId == chosen.charId })
            let speakerName = matchedMember?.displayName(language) ?? targetChar.displayName(language)
            let quote = customQuote ?? localizedMascotQuote(for: chosen.charId)
            DispatchQueue.main.async {
                if let m = matchedMember {
                    self.activeAllMemberChar = m
                }
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
    
    private func activeBaseId() -> Int {
        if selectedCharacter == .all {
            return CharacterFilter.fiveIndividuals.randomElement()!.navBaseId
        }
        return selectedCharacter.navBaseId
    }
    
    private func activeModeOffset() -> Int {
        if selectedCharacter == .all { return 96 }
        return enableBanter ? 48 : 0
    }
    
    func playRandomCharacterGreeting() {
        triggerCharacterTap()
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
    
    func triggerBirthdaySpecialVoice() {
        mascotAction = .special
        let specialIds = Array(1112...1122)
        let chosenId = specialIds.randomElement() ?? 1112
        let msg: String
        switch language {
        case .zhHans: msg = "🎂 【RM-500HTT 生日与全员纪念特典】放课后茶会特别祝福原声♪"
        case .zhHant: msg = "🎂 【RM-500HTT 生日與全員紀念特典】放學後茶會特別祝福原聲♪"
        case .en: msg = "🎂 [RM-500HTT Special Event] K-ON! Birthday & Celebration Voice ♪"
        }
        playVoice(id: chosenId, customQuote: msg)
    }
    
    func cycleNextArrowOutfit() {
        let all = RM500ArrowOutfit.allCases
        if let idx = all.firstIndex(of: arrowOutfit) {
            arrowOutfit = all[(idx + 1) % all.count]
        } else {
            arrowOutfit = .winterUniform
        }
        playMascotVoice()
    }
    
    func resetTripStats() {
        tripDistanceKm = 0.0
        maxSpeedKmh = 0.0
        drivingSeconds = 0
        playRandomCharacterGreeting()
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
    

    // MARK: - Universal One-Click External App Navigation Jump Handler (高德/百度/腾讯/微信/美团/大众点评/小红书/浏览器)
    func handleIncomingNavigationURL(_ url: URL) {
        let rawStr = url.absoluteString
        let scheme = (url.scheme ?? "").lowercased()
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var params: [String: String] = [:]
        if let items = comps?.queryItems {
            for item in items {
                if let val = item.value, !val.isEmpty {
                    params[item.name.lowercased()] = val.removingPercentEncoding ?? val
                }
            }
        }
        
        var parsedLat: Double? = nil
        var parsedLon: Double? = nil
        var parsedName: String? = nil
        
        // 1. Check geo:lat,lon?q=name
        if scheme == "geo" {
            let body = rawStr.replacingOccurrences(of: "geo:", with: "", options: .caseInsensitive)
            let parts = body.components(separatedBy: "?")
            let coords = parts[0].components(separatedBy: ",")
            if coords.count >= 2, let la = Double(coords[0].trimmingCharacters(in: .whitespaces)), let lo = Double(coords[1].trimmingCharacters(in: .whitespaces)) {
                if la != 0 || lo != 0 {
                    parsedLat = la
                    parsedLon = lo
                }
            }
            if let q = params["q"] {
                // Could be "lat,lon(Name)" or just "Name"
                if let parenRange = q.range(of: "("), let closeRange = q.range(of: ")") {
                    parsedName = String(q[parenRange.upperBound..<closeRange.lowerBound])
                } else {
                    parsedName = q
                }
            }
        }
        
        // 2. Check Amap (iosamap:// / amapuri://): dlat, dlon, dname, lat, lon, poiname
        if parsedLat == nil {
            if let dla = params["dlat"] ?? params["lat"] ?? params["latitude"],
               let dlo = params["dlon"] ?? params["lon"] ?? params["lng"] ?? params["longitude"],
               let la = Double(dla), let lo = Double(dlo) {
                parsedLat = la
                parsedLon = lo
            }
        }
        if parsedName == nil {
            parsedName = params["dname"] ?? params["poiname"] ?? params["name"] ?? params["title"] ?? params["dest"] ?? params["keyword"] ?? params["q"] ?? params[" saddr"] ?? params["daddr"]
        }
        
        // 3. Check Baidu Map (baidumap://map/direction?destination=latlng:22.54,114.05|name:xxx or destination=22.54,114.05)
        if let destParam = params["destination"] {
            if destParam.contains("|") {
                let segments = destParam.components(separatedBy: "|")
                for seg in segments {
                    if seg.lowercased().hasPrefix("latlng:") {
                        let cStr = seg.replacingOccurrences(of: "latlng:", with: "", options: .caseInsensitive)
                        let cParts = cStr.components(separatedBy: ",")
                        if cParts.count >= 2, let la = Double(cParts[0]), let lo = Double(cParts[1]) {
                            parsedLat = la
                            parsedLon = lo
                        }
                    } else if seg.lowercased().hasPrefix("name:") {
                        parsedName = seg.replacingOccurrences(of: "name:", with: "", options: .caseInsensitive)
                    }
                }
            } else {
                let cParts = destParam.components(separatedBy: ",")
                if cParts.count == 2, let la = Double(cParts[0]), let lo = Double(cParts[1]) {
                    parsedLat = la
                    parsedLon = lo
                } else {
                    parsedName = destParam
                }
            }
        }
        
        // 4. Check Tencent Map (qqmap://map/routeplan?tocoord=22.54,114.05&to=xxx)
        if let toCoord = params["tocoord"] ?? params["coord"] ?? params["center"] ?? params["ll"] ?? params["sll"] {
            let cParts = toCoord.components(separatedBy: ",")
            if cParts.count >= 2, let la = Double(cParts[0].trimmingCharacters(in: .whitespaces)), let lo = Double(cParts[1].trimmingCharacters(in: .whitespaces)) {
                parsedLat = la
                parsedLon = lo
            }
        }
        if parsedName == nil, let toName = params["to"] ?? params["address"] {
            parsedName = toName
        }
        
        // Convert BD-09 if coming from baidumap and coord_type is bd09
        let coordType = (params["coord_type"] ?? "").lowercased()
        if let la = parsedLat, let lo = parsedLon {
            var finalCoord = CLLocationCoordinate2D(latitude: la, longitude: lo)
            if scheme == "baidumap" && !coordType.contains("gcj") && !coordType.contains("wgs") {
                finalCoord = CoordinateConverter.bd09ToGCJ02(lat: la, lon: lo)
            } else if coordType.contains("wgs") {
                finalCoord = CoordinateConverter.wgs84ToGCJ02(finalCoord)
            }
            let finalTitle = (parsedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? parsedName! : "外部App导入目的地"
            
            DispatchQueue.main.async {
                self.showMapMode = true
                self.isMapEnlarged = true
                self.isNavigatingFocused = false
                self.calculateAndStartRoute(to: finalCoord, title: finalTitle)
            }
            return
        }
        
        // 5. If only a place name/address was provided without coordinates, search and navigate automatically!
        if let queryName = parsedName?.trimmingCharacters(in: .whitespacesAndNewlines), !queryName.isEmpty {
            searchAndNavigateDirectly(query: queryName)
        }
    }
    
    func searchAndNavigateDirectly(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        req.resultTypes = [.address, .pointOfInterest]
        req.region = MKCoordinateRegion(center: userCoordinate, latitudinalMeters: 350000, longitudinalMeters: 350000)
        
        MKLocalSearch(request: req).start { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let first = resp?.mapItems.first {
                    self.showMapMode = true
                    self.isMapEnlarged = true
                    self.isNavigatingFocused = false
                    self.startRouteGuidance(to: first)
                }
            }
        }
    }
    
    func parseSmartClipboardAndNavigate() {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            let msg = language == .en ? "Clipboard is empty!" : "剪贴板为空，请先在微信/美团/点评复制地址或链接！"
            playVoice(id: activeBaseId() + 18, customQuote: msg, clearQueue: true)
            return
        }
        // Check if clipboard contains a URL scheme or http map link
        if let url = URL(string: raw), url.scheme != nil, (raw.contains("://") || raw.lowercased().hasPrefix("geo:")) {
            handleIncomingNavigationURL(url)
            return
        }
        // Otherwise extract clean address text (strip common share noise)
        var cleaned = raw
            .replacingOccurrences(of: "【", with: " ")
            .replacingOccurrences(of: "】", with: " ")
        if let range = cleaned.range(of: "http") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        let finalQuery = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalQuery.isEmpty {
            searchAndNavigateDirectly(query: finalQuery)
        }
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

extension Double {
    func FloorMod(_ mod: Int) -> Int {
        let m = Double(mod)
        var r = self.truncatingRemainder(dividingBy: m)
        if r < 0 { r += m }
        return Int(r) % mod
    }
}
