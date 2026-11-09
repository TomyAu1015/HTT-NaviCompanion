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
import androidx.compose.material3.*
import androidx.compose.runtime.*
import com.tomy.httnavicompanion.ui.cockpit.CockpitScreen
import com.tomy.httnavicompanion.ui.overlay.FloatingMascotService
import com.tomy.httnavicompanion.ui.theme.HTTNaviCompanionTheme

class MainActivity : ComponentActivity() {

    private val requestLocationPermission = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { perms ->
        // GPS permission results
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request standard location permissions
        requestLocationPermission.launch(
            arrayOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            )
        )

        setContent {
            HTTNaviCompanionTheme {
                var showFeedbackDialog by remember { mutableStateOf(false) }

                CockpitScreen(
                    onOpenFeedback = { showFeedbackDialog = true },
                    onStartFloatingPet = { startOverlayService() }
                )

                if (showFeedbackDialog) {
                    AlertDialog(
                        onDismissRequest = { showFeedbackDialog = false },
                        title = { Text("放课后茶会伴侣 · 交流与反馈") },
                        text = {
                            Text(
                                "【作者与社区渠道】\n\n" +
                                "• 哔哩哔哩 (B站)：小君殇 (UID: 239899475)\n" +
                                "• 小红书：小君殇 (小红书号: 638021380)\n" +
                                "• 抖音：不懂二次元的君殇 (抖音号: 363314224)\n" +
                                "• Instagram：@tomy.au1015\n\n" +
                                "欢迎反馈 BUG 与新功能建议！"
                            )
                        },
                        confirmButton = {
                            TextButton(onClick = { showFeedbackDialog = false }) {
                                Text("知道了")
                            }
                        }
                    )
                }
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
            Toast.makeText(this, "桌面悬浮桌宠已启动！可在系统任意界面互动", Toast.LENGTH_SHORT).show()
        }
    }
}
