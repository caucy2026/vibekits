package com.vibekits.vibekits

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
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
import java.security.MessageDigest

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
        private const val CHANNEL = "vibekits_simulator"
        private const val NOTIFICATION_ID = 32148
        const val KEEP_ALIVE = "com.vibekits.vibekits.action.KEEP_SIMULATOR_ALIVE"
    }

    private val messenger = Messenger(IncomingHandler(Looper.getMainLooper()))

    override fun onCreate() {
        super.onCreate()
        FFI.init(this)
        val configDir = File(filesDir, "harness-transport").apply { mkdirs() }
        FFI.startHarnessServer(configDir.absolutePath, isTrustedKemiPad())
        Log.i(TAG, "VibeKits embedded Harness transport started")
    }

    private fun isTrustedKemiPad(): Boolean {
        if (!Build.MODEL.equals("huanglong", ignoreCase = true) ||
            !Build.MANUFACTURER.equals("HL2.0", ignoreCase = true)
        ) return false
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
        }
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners.orEmpty()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures.orEmpty()
        }
        val trustedDigest = "c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8"
        return signatures.any { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) } == trustedDigest
        }
    }

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != KEEP_ALIVE && intent != null) return START_NOT_STICKY
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL, "VibeKits 远程仿真", NotificationManager.IMPORTANCE_LOW,
        ))
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("VibeKits 远程仿真运行中")
            .setContentText("已授权的远程设备可连接")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // The native relay is deliberately isolated from the Flutter UI.
        // Android can recreate this started service after reclaiming its process.
        if (getSharedPreferences("simulator_service", MODE_PRIVATE)
                .getBoolean("enabled", false)) {
            FFI.harnessSetSimulatorAccess(true)
        }
        return START_STICKY
    }

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
                    HarnessRelayClient.STATUS -> response.putString("json",
                        JSONObject(FFI.harnessStatus())
                            // Native libraries may be loaded directly from APK without extraction.
                            .put("executable", applicationInfo.sourceDir)
                            .put("simulatorTargetSupported", true).toString())
                    HarnessRelayClient.SIMULATOR_ACCESS -> response.putBoolean(
                        "ok", FFI.harnessSetSimulatorAccess(request.getBoolean("enabled", false))
                            .also { accepted ->
                                if (accepted) getSharedPreferences("simulator_service", MODE_PRIVATE)
                                    .edit().putBoolean("enabled", request.getBoolean("enabled", false))
                                    .apply()
                            },
                    )
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
