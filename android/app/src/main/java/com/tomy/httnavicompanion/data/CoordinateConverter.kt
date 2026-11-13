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
     * so Amap GCJ-02 tiles and Mars coordinate offsets are applied accurately.
     */
    fun isInMainlandChina(lat: Double, lon: Double): Boolean {
        if (isOutOfChina(lat, lon)) return false
        // Exclude Hong Kong & Macau bounding box (approx 22.12..22.56, 113.50..114.45)
        if (lat in 22.10..22.565 && lon in 113.50..114.46) {
            // Shenzhen north of 22.505 is Mainland China, HK south of 22.505 uses WGS-84
            if (lat < 22.505) return false
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

    fun gcj02ToWGS84(latLng: LatLng): LatLng {
        if (!isInMainlandChina(latLng.latitude, latLng.longitude)) {
            return latLng
        }
        val gcj = wgs84ToGCJ02(latLng)
        val dLat = gcj.latitude - latLng.latitude
        val dLon = gcj.longitude - latLng.longitude
        return LatLng(latLng.latitude - dLat, latLng.longitude - dLon)
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
