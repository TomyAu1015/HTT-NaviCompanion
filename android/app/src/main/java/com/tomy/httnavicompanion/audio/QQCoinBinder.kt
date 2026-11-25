package com.tomy.httnavicompanion.audio

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

object QQCoinBinder {
    private const val PREFS = "htt_qq_coins"
    private val _qqUid = MutableStateFlow("")
    val qqUid: StateFlow<String> = _qqUid
    private val _qqToken = MutableStateFlow("")
    val qqToken: StateFlow<String> = _qqToken
    private val _coins = MutableStateFlow(0)
    val coins: StateFlow<Int> = _coins
    private val _coinAnte = MutableStateFlow(10)
    val coinAnte: StateFlow<Int> = _coinAnte
    private val _status = MutableStateFlow("")
    val status: StateFlow<String> = _status

    val token: String get() = _qqToken.value
    val isBound: Boolean get() = _qqToken.value.isNotEmpty() && _qqUid.value.isNotEmpty()

    fun init(context: Context) {
        val sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        _qqUid.value = sp.getString("qq", "") ?: ""
        _qqToken.value = sp.getString("token", "") ?: ""
        _coins.value = sp.getInt("coins", 0)
        _coinAnte.value = sp.getInt("ante", 10)
    }

    private fun save(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("qq", _qqUid.value)
            .putString("token", _qqToken.value)
            .putInt("coins", _coins.value)
            .putInt("ante", _coinAnte.value)
            .apply()
    }

    fun setAnte(context: Context, amt: Int) {
        _coinAnte.value = amt
        save(context)
    }

    fun unbind(context: Context) {
        _qqUid.value = ""; _qqToken.value = ""; _coins.value = 0; _status.value = "已解除绑定"
        save(context)
    }

    suspend fun requestCode(qq: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val conn = (URL("https://azusa.online/club/bind_code").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8000; readTimeout = 8000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            conn.outputStream.use { it.write(JSONObject().put("qq", qq.trim()).toString().toByteArray()) }
            val text = (if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText().orEmpty()
            val obj = JSONObject(text.ifEmpty { "{}" })
            val ok = obj.optBoolean("ok", false)
            _status.value = if (ok) "✅ 验证码已通过群机器人私聊发送" else "⚠️ " + obj.optString("error", "发送失败")
            ok
        } catch (e: Exception) {
            _status.value = "⚠️ 网络失败：${e.message}"
            false
        }
    }

    suspend fun verifyCode(context: Context, qq: String, code: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val conn = (URL("https://azusa.online/club/bind_verify").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8000; readTimeout = 8000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            conn.outputStream.use { it.write(JSONObject().put("qq", qq.trim()).put("code", code.trim()).toString().toByteArray()) }
            val text = (if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText().orEmpty()
            val obj = JSONObject(text.ifEmpty { "{}" })
            if (obj.optBoolean("ok", false)) {
                _qqUid.value = qq.trim()
                _qqToken.value = obj.optString("token", "")
                _coins.value = obj.optInt("coins", 0)
                _status.value = "🎉 绑定成功！当前群金币：${_coins.value}"
                save(context)
                true
            } else {
                _status.value = "⚠️ " + obj.optString("error", "验证码错误")
                false
            }
        } catch (e: Exception) {
            _status.value = "⚠️ 验证失败：${e.message}"
            false
        }
    }

    suspend fun refreshCoins(context: Context) = withContext(Dispatchers.IO) {
        if (_qqToken.value.isEmpty()) return@withContext
        try {
            val enc = URLEncoder.encode(_qqToken.value, "UTF-8")
            val conn = (URL("https://azusa.online/club/coins?token=$enc").openConnection() as HttpURLConnection).apply {
                connectTimeout = 6000; readTimeout = 6000
            }
            val text = conn.inputStream.bufferedReader().readText()
            val obj = JSONObject(text)
            if (obj.optBoolean("ok", false)) {
                _coins.value = obj.optInt("coins", _coins.value)
                save(context)
            }
        } catch (_: Exception) {}
    }
}
