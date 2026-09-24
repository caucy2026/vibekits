package com.vibekits.vibekits

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap

/** Receives only the one-shot result of a VibeKits-initiated Termux probe. */
class TermuxProbeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("probeId", -1)
        if (id < 0) return
        val pending = callbacks.remove(id) ?: return
        pending.complete(intent.getBundleExtra("result"))
    }

    companion object {
        private val callbacks = ConcurrentHashMap<Int, CompletableFuture<Bundle?>>()

        internal fun register(id: Int): CompletableFuture<Bundle?> {
            val pending = CompletableFuture<Bundle?>()
            check(callbacks.putIfAbsent(id, pending) == null) { "Termux probe ID collision" }
            return pending
        }

        internal fun forget(id: Int) {
            callbacks.remove(id)
        }
    }
}
