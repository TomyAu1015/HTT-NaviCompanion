import UIKit
import CarPlay
import MapKit
import Combine

// MARK: - CarPlay Dedicated Interactive 3D Map & RM-500HTT HUD ViewController (1:1 Phone Parity)
class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()
    var isUserPanning: Bool = false

    // Top Turn-by-Turn & ETA Banner (Matches Phone HUD)
    private let topNavBanner = UIView()
    private let turnIconView = UIImageView()
    private let turnDistLabel = UILabel()
    private let turnInstrLabel = UILabel()
    private let etaSummaryLabel = UILabel()

    // Bottom HUD (Speedometer + Cream Bubble + Mascot)
    private let speedBadge = UIView()
    private let speedLabel = UILabel()
    private let unitLabel = UILabel()
    private let limitLabel = UILabel()
    private let speedLimitSignView = UIView()
    private let speedLimitSignLabel = UILabel()
    private var autoRecenterWorkItem: DispatchWorkItem? = nil
    private var lastCameraFollowTime: CFTimeInterval = 0
    private let bubbleView = UIView()
    private let speakerLabel = UILabel()
    private let quoteLabel = UILabel()
    private let mascotImageView = UIImageView()

    private var cancellables = Set<AnyCancellable>()
    private var lastSplitUpdateCoord: CLLocationCoordinate2D? = nil
    private var destAnnotation: MKPointAnnotation? = nil
    private static let etaDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapView()
        setupCarPlayHUDOverlay()
        bindToManager()
    }

    private func setupMapView() {
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        // 彻底修复 CarPlay 粉色/橙色/绿色 POI 贴图方块：禁用异常的 CarPlay POI 图集并关闭自带路况块
        mapView.overrideUserInterfaceStyle = .light
        mapView.showsTraffic = false
        mapView.showsBuildings = true
        mapView.pointOfInterestFilter = .excludingAll
        if #available(iOS 16.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .realistic)
            config.showsTraffic = false
            config.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = config
        }
        view.addSubview(mapView)

        let region = MKCoordinateRegion(
            center: AudioPlayerManager.shared.userCoordinate,
            latitudinalMeters: 520,
            longitudinalMeters: 520
        )
        mapView.setRegion(region, animated: false)
    }

    private func setupCarPlayHUDOverlay() {
        // 0. Top Turn-by-Turn + ETA Banner (Visible during active navigation)
        topNavBanner.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 0.92)
        topNavBanner.layer.cornerRadius = 12
        topNavBanner.layer.borderWidth = 1.5
        topNavBanner.layer.borderColor = UIColor(red: 0.88, green: 0.68, blue: 0.24, alpha: 0.95).cgColor
        topNavBanner.translatesAutoresizingMaskIntoConstraints = false
        topNavBanner.isHidden = true
        view.addSubview(topNavBanner)

        turnIconView.image = UIImage(systemName: "arrow.up.circle.fill")
        turnIconView.tintColor = UIColor(red: 0.30, green: 0.92, blue: 0.55, alpha: 1.0)
        turnIconView.contentMode = .scaleAspectFit
        turnIconView.translatesAutoresizingMaskIntoConstraints = false
        topNavBanner.addSubview(turnIconView)

        turnDistLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .black)
        turnDistLabel.textColor = UIColor(red: 0.30, green: 0.92, blue: 0.55, alpha: 1.0)
        turnDistLabel.text = "0 m"
        turnDistLabel.translatesAutoresizingMaskIntoConstraints = false
        topNavBanner.addSubview(turnDistLabel)

        turnInstrLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        turnInstrLabel.textColor = .white
        turnInstrLabel.numberOfLines = 1
        turnInstrLabel.lineBreakMode = .byTruncatingTail
        turnInstrLabel.text = "沿规划路线行驶"
        turnInstrLabel.translatesAutoresizingMaskIntoConstraints = false
        topNavBanner.addSubview(turnInstrLabel)

        etaSummaryLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        etaSummaryLabel.textColor = UIColor(red: 0.88, green: 0.72, blue: 0.32, alpha: 1.0)
        etaSummaryLabel.text = ""
        etaSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        topNavBanner.addSubview(etaSummaryLabel)

        // 1. Speedometer Badge (Bottom Left)
        speedBadge.backgroundColor = UIColor.black.withAlphaComponent(0.84)
        speedBadge.layer.cornerRadius = 12
        speedBadge.layer.borderWidth = 2
        speedBadge.layer.borderColor = UIColor(red: 0.88, green: 0.68, blue: 0.24, alpha: 1.0).cgColor
        speedBadge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(speedBadge)

        speedLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .black)
        speedLabel.textColor = UIColor(red: 0.35, green: 0.98, blue: 0.65, alpha: 1.0)
        speedLabel.text = "0"
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedBadge.addSubview(speedLabel)

        unitLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        unitLabel.textColor = .white
        unitLabel.text = "km/h"
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        speedBadge.addSubview(unitLabel)

        limitLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        limitLabel.textColor = UIColor(red: 0.88, green: 0.68, blue: 0.24, alpha: 1.0)
        limitLabel.text = "限速 80"
        limitLabel.translatesAutoresizingMaskIntoConstraints = false
        speedBadge.addSubview(limitLabel)

        // 1.5 GaoDe-style Circular Road Speed Limit Sign (Red Ring + White Center)
        speedLimitSignView.backgroundColor = .white
        speedLimitSignView.layer.cornerRadius = 26
        speedLimitSignView.layer.borderWidth = 4.5
        speedLimitSignView.layer.borderColor = UIColor(red: 0.90, green: 0.14, blue: 0.14, alpha: 1.0).cgColor
        speedLimitSignView.layer.shadowColor = UIColor.black.cgColor
        speedLimitSignView.layer.shadowOpacity = 0.35
        speedLimitSignView.layer.shadowRadius = 4
        speedLimitSignView.layer.shadowOffset = CGSize(width: 0, height: 2)
        speedLimitSignView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(speedLimitSignView)

        speedLimitSignLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .black)
        speedLimitSignLabel.textColor = .black
        speedLimitSignLabel.textAlignment = .center
        speedLimitSignLabel.text = "80"
        speedLimitSignLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLimitSignView.addSubview(speedLimitSignLabel)

        // 2. Voice Bubble & Mascot (Bottom Center/Right)
        bubbleView.backgroundColor = UIColor(red: 0.99, green: 0.96, blue: 0.90, alpha: 0.95)
        bubbleView.layer.cornerRadius = 10
        bubbleView.layer.borderWidth = 1.5
        bubbleView.layer.borderColor = UIColor(red: 0.78, green: 0.18, blue: 0.22, alpha: 1.0).cgColor
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bubbleView)

        speakerLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        speakerLabel.textColor = UIColor(red: 0.78, green: 0.18, blue: 0.22, alpha: 1.0)
        speakerLabel.text = "放课后茶会 (HTT)"
        speakerLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(speakerLabel)

        quoteLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        quoteLabel.textColor = .black
        quoteLabel.numberOfLines = 2
        quoteLabel.text = "準備OK！出発進行～！"
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(quoteLabel)

        mascotImageView.contentMode = .scaleAspectFit
        mascotImageView.layer.magnificationFilter = .nearest
        mascotImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mascotImageView)

        NSLayoutConstraint.activate([
            topNavBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topNavBanner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            topNavBanner.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            topNavBanner.heightAnchor.constraint(equalToConstant: 56),

            turnIconView.leadingAnchor.constraint(equalTo: topNavBanner.leadingAnchor, constant: 10),
            turnIconView.centerYAnchor.constraint(equalTo: topNavBanner.centerYAnchor),
            turnIconView.widthAnchor.constraint(equalToConstant: 32),
            turnIconView.heightAnchor.constraint(equalToConstant: 32),

            turnDistLabel.topAnchor.constraint(equalTo: topNavBanner.topAnchor, constant: 7),
            turnDistLabel.leadingAnchor.constraint(equalTo: turnIconView.trailingAnchor, constant: 8),

            turnInstrLabel.centerYAnchor.constraint(equalTo: turnDistLabel.centerYAnchor),
            turnInstrLabel.leadingAnchor.constraint(equalTo: turnDistLabel.trailingAnchor, constant: 8),
            turnInstrLabel.trailingAnchor.constraint(equalTo: topNavBanner.trailingAnchor, constant: -12),

            etaSummaryLabel.bottomAnchor.constraint(equalTo: topNavBanner.bottomAnchor, constant: -7),
            etaSummaryLabel.leadingAnchor.constraint(equalTo: turnIconView.trailingAnchor, constant: 8),
            etaSummaryLabel.trailingAnchor.constraint(equalTo: topNavBanner.trailingAnchor, constant: -12),

            speedBadge.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            speedBadge.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            speedBadge.widthAnchor.constraint(equalToConstant: 90),
            speedBadge.heightAnchor.constraint(equalToConstant: 64),

            speedLabel.topAnchor.constraint(equalTo: speedBadge.topAnchor, constant: 4),
            speedLabel.leadingAnchor.constraint(equalTo: speedBadge.leadingAnchor, constant: 10),

            unitLabel.bottomAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: -5),
            unitLabel.leadingAnchor.constraint(equalTo: speedLabel.trailingAnchor, constant: 3),

            limitLabel.bottomAnchor.constraint(equalTo: speedBadge.bottomAnchor, constant: -5),
            limitLabel.leadingAnchor.constraint(equalTo: speedBadge.leadingAnchor, constant: 10),

            speedLimitSignView.leadingAnchor.constraint(equalTo: speedBadge.trailingAnchor, constant: 8),
            speedLimitSignView.centerYAnchor.constraint(equalTo: speedBadge.centerYAnchor),
            speedLimitSignView.widthAnchor.constraint(equalToConstant: 52),
            speedLimitSignView.heightAnchor.constraint(equalToConstant: 52),

            speedLimitSignLabel.centerXAnchor.constraint(equalTo: speedLimitSignView.centerXAnchor),
            speedLimitSignLabel.centerYAnchor.constraint(equalTo: speedLimitSignView.centerYAnchor),

            bubbleView.leadingAnchor.constraint(equalTo: speedLimitSignView.trailingAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: speedBadge.bottomAnchor),
            bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: mascotImageView.leadingAnchor, constant: -8),
            bubbleView.heightAnchor.constraint(equalToConstant: 54),

            speakerLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 5),
            speakerLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            speakerLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),

            quoteLabel.topAnchor.constraint(equalTo: speakerLabel.bottomAnchor, constant: 2),
            quoteLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            quoteLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),

            mascotImageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            mascotImageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            mascotImageView.widthAnchor.constraint(equalToConstant: 64),
            mascotImageView.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func bindToManager() {
        let mgr = AudioPlayerManager.shared

        mgr.$currentSpeedKmh
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spd in
                self?.speedLabel.text = "\(Int(spd))"
                self?.speedLabel.textColor = mgr.isOverspeeding
                    ? .systemRed
                    : UIColor(red: 0.35, green: 0.98, blue: 0.65, alpha: 1.0)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(mgr.$speedLimitKmh, mgr.$isOverspeeding)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lim, over in
                guard let self = self else { return }
                let v = Int(lim)
                if v > 0 {
                    self.limitLabel.text = "限速 \(v)"
                    self.speedLimitSignView.isHidden = false
                    self.speedLimitSignLabel.text = "\(v)"
                    self.speedLimitSignView.backgroundColor = over ? UIColor(red: 1.0, green: 0.90, blue: 0.90, alpha: 1.0) : .white
                    self.speedLimitSignLabel.textColor = over ? UIColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1.0) : .black
                } else {
                    self.limitLabel.text = "无限速"
                    self.speedLimitSignView.isHidden = true
                }
            }
            .store(in: &cancellables)

        mgr.$routeHazards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hazards in
                guard let self = self else { return }
                let existing = self.mapView.annotations.filter { $0 is RoadHazardAnnotation }
                self.mapView.removeAnnotations(existing)
                self.mapView.addAnnotations(hazards)
            }
            .store(in: &cancellables)

        mgr.$currentSpeechBubble
            .receive(on: DispatchQueue.main)
            .sink { [weak self] txt in
                self?.quoteLabel.text = txt
                self?.speakerLabel.text = mgr.selectedCharacter.roleTag(mgr.language)
            }
            .store(in: &cancellables)

        mgr.$currentSpriteFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] img in
                self?.mascotImageView.image = img
                if let mapView = self?.mapView, let userView = mapView.view(for: mapView.userLocation) {
                    userView.image = mgr.getRM500NavigationArrowFrame(mapCameraHeading: self?.mapView.camera.heading ?? 0)
                        ?? CarPlayMapViewController.createNavigationArrowImage()
                }
            }
            .store(in: &cancellables)

        // Update Top Turn-by-Turn + ETA Banner
        Publishers.CombineLatest4(mgr.$activeRoute, mgr.$currentStepInstruction, mgr.$distanceToNextStepMeters, mgr.$remainingRouteMinutes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route, instr, distM, remMins in
                guard let self = self else { return }
                if route == nil {
                    self.topNavBanner.isHidden = true
                } else {
                    self.topNavBanner.isHidden = false
                    self.turnDistLabel.text = distM >= 1000 ? String(format: "%.1f km", distM / 1000.0) : "\(Int(distM)) m"
                    self.turnInstrLabel.text = instr.isEmpty ? "沿规划路线行驶" : instr
                    let etaTime = CarPlayMapViewController.etaDateFormatter.string(from: Date().addingTimeInterval(Double(max(1, remMins)) * 60.0))
                    let remKmStr = String(format: "%.1f km", mgr.remainingRouteDistanceKm)
                    self.etaSummaryLabel.text = "\(mgr.destinationName) · 余 \(remKmStr) · \(max(1, remMins))分钟 · 预计 \(etaTime) 到达"

                    let iconName: String
                    if instr.contains("收费站") {
                        iconName = "parkingsign.circle.fill"
                    } else if instr.contains("到达") || instr.contains("目的地") {
                        iconName = "flag.checkered.circle.fill"
                    } else if instr.contains("调头") || instr.contains("掉头") {
                        iconName = "arrow.uturn.left"
                    } else if instr.contains("环岛") {
                        iconName = "arrow.triangle.2.circlepath"
                    } else if instr.contains("左前方") || instr.contains("靠左") {
                        iconName = "arrow.up.left"
                    } else if instr.contains("右前方") || instr.contains("靠右") || instr.contains("出口") || instr.contains("匝道") {
                        iconName = "arrow.up.right"
                    } else if instr.contains("左") && !instr.contains("右") {
                        iconName = "arrow.turn.up.left"
                    } else if instr.contains("右") && !instr.contains("左") {
                        iconName = "arrow.turn.up.right"
                    } else {
                        iconName = "arrow.up"
                    }
                    self.turnIconView.image = UIImage(systemName: iconName)
                }
            }
            .store(in: &cancellables)

        mgr.$userCoordinate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                guard let self = self else { return }
                if !self.isUserPanning {
                    let dynDist = mgr.hasActiveNavigation ? mgr.recommendedNavigationZoomDistance() : (mgr.travelMode == .walking ? 340.0 : 520.0)
                    let nowTime = CACurrentMediaTime()
                    let curDist = self.mapView.camera.centerCoordinateDistance
                    let camLoc = CLLocation(latitude: self.mapView.camera.centerCoordinate.latitude, longitude: self.mapView.camera.centerCoordinate.longitude)
                    let usrLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let movedMeters = camLoc.distance(from: usrLoc)
                    var hDiff = abs(self.mapView.camera.heading - mgr.headingDegrees).truncatingRemainder(dividingBy: 360.0)
                    if hDiff > 180.0 { hDiff = 360.0 - hDiff }
                    if (movedMeters > 2.2 || hDiff > 3.5 || abs(curDist - dynDist) > 40.0) && (nowTime - self.lastCameraFollowTime >= 0.45) {
                        self.lastCameraFollowTime = nowTime
                        let cam = MKMapCamera(
                            lookingAtCenter: coord,
                            fromDistance: dynDist,
                            pitch: 45,
                            heading: mgr.headingDegrees
                        )
                        UIView.animate(
                            withDuration: 0.42,
                            delay: 0,
                            options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]
                        ) {
                            self.mapView.camera = cam
                        }
                    }
                }
                if let route = mgr.activeRoute {
                    let prev = self.lastSplitUpdateCoord
                    let moved = prev == nil || CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        .distance(from: CLLocation(latitude: prev!.latitude, longitude: prev!.longitude)) >= 12.0
                    if moved {
                        self.lastSplitUpdateCoord = coord
                        self.renderSplitRouteOverlays(route: route, userCoord: coord)
                    }
                }
            }
            .store(in: &cancellables)

        mgr.$activeRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                guard let self = self else { return }
                self.lastSplitUpdateCoord = nil
                if let oldPin = self.destAnnotation {
                    self.mapView.removeAnnotation(oldPin)
                    self.destAnnotation = nil
                }
                if let route = route {
                    self.renderSplitRouteOverlays(route: route, userCoord: mgr.userCoordinate)
                    let pts = route.polyline.points()
                    if route.polyline.pointCount > 0 {
                        let endCoord = pts[route.polyline.pointCount - 1].coordinate
                        let pin = MKPointAnnotation()
                        pin.coordinate = endCoord
                        pin.title = mgr.destinationName.isEmpty ? "目的地" : mgr.destinationName
                        self.destAnnotation = pin
                        self.mapView.addAnnotation(pin)
                    }
                } else {
                    self.mapView.removeOverlays(self.mapView.overlays)
                }
            }
            .store(in: &cancellables)
    }

    // Split active route polyline into Traveled (Green) + Remaining (Blue) matching Phone 1:1
    private func renderSplitRouteOverlays(route: MKRoute, userCoord: CLLocationCoordinate2D) {
        let poly = route.polyline
        let count = poly.pointCount
        guard count >= 2 else { return }

        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: count))

        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        var closestIdx = 0
        var minDist = Double.greatestFiniteMagnitude
        for i in 0..<count {
            let d = userLoc.distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
            if d < minDist {
                minDist = d
                closestIdx = i
            }
        }

        mapView.removeOverlays(mapView.overlays)

        let mgr = AudioPlayerManager.shared
        if closestIdx >= 1 && minDist < 120.0 {
            var traveledCoords = Array(coords[0...closestIdx])
            let traveledPoly = MKPolyline(coordinates: &traveledCoords, count: traveledCoords.count)
            traveledPoly.title = "TRAVELED_GRAY"
            mapView.addOverlay(traveledPoly, level: .aboveRoads)
        }

        let remStart = (minDist < 120.0) ? closestIdx : 0
        let remCount = count - remStart
        if mgr.travelMode == .driving && remCount > 8 {
            let slowNow = mgr.isCongested || (mgr.hasActiveNavigation && mgr.currentSpeedKmh > 3 && mgr.speedLimitKmh > 0 && mgr.currentSpeedKmh < mgr.speedLimitKmh * 0.45)
            let cut1 = remStart + max(2, Int(Double(remCount) * 0.45))
            let cut2 = remStart + max(cut1 - remStart + 2, Int(Double(remCount) * 0.72))

            var c1 = Array(coords[remStart...cut1])
            let p1 = MKPolyline(coordinates: &c1, count: c1.count)
            p1.title = slowNow ? "TRAFFIC_RED" : "TRAFFIC_GREEN"
            mapView.addOverlay(p1, level: .aboveRoads)

            var c2 = Array(coords[cut1...cut2])
            let p2 = MKPolyline(coordinates: &c2, count: c2.count)
            p2.title = mgr.isCongested ? "TRAFFIC_RED" : "TRAFFIC_YELLOW"
            mapView.addOverlay(p2, level: .aboveRoads)

            var c3 = Array(coords[cut2..<count])
            let p3 = MKPolyline(coordinates: &c3, count: c3.count)
            p3.title = "TRAFFIC_GREEN"
            mapView.addOverlay(p3, level: .aboveRoads)
        } else if remStart < count - 1 {
            var remCoords = Array(coords[remStart..<count])
            let remPoly = MKPolyline(coordinates: &remCoords, count: remCoords.count)
            switch mgr.travelMode {
            case .walking: remPoly.title = "WALKING_BLUE"
            case .ebike: remPoly.title = "EBIKE_CYAN_BLUE"
            default: remPoly.title = mgr.isCongested ? "TRAFFIC_RED" : "TRAFFIC_GREEN"
            }
            mapView.addOverlay(remPoly, level: .aboveRoads)
        }
    }

    private func scheduleAutoRecenter() {
        autoRecenterWorkItem?.cancel()
        guard AudioPlayerManager.shared.hasActiveNavigation && AudioPlayerManager.shared.autoRecenterEnabled else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.recenterImmediate()
        }
        autoRecenterWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: item)
    }

    func panMap(direction: CPMapTemplate.PanDirection) {
        isUserPanning = true
        scheduleAutoRecenter()
        let span = mapView.region.span
        var center = mapView.centerCoordinate
        let stepLat = span.latitudeDelta * 0.25
        let stepLon = span.longitudeDelta * 0.25
        var sx: Double = 0
        var sy: Double = 0
        if direction.contains(.up) { sy += 1 }
        if direction.contains(.down) { sy -= 1 }
        if direction.contains(.right) { sx += 1 }
        if direction.contains(.left) { sx -= 1 }
        let rad = mapView.camera.heading * .pi / 180.0
        let dLat = (sy * cos(rad) - sx * sin(rad)) * stepLat
        let dLon = (sy * sin(rad) + sx * cos(rad)) * stepLon
        center.latitude = max(-85.0, min(85.0, center.latitude + dLat))
        center.longitude = max(-180.0, min(180.0, center.longitude + dLon))
        mapView.setCenter(center, animated: true)
    }

    func zoomMap(scale: Double) {
        isUserPanning = true
        scheduleAutoRecenter()
        var cam = mapView.camera
        cam.centerCoordinateDistance = max(120, min(15000, cam.centerCoordinateDistance * scale))
        mapView.setCamera(cam, animated: true)
    }

    func recenterImmediate() {
        autoRecenterWorkItem?.cancel()
        isUserPanning = false
        let mgr = AudioPlayerManager.shared
        let coord = mapView.userLocation.location?.coordinate ?? mgr.userCoordinate
        let cam = MKMapCamera(
            lookingAtCenter: coord,
            fromDistance: mgr.hasActiveNavigation ? mgr.recommendedNavigationZoomDistance() : (mgr.travelMode == .walking ? 340.0 : 520.0),
            pitch: 45,
            heading: mgr.headingDegrees
        )
        mapView.setCamera(cam, animated: false)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            let id = "CarPlayUserArrow"
            var v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            if v == nil {
                v = MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                v?.canShowCallout = false
            }
            v?.image = AudioPlayerManager.shared.getRM500NavigationArrowFrame(mapCameraHeading: mapView.camera.heading)
                ?? CarPlayMapViewController.createNavigationArrowImage()
            v?.centerOffset = CGPoint(x: 0, y: -18)
            return v
        }
        if let hazard = annotation as? RoadHazardAnnotation {
            let id = "CarPlayHazard_\(hazard.kind.rawValue)"
            var hv = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
            if hv == nil {
                hv = MKMarkerAnnotationView(annotation: hazard, reuseIdentifier: id)
                hv?.canShowCallout = true
            } else {
                hv?.annotation = hazard
            }
            switch hazard.kind {
            case .speedCamera:
                hv?.markerTintColor = .systemRed
                hv?.glyphText = "\(hazard.speedLimitValue)"
            case .redLightCam:
                hv?.markerTintColor = .systemPink
                hv?.glyphImage = UIImage(systemName: "camera.fill")
            case .violationCam:
                hv?.markerTintColor = .systemPurple
                hv?.glyphImage = UIImage(systemName: "video.badge.checkmark") ?? UIImage(systemName: "camera.fill")
            case .trafficRuleWarn:
                hv?.markerTintColor = .systemIndigo
                hv?.glyphImage = UIImage(systemName: "exclamationmark.shield.fill")
            case .tollStation:
                hv?.markerTintColor = .systemOrange
                hv?.glyphText = "¥"
            case .serviceArea:
                hv?.markerTintColor = .systemBlue
                hv?.glyphImage = UIImage(systemName: "cup.and.saucer.fill")
            case .congestion:
                hv?.markerTintColor = .systemYellow
                hv?.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
            case .trafficLight:
                hv?.markerTintColor = .systemGreen
                hv?.glyphImage = UIImage(systemName: "light.beacon.max.fill") ?? UIImage(systemName: "circle.fill")
            }
            return hv
        }
        return nil
    }

    static func createNavigationArrowImage() -> UIImage {
        let size = CGSize(width: 46, height: 46)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 3), blur: 5, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 23, y: 3))
            path.addLine(to: CGPoint(x: 41, y: 41))
            path.addLine(to: CGPoint(x: 23, y: 31))
            path.addLine(to: CGPoint(x: 5, y: 41))
            path.close()
            UIColor(red: 0.98, green: 0.28, blue: 0.28, alpha: 1.0).setFill()
            path.fill()
            UIColor.white.setStroke()
            path.lineWidth = 2.5
            path.stroke()
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let poly = overlay as? MKPolyline {
            let renderer = GaoDeArrowRouteRenderer(polyline: poly)
            let tag = poly.title ?? ""
            if tag == "TRAVELED_GRAY" || tag == "TRAVELED_GREEN" {
                renderer.mainFillColor = UIColor(white: 0.62, alpha: 0.90)
                renderer.outerBorderColor = UIColor(white: 0.40, alpha: 1.0)
                renderer.drawDirectionChevrons = false
                renderer.lineWidth = 10.0
            } else if tag == "TRAFFIC_GREEN" {
                renderer.mainFillColor = UIColor(red: 0.06, green: 0.72, blue: 0.51, alpha: 0.98)
                renderer.outerBorderColor = UIColor(red: 0.02, green: 0.44, blue: 0.30, alpha: 1.0)
                renderer.drawDirectionChevrons = true
                renderer.lineWidth = 11.0
            } else if tag == "TRAFFIC_YELLOW" {
                renderer.mainFillColor = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 0.98)
                renderer.outerBorderColor = UIColor(red: 0.68, green: 0.40, blue: 0.0, alpha: 1.0)
                renderer.drawDirectionChevrons = true
                renderer.lineWidth = 11.0
            } else if tag == "TRAFFIC_RED" {
                renderer.mainFillColor = UIColor(red: 0.94, green: 0.22, blue: 0.22, alpha: 0.98)
                renderer.outerBorderColor = UIColor(red: 0.60, green: 0.05, blue: 0.05, alpha: 1.0)
                renderer.drawDirectionChevrons = true
                renderer.lineWidth = 11.0
            } else if tag == "WALKING_BLUE" {
                renderer.mainFillColor = UIColor(red: 0.05, green: 0.65, blue: 0.98, alpha: 0.96)
                renderer.outerBorderColor = UIColor(red: 0.0, green: 0.38, blue: 0.72, alpha: 1.0)
                renderer.drawDirectionChevrons = true
                renderer.lineWidth = 9.5
            } else {
                renderer.mainFillColor = UIColor(red: 0.0, green: 0.62, blue: 1.0, alpha: 0.98)
                renderer.outerBorderColor = UIColor(red: 0.0, green: 0.32, blue: 0.68, alpha: 1.0)
                renderer.drawDirectionChevrons = true
                renderer.lineWidth = 11.0
            }
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - CarPlay Scene Delegate (Supports Interactive Panning, Dashboard, ETA & Voice Control)
@objc(CarPlaySceneDelegate)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate {
    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?
    var mapViewController: CarPlayMapViewController?
    var mapTemplate: CPMapTemplate?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        self.interfaceController = interfaceController
        self.carWindow = window

        let mapVC = CarPlayMapViewController()
        self.mapViewController = mapVC
        window.rootViewController = mapVC
        window.makeKeyAndVisible()

        let tmpl = buildCarPlayMapTemplate()
        self.mapTemplate = tmpl
        interfaceController.setRootTemplate(tmpl, animated: true, completion: nil)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let listTemplate = buildCharacterAndActionListTemplate()
        interfaceController.setRootTemplate(listTemplate, animated: true, completion: nil)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        window.rootViewController = nil
        self.interfaceController = nil
        self.carWindow = nil
        self.mapViewController = nil
        self.mapTemplate = nil
    }

    private func buildCarPlayMapTemplate() -> CPMapTemplate {
        let mapTemplate = CPMapTemplate()
        mapTemplate.mapDelegate = self
        mapTemplate.automaticallyHidesNavigationBar = false

        let charBtn = CPBarButton(title: "切换角色") { [weak self] _ in
            guard let self = self else { return }
            let list = self.buildCharacterAndActionListTemplate()
            self.interfaceController?.pushTemplate(list, animated: true, completion: nil)
        }

        let panBtn = CPBarButton(title: "拖动地图") { [weak mapTemplate] _ in
            guard let mt = mapTemplate else { return }
            if mt.isPanningInterfaceVisible {
                mt.dismissPanningInterface(animated: true)
            } else {
                mt.showPanningInterface(animated: true)
            }
        }
        mapTemplate.leadingNavigationBarButtons = [charBtn, panBtn]

        let recenterBtn = CPBarButton(title: "回中跟车") { [weak self, weak mapTemplate] _ in
            mapTemplate?.dismissPanningInterface(animated: true)
            AudioPlayerManager.shared.triggerFastRecenter()
            self?.mapViewController?.recenterImmediate()
        }

        let voiceBtn = CPBarButton(title: "随机语音") { _ in
            AudioPlayerManager.shared.playRandomCharacterGreeting()
        }
        mapTemplate.trailingNavigationBarButtons = [recenterBtn, voiceBtn]

        // Map side buttons for Zoom + / - & Panning
        if let plusImg = UIImage(systemName: "plus.magnifyingglass"),
           let minusImg = UIImage(systemName: "minus.magnifyingglass"),
           let panImg = UIImage(systemName: "hand.draw") {
            let zoomInBtn = CPMapButton { [weak self] _ in self?.mapViewController?.zoomMap(scale: 0.65) }
            zoomInBtn.image = plusImg
            let zoomOutBtn = CPMapButton { [weak self] _ in self?.mapViewController?.zoomMap(scale: 1.5) }
            zoomOutBtn.image = minusImg
            let panToggleBtn = CPMapButton { [weak mapTemplate] _ in
                guard let mt = mapTemplate else { return }
                if mt.isPanningInterfaceVisible { mt.dismissPanningInterface(animated: true) } else { mt.showPanningInterface(animated: true) }
            }
            panToggleBtn.image = panImg
            mapTemplate.mapButtons = [panToggleBtn, zoomInBtn, zoomOutBtn]
        }

        return mapTemplate
    }

    // MARK: - CPMapTemplateDelegate Panning Support
    func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
        mapViewController?.panMap(direction: direction)
    }

    func mapTemplateDidShowPanningInterface(_ mapTemplate: CPMapTemplate) {
        mapViewController?.isUserPanning = true
    }

    func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {
        // Keep user's panned position until they tap "回中跟车"
    }

    private func buildCharacterAndActionListTemplate() -> CPListTemplate {
        let mgr = AudioPlayerManager.shared

        var charItems: [CPListItem] = []
        for char in AudioPlayerManager.CharacterFilter.allCases {
            let item = CPListItem(
                text: char.displayName(mgr.language),
                detailText: char.roleTag(mgr.language),
                image: mgr.getRM500StageIcon(for: char)
            )
            item.handler = { [weak self] _, completion in
                mgr.selectedCharacter = char
                mgr.triggerCharacterTap(member: char)
                completion()
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
            }
            charItems.append(item)
        }
        let charSection = CPListSection(items: charItems, header: "放课后茶会 · 导航语音角色", sectionIndexTitle: nil)

        var outfitItems: [CPListItem] = []
        for outfit in RM500ArrowOutfit.allCases {
            let item = CPListItem(
                text: outfit.title(mgr.language),
                detailText: mgr.arrowOutfit == outfit ? "当前使用中" : "点击切换车标造型"
            )
            item.handler = { [weak self] _, completion in
                mgr.arrowOutfit = outfit
                mgr.playRandomCharacterGreeting()
                completion()
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
            }
            outfitItems.append(item)
        }
        let outfitSection = CPListSection(items: outfitItems, header: "RM-500HTT 原版自车箭头造型", sectionIndexTitle: nil)

        var modeItems: [CPListItem] = []
        for mode in NavigationTravelMode.allCases {
            let item = CPListItem(
                text: mode.title(mgr.language),
                detailText: "默认限速 \(Int(mode.defaultSpeedLimit)) km/h"
            )
            item.handler = { [weak self] _, completion in
                mgr.travelMode = mode
                completion()
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
            }
            modeItems.append(item)
        }
        let modeSection = CPListSection(items: modeItems, header: "出行方式切换", sectionIndexTitle: nil)

        return CPListTemplate(title: "K-ON! 车载中心", sections: [charSection, outfitSection, modeSection])
    }
}

// MARK: - CarPlay Dashboard Split-Screen Scene Delegate (Replaces Amap on CarPlay Home Screen!)
@objc(CarPlayDashboardSceneDelegate)
class CarPlayDashboardSceneDelegate: UIResponder, CPTemplateApplicationDashboardSceneDelegate {
    var dashboardController: CPDashboardController?
    var dashboardWindow: UIWindow?
    var mapVC: CarPlayMapViewController?

    func templateApplicationDashboardScene(_ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
                                           didConnect dashboardController: CPDashboardController,
                                           to window: UIWindow) {
        self.dashboardController = dashboardController
        self.dashboardWindow = window

        let vc = CarPlayMapViewController()
        self.mapVC = vc
        window.rootViewController = vc
        window.makeKeyAndVisible()

        let btn1 = CPDashboardButton(
            titleVariants: ["切换角色"],
            subtitleVariants: ["放课后茶会"],
            image: UIImage(systemName: "person.2.fill") ?? UIImage()
        ) { _ in
            let mgr = AudioPlayerManager.shared
            let allChars = AudioPlayerManager.CharacterFilter.allCases
            if let idx = allChars.firstIndex(of: mgr.selectedCharacter) {
                let nextChar = allChars[(idx + 1) % allChars.count]
                mgr.selectedCharacter = nextChar
                mgr.triggerCharacterTap(member: nextChar)
            } else {
                mgr.playRandomCharacterGreeting()
            }
        }
        let btn2 = CPDashboardButton(
            titleVariants: ["回中跟车"],
            subtitleVariants: ["锁定车位"],
            image: UIImage(systemName: "location.fill") ?? UIImage()
        ) { [weak vc] _ in
            AudioPlayerManager.shared.triggerFastRecenter()
            vc?.recenterImmediate()
        }
        dashboardController.shortcutButtons = [btn1, btn2]
    }

    func templateApplicationDashboardScene(_ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
                                           didDisconnect dashboardController: CPDashboardController,
                                           from window: UIWindow) {
        window.rootViewController = nil
        self.dashboardController = nil
        self.dashboardWindow = nil
        self.mapVC = nil
    }
}
