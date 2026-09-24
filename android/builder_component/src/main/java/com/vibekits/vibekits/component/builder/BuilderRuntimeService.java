package com.vibekits.vibekits.component.builder;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.ParcelFileDescriptor;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/** A signature-protected, on-demand PAD APK builder. It never accepts shell text. */
public final class BuilderRuntimeService extends Service {
    private static final String ARCHIVE = "pad-builder-toolchain-arm64.zip";
    private static final String ARCHIVE_SHA256 =
        "66c86874552908ba76ef9ebb76de6a620407e6be935847df6396a0b643fc1b80";
    private static final Pattern TASK_ID = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final Pattern PACKAGE = Pattern.compile("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+");
    private static final Pattern APK_PACKAGE = Pattern.compile("package: name='([^']+)'");
    private static final long TOOLCHAIN_LIMIT = 400L * 1024 * 1024;
    private static final long SOURCE_LIMIT = 50L * 1024 * 1024;
    private static final String CHANNEL_ID = "pad_builder_active";

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ConcurrentHashMap<String, Job> jobs = new ConcurrentHashMap<>();
    private final AtomicInteger activeJobs = new AtomicInteger();
    private final CountDownLatch prepared = new CountDownLatch(1);
    private volatile String phase = "preparing";
    private volatile String runtimeError = "";
    private File toolchain;

    private final IBuilderRuntime.Stub binder = new IBuilderRuntime.Stub() {
        @Override public String getRuntimeStatus() {
            if ("preparing".equals(phase)) {
                // Keep the bound service alive through first-use conversion;
                // returning early would let the caller unbind and restart it.
                try { prepared.await(190, TimeUnit.SECONDS); }
                catch (InterruptedException error) { Thread.currentThread().interrupt(); }
            }
            JSONObject value = new JSONObject();
            put(value, "state", phase);
            put(value, "buildReady", "ready".equals(phase));
            put(value, "toolchainSha256", ARCHIVE_SHA256);
            put(value, "error", runtimeError);
            return value.toString();
        }

        @Override public String startBuild(String taskId, String expectedPackageName,
                ParcelFileDescriptor sourceZip, ParcelFileDescriptor outputApk) {
            if (taskId == null || !TASK_ID.matcher(taskId).matches() ||
                    expectedPackageName == null || !PACKAGE.matcher(expectedPackageName).matches() ||
                    sourceZip == null || outputApk == null) {
                closeQuietly(sourceZip);
                closeQuietly(outputApk);
                return "{\"accepted\":false,\"error\":\"invalid build request\"}";
            }
            Job job = new Job(taskId, expectedPackageName, sourceZip, outputApk);
            if (jobStatusFile(taskId).isFile()) {
                closeQuietly(sourceZip);
                closeQuietly(outputApk);
                return "{\"accepted\":false,\"error\":\"task ID already exists\"}";
            }
            if (jobs.putIfAbsent(taskId, job) != null) {
                closeQuietly(sourceZip);
                closeQuietly(outputApk);
                return "{\"accepted\":false,\"error\":\"duplicate task ID\"}";
            }
            try {
                if (activeJobs.getAndIncrement() == 0) beginActiveBuild();
            } catch (Exception error) {
                activeJobs.decrementAndGet();
                jobs.remove(taskId);
                closeQuietly(sourceZip);
                closeQuietly(outputApk);
                return "{\"accepted\":false,\"error\":\"cannot start foreground build\"}";
            }
            persistJob(job);
            worker.execute(() -> runJob(job));
            return "{\"accepted\":true,\"taskId\":\"" + taskId + "\"}";
        }

        @Override public String getBuildStatus(String taskId) {
            if (taskId == null || !TASK_ID.matcher(taskId).matches()) {
                return "{\"state\":\"not_found\"}";
            }
            Job job = jobs.get(taskId);
            if (job != null) return job.status();
            try {
                File status = jobStatusFile(taskId);
                if (!status.isFile() || status.length() > 32768) return "{\"state\":\"not_found\"}";
                byte[] bytes = new byte[(int) status.length()];
                try (InputStream input = new FileInputStream(status)) {
                    int offset = 0;
                    while (offset < bytes.length) {
                        int count = input.read(bytes, offset, bytes.length - offset);
                        if (count < 0) break;
                        offset += count;
                    }
                }
                JSONObject saved = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
                String state = saved.optString("state");
                if (!"completed".equals(state) && !"failed".equals(state) &&
                        !"cancelled".equals(state)) {
                    put(saved, "state", "interrupted");
                    put(saved, "error", "PAD 编译进程已停止，原任务未自动重跑");
                }
                return saved.toString();
            } catch (Exception ignored) {
                return "{\"state\":\"not_found\"}";
            }
        }

        @Override public void cancelBuild(String taskId) {
            Job job = jobs.get(taskId);
            if (job != null) {
                job.cancelled = true;
                if ("queued".equals(job.state)) job.state = "cancelled";
                Process process = job.process;
                if (process != null) process.destroyForcibly();
                persistJob(job);
            }
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        toolchain = new File(getFilesDir(), "toolchain-v1");
        worker.execute(this::prepare);
    }

    @Override public IBinder onBind(Intent intent) { return binder; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        return START_NOT_STICKY;
    }

    @Override public void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }

    private void beginActiveBuild() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID,
                "PAD 本机编译", NotificationManager.IMPORTANCE_LOW);
            getSystemService(NotificationManager.class).createNotificationChannel(channel);
        }
        startService(new Intent(this, BuilderRuntimeService.class));
        Notification.Builder notification = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, CHANNEL_ID) : new Notification.Builder(this);
        notification.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("VibeKits PAD 本机编译")
            .setContentText("编译任务正在运行")
            .setOngoing(true);
        startForeground(4307, notification.build());
    }

    private void prepare() {
        try {
            File marker = new File(toolchain, ".archive-sha256");
            if (!toolchain.isDirectory() || !ARCHIVE_SHA256.equals(readSmall(marker))) {
                extractToolchain();
            }
            File aapt = path(toolchain, "bin/aapt");
            File java = path(toolchain, "java-21-openjdk/bin/java");
            if (!aapt.isFile() || !java.isFile()) {
                throw new IOException("incomplete builder toolchain");
            }
            DeviceFrameworkClasspath.resources();
            DeviceFrameworkClasspath.ensure(toolchain, getCacheDir());
            File smokeMarker = path(toolchain, ".smoke-ok");
            if (!ARCHIVE_SHA256.equals(readSmall(smokeMarker))) {
                File sample = new File(getCacheDir(), "builder-smoke");
                File src = new File(sample, "src");
                File manifest = path(src, "app/src/main/AndroidManifest.xml");
                File source = path(src, "app/src/main/java/com/vibekits/buildersmoke/Smoke.java");
                write(manifest, "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" " +
                    "package=\"com.vibekits.buildersmoke\"><uses-sdk android:minSdkVersion=\"24\" " +
                    "android:targetSdkVersion=\"31\"/><application><activity android:name=\".Smoke\" " +
                    "android:exported=\"true\"/></application></manifest>");
                write(source, "package com.vibekits.buildersmoke; " +
                    "public final class Smoke extends android.app.Activity { " +
                    "public void onCreate(android.os.Bundle state) { super.onCreate(state); " +
                    "android.widget.TextView text = new android.widget.TextView(this); " +
                    "text.setText(\"PAD builder ready\"); setContentView(text); } }\n");
                File output = buildProject(new Job("smoke", "com.vibekits.buildersmoke", null, null),
                    src, new File(sample, "out"));
                if (!output.isFile() || output.length() == 0) throw new IOException("empty smoke APK");
                write(smokeMarker, ARCHIVE_SHA256);
            }
            phase = "ready";
        } catch (Exception error) {
            runtimeError = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
            phase = "failed";
        } finally {
            prepared.countDown();
        }
    }

    private void extractToolchain() throws Exception {
        File next = new File(getFilesDir(), "toolchain-v1-next");
        deleteTree(next);
        if (!next.mkdirs()) throw new IOException("cannot prepare toolchain directory");
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = getAssets().open(ARCHIVE)) {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        if (!ARCHIVE_SHA256.equals(hex(digest.digest()))) {
            throw new IOException("builder toolchain hash mismatch");
        }
        try (ZipInputStream zip = new ZipInputStream(getAssets().open(ARCHIVE))) {
            extractZip(zip, next, TOOLCHAIN_LIMIT, 1200);
        }
        File aapt = path(next, "bin/aapt");
        if (!aapt.setExecutable(true, true)) throw new IOException("aapt is not executable");
        File bin = path(next, "java-21-openjdk/bin");
        File[] launchers = bin.listFiles();
        if (launchers != null) for (File file : launchers) file.setExecutable(true, true);
        write(path(next, ".archive-sha256"), ARCHIVE_SHA256);
        deleteTree(toolchain);
        if (!next.renameTo(toolchain)) throw new IOException("cannot activate builder toolchain");
    }

    private void runJob(Job job) {
        File base = new File(new File(getFilesDir(), "builds"), job.id);
        try {
            if (job.cancelled) throw new IOException("cancelled");
            if (!"ready".equals(phase)) throw new IOException("builder unavailable: " + phase);
            job.state = "extracting";
            persistJob(job);
            File src = new File(base, "src");
            if (!src.mkdirs()) throw new IOException("cannot create source directory");
            try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(job.source);
                 ZipInputStream zip = new ZipInputStream(input)) {
                extractZip(zip, src, SOURCE_LIMIT, 1500);
            }
            job.source = null;
            if (job.cancelled) throw new IOException("cancelled");
            job.state = "building";
            persistJob(job);
            File apk = buildProject(job, src, new File(base, "out"));
            if (job.cancelled) throw new IOException("cancelled");
            job.state = "delivering";
            persistJob(job);
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = new FileInputStream(apk);
                 OutputStream output = new ParcelFileDescriptor.AutoCloseOutputStream(job.output)) {
                byte[] bytes = new byte[65536];
                int count;
                while ((count = input.read(bytes)) != -1) {
                    if (job.cancelled) throw new IOException("cancelled");
                    output.write(bytes, 0, count);
                    digest.update(bytes, 0, count);
                }
                output.flush();
            }
            job.output = null;
            job.bytes = apk.length();
            job.sha256 = hex(digest.digest());
            job.state = "completed";
        } catch (Exception error) {
            job.error = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
            job.state = job.cancelled ? "cancelled" : "failed";
        } finally {
            closeQuietly(job.source);
            closeQuietly(job.output);
            persistJob(job);
            if (activeJobs.decrementAndGet() == 0) {
                stopForeground(STOP_FOREGROUND_REMOVE);
                stopSelf();
            }
        }
    }

    private File buildProject(Job job, File src, File out) throws Exception {
        if (!out.exists() && !out.mkdirs()) throw new IOException("cannot create output directory");
        File manifest = path(src, "app/src/main/AndroidManifest.xml");
        File javaDir = path(src, "app/src/main/java");
        if (!manifest.isFile() || !javaDir.isDirectory()) {
            throw new IOException("expected app/src/main/AndroidManifest.xml and Java sources");
        }
        File generated = path(out, "gen");
        File classes = path(out, "classes");
        generated.mkdirs();
        classes.mkdirs();
        File unsigned = path(out, "unsigned.apk");
        List<String> aapt = command("bin/aapt", "package", "-f", "-m", "-J",
            generated.getAbsolutePath(), "-M", manifest.getAbsolutePath());
        File res = path(src, "app/src/main/res");
        if (res.isDirectory()) { aapt.add("-S"); aapt.add(res.getAbsolutePath()); }
        aapt.add("-I"); aapt.add(DeviceFrameworkClasspath.resources().getAbsolutePath());
        aapt.add("-F"); aapt.add(unsigned.getAbsolutePath());
        runStep(job, "resources", aapt, out);
        List<File> sources = new ArrayList<>();
        collectJava(javaDir, sources);
        collectJava(generated, sources);
        if (sources.isEmpty()) throw new IOException("no Java source files");
        List<String> javac = command("java-21-openjdk/bin/javac", "-source", "8", "-target", "8",
            "-cp", path(toolchain, "device-android-api.jar").getAbsolutePath(),
            "-d", classes.getAbsolutePath());
        for (File source : sources) javac.add(source.getAbsolutePath());
        runStep(job, "java", javac, out);
        runStep(job, "dex", list("/system/bin/dalvikvm", "-Xmx256m", "-cp",
            path(toolchain, "share/dex/dx.jar").getAbsolutePath(), "dx.dx.command.Main",
            "--dex", "--output=" + path(out, "classes.dex").getAbsolutePath(), "."), classes);
        runStep(job, "package", command("bin/aapt", "add", unsigned.getAbsolutePath(), "classes.dex"), out);
        File key = path(getFilesDir(), "builder-debug.jks");
        String password = signingPassword();
        if (!key.isFile()) {
            runStep(job, "create_debug_key", command("java-21-openjdk/bin/keytool", "-genkeypair",
                "-noprompt", "-alias", "vbk-debug", "-keyalg", "RSA", "-keysize", "2048",
                "-validity", "3650", "-dname", "CN=VibeKits PAD Build", "-keystore",
                key.getAbsolutePath(), "-storepass", password, "-keypass", password), out);
        }
        File signed = path(out, "signed.apk");
        runStep(job, "sign", command("java-21-openjdk/bin/java", "-jar",
            path(toolchain, "share/java/apksigner.jar").getAbsolutePath(), "sign", "--ks",
            key.getAbsolutePath(), "--ks-key-alias", "vbk-debug", "--ks-pass", "pass:" + password,
            "--key-pass", "pass:" + password, "--out", signed.getAbsolutePath(),
            unsigned.getAbsolutePath()), out);
        runStep(job, "verify_signature", command("java-21-openjdk/bin/java", "-jar",
            path(toolchain, "share/java/apksigner.jar").getAbsolutePath(), "verify",
            signed.getAbsolutePath()), out);
        String badge = runStep(job, "verify_package", command("bin/aapt", "dump", "badging",
            signed.getAbsolutePath()), out);
        Matcher match = APK_PACKAGE.matcher(badge);
        if (!match.find() || !job.packageName.equals(match.group(1))) {
            throw new IOException("APK package differs from requested package");
        }
        return signed;
    }

    private String runStep(Job job, String name, List<String> command, File cwd) throws Exception {
        if (job.cancelled) throw new IOException("cancelled");
        job.step = name;
        persistJob(job);
        File log = path(cwd, "builder-" + name + ".log");
        ProcessBuilder builder = new ProcessBuilder(command).directory(cwd).redirectErrorStream(true)
            .redirectOutput(log);
        String root = toolchain.getAbsolutePath();
        builder.environment().put("LD_LIBRARY_PATH", root + "/lib:" + root + "/java-21-openjdk/lib");
        builder.environment().put("PATH", root + "/bin:" + root + "/java-21-openjdk/bin:/system/bin");
        builder.environment().put("JAVA_HOME", root + "/java-21-openjdk");
        builder.environment().put("HOME", cwd.getAbsolutePath());
        Process process = builder.start();
        job.process = process;
        long deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(3);
        while (!process.waitFor(200, TimeUnit.MILLISECONDS)) {
            if (job.cancelled || System.nanoTime() >= deadline) {
                process.destroyForcibly();
                throw new IOException(job.cancelled ? "cancelled" : name + " timed out");
            }
        }
        job.process = null;
        String text = tail(log, 4096);
        job.step = name;
        job.log = text;
        persistJob(job);
        if (process.exitValue() != 0) throw new IOException(name + " exited " + process.exitValue() + ": " + text);
        return text;
    }

    private String signingPassword() throws Exception {
        File file = path(getFilesDir(), "builder-debug-password");
        String existing = readSmall(file);
        if (!existing.isEmpty()) return existing;
        byte[] bytes = new byte[24];
        new SecureRandom().nextBytes(bytes);
        String value = hex(bytes);
        write(file, value);
        file.setReadable(false, false);
        file.setReadable(true, true);
        return value;
    }

    private File jobStatusFile(String id) {
        return path(new File(new File(getFilesDir(), "builds"), id), "status.json");
    }

    private void persistJob(Job job) {
        try {
            File status = jobStatusFile(job.id);
            File parent = status.getParentFile();
            if (!parent.isDirectory() && !parent.mkdirs()) return;
            File next = new File(parent, "status.json.next");
            write(next, job.status());
            if (!next.renameTo(status)) next.delete();
        } catch (Exception ignored) { }
    }

    private List<String> command(String executable, String... args) {
        List<String> result = new ArrayList<>();
        result.add(path(toolchain, executable).getAbsolutePath());
        for (String arg : args) result.add(arg);
        return result;
    }

    private static List<String> list(String... values) {
        List<String> result = new ArrayList<>();
        for (String value : values) result.add(value);
        return result;
    }

    private static void collectJava(File root, List<File> found) {
        File[] files = root.listFiles();
        if (files == null) return;
        for (File file : files) {
            if (file.isDirectory()) collectJava(file, found);
            else if (file.getName().endsWith(".java")) found.add(file);
        }
    }

    private static void extractZip(ZipInputStream zip, File root, long byteLimit, int entryLimit)
            throws IOException {
        String prefix = root.getCanonicalPath() + File.separator;
        int entries = 0;
        long total = 0;
        ZipEntry entry;
        byte[] buffer = new byte[65536];
        while ((entry = zip.getNextEntry()) != null) {
            if (++entries > entryLimit) throw new IOException("archive has too many entries");
            File target = new File(root, entry.getName()).getCanonicalFile();
            if (!target.getPath().startsWith(prefix)) throw new IOException("archive path escape");
            if (entry.isDirectory()) {
                if (!target.isDirectory() && !target.mkdirs()) throw new IOException("cannot create directory");
                continue;
            }
            File parent = target.getParentFile();
            if (!parent.isDirectory() && !parent.mkdirs()) throw new IOException("cannot create parent");
            try (OutputStream output = new FileOutputStream(target)) {
                int count;
                while ((count = zip.read(buffer)) != -1) {
                    total += count;
                    if (total > byteLimit) throw new IOException("archive exceeds size limit");
                    output.write(buffer, 0, count);
                }
            }
            zip.closeEntry();
        }
    }

    private static String tail(File file, int limit) throws IOException {
        if (!file.isFile()) return "";
        try (RandomAccessFile input = new RandomAccessFile(file, "r")) {
            long start = Math.max(0, input.length() - limit);
            input.seek(start);
            byte[] bytes = new byte[(int) (input.length() - start)];
            input.readFully(bytes);
            return new String(bytes, StandardCharsets.UTF_8);
        }
    }

    private static String readSmall(File file) throws IOException {
        if (!file.isFile() || file.length() > 4096) return "";
        try (InputStream input = new FileInputStream(file)) {
            byte[] bytes = new byte[(int) file.length()];
            int read = input.read(bytes);
            return read < 0 ? "" : new String(bytes, 0, read, StandardCharsets.UTF_8).trim();
        }
    }

    private static void write(File file, String value) throws IOException {
        File parent = file.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IOException("cannot create parent");
        }
        try (OutputStream output = new FileOutputStream(file)) {
            output.write(value.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static void deleteTree(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) for (File child : children) deleteTree(child);
        }
        file.delete();
    }

    private static File path(File root, String child) { return new File(root, child); }
    private static void closeQuietly(ParcelFileDescriptor fd) {
        if (fd != null) try { fd.close(); } catch (IOException ignored) { }
    }
    private static void put(JSONObject target, String key, Object value) {
        try { target.put(key, value); } catch (Exception ignored) { }
    }
    private static String hex(byte[] bytes) {
        StringBuilder value = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) value.append(String.format("%02x", b & 0xff));
        return value.toString();
    }

    private static final class Job {
        final String id;
        final String packageName;
        volatile ParcelFileDescriptor source;
        volatile ParcelFileDescriptor output;
        volatile Process process;
        volatile boolean cancelled;
        volatile String state = "queued";
        volatile String step = "";
        volatile String log = "";
        volatile String error = "";
        volatile String sha256 = "";
        volatile long bytes;

        Job(String id, String packageName, ParcelFileDescriptor source, ParcelFileDescriptor output) {
            this.id = id;
            this.packageName = packageName;
            this.source = source;
            this.output = output;
        }

        String status() {
            JSONObject value = new JSONObject();
            put(value, "taskId", id);
            put(value, "packageName", packageName);
            put(value, "state", state);
            put(value, "step", step);
            put(value, "log", log);
            put(value, "error", error);
            put(value, "bytes", bytes);
            put(value, "sha256", sha256);
            return value.toString();
        }
    }
}
