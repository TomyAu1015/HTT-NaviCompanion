import SwiftUI
import MapKit

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
        mapView.showsCompass = true
        mapView.showsTraffic = true
        mapView.showsBuildings = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didPanMap(_:)))
        panGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didPinchMap(_:)))
        pinchGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(pinchGesture)
        
        let region = MKCoordinateRegion(
            center: manager.userCoordinate,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        mapView.setRegion(region, animated: false)
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        if context.coordinator.lastRoute !== manager.activeRoute {
            context.coordinator.lastRoute = manager.activeRoute
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
                let rect = route.polyline.boundingMapRect
                mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 90, right: 40), animated: false)
                
                // Immediately align camera to user vehicle
                let camera = MKMapCamera(
                    lookingAtCenter: manager.userCoordinate,
                    fromDistance: manager.travelMode == .walking ? 400 : 550,
                    pitch: 45,
                    heading: manager.headingDegrees
                )
                UIView.animate(withDuration: 0.32, delay: 0.05, options: [.curveEaseOut]) {
                    mapView.camera = camera
                }
            }
        }
        
        // Fast Recenter Action Triggered! (Snaps back to user in 0.28s without slow lag)
        if context.coordinator.lastRecenterTrigger != manager.recenterTrigger {
            context.coordinator.lastRecenterTrigger = manager.recenterTrigger
            context.coordinator.isUserInteracting = false
            let camera = MKMapCamera(
                lookingAtCenter: manager.userCoordinate,
                fromDistance: manager.travelMode == .walking ? 400 : 550,
                pitch: 48,
                heading: manager.headingDegrees
            )
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
                mapView.camera = camera
            }
        } else if manager.mapTrackingUser && !context.coordinator.isUserInteracting {
            let camera = MKMapCamera(
                lookingAtCenter: manager.userCoordinate,
                fromDistance: manager.travelMode == .walking ? 400 : 650,
                pitch: 48,
                heading: manager.headingDegrees
            )
            mapView.setCamera(camera, animated: true)
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: HTTSmoothMapView
        var lastRoute: MKRoute? = nil
        var isUserInteracting: Bool = false
        var lastRecenterTrigger: Int = 0
        
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    self.isUserInteracting = false
                }
            }
        }
        
        @objc func didPinchMap(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed {
                isUserInteracting = true
                if parent.manager.mapTrackingUser {
                    DispatchQueue.main.async {
                        self.parent.manager.mapTrackingUser = false
                    }
                }
            } else if gesture.state == .ended || gesture.state == .cancelled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    self.isUserInteracting = false
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let loc = userLocation.location, !parent.manager.isDemoSimulating else { return }
            DispatchQueue.main.async {
                // userLocation.coordinate on MKMapView in China is natively aligned with the blue dot
                self.parent.manager.userCoordinate = userLocation.coordinate
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
                    // High-contrast vibrant yellow (easily distinguished from green expressway/parks)
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
                httDarkPanel.ignoresSafeArea()
                
                // CONDITIONAL 1: Prominent Enlarged Full-Screen Navigation View
                if manager.isMapEnlarged {
                    enlargedNavigationHUDView(geo: geo, isLandscape: isLandscape)
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                } else {
                    // CONDITIONAL 2: Standard Classic Cockpit View
                    if isLandscape {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 8) {
                                topBezelBar
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(spacing: 8) {
                                        speedometerCockpit
                                        utilityControlGrid
                                    }
                                    .frame(width: geo.size.width * 0.45)
                                    
                                    VStack(spacing: 8) {
                                        mainStageOrMapSection(stageWidth: geo.size.width * 0.49, stageHeight: 195)
                                        characterSelectorStrip
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                        .onAppear { manager.stageWalkBound = 95.0 }
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                topBezelBar
                                speedometerCockpit
                                mainStageOrMapSection(stageWidth: geo.size.width - 24, stageHeight: 210)
                                characterSelectorStrip
                                utilityControlGrid
                                Spacer(minLength: 4)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        }
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                        .onAppear { manager.stageWalkBound = 65.0 }
                    }
                }
            }
            .onChange(of: isLandscape) { newVal in
                manager.stageWalkBound = newVal ? 95.0 : 65.0
            }
        }
        .sheet(isPresented: $showSoundboardSheet) {
            SoundboardSheetView(manager: manager)
        }
        .sheet(isPresented: $showSearchSheet) {
            DestinationSearchSheetView(manager: manager)
        }
    }
    
    // MARK: - ENLARGED FULL-SCREEN NAVIGATION HUD
    private func enlargedNavigationHUDView(geo: GeometryProxy, isLandscape: Bool) -> some View {
        ZStack {
            // 1. Full Screen 3D Navigation Map
            HTTSmoothMapView(manager: manager)
                .ignoresSafeArea()
            
            // 2. Overlays
            VStack(spacing: 6) {
                // Top Navigation Guidance Card
                topNavigationBannerCard
                    .padding(.horizontal, 12)
                    .padding(.top, isLandscape ? 4 : 44)
                
                // 4 Travel Modes Quick Switcher Bar (Car / e-Bike / Walk / Transit)
                travelModeSelectorBar
                    .padding(.horizontal, 12)
                
                Spacer()
                
                // Bottom Floating Control Island (Speedometer + Mascot Stage + Recenter + Exit)
                bottomEnlargedFloatingIsland(isLandscape: isLandscape)
                    .padding(.horizontal, 12)
                    .padding(.bottom, isLandscape ? 8 : 24)
            }
        }
    }
    
    // Top Turn-by-Turn Instruction Card
    private var topNavigationBannerCard: some View {
        HStack(spacing: 12) {
            // Maneuver Turn Arrow
            ZStack {
                Circle()
                    .fill(httCrimson)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(httGold, lineWidth: 2))
                
                Image(systemName: turnIconName(for: manager.currentStepInstruction))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(httCream)
            }
            
            // Instruction Text & Distance
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
            
            // Distance Countdown Badge
            if manager.distanceToNextStepMeters > 0 {
                VStack(spacing: 1) {
                    Text("\(Int(manager.distanceToNextStepMeters))")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(httGold)
                    Text("米 (m)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(httCream.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
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
    
    // 4 Travel Modes Switcher Bar in Enlarged Navigation View
    private var travelModeSelectorBar: some View {
        HStack(spacing: 8) {
            ForEach(NavigationTravelMode.allCases) { mode in
                Button(action: {
                    withAnimation {
                        manager.travelMode = mode
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11))
                        Text(mode.title(manager.language))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        manager.travelMode == mode
                        ? httCrimson
                        : Color.black.opacity(0.65)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(manager.travelMode == mode ? httGold : Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            Spacer()
            
            // Re-center onto User Location Button (Fast Instant Recenter)
            Button(action: {
                manager.triggerFastRecenter()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: manager.mapTrackingUser ? "location.north.line.fill" : "location")
                    Text(manager.mapTrackingUser ? tr("跟车中", "跟車中", "Locked") : tr("回中跟车", "回中跟車", "Recenter"))
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(manager.mapTrackingUser ? Color.green.opacity(0.85) : Color.black.opacity(0.75))
                .foregroundColor(manager.mapTrackingUser ? .black : httGold)
                .cornerRadius(8)
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
        HStack(spacing: 6) {
            Button(action: {
                withAnimation { manager.showMapMode.toggle() }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: manager.showMapMode ? "map.fill" : "cup.and.saucer.fill")
                        .foregroundColor(httGold)
                    Text(manager.showMapMode
                         ? tr("地图模式(点切舞台)", "地圖模式(點切舞台)", "Map Mode")
                         : tr("舞台模式(点切地图)", "舞台模式(點切地圖)", "Stage Mode"))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(httCream)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(httCrimson)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold, lineWidth: 1.5))
            }
            
            Spacer()
            
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
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                    Text(manager.language.rawValue)
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.14))
                .foregroundColor(httGold)
                .cornerRadius(8)
            }
            
            Button(action: {
                withAnimation { manager.isHUDMirrored.toggle() }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "flip.horizontal.fill")
                    Text(manager.isHUDMirrored ? tr("镜像中", "鏡像中", "Mirrored") : "HUD")
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(manager.isHUDMirrored ? httGold : Color.white.opacity(0.12))
                .foregroundColor(manager.isHUDMirrored ? .black : httCream)
                .cornerRadius(8)
            }
            
            Button(action: { showSoundboardSheet = true }) {
                HStack(spacing: 3) {
                    Image(systemName: "music.note.list")
                    Text(tr("语音库", "語音庫", "Voices"))
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .foregroundColor(httCream)
                .cornerRadius(8)
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
                    title: tr("出発進行", "出發進行", "Depart"),
                    subtitle: tr("点火出发音", "點火出發音", "Start Guide"),
                    icon: "flag.checkered.2.crossed",
                    color: httCrimson
                ) {
                    manager.triggerDepartureGreeting()
                }
                
                tacticalButton(
                    title: tr("掛け合い", "雙人相聲", "Banter"),
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

// MARK: - Multi-Modal Destination Search & Route Sheet
struct DestinationSearchSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var queryText: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                // 4 Travel Modes Switcher at Top of Search Sheet
                HStack(spacing: 8) {
                    ForEach(NavigationTravelMode.allCases) { mode in
                        Button(action: { manager.travelMode = mode }) {
                            HStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                Text(mode.title(manager.language))
                            }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(manager.travelMode == mode ? Color.red : Color(UIColor.tertiarySystemFill))
                            .foregroundColor(manager.travelMode == mode ? .white : .primary)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(
                        manager.language == .en ? "Enter destination, station or road..." : "输入目的地、口岸、商圈或路名...",
                        text: $queryText,
                        onCommit: { manager.searchPlaces(query: queryText) }
                    )
                    .textFieldStyle(.plain)
                    
                    if !queryText.isEmpty {
                        Button(action: { queryText = ""; manager.searchResults = [] }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: { manager.searchPlaces(query: queryText) }) {
                        Text(manager.language == .en ? "Search" : "搜索")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(10)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                
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
                
                if manager.isSearching {
                    ProgressView("Searching...")
                        .padding()
                }
                
                List(manager.searchResults, id: \.self) { item in
                    Button(action: {
                        manager.showMapMode = true
                        manager.startRouteGuidance(to: item)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: manager.travelMode.icon)
                                .font(.title3)
                                .foregroundColor(.red)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name ?? "未知地点")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(item.placemark.title ?? "")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(manager.language == .en ? "Go" : "开始导航")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                }
            }
            .navigationTitle(manager.language == .en ? "Route Planner" : "出行路线规划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Close" : "关闭") { dismiss() }
                }
            }
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
