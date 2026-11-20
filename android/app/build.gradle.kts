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
        versionCode = 2
        versionName = "1.6.3"

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
                    "-validity", "10000",
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
            enableV3Signing = true
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
    }

    sourceSets {
        getByName("main") {
            assets.srcDirs("src/main/assets")
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.5")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.5")
    implementation("androidx.activity:activity-compose:1.9.2")

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

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
