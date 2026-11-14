package com.tomy.httnavicompanion

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.gms.location.*
import com.tomy.httnavicompanion.ui.cockpit.CockpitScreen
import com.tomy.httnavicompanion.ui.overlay.FloatingMascotService
import com.tomy.httnavicompanion.ui.theme.HTTNaviCompanionTheme

class MainActivity : ComponentActivity() {

    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var systemLocationManager: LocationManager? = null
    private var systemLocationListener: LocationListener? = null

    private val requestLocationPermission = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { perms ->
        val granted = perms[android.Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            perms[android.Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (granted) {
            startRealLocationUpdates()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        } catch (t: Throwable) {
            Log.w("MainActivity", "FusedLocationProvider unavailable, using system LocationManager", t)
        }

        setContent {
            HTTNaviCompanionTheme {
                CockpitScreen(
                    onStartFloatingPet = { startOverlayService() }
                )
            }
        }

        window.decorView.post {
            try {
                val perms = mutableListOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    perms.add(android.Manifest.permission.BLUETOOTH_SCAN)
                    perms.add(android.Manifest.permission.BLUETOOTH_CONNECT)
                    perms.add(android.Manifest.permission.BLUETOOTH_ADVERTISE)
                }
                requestLocationPermission.launch(perms.toTypedArray())
            } catch (t: Throwable) {
                Log.w("MainActivity", "Permission launch warning", t)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startRealLocationUpdates() {
        // 1. Try Google Play Services FusedLocationProviderClient
        try {
            val client = fusedLocationClient
            if (client != null) {
                client.lastLocation.addOnSuccessListener { loc ->
                    if (loc != null) {
                        HTTNaviApp.instance.audioPlayerManager.updateRealLocation(
                            loc.latitude, loc.longitude, loc.speed, loc.bearing
                        )
                    }
                }

                val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1500L)
                    .setMinUpdateIntervalMillis(1000L)
                    .build()

                val cb = object : LocationCallback() {
                    override fun onLocationResult(result: LocationResult) {
                        result.lastLocation?.let { loc ->
                            HTTNaviApp.instance.audioPlayerManager.updateRealLocation(
                                loc.latitude, loc.longitude, loc.speed, loc.bearing
                            )
                        }
                    }
                }
                locationCallback = cb
                client.requestLocationUpdates(req, cb, Looper.getMainLooper())
            }
        } catch (t: Throwable) {
            Log.w("MainActivity", "GMS location failed, falling back to system LocationManager", t)
        }

        // 2. Also register native Android LocationManager (works on MuMu & non-GMS Chinese ROMs)
        try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
            systemLocationManager = lm
            val listener = object : LocationListener {
                override fun onLocationChanged(loc: Location) {
                    HTTNaviApp.instance.audioPlayerManager.updateRealLocation(
                        loc.latitude, loc.longitude, loc.speed, loc.bearing
                    )
                }
                @Deprecated("Deprecated in Java")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
            }
            systemLocationListener = listener
            for (prov in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                if (lm.isProviderEnabled(prov)) {
                    lm.getLastKnownLocation(prov)?.let { loc ->
                        HTTNaviApp.instance.audioPlayerManager.updateRealLocation(
                            loc.latitude, loc.longitude, loc.speed, loc.bearing
                        )
                    }
                    lm.requestLocationUpdates(prov, 1500L, 1f, listener, Looper.getMainLooper())
                }
            }
        } catch (t: Throwable) {
            Log.w("MainActivity", "System LocationManager error", t)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        locationCallback?.let {
            try { fusedLocationClient?.removeLocationUpdates(it) } catch (_: Throwable) {}
        }
        systemLocationListener?.let {
            try { systemLocationManager?.removeUpdates(it) } catch (_: Throwable) {}
        }
    }

    private fun startOverlayService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "请先授予悬浮窗权限以显示桌面桌宠", Toast.LENGTH_LONG).show()
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        } else {
            val intent = Intent(this, FloatingMascotService::class.java)
            startService(intent)
            Toast.makeText(this, "桌面悬浮桌宠已启动！可在系统桌面或任意App上互动", Toast.LENGTH_SHORT).show()
        }
    }
}
