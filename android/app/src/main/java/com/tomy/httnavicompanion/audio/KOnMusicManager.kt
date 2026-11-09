package com.tomy.httnavicompanion.audio

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class KOnTrack(val title: String, val artist: String, val filename: String)

class KOnMusicManager(private val context: Context) {
    val playlist = listOf(
        KOnTrack("Cagayake! GIRLS", "放課後ティータイム", "cagayake_girls.mp3"),
        KOnTrack("Don't say "lazy"", "放課後ティータイム", "dont_say_lazy.mp3"),
        KOnTrack("GO! GO! MANIAC", "放課後ティータイム", "go_go_maniac.mp3"),
        KOnTrack("Listen!!", "放課後ティータイム", "listen.mp3"),
        KOnTrack("NO,Thank You!", "放課後ティータイム", "no_thank_you.mp3"),
        KOnTrack("Utauyo!!MIRACLE", "放課後ティータイム", "utauyo_miracle.mp3"),
        KOnTrack("相遇天使 (天使にふれたよ!)", "放課後ティータイム", "tenshi_ni_fureta_yo.mp3")
    )

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying

    private val _currentTrack = MutableStateFlow(playlist[0])
    val currentTrack: StateFlow<KOnTrack> = _currentTrack

    fun togglePlayPause() {
        _isPlaying.value = !_isPlaying.value
    }

    fun nextTrack() {
        val curIdx = playlist.indexOf(_currentTrack.value)
        val nextIdx = (curIdx + 1) % playlist.size
        _currentTrack.value = playlist[nextIdx]
    }
}
