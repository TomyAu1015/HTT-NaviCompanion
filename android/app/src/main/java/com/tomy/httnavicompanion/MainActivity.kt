package com.tomy.httnavicompanion

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import com.tomy.httnavicompanion.ui.cockpit.CockpitScreen
import com.tomy.httnavicompanion.ui.overlay.FloatingMascotService
import com.tomy.httnavicompanion.ui.theme.HTTNaviCompanionTheme

class MainActivity : ComponentActivity() {

    private val requestLocationPermission = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { _ ->
        // Location permissions callback
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestLocationPermission.launch(
            arrayOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            )
        )

        setContent {
            HTTNaviCompanionTheme {
                CockpitScreen(
                    onStartFloatingPet = { startOverlayService() }
                )
            }
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
