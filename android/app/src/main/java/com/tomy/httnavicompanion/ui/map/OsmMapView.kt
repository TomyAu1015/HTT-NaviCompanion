package com.tomy.httnavicompanion.ui.map

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.graphics.DashPathEffect
import android.graphics.drawable.BitmapDrawable
import android.view.MotionEvent
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.tomy.httnavicompanion.audio.AudioPlayerManager
import com.tomy.httnavicompanion.audio.MapTileSourceMode
import com.tomy.httnavicompanion.audio.NavigationCameraMode
import com.tomy.httnavicompanion.data.CoordinateConverter
import com.tomy.httnavicompanion.data.LatLng
import org.osmdroid.config.Configuration
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.util.GeoPoint
import org.osmdroid.util.MapTileIndex
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline

private object AmapTileSource : OnlineTileSourceBase(
    "AmapVector", 3, 18, 256, ".png",
    arrayOf(
        "https://webrd01.is.autonavi.com/appmaptile",
        "https://webrd02.is.autonavi.com/appmaptile",
        "https://webrd03.is.autonavi.com/appmaptile"
    )
) {
    override fun getTileURLString(pMapTileIndex: Long): String {
        val z = MapTileIndex.getZoom(pMapTileIndex)
        val x = MapTileIndex.getX(pMapTileIndex)
        val y = MapTileIndex.getY(pMapTileIndex)
        return "$baseUrl?lang=zh_cn&size=1&scale=1&style=8&x=$x&y=$y&z=$z"
    }
}

private object GoogleMapsTileSource : OnlineTileSourceBase(
    "GoogleMapsGlobal", 1, 20, 256, ".png",
    arrayOf(
        "https://mt0.google.com/vt/lyrs=m&hl=zh-CN",
        "https://mt1.google.com/vt/lyrs=m&hl=zh-CN",
        "https://mt2.google.com/vt/lyrs=m&hl=zh-CN",
        "https://mt3.google.com/vt/lyrs=m&hl=zh-CN"
    )
) {
    override fun getTileURLString(pMapTileIndex: Long): String {
        val z = MapTileIndex.getZoom(pMapTileIndex)
        val x = MapTileIndex.getX(pMapTileIndex)
        val y = MapTileIndex.getY(pMapTileIndex)
        return "$baseUrl&x=$x&y=$y&z=$z"
    }
}

private val CartoDarkTileSource = XYTileSource(
    "CartoDark", 1, 19, 256, ".png",
    arrayOf("https://basemaps.cartocdn.com/dark_all/")
)

@SuppressLint("ClickableViewAccessibility")
@Composable
fun OsmMapView(
    manager: AudioPlayerManager,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val userCoord by manager.userCoordinate.collectAsState()
    val destCoord by manager.destinationCoord.collectAsState()
    val routePoints by manager.activeRoutePoints.collectAsState()
    val transitSegments by manager.transitSegments.collectAsState()
    val navArrowBmp by manager.currentNavArrowBitmap.collectAsState()
    val camMode by manager.cameraMode.collectAsState()
    val heading by manager.headingDegrees.collectAsState()
    val mapTileMode by manager.mapTileMode.collectAsState()
    val trackingUser by manager.mapTrackingUser.collectAsState()
    val recenterTrigger by manager.recenterTrigger.collectAsState()
    val zoomTrigger by manager.zoomCommandTrigger.collectAsState()
    val tappedCoord by manager.tappedCoord.collectAsState()

    val useAmapTiles = remember(mapTileMode, userCoord) {
        when (mapTileMode) {
            MapTileSourceMode.AMAP_CHINA -> true
            MapTileSourceMode.OSM_GLOBAL, MapTileSourceMode.CARTODB_DARK -> false
            MapTileSourceMode.AUTO -> CoordinateConverter.isInMainlandChina(userCoord.latitude, userCoord.longitude)
        }
    }

    LaunchedEffect(Unit) {
        Configuration.getInstance().load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
        Configuration.getInstance().userAgentValue = context.packageName
    }

    val mapViewHolder = remember { arrayOfNulls<MapView>(1) }
    val userMarkerHolder = remember { arrayOfNulls<Marker>(1) }
    val destMarkerHolder = remember { arrayOfNulls<Marker>(1) }
    val tappedMarkerHolder = remember { arrayOfNulls<Marker>(1) }
    val outerPolyHolder = remember { arrayOfNulls<Polyline>(1) }
    val innerPolyHolder = remember { arrayOfNulls<Polyline>(1) }
    val walkPoly1Holder = remember { arrayOfNulls<Polyline>(1) }
    val walkPoly2Holder = remember { arrayOfNulls<Polyline>(1) }
    val lastAnimatedCoord = remember { arrayOfNulls<LatLng>(1) }
    val lastArrowBmp = remember { arrayOfNulls<Bitmap>(1) }
    val lastCameraAnimMs = remember { longArrayOf(0L) }
    val lastRouteKey = remember { arrayOfNulls<Any>(1) }
    val lastTransitKey = remember { arrayOfNulls<Any>(1) }
    val lastUseAmap = remember { booleanArrayOf(useAmapTiles) }
    val lastDestMarkerKey = remember { arrayOfNulls<LatLng>(1) }
    val lastTappedMarkerKey = remember { arrayOfNulls<LatLng>(1) }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
            Configuration.getInstance().userAgentValue = ctx.packageName
            MapView(ctx).apply {
                setMultiTouchControls(true)
                setBuiltInZoomControls(false)
                controller.setZoom(16.0)
                val initPt = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(userCoord) else userCoord
                controller.setCenter(GeoPoint(initPt.latitude, initPt.longitude))

                // Pause auto-follow when user manually drags/pans the map
                var downX = 0f
                var downY = 0f
                setOnTouchListener { v, ev ->
                    when (ev.actionMasked) {
                        MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                            v.parent?.requestDisallowInterceptTouchEvent(true)
                            manager.setTouchingMap(true)
                            if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
                                downX = ev.x
                                downY = ev.y
                            }
                        }
                        MotionEvent.ACTION_MOVE -> {
                            v.parent?.requestDisallowInterceptTouchEvent(true)
                            val dx = ev.x - downX
                            val dy = ev.y - downY
                            if (dx * dx + dy * dy > 320f) {
                                manager.setMapTracking(false)
                            }
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            v.parent?.requestDisallowInterceptTouchEvent(false)
                            manager.setTouchingMap(false)
                        }
                    }
                    false
                }

                val eventsOverlay = MapEventsOverlay(object : MapEventsReceiver {
                    override fun singleTapConfirmedHelper(p: GeoPoint): Boolean {
                        val tappedRaw = LatLng(p.latitude, p.longitude)
                        val wgs = if (useAmapTiles) CoordinateConverter.gcj02ToWGS84(tappedRaw) else tappedRaw
                        manager.handleMapTap(wgs)
                        return true
                    }

                    override fun longPressHelper(p: GeoPoint): Boolean = false
                })
                overlays.add(eventsOverlay)

                val outerLine = Polyline(this).apply {
                    outlinePaint.color = AndroidColor.rgb(18, 92, 168)
                    outlinePaint.strokeWidth = 20f
                }
                val innerLine = Polyline(this).apply {
                    outlinePaint.color = AndroidColor.rgb(0, 229, 255)
                    outlinePaint.strokeWidth = 11f
                }
                overlays.add(outerLine)
                overlays.add(innerLine)
                outerPolyHolder[0] = outerLine
                innerPolyHolder[0] = innerLine
                val w1 = Polyline(this).apply {
                    outlinePaint.color = AndroidColor.rgb(21, 101, 192)
                    outlinePaint.strokeWidth = 10f
                    outlinePaint.pathEffect = DashPathEffect(floatArrayOf(20f, 14f), 0f)
                }
                val w2 = Polyline(this).apply {
                    outlinePaint.color = AndroidColor.rgb(21, 101, 192)
                    outlinePaint.strokeWidth = 10f
                    outlinePaint.pathEffect = DashPathEffect(floatArrayOf(20f, 14f), 0f)
                }
                overlays.add(w1)
                overlays.add(w2)
                walkPoly1Holder[0] = w1
                walkPoly2Holder[0] = w2

                val uMarker = Marker(this).apply {
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                    title = "当前位置"
                }
                overlays.add(uMarker)
                userMarkerHolder[0] = uMarker

                val dMarker = Marker(this).apply {
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                    title = "目的地"
                }
                overlays.add(dMarker)
                destMarkerHolder[0] = dMarker

                val tMarker = Marker(this).apply {
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                    title = "选点"
                }
                overlays.add(tMarker)
                tappedMarkerHolder[0] = tMarker

                mapViewHolder[0] = this
            }
        },
        update = { mapView ->
            // 1. Update Tile Source only when changed
            val desiredSource = when {
                mapTileMode == MapTileSourceMode.CARTODB_DARK -> CartoDarkTileSource
                useAmapTiles -> AmapTileSource
                else -> GoogleMapsTileSource
            }
            if (mapView.tileProvider.tileSource.name() != desiredSource.name()) {
                mapView.setTileSource(desiredSource)
            }

            // 2. Update User Marker & Arrow (only allocate BitmapDrawable when bitmap actually changes)
            val dispUser = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(userCoord) else userCoord
            val userGeo = GeoPoint(dispUser.latitude, dispUser.longitude)
            userMarkerHolder[0]?.apply {
                position = userGeo
                if (navArrowBmp != null && navArrowBmp !== lastArrowBmp[0]) {
                    lastArrowBmp[0] = navArrowBmp
                    icon = BitmapDrawable(context.resources, navArrowBmp)
                }
            }

            var needsRedraw = false

            // 3. Update Route Polylines ONLY when route/transitSegments/tileCoordSystem actually changed (eliminates GC stutter!)
            if (lastRouteKey[0] !== routePoints || lastTransitKey[0] !== transitSegments || lastUseAmap[0] != useAmapTiles) {
                lastRouteKey[0] = routePoints
                lastTransitKey[0] = transitSegments
                lastUseAmap[0] = useAmapTiles
                needsRedraw = true
                if (transitSegments.size >= 3) {
                    val w1Pts = transitSegments[0].points.map { pt -> val c = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(pt) else pt; GeoPoint(c.latitude, c.longitude) }
                    val trPts = transitSegments[1].points.map { pt -> val c = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(pt) else pt; GeoPoint(c.latitude, c.longitude) }
                    val w2Pts = transitSegments[2].points.map { pt -> val c = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(pt) else pt; GeoPoint(c.latitude, c.longitude) }
                    outerPolyHolder[0]?.outlinePaint?.color = AndroidColor.rgb(0, 150, 136)
                    innerPolyHolder[0]?.outlinePaint?.color = AndroidColor.rgb(0, 230, 118)
                    outerPolyHolder[0]?.setPoints(trPts)
                    innerPolyHolder[0]?.setPoints(trPts)
                    walkPoly1Holder[0]?.setPoints(w1Pts)
                    walkPoly2Holder[0]?.setPoints(w2Pts)
                } else {
                    outerPolyHolder[0]?.outlinePaint?.color = AndroidColor.rgb(18, 92, 168)
                    innerPolyHolder[0]?.outlinePaint?.color = AndroidColor.rgb(0, 229, 255)
                    val dispRoute = routePoints.map { pt ->
                        val c = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(pt) else pt
                        GeoPoint(c.latitude, c.longitude)
                    }
                    outerPolyHolder[0]?.setPoints(dispRoute)
                    innerPolyHolder[0]?.setPoints(dispRoute)
                    walkPoly1Holder[0]?.setPoints(emptyList())
                    walkPoly2Holder[0]?.setPoints(emptyList())
                }
            }

            // 4. Update Destination Marker
            val dMarker = destMarkerHolder[0]
            if (destCoord != lastDestMarkerKey[0]) {
                lastDestMarkerKey[0] = destCoord
                if (destCoord != null && dMarker != null) {
                    val dc = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(destCoord!!) else destCoord!!
                    dMarker.position = GeoPoint(dc.latitude, dc.longitude)
                    dMarker.setVisible(true)
                } else {
                    dMarker?.setVisible(false)
                }
                needsRedraw = true
            }

            // 5. Update Tapped POI Marker
            val tMarker = tappedMarkerHolder[0]
            if (tappedCoord != lastTappedMarkerKey[0]) {
                lastTappedMarkerKey[0] = tappedCoord
                if (tappedCoord != null && tMarker != null) {
                    val tc = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(tappedCoord!!) else tappedCoord!!
                    tMarker.position = GeoPoint(tc.latitude, tc.longitude)
                    tMarker.setVisible(true)
                } else {
                    tMarker?.setVisible(false)
                }
                needsRedraw = true
            }

            // 6. Throttled Smooth Camera follow (min 550ms cadence & >= 2.5m delta prevents canceling in-flight animations!)
            val nowMs = System.currentTimeMillis()
            if (trackingUser) {
                val prev = lastAnimatedCoord[0]
                val moved = prev == null || CoordinateConverter.distanceMeters(prev, dispUser) >= 2.5
                if (moved && (prev == null || nowMs - lastCameraAnimMs[0] >= 550L)) {
                    lastAnimatedCoord[0] = dispUser
                    lastCameraAnimMs[0] = nowMs
                    mapView.controller.animateTo(userGeo, null, 480L)
                    needsRedraw = true
                }
            }
            val targetOrient = if (camMode == NavigationCameraMode.HEADING_UP) -heading.toFloat() else 0f
            if (kotlin.math.abs(mapView.mapOrientation - targetOrient) >= 3.0f) {
                mapView.mapOrientation = targetOrient
                needsRedraw = true
            }

            if (needsRedraw) {
                mapView.invalidate()
            }
        }
    )

    // Respond to recenter trigger
    LaunchedEffect(recenterTrigger) {
        if (recenterTrigger > 0) {
            val dispUser = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(userCoord) else userCoord
            lastAnimatedCoord[0] = dispUser
            mapViewHolder[0]?.controller?.animateTo(GeoPoint(dispUser.latitude, dispUser.longitude))
            mapViewHolder[0]?.controller?.setZoom(16.5)
        }
    }

    // Respond to zoom trigger
    LaunchedEffect(zoomTrigger) {
        if (zoomTrigger > 0) {
            mapViewHolder[0]?.controller?.zoomIn()
            manager.triggerZoom(0)
        } else if (zoomTrigger < 0) {
            mapViewHolder[0]?.controller?.zoomOut()
            manager.triggerZoom(0)
        }
    }
}
