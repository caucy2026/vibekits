package com.vibekits.vibekits

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Starts only the small simulator service after boot when explicitly enabled. */
class PadSimulatorBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!context.getSharedPreferences("simulator_service", Context.MODE_PRIVATE)
                .getBoolean("enabled", false)) return
        val service = Intent(context, HarnessRelayService::class.java)
            .setAction(HarnessRelayService.KEEP_ALIVE)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service)
        else context.startService(service)
    }
}
