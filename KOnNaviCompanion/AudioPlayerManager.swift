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

enum RouteStrategyPreference: String, CaseIterable, Identifiable {
    case highwayFirst = "highwayFirst"
    case avoidHighway = "avoidHighway"
    case shortest = "shortest"
    
    var id: String { self.rawValue }
    
    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.highwayFirst, .zhHans): return "高速优先"
        case (.highwayFirst, .zhHant): return "高速優先"
        case (.highwayFirst, .en): return "Highway First"
        case (.avoidHighway, .zhHans): return "不走高速"
        case (.avoidHighway, .zhHant): return "不走高速"
        case (.avoidHighway, .en): return "No Highway"
        case (.shortest, .zhHans): return "距离最短"
        case (.shortest, .zhHant): return "距離最短"
        case (.shortest, .en): return "Shortest"
        }
    }
    
    var icon: String {
        switch self {
        case .highwayFirst: return "road.lanes"
        case .avoidHighway: return "arrow.triangle.branch"
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
    
    // Built-In Map Navigation State (Enlarged Mode & 4 Travel Modes)
    @Published var showMapMode: Bool = true
    @Published var isMapEnlarged: Bool = false // Auto-enlarges on active navigation!
    @Published var travelMode: NavigationTravelMode = .driving {
        didSet {
            speedLimitKmh = travelMode.defaultSpeedLimit
            if let dest = destinationCoord, !destinationName.isEmpty {
                calculateAndStartRoute(to: dest, title: destinationName, isReroute: true)
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
    @Published var userZoomDistance: Double = 480.0
    @Published var routePreference: RouteStrategyPreference = .highwayFirst {
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
    @Published var congestionStatusText: String = "道路畅通"
    @Published var isCongested: Bool = false
    @Published var recenterTrigger: Int = 0
    
    func toggleCameraMode() {
        cameraMode = (cameraMode == .headingUp) ? .northUp : .headingUp
    }
    
    func zoomMapIn() {
        userZoomDistance = max(140.0, userZoomDistance * 0.65)
        recenterTrigger += 1
    }
    
    func zoomMapOut() {
        userZoomDistance = min(15000.0, userZoomDistance * 1.5)
        recenterTrigger += 1
    }
    
    func handleMapTap(at coord: CLLocationCoordinate2D) {
        let tapLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if #available(iOS 14.0, *) {
            let poiReq = MKLocalPointsOfInterestRequest(center: coord, radius: 42.0)
            poiReq.pointOfInterestFilter = .includingAll
            MKLocalSearch(request: poiReq).start { [weak self] resp, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // Find closest named POI (e.g., 中源大药房, 益友便利店, 沙湾小学) within 42m of tap!
                    let validItems = (resp?.mapItems ?? []).filter { item in
                        guard let name = item.name, !name.isEmpty else { return false }
                        let itemLoc = CLLocation(latitude: item.placemark.coordinate.latitude,
                                                 longitude: item.placemark.coordinate.longitude)
                        return tapLoc.distance(from: itemLoc) <= 42.0
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
                        // Tapped on blank road/ground with no POI -> dismiss card so random clicks don't annoy user!
                        self.tappedMapCoord = nil
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
    
    func openSystemMapsForTransit() {
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
        
        if travelMode == .walking {
            MKDirections(request: reqWalk).calculate { [weak self] resp, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isRecalculatingRoute = false
                    if let routes = resp?.routes, !routes.isEmpty {
                        self.candidateRoutes = routes
                        self.selectedRouteIndex = 0
                        self.applyCalculatedRoute(routes[0], title: title, isReroute: isReroute)
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
                        var sorted = autoRoutes
                        if self.travelMode == .ebike {
                            // e-Bike: strictly prefer non-highway, non-expressway urban surface roads!
                            sorted.sort { a, b in
                                let aHwy = self.routeContainsHighway(a) ? 1 : 0
                                let bHwy = self.routeContainsHighway(b) ? 1 : 0
                                if aHwy != bHwy { return aHwy < bHwy }
                                return a.distance < b.distance
                            }
                        } else {
                            sorted = self.sortRoutes(autoRoutes, by: self.routePreference)
                        }
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
        fbReq.transportType = (travelMode == .walking) ? .walking : .automobile
        fbReq.requestsAlternateRoutes = true
        MKDirections(request: fbReq).calculate { [weak self] fbResp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let routes = fbResp?.routes, !routes.isEmpty {
                    self.candidateRoutes = routes
                    self.selectedRouteIndex = 0
                    self.applyCalculatedRoute(routes[0], title: title, isReroute: isReroute)
                } else {
                    self.triggerDepartureGreeting(title: title, isReroute: isReroute)
                }
            }
        }
    }
    
    private func routeContainsHighway(_ route: MKRoute) -> Bool {
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
        let hasHwy = routeContainsHighway(route)
        if index == 0 {
            return hasHwy ? "方案1·高速快线" : "方案1·推荐路线"
        } else if index == 1 {
            return hasHwy ? "方案2·备选高速" : "方案2·不走高速"
        } else {
            return "方案\(index + 1)·最短路程"
        }
    }
    
    private func applyCalculatedRoute(_ route: MKRoute, title: String, isReroute: Bool) {
        self.activeRoute = route
        self.isMapEnlarged = true
        self.userZoomDistance = (self.travelMode == .walking) ? 350.0 : 480.0
        self.announcedStepThresholds.removeAll()
        self.keepAlivePlayer?.play()
        
        let steps = route.steps
        self.currentStepIndex = steps.count > 1 ? 1 : 0
        if self.currentStepIndex < steps.count {
            let step = steps[self.currentStepIndex]
            self.currentStepInstruction = step.instructions.isEmpty ? title : step.instructions
            self.distanceToNextStepMeters = step.distance
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
            
            // If highway/expressway route or > 5km driving route, mark Toll Station & Service Area
            if hasHighway || (travelMode == .driving && route.distance > 6000) {
                let tollIdx = min(ptCount - 2, max(1, ptCount / 4))
                let toll = RoadHazardAnnotation()
                toll.coordinate = pts[tollIdx].coordinate
                toll.kind = .tollStation
                toll.title = "高速收费站 / ETC通道"
                hazards.append(toll)
                foundTollDist = max(200, Int(route.distance * 0.25))
                
                let saIdx = min(ptCount - 2, max(2, (ptCount * 2) / 3))
                let sa = RoadHazardAnnotation()
                sa.coordinate = pts[saIdx].coordinate
                sa.kind = .serviceArea
                sa.title = "放课后茶会 · 高速服务区(SA)"
                hazards.append(sa)
                foundServiceDist = max(500, Int(route.distance * 0.62))
                foundServiceName = language == .en ? "Highway Service Area" : "前方高速服务区"
            }
        }
        
        self.routeHazards = hazards
        self.upcomingCameraDistance = max(120, min(650, Int(route.distance * 0.12)))
        self.upcomingCameraLimit = hasHighway ? 100 : (travelMode == .ebike ? 25 : 60)
        self.upcomingTollDistance = foundTollDist
        self.upcomingServiceAreaDist = foundServiceDist
        self.upcomingServiceAreaName = foundServiceName
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
            isMapEnlarged = false
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        
        DispatchQueue.main.async {
            if !self.isDemoSimulating {
                // Convert WGS-84 GPS coordinate to GCJ-02 Mars coordinate for China MapKit alignment
                self.userCoordinate = CoordinateConverter.wgs84ToGCJ02(loc.coordinate)
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
