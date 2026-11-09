package com.tomy.httnavicompanion

import android.app.Application
import com.tomy.httnavicompanion.data.AssetDecryptor
import com.tomy.httnavicompanion.audio.AudioPlayerManager
import com.tomy.httnavicompanion.audio.KOnMusicManager

class HTTNaviApp : Application() {
    lateinit var assetDecryptor: AssetDecryptor
        private set
    lateinit var audioPlayerManager: AudioPlayerManager
        private set
    lateinit var musicManager: KOnMusicManager
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this

        assetDecryptor = AssetDecryptor(this)
        audioPlayerManager = AudioPlayerManager(this, assetDecryptor)
        musicManager = KOnMusicManager(this)

        // Initialize assets asynchronously
        Thread {
            assetDecryptor.initAssets()
            audioPlayerManager.initVoicePackage()
        }.start()
    }

    companion object {
        lateinit var instance: HTTNaviApp
            private set
    }
}
