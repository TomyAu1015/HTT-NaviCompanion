package com.tomy.httnavicompanion

import android.app.Application
import android.util.Log
import com.tomy.httnavicompanion.data.AssetDecryptor
import com.tomy.httnavicompanion.audio.AudioPlayerManager
import com.tomy.httnavicompanion.audio.KOnMusicManager
import com.tomy.httnavicompanion.audio.LocalLLMManager

class HTTNaviApp : Application() {
    lateinit var assetDecryptor: AssetDecryptor
        private set
    lateinit var audioPlayerManager: AudioPlayerManager
        private set
    lateinit var musicManager: KOnMusicManager
        private set
    lateinit var localLLMManager: LocalLLMManager
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this

        assetDecryptor = AssetDecryptor(this)
        audioPlayerManager = AudioPlayerManager(this, assetDecryptor)
        musicManager = KOnMusicManager(this)
        localLLMManager = LocalLLMManager(this, audioPlayerManager, musicManager)

        // Initialize assets asynchronously with crash guard
        Thread {
            try {
                assetDecryptor.initAssets()
                audioPlayerManager.initVoicePackage()
            } catch (t: Throwable) {
                Log.e("HTTNaviApp", "Asset init error", t)
            }
        }.start()
    }

    companion object {
        lateinit var instance: HTTNaviApp
            private set
    }
}
