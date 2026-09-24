package com.vibekits.vibekits

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/** Installs the tiny, platform-signed system-UID companion only when needed. */
internal object RemoteAdbBootstrap {
    const val helperPackage = "com.vibekits.vibekits.component.adb"
    private val callbacks = ConcurrentHashMap<Int, (Boolean, String) -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    fun installed(context: Context, minimumVersion: Long = 2L): Boolean = try {
        val packageInfo = context.packageManager.getPackageInfo(helperPackage, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode >= minimumVersion
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong() >= minimumVersion
        }
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    fun installBundled(context: Context, callback: (Boolean, String) -> Unit) {
        Thread({
            try {
                val apk = File(context.cacheDir, "vibekits-adb-helper.apk")
                context.assets.open("vibekits-adb-helper.apk").use { input ->
                    apk.outputStream().use { output -> input.copyTo(output) }
                }
                val manager = context.packageManager
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    @Suppress("DEPRECATION")
                    PackageManager.GET_SIGNATURES
                }
                val archive = manager.getPackageArchiveInfo(apk.path, flags)
                    ?: error("Bundled ADB helper is unreadable")
                require(archive.packageName == helperPackage) { "Wrong ADB helper package" }
                val host = manager.getPackageInfo(context.packageName, flags)
                val hostSigners = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    host.signingInfo?.apkContentsSigners.orEmpty()
                } else {
                    @Suppress("DEPRECATION")
                    host.signatures.orEmpty()
                }
                val helperSigners = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    archive.signingInfo?.apkContentsSigners.orEmpty()
                } else {
                    @Suppress("DEPRECATION")
                    archive.signatures.orEmpty()
                }
                require(hostSigners.size == 1 && helperSigners.size == 1 &&
                    hostSigners[0].toByteArray().contentEquals(helperSigners[0].toByteArray())) {
                    "ADB helper signer differs from VibeKits"
                }
                val installer = manager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                ).apply {
                    setAppPackageName(helperPackage)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                    }
                }
                val sessionId = installer.createSession(params)
                callbacks[sessionId] = callback
                installer.openSession(sessionId).use { session ->
                    session.openWrite("adb-helper.apk", 0, apk.length()).use { output ->
                        apk.inputStream().use { it.copyTo(output) }
                        session.fsync(output)
                    }
                    val intent = Intent(context, RemoteAdbInstallReceiver::class.java)
                        .putExtra("sessionId", sessionId)
                    val sender = PendingIntent.getBroadcast(
                        context, sessionId, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                    )
                    session.commit(sender.intentSender)
                }
            } catch (error: Exception) {
                main.post { callback(false, error.message ?: error.javaClass.simpleName) }
            }
        }, "VibeKitsAdbHelperInstall").start()
    }

    fun onInstallResult(intent: Intent) {
        val sessionId = intent.getIntExtra("sessionId", -1)
        val callback = callbacks.remove(sessionId) ?: return
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE
        )
        callback(
            status == PackageInstaller.STATUS_SUCCESS,
            intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                ?: "ADB helper install status $status",
        )
    }
}

class RemoteAdbInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RemoteAdbBootstrap.onInstallResult(intent)
    }
}
