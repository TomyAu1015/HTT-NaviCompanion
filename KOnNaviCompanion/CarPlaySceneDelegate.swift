import UIKit
import CarPlay
import MapKit
import Combine

// MARK: - CarPlay Dedicated Interactive 3D Map & RM-500HTT HUD ViewController
class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    let mapView = MKMapView()
    private let speedBadge = UIView()
    private let speedLabel = UILabel()
    private let unitLabel = UILabel()
    private let limitLabel = UILabel()
    private let bubbleView = UIView()
    private let speakerLabel = UILabel()
    private let quoteLabel = UILabel()
    private let mascotImageView = UIImageView()
    private var cancellables = Set<AnyCancellable>()
    private var lastRoute: MKRoute? = nil
    
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
        mapView.showsTraffic = true
        mapView.showsBuildings = true
        view.addSubview(mapView)
        
        let region = MKCoordinateRegion(
            center: AudioPlayerManager.shared.userCoordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        mapView.setRegion(region, animated: false)
    }
    
    private func setupCarPlayHUDOverlay() {
        // 1. Speedometer Badge (Bottom Left)
        speedBadge.backgroundColor = UIColor.black.withAlphaComponent(0.82)
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
        
        // 2. Voice Bubble & Mascot (Bottom Center/Right)
        bubbleView.backgroundColor = UIColor(red: 0.99, green: 0.96, blue: 0.90, alpha: 0.94)
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
            
            bubbleView.leadingAnchor.constraint(equalTo: speedBadge.trailingAnchor, constant: 10),
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
        
        mgr.$speedLimitKmh
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lim in
                self?.limitLabel.text = "限速 \(Int(lim))"
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
        
        mgr.$userCoordinate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                guard let self = self else { return }
                let cam = MKMapCamera(
                    lookingAtCenter: coord,
                    fromDistance: mgr.travelMode == .walking ? 380 : 520,
                    pitch: 45,
                    heading: mgr.headingDegrees
                )
                self.mapView.setCamera(cam, animated: true)
            }
            .store(in: &cancellables)
        
        mgr.$activeRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                guard let self = self else { return }
                self.mapView.removeOverlays(self.mapView.overlays)
                if let route = route {
                    self.mapView.addOverlay(route.polyline, level: .aboveRoads)
                }
            }
            .store(in: &cancellables)
    }
    
    func recenterImmediate() {
        let mgr = AudioPlayerManager.shared
        let coord = mapView.userLocation.location?.coordinate ?? mgr.userCoordinate
        let cam = MKMapCamera(
            lookingAtCenter: coord,
            fromDistance: 480,
            pitch: 48,
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
            let r = MKPolylineRenderer(polyline: poly)
            switch AudioPlayerManager.shared.travelMode {
            case .driving:
                r.strokeColor = UIColor(red: 0.92, green: 0.22, blue: 0.35, alpha: 0.92)
            case .ebike:
                r.strokeColor = UIColor(red: 1.0, green: 0.82, blue: 0.10, alpha: 0.96)
            case .walking:
                r.strokeColor = UIColor(red: 0.25, green: 0.58, blue: 0.95, alpha: 0.92)
            case .transit:
                r.strokeColor = UIColor(red: 0.65, green: 0.35, blue: 0.90, alpha: 0.92)
            }
            r.lineWidth = 8.0
            r.lineCap = .round
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - CarPlay Scene Delegate (Supports Both CarPlay Navigation Map & Audio/Voice Control)
@objc(CarPlaySceneDelegate)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate {
    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?
    var mapViewController: CarPlayMapViewController?
    
    // 1. Connected with Dedicated Navigation Window (Driving/Navigation Entitlement)
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        self.interfaceController = interfaceController
        self.carWindow = window
        
        let mapVC = CarPlayMapViewController()
        self.mapViewController = mapVC
        window.rootViewController = mapVC
        window.makeKeyAndVisible()
        
        let mapTemplate = buildCarPlayMapTemplate()
        interfaceController.setRootTemplate(mapTemplate, animated: true, completion: nil)
    }
    
    // 2. Connected without Map Window (Fallback for Audio-Only Entitlement)
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let listTemplate = buildCharacterAndActionListTemplate()
        interfaceController.setRootTemplate(listTemplate, animated: true, completion: nil)
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        self.interfaceController = nil
        self.carWindow = nil
        self.mapViewController = nil
    }
    
    private func buildCarPlayMapTemplate() -> CPMapTemplate {
        let mapTemplate = CPMapTemplate()
        mapTemplate.mapDelegate = self
        
        // Leading Bar Buttons: Switch Character & Switch Outfit
        let charBtn = CPBarButton(title: "切换角色") { [weak self] _ in
            guard let self = self else { return }
            let list = self.buildCharacterAndActionListTemplate()
            self.interfaceController?.pushTemplate(list, animated: true, completion: nil)
        }
        
        let demoBtn = CPBarButton(title: "模拟指路") { _ in
            AudioPlayerManager.shared.toggleDemoSimulation()
        }
        mapTemplate.leadingNavigationBarButtons = [charBtn, demoBtn]
        
        // Trailing Bar Buttons: Instant Recenter & Random Voice
        let recenterBtn = CPBarButton(title: "回中跟车") { [weak self] _ in
            AudioPlayerManager.shared.triggerFastRecenter()
            self?.mapViewController?.recenterImmediate()
        }
        
        let voiceBtn = CPBarButton(title: "随机语音") { _ in
            AudioPlayerManager.shared.playRandomCharacterGreeting()
        }
        mapTemplate.trailingNavigationBarButtons = [recenterBtn, voiceBtn]
        
        return mapTemplate
    }
    
    private func buildCharacterAndActionListTemplate() -> CPListTemplate {
        let mgr = AudioPlayerManager.shared
        
        // Section 1: Character Selection
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
        
        // Section 2: RM-500HTT Navigation Arrow Outfit Selection
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
        
        // Section 3: Travel Mode Selection
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
