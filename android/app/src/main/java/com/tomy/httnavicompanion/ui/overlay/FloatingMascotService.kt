package com.tomy.httnavicompanion.ui.overlay

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
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
import android.widget.TextView
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.R
import com.tomy.httnavicompanion.audio.MascotActionState

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
        val btnIdle = floatView?.findViewById<TextView>(R.id.btn_float_idle)
        val btnWalk = floatView?.findViewById<TextView>(R.id.btn_float_walk)
        val btnDance = floatView?.findViewById<TextView>(R.id.btn_float_dance)
        val btnTea = floatView?.findViewById<TextView>(R.id.btn_float_tea)
        val btnClose = floatView?.findViewById<TextView>(R.id.btn_float_close)

        val mgr = HTTNaviApp.instance.audioPlayerManager

        btnIdle?.setOnClickListener {
            mgr.setMascotPose(MascotActionState.IDLE)
        }
        btnWalk?.setOnClickListener {
            mgr.setMascotPose(MascotActionState.WALK_RIGHT)
        }
        btnDance?.setOnClickListener {
            mgr.setMascotPose(MascotActionState.SPECIAL)
        }
        btnTea?.setOnClickListener {
            mgr.setMascotPose(MascotActionState.TEA_CAKE)
        }
        btnClose?.setOnClickListener {
            stopSelf()
        }

        val runnable = object : Runnable {
            override fun run() {
                val bmp = mgr.currentSpriteFrame.value
                if (bmp != null && ivMascot != null) {
                    ivMascot.setImageBitmap(bmp)
                }
                val curAct = mgr.mascotAction.value
                val gold = Color.parseColor("#FFE0B861")
                val cream = Color.parseColor("#FFFAF2E0")
                btnIdle?.setTextColor(if (curAct == MascotActionState.IDLE) gold else cream)
                btnWalk?.setTextColor(if (curAct == MascotActionState.WALK_LEFT || curAct == MascotActionState.WALK_RIGHT) gold else cream)
                btnDance?.setTextColor(if (curAct == MascotActionState.SPECIAL) gold else cream)
                btnTea?.setTextColor(if (curAct == MascotActionState.TEA_CAKE) gold else cream)

                if (curAct == MascotActionState.WALK_LEFT || curAct == MascotActionState.WALK_RIGHT) {
                    params.x = (params.x + if (curAct == MascotActionState.WALK_RIGHT) 3 else -3).coerceIn(20, 700)
                    try { windowManager?.updateViewLayout(floatView, params) } catch (_: Exception) {}
                }

                handler.postDelayed(this, 180L)
            }
        }
        updateRunnable = runnable
        handler.post(runnable)

        ivMascot?.setOnTouchListener(object : View.OnTouchListener {
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
                            mgr.triggerCharacterTap(null)
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
