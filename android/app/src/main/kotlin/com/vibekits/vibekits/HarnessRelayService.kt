package com.vibekits.vibekits

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.util.Log
import androidx.annotation.Keep
import ffi.FFI
import org.json.JSONObject
import java.io.File

/**
 * VibeKits-owned rendezvous/P2P/HBBR transport process.
 *
 * Only the closed Harness message API below is exposed to the main process.
 * There is no screen, input, clipboard, file-transfer, terminal or generic
 * port-forward operation, and no separately installed RustDesk application is
 * consulted at runtime.
 */
class HarnessRelayService : Service() {
    companion object {
        private const val TAG = "VibeHarnessTransport"
        private const val RESULT = 100
    }

    private val messenger = Messenger(IncomingHandler(Looper.getMainLooper()))

    override fun onCreate() {
        super.onCreate()
        FFI.init(this)
        val configDir = File(filesDir, "harness-transport").apply { mkdirs() }
        FFI.startHarnessServer(configDir.absolutePath)
        Log.i(TAG, "VibeKits embedded Harness transport started")
    }

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onDestroy() {
        Log.i(TAG, "VibeKits embedded Harness transport stopping")
        super.onDestroy()
        // The Rust rendezvous worker is process-scoped. This service is the
        // only component in its private process, so process exit is a bounded
        // close of every transport socket without touching the Flutter UI.
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    @Keep
    fun rustGetByName(name: String): String = ""

    @Keep
    fun rustSetByName(name: String, arg1: String, arg2: String) {
        if (name == "add_connection") {
            Log.i(TAG, "connection=${redactConnection(arg1)}")
        }
    }

    private fun redactConnection(raw: String): String = try {
        val json = JSONObject(raw)
        JSONObject()
            .put("id", json.optInt("id"))
            .put("peer_id", json.optString("peer_id"))
            .put("authorized", json.optBoolean("authorized"))
            .put("port_forward", json.optString("port_forward"))
            .toString()
    } catch (_: Exception) {
        "invalid"
    }

    private inner class IncomingHandler(looper: Looper) : Handler(looper) {
        override fun handleMessage(message: Message) {
            val reply = message.replyTo ?: return
            val request = message.data ?: Bundle.EMPTY
            val response = Bundle()
            var stopAfterReply = false
            try {
                when (message.what) {
                    HarnessRelayClient.STATUS -> response.putString("json", FFI.harnessStatus())
                    HarnessRelayClient.CONNECTIONS -> response.putString("json", FFI.harnessConnections())
                    HarnessRelayClient.AUTHORIZE -> response.putBoolean(
                        "ok",
                        FFI.harnessAuthorize(request.getInt("connectionId", -1)),
                    )
                    HarnessRelayClient.REJECT -> response.putBoolean(
                        "ok",
                        FFI.harnessReject(request.getInt("connectionId", -1)),
                    )
                    HarnessRelayClient.OPEN_TUNNEL -> response.putString(
                        "json",
                        FFI.harnessOpenTunnel(
                            request.getString("routingId").orEmpty(),
                            request.getInt("localPort", -1),
                            request.getInt("remotePort", -1),
                            request.getBoolean("forceRelay", false),
                        ),
                    )
                    HarnessRelayClient.CLOSE_TUNNEL -> response.putBoolean(
                        "ok",
                        FFI.harnessCloseTunnel(request.getInt("localPort", -1)),
                    )
                    HarnessRelayClient.STOP -> {
                        response.putBoolean("ok", true)
                        stopAfterReply = true
                    }
                    else -> response.putString("error", "unsupported_operation")
                }
            } catch (error: Throwable) {
                Log.e(TAG, "embedded Harness transport request failed", error)
                response.putString("error", "native_operation_failed")
            }
            Message.obtain(null, RESULT).apply {
                arg1 = message.arg1
                data = response
                reply.send(this)
            }
            if (stopAfterReply) post { stopSelf() }
        }
    }
}
