package com.caucy.vibekits.component.network_proxy;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.concurrent.TimeUnit;

/** Runs only a package-manager-installed Mihomo binary from this signed APK. */
public final class ProxyRuntimeService extends Service {
    private static final int MAX_CONFIG_BYTES = 32 * 1024 * 1024;
    private static final String CHANNEL = "vibekits_proxy_runtime";
    private Process process;

    private final IProxyRuntime.Stub binder = new IProxyRuntime.Stub() {
        @Override public String version() {
            try {
                Process probe = new ProcessBuilder(executable().getAbsolutePath(), "-v")
                        .redirectErrorStream(true).start();
                if (!probe.waitFor(5, TimeUnit.SECONDS)) {
                    probe.destroyForcibly();
                    return "探测超时";
                }
                return probe.exitValue() == 0
                        ? readLimited(probe.getInputStream(), 512).trim() : "探测失败";
            } catch (Exception error) {
                return "核心无法运行：" + error.getClass().getSimpleName();
            }
        }

        @Override public synchronized boolean start(ParcelFileDescriptor source) {
            if (process != null && process.isAlive()) return true;
            try {
                File data = new File(getFilesDir(), "mihomo");
                if (!data.isDirectory() && !data.mkdirs()) return false;
                File config = new File(data, "active-runtime.yaml");
                try (ParcelFileDescriptor owned = source;
                     FileInputStream input = new FileInputStream(owned.getFileDescriptor());
                     FileOutputStream output = new FileOutputStream(config, false)) {
                    byte[] buffer = new byte[8192];
                    int count;
                    int total = 0;
                    while ((count = input.read(buffer)) != -1) {
                        total += count;
                        if (total > MAX_CONFIG_BYTES) throw new IOException("配置过大");
                        output.write(buffer, 0, count);
                    }
                    output.getFD().sync();
                }
                File core = executable();
                Process validate = new ProcessBuilder(core.getAbsolutePath(), "-t",
                        "-d", data.getAbsolutePath(), "-f", config.getAbsolutePath())
                        .redirectErrorStream(true).start();
                new Thread(() -> drain(validate.getInputStream()), "MihomoValidateOutput").start();
                if (!validate.waitFor(30, TimeUnit.SECONDS)) {
                    validate.destroyForcibly();
                    return false;
                }
                if (validate.exitValue() != 0) return false;
                process = new ProcessBuilder(core.getAbsolutePath(), "-d",
                        data.getAbsolutePath(), "-f", config.getAbsolutePath())
                        .redirectErrorStream(true).start();
                final Process current = process;
                new Thread(() -> drain(current.getInputStream()), "MihomoRuntimeOutput").start();
                Thread.sleep(400);
                return current.isAlive();
            } catch (Exception error) {
                stopProcess();
                return false;
            }
        }

        @Override public synchronized void stop() {
            stopProcess();
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
        }

        @Override public synchronized boolean running() {
            return process != null && process.isAlive();
        }
    };

    @Override public IBinder onBind(Intent intent) { return binder; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(new NotificationChannel(CHANNEL,
                    "VibeKits 代理", NotificationManager.IMPORTANCE_LOW));
        }
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL)
                : new Notification.Builder(this);
        Notification note = builder
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("VibeKits 代理运行中")
                .setContentText("点击 VibeKits 可管理代理")
                .setOngoing(true).build();
        startForeground(4401, note);
        return START_NOT_STICKY;
    }

    @Override public void onDestroy() {
        stopProcess();
        super.onDestroy();
    }

    private File executable() throws IOException {
        File core = new File(getApplicationInfo().nativeLibraryDir, "libmihomo.so");
        if (!core.isFile() || !core.canExecute()) throw new IOException("签名组件核心不可执行");
        return core;
    }

    private synchronized void stopProcess() {
        if (process == null) return;
        process.destroy();
        try {
            if (!process.waitFor(3, TimeUnit.SECONDS)) process.destroyForcibly();
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            process.destroyForcibly();
        }
        process = null;
    }

    private static String readLimited(InputStream stream, int maximum) throws IOException {
        byte[] buffer = new byte[maximum];
        int count = stream.read(buffer);
        return count < 0 ? "" : new String(buffer, 0, count);
    }

    private static void drain(InputStream stream) {
        try (InputStream input = stream) {
            byte[] buffer = new byte[8192];
            while (input.read(buffer) != -1) { /* never log subscription data */ }
        } catch (IOException ignored) { }
    }
}
