package com.tomy.httnavicompanion.ui.cockpit

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.*

@Composable
fun VehicleAndPlateSettingsDialog(onDismiss: () -> Unit) {
    val manager = HTTNaviApp.instance.audioPlayerManager
    val plate by manager.vehicleLicensePlate.collectAsState()
    val energy by manager.vehicleEnergyType.collectAsState()
    val bodyType by manager.vehicleBodyType.collectAsState()
    val avoids by manager.drivingAvoidOptions.collectAsState()
    val tileMode by manager.mapTileMode.collectAsState()

    var plateInput by remember(plate) { mutableStateOf(plate) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .fillMaxHeight(0.86f)
                .clip(RoundedCornerShape(18.dp))
                .border(2.dp, Color(0xFFE0B861), RoundedCornerShape(18.dp)),
            color = Color(0xFF161821)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(14.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("车辆档案 · 限行避让 · 地图图层设置", color = Color(0xFFFAF2E0), fontSize = 16.sp, fontWeight = FontWeight.Black)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                    }
                }

                // 1. Map Tile Source Mode
                Text("1. 地图引擎与图层选择", color = Color(0xFFE0B861), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                MapTileSourceMode.values().forEach { mode ->
                    val sel = tileMode == mode
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (sel) Color(0xFFA61E2E) else Color(0xFF202431))
                            .border(1.dp, if (sel) Color(0xFFE0B861) else Color.Transparent, RoundedCornerShape(10.dp))
                            .clickable { manager.setMapTileMode(mode) }
                            .padding(horizontal = 12.dp, vertical = 9.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(mode.label, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        if (sel) Icon(Icons.Default.Check, contentDescription = null, tint = Color(0xFFE0B861), modifier = Modifier.size(16.dp))
                    }
                }

                // 2. License Plate
                Text("2. 车牌号与限行智能识别", color = Color(0xFFE0B861), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = plateInput,
                    onValueChange = {
                        plateInput = it
                        manager.setVehicleLicensePlate(it)
                    },
                    label = { Text("输入车牌号 (如 粤B·HTT01)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                // 3. Energy Type
                Text("3. 车辆能源类型", color = Color(0xFFE0B861), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    VehicleEnergyType.values().forEach { e ->
                        val sel = energy == e
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (sel) Color(0xFF2E7D32) else Color(0xFF202431))
                                .border(1.dp, if (sel) Color(0xFFE0B861) else Color.Transparent, RoundedCornerShape(8.dp))
                                .clickable { manager.setVehicleEnergyType(e) }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(e.label, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                // 4. Body Type
                Text("4. 车型尺寸", color = Color(0xFFE0B861), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    VehicleBodyType.values().forEach { b ->
                        val sel = bodyType == b
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (sel) Color(0xFFA61E2E) else Color(0xFF202431))
                                .border(1.dp, if (sel) Color(0xFFE0B861) else Color.Transparent, RoundedCornerShape(8.dp))
                                .clickable { manager.setVehicleBodyType(b) }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(b.label, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                // 5. Driving Avoidance
                Text("5. 路线避让偏好", color = Color(0xFFE0B861), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    DrivingAvoidanceOption.values().forEach { opt ->
                        val sel = avoids.contains(opt)
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (sel) Color(0xFF1976D2) else Color(0xFF202431))
                                .border(1.dp, if (sel) Color(0xFFE0B861) else Color.Transparent, RoundedCornerShape(8.dp))
                                .clickable { manager.toggleDrivingAvoidOption(opt) }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(opt.label, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
