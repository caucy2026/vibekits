package com.vibekits.vibekits.component.builder;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.RemoteException;
import android.util.Log;
import android.widget.TextView;

import org.json.JSONObject;

/** Local diagnostic screen; it cannot submit source code or run commands. */
public final class BuilderStatusActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView label;
    private IBuilderRuntime runtime;
    private boolean bound;
    private int polls;

    private final ServiceConnection connection = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder binder) {
            runtime = IBuilderRuntime.Stub.asInterface(binder);
            poll();
        }

        @Override public void onServiceDisconnected(ComponentName name) {
            runtime = null;
            label.setText("编译组件服务已断开");
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        label = new TextView(this);
        label.setTextSize(24);
        label.setPadding(32, 32, 32, 32);
        label.setText("正在检查 PAD 编译组件…");
        setContentView(label);
        bound = bindService(new Intent(this, BuilderRuntimeService.class), connection, BIND_AUTO_CREATE);
        if (!bound) label.setText("无法连接 PAD 编译组件服务");
    }

    private void poll() {
        if (runtime == null || isFinishing()) return;
        IBuilderRuntime current = runtime;
        new Thread(() -> {
            try {
                JSONObject status = new JSONObject(current.getRuntimeStatus());
                handler.post(() -> {
                    if (isFinishing() || runtime != current) return;
                    String phase = status.optString("state");
                    String error = status.optString("error");
                    label.setText("PAD 编译组件：" + phase +
                        (error.isEmpty() ? "" : "\n" + error));
                    Log.i("PAD_BUILDER_COMPONENT", "state=" + phase + " buildReady=" +
                        status.optBoolean("buildReady") +
                        (error.isEmpty() ? "" : " error=" + error));
                    if ("preparing".equals(phase) && ++polls < 180) {
                        handler.postDelayed(this::poll, 500);
                    }
                });
            } catch (RemoteException | org.json.JSONException error) {
                handler.post(() -> {
                    if (!isFinishing()) label.setText("读取编译组件状态失败：" +
                        error.getClass().getSimpleName());
                });
            }
        }, "PadBuilderStatus").start();
    }

    @Override protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (bound) unbindService(connection);
        super.onDestroy();
    }
}
