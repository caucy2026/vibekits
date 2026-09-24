package com.vibekits.vibekits.builderprobeclient;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.widget.TextView;

import com.vibekits.vibekits.component.builder.IBuilderRuntime;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/** Test-only same-certificate caller for the market component's Binder contract. */
public final class ProbeClientActivity extends Activity {
    private static final String TAG = "PAD_BUILDER_IPC_PROBE";
    private static final String PACKAGE = "com.vibekits.builderipcprobe";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private HandlerThread workerThread;
    private Handler worker;
    private TextView label;
    private volatile IBuilderRuntime runtime;
    private String taskId;
    private boolean bound;
    private int polls;
    private volatile boolean stopped;

    private final ServiceConnection connection = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder binder) {
            runtime = IBuilderRuntime.Stub.asInterface(binder);
            worker.post(ProbeClientActivity.this::poll);
        }
        @Override public void onServiceDisconnected(ComponentName name) {
            runtime = null;
            show("service_disconnected");
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        label = new TextView(this);
        label.setTextSize(23);
        label.setPadding(24, 24, 24, 24);
        setContentView(label);
        workerThread = new HandlerThread("PadBuilderIpcProbe");
        workerThread.start();
        worker = new Handler(workerThread.getLooper());
        Intent service = new Intent().setClassName("com.vibekits.vibekits.component.builder",
            "com.vibekits.vibekits.component.builder.BuilderRuntimeService");
        bound = bindService(service, connection, BIND_AUTO_CREATE);
        if (!bound) show("bind_failed");
    }

    private void poll() {
        if (runtime == null || stopped) return;
        try {
            if (taskId == null) {
                JSONObject status = new JSONObject(runtime.getRuntimeStatus());
                String state = status.optString("state");
                if (!"ready".equals(state)) {
                    if ("failed".equals(state) || ++polls > 180) {
                        show("runtime_" + state + ": " + status.optString("error"));
                    } else {
                        worker.postDelayed(this::poll, 500);
                    }
                    return;
                }
                File source = new File(getCacheDir(), "probe-source.zip");
                createSource(source);
                File output = new File(getFilesDir(), "probe-generated.apk");
                taskId = "ipcprobe" + System.currentTimeMillis();
                ParcelFileDescriptor input = ParcelFileDescriptor.open(source,
                    ParcelFileDescriptor.MODE_READ_ONLY);
                ParcelFileDescriptor sink = ParcelFileDescriptor.open(output,
                    ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_TRUNCATE |
                        ParcelFileDescriptor.MODE_WRITE_ONLY);
                String accepted = runtime.startBuild(taskId, PACKAGE, input, sink);
                input.close();
                sink.close();
                if (!new JSONObject(accepted).optBoolean("accepted")) {
                    show("start_rejected: " + accepted);
                    return;
                }
            }
            JSONObject state = new JSONObject(runtime.getBuildStatus(taskId));
            String phase = state.optString("state");
            if ("completed".equals(phase)) {
                File apk = new File(getFilesDir(), "probe-generated.apk");
                String actual = getPackageManager().getPackageArchiveInfo(apk.getAbsolutePath(), 0)
                    .packageName;
                show("completed bytes=" + apk.length() + " package=" + actual +
                    " sha256=" + state.optString("sha256"));
            } else if ("failed".equals(phase) || "cancelled".equals(phase)) {
                show(phase + " step=" + state.optString("step") + " error=" +
                    state.optString("error"));
            } else if (++polls > 360) {
                show("task_timeout state=" + phase);
            } else {
                if (polls % 10 == 0) show("progress=" + phase + " step=" + state.optString("step"));
                worker.postDelayed(this::poll, 500);
            }
        } catch (Exception error) {
            show("client_error=" + error.getClass().getSimpleName() + ": " + error.getMessage());
        }
    }

    private void createSource(File target) throws Exception {
        try (ZipOutputStream output = new ZipOutputStream(new FileOutputStream(target))) {
            add(output, "app/src/main/AndroidManifest.xml",
                "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" package=\"" +
                    PACKAGE + "\"><uses-sdk android:minSdkVersion=\"24\" " +
                    "android:targetSdkVersion=\"35\"/><application/></manifest>");
            add(output, "app/src/main/java/com/vibekits/builderipcprobe/Probe.java",
                "package com.vibekits.builderipcprobe; public final class Probe {}\n");
        }
    }

    private static void add(ZipOutputStream zip, String name, String text) throws Exception {
        zip.putNextEntry(new ZipEntry(name));
        zip.write(text.getBytes(StandardCharsets.UTF_8));
        zip.closeEntry();
    }

    private void show(String text) {
        Log.i(TAG, text);
        handler.post(() -> {
            if (!stopped) label.setText(text);
        });
    }

    @Override protected void onDestroy() {
        stopped = true;
        handler.removeCallbacksAndMessages(null);
        if (bound) unbindService(connection);
        worker.removeCallbacksAndMessages(null);
        workerThread.quitSafely();
        super.onDestroy();
    }
}
