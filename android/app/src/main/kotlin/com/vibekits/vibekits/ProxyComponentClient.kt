package com.vibekits.vibekits

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.caucy.vibekits.component.network_proxy.IProxyRuntime
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Talks only to the installed, same-signer proxy APK over signature-protected Binder. */
internal class ProxyComponentClient(private val context: Context) {
    private val componentPackage = "com.caucy.vibekits.component.network_proxy"
    private val serviceClass = "$componentPackage.ProxyRuntimeService"
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var runtime: IProxyRuntime? = null
    private var connection: ServiceConnection? = null

    fun handle(method: String, configPath: String?, result: MethodChannel.Result) {
        Thread({
            try {
                val response: Map<String, Any?> = when (method) {
                    "inspect" -> {
                        verifyPackage()
                        val service = connect()
                        mapOf("available" to true, "version" to service.version(),
                            "running" to service.running())
                    }
                    "start" -> {
                        verifyPackage()
                        val file = File(configPath ?: "").canonicalFile
                        val files = context.filesDir.canonicalFile
                        require(file.isFile && file.path.startsWith(files.path + File.separator)) {
                            "代理配置必须在应用私有目录"
                        }
                        val intent = serviceIntent()
                        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                        else context.startService(intent)
                        val service = connect()
                        val started = ParcelFileDescriptor.open(file,
                            ParcelFileDescriptor.MODE_READ_ONLY).use { service.start(it) }
                        if (!started) service.stop()
                        mapOf("available" to true, "running" to started,
                            "message" to if (started) "Mihomo 已启动" else "Mihomo 配置无效或启动失败")
                    }
                    "stop" -> {
                        verifyPackage()
                        connect().stop()
                        mapOf("available" to true, "running" to false)
                    }
                    else -> throw IllegalArgumentException("未知代理组件操作")
                }
                main.post { result.success(response) }
            } catch (error: Exception) {
                val reason = error.message ?: error.javaClass.simpleName
                main.post { result.success(mapOf("available" to false,
                    "running" to false, "message" to reason)) }
            }
        }, "VibeKitsProxyComponent").start()
    }

    private fun serviceIntent() = Intent().setClassName(componentPackage, serviceClass)

    private fun verifyPackage() {
        require(Build.SUPPORTED_ABIS.contains("arm64-v8a")) { "代理组件只支持 Android arm64" }
        val flags = if (Build.VERSION.SDK_INT >= 28)
            PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val component = context.packageManager.getPackageInfo(componentPackage, flags)
        require(component.longVersionCode >= 1L) { "代理组件版本无效" }
        val host = context.packageManager.getPackageInfo(context.packageName, flags)
        val componentSigners = if (Build.VERSION.SDK_INT >= 28)
            component.signingInfo?.apkContentsSigners.orEmpty() else component.signatures.orEmpty()
        val hostSigners = if (Build.VERSION.SDK_INT >= 28)
            host.signingInfo?.apkContentsSigners.orEmpty() else host.signatures.orEmpty()
        require(componentSigners.size == 1 && hostSigners.size == 1 &&
            componentSigners[0].toByteArray().contentEquals(hostSigners[0].toByteArray())) {
            "代理组件与 VibeKits 签名不一致"
        }
    }

    @Synchronized private fun connect(): IProxyRuntime {
        runtime?.let { return it }
        val latch = CountDownLatch(1)
        val current = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                runtime = IProxyRuntime.Stub.asInterface(binder)
                latch.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName?) { runtime = null }
        }
        check(context.bindService(serviceIntent(), current, Context.BIND_AUTO_CREATE)) {
            "代理组件服务不可用"
        }
        connection = current
        check(latch.await(8, TimeUnit.SECONDS) && runtime != null) {
            "代理组件连接超时"
        }
        return runtime!!
    }

    fun close() {
        val current = connection ?: return
        connection = null
        runtime = null
        context.unbindService(current)
    }
}
