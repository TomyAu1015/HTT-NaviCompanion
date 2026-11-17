package com.tomy.httnavicompanion.data

import kotlin.math.*

data class LatLng(val latitude: Double, val longitude: Double)

object CoordinateConverter {
    private const val A = 6378245.0
    private const val EE = 0.00669342162296594323

    fun isOutOfChina(lat: Double, lon: Double): Boolean {
        if (lon < 72.004 || lon > 137.8347) return true
        if (lat < 0.8293 || lat > 55.8271) return true
        return false
    }

    /**
     * Checks if coordinate is inside Mainland China (excluding HK, Macau, Taiwan)
     * with an accurate piecewise Shenzhen-HK border curve so Shekou/Nanshan and
     * Lok Ma Chau/Lo Wu never suffer 500m GCJ-02/WGS-84 offset errors.
     */
    fun isInMainlandChina(lat: Double, lon: Double): Boolean {
        if (isOutOfChina(lat, lon)) return false
        // Hong Kong & Macau bounding region
        if (lat in 22.10..22.565 && lon in 113.50..114.46) {
            val borderLat = when {
                lon < 113.85 -> 22.25  // Macau / Zhuhai waters
                lon < 113.95 -> 22.472 // Shekou / Shenzhen Bay West
                lon < 114.03 -> 22.495 // Shenzhen Bay Bridge
                lon < 114.11 -> 22.512 // Futian / Lok Ma Chau
                lon < 114.18 -> 22.531 // Lo Wu / Man Kam To
                else -> 22.548         // Sha Tau Kok / Mirs Bay
            }
            if (lat < borderLat) return false
        }
        // Exclude Taiwan bounding box
        if (lat in 21.85..25.35 && lon in 119.30..122.05) return false
        return true
    }

    fun wgs84ToGCJ02(latLng: LatLng): LatLng {
        if (!isInMainlandChina(latLng.latitude, latLng.longitude)) {
            return latLng
        }
        var dLat = transformLat(latLng.longitude - 105.0, latLng.latitude - 35.0)
        var dLon = transformLon(latLng.longitude - 105.0, latLng.latitude - 35.0)
        val radLat = latLng.latitude / 180.0 * Math.PI
        var magic = sin(radLat)
        magic = 1.0 - EE * magic * magic
        val sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((A * (1.0 - EE)) / (magic * sqrtMagic) * Math.PI)
        dLon = (dLon * 180.0) / (A / sqrtMagic * cos(radLat) * Math.PI)
        return LatLng(latLng.latitude + dLat, latLng.longitude + dLon)
    }

    /**
     * 3-iteration inverse GCJ-02 -> WGS-84 conversion (< 0.5m accuracy)
     */
    fun gcj02ToWGS84(latLng: LatLng): LatLng {
        if (!isInMainlandChina(latLng.latitude, latLng.longitude)) {
            return latLng
        }
        var wgsLat = latLng.latitude
        var wgsLon = latLng.longitude
        for (i in 0 until 3) {
            val gcj = wgs84ToGCJ02(LatLng(wgsLat, wgsLon))
            wgsLat += (latLng.latitude - gcj.latitude)
            wgsLon += (latLng.longitude - gcj.longitude)
        }
        return LatLng(wgsLat, wgsLon)
    }

    fun distanceMeters(a: LatLng, b: LatLng): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(b.latitude - a.latitude)
        val dLon = Math.toRadians(b.longitude - a.longitude)
        val sinLat = sin(dLat / 2.0)
        val sinLon = sin(dLon / 2.0)
        val h = sinLat * sinLat +
            cos(Math.toRadians(a.latitude)) * cos(Math.toRadians(b.latitude)) * sinLon * sinLon
        return 2.0 * r * asin(sqrt(h.coerceIn(0.0, 1.0)))
    }

    fun bearingDegrees(from: LatLng, to: LatLng): Double {
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val dLon = Math.toRadians(to.longitude - from.longitude)
        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (Math.toDegrees(atan2(y, x)) + 360.0) % 360.0
    }

    private fun transformLat(x: Double, y: Double): Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Math.PI) + 20.0 * sin(2.0 * x * Math.PI)) * 2.0 / 3.0
        ret += (20.0 * sin(y * Math.PI) + 40.0 * sin(y / 3.0 * Math.PI)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * Math.PI) + 320 * sin(y * Math.PI / 30.0)) * 2.0 / 3.0
        return ret
    }

    private fun transformLon(x: Double, y: Double): Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Math.PI) + 20.0 * sin(2.0 * x * Math.PI)) * 2.0 / 3.0
        ret += (20.0 * sin(x * Math.PI) + 40.0 * sin(x / 3.0 * Math.PI)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * Math.PI) + 300.0 * sin(x / 30.0 * Math.PI)) * 2.0 / 3.0
        return ret
    }
}
