package com.vibekits.vibekits;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.os.Bundle;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.lang.reflect.Method;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import io.flutter.plugin.common.MethodChannel;

/** Runs the production Kotlin bridge against the signed builder on a real PAD. */
public final class PadBuilderBridgeInstrumentation extends Instrumentation {
    private static final String PACKAGE = "com.vibekits.hostbridgeprobe";

    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        int code = Activity.RESULT_OK;
        File workspace = null;
        String taskId = null;
        try {
            Context target = getTargetContext();
            PadBuilderComponentClient client = new PadBuilderComponentClient(target);
            Map<String, Object> status = call(client, "componentStatus", null, null, null, null);
            require(Boolean.TRUE.equals(status.get("buildReady")), "component not ready: " + status);

            workspace = new File(target.getFilesDir(), "pad-builder-bridge-test");
            File source = new File(workspace, "sample");
            File manifest = new File(source, "app/src/main/AndroidManifest.xml");
            File java = new File(source, "app/src/main/java/com/vibekits/hostbridgeprobe/Probe.java");
            require(manifest.getParentFile().mkdirs() || manifest.getParentFile().isDirectory(), "manifest directory");
            require(java.getParentFile().mkdirs() || java.getParentFile().isDirectory(), "source directory");
            Files.write(manifest.toPath(), ("<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" " +
                "package=\"" + PACKAGE + "\"><uses-sdk android:minSdkVersion=\"24\" " +
                "android:targetSdkVersion=\"35\"/><application/></manifest>").getBytes(StandardCharsets.UTF_8));
            Files.write(java.toPath(), ("package " + PACKAGE + "; public final class Probe {}\n")
                .getBytes(StandardCharsets.UTF_8));
            Map<String, Object> rejected = call(client, "startBuild", target.getCacheDir().getAbsolutePath(),
                workspace.getAbsolutePath(), PACKAGE, "bridgeReject");
            require(!Boolean.TRUE.equals(rejected.get("accepted")) &&
                String.valueOf(rejected.get("error")).contains("工作区"),
                "outside-workspace source was not rejected: " + rejected);
            taskId = "bridge" + System.currentTimeMillis();
            Map<String, Object> started = call(client, "startBuild", source.getAbsolutePath(),
                workspace.getAbsolutePath(), PACKAGE, taskId);
            require(Boolean.TRUE.equals(started.get("accepted")), "build rejected: " + started);

            Map<String, Object> built = null;
            for (int attempt = 0; attempt < 180; attempt++) {
                built = call(client, "buildStatus", null, null, null, taskId);
                if ("completed".equals(built.get("state")) || "failed".equals(built.get("state"))) break;
                Thread.sleep(500);
            }
            require(built != null && "completed".equals(built.get("state")) &&
                Boolean.TRUE.equals(built.get("verified")), "build not verified: " + built);
            Map<String, Object> prepared = call(client, "prepareInstall", null, null, null, taskId);
            require(Boolean.TRUE.equals(prepared.get("verified")), "installer cache rejected: " + prepared);
            require(PACKAGE.equals(prepared.get("packageName")), "wrong generated package");
            result.putString("status", "passed");
            result.putString("sha256", String.valueOf(built.get("actualSha256")));
            result.putLong("bytes", ((Number) built.get("bytes")).longValue());
        } catch (Throwable error) {
            code = Activity.RESULT_CANCELED;
            result.putString("status", "failed");
            result.putString("error", error.toString());
        } finally {
            if (workspace != null) deleteTree(workspace);
            if (taskId != null) {
                Context target = getTargetContext();
                new File(target.getFilesDir(), "Vibekits/builds/" + taskId + ".apk").delete();
                new File(target.getCacheDir(), "pad-builder/" + taskId + ".zip").delete();
                new File(target.getCacheDir(), "pad-builder-install/" + taskId + ".apk").delete();
            }
            finish(code, result);
        }
    }

    private static Map<String, Object> call(PadBuilderComponentClient client, String method,
            String source, String workspace, String packageName, String taskId) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Object> response = new AtomicReference<>();
        MethodChannel.Result callback = new MethodChannel.Result() {
            @Override public void success(Object value) { response.set(value); done.countDown(); }
            @Override public void error(String code, String message, Object details) {
                response.set(new IllegalStateException(code + ": " + message)); done.countDown();
            }
            @Override public void notImplemented() {
                response.set(new UnsupportedOperationException(method)); done.countDown();
            }
        };
        Method bridgeMethod = null;
        for (Method candidate : client.getClass().getDeclaredMethods()) {
            Class<?>[] types = candidate.getParameterTypes();
            if (types.length == 6 && types[0] == String.class &&
                types[5].isInstance(callback)) {
                bridgeMethod = candidate;
                break;
            }
        }
        if (bridgeMethod == null) {
            StringBuilder methods = new StringBuilder();
            for (Method candidate : client.getClass().getDeclaredMethods()) {
                methods.append(candidate.getName()).append('(');
                for (Class<?> type : candidate.getParameterTypes())
                    methods.append(type.getSimpleName()).append(',');
                methods.append("); ");
            }
            throw new IllegalStateException("release bridge method missing: " + methods);
        }
        bridgeMethod.setAccessible(true);
        bridgeMethod.invoke(client, method, source, workspace, packageName, taskId, callback);
        require(done.await(method.equals("componentStatus") ? 220 : 35, TimeUnit.SECONDS),
            "bridge timeout: " + method);
        Object value = response.get();
        if (value instanceof Exception) throw (Exception) value;
        if (!(value instanceof Map)) throw new IllegalStateException("bridge did not return map");
        @SuppressWarnings("unchecked") Map<String, Object> mapped = (Map<String, Object>) value;
        return mapped;
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }

    private static void deleteTree(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) for (File child : children) deleteTree(child);
        }
        file.delete();
    }
}
