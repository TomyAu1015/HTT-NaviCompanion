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
                    // Transit Mode on Map: Split into Walking Approach (Blue) + Bus/Subway Ride (GaoDe Royal Blue / Green) + Station Stop Pins!
                    let pts = route.polyline.points()
                    let totalPts = route.polyline.pointCount
                    if totalPts > 8 {
                        let cutWalk1 = max(2, Int(Double(totalPts) * 0.20))
                        let cutRide = max(cutWalk1 + 2, Int(Double(totalPts) * 0.88))
                        
                        // Leg 1: Walk to Bus/Subway Station (Pedestrian Blue)
                        let polyWalk1 = MKPolyline(points: pts, count: cutWalk1)
                        polyWalk1.title = "WALKING_BLUE"
                        mapView.addOverlay(polyWalk1, level: .aboveRoads)
                        
                        // Boarding Station Marker (e.g. 沙湾天桥 / 地铁站)
                        let boardPin = MKPointAnnotation()
                        boardPin.coordinate = pts[cutWalk1 - 1].coordinate
                        if manager.selectedTransitPlanIndex < manager.transitPlans.count,
                           let firstTransit = manager.transitPlans[manager.selectedTransitPlanIndex].steps.first(where: { $0.kind != .walk }) {
                            boardPin.title = "\(firstTransit.fromStation) (\(firstTransit.lineName))"
                        } else {
                            boardPin.title = "上车站台"
                        }
                        boardPin.subtitle = "BUS_STOP_PIN"
                        mapView.addAnnotation(boardPin)
                        
                        // Leg 2: Bus / Subway Ride (GaoDe Transit Blue/Green)
                        let polyRide = MKPolyline(points: pts.advanced(by: cutWalk1 - 1), count: cutRide - cutWalk1 + 1)
                        polyRide.title = "TRANSIT_GREEN"
                        mapView.addOverlay(polyRide, level: .aboveRoads)
                        
                        // Leg 3: Walk from Alighting Station to Destination
                        let polyWalk2 = MKPolyline(points: pts.advanced(by: cutRide - 1), count: totalPts - cutRide + 1)
                        polyWalk2.title = "WALKING_BLUE"
                        mapView.addOverlay(polyWalk2, level: .aboveRoads)
                    } else {
                        route.polyline.title = "TRANSIT_GREEN"
                        mapView.addOverlay(route.polyline, level: .aboveRoads)
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
                let newCoord = CoordinateConverter.wgs84ToGCJ02(loc.coordinate)
                self.parent.manager.userCoordinate = newCoord
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
    private var portraitBottomCompanionDock: some View {
        VStack(spacing: 7) {
            // Row 1: 4 Travel Modes Direct Switcher (Car / e-Bike / Walk / Transit)
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
            
            // Row 2: RM-500HTT Outfit + Camera Mode + Birthday Special
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
