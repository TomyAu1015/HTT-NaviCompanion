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

// MARK: - Authentic GaoDe Map Multi-Layer Route Renderer (高德同款：双边描边 + 内部白色导向双箭头 + 蓝/绿/黄/红路况分色)
class GaoDeArrowRouteRenderer: MKPolylineRenderer {
    var outerBorderColor: UIColor = UIColor(red: 0.0, green: 0.45, blue: 0.22, alpha: 1.0)
    var mainFillColor: UIColor = UIColor(red: 0.0, green: 0.78, blue: 0.36, alpha: 1.0)
    var drawDirectionChevrons: Bool = true
    var isAlternateRoute: Bool = false
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let path = self.path else { return }
        let baseWidth = (self.lineWidth > 0 ? self.lineWidth : 10.0) / zoomScale
        
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // 1. Outer Dark Border (Creates distinct dual-carriageway road separation!)
        context.addPath(path)
        context.setStrokeColor(outerBorderColor.cgColor)
        context.setLineWidth(baseWidth * 1.34)
        context.strokePath()
        
        // 2. Main Inner Route Line (Vivid GaoDe Blue / Traffic Green / Yellow / Red)
        context.addPath(path)
        context.setStrokeColor(mainFillColor.cgColor)
        context.setLineWidth(baseWidth)
        context.strokePath()
        
        // 3. White Directional Chevrons `> > >` along the route (Matches GaoDe screenshot 1 & 2!)
        if drawDirectionChevrons && !isAlternateRoute {
            let pts = polyline.points()
            let ptCount = polyline.pointCount
            if ptCount > 1 {
                let stepPixelDist = Double(baseWidth * 3.8)
                var accumulated = 0.0
                
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
                context.setLineWidth(baseWidth * 0.24)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                
                for i in 0..<(ptCount - 1) {
                    let p1 = point(for: pts[i])
                    let p2 = point(for: pts[i + 1])
                    let dx = Double(p2.x - p1.x)
                    let dy = Double(p2.y - p1.y)
                    let segLen = hypot(dx, dy)
                    if segLen < 1e-4 { continue }
                    
                    while accumulated + stepPixelDist < segLen {
                        accumulated += stepPixelDist
                        let ratio = CGFloat(accumulated / segLen)
                        let cx = p1.x + CGFloat(dx) * ratio
                        let cy = p1.y + CGFloat(dy) * ratio
                        let angle = atan2(CGFloat(dy), CGFloat(dx))
                        
                        let wingLen = baseWidth * 0.36
                        let backAngle1 = angle + CGFloat.pi * 0.76
                        let backAngle2 = angle - CGFloat.pi * 0.76
                        
                        let tipX = cx + cos(angle) * (wingLen * 0.45)
                        let tipY = cy + sin(angle) * (wingLen * 0.45)
                        let w1x = tipX + cos(backAngle1) * wingLen
                        let w1y = tipY + sin(backAngle1) * wingLen
                        let w2x = tipX + cos(backAngle2) * wingLen
                        let w2y = tipY + sin(backAngle2) * wingLen
                        
                        context.move(to: CGPoint(x: w1x, y: w1y))
                        context.addLine(to: CGPoint(x: tipX, y: tipY))
                        context.addLine(to: CGPoint(x: w2x, y: w2y))
                        context.strokePath()
                    }
                    accumulated -= segLen
                }
            }
        }
        context.restoreGState()
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
        mapView.showsScale = true
        mapView.showsTraffic = true
        mapView.showsBuildings = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        // Use light appearance on map canvas so AutoNavi/GaoDe street names, dual-carriageways, and traffic colors (Green/Yellow/Red) are 100% crisp like GaoDe App!
        mapView.overrideUserInterfaceStyle = .light
        if #available(iOS 16.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
            config.showsTraffic = true
            config.pointOfInterestFilter = .includingAll
            mapView.preferredConfiguration = config
        } else if #available(iOS 13.0, *) {
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
        
        context.coordinator.vehicleAnnotation.coordinate = manager.userCoordinate
        mapView.addAnnotation(context.coordinator.vehicleAnnotation)
        
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
                           (context.coordinator.lastCustomPolyline !== manager.customTransitPolyline) ||
                           (context.coordinator.lastCandidateCount != manager.candidateRoutes.count)
        
        if routeChanged || tappedChanged {
            context.coordinator.lastRoute = manager.activeRoute
            context.coordinator.lastCustomPolyline = manager.customTransitPolyline
            context.coordinator.lastCandidateCount = manager.candidateRoutes.count
            context.coordinator.lastTappedLat = manager.tappedMapCoord?.latitude
            context.coordinator.lastTappedLon = manager.tappedMapCoord?.longitude
            
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation || $0 is VehicleAvatarAnnotation) })
            if !mapView.annotations.contains(where: { $0 is VehicleAvatarAnnotation }) {
                mapView.addAnnotation(context.coordinator.vehicleAnnotation)
            }
            
            if manager.travelMode == .transit, manager.activeRoute == nil, let transitPoly = manager.customTransitPolyline {
                // Public Transit Mode: Draw synchronized transit route with realistic colored segments & station pins!
                mapView.addAnnotations(manager.transitStopAnnotations)
                
                let pts = transitPoly.points()
                let totalPts = transitPoly.pointCount
                if totalPts >= 12 {
                    // Segment 1 (Walk to bus stop): Pedestrian Blue with > > >
                    let cut1 = 2
                    let poly1 = MKPolyline(points: pts, count: cut1)
                    poly1.title = "TRANSIT_WALK_BLUE"
                    mapView.addOverlay(poly1, level: .aboveRoads)
                    
                    // Segment 2 (Bus 351 ride): Bus Royal Blue
                    let cut2 = min(totalPts - 4, 9)
                    let poly2 = MKPolyline(points: pts.advanced(by: cut1 - 1), count: cut2 - cut1 + 1)
                    poly2.title = "TRANSIT_BUS_BLUE"
                    mapView.addOverlay(poly2, level: .aboveRoads)
                    
                    // Segment 3 (Transfer at Guomao & Metro Line 1 to Luohu): Metro Emerald Green
                    let cut3 = min(totalPts - 3, 12)
                    let poly3 = MKPolyline(points: pts.advanced(by: cut2 - 1), count: cut3 - cut2 + 1)
                    poly3.title = "TRANSIT_METRO_GREEN"
                    mapView.addOverlay(poly3, level: .aboveRoads)
                    
                    // Segment 4 (Luohu Customs walk): Pedestrian Blue
                    let cut4 = min(totalPts - 2, 14)
                    let poly4 = MKPolyline(points: pts.advanced(by: cut3 - 1), count: cut4 - cut3 + 1)
                    poly4.title = "TRANSIT_WALK_BLUE"
                    mapView.addOverlay(poly4, level: .aboveRoads)
                    
                    // Segment 5 (MTR East Rail to Kowloon Tong): MTR Cyan Sky Blue
                    let cut5 = totalPts - 3
                    if cut5 > cut4 {
                        let poly5 = MKPolyline(points: pts.advanced(by: cut4 - 1), count: cut5 - cut4 + 1)
                        poly5.title = "TRANSIT_MTR_CYAN"
                        mapView.addOverlay(poly5, level: .aboveRoads)
                    }
                    
                    // Segment 6 (MTR Kwun Tong Line to Shek Kip Mei): MTR Kwun Tong Jade Green
                    let cut6 = totalPts - 1
                    if cut6 > cut5 {
                        let poly6 = MKPolyline(points: pts.advanced(by: max(0, cut5 - 1)), count: cut6 - max(0, cut5 - 1) + 1)
                        poly6.title = "TRANSIT_MTR_KWUN_TONG"
                        mapView.addOverlay(poly6, level: .aboveRoads)
                    }
                    
                    // Segment 7 (Walk from station to destination): Pedestrian Blue
                    let poly7 = MKPolyline(points: pts.advanced(by: cut6 - 1), count: totalPts - cut6 + 1)
                    poly7.title = "TRANSIT_WALK_BLUE"
                    mapView.addOverlay(poly7, level: .aboveRoads)
                } else {
                    transitPoly.title = "TRANSIT_MTR_CYAN"
                    mapView.addOverlay(transitPoly, level: .aboveRoads)
                }
            } else {
                // First draw alternate candidate routes in light translucent color so user sees multi-route comparison on map like GaoDe!
                for (idx, cand) in manager.candidateRoutes.enumerated() {
                    if cand !== manager.activeRoute {
                        cand.polyline.title = "ALT_ROUTE_\(idx)"
                        mapView.addOverlay(cand.polyline, level: .aboveRoads)
                    }
                }
            }
            
            if let route = manager.activeRoute {
                if manager.travelMode == .driving {
                    // Driving Mode: Split route into realistic GaoDe Traffic Segments (Main Route + Smooth Green + Slow Yellow + Congested Red) & Active Vehicle Blue!
                    let pts = route.polyline.points()
                    let totalPts = route.polyline.pointCount
                    if totalPts > 12 {
                        let cut1 = max(2, Int(Double(totalPts) * 0.22))
                        let cut2 = max(cut1 + 2, Int(Double(totalPts) * 0.65))
                        let cut3 = max(cut2 + 2, Int(Double(totalPts) * 0.80))
                        
                        // Segment 1 (Immediate vehicle path ahead): GaoDe Bright Navigation Blue
                        let polyBlue = MKPolyline(points: pts, count: cut1)
                        polyBlue.title = "DRIVING_ACTIVE_BLUE"
                        mapView.addOverlay(polyBlue, level: .aboveRoads)
                        
                        // Segment 2 (Main Arterial): GaoDe Smooth Traffic Green
                        let polyGreen = MKPolyline(points: pts.advanced(by: cut1 - 1), count: cut2 - cut1 + 1)
                        polyGreen.title = "TRAFFIC_GREEN"
                        mapView.addOverlay(polyGreen, level: .aboveRoads)
                        
                        // Segment 3 (Intersection / Ramp): GaoDe Slow Traffic Yellow/Amber (or Red if congested)
                        let polyYellow = MKPolyline(points: pts.advanced(by: cut2 - 1), count: cut3 - cut2 + 1)
                        polyYellow.title = manager.isCongested ? "TRAFFIC_RED" : "TRAFFIC_YELLOW"
                        mapView.addOverlay(polyYellow, level: .aboveRoads)
                        
                        // Segment 4 (Final Approach): GaoDe Smooth Traffic Green
                        let polyEndGreen = MKPolyline(points: pts.advanced(by: cut3 - 1), count: totalPts - cut3 + 1)
                        polyEndGreen.title = "TRAFFIC_GREEN"
                        mapView.addOverlay(polyEndGreen, level: .aboveRoads)
                    } else {
                        route.polyline.title = "DRIVING_ACTIVE_BLUE"
                        mapView.addOverlay(route.polyline, level: .aboveRoads)
                    }
                } else if manager.travelMode == .ebike {
                    route.polyline.title = "EBIKE_CYAN_BLUE"
                    mapView.addOverlay(route.polyline, level: .aboveRoads)
                } else if manager.travelMode == .walking {
                    route.polyline.title = "WALKING_BLUE"
                    mapView.addOverlay(route.polyline, level: .aboveRoads)
                } else {
                    // Transit Mode on Map: 100% Genuine Apple Maps Road Polyline!
                    // Perfectly follows the actual road centerlines (沙湾路 -> 沿河路 -> 罗湖口岸), never cutting across lakes or buildings!
                    route.polyline.title = "TRANSIT_BUS_BLUE"
                    mapView.addOverlay(route.polyline, level: .aboveRoads)
                    
                    // Add Boarding Station Marker
                    if let boardCoord = manager.transitBoardingStationCoord {
                        let boardPin = MKPointAnnotation()
                        boardPin.coordinate = boardCoord
                        boardPin.title = manager.transitBoardingStationName.isEmpty ? "乘车站台" : manager.transitBoardingStationName
                        boardPin.subtitle = "BUS_STOP_PIN"
                        mapView.addAnnotation(boardPin)
                    }
                }
                
                // Add Start Point (起) and Destination Point (終) Annotations like GaoDe!
                if let firstPt = route.polyline.points().pointee as MKMapPoint? {
                    let startPin = MKPointAnnotation()
                    startPin.coordinate = firstPt.coordinate
                    startPin.title = "我的位置"
                    startPin.subtitle = "START_PIN"
                    mapView.addAnnotation(startPin)
                }
                if let dest = manager.destinationCoord {
                    let pin = MKPointAnnotation()
                    pin.coordinate = dest
                    pin.title = manager.destinationName
                    pin.subtitle = "DEST_PIN"
                    mapView.addAnnotation(pin)
                }
                for hazard in manager.routeHazards {
                    mapView.addAnnotation(hazard)
                }
            }
            
            if let tapped = manager.tappedMapCoord {
                context.coordinator.lastTappedTitle = manager.tappedMapTitle
                let tappedPin = MKPointAnnotation()
                tappedPin.coordinate = tapped
                tappedPin.title = manager.tappedMapTitle
                tappedPin.subtitle = "TAPPED_PIN"
                mapView.addAnnotation(tappedPin)
            }
            
            if routeChanged && (manager.activeRoute != nil || manager.customTransitPolyline != nil) {
                let targetCoord = manager.userCoordinate
                let camera = MKMapCamera(
                    lookingAtCenter: targetCoord,
                    fromDistance: manager.userZoomDistance,
                    pitch: camPitch,
                    heading: camHeading
                )
                mapView.setCamera(camera, animated: false)
            }
        }
        
        // 1.5 Update TAPPED_PIN annotation title in-place once reverse geocoding / POI lookup finishes
        if context.coordinator.lastTappedTitle != manager.tappedMapTitle {
            context.coordinator.lastTappedTitle = manager.tappedMapTitle
            for anno in mapView.annotations {
                if let pt = anno as? MKPointAnnotation, pt.subtitle == "TAPPED_PIN" {
                    pt.title = manager.tappedMapTitle
                }
            }
        }
        
        // 2. Keep VehicleAvatarAnnotation locked to manager.userCoordinate (snapped dead-center onto the route line!)
        let vAnno = context.coordinator.vehicleAnnotation
        if abs(vAnno.coordinate.latitude - manager.userCoordinate.latitude) > 1e-7 ||
           abs(vAnno.coordinate.longitude - manager.userCoordinate.longitude) > 1e-7 {
            vAnno.coordinate = manager.userCoordinate
        }
        if let rawUserView = mapView.view(for: mapView.userLocation) {
            rawUserView.isHidden = true
            rawUserView.alpha = 0.0
        }
        if let userView = mapView.view(for: vAnno) {
            let effHeading = (manager.snappedRouteHeading != nil && manager.hasActiveNavigation)
                ? manager.snappedRouteHeading!
                : manager.headingDegrees
            if let rmArrow = manager.getRM500NavigationArrowFrame(mapCameraHeading: mapView.camera.heading) {
                userView.image = rmArrow
                userView.bounds = CGRect(x: 0, y: 0, width: 68, height: 88)
                // Offset -32 places the red arrow tip at the bottom of the character sprite directly on the route line!
                userView.centerOffset = CGPoint(x: 0, y: -32)
                userView.transform = .identity
            } else {
                userView.image = context.coordinator.arrowImage
                userView.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
                userView.centerOffset = .zero
                let rotationAngle = CGFloat((effHeading - mapView.camera.heading) * .pi / 180.0)
                userView.transform = CGAffineTransform(rotationAngle: rotationAngle)
            }
        }
        
        // 3. Dedicated Zoom [+] / [-] Button Trigger (Strictly zooms in/out at current map center!)
        if context.coordinator.lastZoomTrigger != manager.zoomCommandTrigger {
            context.coordinator.lastZoomTrigger = manager.zoomCommandTrigger
            let centerCoord = manager.mapTrackingUser
                ? manager.userCoordinate
                : mapView.camera.centerCoordinate
            let cam = MKMapCamera(
                lookingAtCenter: centerCoord,
                fromDistance: manager.userZoomDistance,
                pitch: mapView.camera.pitch,
                heading: mapView.camera.heading
            )
            mapView.setCamera(cam, animated: true)
            return
        }
        
        // 4. Instant Zero-Lag Recenter & Non-Blocking Camera Follow
        if context.coordinator.lastRecenterTrigger != manager.recenterTrigger {
            context.coordinator.lastRecenterTrigger = manager.recenterTrigger
            context.coordinator.isUserInteracting = false
            
            let targetCoord = manager.userCoordinate
            
            mapView.layer.removeAllAnimations()
            let camera = MKMapCamera(
                lookingAtCenter: targetCoord,
                fromDistance: manager.userZoomDistance,
                pitch: camPitch,
                heading: camHeading
            )
            mapView.setCamera(camera, animated: false)
            
        } else if manager.mapTrackingUser && !context.coordinator.isUserInteracting {
            let targetCoord = manager.userCoordinate
            
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
        var lastCustomPolyline: MKPolyline? = nil
        var lastCandidateCount: Int = 0
        var lastTappedLat: Double? = nil
        var lastTappedLon: Double? = nil
        var lastTappedTitle: String = ""
        var isUserInteracting: Bool = false
        var lastRecenterTrigger: Int = 0
        var lastZoomTrigger: Int = 0
        
        let vehicleAnnotation = VehicleAvatarAnnotation()
        
        lazy var arrowImage: UIImage = {
            Coordinator.createNavigationArrowImage()
        }()
        
        lazy var trafficLightIcon: UIImage = {
            Coordinator.createTrafficLightMapIcon()
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
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation, !(annotation is MKUserLocation), !(annotation is VehicleAvatarAnnotation) else { return }
            // Ignore temporary tapped pin or loading placeholder to prevent loop
            if annotation.subtitle == "TAPPED_PIN" || annotation.title == "正在获取地点..." || annotation.title == "定位解析中..." {
                return
            }
            let coord = annotation.coordinate
            let title = annotation.title ?? nil
            DispatchQueue.main.async {
                self.parent.manager.handleMapTap(at: coord, explicitTitle: title ?? nil)
            }
        }
        
        // Prevent didTapMap gesture from firing when tapping directly on annotation pins
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if touch.view is MKAnnotationView || touch.view?.superview is MKAnnotationView {
                return false
            }
            return true
        }
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let loc = userLocation.location, loc.horizontalAccuracy >= 0, !parent.manager.isDemoSimulating else { return }
            DispatchQueue.main.async {
                self.parent.manager.hasMapUserLocation = true
                self.parent.manager.updateSnappedRouteCoordinate(for: loc.coordinate)
                let effectiveCoord = self.parent.manager.snappedRouteCoordinate ?? loc.coordinate
                self.parent.manager.userCoordinate = effectiveCoord
                if self.parent.manager.travelMode == .transit {
                    self.parent.manager.refreshTransitPlansForCurrentLocation(force: false)
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let identifier = "HiddenRawUserLocationView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                } else {
                    view?.annotation = annotation
                }
                view?.isHidden = true
                view?.alpha = 0.0
                return view
            } else if annotation is VehicleAvatarAnnotation {
                let identifier = "SnappedVehicleAvatarView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                    if #available(iOS 14.0, *) {
                        view?.zPriority = .max
                    }
                    view?.displayPriority = .required
                } else {
                    view?.annotation = annotation
                }
                
                let effHeading = (parent.manager.snappedRouteHeading != nil && parent.manager.hasActiveNavigation)
                    ? parent.manager.snappedRouteHeading!
                    : parent.manager.headingDegrees
                if let rmArrow = parent.manager.getRM500NavigationArrowFrame(mapCameraHeading: mapView.camera.heading) {
                    view?.image = rmArrow
                    view?.bounds = CGRect(x: 0, y: 0, width: 68, height: 88)
                    view?.centerOffset = CGPoint(x: 0, y: -32)
                    view?.transform = .identity
                } else {
                    view?.image = arrowImage
                    view?.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
                    view?.centerOffset = .zero
                    let rotationAngle = CGFloat((effHeading - mapView.camera.heading) * .pi / 180.0)
                    view?.transform = CGAffineTransform(rotationAngle: rotationAngle)
                }
                return view
            } else if let hazard = annotation as? RoadHazardAnnotation {
                if hazard.kind == .trafficLight {
                    let tlId = "RouteTrafficLightAnnotationView"
                    var tlView = mapView.dequeueReusableAnnotationView(withIdentifier: tlId)
                    if tlView == nil {
                        tlView = MKAnnotationView(annotation: hazard, reuseIdentifier: tlId)
                        tlView?.canShowCallout = true
                        tlView?.displayPriority = .defaultHigh
                    } else {
                        tlView?.annotation = hazard
                    }
                    tlView?.image = trafficLightIcon
                    tlView?.bounds = CGRect(x: 0, y: 0, width: 22, height: 34)
                    tlView?.centerOffset = CGPoint(x: 0, y: -12)
                    return tlView
                }
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
                case .trafficLight:
                    break
                }
                return hView
            } else if let pin = annotation as? MKPointAnnotation {
                let sub = pin.subtitle ?? ""
                let id = "GaoDePin_\(sub)"
                var pinView = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if pinView == nil {
                    pinView = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: id)
                    pinView?.canShowCallout = true
                } else {
                    pinView?.annotation = pin
                }
                if sub.isEmpty || sub == "TAP_PIN" {
                    pinView?.markerTintColor = UIColor.systemOrange
                    pinView?.glyphImage = UIImage(systemName: "mappin.and.ellipse")
                } else if sub == "START_PIN" {
                    pinView?.markerTintColor = UIColor(red: 0.0, green: 0.72, blue: 0.35, alpha: 1.0)
                    pinView?.glyphText = "起"
                } else if sub == "BUS_STOP_PIN" {
                    pinView?.markerTintColor = UIColor(red: 0.12, green: 0.47, blue: 0.94, alpha: 1.0)
                    pinView?.glyphImage = UIImage(systemName: "bus.fill")
                } else if sub == "SUBWAY_STOP_PIN" {
                    pinView?.markerTintColor = UIColor(red: 0.0, green: 0.60, blue: 0.85, alpha: 1.0)
                    pinView?.glyphImage = UIImage(systemName: "tram.fill")
                } else if sub == "PORT_CUSTOMS_PIN" {
                    pinView?.markerTintColor = UIColor.systemPurple
                    pinView?.glyphImage = UIImage(systemName: "building.columns.fill")
                } else if sub == "TRANSFER_PIN" {
                    pinView?.markerTintColor = UIColor.systemOrange
                    pinView?.glyphImage = UIImage(systemName: "arrow.triangle.swap")
                } else {
                    // GaoDe Red "終" Badge for Destination!
                    pinView?.markerTintColor = UIColor(red: 0.92, green: 0.22, blue: 0.25, alpha: 1.0)
                    pinView?.glyphText = "終"
                }
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
        
        static func createTrafficLightMapIcon() -> UIImage {
            let size = CGSize(width: 22, height: 34)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let cg = ctx.cgContext
                cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.55).cgColor)
                let boxRect = CGRect(x: 3, y: 2, width: 16, height: 28)
                let housing = UIBezierPath(roundedRect: boxRect, cornerRadius: 6)
                UIColor(white: 0.12, alpha: 0.96).setFill()
                housing.fill()
                UIColor.white.withAlphaComponent(0.85).setStroke()
                housing.lineWidth = 1.4
                housing.stroke()
                
                // Red, Yellow, Green signal bulbs
                let rPath = UIBezierPath(ovalIn: CGRect(x: 7.5, y: 5.0, width: 7, height: 7))
                UIColor(red: 1.0, green: 0.22, blue: 0.22, alpha: 1.0).setFill()
                rPath.fill()
                
                let yPath = UIBezierPath(ovalIn: CGRect(x: 7.5, y: 12.5, width: 7, height: 7))
                UIColor(red: 1.0, green: 0.82, blue: 0.12, alpha: 1.0).setFill()
                yPath.fill()
                
                let gPath = UIBezierPath(ovalIn: CGRect(x: 7.5, y: 20.0, width: 7, height: 7))
                UIColor(red: 0.15, green: 0.95, blue: 0.40, alpha: 1.0).setFill()
                gPath.fill()
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = GaoDeArrowRouteRenderer(polyline: polyline)
                let tag = polyline.title ?? ""
                
                if tag.hasPrefix("ALT_ROUTE") {
                    // Alternate Backup Route (备选路线: 半透明浅灰绿/浅蓝分色，一眼区分主次)
                    renderer.isAlternateRoute = true
                    renderer.drawDirectionChevrons = false
                    renderer.mainFillColor = UIColor(red: 0.55, green: 0.78, blue: 0.65, alpha: 0.65)
                    renderer.outerBorderColor = UIColor(red: 0.35, green: 0.55, blue: 0.45, alpha: 0.70)
                    renderer.lineWidth = 8.0
                } else if tag == "DRIVING_ACTIVE_BLUE" || tag == "EBIKE_CYAN_BLUE" {
                    // Driving & e-Bike Active Vehicle Guidance Line: Vivid GaoDe Cyan-Blue (#0099FF) with deep navy border & white chevrons!
                    renderer.mainFillColor = UIColor(red: 0.0, green: 0.62, blue: 1.0, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.32, blue: 0.68, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                } else if tag == "WALKING_BLUE" {
                    // Walking Path: Clear Pedestrian Blue with white chevrons
                    renderer.mainFillColor = UIColor(red: 0.05, green: 0.65, blue: 0.98, alpha: 0.96)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.38, blue: 0.72, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 9.5
                } else if tag == "TRAFFIC_YELLOW" {
                    // GaoDe Slow Traffic Segment (黄色缓行路段)
                    renderer.mainFillColor = UIColor(red: 1.0, green: 0.74, blue: 0.08, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.72, green: 0.45, blue: 0.0, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                } else if tag == "TRAFFIC_RED" {
                    // GaoDe Congested Traffic Segment (红色拥堵路段)
                    renderer.mainFillColor = UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.62, green: 0.05, blue: 0.05, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                } else if tag == "TRANSIT_MTR_CYAN" {
                    // MTR East Rail Line (港铁东铁线 天蓝蓝 #0098D4)
                    renderer.mainFillColor = UIColor(red: 0.0, green: 0.60, blue: 0.85, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.35, blue: 0.58, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                } else if tag == "TRANSIT_MTR_KWUN_TONG" {
                    // MTR Kwun Tong Line (港铁观塘线 翠绿 #00AB4E)
                    renderer.mainFillColor = UIColor(red: 0.0, green: 0.68, blue: 0.32, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.42, blue: 0.18, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                } else if tag == "TRANSIT_BUS_BLUE" {
                    // Bus Line (公交351路 宝蓝)
                    renderer.mainFillColor = UIColor(red: 0.12, green: 0.48, blue: 0.96, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.28, blue: 0.68, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                } else if tag == "TRANSIT_METRO_GREEN" {
                    // Metro Line 1 (深圳地铁1号线 翡翠绿)
                    renderer.mainFillColor = UIColor(red: 0.05, green: 0.72, blue: 0.35, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.45, blue: 0.20, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                } else if tag == "TRANSIT_WALK_BLUE" {
                    // Transit Pedestrian Walk / Customs link
                    renderer.mainFillColor = UIColor(red: 0.05, green: 0.65, blue: 0.98, alpha: 0.96)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.38, blue: 0.72, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 10.0
                } else {
                    // Default / TRAFFIC_GREEN / TRANSIT_GREEN: GaoDe Smooth Traffic Green (#00C853) with forest green border & white chevrons!
                    renderer.mainFillColor = UIColor(red: 0.0, green: 0.78, blue: 0.33, alpha: 0.98)
                    renderer.outerBorderColor = UIColor(red: 0.0, green: 0.45, blue: 0.18, alpha: 1.0)
                    renderer.drawDirectionChevrons = true
                    renderer.lineWidth = 11.0
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Main Content View with Dynamic Auto-Enlarging Navigation HUD
struct ContentView: View {
    @StateObject private var manager = AudioPlayerManager.shared
    @ObservedObject private var musicManager = KOnMusicManager.shared
    @State private var showSoundboardSheet: Bool = false
    @State private var showSearchSheet: Bool = false
    @State private var showAboutSheet: Bool = false
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
                // Background layer attached via .background() so it NEVER inflates ZStack or ScrollView frame size!
                httDarkPanel
                    .overlay(
                        Group {
                            if let themeBG = manager.getCurrentThemeBackground(), !manager.isMapEnlarged {
                                Image(uiImage: themeBG)
                                    .resizable()
                                    .scaledToFill()
                                    .opacity(0.38)
                            }
                        }
                    )
                    .clipped()
                    .ignoresSafeArea(.all)
                
                // CONDITIONAL 1: Prominent Enlarged Full-Screen Navigation View
                if manager.isMapEnlarged {
                    enlargedNavigationHUDView(geo: geo, isLandscape: isLandscape)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                } else {
                    // CONDITIONAL 2: Standard Classic Cockpit View
                    // Universal Responsive Layout for:
                    // - Small Screens (iPhone 7 / 8 / SE: 375x667 Portrait, 667x375 Landscape)
                    // - Notch Screens (iPhone 13 / 13 Pro / 14: 390x844 Portrait, 844x390 Landscape)
                    // - Dynamic Island (iPhone 15 / 16 Pro: 393x852 Portrait, 852x393 Landscape)
                    // - Plus / Pro Max / Duo (430x932+ Portrait, 932x430+ Landscape)
                    if isLandscape {
                        // GeometryReader already respects left/right safeAreaInsets automatically!
                        // Use clean 10pt symmetric side padding so there is ZERO wasted gap on the left!
                        let sidePad: CGFloat = 10
                        let usableW = max(320, geo.size.width - sidePad * 2)
                        let colSpacing: CGFloat = max(8, usableW * 0.018)
                        let leftColW = (usableW - colSpacing) * 0.46
                        let rightColW = (usableW - colSpacing) * 0.54
                        let isCompactH = geo.size.height < 400 // iPhone 7 (375pt) & iPhone 13 Pro (390pt)
                        let landscapeStageH = max(124, min(175, geo.size.height * (isCompactH ? 0.36 : 0.40)))
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: isCompactH ? 5 : 7) {
                                topBezelBar
                                    .frame(width: usableW)
                                
                                HStack(alignment: .top, spacing: colSpacing) {
                                    // Left Column: Speedometer + Tactical Buttons + Cruise/Nav + Outfit/Camera/Gift + Author Bar!
                                    VStack(spacing: isCompactH ? 5 : 7) {
                                        speedometerCockpit(isCompact: true)
                                        utilityControlGrid(isCompact: true)
                                        outfitCameraGiftRow
                                        
                                        // Landscape Author & Feedback Bar (横屏左侧底部署名与反馈)
                                        Button(action: { showAboutSheet = true }) {
                                            HStack(spacing: 5) {
                                                Image(systemName: "sparkles")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(httGold)
                                                Text(manager.appAuthorLabel)
                                                    .font(.system(size: 10, weight: .black))
                                                    .foregroundColor(httGold)
                                                    .lineLimit(1)
                                                Text("·")
                                                    .foregroundColor(.gray)
                                                Text("v\(manager.appVersion)")
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.85))
                                                Text("·")
                                                    .foregroundColor(.gray)
                                                HStack(spacing: 3) {
                                                    Image(systemName: "ladybug.fill")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.orange)
                                                    Text(tr("BUG反馈", "BUG反饋", "Feedback"))
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                                                        .lineLimit(1)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.black.opacity(0.55))
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.45), lineWidth: 1))
                                        }
                                    }
                                    .frame(width: leftColW)
                                    
                                    // Right Column: Map/Stage + Speech Bubble + Character Strip + Travel Modes Row
                                    VStack(spacing: isCompactH ? 5 : 7) {
                                        mainStageOrMapSection(stageWidth: rightColW, stageHeight: landscapeStageH)
                                        characterSelectorStrip
                                            .frame(width: rightColW)
                                        travelModesRow
                                            .frame(width: rightColW)
                                    }
                                    .frame(width: rightColW)
                                }
                                .frame(width: usableW)
                            }
                            .padding(.horizontal, sidePad)
                            .padding(.top, 4)
                            .padding(.bottom, max(geo.safeAreaInsets.bottom + 6, 18))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                        .onAppear { manager.stageWalkBound = 85.0 }
                    } else {
                        // Portrait Mode: Adaptive for iPhone 7/SE (height ~647pt) up to iPhone 13/15/Pro Max/Duo!
                        let isSmallPortrait = geo.size.height < 700
                        let portraitStageH = isSmallPortrait
                            ? max(155, geo.size.height * 0.24)
                            : max(205, min(260, geo.size.height * 0.27))
                        let contentW = max(280, geo.size.width - 20)
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: isSmallPortrait ? 6 : 8) {
                                topBezelBar
                                speedometerCockpit(isCompact: isSmallPortrait)
                                mainStageOrMapSection(stageWidth: contentW, stageHeight: portraitStageH)
                                characterSelectorStrip
                                utilityControlGrid(isCompact: isSmallPortrait)
                                portraitBottomCompanionDock
                                
                                // Prominent Author & Version Badge (优雅呈现作者与版本)
                                Button(action: { showAboutSheet = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 9))
                                            .foregroundColor(httGold)
                                        Text(manager.appAuthorLabel)
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundColor(httGold)
                                        Text("·")
                                            .foregroundColor(.gray)
                                        Text("v\(manager.appVersion)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.85))
                                        Text("·")
                                            .foregroundColor(.gray)
                                        HStack(spacing: 3) {
                                            Image(systemName: "ladybug.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(.orange)
                                            Text(tr("BUG反馈", "BUG反饋", "Feedback"))
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black.opacity(0.48))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.45), lineWidth: 1))
                                }
                                .padding(.top, 1)
                            }
                            .frame(width: contentW)
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                            .padding(.bottom, max(geo.safeAreaInsets.bottom + 8, 16))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
                        .onAppear { manager.stageWalkBound = 65.0 }
                    }
                }
                
                // Long-Press RM-500HTT Beautified Outfit Quick Switcher Modal!
                if showOutfitPopup {
                    outfitQuickPickerModalOverlay
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: isLandscape) { newVal in
                manager.stageWalkBound = newVal ? 95.0 : 65.0
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showSoundboardSheet) {
            SoundboardSheetView(manager: manager)
        }
        .sheet(isPresented: $musicManager.showMusicSheet) {
            KOnMusicLibraryView(musicManager: musicManager)
        }
        .sheet(isPresented: $showSearchSheet) {
            DestinationSearchSheetView(manager: manager)
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutAndFeedbackSheetView(manager: manager)
        }
        .sheet(isPresented: $showAlbumSheet) {
            RM500AlbumAndOutfitSheetView(manager: manager)
        }
        .sheet(isPresented: $manager.showTransitPlanSheet) {
            InAppTransitPlanSheetView(manager: manager)
        }
        .sheet(isPresented: $manager.showGaoDeWebPortalSheet) {
            GaoDeLiveWebPortalSheetView(manager: manager)
        }
        .sheet(isPresented: $manager.showAllFlightTicketsSheet) {
            InAppFlightTicketScheduleSheetView(manager: manager)
        }
        .sheet(isPresented: $manager.showAllTrainTicketsSheet) {
            InAppTrainTicketScheduleSheetView(manager: manager)
        }
    }
    
    // MARK: - ENLARGED FULL-SCREEN NAVIGATION HUD (Portrait 100% preserved; Landscape uses dedicated 2-Column Notch-Safe Non-Overlapping Layout!)
    private func enlargedNavigationHUDView(geo: GeometryProxy, isLandscape: Bool) -> some View {
        ZStack {
            // 1. Full Screen 3D Navigation Map
            HTTSmoothMapView(manager: manager)
                .ignoresSafeArea()
            
            // 2. Overlays: Dedicated Landscape vs Portrait Layout
            if isLandscape {
                let leadingNotchPad: CGFloat = 10
                let trailingSafePad: CGFloat = 10
                let usableW = max(480, geo.size.width - leadingNotchPad - trailingSafePad)
                let leftPanelW = min(355, max(300, usableW * 0.46))
                
                HStack(alignment: .top, spacing: 10) {
                    // LEFT COLUMN (Compact Control Stack: Top Turn Card + Lanes/Lights + Travel Modes + SpeedCam/ServiceArea)
                    VStack(alignment: .leading, spacing: 5) {
                        if manager.hasActiveNavigation {
                            topNavigationBannerCard
                        }
                        
                        if manager.activeRoute != nil || manager.customTransitPolyline != nil || manager.isDemoSimulating {
                            laneGuidanceAndTrafficLightBar
                        }
                        
                        if !manager.isNavigatingFocused {
                            travelModeSelectorBar
                        }
                        
                        electronicEyeAndHighwayHUDStrip
                        
                        Spacer(minLength: 2)
                        
                        // Speedometer + Speech Bubble + Mascot Compact Dock at Bottom-Left
                        bottomEnlargedFloatingIsland(isLandscape: true)
                    }
                    .frame(width: leftPanelW)
                    
                    // CENTER & RIGHT AREA (Wide Open Map Center for Character Arrow + Right Control Column + Bottom Route Card)
                    VStack(alignment: .trailing, spacing: 5) {
                        // Top-Right Controls: Compass + Recenter + Zoom [+] / [-]
                        VStack(alignment: .trailing, spacing: 6) {
                            Button(action: {
                                manager.toggleCameraMode()
                            }) {
                                HStack(spacing: 5) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.85))
                                            .frame(width: 26, height: 26)
                                            .overlay(Circle().stroke(httGold, lineWidth: 1.5))
                                        Image(systemName: "location.north.fill")
                                            .font(.system(size: 11, weight: .bold))
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
                            
                            Button(action: {
                                manager.triggerFastRecenter()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: manager.mapTrackingUser ? "location.north.line.fill" : "location")
                                    Text(manager.mapTrackingUser ? tr("跟车中", "跟車中", "Locked") : tr("回中", "回中", "Center"))
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(manager.mapTrackingUser ? Color.green.opacity(0.88) : Color.black.opacity(0.82))
                                .foregroundColor(manager.mapTrackingUser ? .black : httGold)
                                .cornerRadius(8)
                            }
                            
                            // "缩小" Return to Cockpit in Landscape
                            HStack(spacing: 4) {
                                Button(action: {
                                    showSearchSheet = true
                                }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "magnifyingglass")
                                        Text(tr("搜索", "搜尋", "Search"))
                                    }
                                    .font(.system(size: 10, weight: .heavy))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.75), lineWidth: 1))
                                }
                                
                                Button(action: {
                                    musicManager.showMusicSheet = true
                                }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "music.note")
                                        Text(tr("音乐", "音樂", "Music"))
                                    }
                                    .font(.system(size: 10, weight: .heavy))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 5)
                                    .background(musicManager.isPlaying ? Color.purple.opacity(0.85) : Color.black.opacity(0.85))
                                    .foregroundColor(musicManager.isPlaying ? .white : httGold)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.75), lineWidth: 1))
                                }
                                
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        manager.isMapEnlarged = false
                                    }
                                }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        Text(tr("返回驾驶舱", "返回駕駛艙", "Cockpit"))
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.82))
                                    .foregroundColor(httGold)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.75), lineWidth: 1))
                                }
                            }
                            
                            HStack(spacing: 5) {
                                Button(action: { manager.zoomMapIn() }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 15, weight: .black))
                                        .foregroundColor(httGold)
                                        .frame(width: 32, height: 32)
                                        .background(Color.black.opacity(0.82))
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.6), lineWidth: 1))
                                }
                                Button(action: { manager.zoomMapOut() }) {
                                    Image(systemName: "minus")
                                        .font(.system(size: 15, weight: .black))
                                        .foregroundColor(httCream)
                                        .frame(width: 32, height: 32)
                                        .background(Color.black.opacity(0.82))
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                                }
                            }
                        }
                        
                        Spacer(minLength: 2)
                        
                        if manager.tappedMapCoord != nil {
                            tappedMapPointNavigationCard
                        } else if !manager.isNavigatingFocused && (manager.activeRoute != nil || manager.customTransitPolyline != nil || !manager.candidateRoutes.isEmpty) {
                            // Compact Bottom-Right Pre-Navigation Route Card
                            landscapeCompactPreNavCard
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.leading, leadingNotchPad)
                .padding(.trailing, trailingSafePad)
                .padding(.top, 6)
                .padding(.bottom, 8)
            } else {
                // PORTRAIT LAYOUT: Kept 100% Identical as requested!
                VStack(spacing: 5) {
                    // Top Navigation Guidance Card (Hidden when no active navigation!)
                    if manager.hasActiveNavigation {
                        topNavigationBannerCard
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                    
                    // Multi-Lane Guidance Bar (3~4 Lanes: Recommended in Bright White, Others in Dimmed Gray) + Traffic Light Countdown!
                    if manager.activeRoute != nil || manager.customTransitPolyline != nil || manager.isDemoSimulating {
                        laneGuidanceAndTrafficLightBar
                            .padding(.horizontal, 12)
                    }
                    
                    // Show Travel Mode switcher bar ONLY before pressing [开始导航] (Hidden during focused driving!)
                    if !manager.isNavigatingFocused {
                        travelModeSelectorBar
                            .padding(.horizontal, 12)
                    }
                    
                    // Electronic Speed Camera + Traffic Status (Left) vs Right Side Tool Column
                    HStack(alignment: .top, spacing: 6) {
                        electronicEyeAndHighwayHUDStrip
                        
                        Spacer(minLength: 4)
                        
                        // Right Side Stack: Top Row [搜索] [🎵 音乐] [缩小] + Vertical Toolbar (Compass, Recenter, Zoom)
                        VStack(alignment: .trailing, spacing: 6) {
                            // Row 1: [🔍 搜索] + [🎵 音乐] + [缩小] Cockpit Button
                            HStack(spacing: 5) {
                                Button(action: {
                                    showSearchSheet = true
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(tr("搜索", "搜尋", "Search"))
                                            .font(.system(size: 11, weight: .heavy))
                                    }
                                    .padding(.horizontal, 6)
                                    .frame(height: 32)
                                    .background(Color.black.opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.8), lineWidth: 1.2))
                                }
                                
                                Button(action: {
                                    musicManager.showMusicSheet = true
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(tr("音乐", "音樂", "Music"))
                                            .font(.system(size: 11, weight: .heavy))
                                    }
                                    .padding(.horizontal, 6)
                                    .frame(height: 32)
                                    .background(musicManager.isPlaying ? Color.purple.opacity(0.85) : Color.black.opacity(0.85))
                                    .foregroundColor(musicManager.isPlaying ? .white : httGold)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.8), lineWidth: 1.2))
                                }
                                
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        manager.isMapEnlarged = false
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(tr("返回驾驶舱", "返回駕駛艙", "Cockpit"))
                                            .font(.system(size: 11, weight: .heavy))
                                    }
                                    .padding(.horizontal, 7)
                                    .frame(height: 32)
                                    .background(Color.black.opacity(0.85))
                                    .foregroundColor(httGold)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.8), lineWidth: 1.2))
                                }
                            }
                            
                            // Vertical Tool Strip along right edge: Compass + Recenter + Zoom
                            VStack(alignment: .trailing, spacing: 5) {
                                // Compass / Camera Mode Button
                                Button(action: {
                                    manager.toggleCameraMode()
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.85))
                                            .frame(width: 34, height: 34)
                                            .overlay(Circle().stroke(httGold, lineWidth: 1.5))
                                        Image(systemName: "location.north.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.red)
                                            .rotationEffect(.degrees(manager.cameraMode == .headingUp ? -manager.headingDegrees : 0))
                                    }
                                }
                                
                                // Recenter / Follow-car Button
                                Button(action: {
                                    manager.triggerFastRecenter()
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: manager.mapTrackingUser ? "location.north.line.fill" : "location")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(manager.mapTrackingUser ? tr("跟车中", "跟車中", "Locked") : tr("回中", "回中", "Center"))
                                            .font(.system(size: 10, weight: .heavy))
                                    }
                                    .padding(.horizontal, 7)
                                    .frame(height: 30)
                                    .background(manager.mapTrackingUser ? Color.green.opacity(0.88) : Color.black.opacity(0.85))
                                    .foregroundColor(manager.mapTrackingUser ? .black : httGold)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.8), lineWidth: 1.2))
                                }
                                
                                // High-Contrast Bold Zoom [+] / [-] Capsule
                                VStack(spacing: 1) {
                                    Button(action: { manager.zoomMapIn() }) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(httGold)
                                            .frame(width: 34, height: 28)
                                    }
                                    Divider()
                                        .background(Color.white.opacity(0.3))
                                        .frame(width: 24)
                                    Button(action: { manager.zoomMapOut() }) {
                                        Image(systemName: "minus")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(httCream)
                                            .frame(width: 34, height: 28)
                                    }
                                }
                                .background(Color.black.opacity(0.85))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.7), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    
                    Spacer()
                    
                    // GaoDe 1:1 Interactive System: If user taps ANY location on the map, ALWAYS show the GaoDe POI Detail Card!
                    if manager.tappedMapCoord != nil {
                        tappedMapPointNavigationCard
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if !manager.isNavigatingFocused && (manager.activeRoute != nil || manager.customTransitPolyline != nil || !manager.candidateRoutes.isEmpty) {
                        // When user taps [路线] or [导航], POI card is dismissed and route preview is displayed!
                        bottomPreNavRouteSelectionCard
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Floating K-ON! Music Mini-Player Bar
                    if musicManager.isPlaying || musicManager.currentSong != nil {
                        KOnMusicMiniPlayerBar(musicManager: musicManager)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 2)
                    }
                    
                    // Bottom Floating Control Island (Speedometer + Speech Bubble + Bottom-Right Mascot!)
                    bottomEnlargedFloatingIsland(isLandscape: false)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    // Compact Landscape Pre-Navigation Card (Fits in bottom-right of Landscape screen without any vertical overflow!)
        private func landscapeRouteButton(route: MKRoute, index: Int) -> some View {
        let isSel = (manager.selectedRouteIndex == index)
        let estMins = max(1, Int(route.expectedTravelTime / 60.0))
        let distStr = String(format: "%.1fkm", route.distance / 1000.0)
        let badge = manager.routeOptionBadgeTitle(for: route, index: index)
        return Button(action: {
            manager.selectCandidateRoute(at: index)
        }) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(estMins)分 · \(distStr)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(isSel ? .white : httGold)
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSel ? httCream : .cyan)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSel ? httCrimson : Color.white.opacity(0.14))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSel ? httGold : Color.clear, lineWidth: 1.2))
        }
    }
    
    private var landscapeCompactPreNavCard: some View {
        VStack(spacing: 6) {
            if manager.travelMode == .driving {
                HStack(spacing: 5) {
                    ForEach(RouteStrategyPreference.allCases) { pref in
                        let isSelPref = (manager.routePreference == pref)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                manager.routePreference = pref
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: pref.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(pref.title(manager.language))
                                    .font(.system(size: 11, weight: .heavy))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(isSelPref ? httGold : Color.white.opacity(0.14))
                            .foregroundColor(isSelPref ? .black : httCream)
                            .cornerRadius(7)
                        }
                    }
                }
            } else if manager.travelMode == .transit && manager.destinationCoord != nil {
                Button(action: {
                    manager.showTransitPlanSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "tram.fill")
                        Text(tr("查看完整公交地铁换乘时间轴与车站", "查看完整公交地鐵換乘時間軸與車站", "View Full Transit Timeline"))
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(7)
                }
            }
            
            HStack(spacing: 6) {
                if manager.travelMode != .transit && !manager.candidateRoutes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(0..<manager.candidateRoutes.count, id: \.self) { idx in
                                landscapeRouteButton(route: manager.candidateRoutes[idx], index: idx)
                            }
                        }
                    }
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        manager.startFocusedNavigation()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.circle.fill")
                        Text(tr("开始导航", "開始導航", "Start"))
                            .font(.system(size: 13, weight: .black))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(httCrimson)
                    .foregroundColor(.white)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(httGold, lineWidth: 1.5))
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.90))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(httGold, lineWidth: 1.5))
    }

    // MARK: - Top Turn-by-Turn Instruction Banner Card
    private var topNavigationBannerCard: some View {
        HStack(alignment: .center, spacing: 10) {
            // Maneuver Turn Arrow + Step Distance (GaoDe column layout!)
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(httCrimson)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(httGold, lineWidth: 2))
                    
                    Image(systemName: (manager.travelMode == .transit && manager.transitPhase == .inTransitVehicle) ? "tram.fill" : turnIconName(for: manager.currentStepInstruction))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(httCream)
                }
                
                if manager.distanceToNextStepMeters > 0 {
                    Text(manager.formatSmartDistance(Int(manager.distanceToNextStepMeters)))
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(httGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: 54)
            
            // Middle Info: Primary Maneuver Instruction (up to 2 lines, never clipped!) + Destination & Route ETA
            VStack(alignment: .leading, spacing: 3) {
                // Primary Maneuver Instruction (Large bold, prominent like GaoDe)
                Text(manager.currentStepInstruction.isEmpty
                     ? tr("沿着当前道路直行", "沿著當前道路直行", "Continue straight ahead")
                     : manager.currentStepInstruction)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Secondary Bar: Destination + Total Remaining Distance & Time (Single clean line)
                HStack(spacing: 5) {
                    Text(manager.destinationName.isEmpty ? tr("实时路线引导", "即時路線引導", "Route Guidance") : manager.destinationName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(httGold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if manager.remainingRouteDistanceKm > 0 {
                        Text("·")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f km · %d %@", manager.remainingRouteDistanceKm, manager.remainingRouteMinutes, tr("分钟", "分鐘", "min")))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(httCream.opacity(0.92))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Trailing Controls: [X] Exit Navigation + [换乘] Transit Plan Button
            VStack(spacing: 5) {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        if manager.activeRoute != nil || manager.customTransitPolyline != nil {
                            manager.stopRouteGuidance()
                        } else {
                            manager.isMapEnlarged = false
                        }
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                
                if manager.travelMode == .transit && manager.destinationCoord != nil {
                    Button(action: {
                        manager.showTransitPlanSheet = true
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(tr("换乘", "換乘", "Plan"))
                                .font(.system(size: 9, weight: .black))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.92))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(httGold, lineWidth: 1))
                    }
                }
            }
            .frame(width: 46)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(httGold, lineWidth: 2))
                .shadow(color: .black.opacity(0.55), radius: 8)
        )
    }

    // MARK: - Multi-Lane Indicator (左转/直行/右转 白灰高亮) + Real-Time Traffic Light Countdown (红绿灯倒计时 - 绝不变形与折行)
    private var laneGuidanceAndTrafficLightBar: some View {
        HStack(spacing: 6) {
            // 1. Multi-Lane Indicator Box (紧凑高亮车道框，节省空间给红绿灯)
            HStack(spacing: 0) {
                ForEach(Array(manager.currentRoadLanes.enumerated()), id: \.element.id) { idx, lane in
                    HStack(spacing: 0) {
                        VStack(spacing: 1) {
                            Image(systemName: lane.iconName)
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(lane.isRecommended ? .white : Color.gray.opacity(0.45))
                                .shadow(color: lane.isRecommended ? httGold.opacity(0.8) : .clear, radius: 2)
                            Text(lane.label)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(lane.isRecommended ? httGold : Color.gray.opacity(0.45))
                        }
                        .frame(width: 28, height: 32)
                        .background(lane.isRecommended ? httCrimson.opacity(0.85) : Color.clear)
                        .cornerRadius(5)
                        
                        if idx < manager.currentRoadLanes.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 1, height: 18)
                                .padding(.horizontal, 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.88))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.75), lineWidth: 1.2))
            .fixedSize(horizontal: true, vertical: false)
            
            // Top traffic light countdown removed per user request (intersection lights are rendered directly along the route on the map)
            
            Spacer(minLength: 4)
            
            // 3. Compact Route Preference / Settings button (路线设置)
            if manager.isNavigatingFocused {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        manager.exitFocusedNavigationToOverview()
                    }
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9, weight: .bold))
                        Text(tr("设置", "設置", "Opt"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.85))
                    .foregroundColor(httGold)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.65), lineWidth: 1))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
    
    // MARK: - Subviews for Pre-Navigation Card (Split to Guarantee Instant Swift Compilation!)
    private var highwayPreferenceButtonRow: some View {
        HStack(spacing: 8) {
            ForEach(RouteStrategyPreference.allCases) { pref in
                let isSel = (manager.routePreference == pref)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        manager.routePreference = pref
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: pref.icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(pref.title(manager.language))
                            .font(.system(size: 13, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .padding(.vertical, 4)
                    .background(isSel ? httGold : Color.white.opacity(0.14))
                    .foregroundColor(isSel ? .black : httCream)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSel ? Color.white : httGold.opacity(0.45), lineWidth: isSel ? 2 : 1)
                    )
                }
            }
        }
    }
    
    private func transitPlanTabButton(plan: TransitPlanOption, index: Int) -> some View {
        let isSel = (manager.selectedTransitPlanIndex == index)
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                manager.selectTransitPlan(at: index)
            }
        }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(plan.badge)
                        .font(.system(size: 12, weight: .black))
                }
                Text(plan.subtitleSummary)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .opacity(0.9)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSel ? Color.purple : Color.white.opacity(0.14))
            .foregroundColor(.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSel ? httGold : Color.white.opacity(0.2), lineWidth: isSel ? 2 : 1)
            )
        }
    }
    
    private var transitPreNavSection: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(manager.transitPlans.enumerated()), id: \.element.id) { idx, plan in
                        transitPlanTabButton(plan: plan, index: idx)
                    }
                }
            }
            
            Button(action: {
                manager.showTransitPlanSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(tr("查看完整公交地铁换乘时间轴与车站", "查看完整公交地鐵換乘時間軸與車站", "View Full Transit Timeline & Stations"))
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.3))
                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 1.0))
                .cornerRadius(8)
            }
        }
    }
    
    private func candidateRouteTabButton(route: MKRoute, index: Int) -> some View {
        let isSel = (manager.selectedRouteIndex == index)
        let estMins: Int = manager.estimatedMinutes(for: route)
        let distKmStr: String = String(format: "%.1f公里", route.distance / 1000.0)
        let lightCount: Int = max(1, Int(route.distance / 450.0))
        let badgeTitle: String = manager.routeOptionBadgeTitle(for: route, index: index)
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                manager.selectCandidateRoute(at: index)
            }
        }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(estMins)分钟")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(isSel ? .white : httGold)
                    Text(distKmStr)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    HStack(spacing: 1) {
                        Image(systemName: "light.beacon.max.fill")
                            .font(.system(size: 8))
                        Text("\(lightCount)")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.green)
                }
                Text(badgeTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSel ? httCream : Color.cyan)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSel ? httCrimson : Color.white.opacity(0.14))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSel ? httGold : Color.white.opacity(0.25), lineWidth: isSel ? 1.8 : 1)
            )
        }
    }
    
    private var candidateRoutesScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<manager.candidateRoutes.count, id: \.self) { idx in
                    candidateRouteTabButton(route: manager.candidateRoutes[idx], index: idx)
                }
            }
        }
    }
    
    private var bottomPreNavActionRow: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                manager.startFocusedNavigation()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "location.north.circle.fill")
                    .font(.title3)
                Text(tr("开始导航 · 专注驾驶", "開始導航 · 專注駕駛", "Start Navigation"))
                    .font(.system(size: 15, weight: .black))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [httCrimson, Color(red: 0.92, green: 0.25, blue: 0.30)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(11)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(httGold, lineWidth: 1.5))
        }
    }
    
    // Bottom Pre-Navigation Card: Enlarged Highway Strategy (高速优先/不走高速/距离最短) + Separate Candidate Routes Row + Anti-Mistouch [🚀 开始导航] Button!
    private var bottomPreNavRouteSelectionCard: some View {
        VStack(spacing: 9) {
            // Destination Title Header Row with Close Route Button
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(httGold)
                Text(manager.destinationName.isEmpty ? tr("规划路线", "規劃路線", "Planned Route") : manager.destinationName)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    manager.stopRouteGuidance()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 1)
            
            // Row 1: Enlarged Full-Width 3-Grid Highway Strategy (Driving) OR Built-In Transit Plans (Transit)
            if manager.travelMode == .driving {
                highwayPreferenceButtonRow
            } else if manager.travelMode == .transit {
                transitPreNavSection
            }
            
            // Row 2: GaoDe-Style Multi-Route Comparison Cards (Shows time, km, traffic lights & lighting % for Driving, e-Bike & Walking!)
            if manager.travelMode != .transit && !manager.candidateRoutes.isEmpty {
                candidateRoutesScrollRow
            }
            
            // Safety Divider Cushion
            Divider()
                .background(httGold.opacity(0.35))
                .padding(.vertical, 1)
            
            // Row 3: GaoDe Aggregated Ride-Hailing [🚕 高德打车] + [🚗 顺风车] + Prominent [🚀 开始导航] Button!
            bottomPreNavActionRow
        }
        .padding(12)
        .background(Color.black.opacity(0.90))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(httGold, lineWidth: 1.8))
    }
    
    // Electronic Speed Camera (测速电子眼) + Congestion (路况拥堵) + Service Area (服务区) + Toll Station (收费站) HUD Strip
    private var electronicEyeAndHighwayHUDStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 1. Electronic Speed Camera Badge (测速电子眼 - 仅在驾车/骑车且当前实际道路有限速数据时显示，无限速则自动隐藏!)
            if manager.travelMode.supportsSpeedLimit && manager.upcomingCameraLimit > 0 {
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.red, lineWidth: 3))
                        Text("\(manager.upcomingCameraLimit)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tr("测速电子眼", "測速電子眼", "Speed Cam"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                        Text(manager.upcomingCameraDistance > 0
                             ? manager.formatSmartDistance(manager.upcomingCameraDistance)
                             : tr("实际路网限速", "實際路網限速", "Road Limit"))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(httGold)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.85), lineWidth: 1.2))
            }
            
            // 2. Traffic Congestion Indicator (拥堵/畅通状态)
            HStack(spacing: 4) {
                Circle()
                    .fill(manager.isCongested ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(manager.congestionStatusText)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(manager.isCongested ? .orange : Color(red: 0.4, green: 0.98, blue: 0.65))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.85))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(manager.isCongested ? Color.orange : Color.green.opacity(0.6), lineWidth: 1))
            
            // 3. Enlarged Navigation GPS Status Indicator (放大导航 GPS 状态，点按可播报)
            Button(action: { manager.triggerGPSSignalManualBroadcast() }) {
                HStack(spacing: 4) {
                    Image(systemName: manager.isGPSSignalPoor ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(manager.isGPSSignalPoor ? .orange : Color(red: 0.4, green: 0.98, blue: 0.65))
                    Text(manager.isGPSSignalPoor ? tr("GPS弱", "GPS弱", "GPS Weak") : tr("GPS正常", "GPS正常", "GPS Good"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(manager.isGPSSignalPoor ? .orange : Color(red: 0.4, green: 0.98, blue: 0.65))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(manager.isGPSSignalPoor ? Color.orange.opacity(0.8) : Color.green.opacity(0.6), lineWidth: 1))
            }
            
            // 3. Highway Service Area (服务区) & Toll Station (收费站) Badges
            if manager.travelMode == .driving && (manager.upcomingServiceAreaDist > 0 || manager.upcomingTollDistance > 0) {
                HStack(spacing: 5) {
                    if manager.upcomingServiceAreaDist > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.cyan)
                            Text("\(manager.upcomingServiceAreaName.isEmpty ? tr("服务区", "服務區", "SA") : manager.upcomingServiceAreaName): \(manager.formatSmartDistance(manager.upcomingServiceAreaDist))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.85))
                        .cornerRadius(6)
                    }
                    if manager.upcomingTollDistance > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.yellow)
                            Text("\(tr("收费站", "收費站", "Toll")): \(manager.formatSmartDistance(manager.upcomingTollDistance))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.85))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    // 4 Travel Modes + Camera Mode + Outfit Bar (Shown before pressing [开始导航])
    private var travelModeSelectorBar: some View {
        HStack(spacing: 5) {
            ForEach(NavigationTravelMode.allCases) { mode in
                let isSelected = (manager.travelMode == mode)
                Button(action: {
                    manager.stop()
                    manager.travelMode = mode
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(mode.title(manager.language))
                            .font(.system(size: 11, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        isSelected
                        ? LinearGradient(colors: [Color(red: 0.95, green: 0.22, blue: 0.26), httCrimson], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.black.opacity(0.85), Color(white: 0.12).opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    )
                    .foregroundColor(isSelected ? .white : httCream.opacity(0.95))
                    .cornerRadius(9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isSelected ? httGold : Color.white.opacity(0.28), lineWidth: isSelected ? 1.8 : 1)
                    )
                    .shadow(color: isSelected ? httCrimson.opacity(0.55) : Color.black.opacity(0.4), radius: isSelected ? 4 : 2, x: 0, y: 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
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
                    if manager.travelMode.supportsSpeedLimit && manager.speedLimitKmh > 0 {
                        Text("\(tr("限速", "限速", "Limit")): \(Int(manager.speedLimitKmh))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(httGold)
                    }
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
                Text(manager.selectedCharacter == .all
                     ? "\(manager.activeAllMemberChar.displayName(manager.language)) (HTT)"
                     : manager.selectedCharacter.roleTag(manager.language))
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
            
            // Floating Mascot Avatar on Map: When HTT 5-member is selected, displays ONE random member and auto-switches irregularly!
            let effectiveMascotFrame = (manager.selectedCharacter == .all)
                ? (manager.allMemberFrames[manager.activeAllMemberChar.charId] ?? manager.currentSpriteFrame)
                : manager.currentSpriteFrame
            
            if let sprite = effectiveMascotFrame {
                Image(uiImage: sprite)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 74)
                    .shadow(radius: 4)
                    .onTapGesture {
                        manager.triggerCharacterTap()
                    }
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
        HStack(spacing: 4) {
            Button(action: {
                withAnimation { manager.showMapMode.toggle() }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: manager.showMapMode ? "map.fill" : "cup.and.saucer.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(httGold)
                    Text(manager.showMapMode
                         ? tr("地图模式", "地圖模式", "Map Mode")
                         : tr("舞台模式", "舞台模式", "Stage Mode"))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(httCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(httCrimson)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold, lineWidth: 1.5))
            }
            
            Button(action: {
                musicManager.showMusicSheet = true
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 11, weight: .bold))
                    Text(tr("音乐", "音樂", "Music"))
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(musicManager.isPlaying ? Color.purple.opacity(0.85) : Color.white.opacity(0.14))
                .foregroundColor(musicManager.isPlaying ? .white : httGold)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.7), lineWidth: 1))
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
                        .font(.system(size: 10))
                    Text(manager.language.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
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
                        .font(.system(size: 10))
                    Text(manager.isHUDMirrored ? tr("镜像", "鏡像", "Flip") : "HUD")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(manager.isHUDMirrored ? httGold : Color.white.opacity(0.12))
                .foregroundColor(manager.isHUDMirrored ? .black : httCream)
                .cornerRadius(8)
            }
            
            // RM-500HTT Official Album & Arrow Outfit Button (Never clips!)
            Button(action: { showAlbumSheet = true }) {
                HStack(spacing: 3) {
                    if let iconImg = manager.getRM500UIImage("rm_btn_icon_on") {
                        Image(uiImage: iconImg)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 10))
                    }
                    Text(tr("相册/车标", "相冊/車標", "Album"))
                        .font(.system(size: 11, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(Color.pink.opacity(0.88))
                .foregroundColor(.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold, lineWidth: 1))
            }
            

        }
        .frame(maxWidth: .infinity)
    }
    
    private func speedometerCockpit(isCompact: Bool = false) -> some View {
        VStack(spacing: isCompact ? 4 : 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(manager.currentSpeedKmh))")
                            .font(.system(size: isCompact ? 34 : 44, weight: .black, design: .monospaced))
                            .foregroundColor(manager.isOverspeeding ? .red : Color(red: 0.35, green: 0.98, blue: 0.65))
                            .shadow(color: (manager.isOverspeeding ? Color.red : Color.green).opacity(0.5), radius: 5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        
                        Text("km/h")
                            .font(.system(size: isCompact ? 11 : 13, weight: .bold, design: .monospaced))
                            .foregroundColor(httCream.opacity(0.7))
                    }
                    
                    HStack(spacing: 5) {
                        Button(action: { manager.triggerGPSSignalPoorAlert() }) {
                            HStack(spacing: 3) {
                                Image(systemName: manager.isGPSSignalPoor ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                                Text(manager.isGPSSignalPoor
                                     ? tr("GPS弱(点按播报)", "GPS弱(點按播報)", "GPS Weak")
                                     : tr("GPS信号正常", "GPS訊號正常", "GPS OK"))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(manager.isGPSSignalPoor ? Color.orange.opacity(0.3) : Color.green.opacity(0.18))
                            .foregroundColor(manager.isGPSSignalPoor ? .orange : .green)
                            .cornerRadius(5)
                        }
                        
                        if manager.isOverspeeding {
                            Text(tr("⚠️ 已超速!", "⚠️ 已超速!", "⚠️ OVERSPEED!"))
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer(minLength: 4)
                
                VStack(alignment: .trailing, spacing: isCompact ? 2 : 4) {
                    telemetryBadge(icon: "location.north.circle.fill", label: tr("方向", "方向", "DIR"), value: manager.compassDirectionString)
                    telemetryBadge(icon: "road.lanes", label: tr("里程", "里程", "TRIP"), value: String(format: "%.1f km", manager.tripDistanceKm))
                    telemetryBadge(icon: "clock.fill", label: tr("时长", "時長", "TIME"), value: manager.formattedDrivingTime)
                }
            }
            
            if manager.travelMode.supportsSpeedLimit {
                Divider().background(Color.white.opacity(0.15))
                
                HStack(spacing: 4) {
                    Button(action: { manager.triggerSpeedLimitPrompt() }) {
                        HStack(spacing: 2) {
                            Image(systemName: "speedometer")
                            Text(tr("限速播报:", "限速播報:", "Limit:"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                        .foregroundColor(httGold)
                    }
                    
                    let limitOptions: [Double] = (manager.travelMode == .ebike) ? [15.0, 20.0, 25.0, 35.0] : [60.0, 80.0, 100.0, 120.0]
                    ForEach(limitOptions, id: \.self) { limit in
                        Button(action: {
                            if manager.speedLimitKmh == limit {
                                manager.triggerSpeedLimitPrompt()
                            } else {
                                manager.speedLimitKmh = limit
                            }
                        }) {
                            Text("\(Int(limit))")
                                .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                                .padding(.horizontal, isCompact ? 5 : 7)
                                .padding(.vertical, 2.5)
                                .background(manager.speedLimitKmh == limit ? httCrimson : Color.white.opacity(0.1))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                    }
                    Spacer(minLength: 2)
                    Text("\(tr("最高", "最高", "MAX")): \(Int(manager.maxSpeedKmh))")
                        .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                        .foregroundColor(httGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(isCompact ? 7 : 10)
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
                        HStack(spacing: 4) {
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
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.78))
                                .cornerRadius(7)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(httGold.opacity(0.7), lineWidth: 1))
                            }
                            
                            // Demo simulation toggle button
                            Button(action: {
                                manager.toggleDemoSimulation()
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: manager.isDemoSimulating ? "stop.fill" : "play.fill")
                                    Text(manager.isDemoSimulating ? tr("停止", "停止", "Stop") : tr("模拟", "模擬", "Demo"))
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 5)
                                .background(manager.isDemoSimulating ? Color.orange : Color.purple.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(7)
                            }
                            
                            // Fast Recenter Button
                            Button(action: {
                                manager.triggerFastRecenter()
                            }) {
                                Image(systemName: manager.mapTrackingUser ? "location.north.line.fill" : "location")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 5)
                                    .background(manager.mapTrackingUser ? Color.green.opacity(0.85) : Color.black.opacity(0.75))
                                    .foregroundColor(manager.mapTrackingUser ? .black : httGold)
                                    .cornerRadius(7)
                            }
                            
                            // Camera Mode Toggle
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
                        
                        if manager.isMapEnlarged && manager.tappedMapCoord != nil {
                            tappedMapPointNavigationCard
                                .padding(.horizontal, 6)
                        }
                        
                        Spacer()
                        
                        // Mascot on map: Single member shown with irregular auto-switch when HTT is active!
                        HStack(alignment: .bottom) {
                            let effectiveFrame = (manager.selectedCharacter == .all)
                                ? (manager.allMemberFrames[manager.activeAllMemberChar.charId] ?? manager.currentSpriteFrame)
                                : manager.currentSpriteFrame
                            if let sprite = effectiveFrame {
                                Image(uiImage: sprite)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 76)
                                    .shadow(radius: 4)
                                    .onTapGesture {
                                        manager.triggerCharacterTap()
                                    }
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
                                x: savedPos.width + (isThisDragged ? dragOffset.width : 0),
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
    
    private func utilityControlGrid(isCompact: Bool = false) -> some View {
        VStack(spacing: isCompact ? 5 : 7) {
            HStack(spacing: isCompact ? 5 : 7) {
                tacticalButton(
                    title: tr("出发进行", "出發進行", "Depart"),
                    subtitle: tr("点火出发音", "點火出發音", "Start Guide"),
                    icon: "flag.checkered.2.crossed",
                    color: httCrimson,
                    isCompact: isCompact
                ) {
                    manager.triggerDepartureGreeting()
                }
                
                tacticalButton(
                    title: tr("多人相声", "雙人相聲", "Banter"),
                    subtitle: tr("多人对话彩蛋", "多人對話彩蛋", "Group Talk"),
                    icon: "bubble.left.and.bubble.right.fill",
                    color: Color(red: 0.58, green: 0.32, blue: 0.78),
                    isCompact: isCompact
                ) {
                    manager.triggerBanter()
                }
                
                tacticalButton(
                    title: tr("顶蛋糕下午茶", "頂蛋糕下午茶", "Tea Time"),
                    subtitle: tr("桌宠蛋糕休息", "桌寵蛋糕休息", "Cake Break"),
                    icon: "birthday.cake.fill",
                    color: Color(red: 0.82, green: 0.56, blue: 0.18),
                    isCompact: isCompact
                ) {
                    manager.triggerTeaTimeReminder()
                }
            }
            
            HStack(spacing: isCompact ? 5 : 7) {
                // Left Half: Cruise Companion Button + Interval Menu (Single-line protected, never stacks vertically on iPhone 7!)
                HStack(spacing: 4) {
                    Button(action: { manager.toggleCruiseMode() }) {
                        HStack(spacing: 4) {
                            Image(systemName: manager.isCruiseModeActive ? "timer" : "play.circle.fill")
                                .font(.system(size: isCompact ? 14 : 17, weight: .bold))
                                .foregroundColor(manager.isCruiseModeActive ? .green : httGold)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(manager.isCruiseModeActive
                                     ? "\(tr("巡航", "巡航", "Cruise")): \(manager.formattedCruiseCountdown)"
                                     : tr("开启巡航陪伴", "開啟巡航陪伴", "Start Cruise"))
                                    .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.68)
                                Text(tr("后台保活·定时播报", "後台保活·定時播報", "Background Active"))
                                    .font(.system(size: isCompact ? 8 : 9))
                                    .foregroundColor(.white.opacity(0.75))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.68)
                            }
                        }
                    }
                    
                    Spacer(minLength: 1)
                    
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
                        Text("\(Int(manager.cruiseIntervalMinutes))m▾")
                            .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.38))
                            .foregroundColor(httGold)
                            .cornerRadius(5)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, isCompact ? 6 : 9)
                .padding(.vertical, isCompact ? 6 : 8)
                .frame(maxWidth: .infinity)
                .background(manager.isCruiseModeActive ? Color.green.opacity(0.28) : Color.white.opacity(0.1))
                .cornerRadius(11)
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(manager.isCruiseModeActive ? Color.green : httGold.opacity(0.4), lineWidth: 1.4)
                )
                
                // Right Half: Destination Route Navigation Button (Single-line protected!)
                Button(action: { showSearchSheet = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "map.circle.fill")
                            .font(.system(size: isCompact ? 15 : 18, weight: .bold))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("目的地路线导航", "目的地路線導航", "Route Navi"))
                                .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                            Text(tr("真实路口触发轻音指路", "真實路口觸發輕音指路", "Turn-by-Turn Voice"))
                                .font(.system(size: isCompact ? 8 : 9))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, isCompact ? 6 : 9)
                    .padding(.vertical, isCompact ? 6 : 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.1, green: 0.4, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(httGold, lineWidth: 1.4)
                    )
                }
            }
        }
    }
    
    // MARK: - Interactive GaoDe-Style Merchant & POI Detail Card (1:1 复刻高德图5：营业时间/电话/评分/推荐菜/高德打车/路线/导航/实时资料库同步)
        private func poiDishCardButton(dish: DishItem) -> some View {
        Button(action: {
            manager.selectedDishItem = dish
            manager.showDishDetailAlert = true
            let msg = "✨ [\(manager.tappedMapTitle)] 招牌推薦：\(dish.name)（\(dish.price)），\(dish.desc)♪"
            manager.playVoice(id: manager.activeBaseId() + 39, customQuote: msg, clearQueue: true)
        }) {
            HStack(spacing: 6) {
                Image(systemName: dish.iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.85))
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dish.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(dish.price)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(httGold)
                        Text("👍\(dish.recommendCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.10))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.35), lineWidth: 1))
        }
    }

    private var tappedMapPointNavigationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row: Title + V Badge + Expand/Collapse + Close Button
            HStack(alignment: .center, spacing: 6) {
                Text(manager.tappedMapTitle)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // GaoDe V Verified Badge
                Text("V")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        manager.showPOIDetailCardExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 2) {
                        Text(manager.showPOIDetailCardExpanded ? "收起" : "详情")
                            .font(.system(size: 10, weight: .bold))
                        Image(systemName: manager.showPOIDetailCardExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(httGold)
                    .cornerRadius(6)
                }
                
                Button(action: {
                    withAnimation { manager.dismissTappedPoint() }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            // Row 2: Rating Badge (4.4 好好) + Tags (收录1年 · 外卖服务) + Price (¥41/人 火锅)
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Text(manager.tappedMapRating)
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                    Text(manager.tappedMapReviewLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.35, green: 0.72, blue: 1.0))
                }
                
                ForEach(manager.tappedMapTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(3)
                }
                
                Text("\(manager.tappedMapPricePerPerson) \(manager.tappedMapCategory)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                
                Spacer()
            }
            
            // Row 3: Operating Status (营业中 / 休息中) + Exact Hours (17:00-06:00) + Sync Live GaoDe Info Button
            HStack(spacing: 6) {
                Text(manager.tappedMapIsOpen ? "營業中" : "休息中")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(manager.tappedMapIsOpen ? Color.green : Color.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background((manager.tappedMapIsOpen ? Color.green : Color.orange).opacity(0.18))
                    .cornerRadius(4)
                
                Text(manager.tappedMapHours)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                

                
                Spacer()
            }
            
            // Row 4: Walking/Driving Time + Detailed Street Address + One-Click Phone Call Button (📞 電話)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(manager.tappedMapWalkDistText) · \(manager.tappedMapAddress)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(httCream.opacity(0.88))
                        .lineLimit(2)
                    Text("聯繫電話：\(manager.tappedMapPhone)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.45, green: 0.82, blue: 1.0))
                }
                
                Spacer()
                
                Button(action: {
                    manager.callTappedMerchantPhone()
                }) {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "phone.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            Text("訂座")
                                .font(.system(size: 7, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.blue)
                                .cornerRadius(3)
                                .offset(x: 6, y: -4)
                        }
                        Text("電話")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 6)
                }
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            // Row 6: Bottom Action Bar matching GaoDe Screenshot 5 (搜周边 · 顺风车 · 打车[红包] · 导航 · 路线)
            HStack(spacing: 10) {
                // 1. 路线 (View Multi-Mode Route & Transit Sheet)
                Button(action: {
                    guard let coord = manager.tappedMapCoord else { return }
                    let title = manager.tappedMapTitle.isEmpty ? "目的地" : manager.tappedMapTitle
                    manager.tappedMapCoord = nil
                    manager.calculateAndStartRoute(to: coord, title: title)
                    if manager.travelMode == .transit {
                        manager.showTransitPlanSheet = true
                    }
                }) {
                    Text(tr("路线", "路線", "Routes"))
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.35), lineWidth: 1))
                }
                
                // 2. 导航 (Start Immediate Turn-by-Turn Navigation)
                Button(action: {
                    manager.startNavigationToTappedPoint()
                    manager.startFocusedNavigation()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(tr("导航", "導航", "Start"))
                            .font(.system(size: 14, weight: .black))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(LinearGradient(colors: [Color.blue, Color(red: 0.0, green: 0.48, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
                    .shadow(color: Color.blue.opacity(0.4), radius: 4)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.96))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(httGold.opacity(0.85), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.55), radius: 10)
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
        // Row 1: 4 Travel Modes Direct Switcher (Car / e-Bike / Walk / Transit)
    private var travelModesRow: some View {
        HStack(spacing: 5) {
            ForEach(NavigationTravelMode.allCases) { mode in
                let isSelected = (manager.travelMode == mode)
                Button(action: {
                    manager.stop()
                    manager.travelMode = mode
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 14, weight: .bold))
                        Text(mode.title(manager.language))
                            .font(.system(size: 12, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isSelected
                        ? LinearGradient(colors: [Color(red: 0.95, green: 0.22, blue: 0.26), httCrimson], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.black.opacity(0.8), Color(white: 0.15).opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    )
                    .foregroundColor(isSelected ? .white : httCream)
                    .cornerRadius(9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isSelected ? httGold : Color.white.opacity(0.25), lineWidth: isSelected ? 1.8 : 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // Row 2: RM-500HTT Outfit + Camera Mode + Birthday Special
    private var outfitCameraGiftRow: some View {
        HStack(spacing: 5) {
            // Outfit Button: Tap to cycle, Long-press to open Beautified Wardrobe Popup!
            HStack(spacing: 4) {
                Image(systemName: manager.arrowOutfit.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(httGold)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("车标换装", "車標換裝", "Outfit"))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(manager.arrowOutfit.title(manager.language))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(httGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("视角模式", "視角模式", "Camera"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(manager.cameraMode.title(manager.language))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.cyan)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.75))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.6), lineWidth: 1.2))
            }
            
            // Birthday Special Voice Button [特典音] (Never clips!)
            Button(action: {
                manager.triggerBirthdaySpecialVoice()
            }) {
                VStack(spacing: 2) {
                    if let giftImg = manager.getRM500UIImage("rm_gift_yui") {
                        Image(uiImage: giftImg)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.pink)
                    }
                    Text(tr("特典音", "特典音", "Gift"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(width: 52, height: 38)
                .background(Color(red: 0.72, green: 0.22, blue: 0.48).opacity(0.88))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold.opacity(0.65), lineWidth: 1.2))
            }
        }
    }

    // Portrait Combined Dock (竖屏保持原样不动)
    private var portraitBottomCompanionDock: some View {
        VStack(spacing: 7) {
            travelModesRow
            outfitCameraGiftRow
        }
    }

    private func tacticalButton(title: String, subtitle: String, icon: String, color: Color, isCompact: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: isCompact ? 1.5 : 3) {
                Image(systemName: icon)
                    .font(.system(size: isCompact ? 12 : 14, weight: .bold))
                    .foregroundColor(httCream)
                Text(title)
                    .font(.system(size: isCompact ? 10.5 : 12, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.system(size: isCompact ? 8 : 9))
                    .foregroundColor(httCream.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 5 : 7)
            .padding(.horizontal, 3)
            .background(color)
            .cornerRadius(11)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(httGold.opacity(0.8), lineWidth: 1.4)
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
                
                // Driving Highway Preference Selector in Search Sheet (Enlarged!)
                if selectedMode == .driving {
                    HStack(spacing: 8) {
                        ForEach(RouteStrategyPreference.allCases) { pref in
                            Button(action: {
                                manager.routePreference = pref
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: pref.icon)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(pref.title(manager.language))
                                        .font(.system(size: 13, weight: .heavy))
                                }
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(manager.routePreference == pref ? Color.orange : Color(UIColor.tertiarySystemFill))
                                .foregroundColor(manager.routePreference == pref ? .white : .primary)
                                .cornerRadius(9)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // One-Click External App / Clipboard Quick Navigation Bar
                Button(action: {
                    dismiss()
                    manager.parseSmartClipboardAndNavigate()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.forward.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(manager.language == .en
                             ? "One-Click Navigate from Copied Address / App Link"
                             : (manager.language == .zhHant ? "一鍵識別外部App複製的地址/分享連結並直接導航" : "一键识别外部App复制的地址/分享链接并直接导航"))
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(9)
                    .padding(.horizontal)
                }
                
                // Pinyin-Safe Native Search Bar + Search Button
                HStack(spacing: 4) {
                    NativePinyinSearchBar(
                        text: $queryText,
                        placeholder: manager.language == .en ? "Search station, mall, road or city..." : (manager.language == .zhHant ? "輸入目的地（如：廣州南站、羅湖口岸、大廈）..." : "输入目的地（如：广州南站、罗湖口岸、大厦）..."),
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
                        Text(manager.language == .en ? "Search" : (manager.language == .zhHant ? "搜尋" : "搜索"))
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
                             : (manager.language == .zhHant ? "室內一鍵測試：模擬路線指路（完整聽轉向原聲）" : "室内一键测试：模拟路线指路（完整听转向原声）"))
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
                        Text(manager.language == .en ? "Searching places..." : (manager.language == .zhHant ? "正在檢索全城及周邊詳細地點..." : "正在检索全城及周边详细地点..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // Combined List: Direct POI MapItems (with Distance!) + Rich Autocomplete Sub-entrances (East/West Plaza, Parking, Metro, etc.)
                List {
                    if !searchEngine.mapItems.isEmpty {
                        Section(header: Text(manager.language == .en ? "Exact Matches (\(searchEngine.mapItems.count))" : (manager.language == .zhHant ? "精準地點結果 (\(searchEngine.mapItems.count) 個)" : "精准地点结果 (\(searchEngine.mapItems.count) 个)"))) {
                            ForEach(searchEngine.mapItems, id: \.self) { item in
                                Button(action: {
                                    manager.travelMode = selectedMode
                                    manager.isMapEnlarged = true
                                    manager.showMapMode = true
                                    manager.startRouteGuidance(to: item)
                                    dismiss()
                                    if selectedMode == .transit {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                            manager.showTransitPlanSheet = true
                                        }
                                    }
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedMode.icon)
                                            .font(.title3)
                                            .foregroundColor(.red)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name ?? (manager.language == .zhHant ? "未知地點" : "未知地点"))
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
                                            Text(manager.language == .en ? "Go" : (manager.language == .zhHant ? "去這裡" : "去这里"))
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
                        Section(header: Text(manager.language == .en ? "Suggestions & Entrances (\(searchEngine.completions.count))" : (manager.language == .zhHant ? "全城聯想與詳細出入口 (\(searchEngine.completions.count) 個)" : "全城联想与详细出入口 (\(searchEngine.completions.count) 个)"))) {
                            ForEach(searchEngine.completions, id: \.self) { comp in
                                Button(action: {
                                    manager.travelMode = selectedMode
                                    manager.isMapEnlarged = true
                                    manager.showMapMode = true
                                    searchEngine.resolveAndStartNavigation(for: comp, manager: manager) {
                                        dismiss()
                                        if selectedMode == .transit {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                                manager.showTransitPlanSheet = true
                                            }
                                        }
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
                                        Text(manager.language == .en ? "Navigate" : (manager.language == .zhHant ? "開始導航" : "开始导航"))
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
            .navigationTitle(manager.language == .en ? "Route Planner" : (manager.language == .zhHant ? "高德/MapKit 智慧路線搜尋" : "高德/MapKit 智能路线搜索"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Close" : (manager.language == .zhHant ? "關閉" : "关闭")) { dismiss() }
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
            (lang == .en ? "Bonus & Birthdays (11)" : (lang == .zhHant ? "全收集與生日彩蛋 (11)" : "全收集与生日彩蛋 (11)"), Array(1112...1122))
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
            .navigationTitle(manager.language == .en ? "Voice DB" : (manager.language == .zhHant ? "已校準純享角色語音庫" : "已校准纯享角色语音库"))
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
                    Text(manager.language == .en ? "Outfits" : (manager.language == .zhHant ? "導航換裝" : "导航换装")).tag(0)
                    Text(manager.language == .en ? "Album" : (manager.language == .zhHant ? "紀念相冊" : "纪念相册")).tag(1)
                    Text(manager.language == .en ? "Author & Feedback" : (manager.language == .zhHant ? "製作作者與BUG反饋" : "制作作者与BUG反馈")).tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                if selectedTab == 0 {
                    ScrollView {
                        VStack(spacing: 14) {
                            // Live Preview Card of Current RM-500HTT Navigation Arrow
                            VStack(spacing: 8) {
                                Text(manager.language == .en ? "Current Navigation Arrow Preview" : (manager.language == .zhHant ? "當前地圖自車導航箭頭預覽" : "当前地图自车导航箭头预览"))
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
                                        Text(manager.language == .en ? "Enable RM-500HTT Original Starry Background Skin" : (manager.language == .zhHant ? "啟用 RM-500HTT 原版角色星光斜紋背景皮膚" : "启用 RM-500HTT 原版角色星光斜纹背景皮肤"))
                                            .font(.subheadline.bold())
                                        Text(manager.language == .en ? "Auto-switches Red/Blue/Yellow/Pink/Green starry background" : (manager.language == .zhHant ? "隨所選角色自動切換紅/藍/黃/粉/綠專屬星光底圖" : "随所选角色自动切换红/蓝/黄/粉/绿专属星光底图"))
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
                                Text(manager.language == .en ? "Select RM-500HTT Original Navigation Arrow Outfit" : (manager.language == .zhHant ? "選擇 RM-500HTT 原版導航自車箭頭服裝" : "选择 RM-500HTT 原版导航自车箭头服装"))
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
                                                Text(outfit == .tonchan
                                                     ? (manager.language == .en ? "K-ON! Pet Pig-Nosed Turtle Swimming Arrow" : (manager.language == .zhHant ? "輕音部寵物小豬(豬鼻龜)專屬游泳導航車標" : "轻音部宠物小猪(猪鼻龟)专属游泳导航车标"))
                                                     : (manager.language == .en ? "Supports 12-direction turning & walking animation" : (manager.language == .zhHant ? "支援 12 方向精準轉向與行車邁步動畫" : "支持 12 方向精准转向与行车迈步动画")))
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
                } else if selectedTab == 2 {
                    // Tab 2: Author & Bug Feedback (制作作者与BUG反馈)
                    AboutAndFeedbackContentView(manager: manager)
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
                                            Label(manager.language == .en ? "Prev" : (manager.language == .zhHant ? "上一張" : "上一张"), systemImage: "chevron.left.circle.fill")
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
                                            Label(manager.language == .en ? "Next" : (manager.language == .zhHant ? "下一張" : "下一张"), systemImage: "chevron.right.circle.fill")
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
            .navigationTitle(manager.language == .en ? "RM-500HTT Collection" : "RM-500HTT 典藏中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Done" : "完成") { dismiss() }
                }
            }
        }
    }
}


// MARK: - Native Built-In GaoDe-Style Transit, Intercity Rail & High-Speed Train Modal Sheet (高德同款跨城火车/城际/地铁公交全能面板)
struct InAppTransitPlanSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var expandedStepIds: Set<UUID> = []
    
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    
        private func sheetPlanTabButton(plan: TransitPlanOption, index: Int) -> some View {
        let isSel = (manager.selectedTransitPlanIndex == index)
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                manager.selectTransitPlan(at: index)
            }
        }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.badge)
                    .font(.system(size: 12, weight: .black))
                Text(plan.shortPriceSummary)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                Text(plan.transferAndWalkSummary)
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.85)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSel ? Color.purple : Color.white.opacity(0.10))
            .foregroundColor(.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSel ? httGold : Color.clear, lineWidth: 2)
            )
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.11, green: 0.10, blue: 0.12).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 1. Plan Tabs (方案1/方案2/方案3)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(manager.transitPlans.enumerated()), id: \.element.id) { idx, plan in
                                sheetPlanTabButton(plan: plan, index: idx)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .background(Color.black.opacity(0.6))
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // 2. Active Plan Detailed Station & Transfer Timeline (高德同款：支持跨城火车卡片、顺风车卡片、城际铁路与市内地铁公交)
                    if manager.transitPlans.isEmpty || manager.destinationCoord == nil {
                        VStack(spacing: 14) {
                            Spacer()
                            Image(systemName: "tram.fill")
                                .font(.system(size: 44))
                                .foregroundColor(httGold)
                            Text("暂无有效导航目的地")
                                .font(.system(size: 17, weight: .black))
                                .foregroundColor(.white)
                            Text("请先在地图上点击选择目的地，或输入搜索终点并点击【路线/导航】，即可自动规划推荐公交地铁换乘方案。")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                            Button(action: { dismiss() }) {
                                Text("返回地图选点")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(httGold)
                                    .cornerRadius(18)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if manager.selectedTransitPlanIndex < manager.transitPlans.count {
                        let activePlan = manager.transitPlans[manager.selectedTransitPlanIndex]
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                // IF CROSS-CITY OR NATIONWIDE LONG-DISTANCE: Show GaoDe Flight (✈️ 飛機) + Normal Train (🚂 火車) + High-Speed Rail (🚄 高鐵動車) matching Screenshot 3 & 4!
                                if let ic = activePlan.intercityBanner {
                                    VStack(spacing: 12) {
                                        // 1. IF LONG-DISTANCE FLIGHT AVAILABLE: Show ✈️ 飛機 Card (宝安机场 -> 浦东机场 / 虹桥机场)
                                        if ic.hasFlightOption {
                                            VStack(alignment: .leading, spacing: 10) {
                                                HStack {
                                                    Image(systemName: "airplane")
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(5)
                                                        .background(Color.blue)
                                                        .cornerRadius(6)
                                                    Text("飛機")
                                                        .font(.system(size: 17, weight: .black))
                                                        .foregroundColor(.white)
                                                    Spacer()
                                                    Text("\(ic.flight1Duration)  \(ic.flight1TotalFrom)")
                                                        .font(.system(size: 15, weight: .black))
                                                        .foregroundColor(httGold)
                                                }
                                                
                                                // Flight Option 1 (Direct Low Price: 宝安机场 -> 浦东机场 ¥580起)
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack {
                                                        Text("\(ic.flight1Duration) \(ic.flight1TotalFrom)")
                                                            .font(.system(size: 14, weight: .black))
                                                            .foregroundColor(.white)
                                                        Spacer()
                                                        Text(ic.flight1Badge)
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(Color.green)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.green.opacity(0.16))
                                                            .cornerRadius(4)
                                                    }
                                                    
                                                    HStack(spacing: 6) {
                                                        Circle().stroke(Color.green, lineWidth: 2).frame(width: 8, height: 8)
                                                        Text("去機場")
                                                            .foregroundColor(.gray)
                                                        Button(action: { manager.openGaoDeLivePortal(mode: 0) }) {
                                                            Text(ic.flight1ToAirportText)
                                                                .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                        }
                                                    }
                                                    .font(.system(size: 11, weight: .bold))
                                                    
                                                    HStack {
                                                        Image(systemName: "airplane")
                                                            .foregroundColor(.blue)
                                                        Text(ic.flight1FromAirport)
                                                            .font(.system(size: 15, weight: .black))
                                                            .foregroundColor(.white)
                                                        Spacer()
                                                        VStack(spacing: 2) {
                                                            Text(ic.flight1AirTime)
                                                                .font(.system(size: 10, weight: .bold))
                                                                .foregroundColor(.gray)
                                                            Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 55, height: 1)
                                                            Text(ic.flight1CountText)
                                                                .font(.system(size: 10, weight: .bold))
                                                                .foregroundColor(.gray)
                                                        }
                                                        Spacer()
                                                        Text(ic.flight1ToAirport)
                                                            .font(.system(size: 15, weight: .black))
                                                            .foregroundColor(.white)
                                                        Text(ic.flight1TicketPrice)
                                                            .font(.system(size: 15, weight: .black))
                                                            .foregroundColor(.orange)
                                                        Button(action: { manager.openFlightTicketsSheet() }) {
                                                            Text("全部\n班次")
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                                .padding(5)
                                                                .background(Color.blue.opacity(0.15))
                                                                .cornerRadius(5)
                                                        }
                                                    }
                                                    .padding(9)
                                                    .background(Color.white.opacity(0.08))
                                                    .cornerRadius(8)
                                                    
                                                    HStack(spacing: 6) {
                                                        Circle().stroke(Color.red, lineWidth: 2).frame(width: 8, height: 8)
                                                        Text("去終點")
                                                            .foregroundColor(.gray)
                                                        Text(ic.flight1ToDestText)
                                                            .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                    }
                                                    .font(.system(size: 11, weight: .bold))
                                                }
                                                
                                                Divider().background(Color.white.opacity(0.12))
                                                
                                                // Flight Option 2 (Fastest: 宝安机场 -> 虹桥机场 ¥1825起)
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack {
                                                        Text("\(ic.flight2Duration) \(ic.flight2TotalFrom)")
                                                            .font(.system(size: 14, weight: .black))
                                                            .foregroundColor(.white)
                                                        Spacer()
                                                        Text(ic.flight2Badge)
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(Color.green)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.green.opacity(0.16))
                                                            .cornerRadius(4)
                                                    }
                                                    
                                                    HStack {
                                                        Image(systemName: "airplane")
                                                            .foregroundColor(.blue)
                                                        Text(ic.flight1FromAirport)
                                                            .font(.system(size: 15, weight: .black))
                                                            .foregroundColor(.white)
                                                        Spacer()
                                                        VStack(spacing: 2) {
                                                            Text(ic.flight2AirTime)
                                                                .font(.system(size: 10, weight: .bold))
                                                                .foregroundColor(.gray)
                                                            Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 55, height: 1)
                                                            Text(ic.flight2CountText)
                                                                .font(.system(size: 10, weight: .bold))
                                                                .foregroundColor(.gray)
                                                        }
                                                        Spacer()
                                                        Text(ic.flight2ToAirport)
                                                            .font(.system(size: 15, weight: .black))
                                                            .foregroundColor(.white)
                                                        Text(ic.flight2TicketPrice)
                                                            .font(.system(size: 15, weight: .black))
                                                            .foregroundColor(.orange)
                                                        Button(action: { manager.openFlightTicketsSheet() }) {
                                                            Text("全部\n班次")
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                                .padding(5)
                                                                .background(Color.blue.opacity(0.15))
                                                                .cornerRadius(5)
                                                        }
                                                    }
                                                    .padding(9)
                                                    .background(Color.white.opacity(0.08))
                                                    .cornerRadius(8)
                                                    
                                                    HStack(spacing: 6) {
                                                        Circle().stroke(Color.red, lineWidth: 2).frame(width: 8, height: 8)
                                                        Text("去終點")
                                                            .foregroundColor(.gray)
                                                        Text(ic.flight2ToDestText)
                                                            .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                    }
                                                    .font(.system(size: 11, weight: .bold))
                                                }
                                            }
                                            .padding(12)
                                            .background(Color.black.opacity(0.58))
                                            .cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.45), lineWidth: 1))
                                        }
                                        
                                        // 2. IF NORMAL SLEEPER TRAIN AVAILABLE: Show 🚂 火車 Card (深圳东 -> 嘉兴 ¥223.5起)
                                        if ic.hasNormalTrainOption {
                                            VStack(alignment: .leading, spacing: 10) {
                                                HStack {
                                                    Image(systemName: "tram.fill")
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(5)
                                                        .background(Color.blue)
                                                        .cornerRadius(6)
                                                    Text("火車")
                                                        .font(.system(size: 17, weight: .black))
                                                        .foregroundColor(.white)
                                                    Spacer()
                                                    Text("\(ic.normalTrainDuration)  \(ic.normalTrainTotalFrom)")
                                                        .font(.system(size: 15, weight: .black))
                                                        .foregroundColor(httGold)
                                                }
                                                
                                                HStack(spacing: 6) {
                                                    Circle().stroke(Color.green, lineWidth: 2).frame(width: 8, height: 8)
                                                    Text("去火車站")
                                                        .foregroundColor(.gray)
                                                    Button(action: { manager.openGaoDeLivePortal(mode: 0) }) {
                                                        Text(ic.normalTrainToStText)
                                                            .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                    }
                                                }
                                                .font(.system(size: 11, weight: .bold))
                                                
                                                HStack {
                                                    Image(systemName: "tram.fill")
                                                        .foregroundColor(.blue)
                                                    Text(ic.normalTrainFromSt)
                                                        .font(.system(size: 15, weight: .black))
                                                        .foregroundColor(.white)
                                                    Spacer()
                                                    VStack(spacing: 2) {
                                                        Text(ic.normalTrainRunTime)
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(.gray)
                                                        Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 55, height: 1)
                                                        Text(ic.normalTrainCountText)
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(.gray)
                                                    }
                                                    Spacer()
                                                    Text(ic.normalTrainToSt)
                                                        .font(.system(size: 15, weight: .black))
                                                        .foregroundColor(.white)
                                                    Text(ic.normalTrainTicketPrice)
                                                        .font(.system(size: 15, weight: .black))
                                                        .foregroundColor(.orange)
                                                    Button(action: { manager.openGaoDeLivePortal(mode: 2) }) {
                                                        Text("全部\n班次")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                            .padding(5)
                                                            .background(Color.blue.opacity(0.15))
                                                            .cornerRadius(5)
                                                    }
                                                }
                                                .padding(9)
                                                .background(Color.white.opacity(0.08))
                                                .cornerRadius(8)
                                                
                                                HStack(spacing: 6) {
                                                    Circle().stroke(Color.red, lineWidth: 2).frame(width: 8, height: 8)
                                                    Text("去終點")
                                                        .foregroundColor(.gray)
                                                    Text(ic.normalTrainToDestText)
                                                        .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                }
                                                .font(.system(size: 11, weight: .bold))
                                            }
                                            .padding(12)
                                            .background(Color.black.opacity(0.58))
                                            .cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.45), lineWidth: 1))
                                        }
                                        
                                        // 3. Card C: 🚄 高鐵動車 (High-Speed Rail Overview Card: 深圳北 -> 上海南 ¥845起)
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Image(systemName: "train.side.front.car")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(5)
                                                    .background(Color.blue)
                                                    .cornerRadius(6)
                                                Text(ic.hasFlightOption ? "高鐵動車" : "火車 / 高鐵跨城方案")
                                                    .font(.system(size: 17, weight: .black))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Text("\(ic.durationText)  \(ic.startPriceText)")
                                                    .font(.system(size: 15, weight: .black))
                                                    .foregroundColor(httGold)
                                            }
                                            
                                            HStack(spacing: 6) {
                                                Circle().stroke(Color.green, lineWidth: 2).frame(width: 8, height: 8)
                                                Text("去火車站")
                                                    .foregroundColor(.gray)
                                                Button(action: { manager.openGaoDeLivePortal(mode: 0) }) {
                                                    Text(ic.toStationBusText)
                                                        .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                }
                                            }
                                            .font(.system(size: 12, weight: .bold))
                                            
                                            // Train Ticket Box (深圳北 ➔ 上海南 ¥845起 [全部班次])
                                            HStack {
                                                Image(systemName: "tram.fill")
                                                    .foregroundColor(.blue)
                                                Text(ic.fromTrainSt)
                                                    .font(.system(size: 15, weight: .black))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                VStack(spacing: 2) {
                                                    Text(ic.trainRunTime)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.gray)
                                                    Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 60, height: 1)
                                                    Text(ic.trainFreqText)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.gray)
                                                }
                                                Spacer()
                                                Text(ic.toTrainSt)
                                                    .font(.system(size: 15, weight: .black))
                                                    .foregroundColor(.white)
                                                Text(ic.trainTicketPrice)
                                                    .font(.system(size: 15, weight: .black))
                                                    .foregroundColor(.orange)
                                                Button(action: { manager.openTrainTicketsSheet() }) {
                                                    Text("全部\n班次")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                                        .padding(5)
                                                        .background(Color.blue.opacity(0.15))
                                                        .cornerRadius(5)
                                                }
                                            }
                                            .padding(10)
                                            .background(Color.white.opacity(0.08))
                                            .cornerRadius(8)
                                            
                                            HStack(spacing: 6) {
                                                Circle().stroke(Color.red, lineWidth: 2).frame(width: 8, height: 8)
                                                Text("去終點")
                                                    .foregroundColor(.gray)
                                                Text(ic.fromStationBusText)
                                                    .foregroundColor(Color(red: 0.4, green: 0.78, blue: 1.0))
                                            }
                                            .font(.system(size: 12, weight: .bold))
                                        }
                                        .padding(12)
                                        .background(Color.black.opacity(0.55))
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.45), lineWidth: 1))
                                        

                                    }
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                                }
                                
                                // GaoDe Summary strip (5小時20分 步行3.8公里 + 🚶40 [地鐵3號綫] [惠州208路] [城際(惠州北-番禺)] 🚶17 + 首班車提醒!)
                                VStack(alignment: .leading, spacing: 9) {
                                    if !activePlan.warningNotice.isEmpty {
                                        Text(activePlan.warningNotice)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.38))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.red.opacity(0.16))
                                            .cornerRadius(6)
                                    }
                                    
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(activePlan.formattedDuration)
                                            .font(.system(size: 24, weight: .black))
                                            .foregroundColor(.white)
                                        Text(activePlan.formattedWalk)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Text("¥\(activePlan.priceYuan)")
                                            .font(.system(size: 18, weight: .black))
                                            .foregroundColor(httGold)
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Text(activePlan.formattedWalk)
                                        Text("·")
                                        Text("\(activePlan.totalStations) 站")
                                        Text("·")
                                        Text(activePlan.startExitDesc)
                                            .foregroundColor(Color(red: 0.45, green: 0.85, blue: 1.0))
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(httCream.opacity(0.85))
                                    
                                    // GaoDe Step Overview Pill Bar (🚶40 -> [地鐵3號綫] -> [惠州208路] -> [城際(惠州北--番禺)] -> 🚶17)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(Array(activePlan.steps.enumerated()), id: \.element.id) { idx, st in
                                                if st.kind == .walk {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: "figure.walk")
                                                            .font(.system(size: 10, weight: .bold))
                                                        Text("\(st.durationMins)分鐘")
                                                            .font(.system(size: 11, weight: .bold))
                                                    }
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
                                                    .background(Color.white.opacity(0.12))
                                                    .foregroundColor(httCream)
                                                    .cornerRadius(5)
                                                } else if st.kind == .bus {
                                                    Text(st.lineName)
                                                        .font(.system(size: 11, weight: .black))
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.blue.opacity(0.12))
                                                        .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                                                        .cornerRadius(5)
                                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue, lineWidth: 1.2))
                                                } else {
                                                    HStack(spacing: 3) {
                                                        if st.kind == .intercity || st.kind == .train {
                                                            Image(systemName: "tram.fill")
                                                                .font(.system(size: 10))
                                                        }
                                                        Text(st.lineName)
                                                            .font(.system(size: 11, weight: .black))
                                                    }
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(stepColor(for: st))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(5)
                                                }
                                            }
                                        }
                                    }
                                    
                                    if !activePlan.realtimeArrivalText.isEmpty {
                                        Button(action: {
                                            if activePlan.realtimeArrivalText.contains("班") || activePlan.realtimeArrivalText.contains("車") || activePlan.realtimeArrivalText.contains("车") {
                                                manager.openTrainTicketsSheet()
                                            } else {
                                                manager.openGaoDeLivePortal(mode: 2)
                                            }
                                        }) {
                                            HStack {
                                                Text(activePlan.realtimeArrivalText)
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(Color.green)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.08))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.45))
                                
                                // Vertical Step-by-Step Timeline (含可开合站台与车厢强冷/弱冷)
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(activePlan.steps.enumerated()), id: \.element.id) { stepIdx, step in
                                        HStack(alignment: .top, spacing: 14) {
                                            // Left Icon & Vertical Track Line
                                            VStack(spacing: 0) {
                                                Circle()
                                                    .fill(stepColor(for: step))
                                                    .frame(width: 28, height: 28)
                                                    .overlay(
                                                        Image(systemName: step.kind.icon)
                                                            .font(.system(size: 13, weight: .bold))
                                                            .foregroundColor(.white)
                                                    )
                                                
                                                if stepIdx < activePlan.steps.count - 1 {
                                                    Rectangle()
                                                        .fill(stepColor(for: step).opacity(0.6))
                                                        .frame(width: 3)
                                                        .frame(minHeight: 52)
                                                }
                                            }
                                            
                                            // Right Step Info
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text(step.fromStation)
                                                        .font(.system(size: 16, weight: .black))
                                                        .foregroundColor(.white)
                                                    
                                                    if !step.exitDesc.isEmpty && step.kind == .walk {
                                                        Text(step.exitDesc)
                                                            .font(.system(size: 11, weight: .bold))
                                                            .foregroundColor(Color(red: 0.45, green: 0.85, blue: 1.0))
                                                    }
                                                }
                                                
                                                if step.kind != .walk {
                                                    // Line Name Badge & Direction
                                                    HStack(spacing: 6) {
                                                        Text(step.lineName)
                                                            .font(.system(size: 12, weight: .black))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 3)
                                                            .background(stepColor(for: step))
                                                            .foregroundColor(.white)
                                                            .cornerRadius(5)
                                                        
                                                        Text(step.directionDesc)
                                                            .font(.system(size: 12, weight: .bold))
                                                            .foregroundColor(.gray)
                                                    }
                                                    
                                                    // Air-conditioning / Realtime Notice
                                                    if !step.acNotice.isEmpty {
                                                        Text(step.acNotice)
                                                            .font(.system(size: 10, weight: .medium))
                                                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                                                    }
                                                    
                                                    // Expandable / Collapsible Stations Badge (^ X站 (X分钟)) - 可开合！
                                                    if !step.passStations.isEmpty {
                                                        VStack(alignment: .leading, spacing: 5) {
                                                            Button(action: {
                                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                                    if expandedStepIds.contains(step.id) {
                                                                        expandedStepIds.remove(step.id)
                                                                    } else {
                                                                        expandedStepIds.insert(step.id)
                                                                    }
                                                                }
                                                            }) {
                                                                HStack(spacing: 5) {
                                                                    Image(systemName: expandedStepIds.contains(step.id) ? "chevron.up" : "chevron.down")
                                                                        .font(.system(size: 10, weight: .bold))
                                                                    Text("\(step.passStations.count + 1) 站 (\(step.durationMins) 分钟)")
                                                                        .font(.system(size: 12, weight: .heavy))
                                                                    Text(expandedStepIds.contains(step.id) ? "点击收起站台" : "点击展开经停车站")
                                                                        .font(.system(size: 10, weight: .medium))
                                                                        .opacity(0.8)
                                                                }
                                                                .foregroundColor(Color.cyan)
                                                                .padding(.horizontal, 8)
                                                                .padding(.vertical, 4)
                                                                .background(Color.cyan.opacity(0.12))
                                                                .cornerRadius(6)
                                                            }
                                                            
                                                            // Expanded Station Sub-List (垂直站点连线)
                                                            if expandedStepIds.contains(step.id) {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    ForEach(step.passStations, id: \.self) { stName in
                                                                        HStack(spacing: 8) {
                                                                            Circle()
                                                                                .fill(Color.gray.opacity(0.7))
                                                                                .frame(width: 5, height: 5)
                                                                            Text(stName)
                                                                                .font(.system(size: 12, weight: .medium))
                                                                                .foregroundColor(.white.opacity(0.9))
                                                                        }
                                                                        .padding(.leading, 8)
                                                                    }
                                                                }
                                                                .padding(.vertical, 4)
                                                                .transition(.opacity.combined(with: .move(edge: .top)))
                                                            }
                                                        }
                                                    }
                                                    
                                                    // Interval & First/Last Train Desc
                                                    if !step.intervalDesc.isEmpty {
                                                        Text(step.intervalDesc)
                                                            .font(.system(size: 10, weight: .medium))
                                                            .foregroundColor(.gray)
                                                    }
                                                    
                                                    // Target Destination Station & Door Side
                                                    HStack {
                                                        Text(step.toStation)
                                                            .font(.system(size: 15, weight: .black))
                                                            .foregroundColor(.white)
                                                        
                                                        if !step.doorSideDesc.isEmpty {
                                                            Text(step.doorSideDesc)
                                                                .font(.system(size: 11, weight: .bold))
                                                                .foregroundColor(httGold)
                                                                .padding(.horizontal, 5)
                                                                .padding(.vertical, 2)
                                                                .background(Color.black.opacity(0.6))
                                                                .cornerRadius(4)
                                                        }
                                                    }
                                                    .padding(.top, 2)
                                                } else if step.kind == .walk {
                                                    // Walking segment description & duration
                                                    Text(step.intervalDesc)
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(httCream.opacity(0.85))
                                                    
                                                    // One-click Walking Navigation Button
                                                    if stepIdx == 0 {
                                                        Button(action: {
                                                            dismiss()
                                                            manager.startTransitWalkingNavigation()
                                                        }) {
                                                            HStack(spacing: 5) {
                                                                Image(systemName: "figure.walk.circle.fill")
                                                                    .font(.system(size: 13, weight: .bold))
                                                                Text("开启第一段步行实景导航 (前往 \(step.toStation))")
                                                                    .font(.system(size: 11, weight: .bold))
                                                            }
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 5)
                                                            .background(Color.green.opacity(0.2))
                                                            .foregroundColor(Color.green)
                                                            .cornerRadius(6)
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.bottom, 18)
                                            
                                            Spacer()
                                        }
                                    }
                                }
                                .padding()
                            }
                        }
                    } else {
                        // Loading fallback
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: httGold))
                                .scaleEffect(1.4)
                            Text("正在根据您当前位置匹配最佳跨城/市内公共交通路线...")
                                .font(.subheadline.bold())
                                .foregroundColor(httCream)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // 3. Bottom One-Click Start Guidance in App (Zero External Jump!)
                    Button(action: {
                        dismiss()
                        manager.startTransitWalkingNavigation()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "tram.circle.fill")
                                .font(.title3)
                            Text("开始全流程乘车指引 (含步行导航)")
                                .font(.system(size: 15, weight: .black))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color(red: 0.65, green: 0.25, blue: 0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(httGold, lineWidth: 1.8))
                        .padding()
                    }
                }
            }
            .navigationTitle("放课后茶会 · 内置公交地铁导航")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundColor(httGold)
                }
            }
            .onAppear {
                manager.refreshTransitPlansForCurrentLocation(force: true)
            }
        }
        .sheet(isPresented: $manager.showAllFlightTicketsSheet) {
            InAppFlightTicketScheduleSheetView(manager: manager)
        }
        .sheet(isPresented: $manager.showAllTrainTicketsSheet) {
            InAppTrainTicketScheduleSheetView(manager: manager)
        }
    }
    
    private func stepColor(for step: TransitStepItem) -> Color {
        switch step.kind {
        case .walk:
            return Color.gray
        case .subway:
            return Color(hex: step.colorHex) ?? Color.purple
        case .bus:
            return Color(hex: step.colorHex) ?? Color(red: 0.12, green: 0.47, blue: 0.94)
        case .intercity:
            return Color(hex: step.colorHex) ?? Color(red: 0.48, green: 0.70, blue: 0.02)
        case .train:
            return Color(hex: step.colorHex) ?? Color.blue
        }
    }
}


extension Color {
    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgb = UInt64(cleanHex, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}


// MARK: - 100% Native In-App GaoDe Service Hub (聚合打车 / 跨城顺风车 / 实时班次票务 / 商家全部商品与评价 - 零网页弹窗、零跳转高德App!)
struct GaoDeLiveWebPortalSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var phoneInput: String = ""
    @State private var smsCodeInput: String = ""
    @State private var smsSent: Bool = false
    @State private var selectedCarIndex: Int = 0
    @State private var selectedSeatType: Int = 0 // 0: 拼座, 1: 独享
    @State private var bookingToast: String = ""
    
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    
    private var currentDestTitle: String {
        if !manager.tappedMapTitle.isEmpty { return manager.tappedMapTitle }
        if !manager.destinationName.isEmpty { return manager.destinationName }
        return "所选目的地"
    }
    
    private var currentDestAddress: String {
        if !manager.tappedMapAddress.isEmpty { return manager.tappedMapAddress }
        return "已根据当前实时GPS锁定终点坐标"
    }
    
    private var currentDistKm: Double {
        if let tc = manager.tappedMapCoord {
            let loc1 = CLLocation(latitude: manager.userCoordinate.latitude, longitude: manager.userCoordinate.longitude)
            let loc2 = CLLocation(latitude: tc.latitude, longitude: tc.longitude)
            return max(1.2, loc1.distance(from: loc2) / 1000.0)
        }
        return max(3.5, manager.remainingRouteDistanceKm)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.12).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 1. Top 4-Tab Switcher (🚕 聚合打车 / 🚗 顺风车 / 🚄 班次票务 / 🏪 商家详情)
                    HStack(spacing: 12) {
                        portalTabButton(title: "🚄 班次票務", mode: 2)
                        portalTabButton(title: "🏪 商家詳情", mode: 3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.92))
                    
                    // 2. In-App Account Bar (Built-in Login without jumping to external Amap!)
                    inAppAccountStatusBar
                    
                    // 3. Route / Merchant Header Card
                    inAppTargetHeaderCard
                    
                    // 4. Main Content Area by Mode
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 12) {
                            if !bookingToast.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(bookingToast)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.green.opacity(0.22))
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green, lineWidth: 1))
                            }
                            
                            if manager.gaoDeWebPortalMode == 0 {
                                nativeTaxiAggregationSection
                            } else if manager.gaoDeWebPortalMode == 1 {
                                nativeHitchhikeSection
                            } else if manager.gaoDeWebPortalMode == 2 {
                                nativeTrainAndFlightSchedulesSection
                            } else {
                                nativeMerchantFullCatalogSection
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle(portalNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(httGold)
                }
            }
        }
    }
    
    private var inAppAccountStatusBar: some View {
        VStack(spacing: 6) {
            if manager.isGaoDeAccountLoggedIn {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(.green)
                    Text("已登錄高德通行證：\(manager.gaoDeAccountPhone) (免密叫車/立減紅包已激活)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("切換賬號") {
                        manager.isGaoDeAccountLoggedIn = false
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(httGold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(red: 0.15, green: 0.22, blue: 0.16))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundColor(httGold)
                        Text("應用內直接登錄打車賬戶 (無需跳轉外部App)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        TextField("輸入手機號碼登錄...", text: $phoneInput)
                            .keyboardType(.numberPad)
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(7)
                        
                        Button(action: {
                            let num = phoneInput.isEmpty ? "13800138000" : phoneInput
                            manager.loginGaoDeAccountInApp(phone: num)
                        }) {
                            Text("一鍵登錄領¥10券")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(httGold)
                                .cornerRadius(7)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.16, green: 0.15, blue: 0.20))
            }
        }
    }
    
    private var inAppTargetHeaderCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("起點：我的當前位置 (實時GPS)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gray)
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("終點：\(currentDestTitle)")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text("\(currentDestAddress) · 距離 \(String(format: "%.1f", currentDistKm)) 公里")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(httCream.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: {
                dismiss()
                if manager.tappedMapCoord != nil {
                    manager.startNavigationToTappedPoint()
                    manager.startFocusedNavigation()
                } else {
                    manager.startFocusedNavigation()
                }
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("直接導航")
                        .font(.system(size: 9, weight: .black))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(httCrimson)
                .cornerRadius(9)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
    }
    
    // MODE 0: Native Ride-Hailing Aggregation (滴滴 / 曹操 / T3 / 享道 / 高德特惠)
    private var nativeTaxiAggregationSection: some View {
        let baseFare = max(12, Int(currentDistKm * 2.6) + 8)
        let tiers: [RideHailingCarTier] = [
            RideHailingCarTier(provider: "高德特惠快車", tierName: "特惠一口價 (陽光/風韻/妥妥E行)", waitMins: 1, priceYuan: baseFare, discountYuan: 5, iconName: "car.fill", colorHex: "#FF6D00"),
            RideHailingCarTier(provider: "滴滴出行 · 快車", tierName: "滴滴快車 · 極速應答", waitMins: 2, priceYuan: baseFare + 3, discountYuan: 3, iconName: "car.circle.fill", colorHex: "#1E88E5"),
            RideHailingCarTier(provider: "曹操出行 · 新能源", tierName: "新能源舒適專享 (純電靜音)", waitMins: 2, priceYuan: baseFare + 4, discountYuan: 4, iconName: "bolt.car.fill", colorHex: "#00897B"),
            RideHailingCarTier(provider: "T3出行 / 享道專車", tierName: "品質專車 · 認證司機", waitMins: 3, priceYuan: baseFare + 11, discountYuan: 6, iconName: "crown.fill", colorHex: "#8E24AA")
        ]
        
        return VStack(alignment: .leading, spacing: 10) {
            if !manager.activeTaxiOrderStatus.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(manager.activeTaxiOrderStatus)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.white)
                    Button("取消呼叫") {
                        manager.activeTaxiOrderStatus = ""
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                }
                .padding(12)
                .background(Color.blue.opacity(0.22))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 1))
            }
            
            Text("高德聚合打車 · 全網比價同時呼叫 (已抵扣紅包)")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(httGold)
            
            ForEach(Array(tiers.enumerated()), id: \.element.id) { idx, tier in
                let isSel = (selectedCarIndex == idx)
                Button(action: {
                    selectedCarIndex = idx
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isSel ? httGold : .gray)
                        
                        Image(systemName: tier.iconName)
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.65))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(tier.provider)
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(.white)
                                Text("\(tier.waitMins)分鐘接駕")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.16))
                                    .cornerRadius(4)
                            }
                            Text(tier.tierName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("預計 ¥\(tier.priceYuan)")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(httGold)
                            Text("已減 ¥\(tier.discountYuan) 紅包")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(11)
                    .background(isSel ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSel ? httGold : Color.clear, lineWidth: 1.5))
                }
            }
            
            Button(action: {
                let chosen = tiers[selectedCarIndex]
                manager.dispatchInAppTaxiOrder(tierName: chosen.provider, price: chosen.priceYuan)
                bookingToast = "✅ 已向附近【\(chosen.provider)】派單！車牌與司機位置將實時同步！"
            }) {
                HStack {
                    Image(systemName: "figure.wave")
                    Text("立即呼叫 \(tiers[selectedCarIndex].provider) (¥\(tiers[selectedCarIndex].priceYuan))")
                        .font(.system(size: 15, weight: .black))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(12)
            }
            .padding(.top, 4)
        }
    }
    
    // MODE 1: Native Hitchhike (高德顺风车 / 哈啰顺风车 市内与跨城拼车)
    private var nativeHitchhikeSection: some View {
        let baseShare = max(10, Int(currentDistKm * 1.15) + 5)
        let baseSolo = max(15, Int(currentDistKm * 1.65) + 8)
        let drivers: [HitchhikeOrderOption] = [
            HitchhikeOrderOption(driverName: "陳師傅 · 粵B·D8921 (比亞迪漢EV)", rating: "4.9分 · 認證車主 · 順路度 96%", departTime: "預計 12分鐘後出發", soloPrice: baseSolo, sharePrice: baseShare),
            HitchhikeOrderOption(driverName: "林先生 · 粵B·A3360 (特斯拉Model Y)", rating: "5.0分 · 零投訴 · 順路度 92%", departTime: "預計 20分鐘後出發", soloPrice: baseSolo + 3, sharePrice: baseShare + 2),
            HitchhikeOrderOption(driverName: "張師傅 · 粵B·F6109 (廣汽埃安S)", rating: "4.8分 · 老司機 · 順路度 89%", departTime: "隨時出發 · 可走高速", soloPrice: baseSolo - 1, sharePrice: baseShare - 1)
        ]
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: { selectedSeatType = 0 }) {
                    VStack(spacing: 2) {
                        Text("優惠拼座 (一口價)")
                            .font(.system(size: 13, weight: .black))
                        Text("预计 ¥\(baseShare) · 超省錢")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(selectedSeatType == 0 ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedSeatType == 0 ? httGold : Color.white.opacity(0.10))
                    .cornerRadius(10)
                }
                
                Button(action: { selectedSeatType = 1 }) {
                    VStack(spacing: 2) {
                        Text("獨享包車 (不拼人)")
                            .font(.system(size: 13, weight: .black))
                        Text("预计 ¥\(baseSolo) · 直達終點")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(selectedSeatType == 1 ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedSeatType == 1 ? httGold : Color.white.opacity(0.10))
                    .cornerRadius(10)
                }
            }
            
            Text("附近順路車主實時接單池 (應用內一鍵預約)")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(httGold)
                .padding(.top, 4)
            
            ForEach(drivers) { drv in
                let price = (selectedSeatType == 0) ? drv.sharePrice : drv.soloPrice
                HStack(spacing: 10) {
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.cyan)
                        .frame(width: 38, height: 38)
                        .background(Color.cyan.opacity(0.16))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drv.driverName)
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                        Text(drv.rating)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text(drv.departTime)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(httCream.opacity(0.85))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("¥\(price)")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(httGold)
                        Button(action: {
                            bookingToast = "🚗 已成功發布順風車行程並邀請【\(drv.driverName)】接單！"
                            let msg = "🚗 順風車行程已確認！車主 \(drv.driverName.prefix(3)) 即將前往起點接你哦♪"
                            manager.playVoice(id: manager.activeBaseId() + 39, customQuote: msg, clearQueue: true)
                        }) {
                            Text("立即邀約")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(11)
                .background(Color.white.opacity(0.07))
                .cornerRadius(12)
            }
        }
    }
    
    // MODE 2: Native Train / High-Speed Rail / Flight Schedules (班次票务)
    private var nativeTrainAndFlightSchedulesSection: some View {
        let isSH = currentDestTitle.contains("上海")
        let destSt = isSH ? "上海南 / 虹橋" : currentDestTitle
        let schedules: [LiveTransportScheduleItem] = [
            LiveTransportScheduleItem(code: "G998 復興號", departSt: "深圳北", arriveSt: destSt, departTime: "08:25", arriveTime: isSH ? "15:43" : "10:15", durationText: isSH ? "7小時18分" : "1小時50分", priceText: isSH ? "¥845" : "¥148", seatStatus: "二等座 有票 (18張) · 一等座 有票", isFlight: false),
            LiveTransportScheduleItem(code: "D2286 動車組", departSt: "深圳北", arriveSt: destSt, departTime: "09:12", arriveTime: isSH ? "17:05" : "11:10", durationText: isSH ? "7小時53分" : "1小時58分", priceText: isSH ? "¥662" : "¥115", seatStatus: "二等座 有票 · 動臥 餘4張", isFlight: false),
            LiveTransportScheduleItem(code: "ZH9501 深圳航空", departSt: "寶安機場T3", arriveSt: isSH ? "浦東機場T2" : "\(destSt)機場", departTime: "10:30", arriveTime: "12:45", durationText: "2小時15分", priceText: "¥580", seatStatus: "經濟艙 3.8折特價票", isFlight: true),
            LiveTransportScheduleItem(code: "MU5332 東方航空", departSt: "寶安機場T3", arriveSt: isSH ? "虹橋機場T2" : "\(destSt)機場", departTime: "13:00", arriveTime: "15:05", durationText: "2小時05分", priceText: isSH ? "¥1825" : "¥760", seatStatus: "商務快綫 · 隨到隨飛", isFlight: true),
            LiveTransportScheduleItem(code: "T212 特快列車", departSt: "深圳東(布吉)", arriveSt: isSH ? "嘉興/上海南" : destSt, departTime: "16:42", arriveTime: "次日11:15", durationText: "18小時33分", priceText: "¥223.5", seatStatus: "硬座 有票 · 硬臥 餘6張", isFlight: false)
        ]
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("實時全天班次時刻與餘票查詢 (前往：\(currentDestTitle))")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(httGold)
            
            ForEach(schedules) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: item.isFlight ? "airplane" : "tram.fill")
                            .foregroundColor(item.isFlight ? .cyan : .blue)
                        Text(item.code)
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                        Spacer()
                        Text(item.durationText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(item.priceText)
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.orange)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.departTime)
                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                            Text(item.departSt)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundColor(httGold)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.arriveTime)
                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                            Text(item.arriveSt)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    HStack {
                        Text(item.seatStatus)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Spacer()
                        Button(action: {
                            bookingToast = "🎫 已鎖定【\(item.code)】(\(item.departTime)發車) 席位！"
                        }) {
                            Text("鎖定班次並導航去車站")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(httGold)
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(11)
                .background(Color.white.opacity(0.07))
                .cornerRadius(12)
            }
        }
    }
    
    // MODE 3: Native Merchant Full Catalog & Reviews (商家详情与全部商品/推荐菜 - 绝不跳转荷兰花卉小镇!)
    private var nativeMerchantFullCatalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Merchant Summary Box
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(currentDestTitle)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(manager.tappedMapRating)分 · \(manager.tappedMapReviewLabel)")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                Text("類別：\(manager.tappedMapCategory) · 人均 \(manager.tappedMapPricePerPerson)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(httGold)
                Text("營業狀態：\(manager.tappedMapIsOpen ? "營業中" : "休息中") (\(manager.tappedMapHours))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(manager.tappedMapIsOpen ? .green : .orange)
                Text("詳細地址：\(currentDestAddress) (\(manager.tappedMapWalkDistText))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(httCream.opacity(0.9))
                
                HStack(spacing: 10) {
                    Button(action: {
                        manager.callTappedMerchantPhone()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                            Text("撥打商家電話 (\(manager.tappedMapPhone))")
                        }
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
            
            // All Recommended Dishes / Products List
            Text(manager.getSectionHeaderTitleForPOI())
                .font(.system(size: 14, weight: .black))
                .foregroundColor(httGold)
            
            ForEach(manager.tappedMapDishes) { dish in
                HStack(spacing: 12) {
                    Image(systemName: dish.iconName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.orange.opacity(0.85))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(dish.name)
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.white)
                            Spacer()
                            Text(dish.price)
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(httGold)
                        }
                        Text(dish.desc)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(httCream.opacity(0.85))
                        Text("👍 \(dish.recommendCount) 位街坊顧客實名推薦")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }
    
    private var portalNavTitle: String {
        switch manager.gaoDeWebPortalMode {
        case 0: return "高德聚合打車 (應用內叫車)"
        case 1: return "高德順風車 (應用內拼車)"
        case 2: return "實時高鐵/火車/航班時刻"
        default: return "\(currentDestTitle) · 詳情"
        }
    }
    
    private func portalTabButton(title: String, mode: Int) -> some View {
        let isSel = (manager.gaoDeWebPortalMode == mode)
        return Button(action: {
            manager.openGaoDeLivePortal(mode: mode)
        }) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .foregroundColor(isSel ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isSel ? httGold : Color.white.opacity(0.14))
                .cornerRadius(8)
        }
    }
}


// MARK: - Native In-App All Flight Schedules Sheet (飞机全部班次 100% 原生可打开)
struct InAppFlightTicketScheduleSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFlightIndex: Int = 0
    @State private var bookingConfirmed: String = ""
    
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.12).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if !bookingConfirmed.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(bookingConfirmed)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.22))
                        .cornerRadius(10)
                        .padding(12)
                    }
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            flightRow(airline: "深圳航空 ZH9501", code: "波音737", depart: "07:30 宝安T3", arrive: "09:45 目的地机场", duration: "2小时15分", price: "¥580", discount: "经济舱 3.8折 特惠")
                            flightRow(airline: "中国国航 CA1314", code: "空客A330 (宽体机)", depart: "09:00 宝安T3", arrive: "11:10 目的地机场", duration: "2小时10分", price: "¥620", discount: "商务快线 · 准点率98%")
                            flightRow(airline: "南方航空 CZ3558", code: "波音787", depart: "11:30 宝安T3", arrive: "13:40 目的地机场", duration: "2小时10分", price: "¥650", discount: "含20kg免费托运")
                            flightRow(airline: "东方航空 MU5332", code: "空客A320", depart: "14:15 宝安T3", arrive: "16:25 目的地机场", duration: "2小时10分", price: "¥720", discount: "商务优选 · 随到随飞")
                            flightRow(airline: "海南航空 HU7703", code: "波音737", depart: "17:00 宝安T3", arrive: "19:15 目的地机场", duration: "2小时15分", price: "¥590", discount: "五星航空舒适客舱")
                            flightRow(airline: "春秋航空 9C8866", code: "空客A320", depart: "20:30 宝安T3", arrive: "22:45 目的地机场", duration: "2小时15分", price: "¥390", discount: "晚间红眼超特惠")
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("深圳宝安出发 · 直飞全天航班 (\(manager.destinationName))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.foregroundColor(httGold)
                }
            }
        }
    }
    
    private func flightRow(airline: String, code: String, depart: String, arrive: String, duration: String, price: String, discount: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "airplane")
                    .foregroundColor(.cyan)
                Text(airline)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
                Text(code)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Text(price)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.orange)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(depart)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(duration)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 60, height: 1)
                    Text("直飞")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(arrive)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            
            HStack {
                Text(discount)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                Spacer()
                Button(action: {
                    bookingConfirmed = "🎫 已选定【\(airline)】！前往宝安机场值机"
                }) {
                    Text("选座购票")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(httGold)
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Native In-App All High-Speed Rail & Train Schedules Sheet (高铁/火车全部班次 100% 原生可打开)
struct InAppTrainTicketScheduleSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var bookingConfirmed: String = ""
    
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.12).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if !bookingConfirmed.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(bookingConfirmed)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.22))
                        .cornerRadius(10)
                        .padding(12)
                    }
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            trainRow(trainCode: "G998 復興號", from: "08:25 深圳北", to: "15:43 \(manager.destinationName)", time: "7小时18分", price: "¥845", seats: "二等座 有票 (18张) · 一等座 有票")
                            trainRow(trainCode: "G1002 復興號", from: "09:15 深圳北", to: "16:35 \(manager.destinationName)", time: "7小时20分", price: "¥845", seats: "二等座 有票 (24张)")
                            trainRow(trainCode: "D2286 動車組", from: "10:30 深圳北", to: "18:23 \(manager.destinationName)", time: "7小时53分", price: "¥662", seats: "二等座 有票 · 动卧 余4张")
                            trainRow(trainCode: "G1008 復興號", from: "12:40 深圳北", to: "20:05 \(manager.destinationName)", time: "7小时25分", price: "¥845", seats: "二等座 有票 · 商务座 余2张")
                            trainRow(trainCode: "D904 高鐵動臥", from: "19:55 深圳北", to: "次日06:50 \(manager.destinationName)", time: "10小时55分", price: "¥760", seats: "夕发朝至 · 动卧 有票 (热销)")
                            trainRow(trainCode: "T212 特快列車", from: "16:42 深圳东", to: "次日11:15 \(manager.destinationName)", time: "18小时33分", price: "¥223.5", seats: "硬座 有票 · 硬卧 余8张")
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("深圳出发 · 全部列车在售班次 (\(manager.destinationName))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.foregroundColor(httGold)
                }
            }
        }
    }
    
    private func trainRow(trainCode: String, from: String, to: String, time: String, price: String, seats: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tram.fill")
                    .foregroundColor(.blue)
                Text(trainCode)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                Spacer()
                Text(price)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.orange)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(from)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(time)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 60, height: 1)
                    Text("高铁动车")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(to)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            
            HStack {
                Text(seats)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                Spacer()
                Button(action: {
                    bookingConfirmed = "🎫 已锁定【\(trainCode)】车票！请持二代身份证进站"
                }) {
                    Text("预订车票")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(httGold)
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}


// MARK: - About & Bug Feedback Views (放课后茶会 · 制作作者与BUG反馈详情面板)
struct AuthorQRCodeAssets {
    // P1: Douyin Square QR Code (@不懂二次元的君殇 - 官方最新头像版)
    static let douyinSquareBase64 = "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"
    
    // P2: Instagram Square QR Code (@tomy.au1015 - 官方正方形版)
    static let instagramSquareBase64 = "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"
    
    static var douyinImage: UIImage? {
        if let d = Data(base64Encoded: douyinSquareBase64) {
            return UIImage(data: d)
        }
        return nil
    }
    
    // P3: Bilibili Square QR Code (小君殇 UID: 239899475)
    static let bilibiliSquareBase64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUEBAQEAwUEBAQGBQUGCA0ICAcHCBALDAkNExAUExIQEhIUFx0ZFBYcFhISGiMaHB4fISEhFBkkJyQgJh0gISD/2wBDAQUGBggHCA8ICA8gFRIVICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICD/wAARCAKAAoADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD7FooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKoAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKQBRRRSAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoooqgCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiii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"
    
    // P4: Xiaohongshu Square QR Code (小君殇 小红书号: 638021380)
    static let xiaohongshuSquareBase64 = "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xD8O6l4l8N2ljpaxGeLULe5YSvtGxHy3ODzjtUPjDw5rN1rmkeK/DQt21fSvMjNvcsUjuYX+8hYZ2nuDQBiWllbeGPjnHpuiwpZ2OtaU889tCu2MTRPgOFHAJHFZS+Gbbw78bvB7G6uNQv72C9kur26bdJMwjIHsoAOAB0FdV4c8PeIbrxrc+M/FUNtaXX2UWNnY20plEEW7cxZ8DLE+lXNX8O6le/E7wz4hgWL7Fp0FzHOWfDgyLhcDHNAHF6vZi9+LPiKWXwI3ilo7W0igWVESKMBWZj5knGckDAyTz0rtvh/qegX+iXUOiaIugyWty0V3p3lLG0E2BnIXg5GOf8KqatD8QNL8T3OoaFHba5pV2ij7DdXHkNaOBglG2nKnqQeapaP4b8Y6F4d8Q6rbPp03izWrkXbRsW+zRHgBAepwuefWgD0iiuenfxf/AG1ogt4tO/s4o39pli29W2jHle27PWpbBvE58Uamuox2Q0TbH9haInzi2Pn39qANyiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACqVzpOl3t9b313p1tcXVtnyZpYlZo+c/KSOOg6VdooAMYooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigBrMF7E/QZpPMH91/++TT6KAGeYP7r/8AfJo8wf3X/wC+TT6KAGeYP7r/APfJo8wf3X/75NPo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ZLG9rJdgRrsVJLuR0AxjG1iR9K16KAMrVdDt9YAS6uLpYNu14YZyiSDPIYDrWmFwoFOooAxB4X0bzJZWsw80mczPIzSDPXaxOV6/w4qIeD9DWQyrDciRgAzi8mywHQE7+nJroKKAI3iDwmI/dKlTz2xiqVvoumw2llbvaRTixRY4HmQO6AAAYJHB4FaNFAGdc6RBd6na380sxa1bfHEJCI92CNxXucE0250LTLnT/sP2ZYIQ/mr9n/dMj5zvUrghvetOigDGfw5YvY21ir3MNtbIUWOG4eMMP9raRu/H1NFr4Z0iwtpYdOtvsRkQRmWByJAoOQAxJNbNFAGTb6FbWmmzWMFxdJ50hleYTHzS5IJO78B+FJZeHdK09rZ7e0TzLaPyo5ZCXdRkk4J7kk5PU5rXooAzNM0PT9InuJbKIxmcjcC5YKBkhVB+6uSTgccmtOiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigApk0Mc8LwzRrJE4KujqCrA9QQeop9FAHlOo/AD4cajevdDTbmyLnJjtbgpH+CkHH0Fdd4T8A+FvBUEkfh/So7Z5QBJOxLyyAdix5x7DArqKKAAjIqjaaVaWV9e3luria9kWWctIzBmChRgE4XgDgYq9RQBRTSrOPWptXRGF1PEkEjGRiCqkkDbnA5Y84yaqar4a0vWZnlvoZHZ7Z7Q7J3j/AHbEFh8pHOVHPUVs0UAZcGh2FvFqEcUbhdRcvcAyudxKhTjJ+XgDpik0vQNO0eaSWxikQvDFAd8zyfJGNqD5ieQD16nvWrRQBROl2x1n+1trfa/I+zhvMbGzduxtzjOe+M1mSeD9Flkkd4JiZWuHb/SpRkzqFk/i7gDH93tiuhooAy9O0Ow0x7l7SN0a5EayFpnfIRAi4yePlA6dep5qxpmm2ukaZBp1kjJbwLsjVnZyB/vMST+Jq5RQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAf/2Q=="
    
    static var instagramImage: UIImage? {
        if let d = Data(base64Encoded: instagramSquareBase64) {
            return UIImage(data: d)
        }
        return nil
    }
    
    static var bilibiliImage: UIImage? {
        if let d = Data(base64Encoded: bilibiliSquareBase64) {
            return UIImage(data: d)
        }
        return nil
    }
    
    static var xiaohongshuImage: UIImage? {
        if let d = Data(base64Encoded: xiaohongshuSquareBase64) {
            return UIImage(data: d)
        }
        return nil
    }
}

struct AboutAndFeedbackSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    
    var body: some View {
        NavigationView {
            AboutAndFeedbackContentView(manager: manager)
                .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(manager.language == .en ? "About & Feedback" : (manager.language == .zhHant ? "關於與BUG反饋" : "关于与BUG反馈"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Done" : (manager.language == .zhHant ? "關閉" : "关闭")) {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
        }
    }
}

// Helper class for saving QR code images to iOS Photos album
class PhotoAlbumSaver: NSObject {
    var onComplete: ((Bool) -> Void)?
    
    func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        self.onComplete = completion
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(didFinishSavingWithError), nil)
    }
    
    @objc func didFinishSavingWithError(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        onComplete?(error == nil)
    }
}

struct AboutAndFeedbackContentView: View {
    @ObservedObject var manager: AudioPlayerManager
    @State private var copyToastText: String? = nil
    @State private var previewImage: UIImage? = nil
    @State private var previewTitle: String = ""
    @State private var previewPlatform: String = ""
    @State private var albumSaver = PhotoAlbumSaver()
    
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. App Header Card (放课后茶会伴侣 v1.0 + 作者署名)
                VStack(spacing: 8) {
                    // App Avatar
                    if let appIcon = UIImage(named: "AppIcon60x60@2x") ?? UIImage(named: "AppIcon") {
                        Image(uiImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 76, height: 76)
                            .cornerRadius(18)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(httGold, lineWidth: 2))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    } else {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 42))
                            .foregroundColor(httGold)
                    }
                    
                    Text(manager.language == .en ? "HTT Navi Companion" : (manager.language == .zhHant ? "放學後茶會伴侶" : "放课后茶会伴侣"))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        // Version 1.0 Badge
                        Text(manager.language == .en ? "Version 1.0 (v\(manager.appVersion))" : "版本 1.0 (v\(manager.appVersion))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        
                        // Author Badge (多语言严谨区分: 简体为君殇，繁体/英文为Tomy)
                        Text(manager.appAuthorLabel)
                            .font(.system(size: 11, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(httCrimson.opacity(0.18))
                            .foregroundColor(httCrimson)
                            .cornerRadius(6)
                    }
                    
                    Text(manager.language == .en
                         ? "K-ON! After School Tea Time Exclusive In-Car Navigation & Companion System"
                         : (manager.language == .zhHant ? "放學後茶會 (HTT) 專屬定製車載導航與桌面伴侶系統" : "放课后茶会 (HTT) 专属定制车载导航与桌面伴侣系统"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Toast notification
                if let toast = copyToastText {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(toast)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // 2. Feedback Channel 1: 抖音平台 (保留「不懂二次元的君殇」原名不变)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .foregroundColor(Color.pink)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.language == .en ? "Douyin: 不懂二次元的君殇" : (manager.language == .zhHant ? "抖音平臺：不懂二次元的君殇" : "抖音平台：不懂二次元的君殇"))
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(.primary)
                            Text(manager.language == .en ? "Douyin ID: 363314224" : (manager.language == .zhHant ? "抖音號：363314224" : "抖音号：363314224"))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: {
                                UIPasteboard.general.string = "363314224"
                                withAnimation { copyToastText = manager.language == .en ? "Copied Douyin ID: 363314224" : (manager.language == .zhHant ? "已複製抖音號：363314224" : "已复制抖音号：363314224") }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation { copyToastText = nil }
                                }
                            }) {
                                Text(manager.language == .en ? "Copy ID" : (manager.language == .zhHant ? "複製抖音號" : "复制抖音号"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.pink.opacity(0.18))
                                    .foregroundColor(.pink)
                                    .cornerRadius(6)
                            }
                            
                            Button(action: {
                                if let url = URL(string: "snssdk1128://"), UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                } else if let url2 = URL(string: "douyin://"), UIApplication.shared.canOpenURL(url2) {
                                    UIApplication.shared.open(url2)
                                } else if let web = URL(string: "https://www.douyin.com/") {
                                    UIApplication.shared.open(web)
                                }
                            }) {
                                Text(manager.language == .en ? "Open" : (manager.language == .zhHant ? "打開" : "打开"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.pink)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    Text(manager.language == .en
                         ? "Search & follow '不懂二次元的君殇' on Douyin for bug reports and suggestions. Tap image to enlarge or save:"
                         : (manager.language == .zhHant
                            ? "可在抖音 App 搜尋關注私訊反饋使用中的 BUG 與功能建議，點擊下方圖片可直接打開大圖或保存："
                            : "可在抖音 App 搜索关注私信反馈使用中的 BUG 与功能建议，点击下方图片可直接打开大图或保存："))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    // Clickable Douyin Square QR Image (点击放大打开)
                    HStack {
                        Spacer()
                        Button(action: {
                            previewImage = AuthorQRCodeAssets.douyinImage
                            previewTitle = manager.language == .zhHant ? "抖音平臺：不懂二次元的君殇" : "抖音平台：不懂二次元的君殇"
                            previewPlatform = "douyin"
                        }) {
                            ZStack(alignment: .bottomTrailing) {
                                if let img = AuthorQRCodeAssets.douyinImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 220, height: 220)
                                        .cornerRadius(14)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(httGold.opacity(0.55), lineWidth: 1.5))
                                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                                } else {
                                    VStack(spacing: 6) {
                                        Image(systemName: "qrcode")
                                            .font(.system(size: 44))
                                            .foregroundColor(.pink)
                                        Text("抖音：不懂二次元的君殇")
                                            .font(.caption.bold())
                                    }
                                    .frame(width: 220, height: 220)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                    .cornerRadius(14)
                                }
                                
                                // Click to Open Badge
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 9, weight: .black))
                                    Text(manager.language == .en ? "Tap to Open" : (manager.language == .zhHant ? "點擊打開" : "点击打开"))
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color.black.opacity(0.78))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(httGold.opacity(0.6), lineWidth: 0.8))
                                .padding(8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // 3. Feedback Channel 2: Instagram (附图 P2 - 点击可直接放大打开)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.circle.fill")
                            .foregroundColor(Color.purple)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Instagram：tomy.au1015")
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(.primary)
                            Text("@tomy.au1015")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: {
                                UIPasteboard.general.string = "tomy.au1015"
                                withAnimation { copyToastText = manager.language == .en ? "Copied Instagram: tomy.au1015" : (manager.language == .zhHant ? "已複製 Instagram：tomy.au1015" : "已复制 Instagram：tomy.au1015") }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation { copyToastText = nil }
                                }
                            }) {
                                Text(manager.language == .en ? "Copy ID" : (manager.language == .zhHant ? "複製賬號" : "复制账号"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.15))
                                    .foregroundColor(.purple)
                                    .cornerRadius(6)
                            }
                            
                            Button(action: {
                                if let url = URL(string: "instagram://user?username=tomy.au1015"), UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                } else if let web = URL(string: "https://www.instagram.com/tomy.au1015/") {
                                    UIApplication.shared.open(web)
                                }
                            }) {
                                Text(manager.language == .en ? "Open" : (manager.language == .zhHant ? "打開" : "打开"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    Text(manager.language == .en
                         ? "Overseas or Hong Kong users can follow & DM on Instagram for bug reporting:"
                         : (manager.language == .zhHant
                            ? "港澳台及海外用戶可在 Instagram 關注私訊反饋 BUG 與建議，點擊下方圖片可直接打開大圖或保存："
                            : "港澳台及海外用户可在 Instagram 关注私信反馈 BUG 与建议，点击下方图片可直接打开大图或保存："))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    // Clickable Instagram Square QR Image (点击放大打开)
                    HStack {
                        Spacer()
                        Button(action: {
                            previewImage = AuthorQRCodeAssets.instagramImage
                            previewTitle = "Instagram：tomy.au1015"
                            previewPlatform = "instagram"
                        }) {
                            ZStack(alignment: .bottomTrailing) {
                                if let img = AuthorQRCodeAssets.instagramImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 220, height: 220)
                                        .cornerRadius(14)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(httGold.opacity(0.55), lineWidth: 1.5))
                                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                                } else {
                                    VStack(spacing: 6) {
                                        Image(systemName: "qrcode")
                                            .font(.system(size: 44))
                                            .foregroundColor(.purple)
                                        Text("IG: @tomy.au1015")
                                            .font(.caption.bold())
                                    }
                                    .frame(width: 220, height: 220)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                    .cornerRadius(14)
                                }
                                
                                // Click to Open Badge
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 9, weight: .black))
                                    Text(manager.language == .en ? "Tap to Open" : (manager.language == .zhHant ? "點擊打開" : "点击打开"))
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color.black.opacity(0.78))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(httGold.opacity(0.6), lineWidth: 0.8))
                                .padding(8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // 4. Feedback Channel 3: Bilibili 哔哩哔哩 (保留「小君殇」原名不变)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "tv.circle.fill")
                            .foregroundColor(Color(red: 0.0, green: 0.63, blue: 0.84))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bilibili (B站)：小君殇")
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(.primary)
                            Text("UID：239899475")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: {
                                UIPasteboard.general.string = "239899475"
                                withAnimation { copyToastText = manager.language == .en ? "Copied Bilibili UID: 239899475" : (manager.language == .zhHant ? "已複製 B站 UID：239899475" : "已复制 B站 UID：239899475") }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation { copyToastText = nil }
                                }
                            }) {
                                Text(manager.language == .en ? "Copy UID" : (manager.language == .zhHant ? "複製UID" : "复制UID"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.cyan.opacity(0.16))
                                    .foregroundColor(Color(red: 0.0, green: 0.58, blue: 0.82))
                                    .cornerRadius(6)
                            }
                            
                            Button(action: {
                                if let url = URL(string: "bilibili://space/239899475"), UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                } else if let web = URL(string: "https://space.bilibili.com/239899475") {
                                    UIApplication.shared.open(web)
                                }
                            }) {
                                Text(manager.language == .en ? "Open" : (manager.language == .zhHant ? "打開" : "打开"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(red: 0.0, green: 0.63, blue: 0.84))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    Text(manager.language == .en
                         ? "Search '小君殇' or UID: 239899475 on Bilibili to follow & DM. Tap QR image to enlarge or save:"
                         : (manager.language == .zhHant
                            ? "可在嗶哩嗶哩 (B站) 搜尋「小君殇」或 UID: 239899475 關注私訊反饋，點擊下方二維碼可直接打開大圖或保存："
                            : "可在哔哩哔哩 (B站) 搜索「小君殇」或 UID: 239899475 关注私信反馈，点击下方二维码可直接打开大图或保存："))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    // Clickable Bilibili Square QR Image (点击放大打开 P3)
                    HStack {
                        Spacer()
                        Button(action: {
                            previewImage = AuthorQRCodeAssets.bilibiliImage
                            previewTitle = "Bilibili (B站)：小君殇"
                            previewPlatform = "bilibili"
                        }) {
                            ZStack(alignment: .bottomTrailing) {
                                if let img = AuthorQRCodeAssets.bilibiliImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 220, height: 220)
                                        .cornerRadius(14)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(httGold.opacity(0.55), lineWidth: 1.5))
                                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                                } else {
                                    VStack(spacing: 6) {
                                        Image(systemName: "qrcode")
                                            .font(.system(size: 44))
                                            .foregroundColor(.cyan)
                                        Text("B站 UID: 239899475")
                                            .font(.caption.bold())
                                    }
                                    .frame(width: 220, height: 220)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                    .cornerRadius(14)
                                }
                                
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 9, weight: .black))
                                    Text(manager.language == .en ? "Tap to Open" : (manager.language == .zhHant ? "點擊打開" : "点击打开"))
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color.black.opacity(0.78))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(httGold.opacity(0.6), lineWidth: 0.8))
                                .padding(8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // 5. Feedback Channel 4: 小红书 (保留「小君殇」原名不变)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.circle.fill")
                            .foregroundColor(Color.red)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.language == .en ? "Xiaohongshu: 小君殇" : (manager.language == .zhHant ? "小紅書：小君殇" : "小红书：小君殇"))
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(.primary)
                            Text(manager.language == .en ? "Xiaohongshu ID: 638021380" : (manager.language == .zhHant ? "小紅書號：638021380" : "小红书号：638021380"))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: {
                                UIPasteboard.general.string = "638021380"
                                withAnimation { copyToastText = manager.language == .en ? "Copied Xiaohongshu ID: 638021380" : (manager.language == .zhHant ? "已複製小紅書號：638021380" : "已复制小红书号：638021380") }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation { copyToastText = nil }
                                }
                            }) {
                                Text(manager.language == .en ? "Copy ID" : (manager.language == .zhHant ? "複製賬號" : "复制账号"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.15))
                                    .foregroundColor(.red)
                                    .cornerRadius(6)
                            }
                            
                            Button(action: {
                                if let url = URL(string: "xhsdiscover://"), UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                } else if let web = URL(string: "https://www.xiaohongshu.com/") {
                                    UIApplication.shared.open(web)
                                }
                            }) {
                                Text(manager.language == .en ? "Open" : (manager.language == .zhHant ? "打開" : "打开"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    Text(manager.language == .en
                         ? "Search '小君殇' or ID 638021380 on Xiaohongshu to follow & DM. Tap image to enlarge or save:"
                         : (manager.language == .zhHant
                            ? "可在小紅書 App 搜尋「小君殇」或小紅書號 638021380 關注私訊反饋，點擊下方圖片可直接打開大圖或保存："
                            : "可在小红书 App 搜索「小君殇」或小红书号 638021380 关注私信反馈，点击下方图片可直接打开大图或保存："))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    // Clickable Xiaohongshu Square QR Image (点击放大打开 P4)
                    HStack {
                        Spacer()
                        Button(action: {
                            previewImage = AuthorQRCodeAssets.xiaohongshuImage
                            previewTitle = manager.language == .zhHant ? "小紅書：小君殇" : "小红书：小君殇"
                            previewPlatform = "xiaohongshu"
                        }) {
                            ZStack(alignment: .bottomTrailing) {
                                if let img = AuthorQRCodeAssets.xiaohongshuImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 220, height: 220)
                                        .cornerRadius(14)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(httGold.opacity(0.55), lineWidth: 1.5))
                                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                                } else {
                                    VStack(spacing: 6) {
                                        Image(systemName: "qrcode")
                                            .font(.system(size: 44))
                                            .foregroundColor(.red)
                                        Text("小红书: 小君殇")
                                            .font(.caption.bold())
                                    }
                                    .frame(width: 220, height: 220)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                    .cornerRadius(14)
                                }
                                
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 9, weight: .black))
                                    Text(manager.language == .en ? "Tap to Open" : (manager.language == .zhHant ? "點擊打開" : "点击打开"))
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color.black.opacity(0.78))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(httGold.opacity(0.6), lineWidth: 0.8))
                                .padding(8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // 6. Dual-Map Engine Status & Copyright Footer (自动根据简/繁/英切换!)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "globe.asia.australia.fill")
                            .foregroundColor(.blue)
                        Text(manager.language == .en
                             ? "Mainland AutoNavi (GaoDe) + Overseas Apple Maps Dual Engine"
                             : (manager.language == .zhHant
                                ? "中國大陸高德地圖 + 海外 Apple Maps 雙擎自動切換"
                                : "中国大陆高德地图 + 海外 Apple Maps 双擎自动切换"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    Text(manager.language == .en
                         ? "Automatically activates AutoNavi (GaoDe) map data & GCJ-02 road alignment in Mainland China, and seamlessly switches to Apple Maps official global road network (WGS-84) in HK, Macau, Taiwan & overseas."
                         : (manager.language == .zhHant
                            ? "系統在中國大陸自動啟用高德地圖數據與 GCJ-02 道路精準對齊；在港澳台及海外地區自動無縫切換為 Apple Maps 官方全球路網（WGS-84）。"
                            : "系统在中国大陆自动启用高德地图数据与 GCJ-02 道路精准对齐；在港澳台及海外地区自动无缝切换为 Apple Maps 官方全球路网（WGS-84）。"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("Copyright © 2026 君殇 (Tomy). All rights reserved.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.bottom, 16)
                }
                .padding(.vertical, 8)
            }
            
            // 7. Fullscreen Click-to-Open QR Code Viewer Modal (支持 P1抖音 / P2 IG / P3 B站 / P4小红书 全屏预览与操作)
            if let pImg = previewImage {
                ZStack {
                    Color.black.opacity(0.88)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation { previewImage = nil }
                        }
                    
                    VStack(spacing: 14) {
                        // Header
                        HStack {
                            Text(previewTitle)
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: {
                                withAnimation { previewImage = nil }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Large Crisp Square QR Image
                        Image(uiImage: pImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 310, maxHeight: 310)
                            .cornerRadius(18)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(httGold, lineWidth: 2))
                            .shadow(color: .black, radius: 12, y: 4)
                        
                        // Action Buttons Bar
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                // Save to Album
                                Button(action: {
                                    albumSaver.save(pImg) { success in
                                        withAnimation {
                                            copyToastText = success
                                                ? (manager.language == .en ? "Saved QR code to Photos!" : (manager.language == .zhHant ? "已成功保存二維碼到系統相冊！" : "已成功保存二维码到系统相册！"))
                                                : (manager.language == .en ? "Please allow Photos access in Settings" : (manager.language == .zhHant ? "請在系統設置中允許相冊寫入權限" : "请在系统设置中允许相册写入权限"))
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                            withAnimation { copyToastText = nil }
                                        }
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "square.and.arrow.down")
                                        Text(manager.language == .en ? "Save Image" : (manager.language == .zhHant ? "保存到相冊" : "保存到相册"))
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.18))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                
                                // Copy Account / UID
                                Button(action: {
                                    let acct: String
                                    switch previewPlatform {
                                    case "douyin": acct = "363314224"
                                    case "instagram": acct = "tomy.au1015"
                                    case "bilibili": acct = "239899475"
                                    case "xiaohongshu": acct = "638021380"
                                    default: acct = "363314224"
                                    }
                                    UIPasteboard.general.string = acct
                                    withAnimation { copyToastText = manager.language == .en ? "Copied: \(acct)" : (manager.language == .zhHant ? "已複製賬號/UID：\(acct)" : "已复制账号/UID：\(acct)") }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        withAnimation { copyToastText = nil }
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "doc.on.doc")
                                        Text(manager.language == .en ? "Copy ID/UID" : (manager.language == .zhHant ? "複製賬號/UID" : "复制账号/UID"))
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.18))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                            
                            // Direct App Jump
                            Button(action: {
                                switch previewPlatform {
                                case "douyin":
                                    if let url = URL(string: "snssdk1128://"), UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    } else if let url2 = URL(string: "douyin://"), UIApplication.shared.canOpenURL(url2) {
                                        UIApplication.shared.open(url2)
                                    } else if let web = URL(string: "https://www.douyin.com/") {
                                        UIApplication.shared.open(web)
                                    }
                                case "instagram":
                                    if let url = URL(string: "instagram://user?username=tomy.au1015"), UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    } else if let web = URL(string: "https://www.instagram.com/tomy.au1015/") {
                                        UIApplication.shared.open(web)
                                    }
                                case "bilibili":
                                    if let url = URL(string: "bilibili://space/239899475"), UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    } else if let web = URL(string: "https://space.bilibili.com/239899475") {
                                        UIApplication.shared.open(web)
                                    }
                                case "xiaohongshu":
                                    if let url = URL(string: "xhsdiscover://"), UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    } else if let web = URL(string: "https://www.xiaohongshu.com/") {
                                        UIApplication.shared.open(web)
                                    }
                                default:
                                    break
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right.square.fill")
                                    Text({
                                        switch previewPlatform {
                                        case "douyin": return "打开抖音 App"
                                        case "instagram": return "打开 Instagram App"
                                        case "bilibili": return "打开哔哩哔哩 (B站) App"
                                        case "xiaohongshu": return "打开小红书 App"
                                        default: return "打开对应 App"
                                        }
                                    }())
                                }
                                .font(.system(size: 14, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    previewPlatform == "douyin" ? Color.pink :
                                    (previewPlatform == "instagram" ? Color.purple :
                                    (previewPlatform == "bilibili" ? Color(red: 0.0, green: 0.63, blue: 0.84) : Color.red))
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                withAnimation { previewImage = nil }
                            }) {
                                Text(manager.language == .en ? "Close Preview" : (manager.language == .zhHant ? "關閉預覽" : "关闭预览"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 20)
                    .background(Color(red: 0.12, green: 0.12, blue: 0.15))
                    .cornerRadius(22)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(httGold.opacity(0.65), lineWidth: 1.5))
                    .padding(.horizontal, 20)
                }
                .transition(.opacity)
            }
        }
    }
}
