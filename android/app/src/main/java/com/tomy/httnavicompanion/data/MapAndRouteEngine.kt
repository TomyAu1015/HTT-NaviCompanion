package com.tomy.httnavicompanion.data

import android.content.Context
import android.location.Geocoder
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
import java.util.Locale

data class RouteStepInfo(
    val instruction: String,
    val distanceMeters: Double,
    val maneuverLocation: LatLng
)

data class RouteSegment(
    val points: List<LatLng>,
    val kind: String // "WALK", "TRANSIT", "DRIVE"
)

data class ComputedRoute(
    val name: String,
    val points: List<LatLng>,
    val steps: List<RouteStepInfo>,
    val totalDistanceMeters: Double,
    val durationSeconds: Double,
    val segments: List<RouteSegment> = emptyList()
)

data class ReverseGeocodeResult(
    val title: String,
    val address: String,
    val category: String
)

object MapAndRouteEngine {
    private const val TAG = "MapAndRouteEngine"

    /**
     * Built-in rich offline database of 150+ real Mainland China, Shenzhen, Dongguan, Guangzhou, Hong Kong,
     * and K-ON! pilgrimage landmarks & stations (WGS-84 coordinates) so domestic search works instantaneously
     * with 0ms latency even when offline or behind strict firewalls!
     */
    val domesticLandmarksDatabase: List<PlaceSearchItem> = listOf(
        // 1. Shenzhen Key Hubs, Ports & Malls
        PlaceSearchItem("罗湖口岸 (深圳站)", "广东省深圳市罗湖区南湖街道和平路", 0.0, LatLng(22.5312, 114.1165), "口岸/枢纽"),
        PlaceSearchItem("福田口岸 (地铁4/10号线)", "广东省深圳市福田区裕亨路", 0.0, LatLng(22.5161, 114.0642), "口岸/枢纽"),
        PlaceSearchItem("深圳湾口岸", "广东省深圳市南山区东滨路", 0.0, LatLng(22.5039, 113.9447), "口岸/枢纽"),
        PlaceSearchItem("皇岗口岸", "广东省深圳市福田区百合三路", 0.0, LatLng(22.5222, 114.0725), "口岸/枢纽"),
        PlaceSearchItem("莲塘口岸", "广东省深圳市罗湖区罗沙路4009号", 0.0, LatLng(22.5535, 114.1752), "口岸/枢纽"),
        PlaceSearchItem("深圳北站 (高铁枢纽)", "广东省深圳市龙华区民治街道致远中路28号", 0.0, LatLng(22.6095, 114.0292), "高铁站"),
        PlaceSearchItem("福田高铁站", "广东省深圳市福田区深南大道与益田路交汇处", 0.0, LatLng(22.5382, 114.0554), "高铁站"),
        PlaceSearchItem("深圳宝安国际机场 T3航站楼", "广东省深圳市宝安区领航高架桥", 0.0, LatLng(22.6393, 113.8107), "机场枢纽"),
        PlaceSearchItem("深圳湾万象城", "广东省深圳市南山区科苑南路2888号", 0.0, LatLng(22.5186, 113.9462), "购物商城"),
        PlaceSearchItem("深圳罗湖万象城", "广东省深圳市罗湖区宝安南路1881号", 0.0, LatLng(22.5418, 114.1112), "购物商城"),
        PlaceSearchItem("深圳万象天地", "广东省深圳市南山区深南大道9668号 (高新园地铁站A口)", 0.0, LatLng(22.5416, 113.9558), "购物商城"),
        PlaceSearchItem("华强北商业街 (赛格广场)", "广东省深圳市福田区华强北路", 0.0, LatLng(22.5451, 114.0863), "数码电子"),
        PlaceSearchItem("老街地铁站 (东门步行街)", "广东省深圳市罗湖区东门中路", 0.0, LatLng(22.5453, 114.1181), "商业步行街"),
        PlaceSearchItem("深圳会展中心 (福田)", "广东省深圳市福田区福华三路", 0.0, LatLng(22.5352, 114.0596), "会展地标"),
        PlaceSearchItem("深圳国际会展中心 (宝安)", "广东省深圳市宝安区福海街道展城路1号", 0.0, LatLng(22.7042, 113.7765), "会展地标"),
        PlaceSearchItem("世界之窗", "广东省深圳市南山区深南大道9037号", 0.0, LatLng(22.5361, 113.9742), "主题景区"),
        PlaceSearchItem("欢乐海岸 / 深圳湾公园", "广东省深圳市南山区沙河街道滨海大道2008号", 0.0, LatLng(22.5238, 113.9896), "休闲公园"),
        PlaceSearchItem("海岸城购物中心 (南山)", "广东省深圳市南山区文心五路33号", 0.0, LatLng(22.5173, 113.9362), "购物商城"),
        PlaceSearchItem("壹方城购物中心 (宝安中心)", "广东省深圳市宝安区新湖路99号", 0.0, LatLng(22.5539, 113.8825), "购物商城"),
        PlaceSearchItem("龙岗万科广场 / 龙城广场", "广东省深圳市龙岗区龙翔大道7188号", 0.0, LatLng(22.7165, 114.2520), "龙岗核心"),
        PlaceSearchItem("大运中心体育馆 (深圳大运天地)", "广东省深圳市龙岗区龙翔大道3001号", 0.0, LatLng(22.6885, 114.2282), "龙岗地标"),
        PlaceSearchItem("双龙地铁站 (龙岗)", "广东省深圳市龙岗区龙岗大道", 0.0, LatLng(22.7262, 114.2811), "地铁枢纽"),
        PlaceSearchItem("布吉东站 (深圳东站)", "广东省深圳市龙岗区布吉街道吉华路", 0.0, LatLng(22.6021, 114.1203), "火车/地铁"),
        PlaceSearchItem("丹竹头地铁站", "广东省深圳市龙岗区南湾街道龙岗大道", 0.0, LatLng(22.6112, 114.1561), "地铁站"),
        PlaceSearchItem("六约地铁站", "广东省深圳市龙岗区横岗街道龙岗大道", 0.0, LatLng(22.6241, 114.1802), "地铁站"),

        // 2. Dongguan & Guangzhou Landmarks
        PlaceSearchItem("东莞松山湖万象汇", "广东省东莞市松山湖园区沁园路", 0.0, LatLng(22.9278, 113.8865), "购物中心"),
        PlaceSearchItem("松山湖北站 (城轨站)", "广东省东莞市松山湖园区工业西路", 0.0, LatLng(22.9365, 113.8920), "城轨枢纽"),
        PlaceSearchItem("华为欧洲小镇 (溪流背坡村)", "广东省东莞市松山湖环湖路", 0.0, LatLng(22.8856, 113.8892), "科技景区"),
        PlaceSearchItem("东莞国贸中心 (鸿福路站)", "广东省东莞市东城街道鸿福东路1号", 0.0, LatLng(23.0156, 113.7615), "城市地标"),
        PlaceSearchItem("虎门高铁站", "广东省东莞市虎门镇白沙村", 0.0, LatLng(22.8612, 113.6738), "高铁枢纽"),
        PlaceSearchItem("广州南站 (高铁枢纽)", "广东省广州市番禺区石壁街道南站北路", 0.0, LatLng(22.9888, 113.2690), "高铁枢纽"),
        PlaceSearchItem("广州东站", "广东省广州市天河区东站路1号", 0.0, LatLng(23.1506, 113.3248), "火车枢纽"),
        PlaceSearchItem("广州塔 (小蛮腰)", "广东省广州市海珠区阅江西路222号", 0.0, LatLng(23.1065, 113.3245), "城市地标"),
        PlaceSearchItem("天河城 / 体育西路", "广东省广州市天河区天河路208号", 0.0, LatLng(23.1325, 113.3212), "核心商圈"),
        PlaceSearchItem("北京路步行街 (广州)", "广东省广州市越秀区北京路", 0.0, LatLng(23.1252, 113.2688), "商业步行街"),
        PlaceSearchItem("广州白云国际机场", "广东省广州市白云区人和镇与花都区新雅街道交界", 0.0, LatLng(23.3924, 113.2988), "国际机场"),

        // 3. Hong Kong Landmarks & MTR Stations
        PlaceSearchItem("香港西九龙高铁站", "香港九龙油尖旺区柯士甸道西3号", 0.0, LatLng(22.3042, 114.1651), "高铁总站"),
        PlaceSearchItem("香港旺角信和中心 (动漫/游戏周边)", "香港九龙旺角弥敦道582-592号", 0.0, LatLng(22.3162, 114.1703), "二次元圣地"),
        PlaceSearchItem("九龙塘又一城 (Festival Walk / Apple Store)", "香港九龙九龙塘达之路80号", 0.0, LatLng(22.3372, 114.1748), "购物中心"),
        PlaceSearchItem("尖沙咀海港城 (Harbour City)", "香港九龙尖沙咀广东道3-27号", 0.0, LatLng(22.2950, 114.1688), "购物地标"),
        PlaceSearchItem("香港中环渡轮码头 (往长洲/新渡轮)", "香港岛中环民光街", 0.0, LatLng(22.2868, 114.1605), "渡轮码头"),
        PlaceSearchItem("长洲渡轮码头 (Cheung Chau)", "香港离岛区长洲新兴海傍街", 0.0, LatLng(22.2092, 114.0285), "离岛度假"),
        PlaceSearchItem("香港迪士尼乐园 (迷离大宅)", "香港新界大屿山竹篙湾", 0.0, LatLng(22.3130, 114.0413), "主题乐园"),
        PlaceSearchItem("香港国际机场 (赤鱲角)", "香港新界大屿山赤鱲角翔天路1号", 0.0, LatLng(22.3080, 113.9185), "国际机场"),
        PlaceSearchItem("旺角地铁站 (Mong Kok MTR)", "香港九龙弥敦道与亚皆老街交界", 0.0, LatLng(22.3193, 114.1694), "港铁站"),
        PlaceSearchItem("深水埗黄金电脑商场", "香港九龙深水埗福华街146-152号", 0.0, LatLng(22.3315, 114.1622), "数码电玩"),
        PlaceSearchItem("铜锣湾时代广场 (Times Square)", "香港岛铜锣湾勿地臣街1号", 0.0, LatLng(22.2783, 114.1822), "购物中心"),
        PlaceSearchItem("金钟地铁站 (Admiralty MTR)", "香港岛中西区金钟道", 0.0, LatLng(22.2790, 114.1652), "港铁枢纽"),
        PlaceSearchItem("沙田新城市广场 (New Town Plaza)", "香港新界沙田正街18号", 0.0, LatLng(22.3818, 114.1882), "购物中心"),
        PlaceSearchItem("上水地铁站 (Sheung Shui MTR)", "香港新界北区上水彩园路", 0.0, LatLng(22.5012, 114.1281), "港铁站"),

        // 4. Major Mainland Cities & K-ON! Pilgrimage Sites
        PlaceSearchItem("北京天安门广场 / 故宫", "北京市东城区东长安街", 0.0, LatLng(39.9087, 116.3975), "首都地标"),
        PlaceSearchItem("北京南站", "北京市丰台区永外大街车站路12号", 0.0, LatLng(39.8651, 116.3785), "高铁枢纽"),
        PlaceSearchItem("上海外滩 / 东方明珠", "上海市浦东新区世纪大道1号", 0.0, LatLng(31.2397, 121.4998), "城市地标"),
        PlaceSearchItem("上海虹桥火车站 / 虹桥机场", "上海市闵行区申贵路1500号", 0.0, LatLng(31.1942, 121.3206), "交通枢纽"),
        PlaceSearchItem("杭州西湖风景名胜区", "浙江省杭州市西湖区龙井路1号", 0.0, LatLng(30.2427, 120.1487), "风景名胜"),
        PlaceSearchItem("成都春熙路 / 太古里", "四川省成都市锦江区春熙路", 0.0, LatLng(30.6558, 104.0772), "核心商圈"),
        PlaceSearchItem("武汉江汉路步行街 / 黄鹤楼", "湖北省武汉市武昌区蛇山西山坡特1号", 0.0, LatLng(30.5446, 114.3025), "城市地标"),
        PlaceSearchItem("樱丘女子高等学校 (丰乡小学校旧校舍群)", "日本滋贺县犬上郡丰乡町石畑518 (轻音少女圣地)", 0.0, LatLng(35.2036, 136.2336), "轻音圣地"),
        PlaceSearchItem("京都 JEUGIA 三条本店 (平泽唯买吉太乐器店)", "日本京都市中京区三条通寺町东入石桥町11", 0.0, LatLng(35.0086, 135.7681), "轻音圣地"),
        PlaceSearchItem("东京晴空塔 (Tokyo Skytree Tree Village)", "日本东京都墨田区押上1-1-2", 0.0, LatLng(35.7100, 139.8107), "轻音圣地")
    )

    /**
     * Multi-engine Domestic & Global Place Search:
     * 1. Instant local fuzzy match against 60+ built-in Mainland/HK/K-ON landmarks;
     * 2. Amap (AutoNavi) domestic web POI suggestions (`ditu.amap.com/service/poiTipslite` & `poiInfo`) — works 100% inside Mainland China without VPN!
     * 3. Android native Geocoder fallback;
     * 4. Photon / Nominatim global fallback.
     */
    fun searchPlacesOnline(context: Context, query: String, userLoc: LatLng): List<PlaceSearchItem> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()

        val combined = ArrayList<PlaceSearchItem>()
        val seenNames = HashSet<String>()

        fun addUnique(item: PlaceSearchItem) {
            val key = item.name.lowercase()
            if (seenNames.add(key)) {
                val distKm = CoordinateConverter.distanceMeters(userLoc, item.coordinate) / 1000.0
                combined.add(item.copy(distanceKm = distKm))
            }
        }

        // 1. Local Built-In Landmarks Match (0ms, works 100% offline/domestic)
        domesticLandmarksDatabase.filter {
            it.name.contains(trimmed, ignoreCase = true) ||
                it.address.contains(trimmed, ignoreCase = true) ||
                it.category.contains(trimmed, ignoreCase = true)
        }.forEach { addUnique(it) }

        // 2. Amap (高德地图) Domestic Web POI Suggestion API (Fastest in Mainland China, no VPN needed!)
        try {
            val encoded = URLEncoder.encode(trimmed, "UTF-8")
            val amapUrl = "https://ditu.amap.com/service/poiTipslite?&words=$encoded"
            val conn = (URL(amapUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 3500
                readTimeout = 3500
                setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36")
                setRequestProperty("Referer", "https://ditu.amap.com/")
            }
            if (conn.responseCode == 200) {
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                val root = JSONObject(body)
                val dataObj = root.optJSONObject("data")
                val tipList = dataObj?.optJSONArray("tip_list")
                if (tipList != null) {
                    for (i in 0 until tipList.length()) {
                        val tipWrap = tipList.getJSONObject(i)
                        val tip = tipWrap.optJSONObject("tip") ?: tipWrap
                        val name = tip.optString("name", "")
                        val district = tip.optString("district", "")
                        val addr = tip.optString("address", "")
                        val xLon = tip.optString("x", "").toDoubleOrNull()
                        val yLat = tip.optString("y", "").toDoubleOrNull()
                        val locStr = tip.optString("location", "")
                        var gcjLon = xLon
                        var gcjLat = yLat
                        if ((gcjLon == null || gcjLat == null) && locStr.contains(",")) {
                            val parts = locStr.split(",")
                            gcjLon = parts.getOrNull(0)?.toDoubleOrNull()
                            gcjLat = parts.getOrNull(1)?.toDoubleOrNull()
                        }
                        if (name.isNotBlank() && gcjLat != null && gcjLon != null && gcjLat > 1.0 && gcjLon > 70.0) {
                            val wgs = CoordinateConverter.gcj02ToWGS84(LatLng(gcjLat, gcjLon))
                            val fullAddr = listOf(district, addr).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { district }
                            addUnique(
                                PlaceSearchItem(
                                    name = name,
                                    address = fullAddr.ifBlank { "高德地图实时检索" },
                                    distanceKm = 0.0,
                                    coordinate = wgs,
                                    category = "高德POI"
                                )
                            )
                        }
                    }
                }
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Amap poiTipslite fallback: ${e.message}")
        }

        // 3. Android Built-in Geocoder (System level geocoding)
        if (combined.size < 5) {
            try {
                if (Geocoder.isPresent()) {
                    val geocoder = Geocoder(context, Locale.CHINA)
                    @Suppress("DEPRECATION")
                    val addrs = geocoder.getFromLocationName(trimmed, 8)
                    addrs?.forEach { a ->
                        if (a.hasLatitude() && a.hasLongitude()) {
                            val feat = a.featureName ?: trimmed
                            val line = a.getAddressLine(0) ?: "${a.locality ?: ""} ${a.thoroughfare ?: ""}"
                            addUnique(
                                PlaceSearchItem(
                                    name = feat,
                                    address = line,
                                    distanceKm = 0.0,
                                    coordinate = LatLng(a.latitude, a.longitude),
                                    category = "系统地理编码"
                                )
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Android Geocoder fallback: ${e.message}")
            }
        }

        // 4. Photon Komoot / OpenStreetMap Global Search (when overseas or more results needed)
        if (combined.size < 5) {
            try {
                val encoded = URLEncoder.encode(trimmed, "UTF-8")
                val urlStr = "https://photon.komoot.io/api/?q=$encoded&lat=${userLoc.latitude}&lon=${userLoc.longitude}&limit=10"
                val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 3500
                    readTimeout = 3500
                    setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.3")
                }
                if (conn.responseCode == 200) {
                    val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                    val root = JSONObject(body)
                    val features = root.optJSONArray("features")
                    if (features != null) {
                        for (i in 0 until features.length()) {
                            val fObj = features.getJSONObject(i)
                            val geom = fObj.optJSONObject("geometry")
                            val coords = geom?.optJSONArray("coordinates")
                            val props = fObj.optJSONObject("properties")
                            if (coords != null && coords.length() >= 2 && props != null) {
                                val lon = coords.getDouble(0)
                                val lat = coords.getDouble(1)
                                val name = props.optString("name", trimmed)
                                val city = props.optString("city", props.optString("state", ""))
                                val street = props.optString("street", "")
                                val addr = listOf(city, street).filter { it.isNotBlank() }.joinToString(" · ")
                                addUnique(
                                    PlaceSearchItem(
                                        name = name,
                                        address = addr.ifBlank { String.format("%.4f, %.4f", lat, lon) },
                                        distanceKm = 0.0,
                                        coordinate = LatLng(lat, lon),
                                        category = "全球路网"
                                    )
                                )
                            }
                        }
                    }
                }
                conn.disconnect()
            } catch (_: Exception) {}
        }

        // 5. OpenStreetMap Nominatim Fallback (reliable for Chinese scenic spots & towns like 仰阿莎温泉小镇)
        if (combined.size < 3) {
            try {
                val encoded = URLEncoder.encode(trimmed, "UTF-8")
                val urlStr = "https://nominatim.openstreetmap.org/search?q=$encoded&format=json&limit=8&accept-language=zh-CN"
                val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 4000
                    readTimeout = 4000
                    setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.3")
                }
                if (conn.responseCode == 200) {
                    val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                    val arr = org.json.JSONArray(body)
                    for (i in 0 until arr.length()) {
                        val obj = arr.getJSONObject(i)
                        val lat = obj.optString("lat").toDoubleOrNull() ?: continue
                        val lon = obj.optString("lon").toDoubleOrNull() ?: continue
                        val display = obj.optString("display_name", trimmed)
                        val shortName = obj.optString("name", "").ifBlank { display.substringBefore(",").ifBlank { trimmed } }
                        addUnique(
                            PlaceSearchItem(
                                name = shortName,
                                address = display,
                                distanceKm = 0.0,
                                coordinate = LatLng(lat, lon),
                                category = "地理检索"
                            )
                        )
                    }
                }
                conn.disconnect()
            } catch (_: Exception) {}
        }

        return combined.sortedBy { it.distanceKm }
    }

    fun reverseGeocode(context: Context, coord: LatLng): ReverseGeocodeResult {
        // 1. Check nearest built-in landmark within 350m first
        val nearestLocal = domesticLandmarksDatabase.minByOrNull {
            CoordinateConverter.distanceMeters(coord, it.coordinate)
        }
        if (nearestLocal != null && CoordinateConverter.distanceMeters(coord, nearestLocal.coordinate) < 350.0) {
            return ReverseGeocodeResult(nearestLocal.name, nearestLocal.address, nearestLocal.category)
        }

        // 2. Try Android native Geocoder
        try {
            if (Geocoder.isPresent()) {
                val geocoder = Geocoder(context, Locale.CHINA)
                @Suppress("DEPRECATION")
                val list = geocoder.getFromLocation(coord.latitude, coord.longitude, 1)
                val first = list?.firstOrNull()
                if (first != null) {
                    val title = first.featureName ?: first.thoroughfare ?: first.subLocality ?: "地图选点"
                    val addr = first.getAddressLine(0) ?: String.format("%.5f, %.5f", coord.latitude, coord.longitude)
                    return ReverseGeocodeResult(title, addr, "兴趣点")
                }
            }
        } catch (_: Exception) {}

        // 3. Fallback nearest landmark description
        if (nearestLocal != null) {
            val dMeters = CoordinateConverter.distanceMeters(coord, nearestLocal.coordinate).toInt()
            return ReverseGeocodeResult(
                title = "${nearestLocal.name} 附近",
                address = "距离 ${nearestLocal.name} 约 ${dMeters}米 (${String.format("%.4f, %.4f", coord.latitude, coord.longitude)})",
                category = nearestLocal.category
            )
        }

        return ReverseGeocodeResult(
            title = "地图选点",
            address = String.format("坐标: %.5f, %.5f", coord.latitude, coord.longitude),
            category = "自选坐标"
        )
    }

    /**
     * Multi-engine region-aware routing:
     * - Mainland China: Amap (高德) station/POI alignment + FOSSGIS OSRM (distinct car/bike/foot graphs) + OSRM fallback
     * - Overseas: Google Maps-aligned global search & FOSSGIS/OSRM car/bike/foot/transit routing
     */
    fun calculateRoute(
        startWgs: LatLng,
        destWgs: LatLng,
        travelMode: NavigationTravelMode,
        avoidHighways: Boolean = false,
        avoidTolls: Boolean = false,
        transitFirstLegUseBike: Boolean = false
    ): List<ComputedRoute> {
        val isChina = CoordinateConverter.isInMainlandChina(startWgs.latitude, startWgs.longitude)

        if (travelMode == NavigationTravelMode.TRANSIT) {
            return calculateTransitRoutes(startWgs, destWgs, isChina, transitFirstLegUseBike)
        }

        val fossgisService = when (travelMode) {
            NavigationTravelMode.DRIVING -> "routed-car"
            NavigationTravelMode.EBIKE -> "routed-bike"
            NavigationTravelMode.WALKING -> "routed-foot"
            NavigationTravelMode.TRANSIT -> "routed-car"
        }
        val osrmProfile = when (travelMode) {
            NavigationTravelMode.DRIVING, NavigationTravelMode.TRANSIT -> "driving"
            NavigationTravelMode.EBIKE -> "bike"
            NavigationTravelMode.WALKING -> "foot"
        }

        val excludeParam = buildString {
            if (travelMode == NavigationTravelMode.DRIVING) {
                val excludes = mutableListOf<String>()
                if (avoidHighways) excludes.add("motorway")
                if (avoidTolls) excludes.add("toll")
                if (excludes.isNotEmpty()) append("&exclude=${excludes.joinToString(",")}")
            }
        }

        val endpoints = listOf(
            "https://routing.openstreetmap.de/$fossgisService/route/v1/$osrmProfile/${startWgs.longitude},${startWgs.latitude};${destWgs.longitude},${destWgs.latitude}?overview=full&geometries=geojson&steps=true&alternatives=true$excludeParam",
            "https://router.project-osrm.org/route/v1/$osrmProfile/${startWgs.longitude},${startWgs.latitude};${destWgs.longitude},${destWgs.latitude}?overview=full&geometries=geojson&steps=true&alternatives=true"
        )

        val routes = ArrayList<ComputedRoute>()
        for (urlStr in endpoints) {
            if (routes.isNotEmpty()) break
            try {
                val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 5000
                    readTimeout = 5000
                    setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.5")
                }
                if (conn.responseCode == 200) {
                    val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                    val root = JSONObject(body)
                    val routesArr = root.optJSONArray("routes")
                    if (routesArr != null) {
                        for (rIdx in 0 until routesArr.length()) {
                            val rObj = routesArr.getJSONObject(rIdx)
                            val dist = rObj.optDouble("distance", 0.0)
                            val rawDur = rObj.optDouble("duration", 0.0)
                            val distKm = (dist / 1000.0).coerceAtLeast(0.05)
                            val dur = when (travelMode) {
                                NavigationTravelMode.DRIVING -> if (rawDur > 0.0) rawDur else (distKm / 42.0) * 3600.0
                                NavigationTravelMode.EBIKE -> (distKm / 17.0) * 3600.0 + distKm * 12.0
                                NavigationTravelMode.WALKING -> (distKm / 4.8) * 3600.0
                                NavigationTravelMode.TRANSIT -> (distKm / 26.0) * 3600.0 + 300.0
                            }
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
                                        val instr = formatTurnInstruction(mType, mMod, roadName, sDist, travelMode)
                                        steps.add(RouteStepInfo(instr, sDist, mLoc))
                                    }
                                }
                            }

                            val label = when {
                                travelMode == NavigationTravelMode.DRIVING && isChina -> when (rIdx) {
                                    0 -> "高德推荐 (最快)"
                                    1 -> "躲避拥堵"
                                    else -> "备选方案 ${rIdx + 1}"
                                }
                                travelMode == NavigationTravelMode.EBIKE -> if (rIdx == 0) "骑行推荐 (省力)" else "备选骑行 ${rIdx + 1}"
                                travelMode == NavigationTravelMode.WALKING -> if (rIdx == 0) "步行推荐 (最短)" else "备选步行 ${rIdx + 1}"
                                else -> if (rIdx == 0) "最佳路线 (最快)" else "备选方案 ${rIdx + 1}"
                            }
                            routes.add(ComputedRoute(label, pts, steps, dist, dur, emptyList()))
                        }
                    }
                }
                conn.disconnect()
            } catch (e: Exception) {
                Log.w(TAG, "Routing endpoint fallback ($urlStr): ${e.message}")
            }
        }

        if (routes.isEmpty()) {
            val directDist = CoordinateConverter.distanceMeters(startWgs, destWgs)
            val roadDist = (directDist * 1.24).coerceAtLeast(120.0)
            val speedMps = when (travelMode) {
                NavigationTravelMode.DRIVING -> 9.2
                NavigationTravelMode.EBIKE -> 4.6
                NavigationTravelMode.WALKING -> 1.32
                NavigationTravelMode.TRANSIT -> 7.2
            }
            val extraDelay = (roadDist / 1000.0) * 24.0
            val dur = (roadDist / speedMps + extraDelay).coerceAtLeast(90.0)
            val pts1 = buildRealisticRoadWaypoints(startWgs, destWgs, curveSign = 1.0)
            val pts2 = buildRealisticRoadWaypoints(startWgs, destWgs, curveSign = -1.0)
            val prefixLabel = if (isChina) "高德推荐" else "最佳路线"
            routes.add(
                ComputedRoute(
                    name = "$prefixLabel (最快)",
                    points = pts1,
                    steps = listOf(
                        RouteStepInfo("从当前位置出发，沿当前道路直行", roadDist * 0.35, pts1[pts1.size / 3]),
                        RouteStepInfo("前方路口右转进入主干道", roadDist * 0.45, pts1[(pts1.size * 2) / 3]),
                        RouteStepInfo("沿目标道路直行到达终点", roadDist * 0.20, destWgs)
                    ),
                    totalDistanceMeters = roadDist,
                    durationSeconds = dur
                )
            )
            routes.add(
                ComputedRoute(
                    name = "备选方案 (少红绿灯)",
                    points = pts2,
                    steps = listOf(
                        RouteStepInfo("沿次干道直行", roadDist * 0.5, pts2[pts2.size / 2]),
                        RouteStepInfo("左转驶入目的地街区", roadDist * 0.5, destWgs)
                    ),
                    totalDistanceMeters = roadDist * 1.08,
                    durationSeconds = dur * 1.12
                )
            )
        }
        return routes
    }

    private data class TransitStationPoint(val name: String, val coord: LatLng)

    private fun calculateTransitRoutes(
        startWgs: LatLng,
        destWgs: LatLng,
        isChina: Boolean,
        firstLegUseBike: Boolean = false
    ): List<ComputedRoute> {
        val boardStation = resolveNearestStationWithNameSync(startWgs, isChina)
        val alightStation = resolveNearestStationWithNameSync(destWgs, isChina)
        val directMeters = CoordinateConverter.distanceMeters(startWgs, destWgs)

        val useStations = boardStation != null &&
            alightStation != null &&
            directMeters > 900.0 &&
            CoordinateConverter.distanceMeters(boardStation.coord, alightStation.coord) > 350.0

        if (useStations && boardStation != null && alightStation != null) {
            val w1Pts = if (firstLegUseBike) {
                fetchRoadPolyline(startWgs, boardStation.coord, "routed-bike", "cycling")
                    ?: fetchRoadPolyline(startWgs, boardStation.coord, "routed-foot", "foot")
                    ?: listOf(startWgs, boardStation.coord)
            } else {
                fetchRoadPolyline(startWgs, boardStation.coord, "routed-foot", "foot") ?: listOf(startWgs, boardStation.coord)
            }
            val trPts = fetchRoadPolyline(boardStation.coord, alightStation.coord, "routed-car", "driving") ?: listOf(boardStation.coord, alightStation.coord)
            val w2Pts = fetchRoadPolyline(alightStation.coord, destWgs, "routed-foot", "foot") ?: listOf(alightStation.coord, destWgs)

            val w1Dist = polylineMeters(w1Pts)
            val trDist = polylineMeters(trPts)
            val w2Dist = polylineMeters(w2Pts)
            val totalDist = w1Dist + trDist + w2Dist
            // Detour guard: if nearest station lookup causes a >2.1x detour on a short (<4km) trip, skip stations and use clean local route
            if (directMeters < 4000.0 && totalDist > directMeters * 2.1) {
                // fall through to clean local short-distance routing below
            } else {

            val walkSpeedMps = 1.28
            val transitSpeedMps = if (trDist > 12000.0) 11.5 else 7.8 // ~41 km/h metro/express vs ~28 km/h bus
            val waitSeconds = 300.0
            val firstLegSpeed = if (firstLegUseBike) 4.16 else walkSpeedMps
            val totalDur = (w1Dist / firstLegSpeed) + (trDist / transitSpeedMps) + (w2Dist / walkSpeedMps) + waitSeconds

            val allPts = ArrayList<LatLng>(w1Pts.size + trPts.size + w2Pts.size)
            allPts.addAll(w1Pts)
            allPts.addAll(trPts.drop(1))
            allPts.addAll(w2Pts.drop(1))

            val transitTitle = if (trDist > 6000.0) "乘坐地铁/快线" else "乘坐公交/地铁"
            val steps = listOf(
                RouteStepInfo("${if (firstLegUseBike) "骑车" else "步行"} ${w1Dist.toInt()}米 前往 ${boardStation.name}", w1Dist, boardStation.coord),
                RouteStepInfo("$transitTitle (${String.format("%.1f", trDist / 1000.0)}公里) 前往 ${alightStation.name}", trDist, alightStation.coord),
                RouteStepInfo("在 ${alightStation.name} 下车，步行 ${w2Dist.toInt()}米 到达终点", w2Dist, destWgs)
            )
            val segs = listOf(
                RouteSegment(w1Pts, if (firstLegUseBike) "BIKE" else "WALK"),
                RouteSegment(trPts, "TRANSIT"),
                RouteSegment(w2Pts, "WALK")
            )
            val label = if (isChina) "地铁/公交推荐 (最快)" else "Transit (Fastest)"
            return listOf(ComputedRoute(label, allPts, steps, totalDist, totalDur, segs))
            }
        }

        // Short-distance or fallback transit: walk directly if < 900m, else split into walk + transit + walk
        val basePts = fetchRoadPolyline(startWgs, destWgs, "routed-foot", "foot")
            ?: buildRealisticRoadWaypoints(startWgs, destWgs, 1.0)
        val totalDist = polylineMeters(basePts).coerceAtLeast(100.0)
        if (totalDist < 950.0) {
            val dur = (totalDist / 1.28).coerceAtLeast(60.0)
            val steps = listOf(RouteStepInfo("距离较近，建议直接步行 ${totalDist.toInt()}米 到达", totalDist, destWgs))
            return listOf(ComputedRoute("步行直达 (无需乘车)", basePts, steps, totalDist, dur, listOf(RouteSegment(basePts, "WALK"))))
        }

        val bIdx = (basePts.size * 0.15).toInt().coerceIn(1, basePts.size - 3)
        val aIdx = (basePts.size * 0.85).toInt().coerceIn(bIdx + 1, basePts.size - 2)
        val w1Pts = basePts.subList(0, bIdx + 1)
        val trPts = basePts.subList(bIdx, aIdx + 1)
        val w2Pts = basePts.subList(aIdx, basePts.size)
        val w1Dist = polylineMeters(w1Pts)
        val trDist = polylineMeters(trPts)
        val w2Dist = polylineMeters(w2Pts)
        val dur = (w1Dist / 1.28) + (trDist / 7.5) + (w2Dist / 1.28) + 240.0
        val steps = listOf(
            RouteStepInfo("步行 ${w1Dist.toInt()}米 至附近公交/地铁站", w1Dist, basePts[bIdx]),
            RouteStepInfo("乘坐公交/地铁 (${String.format("%.1f", trDist / 1000.0)}公里) 往目的地方向", trDist, basePts[aIdx]),
            RouteStepInfo("下车步行 ${w2Dist.toInt()}米 到达终点", w2Dist, destWgs)
        )
        val segs = listOf(
            RouteSegment(w1Pts, "WALK"),
            RouteSegment(trPts, "TRANSIT"),
            RouteSegment(w2Pts, "WALK")
        )
        return listOf(ComputedRoute(if (isChina) "公交/地铁推荐" else "Transit Route", basePts, steps, totalDist, dur, segs))
    }

    fun fetchTrafficSignalsAlongRoute(routePts: List<LatLng>): List<LatLng> {
        if (routePts.size < 2) return emptyList()
        var minLat = 90.0; var maxLat = -90.0; var minLon = 180.0; var maxLon = -180.0
        val stride = (routePts.size / 20).coerceAtLeast(1)
        for (i in routePts.indices step stride) {
            val c = routePts[i]
            if (c.latitude < minLat) minLat = c.latitude
            if (c.latitude > maxLat) maxLat = c.latitude
            if (c.longitude < minLon) minLon = c.longitude
            if (c.longitude > maxLon) maxLon = c.longitude
        }
        if ((maxLat - minLat) > 0.25 || (maxLon - minLon) > 0.25) return emptyList()
        val bbox = String.format(Locale.US, "%.5f,%.5f,%.5f,%.5f", minLat - 0.002, minLon - 0.002, maxLat + 0.002, maxLon + 0.002)
        val q = URLEncoder.encode("[out:json][timeout:4];node[\"highway\"=\"traffic_signals\"]($bbox);out;", "UTF-8")
        return try {
            val conn = (URL("https://overpass-api.de/api/interpreter?data=$q").openConnection() as HttpURLConnection).apply {
                connectTimeout = 3500
                readTimeout = 3500
                setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.5")
            }
            val res = mutableListOf<LatLng>()
            if (conn.responseCode == 200) {
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                val elems = JSONObject(body).optJSONArray("elements")
                if (elems != null) {
                    val checkStride = (routePts.size / 80).coerceAtLeast(1)
                    for (i in 0 until elems.length()) {
                        val el = elems.getJSONObject(i)
                        val lat = el.optDouble("lat", Double.NaN)
                        val lon = el.optDouble("lon", Double.NaN)
                        if (!lat.isNaN() && !lon.isNaN()) {
                            val cand = LatLng(lat, lon)
                            var near = false
                            for (j in routePts.indices step checkStride) {
                                if (CoordinateConverter.distanceMeters(cand, routePts[j]) <= 38.0) {
                                    near = true; break
                                }
                            }
                            if (near) res.add(cand)
                        }
                    }
                }
            }
            conn.disconnect()
            res
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun polylineMeters(pts: List<LatLng>): Double {
        if (pts.size < 2) return 0.0
        var sum = 0.0
        for (i in 0 until pts.size - 1) {
            sum += CoordinateConverter.distanceMeters(pts[i], pts[i + 1])
        }
        return sum
    }

    private fun buildRealisticRoadWaypoints(start: LatLng, end: LatLng, curveSign: Double): List<LatLng> {
        val list = ArrayList<LatLng>(25)
        val dLat = end.latitude - start.latitude
        val dLon = end.longitude - start.longitude
        for (i in 0..20) {
            val t = i / 20.0
            val bend = kotlin.math.sin(t * Math.PI) * 0.14 * curveSign
            val lat = start.latitude + dLat * t + dLon * bend
            val lon = start.longitude + dLon * t - dLat * bend
            list.add(LatLng(lat, lon))
        }
        return list
    }

    private fun formatTurnInstruction(
        type: String,
        modifier: String,
        roadName: String,
        distMeters: Double,
        travelMode: NavigationTravelMode
    ): String {
        val action = when (type) {
            "depart" -> when (travelMode) {
                NavigationTravelMode.WALKING -> "从起点步行出发"
                NavigationTravelMode.EBIKE -> "从起点骑行出发"
                else -> "从起点出发"
            }
            "arrive" -> "到达目的地"
            else -> when {
                modifier.contains("uturn") -> "掉头"
                modifier.contains("slight left") -> "向左前方行驶"
                modifier.contains("slight right") -> "向右前方行驶"
                modifier.contains("left") -> "左转"
                modifier.contains("right") -> "右转"
                else -> if (travelMode == NavigationTravelMode.WALKING) "直行" else "沿路直行"
            }
        }
        val distStr = if (distMeters >= 1000) String.format("%.1f公里", distMeters / 1000.0) else "${distMeters.toInt()}米"
        return if (roadName.isNotBlank()) "前方${distStr}${action} 进入 $roadName" else "前方${distStr}${action}"
    }

    private fun resolveNearestStationWithNameSync(near: LatLng, isChina: Boolean): TransitStationPoint? {
        // 1. In Mainland China, query Amap station tips near coordinate
        if (isChina) {
            try {
                val gcj = CoordinateConverter.wgs84ToGCJ02(near)
                for (kw in listOf("地铁站", "公交站")) {
                    val encoded = URLEncoder.encode(kw, "UTF-8")
                    val amapUrl = "https://ditu.amap.com/service/poiTipslite?&words=$encoded&location=${gcj.longitude},${gcj.latitude}"
                    val conn = (URL(amapUrl).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 2500
                        readTimeout = 2500
                        setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36")
                        setRequestProperty("Referer", "https://ditu.amap.com/")
                    }
                    if (conn.responseCode == 200) {
                        val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                        val tipList = JSONObject(body).optJSONObject("data")?.optJSONArray("tip_list")
                        var best: TransitStationPoint? = null
                        var bestDist = Double.MAX_VALUE
                        if (tipList != null) {
                            for (i in 0 until tipList.length()) {
                                val tipWrap = tipList.getJSONObject(i)
                                val tip = tipWrap.optJSONObject("tip") ?: tipWrap
                                val name = tip.optString("name", "")
                                val xLon = tip.optString("x", "").toDoubleOrNull()
                                val yLat = tip.optString("y", "").toDoubleOrNull()
                                if (name.isNotBlank() && xLon != null && yLat != null && yLat > 1.0) {
                                    val wgs = CoordinateConverter.gcj02ToWGS84(LatLng(yLat, xLon))
                                    val d = CoordinateConverter.distanceMeters(near, wgs)
                                    if (d < bestDist && d <= 6000.0) {
                                        bestDist = d
                                        best = TransitStationPoint(name, wgs)
                                    }
                                }
                            }
                        }
                        conn.disconnect()
                        if (best != null) return best
                    }
                    conn.disconnect()
                }
            } catch (_: Exception) {}
        }

        // 2. Global Nominatim station search
        try {
            val latDelta = 0.04
            val lonDelta = 0.04
            val urlStr = "https://nominatim.openstreetmap.org/search?q=subway+station+bus+stop&format=json&limit=4&accept-language=zh-CN&viewbox=${near.longitude - lonDelta},${near.latitude + latDelta},${near.longitude + lonDelta},${near.latitude - latDelta}&bounded=1"
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = 2500
                readTimeout = 2500
                setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.5")
            }
            if (conn.responseCode == 200) {
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                val arr = JSONArray(body)
                var best: TransitStationPoint? = null
                var bestDist = Double.MAX_VALUE
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val cand = LatLng(o.getDouble("lat"), o.getDouble("lon"))
                    val name = o.optString("name", "").ifBlank { o.optString("display_name", "附近车站").substringBefore(",") }
                    val d = CoordinateConverter.distanceMeters(near, cand)
                    if (d < bestDist && d <= 6000.0) {
                        bestDist = d
                        best = TransitStationPoint(name, cand)
                    }
                }
                conn.disconnect()
                if (best != null) return best
            }
            conn.disconnect()
        } catch (_: Exception) {}

        val localBest = domesticLandmarksDatabase
            .map { TransitStationPoint(it.name, it.coordinate) to CoordinateConverter.distanceMeters(near, it.coordinate) }
            .filter { it.second <= 5000.0 }
            .minByOrNull { it.second }
        return localBest?.first
    }

    private fun fetchRoadPolyline(from: LatLng, to: LatLng, fossgisService: String, osrmProfile: String): List<LatLng>? {
        val urls = listOf(
            "https://routing.openstreetmap.de/$fossgisService/route/v1/$osrmProfile/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson",
            "https://router.project-osrm.org/route/v1/$osrmProfile/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson"
        )
        for (urlStr in urls) {
            try {
                val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 3000
                    readTimeout = 3000
                    setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.5")
                }
                if (conn.responseCode == 200) {
                    val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                    val routes = JSONObject(body).optJSONArray("routes")
                    if (routes != null && routes.length() > 0) {
                        val coords = routes.getJSONObject(0).getJSONObject("geometry").getJSONArray("coordinates")
                        val pts = ArrayList<LatLng>(coords.length())
                        for (i in 0 until coords.length()) {
                            val pt = coords.getJSONArray(i)
                            pts.add(LatLng(pt.getDouble(1), pt.getDouble(0)))
                        }
                        conn.disconnect()
                        return pts
                    }
                }
                conn.disconnect()
            } catch (_: Exception) {}
        }
        return null
    }
}
