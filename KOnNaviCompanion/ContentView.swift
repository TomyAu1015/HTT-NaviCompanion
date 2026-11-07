import SwiftUI
import MapKit

// MARK: - Pinyin IME-Safe Native UISearchBar (Never Interrupts Chinese Marked Text!)
struct NativePinyinSearchBar: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onTypingSettled: (String) -> Void
    var onSearchButtonClicked: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar(frame: .zero)
        bar.delegate = context.coordinator
        bar.searchBarStyle = .minimal
        bar.placeholder = placeholder
        bar.returnKeyType = .search
        bar.autocapitalizationType = .none
        bar.autocorrectionType = .default
        return bar
    }
    
    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.placeholder = placeholder
        // CRITICAL FOR CHINESE PINYIN INPUT:
        // Never overwrite textField.text while markedTextRange != nil (when user is composing Pinyin like "guang zhou")!
        if let tf = uiView.value(forKey: "searchField") as? UITextField {
            if tf.markedTextRange != nil {
                return
            }
        }
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativePinyinSearchBar
        private var debounceTimer: Timer?
        
        init(_ parent: NativePinyinSearchBar) {
            self.parent = parent
        }
        
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            // Check if user is still in the middle of Pinyin composition (markedTextRange != nil)
            if let tf = searchBar.value(forKey: "searchField") as? UITextField,
               tf.markedTextRange != nil {
                return
            }
            parent.text = searchText
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                self?.parent.onTypingSettled(searchText)
            }
        }
        
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            let finalStr = searchBar.text ?? ""
            parent.text = finalStr
            parent.onSearchButtonClicked(finalStr)
        }
    }
}

// MARK: - Native 3D AutoNavi/MapKit Route & 60fps Smooth Tracking View
struct HTTSmoothMapView: UIViewRepresentable {
    @ObservedObject var manager: AudioPlayerManager
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsTraffic = true
        mapView.showsBuildings = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        if #available(iOS 13.0, *) {
            mapView.pointOfInterestFilter = .includingAll
        }
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didPanMap(_:)))
        panGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didPinchMap(_:)))
        pinchGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(pinchGesture)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTapMap(_:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)
        
        let region = MKCoordinateRegion(
            center: manager.userCoordinate,
            latitudinalMeters: 380,
            longitudinalMeters: 380
        )
        mapView.setRegion(region, animated: false)
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let camHeading = (manager.cameraMode == .headingUp) ? manager.headingDegrees : 0.0
        let camPitch: CGFloat = (manager.cameraMode == .headingUp) ? 45.0 : 0.0
        
        // 1. Route Overlays, Candidate Alternate Routes, Electronic Speed Cameras & Tapped POI Pins
        let tappedChanged = (context.coordinator.lastTappedLat != manager.tappedMapCoord?.latitude) ||
                            (context.coordinator.lastTappedLon != manager.tappedMapCoord?.longitude)
        let routeChanged = (context.coordinator.lastRoute !== manager.activeRoute) ||
                           (context.coordinator.lastCandidateCount != manager.candidateRoutes.count)
        
        if routeChanged || tappedChanged {
            context.coordinator.lastRoute = manager.activeRoute
            context.coordinator.lastCandidateCount = manager.candidateRoutes.count
            context.coordinator.lastTappedLat = manager.tappedMapCoord?.latitude
            context.coordinator.lastTappedLon = manager.tappedMapCoord?.longitude
            
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            
            if let route = manager.activeRoute {
                mapView.addOverlay(route.polyline, level: .aboveRoads)
                if let dest = manager.destinationCoord {
                    let pin = MKPointAnnotation()
                    pin.coordinate = dest
                    pin.title = manager.destinationName
                    mapView.addAnnotation(pin)
                }
                for hazard in manager.routeHazards {
                    mapView.addAnnotation(hazard)
                }
            }
            
            if let tapped = manager.tappedMapCoord {
                let tappedPin = MKPointAnnotation()
                tappedPin.coordinate = tapped
                tappedPin.title = manager.tappedMapTitle
                tappedPin.subtitle = "TAP_PIN"
                mapView.addAnnotation(tappedPin)
            }
            
            if routeChanged && manager.activeRoute != nil {
                let targetCoord = (!manager.isDemoSimulating && mapView.userLocation.location != nil)
                    ? mapView.userLocation.coordinate
                    : manager.userCoordinate
                let camera = MKMapCamera(
                    lookingAtCenter: targetCoord,
                    fromDistance: manager.userZoomDistance,
                    pitch: camPitch,
                    heading: camHeading
                )
                mapView.setCamera(camera, animated: false)
            }
        }
        
        // 2. Update Authentic RM-500HTT Navigation Arrow Sprite / 3D Arrow
        if let userView = mapView.view(for: mapView.userLocation) {
            if let rmArrow = manager.getRM500NavigationArrowFrame(mapCameraHeading: mapView.camera.heading) {
                userView.image = rmArrow
                userView.bounds = CGRect(x: 0, y: 0, width: 68, height: 88)
                userView.centerOffset = CGPoint(x: 0, y: -22)
                userView.transform = .identity
            } else {
                userView.image = context.coordinator.arrowImage
                userView.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
                userView.centerOffset = .zero
                let rotationAngle = CGFloat((manager.headingDegrees - mapView.camera.heading) * .pi / 180.0)
                userView.transform = CGAffineTransform(rotationAngle: rotationAngle)
            }
        }
        
        // 3. Dedicated Zoom [+] / [-] Button Trigger (Strictly zooms in/out at current map center!)
        if context.coordinator.lastZoomTrigger != manager.zoomCommandTrigger {
            context.coordinator.lastZoomTrigger = manager.zoomCommandTrigger
            let centerCoord = manager.mapTrackingUser
                ? ((!manager.isDemoSimulating && mapView.userLocation.location != nil) ? mapView.userLocation.coordinate : manager.userCoordinate)
                : mapView.camera.centerCoordinate
            let cam = MKMapCamera(
                lookingAtCenter: centerCoord,
                fromDistance: manager.userZoomDistance,
                pitch: mapView.camera.pitch,
                heading: mapView.camera.heading
            )
            mapView.setCamera(cam, animated: false)
            return
        }
        
        // 4. Instant Zero-Lag Recenter & Non-Blocking Camera Follow
        if context.coordinator.lastRecenterTrigger != manager.recenterTrigger {
            context.coordinator.lastRecenterTrigger = manager.recenterTrigger
            context.coordinator.isUserInteracting = false
            
            let targetCoord = (!manager.isDemoSimulating && mapView.userLocation.location != nil)
                ? mapView.userLocation.coordinate
                : manager.userCoordinate
            
            mapView.layer.removeAllAnimations()
            let camera = MKMapCamera(
                lookingAtCenter: targetCoord,
                fromDistance: manager.userZoomDistance,
                pitch: camPitch,
                heading: camHeading
            )
            mapView.setCamera(camera, animated: false)
            
        } else if manager.mapTrackingUser && !context.coordinator.isUserInteracting {
            let targetCoord = (!manager.isDemoSimulating && mapView.userLocation.location != nil)
                ? mapView.userLocation.coordinate
                : manager.userCoordinate
            
            var hDiff = abs(mapView.camera.heading - camHeading).truncatingRemainder(dividingBy: 360.0)
            if hDiff > 180.0 { hDiff = 360.0 - hDiff }
            let camLoc = CLLocation(latitude: mapView.camera.centerCoordinate.latitude,
                                    longitude: mapView.camera.centerCoordinate.longitude)
            let usrLoc = CLLocation(latitude: targetCoord.latitude, longitude: targetCoord.longitude)
            let distDelta = camLoc.distance(from: usrLoc)
            
            if distDelta > 3.0 || hDiff > 2.5 {
                let camera = MKMapCamera(
                    lookingAtCenter: targetCoord,
                    fromDistance: manager.userZoomDistance,
                    pitch: camPitch,
                    heading: camHeading
                )
                // Use animated: false for small heading updates so MapKit NEVER freezes or locks up!
                mapView.setCamera(camera, animated: false)
            }
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: HTTSmoothMapView
        var lastRoute: MKRoute? = nil
        var lastCandidateCount: Int = 0
        var lastTappedLat: Double? = nil
        var lastTappedLon: Double? = nil
        var isUserInteracting: Bool = false
        var lastRecenterTrigger: Int = 0
        var lastZoomTrigger: Int = 0
        
        lazy var arrowImage: UIImage = {
            Coordinator.createNavigationArrowImage()
        }()
        
        init(_ parent: HTTSmoothMapView) {
            self.parent = parent
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        @objc func didPanMap(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed {
                isUserInteracting = true
                if parent.manager.mapTrackingUser {
                    DispatchQueue.main.async {
                        self.parent.manager.mapTrackingUser = false
                    }
                }
            } else if gesture.state == .ended || gesture.state == .cancelled {
                isUserInteracting = false
            }
        }
        
        @objc func didPinchMap(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed {
                isUserInteracting = true
            } else if gesture.state == .ended || gesture.state == .cancelled {
                isUserInteracting = false
                if let mapView = gesture.view as? MKMapView {
                    let currentAlt = max(100.0, min(30000.0, mapView.camera.centerCoordinateDistance))
                    DispatchQueue.main.async {
                        self.parent.manager.userZoomDistance = currentAlt
                    }
                }
            }
        }
        
        @objc func didTapMap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            DispatchQueue.main.async {
                self.parent.manager.handleMapTap(at: coord)
            }
        }
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard userLocation.location != nil, !parent.manager.isDemoSimulating else { return }
            DispatchQueue.main.async {
                self.parent.manager.userCoordinate = userLocation.coordinate
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let identifier = "UserVehicleArrowView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                } else {
                    view?.annotation = annotation
                }
                
                if let rmArrow = parent.manager.getRM500NavigationArrowFrame(mapCameraHeading: mapView.camera.heading) {
                    view?.image = rmArrow
                    view?.bounds = CGRect(x: 0, y: 0, width: 68, height: 88)
                    view?.centerOffset = CGPoint(x: 0, y: -22)
                    view?.transform = .identity
                } else {
                    view?.image = arrowImage
                    view?.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
                    view?.centerOffset = .zero
                    let rotationAngle = CGFloat((parent.manager.headingDegrees - mapView.camera.heading) * .pi / 180.0)
                    view?.transform = CGAffineTransform(rotationAngle: rotationAngle)
                }
                return view
            } else if let hazard = annotation as? RoadHazardAnnotation {
                let id = "RoadHazardPinView_\(hazard.kind.rawValue)"
                var hView = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if hView == nil {
                    hView = MKMarkerAnnotationView(annotation: hazard, reuseIdentifier: id)
                    hView?.canShowCallout = true
                } else {
                    hView?.annotation = hazard
                }
                switch hazard.kind {
                case .speedCamera:
                    hView?.markerTintColor = .systemRed
                    hView?.glyphText = "\(hazard.speedLimitValue)"
                case .redLightCam:
                    hView?.markerTintColor = .systemPink
                    hView?.glyphImage = UIImage(systemName: "camera.fill")
                case .tollStation:
                    hView?.markerTintColor = .systemOrange
                    hView?.glyphText = "¥"
                case .serviceArea:
                    hView?.markerTintColor = .systemBlue
                    hView?.glyphImage = UIImage(systemName: "cup.and.saucer.fill")
                case .congestion:
                    hView?.markerTintColor = .systemYellow
                    hView?.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
                }
                return hView
            } else if let pin = annotation as? MKPointAnnotation {
                let isTapPin = (pin.subtitle == "TAP_PIN")
                let id = isTapPin ? "TappedPinView" : "DestinationPinView"
                var pinView = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if pinView == nil {
                    pinView = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: id)
                    pinView?.canShowCallout = false
                } else {
                    pinView?.annotation = pin
                }
                pinView?.markerTintColor = isTapPin
                    ? UIColor.systemOrange
                    : UIColor(red: 0.78, green: 0.18, blue: 0.22, alpha: 1.0)
                pinView?.glyphImage = UIImage(systemName: isTapPin ? "mappin.and.ellipse" : "flag.checkered")
                return pinView
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
                path.move(to: CGPoint(x: 23, y: 4))
                path.addLine(to: CGPoint(x: 41, y: 41))
                path.addLine(to: CGPoint(x: 23, y: 31))
                path.addLine(to: CGPoint(x: 5, y: 41))
                path.close()
                UIColor.white.setStroke()
                path.lineWidth = 3.5
                path.lineJoinStyle = .round
                path.stroke()
                UIColor(red: 0.10, green: 0.58, blue: 0.98, alpha: 1.0).setFill()
                path.fill()
                let ridge = UIBezierPath()
                ridge.move(to: CGPoint(x: 23, y: 8))
                ridge.addLine(to: CGPoint(x: 23, y: 29))
                UIColor.white.withAlphaComponent(0.55).setStroke()
                ridge.lineWidth = 2.0
                ridge.stroke()
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                switch parent.manager.travelMode {
                case .driving:
                    renderer.strokeColor = UIColor(red: 0.92, green: 0.22, blue: 0.35, alpha: 0.92)
                    renderer.lineWidth = 8.0
                case .ebike:
                    renderer.strokeColor = UIColor(red: 1.0, green: 0.82, blue: 0.10, alpha: 0.96)
                    renderer.lineWidth = 8.0
                case .walking:
                    renderer.strokeColor = UIColor(red: 0.25, green: 0.58, blue: 0.95, alpha: 0.92)
                    renderer.lineWidth = 6.0
                    renderer.lineDashPattern = [2, 5]
                case .transit:
                    renderer.strokeColor = UIColor(red: 0.65, green: 0.35, blue: 0.90, alpha: 0.92)
                    renderer.lineWidth = 7.0
                }
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Main Content View with Dynamic Auto-Enlarging Navigation HUD
struct ContentView: View {
    @StateObject private var manager = AudioPlayerManager.shared
    @State private var showSoundboardSheet: Bool = false
    @State private var showSearchSheet: Bool = false
    @State private var showAlbumSheet: Bool = false
    @State private var showOutfitPopup: Bool = false
    @State private var showCautionSplash: Bool = false
    @State private var dragOffset: CGSize = .zero
    
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httDarkPanel = Color(red: 0.14, green: 0.12, blue: 0.13)
    
    private func tr(_ hans: String, _ hant: String, _ en: String) -> String {
        switch manager.language {
        case .zhHans: return hans
        case .zhHant: return hant
        case .en: return en
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                httDarkPanel.ignoresSafeArea(.all)
                
                // RM-500HTT Authentic Character Starry Diagonal Background Skin (Full Edge-to-Edge Coverage!)
                if let themeBG = manager.getCurrentThemeBackground(), !manager.isMapEnlarged {
                    Image(uiImage: themeBG)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: max(geo.size.width, UIScreen.main.bounds.width),
                            height: max(geo.size.height + 120, UIScreen.main.bounds.height + 120)
                        )
                        .clipped()
                        .opacity(0.38)
                        .ignoresSafeArea(.all)
                }
                
                // CONDITIONAL 1: Prominent Enlarged Full-Screen Navigation View
                if manager.isMapEnlarged {
                    enlargedNavigationHUDView(geo: geo, isLandscape: isLandscape)
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                } else {
                    // CONDITIONAL 2: Standard Classic Cockpit View
                    if isLandscape {
                        // Explicitly reserve 44pt on notch side & 20pt on trailing side, and move Companion Dock to Right Column so both sides are balanced and nothing is clipped!
                        let leadingNotchPad: CGFloat = max(geo.safeAreaInsets.leading + 8, 44)
                        let trailingSafePad: CGFloat = max(geo.safeAreaInsets.trailing + 8, 20)
                        let usableW = max(320, geo.size.width - leadingNotchPad - trailingSafePad)
                        let leftColW = usableW * 0.43
                        let rightColW = usableW * 0.55
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                topBezelBar
                                    .frame(width: usableW)
                                HStack(alignment: .top, spacing: usableW * 0.02) {
                                    // Left Column: Speedometer + 3 Tactical Buttons + Cruise/Route
                                    VStack(spacing: 7) {
                                        speedometerCockpit
                                        utilityControlGrid
                                    }
                                    .frame(width: leftColW)
                                    
                                    // Right Column: Map/Stage + Speech Bubble + Character Strip + Quick Travel & Outfit Dock (Fills right side completely!)
                                    VStack(spacing: 6) {
                                        mainStageOrMapSection(stageWidth: rightColW, stageHeight: 165)
                                        characterSelectorStrip
                                            .frame(width: rightColW)
                                        portraitBottomCompanionDock
                                            .frame(width: rightColW)
                                    }
                                    .frame(width: rightColW)
                                }
                                .frame(width: usableW)
                            }
                            .padding(.leading, leadingNotchPad)
                            .padding(.trailing, trailingSafePad)
                            .padding(.vertical, 4)
                        }
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                        .onAppear { manager.stageWalkBound = 85.0 }
                    } else {
                        let portraitStageH = max(210, min(255, geo.size.height * 0.27))
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 9) {
                                topBezelBar
                                speedometerCockpit
                                mainStageOrMapSection(stageWidth: geo.size.width - 24, stageHeight: portraitStageH)
                                characterSelectorStrip
                                utilityControlGrid
                                portraitBottomCompanionDock
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, 12)
                        }
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                        .onAppear { manager.stageWalkBound = 65.0 }
                    }
                }
                
                // Long-Press RM-500HTT Beautified Outfit Quick Switcher Modal!
                if showOutfitPopup {
                    outfitQuickPickerModalOverlay
                }
            }
            .onChange(of: isLandscape) { newVal in
                manager.stageWalkBound = newVal ? 95.0 : 65.0
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showSoundboardSheet) {
            SoundboardSheetView(manager: manager)
        }
        .sheet(isPresented: $showSearchSheet) {
            DestinationSearchSheetView(manager: manager)
        }
        .sheet(isPresented: $showAlbumSheet) {
            RM500AlbumAndOutfitSheetView(manager: manager)
        }
    }
    
    // MARK: - ENLARGED FULL-SCREEN NAVIGATION HUD
    private func enlargedNavigationHUDView(geo: GeometryProxy, isLandscape: Bool) -> some View {
        ZStack {
            // 1. Full Screen 3D Navigation Map
            HTTSmoothMapView(manager: manager)
                .ignoresSafeArea()
            
            // 2. Overlays
            VStack(spacing: 5) {
                // Top Navigation Guidance Card
                topNavigationBannerCard
                    .padding(.horizontal, 12)
                    .padding(.top, isLandscape ? 6 : 8)
                
                // Multi-Lane Guidance Bar (3~4 Lanes: Recommended in Bright White, Others in Dimmed Gray) + Traffic Light Countdown!
                if manager.activeRoute != nil || manager.isDemoSimulating {
                    laneGuidanceAndTrafficLightBar
                        .padding(.horizontal, 12)
                }
                
                // Show Travel Mode switcher bar ONLY before pressing [开始导航] (Hidden during focused driving!)
                if !manager.isNavigatingFocused {
                    travelModeSelectorBar
                        .padding(.horizontal, 12)
                }
                
                // Electronic Speed Camera + Traffic Congestion + Toll + Service Area HUD Strip + Unobstructed Compass + Zoom [+] / [-]!
                HStack(alignment: .top, spacing: 6) {
                    electronicEyeAndHighwayHUDStrip
                    
                    Spacer(minLength: 4)
                    
                    // Right Side Stack: Unobstructed Rotating HTT Compass + Recenter + Zoom [+] / [-] Buttons!
                    VStack(alignment: .trailing, spacing: 7) {
                        Button(action: {
                            manager.toggleCameraMode()
                        }) {
                            HStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.85))
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().stroke(httGold, lineWidth: 1.5))
                                    Image(systemName: "location.north.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.red)
                                        .rotationEffect(.degrees(manager.cameraMode == .headingUp ? -manager.headingDegrees : 0))
                                }
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(manager.compassDirectionString)
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(.white)
                                    Text(manager.cameraMode.shortTitle(manager.language))
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(httGold)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.82))
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(httGold.opacity(0.75), lineWidth: 1))
                        }
                        
                        // Recenter Button on Right Side (Always accessible even in Focused Driving Mode!)
                        Button(action: {
                            manager.triggerFastRecenter()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: manager.mapTrackingUser ? "location.north.line.fill" : "location")
                                Text(manager.mapTrackingUser ? tr("跟车中", "跟車中", "Locked") : tr("回中", "回中", "Center"))
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(manager.mapTrackingUser ? Color.green.opacity(0.88) : Color.black.opacity(0.82))
                            .foregroundColor(manager.mapTrackingUser ? .black : httGold)
                            .cornerRadius(8)
                        }
                        
                        // Explicit Zoom In [+] / Zoom Out [-] Buttons (Strictly zooms in/out at current position!)
                        VStack(spacing: 4) {
                            Button(action: { manager.zoomMapIn() }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(httGold)
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(0.82))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.6), lineWidth: 1))
                            }
                            Button(action: { manager.zoomMapOut() }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(httCream)
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(0.82))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer()
                
                // Interactive Tapped Named POI Card (Appears only when user taps a real shop/place on map!)
                if manager.tappedMapCoord != nil {
                    tappedMapPointNavigationCard
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Bottom Pre-Navigation Panel: Highway Preference + Candidate Routes + Prominent [🚀 开始导航] Button!
                // Moved to the bottom as requested, and automatically hides once [开始导航] is pressed!
                if !manager.isNavigatingFocused && (manager.activeRoute != nil || !manager.candidateRoutes.isEmpty) {
                    bottomPreNavRouteSelectionCard
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Bottom Floating Control Island (Speedometer + Speech Bubble + Bottom-Right Mascot!)
                bottomEnlargedFloatingIsland(isLandscape: isLandscape)
                    .padding(.horizontal, 12)
                    .padding(.bottom, isLandscape ? 8 : 20)
            }
        }
    }
    
    // MARK: - Top Turn-by-Turn Instruction Banner Card
    private var topNavigationBannerCard: some View {
        HStack(spacing: 12) {
            // Maneuver Turn Arrow
            ZStack {
                Circle()
                    .fill(httCrimson)
                    .frame(width: 50, height: 50)
                    .overlay(Circle().stroke(httGold, lineWidth: 2))
                
                Image(systemName: turnIconName(for: manager.currentStepInstruction))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(httCream)
            }
            
            // Instruction Text & Total Route Distance/Time
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(manager.destinationName.isEmpty ? tr("实时路线引导", "即時路線引導", "Route Guidance") : manager.destinationName)
                        .font(.caption2.bold())
                        .foregroundColor(httGold)
                    Spacer()
                    if manager.remainingRouteDistanceKm > 0 {
                        Text(String(format: "%.1f km · %d %@", manager.remainingRouteDistanceKm, manager.remainingRouteMinutes, tr("分钟", "分鐘", "min")))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(httCream.opacity(0.9))
                    }
                }
                
                Text(manager.currentStepInstruction.isEmpty
                     ? tr("沿着当前道路直行", "沿著當前道路直行", "Continue straight ahead")
                     : manager.currentStepInstruction)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            // Step Distance Countdown Badge (Smart km / m format!)
            if manager.distanceToNextStepMeters > 0 {
                VStack(spacing: 1) {
                    Text(manager.formatSmartDistance(Int(manager.distanceToNextStepMeters)))
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(httGold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55))
                .cornerRadius(8)
            }
            
            // Transit Public Timetable Detail Button
            if manager.travelMode == .transit {
                Button(action: {
                    manager.openSystemMapsForTransit()
                }) {
                    VStack(spacing: 1) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(tr("班次", "班次", "Transit"))
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Color.purple.opacity(0.85))
                    .cornerRadius(8)
                }
            }
            
            // Exit Navigation / Minimize Button
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    if manager.activeRoute != nil {
                        manager.stopRouteGuidance()
                    } else {
                        manager.isMapEnlarged = false
                    }
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(httGold, lineWidth: 2))
                .shadow(color: .black.opacity(0.5), radius: 8)
        )
    }

    // MARK: - Multi-Lane Indicator (左转/直行/右转 白灰高亮) + Real-Time Traffic Light Countdown (红绿灯倒计时)
    private var laneGuidanceAndTrafficLightBar: some View {
        HStack(spacing: 10) {
            // 1. Multi-Lane Indicator Box (Recommended lane = Bright White, Other lanes = Gray)
            HStack(spacing: 0) {
                ForEach(Array(manager.currentRoadLanes.enumerated()), id: \.element.id) { idx, lane in
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Image(systemName: lane.iconName)
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(lane.isRecommended ? .white : Color.gray.opacity(0.45))
                                .shadow(color: lane.isRecommended ? httGold.opacity(0.8) : .clear, radius: 3)
                            Text(lane.label)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(lane.isRecommended ? httGold : Color.gray.opacity(0.45))
                        }
                        .frame(width: 36, height: 38)
                        .background(lane.isRecommended ? httCrimson.opacity(0.75) : Color.clear)
                        .cornerRadius(6)
                        
                        if idx < manager.currentRoadLanes.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 1, height: 24)
                                .padding(.horizontal, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.86))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold.opacity(0.8), lineWidth: 1.5))
            
            // 2. Real-Time Traffic Light Countdown Box (红绿灯倒计时)
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.trafficLightPhase == .red ? Color.red : Color.red.opacity(0.25))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(manager.trafficLightPhase == .yellow ? Color.yellow : Color.yellow.opacity(0.25))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(manager.trafficLightPhase == .green ? Color.green : Color.green.opacity(0.25))
                        .frame(width: 10, height: 10)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(Color.black)
                .cornerRadius(8)
                
                Text("\(manager.trafficLightSeconds)s")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(
                        manager.trafficLightPhase == .red ? .red :
                        (manager.trafficLightPhase == .yellow ? .yellow : .green)
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.86))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.25), lineWidth: 1.2))
            
            Spacer()
            
            // If in Focused Driving Mode, provide a subtle [路线选项] button to re-open route preferences if needed
            if manager.isNavigatingFocused {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        manager.exitFocusedNavigationToOverview()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "slider.horizontal.3")
                        Text(tr("路线设置", "路線設置", "Options"))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.78))
                    .foregroundColor(httGold)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.5), lineWidth: 1))
                }
            }
        }
    }
    
    // Bottom Pre-Navigation Card: Highway Strategy (高速优先/不走高速/距离最短) + Candidate Routes + Prominent [🚀 开始导航] Button!
    private var bottomPreNavRouteSelectionCard: some View {
        VStack(spacing: 7) {
            // Row 1: Highway Strategy + Candidate Routes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if manager.travelMode == .driving {
                        ForEach(RouteStrategyPreference.allCases) { pref in
                            Button(action: {
                                manager.routePreference = pref
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: pref.icon)
                                        .font(.system(size: 9, weight: .bold))
                                    Text(pref.title(manager.language))
                                        .font(.system(size: 10, weight: .bold))
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(manager.routePreference == pref ? httGold : Color.white.opacity(0.12))
                                .foregroundColor(manager.routePreference == pref ? .black : httCream)
                                .cornerRadius(7)
                            }
                        }
                    }
                    
                    if manager.candidateRoutes.count > 1 {
                        ForEach(0..<manager.candidateRoutes.count, id: \.self) { idx in
                            let r = manager.candidateRoutes[idx]
                            let isSel = (manager.selectedRouteIndex == idx)
                            Button(action: {
                                manager.selectCandidateRoute(at: idx)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isSel ? "checkmark.circle.fill" : "arrow.triangle.swap")
                                        .font(.system(size: 9))
                                    Text("\(manager.routeOptionBadgeTitle(for: r, index: idx)) (\(String(format: "%.1fkm", r.distance / 1000.0)))")
                                        .font(.system(size: 10, weight: .heavy))
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(isSel ? httCrimson : Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .cornerRadius(7)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSel ? httGold : Color.clear, lineWidth: 1))
                            }
                        }
                    }
                }
            }
            
            // Row 2: Prominent [🚀 开始导航 (专注驾驶)] Button!
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    manager.startFocusedNavigation()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.title3)
                    Text(tr("开始导航 · 隐藏选项专注驾驶", "開始導航 · 隱藏選項專注駕駛", "Start Navigation (Focus Mode)"))
                        .font(.system(size: 14, weight: .black))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [httCrimson, Color(red: 0.92, green: 0.25, blue: 0.30)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold, lineWidth: 1.5))
            }
        }
        .padding(9)
        .background(Color.black.opacity(0.88))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(httGold, lineWidth: 1.5))
    }
    
    // Electronic Speed Camera (测速电子眼) + Congestion (路况拥堵) + Service Area (服务区) + Toll Station (收费站) HUD Strip
    private var electronicEyeAndHighwayHUDStrip: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                // 1. Electronic Speed Camera Badge (测速电子眼 - Dynamically changes with road limit & alerts!)
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.red, lineWidth: 3))
                        Text("\(manager.upcomingCameraLimit > 0 ? manager.upcomingCameraLimit : Int(manager.speedLimitKmh))")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.black)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tr("测速电子眼", "測速電子眼", "Speed Cam"))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                        Text(manager.upcomingCameraDistance > 0
                             ? manager.formatSmartDistance(manager.upcomingCameraDistance)
                             : tr("全程监控中", "全程監控中", "Active"))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(httGold)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.82))
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.red.opacity(0.8), lineWidth: 1.2))
                
                // 2. Traffic Congestion Indicator (拥堵/畅通状态)
                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.isCongested ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(manager.congestionStatusText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(manager.isCongested ? .orange : Color(red: 0.4, green: 0.98, blue: 0.65))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.82))
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(manager.isCongested ? Color.orange : Color.green.opacity(0.6), lineWidth: 1))
            }
            
            // 3. Highway Service Area (服务区) & Toll Station (收费站) Badges (Auto converts >=1000m to km, <1000m to m!)
            if manager.travelMode == .driving && (manager.upcomingTollDistance > 0 || manager.upcomingServiceAreaDist > 0 || manager.activeRoute != nil || manager.isDemoSimulating) {
                HStack(spacing: 6) {
                    // Service Area (服务区)
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.cyan)
                        Text(manager.upcomingServiceAreaDist > 0
                             ? "\(tr("服务区", "服務區", "SA")): \(manager.formatSmartDistance(manager.upcomingServiceAreaDist))"
                             : tr("服务区: 沿途开放", "服務區: 沿途開放", "SA Open"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.78))
                    .cornerRadius(7)
                    
                    // Toll Station (收费站: >=1000m displays km, <1000m displays m!)
                    HStack(spacing: 4) {
                        Image(systemName: "yensign.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(httGold)
                        Text(manager.upcomingTollDistance > 0
                             ? "\(tr("收费站", "收費站", "Toll")): \(manager.formatSmartDistance(manager.upcomingTollDistance))"
                             : (manager.routePreference == .avoidHighway ? tr("免收费路段", "免收費路段", "No Toll") : tr("收费站/ETC", "收費站/ETC", "Toll/ETC")))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.82))
                    .cornerRadius(7)
                }
            }
        }
    }
    
    // 4 Travel Modes + Camera Mode + Outfit Bar (Shown before pressing [开始导航])
    private var travelModeSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NavigationTravelMode.allCases) { mode in
                    Button(action: {
                        withAnimation {
                            manager.travelMode = mode
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(mode.title(manager.language))
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            manager.travelMode == mode
                            ? httCrimson
                            : Color.black.opacity(0.72)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(manager.travelMode == mode ? httGold : Color.white.opacity(0.22), lineWidth: 1)
                        )
                    }
                }
                
                // Camera Mode Toggle: 地图动 (Heading Up) vs 车标动 (North Up)
                Button(action: {
                    manager.toggleCameraMode()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: manager.cameraMode.icon)
                        Text(manager.cameraMode.title(manager.language))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.82))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.6), lineWidth: 1))
                }
                
                // Outfit Switcher Button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        showOutfitPopup = true
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: manager.arrowOutfit.icon)
                        Text(manager.arrowOutfit.title(manager.language))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.78))
                    .foregroundColor(httGold)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.6), lineWidth: 1))
                }
            }
        }
    }
    
    // Bottom Floating Island in Enlarged Navigation View
    private func bottomEnlargedFloatingIsland(isLandscape: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Floating Mini Speedometer
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(manager.currentSpeedKmh))")
                        .font(.system(size: 38, weight: .black, design: .monospaced))
                        .foregroundColor(manager.isOverspeeding ? .red : Color(red: 0.35, green: 0.98, blue: 0.65))
                    Text("km/h")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(httCream)
                }
                
                HStack(spacing: 5) {
                    Text("\(tr("限速", "限速", "Limit")): \(Int(manager.speedLimitKmh))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(httGold)
                    Text(manager.compassDirectionString)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.82))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(manager.isOverspeeding ? Color.red : httGold, lineWidth: 1.5))
            
            // Speech Bubble Box
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.selectedCharacter.roleTag(manager.language))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(httCrimson)
                Text(manager.currentSpeechBubble)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(httCream)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold, lineWidth: 1.5))
            .frame(maxWidth: .infinity)
            
            // Floating Mascot Avatar on Map
            if manager.selectedCharacter == .all {
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(AudioPlayerManager.CharacterFilter.fiveIndividuals) { member in
                        if let frame = manager.allMemberFrames[member.charId] {
                            Image(uiImage: frame)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 60)
                                .shadow(radius: 3)
                                .onTapGesture { manager.triggerCharacterTap(member: member) }
                        }
                    }
                }
            } else if let sprite = manager.currentSpriteFrame {
                Image(uiImage: sprite)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 72)
                    .shadow(radius: 4)
                    .onTapGesture { manager.triggerCharacterTap() }
            }
        }
    }
    
    private func turnIconName(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("调头") || lower.contains("掉头") || lower.contains("u-turn") { return "arrow.uturn.left" }
        if lower.contains("稍向右") || lower.contains("右前方") { return "arrow.up.right" }
        if lower.contains("稍向左") || lower.contains("左前方") { return "arrow.up.left" }
        if lower.contains("右") { return "arrow.turn.up.right" }
        if lower.contains("左") { return "arrow.turn.up.left" }
        if lower.contains("出口") { return "arrow.right.to.line" }
        return "arrow.up"
    }
    
    // MARK: - STANDARD COCKPIT COMPONENTS (When Not In Full Screen)
    private var topBezelBar: some View {
        HStack(spacing: 5) {
            Button(action: {
                withAnimation { manager.showMapMode.toggle() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: manager.showMapMode ? "map.fill" : "cup.and.saucer.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(httGold)
                    Text(manager.showMapMode
                         ? tr("地图模式(点切舞台)", "地圖模式(點切舞台)", "Map(Tap Stage)")
                         : tr("舞台模式(点切地图)", "舞台模式(點切地圖)", "Stage(Tap Map)"))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(httCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(httCrimson)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold, lineWidth: 1.5))
            }
            
            Spacer(minLength: 2)
            
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button(action: { manager.language = lang }) {
                        HStack {
                            Text(lang.rawValue)
                            if manager.language == lang { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "globe")
                    Text(manager.language.rawValue)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.14))
                .foregroundColor(httGold)
                .cornerRadius(8)
            }
            
            Button(action: {
                withAnimation { manager.isHUDMirrored.toggle() }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "flip.horizontal.fill")
                    Text(manager.isHUDMirrored ? tr("镜像", "鏡像", "Flip") : "HUD")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(manager.isHUDMirrored ? httGold : Color.white.opacity(0.12))
                .foregroundColor(manager.isHUDMirrored ? .black : httCream)
                .cornerRadius(8)
            }
            
            // RM-500HTT Official Album & Arrow Outfit Button (Never truncates!)
            Button(action: { showAlbumSheet = true }) {
                HStack(spacing: 3) {
                    if let iconImg = manager.getRM500UIImage("rm_btn_icon_on") {
                        Image(uiImage: iconImg)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    Text(tr("相册/车标", "相冊/車標", "Album"))
                        .font(.system(size: 11, weight: .heavy))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.pink.opacity(0.88))
                .foregroundColor(.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold, lineWidth: 1))
            }
        }
    }
    
    private var speedometerCockpit: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(manager.currentSpeedKmh))")
                            .font(.system(size: 46, weight: .black, design: .monospaced))
                            .foregroundColor(manager.isOverspeeding ? .red : Color(red: 0.35, green: 0.98, blue: 0.65))
                            .shadow(color: (manager.isOverspeeding ? Color.red : Color.green).opacity(0.5), radius: 6)
                        
                        Text("km/h")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(httCream.opacity(0.7))
                    }
                    
                    HStack(spacing: 6) {
                        Button(action: { manager.triggerGPSSignalPoorAlert() }) {
                            HStack(spacing: 3) {
                                Image(systemName: manager.isGPSSignalPoor ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                                Text(manager.isGPSSignalPoor
                                     ? tr("GPS弱(点按播报)", "GPS弱(點按播報)", "GPS Weak")
                                     : tr("GPS信号正常", "GPS訊號正常", "GPS OK"))
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(manager.isGPSSignalPoor ? Color.orange.opacity(0.3) : Color.green.opacity(0.18))
                            .foregroundColor(manager.isGPSSignalPoor ? .orange : .green)
                            .cornerRadius(5)
                        }
                        
                        if manager.isOverspeeding {
                            Text(tr("⚠️ 已超速!", "⚠️ 已超速!", "⚠️ OVERSPEED!"))
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    telemetryBadge(icon: "location.north.circle.fill", label: tr("方向", "方向", "DIR"), value: manager.compassDirectionString)
                    telemetryBadge(icon: "road.lanes", label: tr("里程", "里程", "TRIP"), value: String(format: "%.1f km", manager.tripDistanceKm))
                    telemetryBadge(icon: "clock.fill", label: tr("时长", "時長", "TIME"), value: manager.formattedDrivingTime)
                }
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            HStack(spacing: 5) {
                Button(action: { manager.triggerSpeedLimitPrompt() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "speedometer")
                        Text(tr("限速播报:", "限速播報:", "Limit:"))
                    }
                    .font(.caption2.bold())
                    .foregroundColor(httGold)
                }
                
                ForEach([60.0, 80.0, 100.0, 120.0], id: \.self) { limit in
                    Button(action: {
                        if manager.speedLimitKmh == limit {
                            manager.triggerSpeedLimitPrompt()
                        } else {
                            manager.speedLimitKmh = limit
                        }
                    }) {
                        Text("\(Int(limit))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(manager.speedLimitKmh == limit ? httCrimson : Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }
                Spacer()
                Text("\(tr("最高", "最高", "MAX")): \(Int(manager.maxSpeedKmh))")
                    .font(.caption2)
                    .foregroundColor(httGold)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(manager.isOverspeeding ? Color.red : httGold.opacity(0.6), lineWidth: 2)
                )
        )
    }
    
    private func telemetryBadge(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(httGold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(httCream)
        }
    }
    
    private func mainStageOrMapSection(stageWidth: CGFloat, stageHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            if manager.showMapMode {
                ZStack {
                    HTTSmoothMapView(manager: manager)
                        .frame(height: stageHeight)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(httGold, lineWidth: 2))
                    
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Button(action: { showSearchSheet = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(httGold)
                                    Text(manager.destinationName.isEmpty
                                         ? tr("搜索路线...", "搜尋路線...", "Search...")
                                         : manager.destinationName)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.78))
                                .cornerRadius(7)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(httGold.opacity(0.7), lineWidth: 1))
                            }
                            
                            // Demo simulation toggle button (Accessible in compact cockpit mode!)
                            Button(action: {
                                manager.toggleDemoSimulation()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: manager.isDemoSimulating ? "stop.fill" : "play.fill")
                                    Text(manager.isDemoSimulating ? tr("停止", "停止", "Stop") : tr("模拟", "模擬", "Demo"))
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background(manager.isDemoSimulating ? Color.orange : Color.purple.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(7)
                            }
                            
                            // Zoom In [+] / Out [-] in compact mode!
                            Button(action: { manager.zoomMapIn() }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.78))
                                    .foregroundColor(httGold)
                                    .cornerRadius(7)
                            }
                            
                            Button(action: { manager.zoomMapOut() }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.78))
                                    .foregroundColor(httCream)
                                    .cornerRadius(7)
                            }
                            
                            // Fast Recenter Button in compact mode!
                            Button(action: {
                                manager.triggerFastRecenter()
                            }) {
                                Image(systemName: manager.mapTrackingUser ? "location.north.line.fill" : "location")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 5)
                                    .background(manager.mapTrackingUser ? Color.green.opacity(0.85) : Color.black.opacity(0.75))
                                    .foregroundColor(manager.mapTrackingUser ? .black : httGold)
                                    .cornerRadius(7)
                            }
                            
                            // Camera Mode Toggle in compact map (地图动 / 车标动)
                            Button(action: {
                                manager.toggleCameraMode()
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: manager.cameraMode.icon)
                                    Text(manager.cameraMode.shortTitle(manager.language))
                                }
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.82))
                                .foregroundColor(.white)
                                .cornerRadius(7)
                            }
                            
                            // Manual Enlarge Full-Screen Button!
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    manager.isMapEnlarged = true
                                }
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    Text(tr("放大", "放大", "Full"))
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background(httCrimson)
                                .foregroundColor(.white)
                                .cornerRadius(7)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                        
                        if manager.tappedMapCoord != nil {
                            tappedMapPointNavigationCard
                                .padding(.horizontal, 6)
                        }
                        
                        Spacer()
                        
                        // Mascot on map
                        HStack(alignment: .bottom) {
                            if manager.selectedCharacter == .all {
                                HStack(alignment: .bottom, spacing: 1) {
                                    ForEach(AudioPlayerManager.CharacterFilter.fiveIndividuals) { member in
                                        if let frame = manager.allMemberFrames[member.charId] {
                                            Image(uiImage: frame)
                                                .interpolation(.none)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 64)
                                                .shadow(radius: 3)
                                                .onTapGesture { manager.triggerCharacterTap(member: member) }
                                        }
                                    }
                                }
                            } else if let sprite = manager.currentSpriteFrame {
                                Image(uiImage: sprite)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 78)
                                    .shadow(radius: 4)
                                    .onTapGesture { manager.triggerCharacterTap() }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                    }
                }
                .frame(height: stageHeight)
                .clipped()
            } else {
                clubroomStageView(stageWidth: stageWidth, stageHeight: stageHeight)
            }
            
            speechBubbleBox
        }
    }
    
    private func clubroomStageView(stageWidth: CGFloat, stageHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            characterThemeColor(manager.selectedCharacter).opacity(0.35),
                            Color.black.opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: stageHeight)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(httGold, lineWidth: 2))
            
            if let deskImg = manager.deskSpriteFrame {
                Image(uiImage: deskImg)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(height: manager.selectedCharacter == .all ? 92 : 82)
                    .opacity(manager.selectedCharacter == .all ? 0.85 : 0.45)
                    .padding(.bottom, 8)
            }
            
            VStack {
                HStack(spacing: 5) {
                    posePill(title: tr("待机", "待機", "Idle"), state: .idle)
                    posePill(title: tr("散步", "散步", "Walk"), state: .walkRight)
                    posePill(title: tr("招牌动作", "招牌動作", "Dance"), state: .special)
                    posePill(title: tr("顶蛋糕", "頂蛋糕", "Cake"), state: .teaCake)
                    Spacer()
                    Text(manager.isDraggingMascot
                         ? tr("提起挣扎!", "提起掙扎!", "Lifted!")
                         : manager.mascotAction.localizedTitle(manager.language))
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(httCrimson)
                        .foregroundColor(httCream)
                        .cornerRadius(6)
                }
                .padding(.horizontal, 10)
                .padding(.top, 7)
                Spacer()
            }
            
            if manager.selectedCharacter == .all {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(AudioPlayerManager.CharacterFilter.fiveIndividuals) { member in
                        if let frame = manager.allMemberFrames[member.charId] {
                            let isThisDragged = manager.isDraggingMascot && manager.draggedMemberId == member.charId
                            let savedPos = manager.memberPositions[member.charId] ?? .zero
                            VStack(spacing: 0) {
                                Image(uiImage: frame)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 86)
                                Text(member.displayName(manager.language))
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(characterThemeColor(member).opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            .offset(
                                x: savedPos.width + (isThisDragged ? dragOffset.width : (manager.mascotOffsetX * 0.45)),
                                y: savedPos.height + (isThisDragged ? dragOffset.height : 0)
                            )
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        if !manager.isDraggingMascot {
                                            manager.isDraggingMascot = true
                                            manager.draggedMemberId = member.charId
                                            manager.playMascotVoice(for: member)
                                        }
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        let oldPos = manager.memberPositions[member.charId] ?? .zero
                                        let maxBoundX = stageWidth * 0.35
                                        let newX = min(max(oldPos.width + value.translation.width, -maxBoundX), maxBoundX)
                                        let newY = min(max(oldPos.height + value.translation.height, -55), 10)
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                            manager.memberPositions[member.charId] = CGSize(width: newX, height: newY)
                                            manager.isDraggingMascot = false
                                            manager.draggedMemberId = nil
                                            dragOffset = .zero
                                            manager.mascotAction = .idle
                                        }
                                    }
                            )
                            .onTapGesture {
                                manager.triggerCharacterTap(member: member)
                            }
                        }
                    }
                }
                .padding(.bottom, 5)
            } else if let sprite = manager.currentSpriteFrame {
                Image(uiImage: sprite)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 115)
                    .offset(
                        x: manager.mascotOffsetX + (manager.isDraggingMascot ? dragOffset.width : 0),
                        y: manager.mascotOffsetY + (manager.isDraggingMascot ? dragOffset.height : 0)
                    )
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if !manager.isDraggingMascot {
                                    manager.isDraggingMascot = true
                                    manager.playMascotVoice()
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                let maxBoundX = stageWidth * 0.38
                                let newX = min(max(manager.mascotOffsetX + value.translation.width, -maxBoundX), maxBoundX)
                                let newY = min(max(manager.mascotOffsetY + value.translation.height, -55), 10)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                    manager.mascotOffsetX = newX
                                    manager.mascotOffsetY = newY
                                    manager.isDraggingMascot = false
                                    dragOffset = .zero
                                    manager.mascotAction = .idle
                                }
                            }
                    )
                    .onTapGesture {
                        manager.triggerCharacterTap()
                    }
                    .padding(.bottom, 4)
            }
        }
        .frame(height: stageHeight)
        .clipped()
    }
    
    private var speechBubbleBox: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(manager.selectedCharacter.roleTag(manager.language))
                        .font(.caption2.bold())
                        .foregroundColor(httCrimson)
                    Spacer()
                    Button(action: {
                        withAnimation { manager.resetPositions() }
                    }) {
                        Text(tr("位置归位", "位置歸位", "Reset Pos"))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(httCrimson.opacity(0.15))
                            .foregroundColor(httCrimson)
                            .cornerRadius(4)
                    }
                }
                
                Text(manager.currentSpeechBubble)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black.opacity(0.88))
                    .lineLimit(2)
            }
            
            if manager.isPlaying {
                Button(action: { manager.stop() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(httCream)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(httGold, lineWidth: 2))
    }
    
    private func posePill(title: String, state: MascotActionState) -> some View {
        Button(action: {
            manager.mascotAction = state
            manager.playMascotVoice()
        }) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(manager.mascotAction == state ? httGold : Color.black.opacity(0.55))
                .foregroundColor(manager.mascotAction == state ? .black : httCream)
                .cornerRadius(6)
        }
    }
    
    private var characterSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(AudioPlayerManager.CharacterFilter.allCases) { char in
                    Button(action: {
                        manager.selectedCharacter = char
                        manager.resetPositions()
                        manager.triggerCharacterTap(member: char)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: char == .all ? "person.3.fill" : "person.fill")
                                .font(.system(size: 10))
                            Text(char.displayName(manager.language))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            manager.selectedCharacter == char
                            ? characterThemeColor(char)
                            : Color.white.opacity(0.1)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(manager.selectedCharacter == char ? httGold : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
        }
    }
    
    private var utilityControlGrid: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                tacticalButton(
                    title: tr("出发进行", "出發進行", "Depart"),
                    subtitle: tr("点火出发音", "點火出發音", "Start Guide"),
                    icon: "flag.checkered.2.crossed",
                    color: httCrimson
                ) {
                    manager.triggerDepartureGreeting()
                }
                
                tacticalButton(
                    title: tr("多人相声", "雙人相聲", "Banter"),
                    subtitle: tr("多人对话彩蛋", "多人對話彩蛋", "Group Talk"),
                    icon: "bubble.left.and.bubble.right.fill",
                    color: Color(red: 0.58, green: 0.32, blue: 0.78)
                ) {
                    manager.triggerBanter()
                }
                
                tacticalButton(
                    title: tr("顶蛋糕下午茶", "頂蛋糕下午茶", "Tea Time"),
                    subtitle: tr("桌宠蛋糕休息", "桌寵蛋糕休息", "Cake Break"),
                    icon: "birthday.cake.fill",
                    color: Color(red: 0.82, green: 0.56, blue: 0.18)
                ) {
                    manager.triggerTeaTimeReminder()
                }
            }
            
            HStack(spacing: 7) {
                HStack(spacing: 6) {
                    Button(action: { manager.toggleCruiseMode() }) {
                        HStack(spacing: 6) {
                            Image(systemName: manager.isCruiseModeActive ? "timer" : "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(manager.isCruiseModeActive ? .green : httGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manager.isCruiseModeActive
                                     ? "\(tr("巡航中", "巡航中", "Cruise")): \(manager.formattedCruiseCountdown)"
                                     : tr("开启巡航陪伴", "開啟巡航陪伴", "Start Cruise"))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text(tr("后台保活·定时播报", "後台保活·定時播報", "Background Active"))
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                    }
                    
                    Spacer(minLength: 2)
                    
                    Menu {
                        ForEach([1.0, 3.0, 5.0, 10.0, 15.0, 30.0], id: \.self) { mins in
                            Button(action: { manager.cruiseIntervalMinutes = mins }) {
                                HStack {
                                    Text("\(Int(mins)) \(tr("分钟", "分鐘", "min"))")
                                    if manager.cruiseIntervalMinutes == mins {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("\(Int(manager.cruiseIntervalMinutes))m ▾")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.35))
                            .foregroundColor(httGold)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(manager.isCruiseModeActive ? Color.green.opacity(0.28) : Color.white.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(manager.isCruiseModeActive ? Color.green : httGold.opacity(0.4), lineWidth: 1.5)
                )
                
                Button(action: { showSearchSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "map.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("目的地路线导航", "目的地路線導航", "Route Navi"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text(tr("真实路口触发轻音指路", "真實路口觸發輕音指路", "Turn-by-Turn Voice"))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.1, green: 0.4, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(httGold, lineWidth: 1.5)
                    )
                }
            }
        }
    }
    
    // MARK: - Interactive Tapped Map Point Card (Click Any Place on Map to Navigate!)
    private var tappedMapPointNavigationCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(manager.tappedMapTitle)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if manager.isReverseGeocoding {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                Text(manager.tappedMapAddress)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(httCream.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
            
            Button(action: {
                manager.startNavigationToTappedPoint()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill")
                    Text(tr("去这里", "去這裡", "Go Here"))
                }
                .font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(httCrimson)
                .foregroundColor(.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold, lineWidth: 1))
            }
            
            Button(action: {
                withAnimation { manager.dismissTappedPoint() }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.88))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange, lineWidth: 1.5))
    }

    // MARK: - Beautified RM-500HTT Long-Press Outfit Picker Modal Overlay
    private var outfitQuickPickerModalOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        showOutfitPopup = false
                    }
                }
            
            VStack(spacing: 12) {
                // Header with RM-500HTT Authentic Notebook & Tea Cup aesthetics
                HStack {
                    if let cup = manager.getRM500UIImage("rm_teacup") {
                        Image(uiImage: cup)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 24)
                    }
                    Text(tr("RM-500HTT 导航车标衣橱", "RM-500HTT 導航車標衣櫥", "RM-500HTT Arrow Wardrobe"))
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(httGold)
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showOutfitPopup = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(httCream)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                
                // Live Character Arrow Preview Banner
                HStack(spacing: 18) {
                    if let arrowImg = manager.getRM500NavigationArrowFrame(mapCameraHeading: manager.headingDegrees) {
                        Image(uiImage: arrowImg)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 68, height: 86)
                            .shadow(color: .black, radius: 4)
                    } else {
                        Image(uiImage: HTTSmoothMapView.Coordinator.createNavigationArrowImage())
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.selectedCharacter.displayName(manager.language))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(tr("当前车标", "當前車標", "Current")): \(manager.arrowOutfit.title(manager.language))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(httGold)
                        Text(tr("点选下方造型立即更换自车导航标", "點選下方造型立即更換自車導航標", "Tap any outfit below to switch"))
                            .font(.system(size: 10))
                            .foregroundColor(httCream.opacity(0.75))
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal, 14)
                
                // 2-Column Beautified Grid of All Outfits
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(RM500ArrowOutfit.allCases) { outfit in
                        Button(action: {
                            manager.arrowOutfit = outfit
                            manager.playRandomCharacterGreeting()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                showOutfitPopup = false
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: outfit.icon)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(manager.arrowOutfit == outfit ? .black : httGold)
                                    .frame(width: 30, height: 30)
                                    .background(manager.arrowOutfit == outfit ? httGold : Color.black.opacity(0.5))
                                    .cornerRadius(8)
                                
                                Text(outfit.title(manager.language))
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(manager.arrowOutfit == outfit ? httGold : .white)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if manager.arrowOutfit == outfit {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(httGold)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(manager.arrowOutfit == outfit ? httCrimson.opacity(0.88) : Color.black.opacity(0.65))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(manager.arrowOutfit == outfit ? httGold : Color.white.opacity(0.18), lineWidth: 1.5)
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: 380)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.16, green: 0.12, blue: 0.15).opacity(0.96))
                    if let themeBG = manager.getCurrentThemeBackground() {
                        Image(uiImage: themeBG)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.22)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(httGold, lineWidth: 2.5)
                }
            )
            .shadow(color: .black.opacity(0.6), radius: 16)
            .padding(20)
        }
    }

    // MARK: - Portrait & Landscape Bottom RM-500HTT Quick Feature Dock
    private var portraitBottomCompanionDock: some View {
        VStack(spacing: 7) {
            // Row 1: 4 Travel Modes Direct Switcher (Car / e-Bike / Walk / Transit)
            HStack(spacing: 5) {
                ForEach(NavigationTravelMode.allCases) { mode in
                    Button(action: {
                        manager.travelMode = mode
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10, weight: .bold))
                            Text(mode.title(manager.language))
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(manager.travelMode == mode ? httCrimson : Color.black.opacity(0.65))
                        .foregroundColor(manager.travelMode == mode ? .white : httCream)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(manager.travelMode == mode ? httGold : Color.white.opacity(0.18), lineWidth: 1.2)
                        )
                    }
                }
            }
            
            // Row 2: RM-500HTT Outfit (Tap=Cycle, LongPress=Wardrobe) + Camera Mode (地图动/车标动) + Birthday Special + Trip Reset
            HStack(spacing: 6) {
                // Outfit Button: Tap to cycle, Long-press to open Beautified Wardrobe Popup!
                HStack(spacing: 5) {
                    Image(systemName: manager.arrowOutfit.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(httGold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("车标换装(长按选)", "車標換裝(長按選)", "Outfit(Hold)"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(manager.arrowOutfit.title(manager.language))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(httGold)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.75))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold.opacity(0.7), lineWidth: 1.2))
                .onTapGesture {
                    manager.cycleNextArrowOutfit()
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        showOutfitPopup = true
                    }
                }
                
                // Camera Mode Button: Switch between 地图动 (Heading Up) and 车标动 (North Up)
                Button(action: {
                    manager.toggleCameraMode()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: manager.cameraMode.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("导航视角模式", "導航視角模式", "Nav View"))
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(manager.cameraMode.title(manager.language))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.cyan)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.6), lineWidth: 1.2))
                }
                
                // Birthday Special Voice Button
                Button(action: {
                    manager.triggerBirthdaySpecialVoice()
                }) {
                    VStack(spacing: 2) {
                        if let giftImg = manager.getRM500UIImage("rm_gift_yui") {
                            Image(uiImage: giftImg)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.pink)
                        }
                        Text(tr("特典音", "特典音", "Gift"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.72, green: 0.22, blue: 0.48).opacity(0.88))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold.opacity(0.65), lineWidth: 1.2))
                }
            }
        }
    }

    private func tacticalButton(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(httCream)
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(httCream.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(color)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(httGold.opacity(0.8), lineWidth: 1.5)
            )
        }
    }
    
    private func characterThemeColor(_ char: AudioPlayerManager.CharacterFilter) -> Color {
        switch char {
        case .yui: return Color(red: 0.90, green: 0.32, blue: 0.38)
        case .mio: return Color(red: 0.25, green: 0.48, blue: 0.82)
        case .ritsu: return Color(red: 0.85, green: 0.58, blue: 0.15)
        case .mugi: return Color(red: 0.78, green: 0.52, blue: 0.68)
        case .azusa: return Color(red: 0.22, green: 0.65, blue: 0.52)
        case .all: return httCrimson
        }
    }
}

// MARK: - Multi-Modal Destination Search & Route Sheet (Pinyin-Safe & 20+ Amap POI Suggestions)
struct DestinationSearchSheetView: View {
    // NOT @ObservedObject on manager so 60fps sprite/GPS ticks never re-render this sheet or interrupt Pinyin typing!
    let manager: AudioPlayerManager
    @StateObject private var searchEngine = PlaceSearchEngine()
    @Environment(\.dismiss) var dismiss
    @State private var queryText: String = ""
    @State private var selectedMode: NavigationTravelMode = AudioPlayerManager.shared.travelMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                // 4 Travel Modes Switcher at Top of Search Sheet
                HStack(spacing: 8) {
                    ForEach(NavigationTravelMode.allCases) { mode in
                        Button(action: {
                            selectedMode = mode
                            manager.travelMode = mode
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                Text(mode.title(manager.language))
                            }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selectedMode == mode ? Color.red : Color(UIColor.tertiarySystemFill))
                            .foregroundColor(selectedMode == mode ? .white : .primary)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                
                // Driving Highway Preference Selector in Search Sheet
                if selectedMode == .driving {
                    HStack(spacing: 8) {
                        ForEach(RouteStrategyPreference.allCases) { pref in
                            Button(action: {
                                manager.routePreference = pref
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: pref.icon)
                                    Text(pref.title(manager.language))
                                }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(manager.routePreference == pref ? Color.orange : Color(UIColor.tertiarySystemFill))
                                .foregroundColor(manager.routePreference == pref ? .white : .primary)
                                .cornerRadius(7)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Pinyin-Safe Native Search Bar + Search Button
                HStack(spacing: 4) {
                    NativePinyinSearchBar(
                        text: $queryText,
                        placeholder: manager.language == .en ? "Search station, mall, road or city..." : "输入目的地（如：广州南站、罗湖口岸、大厦）...",
                        onTypingSettled: { settledText in
                            searchEngine.updateQueryFragment(settledText, center: manager.userCoordinate)
                            searchEngine.performFullSearch(query: settledText, center: manager.userCoordinate)
                        },
                        onSearchButtonClicked: { finalQuery in
                            searchEngine.updateQueryFragment(finalQuery, center: manager.userCoordinate)
                            searchEngine.performFullSearch(query: finalQuery, center: manager.userCoordinate)
                        }
                    )
                    .frame(height: 44)
                    
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        searchEngine.updateQueryFragment(queryText, center: manager.userCoordinate)
                        searchEngine.performFullSearch(query: queryText, center: manager.userCoordinate)
                    }) {
                        Text(manager.language == .en ? "Search" : "搜索")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.trailing, 12)
                }
                
                // Demo Navigation Test Button
                Button(action: {
                    dismiss()
                    manager.showMapMode = true
                    manager.startDemoSimulation()
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.orange)
                        Text(manager.language == .en
                             ? "Test 1-Click Simulation (Listen to Full Turn Guidance Indoors)"
                             : "室内一键测试：模拟路线指路（完整听转向原声）")
                            .font(.caption.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.12))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                if searchEngine.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在检索全城及周边详细地点...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // Combined List: Direct POI MapItems (with Distance!) + Rich Autocomplete Sub-entrances (East/West Plaza, Parking, Metro, etc.)
                List {
                    if !searchEngine.mapItems.isEmpty {
                        Section(header: Text("精准地点结果 (\(searchEngine.mapItems.count) 个)")) {
                            ForEach(searchEngine.mapItems, id: \.self) { item in
                                Button(action: {
                                    manager.travelMode = selectedMode
                                    manager.showMapMode = true
                                    manager.startRouteGuidance(to: item)
                                    dismiss()
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedMode.icon)
                                            .font(.title3)
                                            .foregroundColor(.red)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name ?? "未知地点")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            Text(detailedAddress(for: item.placemark))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text(distanceString(to: item.placemark.coordinate))
                                                .font(.caption2.bold())
                                                .foregroundColor(.secondary)
                                            Text(manager.language == .en ? "Go" : "去这里")
                                                .font(.caption.bold())
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.red)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if !searchEngine.completions.isEmpty {
                        Section(header: Text("全城联想与详细出入口 (\(searchEngine.completions.count) 个)")) {
                            ForEach(searchEngine.completions, id: \.self) { comp in
                                Button(action: {
                                    manager.travelMode = selectedMode
                                    searchEngine.resolveAndStartNavigation(for: comp, manager: manager) {
                                        dismiss()
                                    }
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.title3)
                                            .foregroundColor(.orange)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(comp.title)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            if !comp.subtitle.isEmpty {
                                                Text(comp.subtitle)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text(manager.language == .en ? "Navigate" : "开始导航")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.red.opacity(0.9))
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(manager.language == .en ? "Route Planner" : "高德/MapKit 智能路线搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Close" : "关闭") { dismiss() }
                }
            }
        }
    }
    
    private func detailedAddress(for pm: MKPlacemark) -> String {
        var parts: [String] = []
        if let city = pm.locality { parts.append(city) }
        if let sub = pm.subLocality { parts.append(sub) }
        if let road = pm.thoroughfare { parts.append(road) }
        if let num = pm.subThoroughfare { parts.append(num) }
        if parts.isEmpty { return pm.title ?? "" }
        return parts.joined(separator: " · ")
    }
    
    private func distanceString(to coord: CLLocationCoordinate2D) -> String {
        let uLoc = CLLocation(latitude: manager.userCoordinate.latitude, longitude: manager.userCoordinate.longitude)
        let dLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distKm = uLoc.distance(from: dLoc) / 1000.0
        if distKm < 1.0 {
            return String(format: "%.0f m", distKm * 1000.0)
        } else {
            return String(format: "%.1f km", distKm)
        }
    }
}

// MARK: - Verified Character Soundboard
struct SoundboardSheetView: View {
    @ObservedObject var manager = AudioPlayerManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedSection: Int = 0
    
    private var sections: [(title: String, ids: [Int])] {
        let lang = manager.language
        return [
            ("\(AudioPlayerManager.CharacterFilter.yui.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.yui.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.mio.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.mio.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.ritsu.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.ritsu.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.mugi.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.mugi.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.azusa.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.azusa.verifiedVoiceIds),
            (lang == .en ? "Bonus & Birthdays (11)" : "全收集与生日彩蛋 (11)", Array(1112...1122))
        ]
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<sections.count, id: \.self) { idx in
                            Button(action: { selectedSection = idx }) {
                                Text(sections[idx].title)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedSection == idx ? Color.red : Color.gray.opacity(0.2))
                                    .foregroundColor(selectedSection == idx ? .white : .primary)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }
                
                List(sections[selectedSection].ids, id: \.self) { voiceId in
                    Button(action: { manager.playVoice(id: voiceId) }) {
                        HStack {
                            Image(systemName: manager.currentPlayingId == voiceId && manager.isPlaying ? "waveform.circle.fill" : "play.circle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text("[\(manager.characterForVoiceId(voiceId).displayName(manager.language))] #\(voiceId)")
                                    .font(.subheadline.bold())
                                Text("VOICE_DB-\(String(format: "%010d", voiceId))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if manager.currentPlayingId == voiceId && manager.isPlaying {
                                Text(manager.language == .en ? "Playing" : "播放中")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(manager.language == .en ? "Voice DB" : "已校准纯享角色语音库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Done" : "完成") { dismiss() }
                }
            }
        }
    }
}


// MARK: - RM-500HTT Official Memorial Album (36 Episode CGs) & Vehicle Arrow Outfit Selector
struct RM500AlbumAndOutfitSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: Int = 0
    @State private var selectedCGIndex: Int = 1
    
    private let episodeTitles: [String] = [
        "けいおん！ #1 廃部！", "けいおん！ #2 楽器！", "けいおん！ #3 特訓！", "けいおん！ #4 合宿！",
        "けいおん！ #5 顧問！", "けいおん！ #6 学園祭！", "けいおん！ #7 クリスマス！", "けいおん！ #8 新歓！",
        "けいおん！ #9 新入部員！", "けいおん！ #10 また合宿！", "けいおん！ #11 ピンチ！", "けいおん！ 最終回 軽音！",
        "けいおん！！ #1 高3！", "けいおん！！ #2 整頓！", "けいおん！！ #3 ドラマー！", "けいおん！！ #4 修学旅行！",
        "けいおん！！ #5 お留守番！", "けいおん！！ #6 梅雨！", "けいおん！！ #7 お茶会！", "けいおん！！ #8 進路！",
        "けいおん！！ #9 期末試験！", "けいおん！！ #10 先生！", "けいおん！！ #11 暑い！", "けいおん！！ #12 夏フェス！",
        "けいおん！！ #13 残暑見舞い！", "けいおん！！ #14 夏期講習！", "けいおん！！ #15 マラソン大会！", "けいおん！！ #16 先輩！",
        "けいおん！！ #17 部室がない！", "けいおん！！ #18 主役！", "けいおん！！ #19 ロミジュリ！", "けいおん！！ #20 またまた学園祭！",
        "けいおん！！ #21 卒業アルバム！", "けいおん！！ #22 受験！", "けいおん！！ #23 放課後！", "けいおん！！ 最終回 卒業式！"
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Picker("Mode", selection: $selectedTab) {
                    Text("RM-500HTT 导航箭头换装").tag(0)
                    Text("放課後ティータイム 纪念相册 (36枚)").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                if selectedTab == 0 {
                    ScrollView {
                        VStack(spacing: 14) {
                            // Live Preview Card of Current RM-500HTT Navigation Arrow
                            VStack(spacing: 8) {
                                Text("当前地图自车导航箭头预览")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 24) {
                                    if let arrowImg = manager.getRM500NavigationArrowFrame(mapCameraHeading: manager.headingDegrees) {
                                        Image(uiImage: arrowImg)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 90, height: 115)
                                    } else {
                                        Image(uiImage: HTTSmoothMapView.Coordinator.createNavigationArrowImage())
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 70, height: 70)
                                    }
                                    
                                    if let stageIcon = manager.getRM500StageIcon(for: manager.selectedCharacter) {
                                        Image(uiImage: stageIcon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 95, height: 95)
                                            .cornerRadius(12)
                                    }
                                }
                                
                                Text("\(manager.selectedCharacter.displayName(manager.language)) · \(manager.arrowOutfit.title(manager.language))")
                                    .font(.headline.bold())
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                            .padding(.horizontal)
                            
                            // Toggle for RM-500HTT Starry Cockpit Background Skin
                            Toggle(isOn: $manager.useRM500ThemeSkin) {
                                HStack {
                                    Image(systemName: "sparkles.rectangle.stack.fill")
                                        .foregroundColor(.pink)
                                    VStack(alignment: .leading) {
                                        Text("启用 RM-500HTT 原版角色星光斜纹背景皮肤")
                                            .font(.subheadline.bold())
                                        Text("随所选角色自动切换红/蓝/黄/粉/绿专属星光底图")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            
                            // Outfit Grid
                            VStack(alignment: .leading, spacing: 8) {
                                Text("选择 RM-500HTT 原版导航自车箭头服装")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal)
                                
                                ForEach(RM500ArrowOutfit.allCases) { outfit in
                                    Button(action: {
                                        manager.arrowOutfit = outfit
                                        manager.playRandomCharacterGreeting()
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: outfit.icon)
                                                .font(.title3)
                                                .foregroundColor(.white)
                                                .frame(width: 38, height: 38)
                                                .background(manager.arrowOutfit == outfit ? Color.red : Color.gray)
                                                .cornerRadius(8)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(outfit.title(manager.language))
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.primary)
                                                Text(outfit == .tonchan ? "轻音部宠物猪鼻龟专属游泳导航车标" : "支持 12 方向精准转向与行车迈步动画")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            if manager.arrowOutfit == outfit {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .font(.title3)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .cornerRadius(12)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                } else {
                    // Tab 1: Official RM-500HTT 36 Memorial Album CGs
                    ScrollView {
                        VStack(spacing: 12) {
                            if let logo = manager.getRM500UIImage("rm_album_logo") {
                                Image(uiImage: logo)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 90)
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                            }
                            
                            // Large Selected CG Viewer
                            if let cgImg = manager.getRM500UIImage(String(format: "rm_cg_%02d", selectedCGIndex)) {
                                VStack(spacing: 6) {
                                    Image(uiImage: cgImg)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                    
                                    HStack {
                                        Button(action: {
                                            selectedCGIndex = selectedCGIndex > 1 ? selectedCGIndex - 1 : 36
                                        }) {
                                            Label("上一张", systemImage: "chevron.left.circle.fill")
                                                .font(.caption.bold())
                                        }
                                        Spacer()
                                        Text("\(selectedCGIndex) / 36 · \(episodeTitles[selectedCGIndex - 1])")
                                            .font(.caption.bold())
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Button(action: {
                                            selectedCGIndex = selectedCGIndex < 36 ? selectedCGIndex + 1 : 1
                                        }) {
                                            Label("下一张", systemImage: "chevron.right.circle.fill")
                                                .font(.caption.bold())
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(14)
                                .padding(.horizontal)
                            }
                            
                            // Thumbnail Grid of all 36 CGs
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(1...36, id: \.self) { idx in
                                    Button(action: {
                                        selectedCGIndex = idx
                                        manager.playRandomCharacterGreeting()
                                    }) {
                                        VStack(spacing: 3) {
                                            if let thumb = manager.getRM500UIImage(String(format: "rm_cg_%02d", idx)) {
                                                Image(uiImage: thumb)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .cornerRadius(6)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(selectedCGIndex == idx ? Color.red : Color.clear, lineWidth: 2.5)
                                                    )
                                            }
                                            Text(episodeTitles[idx - 1])
                                                .font(.system(size: 9, weight: .bold))
                                                .lineLimit(1)
                                                .foregroundColor(.primary)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("RM-500HTT 典藏中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
