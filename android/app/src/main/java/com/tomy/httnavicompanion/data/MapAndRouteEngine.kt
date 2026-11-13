package com.tomy.httnavicompanion.data

import android.util.Log
import com.tomy.httnavicompanion.audio.NavigationTravelMode
import com.tomy.httnavicompanion.audio.PlaceSearchItem
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class RouteStepInfo(
    val instruction: String,
    val distanceMeters: Double,
    val maneuverLocation: LatLng
)

data class ComputedRoute(
    val name: String,
    val points: List<LatLng>,
    val steps: List<RouteStepInfo>,
    val totalDistanceMeters: Double,
    val durationSeconds: Double
)

data class ReverseGeocodeResult(
    val title: String,
    val address: String,
    val category: String
)

object MapAndRouteEngine {
    private const val TAG = "MapAndRouteEngine"

    /**
     * Searches places via OpenStreetMap Nominatim API (no API key needed)
     * and merges with local K-ON! / Greater Bay Area presets.
     */
    fun searchPlacesOnline(query: String, userLoc: LatLng): List<PlaceSearchItem> {
        val results = ArrayList<PlaceSearchItem>()
        try {
            val encoded = URLEncoder.encode(query.trim(), "UTF-8")
            val urlStr = "https://nominatim.openstreetmap.org/search?format=jsonv2&q=$encoded&limit=15&accept-language=zh-CN,zh-TW,en"
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 5000
                setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.3")
            }
            if (conn.responseCode == 200) {
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                val arr = JSONArray(body)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val lat = obj.optDouble("lat", 0.0)
                    val lon = obj.optDouble("lon", 0.0)
                    val displayName = obj.optString("display_name", "")
                    val shortName = obj.optString("name", "").ifBlank {
                        displayName.substringBefore(",").trim()
                    }
                    val cat = obj.optString("type", "地点")
                    val coord = LatLng(lat, lon)
                    val distKm = CoordinateConverter.distanceMeters(userLoc, coord) / 1000.0
                    results.add(
                        PlaceSearchItem(
                            name = shortName,
                            address = displayName,
                            distanceKm = distKm,
                            coordinate = coord,
                            category = cat
                        )
                    )
                }
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Nominatim search fallback: ${e.message}")
        }
        return results
    }

    fun reverseGeocode(coord: LatLng): ReverseGeocodeResult {
        try {
            val urlStr = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${coord.latitude}&lon=${coord.longitude}&zoom=18&accept-language=zh-CN,zh-TW,en"
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = 4500
                readTimeout = 4500
                setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.3")
            }
            if (conn.responseCode == 200) {
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                val obj = JSONObject(body)
                val name = obj.optString("name", "")
                val addr = obj.optJSONObject("address")
                val road = addr?.optString("road", "") ?: ""
                val suburb = addr?.optString("suburb", addr.optString("district", "")) ?: ""
                val city = addr?.optString("city", addr.optString("town", "")) ?: ""
                val title = when {
                    name.isNotBlank() -> name
                    road.isNotBlank() -> road
                    suburb.isNotBlank() -> suburb
                    else -> obj.optString("display_name", "地图选点").substringBefore(",")
                }
                val fullAddr = listOf(city, suburb, road).filter { it.isNotBlank() }.joinToString(" · ")
                    .ifBlank { obj.optString("display_name", String.format("%.5f, %.5f", coord.latitude, coord.longitude)) }
                val cat = obj.optString("type", "地图兴趣点")
                conn.disconnect()
                return ReverseGeocodeResult(title, fullAddr, cat)
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Reverse geocode fallback: ${e.message}")
        }
        return ReverseGeocodeResult(
            title = "地图选点",
            address = String.format("坐标: %.5f, %.5f", coord.latitude, coord.longitude),
            category = "自选坐标"
        )
    }

    /**
     * Computes real turn-by-turn road route via OSRM public API (WGS-84),
     * with automatic multi-waypoint fallback if offline.
     */
    fun calculateRoute(
        startWgs: LatLng,
        destWgs: LatLng,
        travelMode: NavigationTravelMode
    ): List<ComputedRoute> {
        val profile = when (travelMode) {
            NavigationTravelMode.DRIVING, NavigationTravelMode.TRANSIT -> "driving"
            NavigationTravelMode.EBIKE -> "bike"
            NavigationTravelMode.WALKING -> "foot"
        }

        val routes = ArrayList<ComputedRoute>()
        try {
            val urlStr = "https://router.project-osrm.org/route/v1/$profile/${startWgs.longitude},${startWgs.latitude};${destWgs.longitude},${destWgs.latitude}?overview=full&geometries=geojson&steps=true&alternatives=true"
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = 6000
                readTimeout = 6000
                setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.3")
            }
            if (conn.responseCode == 200) {
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                val root = JSONObject(body)
                val routesArr = root.optJSONArray("routes")
                if (routesArr != null) {
                    for (rIdx in 0 until routesArr.length()) {
                        val rObj = routesArr.getJSONObject(rIdx)
                        val dist = rObj.optDouble("distance", 0.0)
                        val dur = rObj.optDouble("duration", 0.0)
                        val geom = rObj.getJSONObject("geometry")
                        val coordsArr = geom.getJSONArray("coordinates")
                        val pts = ArrayList<LatLng>(coordsArr.length())
                        for (cIdx in 0 until coordsArr.length()) {
                            val pt = coordsArr.getJSONArray(cIdx)
                            pts.add(LatLng(pt.getDouble(1), pt.getDouble(0)))
                        }

                        val steps = ArrayList<RouteStepInfo>()
                        val legs = rObj.optJSONArray("legs")
                        if (legs != null && legs.length() > 0) {
                            val stepsArr = legs.getJSONObject(0).optJSONArray("steps")
                            if (stepsArr != null) {
                                for (sIdx in 0 until stepsArr.length()) {
                                    val sObj = stepsArr.getJSONObject(sIdx)
                                    val sDist = sObj.optDouble("distance", 0.0)
                                    val roadName = sObj.optString("name", "")
                                    val maneuver = sObj.optJSONObject("maneuver")
                                    val mType = maneuver?.optString("type", "continue") ?: "continue"
                                    val mMod = maneuver?.optString("modifier", "") ?: ""
                                    val locArr = maneuver?.optJSONArray("location")
                                    val mLoc = if (locArr != null && locArr.length() >= 2) {
                                        LatLng(locArr.getDouble(1), locArr.getDouble(0))
                                    } else {
                                        pts.firstOrNull() ?: startWgs
                                    }
                                    val instr = formatTurnInstruction(mType, mMod, roadName, sDist)
                                    steps.add(RouteStepInfo(instr, sDist, mLoc))
                                }
                            }
                        }

                        val label = when (rIdx) {
                            0 -> "推荐路线 (最快)"
                            1 -> "备选方案 2"
                            else -> "备选方案 ${rIdx + 1}"
                        }
                        routes.add(ComputedRoute(label, pts, steps, dist, dur))
                    }
                }
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "OSRM routing fallback: ${e.message}")
        }

        if (routes.isEmpty()) {
            // Offline / fallback route
            val dist = CoordinateConverter.distanceMeters(startWgs, destWgs)
            val midLat = (startWgs.latitude + destWgs.latitude) / 2.0 + 0.0012
            val midLon = (startWgs.longitude + destWgs.longitude) / 2.0 - 0.0012
            val pts = listOf(startWgs, LatLng(midLat, midLon), destWgs)
            val speedMps = when (travelMode) {
                NavigationTravelMode.DRIVING -> 12.0
                NavigationTravelMode.EBIKE -> 5.5
                NavigationTravelMode.WALKING -> 1.3
                NavigationTravelMode.TRANSIT -> 9.0
            }
            val dur = (dist / speedMps).coerceAtLeast(60.0)
            routes.add(
                ComputedRoute(
                    name = "直线/离线引导路线",
                    points = pts,
                    steps = listOf(
                        RouteStepInfo("沿当前道路直行前往目的地", dist * 0.5, pts[1]),
                        RouteStepInfo("即将到达终点附近", dist * 0.5, destWgs)
                    ),
                    totalDistanceMeters = dist,
                    durationSeconds = dur
                )
            )
        }
        return routes
    }

    private fun formatTurnInstruction(type: String, modifier: String, roadName: String, distMeters: Double): String {
        val action = when (type) {
            "depart" -> "从起点出发"
            "arrive" -> "到达目的地"
            else -> when {
                modifier.contains("left") -> "左转"
                modifier.contains("right") -> "右转"
                modifier.contains("uturn") -> "掉头"
                else -> "直行"
            }
        }
        val distStr = if (distMeters >= 1000) String.format("%.1f公里", distMeters / 1000.0) else "${distMeters.toInt()}米"
        return if (roadName.isNotBlank()) "前方${distStr}${action} 进入 $roadName" else "前方${distStr}${action}"
    }
}
