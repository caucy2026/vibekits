package com.vibekits.vibekits.component.adb;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Process;

/** Restores adbd after reboot only when the user left remote simulation enabled. */
public final class RemoteAdbBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction()) ||
                Process.myUid() != Process.SYSTEM_UID ||
                !context.getSharedPreferences("remote_adb_state", Context.MODE_PRIVATE)
                        .getBoolean("enabled", false)) return;
        final PendingResult pending = goAsync();
        new Thread(() -> {
            try {
                RemoteAdbReceiver.ensure(context);
            } catch (Exception ignored) {
                // The main application also retries its bounded restore path.
            } finally {
                pending.finish();
            }
        }, "VibeKitsAdbBootRestore").start();
    }
}
