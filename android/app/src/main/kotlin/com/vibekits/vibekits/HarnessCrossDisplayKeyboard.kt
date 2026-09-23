package com.vibekits.vibekits

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Display
import io.flutter.plugin.common.MethodChannel
import org.fcitx.fcitx5.android.common.ipc.IKBoardOverlayCallback
import org.fcitx.fcitx5.android.common.ipc.IKBoardOverlayService

/** KBoard draws on the physical opposite display; no Activity or virtual display is created. */
internal class HarnessCrossDisplayKeyboard(
    private val activity: MainActivity,
    private val channel: MethodChannel,
) {
    private val tag = "HarnessCrossDisplayKeyboard"
    private val handler = Handler(Looper.getMainLooper())
    private val serviceIntent = Intent("com.newlink.kemi.kboard.OVERLAY_IPC").setComponent(
        ComponentName(
            "com.newlink.kemi.kboard",
            "org.fcitx.fcitx5.android.input.overlay.KBoardOverlayService",
        ),
    )
    private var service: IKBoardOverlayService? = null
    private var bound = false
    private var requestId = 0L
    private var currentSession = ""
    private var active = false
    private var opening = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = IKBoardOverlayService.Stub.asInterface(binder)
            val sourceId = activity.display?.displayId ?: Display.DEFAULT_DISPLAY
            val target = targetDisplay() ?: return fail("display_removed")
            val id = requestId
            val session = currentSession
            try {
                if ((service?.capabilities ?: 0) and 1 == 0 ||
                    service?.show(
                        id, session, sourceId, target.displayId,
                        target.mode.physicalWidth, target.mode.physicalHeight,
                        (target.mode.physicalHeight * 0.52f).toInt().coerceAtLeast(360),
                        callback,
                    ) != true
                ) fail("show_rejected")
            } catch (error: Exception) {
                Log.e(tag, "KBoard show failed", error)
                fail("show_failed")
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) = fail("service_disconnected")
        override fun onBindingDied(name: ComponentName?) = fail("service_died")
        override fun onNullBinding(name: ComponentName?) = fail("service_unavailable")
    }

    private val callback = object : IKBoardOverlayCallback.Stub() {
        override fun onReady(id: Long, session: String?, displayId: Int) {
            handler.post {
                Log.i(tag, "ready request=$id display=$displayId matches=${id == requestId && session == currentSession} opening=$opening")
                if (id == requestId && session == currentSession && opening) {
                    opening = false
                    active = true
                    channel.invokeMethod("state", mapOf("state" to "visible"))
                }
            }
        }

        override fun onInput(
            id: Long, session: String?, operation: String?, text: String?,
            arg1: Int, arg2: Int, extras: Bundle?,
        ) {
            handler.post {
                if (id == requestId && session == currentSession && active) {
                    channel.invokeMethod("input", mapOf(
                        "operation" to operation.orEmpty(), "text" to text.orEmpty(),
                        "arg1" to arg1, "arg2" to arg2,
                    ), object : MethodChannel.Result {
                        override fun success(result: Any?) = Unit
                        override fun error(code: String, message: String?, details: Any?) {
                            Log.e(tag, "input delivery failed code=$code message=$message")
                        }
                        override fun notImplemented() {
                            Log.e(tag, "input delivery has no Dart handler")
                        }
                    })
                }
            }
        }

        override fun onClosed(id: Long, session: String?, reason: Int) {
            handler.post {
                if (id == requestId && session == currentSession) fail("closed_$reason")
            }
        }
    }

    private fun targetDisplay(): Display? {
        val manager = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val sourceId = activity.display?.displayId ?: Display.DEFAULT_DISPLAY
        return manager.displays.firstOrNull {
            it.displayId != sourceId && it.state == Display.STATE_ON &&
                it.mode.physicalWidth == 1920 && it.mode.physicalHeight == 1280
        }
    }

    fun available(): Boolean {
        val target = targetDisplay()
        val serviceFound = activity.packageManager.resolveService(serviceIntent, 0) != null
        Log.i(tag, "available target=${target?.displayId} service=$serviceFound")
        return target != null && serviceFound
    }

    fun open(): Boolean {
        Log.i(tag, "open requested active=$active opening=$opening")
        if (active || opening) return true
        if (!available()) return false
        requestId += 1
        currentSession = "vibekits-harness-composer-$requestId"
        opening = true
        channel.invokeMethod("state", mapOf("state" to "opening"))
        return try {
            bound = activity.applicationContext.bindService(
                serviceIntent, connection, Context.BIND_AUTO_CREATE,
            )
            if (!bound) fail("bind_failed")
            bound
        } catch (_: Exception) {
            fail("bind_failed")
            false
        }
    }

    fun close() {
        if (opening || active) {
            runCatching { service?.hide(requestId, currentSession) }
        }
        fail("closed")
    }

    private fun fail(reason: String) {
        Log.w(tag, "keyboard hidden reason=$reason")
        opening = false
        active = false
        service = null
        if (bound) {
            bound = false
            runCatching { activity.applicationContext.unbindService(connection) }
        }
        channel.invokeMethod("state", mapOf("state" to "hidden", "reason" to reason))
    }
}
