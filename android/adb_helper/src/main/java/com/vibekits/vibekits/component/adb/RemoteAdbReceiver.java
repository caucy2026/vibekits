package com.vibekits.vibekits.component.adb;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Process;
import android.provider.Settings;

import java.util.concurrent.TimeUnit;
import java.net.InetSocketAddress;
import java.net.Socket;

/** Minimal system-UID companion; only VibeKits' same-signature request reaches it. */
public final class RemoteAdbReceiver extends BroadcastReceiver {
    public static final String ACTION = "com.vibekits.vibekits.action.ENSURE_REMOTE_ADB";
    public static final String DISABLE = "com.vibekits.vibekits.action.DISABLE_REMOTE_ADB";
    public static final String APPLY_PROXY = "com.vibekits.vibekits.action.APPLY_SYSTEM_PROXY";
    public static final String RESTORE_PROXY = "com.vibekits.vibekits.action.RESTORE_SYSTEM_PROXY";
    private static final String PREFS = "remote_adb_state";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null ||
                (!ACTION.equals(intent.getAction()) && !DISABLE.equals(intent.getAction()) &&
                 !APPLY_PROXY.equals(intent.getAction()) && !RESTORE_PROXY.equals(intent.getAction()))) return;
        final boolean enable = ACTION.equals(intent.getAction());
        final boolean applyProxy = APPLY_PROXY.equals(intent.getAction());
        final boolean restoreProxy = RESTORE_PROXY.equals(intent.getAction());
        final int port = intent.getIntExtra("port", 0);
        final PendingResult pending = goAsync();
        new Thread(() -> {
            int code = Activity.RESULT_CANCELED;
            String message = "ADB helper requires system UID";
            try {
                if (Process.myUid() == Process.SYSTEM_UID) {
                    boolean changed = applyProxy ? applyProxy(context, port) :
                            restoreProxy ? restoreProxy(context) :
                            enable ? ensure(context) : disable(context);
                    code = changed ? Activity.RESULT_OK : Activity.RESULT_CANCELED;
                    message = changed ? (applyProxy ? "system proxy enabled" :
                            restoreProxy ? "system proxy restored" :
                            enable ? "adbd requested on TCP 5555" :
                            "remote ADB authorization cleared") : "system property rejected";
                }
            } catch (Exception error) {
                message = error.getClass().getSimpleName();
            } finally {
                pending.setResultCode(code);
                pending.setResultData(message);
                pending.finish();
            }
        }, "VibeKitsAdbBootstrap").start();
    }

    static boolean ensure(Context context) throws Exception {
        boolean alreadyListening = listening();
        boolean port = setProperty("service.adb.tcp.port", "5555");
        boolean start = port && setProperty("ctl.start", "adbd");
        if (start) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putBoolean("enabled", true)
                    .putBoolean("owned", !alreadyListening ||
                            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                                    .getBoolean("owned", false)).apply();
        }
        return start;
    }

    private static boolean applyProxy(Context context, int port) {
        if (port < 1024 || port > 65535) return false;
        String target = "127.0.0.1:" + port;
        String current = Settings.Global.getString(context.getContentResolver(), Settings.Global.HTTP_PROXY);
        if (target.equals(current)) return true;
        android.content.SharedPreferences prefs = context.getSharedPreferences("proxy_state", Context.MODE_PRIVATE);
        if (!prefs.getBoolean("owned", false)) {
            prefs.edit().putBoolean("previousAbsent", current == null)
                    .putString("previous", current).commit();
        }
        boolean applied = Settings.Global.putString(context.getContentResolver(),
                Settings.Global.HTTP_PROXY, target);
        if (applied) prefs.edit().putString("target", target).putBoolean("owned", true).commit();
        return applied;
    }

    private static boolean restoreProxy(Context context) {
        android.content.SharedPreferences prefs = context.getSharedPreferences("proxy_state", Context.MODE_PRIVATE);
        if (!prefs.getBoolean("owned", false)) return true;
        String target = prefs.getString("target", "");
        String current = Settings.Global.getString(context.getContentResolver(), Settings.Global.HTTP_PROXY);
        if (!target.equals(current)) {
            prefs.edit().clear().commit();
            return true;
        }
        boolean restored = Settings.Global.putString(context.getContentResolver(),
                Settings.Global.HTTP_PROXY,
                prefs.getBoolean("previousAbsent", false) ? null : prefs.getString("previous", ""));
        if (restored) prefs.edit().clear().commit();
        return restored;
    }

    private static boolean disable(Context context) throws Exception {
        boolean owned = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean("owned", false);
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("enabled", false).putBoolean("owned", false).commit();
        if (!owned) return true;
        return setProperty("ctl.stop", "adbd") &&
                setProperty("service.adb.tcp.port", "-1");
    }

    private static boolean listening() {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("127.0.0.1", 5555), 300);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    private static boolean setProperty(String name, String value) throws Exception {
        java.lang.Process command = new ProcessBuilder("/system/bin/setprop", name, value)
                .redirectErrorStream(true).start();
        if (!command.waitFor(3, TimeUnit.SECONDS)) {
            command.destroyForcibly();
            return false;
        }
        return command.exitValue() == 0;
    }
}
