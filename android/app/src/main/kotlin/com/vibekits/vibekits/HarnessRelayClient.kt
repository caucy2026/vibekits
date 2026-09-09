package com.vibekits.vibekits

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicLong

/** Client for VibeKits' own isolated, text-only Harness transport process. */
class HarnessRelayClient(private val context: Context) {
    companion object {
        const val STATUS = 1
        const val CONNECTIONS = 2
        const val AUTHORIZE = 3
        const val REJECT = 4
        const val OPEN_TUNNEL = 5
        const val CLOSE_TUNNEL = 6
        const val STOP = 7
        private const val RESULT = 100
    }

    private data class Pending(
        val what: Int,
        val values: Map<String, Any>,
        val result: MethodChannel.Result,
    )

    private val handler = Handler(Looper.getMainLooper())
    private val sequence = AtomicLong()
    private val awaiting = mutableMapOf<Long, MethodChannel.Result>()
    private val queued = ArrayDeque<Pending>()
    private var remote: Messenger? = null
    private var binding = false
    private var bound = false
    private val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what != RESULT) return@Handler false
        val id = message.arg1.toLong() and 0xffffffffL
        val result = awaiting.remove(id) ?: return@Handler true
        handler.removeCallbacksAndMessages(result)
        val error = message.data.getString("error")
        if (error != null) result.error("HARNESS_RELAY_ERROR", error, null)
        else result.success(bundleToMap(message.data))
        true
    })

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            binding = false
            bound = true
            remote = binder?.let(::Messenger)
            while (queued.isNotEmpty()) send(queued.removeFirst())
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            remote = null
            bound = false
        }
    }

    fun request(what: Int, values: Map<String, Any>, result: MethodChannel.Result) {
        val pending = Pending(what, values, result)
        if (remote != null) {
            send(pending)
            return
        }
        queued.addLast(pending)
        if (binding) return
        binding = true
        val ok = try {
            context.bindService(
                Intent(context, HarnessRelayService::class.java),
                connection,
                Context.BIND_AUTO_CREATE,
            )
        } catch (error: SecurityException) {
            false
        }
        if (!ok) {
            binding = false
            failQueued("VibeKits 内置远程消息引擎启动失败")
        }
    }

    private fun send(pending: Pending) {
        val remote = remote
        if (remote == null) {
            queued.addFirst(pending)
            return
        }
        val id = sequence.incrementAndGet() and 0x7fffffff
        val data = Bundle()
        pending.values.forEach { (key, value) ->
            when (value) {
                is String -> data.putString(key, value)
                is Int -> data.putInt(key, value)
                is Boolean -> data.putBoolean(key, value)
            }
        }
        awaiting[id] = pending.result
        val timeout = Runnable {
            awaiting.remove(id)?.error("HARNESS_RELAY_TIMEOUT", "远程协助服务响应超时", null)
        }
        handler.postAtTime(timeout, pending.result, android.os.SystemClock.uptimeMillis() + 8_000)
        try {
            remote.send(Message.obtain(null, pending.what).apply {
                arg1 = id.toInt()
                replyTo = replies
                this.data = data
            })
        } catch (error: RemoteException) {
            handler.removeCallbacksAndMessages(pending.result)
            awaiting.remove(id)
            pending.result.error("HARNESS_RELAY_DISCONNECTED", error.message, null)
        }
    }

    fun close() {
        if (bound) context.unbindService(connection)
        bound = false
        binding = false
        remote = null
        failQueued("远程协助界面已关闭")
        awaiting.values.forEach {
            handler.removeCallbacksAndMessages(it)
            it.error("HARNESS_RELAY_CLOSED", "远程协助界面已关闭", null)
        }
        awaiting.clear()
    }

    private fun failQueued(message: String) {
        while (queued.isNotEmpty()) {
            queued.removeFirst().result.error("HARNESS_RELAY_UNAVAILABLE", message, null)
        }
    }

    private fun bundleToMap(bundle: Bundle): Map<String, Any?> =
        bundle.keySet().associateWith { bundle.get(it) }
}
