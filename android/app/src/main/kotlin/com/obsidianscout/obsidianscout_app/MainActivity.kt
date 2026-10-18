package com.obsidianscout.obsidianscout_app

import android.hardware.input.InputManager
import android.os.Handler
import android.view.KeyEvent
import android.view.MotionEvent
import com.obsidianscout.obsidianscout_app.widgets.WidgetAccessGate
import com.obsidianscout.obsidianscout_app.widgets.WidgetScheduler
import com.obsidianscout.obsidianscout_app.widgets.WidgetUpdater
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

class MainActivity : FlutterFragmentActivity(), GamepadsCompatibleActivity {
    private var keyListener: ((KeyEvent) -> Boolean)? = null
    private var motionListener: ((MotionEvent) -> Boolean)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Home-screen widgets: the app tells native code which widgets this user may have (lib/services/home_widget_service.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "obsidianscout/widgets").setMethodCallHandler { call, result ->
            when (call.method) {
                "applyAccess" -> {
                    @Suppress("UNCHECKED_CAST")
                    val widgets = (call.argument<Map<String, Any?>>("widgets") ?: emptyMap()).mapValues { it.value == true }
                    WidgetAccessGate.apply(applicationContext, widgets)
                    if (WidgetUpdater.anyPlaced(applicationContext)) {
                        WidgetScheduler.ensurePeriodic(applicationContext)
                        WidgetScheduler.armClock(applicationContext)
                        WidgetScheduler.armPoll(applicationContext)
                    } else {
                        WidgetScheduler.stopIfUnused(applicationContext)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchGenericMotionEvent(motionEvent: MotionEvent): Boolean {
        if (motionListener?.invoke(motionEvent) == true) {
            return true
        }
        return super.dispatchGenericMotionEvent(motionEvent)
    }

    override fun dispatchKeyEvent(keyEvent: KeyEvent): Boolean {
        // Let gamepads plugin process the key event; do not block system back navigation
        val handledByGamepad = if (keyEvent.keyCode != KeyEvent.KEYCODE_BACK) {
            keyListener?.invoke(keyEvent) == true
        } else {
            keyListener?.invoke(keyEvent)
            false
        }
        if (handledByGamepad) {
            return true
        }
        return super.dispatchKeyEvent(keyEvent)
    }

    override fun registerInputDeviceListener(listener: InputManager.InputDeviceListener, handler: Handler?) {
        val inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyListener = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionListener = handler
    }
}

