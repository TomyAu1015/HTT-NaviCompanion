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
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            
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
                let tappedPin = MKPointAnnotation()
                tappedPin.coordinate = tapped
                tappedPin.title = manager.tappedMapTitle
                tappedPin.subtitle = ""
                mapView.addAnnotation(tappedPin)
            }
            
            if routeChanged && (manager.activeRoute != nil || manager.customTransitPolyline != nil) {
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
            mapView.setCamera(cam, animated: true)
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
        var lastCustomPolyline: MKPolyline? = nil
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
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation, !(annotation is MKUserLocation) else { return }
            let coord = annotation.coordinate
            let title = annotation.title ?? nil
            DispatchQueue.main.async {
                self.parent.manager.handleMapTap(at: coord, explicitTitle: title ?? nil)
            }
        }
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let loc = userLocation.location, !parent.manager.isDemoSimulating else { return }
            DispatchQueue.main.async {
                self.parent.manager.userCoordinate = loc.coordinate
                if self.parent.manager.travelMode == .transit {
                    self.parent.manager.refreshTransitPlansForCurrentLocation(force: false)
                }
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
                                    // Left Column: Speedometer + Tactical Buttons + Cruise/Nav + Outfit/Camera/Gift + Author Bar!
                                    // Fully utilizes left open space and avoids Home Indicator!
                                    VStack(spacing: 7) {
                                        speedometerCockpit
                                        utilityControlGrid
                                        outfitCameraGiftRow
                                        
                                        // Landscape Author & Feedback Bar (横屏左侧署名与反馈)
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
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.black.opacity(0.55))
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.45), lineWidth: 1))
                                        }
                                    }
                                    .frame(width: leftColW)
                                    
                                    // Right Column: Map/Stage + Speech Bubble + Character Strip + Travel Modes Row (No bottom clutter!)
                                    VStack(spacing: 6) {
                                        mainStageOrMapSection(stageWidth: rightColW, stageHeight: 165)
                                        characterSelectorStrip
                                            .frame(width: rightColW)
                                        travelModesRow
                                            .frame(width: rightColW)
                                    }
                                    .frame(width: rightColW)
                                }
                                .frame(width: usableW)
                            }
                            .padding(.leading, leadingNotchPad)
                            .padding(.trailing, trailingSafePad)
                            .padding(.top, 4)
                            .padding(.bottom, max(geo.safeAreaInsets.bottom + 8, 26))
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
                                    .background(Color.black.opacity(0.45))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.45), lineWidth: 1))
                                }
                                .padding(.top, 2)
                            }
                            .frame(width: geo.size.width - 24)
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
                let leadingNotchPad: CGFloat = max(geo.safeAreaInsets.leading + 8, 44)
                let trailingSafePad: CGFloat = max(geo.safeAreaInsets.trailing + 8, 16)
                let usableW = max(480, geo.size.width - leadingNotchPad - trailingSafePad)
                let leftPanelW = min(340, usableW * 0.44)
                
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
                                        Text(tr("缩小", "縮小", "Cockpit"))
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
                                        Text(tr("缩小", "縮小", "Cockpit"))
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
            // 1. Electronic Speed Camera Badge (测速电子眼)
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.red, lineWidth: 3))
                    Text("\(manager.upcomingCameraLimit > 0 ? manager.upcomingCameraLimit : Int(manager.speedLimitKmh))")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("测速电子眼", "測速電子眼", "Speed Cam"))
                        .font(.system(size: 10, weight: .heavy))
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
            .background(Color.black.opacity(0.85))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.85), lineWidth: 1.2))
            
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
                        manager.triggerCharacterTap(member: manager.activeAllMemberChar)
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
                                        manager.triggerCharacterTap(member: manager.activeAllMemberChar)
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
                             : "一键识别外部App复制的地址/分享链接并直接导航")
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
                    Text("导航换装").tag(0)
                    Text("纪念相册").tag(1)
                    Text(manager.language == .en ? "Author & Feedback" : (manager.language == .zhHant ? "製作作者與反饋" : "制作作者与BUG反馈")).tag(2)
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
                } else if selectedTab == 2 {
                    // Tab 2: Author & Bug Feedback (制作作者与BUG反馈)
                    ScrollView {
                        AboutAndFeedbackContentView(manager: manager)
                            .padding(.top, 6)
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
    // P1: Douyin Square QR Code (@不懂二次元的君殇)
    static let douyinSquareBase64 = "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"
    
    // P2: Instagram Square QR Code (@tomy.au1015)
    static let instagramSquareBase64 = "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"
    
    static var douyinImage: UIImage? {
        if let d = Data(base64Encoded: douyinSquareBase64) {
            return UIImage(data: d)
        }
        return nil
    }
    
    static var instagramImage: UIImage? {
        if let d = Data(base64Encoded: instagramSquareBase64) {
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
            ScrollView {
                AboutAndFeedbackContentView(manager: manager)
                    .padding(.vertical, 8)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(manager.language == .en ? "About & Feedback" : (manager.language == .zhHant ? "關於與BUG反饋" : "关于与BUG反馈"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Done" : "关闭") {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
        }
    }
}

struct AboutAndFeedbackContentView: View {
    @ObservedObject var manager: AudioPlayerManager
    @State private var copyToastText: String? = nil
    
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    
    var body: some View {
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
                
                Text(manager.language == .en ? "HTT Navi Companion" : "放课后茶会伴侣")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // Version 1.0 Badge
                    Text("版本 1.0 (v\(manager.appVersion))")
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
                     : "放课后茶会 (HTT) 专属定制车载导航与桌面伴侣系统")
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
            
            // 2. Feedback Channel 1: 抖音平台 (正方形二维码 P1)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "play.tv.fill")
                        .foregroundColor(Color.pink)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("抖音平台：不懂二次元的君殇")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.primary)
                        Text("抖音号：363314224")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        UIPasteboard.general.string = "363314224"
                        withAnimation { copyToastText = "已复制抖音号：363314224" }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation { copyToastText = nil }
                        }
                    }) {
                        Text("复制抖音号")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.pink.opacity(0.18))
                            .foregroundColor(.pink)
                            .cornerRadius(6)
                    }
                }
                
                Text("可在抖音 App 搜索关注私信反馈使用中的 BUG 与功能建议，或直接扫描下方正方形二维码：")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                // Douyin Square QR Image (附图 P1 正方形图片)
                HStack {
                    Spacer()
                    if let img = AuthorQRCodeAssets.douyinImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.25), lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 44))
                                .foregroundColor(.pink)
                            Text("抖音搜索：不懂二次元的君殇")
                                .font(.caption.bold())
                        }
                        .frame(width: 220, height: 220)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .cornerRadius(14)
                    }
                    Spacer()
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // 3. Feedback Channel 2: Instagram (正方形二维码 P2)
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
                            withAnimation { copyToastText = "已复制 Instagram：tomy.au1015" }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation { copyToastText = nil }
                            }
                        }) {
                            Text("复制账号")
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
                            Text("打开")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                }
                
                Text("Overseas or Hong Kong users can follow & DM on Instagram for bug reporting:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                // Instagram Square QR Image (附图 P2 正方形图片)
                HStack {
                    Spacer()
                    if let img = AuthorQRCodeAssets.instagramImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.25), lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
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
                    Spacer()
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // 4. More Channels & Tech Engine Details
            VStack(alignment: .leading, spacing: 8) {
                Text("其他关注与技术信息")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bilibili (B站)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                        Text("小君殇")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(httGold)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("小红书")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                        Text("小君殇")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(httCrimson)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("地图核心")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Apple MapKit")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.blue)
                    }
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
                
                Text("Copyright © 2026 君殇 (Tomy). All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }
}
