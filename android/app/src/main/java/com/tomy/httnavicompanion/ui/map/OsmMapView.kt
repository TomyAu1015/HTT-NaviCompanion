package com.tomy.httnavicompanion.ui.map

import android.content.Context
import android.graphics.Color as AndroidColor
import android.graphics.drawable.BitmapDrawable
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

private val CartoDarkTileSource = XYTileSource(
    "CartoDark", 1, 19, 256, ".png",
    arrayOf("https://basemaps.cartocdn.com/dark_all/")
)

@Composable
fun OsmMapView(
    manager: AudioPlayerManager,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val userCoord by manager.userCoordinate.collectAsState()
    val destCoord by manager.destinationCoord.collectAsState()
    val routePoints by manager.activeRoutePoints.collectAsState()
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

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                setMultiTouchControls(true)
                setBuiltInZoomControls(false)
                controller.setZoom(16.0)
                val initPt = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(userCoord) else userCoord
                controller.setCenter(GeoPoint(initPt.latitude, initPt.longitude))

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
            // 1. Update Tile Source
            val desiredSource = when {
                mapTileMode == MapTileSourceMode.CARTODB_DARK -> CartoDarkTileSource
                useAmapTiles -> AmapTileSource
                else -> TileSourceFactory.MAPNIK
            }
            if (mapView.tileProvider.tileSource.name() != desiredSource.name()) {
                mapView.setTileSource(desiredSource)
            }

            // 2. Update User Marker & Arrow
            val dispUser = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(userCoord) else userCoord
            val userGeo = GeoPoint(dispUser.latitude, dispUser.longitude)
            userMarkerHolder[0]?.apply {
                position = userGeo
                if (navArrowBmp != null) {
                    icon = BitmapDrawable(context.resources, navArrowBmp)
                }
            }

            // 3. Update Route Polylines
            val dispRoute = routePoints.map { pt ->
                val c = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(pt) else pt
                GeoPoint(c.latitude, c.longitude)
            }
            outerPolyHolder[0]?.setPoints(dispRoute)
            innerPolyHolder[0]?.setPoints(dispRoute)

            // 4. Update Destination Marker
            val dMarker = destMarkerHolder[0]
            if (destCoord != null && dMarker != null) {
                val dc = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(destCoord!!) else destCoord!!
                dMarker.position = GeoPoint(dc.latitude, dc.longitude)
                dMarker.setVisible(true)
            } else {
                dMarker?.setVisible(false)
            }

            // 5. Update Tapped POI Marker
            val tMarker = tappedMarkerHolder[0]
            if (tappedCoord != null && tMarker != null) {
                val tc = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(tappedCoord!!) else tappedCoord!!
                tMarker.position = GeoPoint(tc.latitude, tc.longitude)
                tMarker.setVisible(true)
            } else {
                tMarker?.setVisible(false)
            }

            // 6. Camera follow & orientation
            if (trackingUser) {
                mapView.controller.animateTo(userGeo)
            }
            mapView.mapOrientation = if (camMode == NavigationCameraMode.HEADING_UP) -heading.toFloat() else 0f

            mapView.invalidate()
        }
    )

    // Respond to recenter trigger
    LaunchedEffect(recenterTrigger) {
        if (recenterTrigger > 0) {
            val dispUser = if (useAmapTiles) CoordinateConverter.wgs84ToGCJ02(userCoord) else userCoord
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
