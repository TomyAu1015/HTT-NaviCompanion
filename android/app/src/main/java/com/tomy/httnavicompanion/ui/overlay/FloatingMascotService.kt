package com.tomy.httnavicompanion.ui.overlay

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.R

class FloatingMascotService : Service() {
    private var windowManager: WindowManager? = null
    private var floatView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var updateRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        setupFloatingWindow()
    }

    private fun setupFloatingWindow() {
        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 120
            y = 220
        }

        floatView = LayoutInflater.from(this).inflate(R.layout.layout_floating_mascot, null)
        val ivMascot = floatView?.findViewById<ImageView>(R.id.iv_floating_mascot)

        val runnable = object : Runnable {
            override fun run() {
                val bmp = HTTNaviApp.instance.audioPlayerManager.currentSpriteFrame.value
                if (bmp != null && ivMascot != null) {
                    ivMascot.setImageBitmap(bmp)
                }
                handler.postDelayed(this, 160L)
            }
        }
        updateRunnable = runnable
        handler.post(runnable)

        floatView?.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isMoved = false

            override fun onTouch(v: View?, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isMoved = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        if (kotlin.math.abs(dx) > 6 || kotlin.math.abs(dy) > 6) {
                            isMoved = true
                        }
                        params.x = initialX + dx
                        params.y = initialY + dy
                        windowManager?.updateViewLayout(floatView, params)
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isMoved) {
                            HTTNaviApp.instance.audioPlayerManager.triggerCharacterTap(null)
                        }
                        return true
                    }
                }
                return false
            }
        })

        try {
            windowManager?.addView(floatView, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        updateRunnable?.let { handler.removeCallbacks(it) }
        if (floatView != null) {
            windowManager?.removeView(floatView)
        }
    }
}
