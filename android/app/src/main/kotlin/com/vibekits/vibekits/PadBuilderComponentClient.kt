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
import com.vibekits.vibekits.component.builder.IBuilderRuntime
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Same-signer Binder transport; the agent cannot pass shell text to the builder. */
internal class PadBuilderComponentClient(context: Context) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val componentPackage = "com.vibekits.vibekits.component.builder"
    private val serviceClass = "$componentPackage.BuilderRuntimeService"
    private val taskIdPattern = Regex("[A-Za-z0-9_-]{1,64}")
    private val packagePattern = Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+")
    fun handle(
        method: String,
        sourceDirectory: String?,
        workspaceRoot: String?,
        expectedPackage: String?,
        taskId: String?,
        result: MethodChannel.Result,
    ) {
        Thread({
            val response = try {
                verifyPackage()
                withService { service ->
                    when (method) {
                        "componentStatus" -> payload(service.getRuntimeStatus())
                        "startBuild" -> start(service, sourceDirectory, workspaceRoot,
                            expectedPackage, taskId)
                        "buildStatus" -> status(service, taskId)
                        "prepareInstall" -> prepareInstall(service, taskId)
                        "cancelBuild" -> {
                            require(taskId != null && taskIdPattern.matches(taskId)) { "任务 ID 无效" }
                            service.cancelBuild(taskId)
                            payload(service.getBuildStatus(taskId))
                        }
                        else -> throw IllegalArgumentException("未知 PAD 编译组件操作")
                    }
                }
            } catch (error: Exception) {
                mapOf("available" to false, "buildReady" to false,
                    "error" to (error.message ?: error.javaClass.simpleName))
            }
            main.post { result.success(response) }
        }, "VibeKitsPadBuilderClient").start()
    }

    private fun start(
        service: IBuilderRuntime,
        sourceDirectory: String?,
        workspaceRoot: String?,
        expectedPackage: String?,
        taskId: String?,
    ): Map<String, Any?> {
        require(taskId != null && taskIdPattern.matches(taskId)) { "任务 ID 无效" }
        require(expectedPackage != null && packagePattern.matches(expectedPackage)) { "APK 包名无效" }
        require(!workspaceRoot.isNullOrBlank()) { "PAD Harness 工作区无效" }
        val workspace = File(workspaceRoot).canonicalFile
        val source = File(sourceDirectory ?: "").canonicalFile
        require(workspace.isDirectory && source.isDirectory &&
            (source == workspace || source.path.startsWith(workspace.path + File.separator))) {
            "源码必须位于 PAD Harness 工作区"
        }
        val manifest = File(source, "app/src/main/AndroidManifest.xml")
        require(manifest.isFile) { "缺少 app/src/main/AndroidManifest.xml" }
        val sourceZip = File(app.cacheDir, "pad-builder/$taskId.zip")
        sourceZip.parentFile?.mkdirs()
        zipSource(source, sourceZip)
        val output = artifact(taskId)
        output.parentFile?.mkdirs()
        val answer = ParcelFileDescriptor.open(sourceZip, ParcelFileDescriptor.MODE_READ_ONLY).use { input ->
            ParcelFileDescriptor.open(output, ParcelFileDescriptor.MODE_CREATE or
                ParcelFileDescriptor.MODE_TRUNCATE or ParcelFileDescriptor.MODE_WRITE_ONLY).use { sink ->
                service.startBuild(taskId, expectedPackage, input, sink)
            }
        }
        val parsed = JSONObject(answer)
        if (!parsed.optBoolean("accepted")) output.delete()
        return mapOf("available" to true, "accepted" to parsed.optBoolean("accepted"),
            "taskId" to taskId, "error" to parsed.optString("error"))
    }

    private fun status(service: IBuilderRuntime, taskId: String?): Map<String, Any?> {
        require(taskId != null && taskIdPattern.matches(taskId)) { "任务 ID 无效" }
        val parsed = JSONObject(service.getBuildStatus(taskId))
        val response = payload(parsed.toString()).toMutableMap()
        if (parsed.optString("state") == "completed") {
            val output = artifact(taskId)
            val expectedSha = parsed.optString("sha256")
            val expectedBytes = parsed.optLong("bytes")
            val actualSha = if (output.isFile) sha256(output) else ""
            val archive = if (output.isFile) app.packageManager.getPackageArchiveInfo(
                output.absolutePath, 0) else null
            val matches = actualSha.isNotEmpty() && actualSha == expectedSha &&
                output.length() == expectedBytes && archive?.packageName == parsed.optString("packageName")
            response["verified"] = matches
            response["artifactPath"] = if (matches) output.absolutePath else null
            response["actualSha256"] = actualSha
            response["actualPackageName"] = archive?.packageName
        }
        return response
    }

    private fun prepareInstall(service: IBuilderRuntime, taskId: String?): Map<String, Any?> {
        val checked = status(service, taskId)
        require(checked["verified"] == true) { "PAD 编译产物尚未通过包名、大小与 SHA-256 核验" }
        val source = artifact(taskId!!)
        val target = File(app.cacheDir, "pad-builder-install/$taskId.apk")
        target.parentFile?.mkdirs()
        source.copyTo(target, overwrite = true)
        require(sha256(target) == checked["actualSha256"]) { "安装缓存中的 APK 校验失败" }
        return mapOf("available" to true, "verified" to true,
            "path" to target.absolutePath, "packageName" to checked["actualPackageName"])
    }

    private fun zipSource(source: File, archive: File) {
        val main = File(source, "app/src/main").canonicalFile
        require(main.isDirectory) { "缺少 app/src/main" }
        var entries = 0
        var bytes = 0L
        ZipOutputStream(FileOutputStream(archive)).use { zip ->
            main.walkTopDown().filter { it.isFile }.forEach { file ->
                val canonical = file.canonicalFile
                require(canonical.path.startsWith(main.path + File.separator)) { "源码包含越界链接" }
                require(++entries <= 1500) { "源码文件过多" }
                bytes += file.length()
                require(bytes <= 50L * 1024 * 1024) { "源码归档超过 50 MB" }
                val relative = file.relativeTo(source).invariantSeparatorsPath
                zip.putNextEntry(ZipEntry(relative))
                FileInputStream(file).use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
    }

    private fun artifact(taskId: String) = File(app.filesDir, "Vibekits/builds/$taskId.apk")

    private fun payload(json: String): Map<String, Any?> {
        val parsed = JSONObject(json)
        return mapOf(
            "available" to true,
            "state" to parsed.optString("state"),
            "buildReady" to parsed.optBoolean("buildReady"),
            "taskId" to parsed.optString("taskId"),
            "packageName" to parsed.optString("packageName"),
            "step" to parsed.optString("step"),
            "log" to parsed.optString("log"),
            "error" to parsed.optString("error"),
            "bytes" to parsed.optLong("bytes"),
            "sha256" to parsed.optString("sha256"),
            "toolchainSha256" to parsed.optString("toolchainSha256"),
        )
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun verifyPackage() {
        require(Build.SUPPORTED_ABIS.contains("arm64-v8a")) { "PAD 编译组件只支持 arm64" }
        val flags = if (Build.VERSION.SDK_INT >= 28)
            PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val component = app.packageManager.getPackageInfo(componentPackage, flags)
        require(component.longVersionCode >= 1L) { "PAD 编译组件版本无效" }
        val host = app.packageManager.getPackageInfo(app.packageName, flags)
        val a = if (Build.VERSION.SDK_INT >= 28)
            component.signingInfo?.apkContentsSigners.orEmpty() else component.signatures.orEmpty()
        val b = if (Build.VERSION.SDK_INT >= 28)
            host.signingInfo?.apkContentsSigners.orEmpty() else host.signatures.orEmpty()
        require(a.size == 1 && b.size == 1 &&
            a[0].toByteArray().contentEquals(b[0].toByteArray())) {
            "PAD 编译组件与 VibeKits 签名不一致"
        }
    }

    private fun <T> withService(action: (IBuilderRuntime) -> T): T {
        val latch = CountDownLatch(1)
        val runtime = AtomicReference<IBuilderRuntime?>()
        val current = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                runtime.set(IBuilderRuntime.Stub.asInterface(binder))
                latch.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName?) { runtime.set(null) }
        }
        val intent = Intent().setClassName(componentPackage, serviceClass)
        check(app.bindService(intent, current, Context.BIND_AUTO_CREATE)) { "PAD 编译服务不可用" }
        try {
            check(latch.await(8, TimeUnit.SECONDS)) { "PAD 编译服务连接超时" }
            return action(checkNotNull(runtime.get()) { "PAD 编译服务已断开" })
        } finally {
            app.unbindService(current)
        }
    }

    fun close() = Unit
}
