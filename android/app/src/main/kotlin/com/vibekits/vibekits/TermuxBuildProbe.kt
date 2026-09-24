package com.vibekits.vibekits

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger

/** Uses Termux's documented, user-granted RUN_COMMAND API; never runs caller text. */
internal class TermuxBuildProbe(context: Context) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    fun inspect(result: MethodChannel.Result) {
        Thread({
            val response = try {
                inspectBlocking()
            } catch (error: Exception) {
                mapOf<String, Any?>(
                    "installed" to null,
                    "permissionGranted" to false,
                    "commandsPresent" to false,
                    "reason" to (error.message ?: error.javaClass.simpleName),
                )
            }
            main.post { result.success(response) }
        }, "VibeKitsTermuxProbe").start()
    }

    private fun inspectBlocking(): Map<String, Any?> {
        val version = try {
            val info = app.packageManager.getPackageInfo("com.termux", 0)
            if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
            else @Suppress("DEPRECATION") info.versionCode.toLong()
        } catch (_: PackageManager.NameNotFoundException) {
            return mapOf("installed" to false, "permissionGranted" to false,
                "commandsPresent" to false, "reason" to "Termux 未安装")
        }
        val permission = app.checkSelfPermission("com.termux.permission.RUN_COMMAND") ==
            PackageManager.PERMISSION_GRANTED
        if (!permission) {
            return mapOf("installed" to true, "versionCode" to version,
                "permissionGranted" to false, "commandsPresent" to false,
                "reason" to "请在 Android 应用权限中允许 VibeKits 运行 Termux 命令")
        }
        val id = nextId.incrementAndGet()
        val completion = TermuxProbeReceiver.register(id)
        val callback = Intent(app, TermuxProbeReceiver::class.java).putExtra("probeId", id)
        val flags = PendingIntent.FLAG_ONE_SHOT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        val pendingIntent = PendingIntent.getBroadcast(app, id, callback, flags)
        val probe = Intent().setClassName("com.termux", "com.termux.app.RunCommandService")
            .setAction("com.termux.RUN_COMMAND")
            .putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/sh")
            .putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf(
                "-c",
                "for tool in aapt javac dx apksigner; do command -v \"\$tool\" >/dev/null || exit 20; done; printf VIBEKITS_TOOLCHAIN_PRESENT",
            ))
            .putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home")
            .putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            .putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pendingIntent)
        try {
            app.startService(probe) ?: error("Termux 命令服务不可用")
            val bundle = try {
                completion.get(15, TimeUnit.SECONDS)
            } catch (_: TimeoutException) {
                return mapOf("installed" to true, "versionCode" to version,
                    "permissionGranted" to true, "commandsPresent" to false,
                    "reason" to "Termux 未在 15 秒内返回；检查 allow-external-apps 或后台限制")
            }
            val exit = bundle?.getInt("exitCode", -1) ?: -1
            val stdout = bundle?.getString("stdout", "") ?: ""
            val present = exit == 0 && stdout.contains("VIBEKITS_TOOLCHAIN_PRESENT")
            return mapOf("installed" to true, "versionCode" to version,
                "permissionGranted" to true, "commandsPresent" to present,
                "reason" to if (present) "工具命令存在，仍需原生 APK 构建验收"
                    else (bundle?.getString("errmsg")?.takeIf { it.isNotBlank() }
                        ?: if (exit == 20) "Termux 缺少 aapt、javac、dx 或 apksigner"
                        else "Termux 外部命令不可用；检查 allow-external-apps 与工具链"))
        } finally {
            TermuxProbeReceiver.forget(id)
            pendingIntent.cancel()
        }
    }

    companion object {
        private val nextId = AtomicInteger(1000)
    }
}
