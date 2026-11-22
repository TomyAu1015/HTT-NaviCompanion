import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.tomy.httnavicompanion"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.tomy.httnavicompanion"
        minSdk = 26
        targetSdk = 34
        val shanghaiNow = LocalDate.now(ZoneId.of("Asia/Shanghai"))
        val buildDateStr = System.getenv("APP_BUILD_DATE")
            ?: shanghaiNow.format(DateTimeFormatter.ofPattern("dd/MM/yyyy"))
        val todayIso = shanghaiNow.format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
        val gitDailySeq = try {
            val proc = ProcessBuilder("git", "log", "--since=$todayIso 00:00:00 +0800", "--oneline", "--", "android/")
                .directory(rootProject.file(".."))
                .redirectErrorStream(true)
                .start()
            val lines = proc.inputStream.bufferedReader().readLines().count { it.isNotBlank() }
            proc.waitFor()
            lines.coerceAtLeast(1)
        } catch (_: Throwable) { 1 }
        val minSeqForDate = if (todayIso == "2026-11-22") 2 else 1
        val dailySeq = (System.getenv("APP_DAILY_SEQ")?.toIntOrNull() ?: gitDailySeq).coerceAtLeast(minSeqForDate)
        val computedCode = (System.getenv("APP_VERSION_CODE")?.toIntOrNull()
            ?: (shanghaiNow.format(DateTimeFormatter.ofPattern("yyyyMMdd")).toInt() * 100 + (dailySeq % 100)))
        versionCode = computedCode
        versionName = "${dailySeq}.0 (v${buildDateStr})"
        buildConfigField("String", "APP_BUILD_DATE", "\"${buildDateStr}\"")
        buildConfigField("String", "APP_SHORT_VER", "\"${dailySeq}.0\"")

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    signingConfigs {
        create("release") {
            val ksFile = file(System.getenv("KEYSTORE_PATH") ?: "${rootDir}/htt_release.jks")
            val ksPass = System.getenv("KEYSTORE_PASSWORD") ?: "htt_kon_release_2026"
            val kAlias = System.getenv("KEY_ALIAS") ?: "htt_release_key"
            val kPass = System.getenv("KEY_PASSWORD") ?: "htt_kon_release_2026"
            if (!ksFile.exists()) {
                ksFile.parentFile?.mkdirs()
                val proc = ProcessBuilder(
                    "keytool", "-genkeypair", "-v",
                    "-keystore", ksFile.absolutePath,
                    "-storepass", ksPass,
                    "-keypass", kPass,
                    "-alias", kAlias,
                    "-keyalg", "RSA",
                    "-keysize", "2048",
                    "-storetype", "JKS",
                    "-validity", "7300",
                    "-dname", "CN=HTT-NaviCompanion, OU=HoKagoTeaTime, O=HTT, L=Shenzhen, S=Guangdong, C=CN"
                ).redirectErrorStream(true).start()
                proc.inputStream.bufferedReader().readText()
                proc.waitFor()
            }
            storeFile = ksFile
            storePassword = ksPass
            keyAlias = kAlias
            keyPassword = kPass
            // Force v1 (META-INF) + v2 + v3 signing for Mainland China OPPO / OnePlus ColorOS 14-16 compatibility!
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = false
            enableV4Signing = false
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    sourceSets {
        getByName("main") {
            assets.srcDirs("src/main/assets")
        }
    }
}

val sherpaAar = file("libs/sherpa-onnx-2.0.2.aar")
if (!sherpaAar.exists()) {
    sherpaAar.parentFile.mkdirs()
    val dlProc = ProcessBuilder(
        "curl", "-fSL", "-o", sherpaAar.absolutePath,
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.2/sherpa-onnx-2.0.2.aar"
    ).inheritIO().start()
    val rc = dlProc.waitFor()
    if (rc != 0) throw GradleException("Failed to download sherpa-onnx-2.0.2.aar (exit $rc)")
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.5")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.5")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.fragment:fragment-ktx:1.8.5")

    // Jetpack Compose
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    // Real Interactive Map (osmdroid - zero API key required, supports Amap & OSM tiles)
    implementation("org.osmdroid:osmdroid-android:6.1.20")

    // Location & Audio
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-ui:1.4.1")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

val syncSharedDatAssets by tasks.registering(Copy::class) {
    from(rootProject.file("../KOnNaviCompanion")) {
        include("mascot_assets.dat", "voice_assets.dat")
    }
    into(file("src/main/assets"))
}
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(syncSharedDatAssets)
}
