package com.vibekits.vibekits.component.builder;

import android.os.Build;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/** Generates compile-only Java classes from this PAD's installed Android framework. */
final class DeviceFrameworkClasspath {
    private static final File FRAMEWORK_DEX = new File("/system/framework/framework.jar");
    private static final File FRAMEWORK_RES = new File("/system/framework/framework-res.apk");
    private static final int MAX_CLASSES = 100_000;
    private static final long MAX_UNCOMPRESSED = 180L * 1024 * 1024;

    private DeviceFrameworkClasspath() { }

    static File resources() throws IOException {
        if (!FRAMEWORK_RES.isFile() || !FRAMEWORK_RES.canRead()) {
            throw new IOException("device Android framework resources are unavailable");
        }
        return FRAMEWORK_RES;
    }

    static File ensure(File toolchain, File cacheDir) throws Exception {
        if (!FRAMEWORK_DEX.isFile() || !FRAMEWORK_DEX.canRead()) {
            throw new IOException("device Android framework DEX is unavailable");
        }
        File library = new File(toolchain, "dex2jar/lib");
        if (!new File(library, "dex-tools-v2.4.jar").isFile()) {
            throw new IOException("incomplete dex2jar toolchain");
        }
        File api = new File(toolchain, "device-android-api.jar");
        File marker = new File(toolchain, ".device-framework-fingerprint");
        String fingerprint = Build.FINGERPRINT;
        if (api.isFile() && api.length() > 0 && fingerprint.equals(readMarker(marker))) {
            return api;
        }

        File work = new File(cacheDir, "builder-framework");
        if (!work.isDirectory() && !work.mkdirs()) {
            throw new IOException("cannot create framework conversion directory");
        }
        File converted = new File(work, "converted.jar");
        File patched = new File(work, "patched.jar");
        File log = new File(work, "conversion.log");
        converted.delete();
        patched.delete();

        List<String> command = new ArrayList<>();
        command.add(new File(toolchain, "java-21-openjdk/bin/java").getAbsolutePath());
        command.add("-Xms128m");
        command.add("-Xmx768m");
        command.add("-cp");
        command.add(new File(library, "*").getAbsolutePath());
        command.add("com.googlecode.dex2jar.tools.Dex2jarCmd");
        command.add("-nc");
        command.add("-f");
        command.add(FRAMEWORK_DEX.getAbsolutePath());
        command.add("-o");
        command.add(converted.getAbsolutePath());
        ProcessBuilder builder = new ProcessBuilder(command).directory(work)
            .redirectErrorStream(true).redirectOutput(log);
        String root = toolchain.getAbsolutePath();
        builder.environment().put("LD_LIBRARY_PATH", root + "/lib:" + root + "/java-21-openjdk/lib");
        builder.environment().put("JAVA_HOME", root + "/java-21-openjdk");
        builder.environment().put("HOME", work.getAbsolutePath());
        Process process = builder.start();
        if (!process.waitFor(120, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            throw new IOException("device framework conversion timed out");
        }
        if (process.exitValue() != 0 || !converted.isFile()) {
            throw new IOException("device framework conversion failed (exit " + process.exitValue() + ")");
        }
        patchClassVersions(converted, patched);
        if (!patched.isFile() || patched.length() == 0) {
            throw new IOException("empty device framework classpath");
        }
        if (api.exists() && !api.delete()) throw new IOException("cannot replace old framework classpath");
        if (!patched.renameTo(api)) throw new IOException("cannot activate framework classpath");
        try (OutputStream output = new FileOutputStream(marker)) {
            output.write(fingerprint.getBytes(StandardCharsets.UTF_8));
        }
        converted.delete();
        return api;
    }

    private static String readMarker(File marker) throws IOException {
        if (!marker.isFile() || marker.length() > 4096) return "";
        byte[] bytes = new byte[(int) marker.length()];
        try (InputStream input = new FileInputStream(marker)) {
            int offset = 0;
            while (offset < bytes.length) {
                int count = input.read(bytes, offset, bytes.length - offset);
                if (count < 0) return "";
                offset += count;
            }
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    static void patchClassVersions(File source, File target) throws IOException {
        int classes = 0;
        long total = 0;
        byte[] buffer = new byte[65536];
        try (ZipInputStream input = new ZipInputStream(new FileInputStream(source));
             ZipOutputStream output = new ZipOutputStream(new FileOutputStream(target))) {
            ZipEntry entry;
            while ((entry = input.getNextEntry()) != null) {
                if (!entry.getName().endsWith(".class")) continue;
                if (++classes > MAX_CLASSES) throw new IOException("too many framework classes");
                output.putNextEntry(new ZipEntry(entry.getName()));
                int header = 0;
                while (header < 8) {
                    int count = input.read(buffer, header, 8 - header);
                    if (count < 0) throw new IOException("truncated framework class file");
                    header += count;
                }
                if (buffer[0] != (byte) 0xca || buffer[1] != (byte) 0xfe ||
                        buffer[2] != (byte) 0xba || buffer[3] != (byte) 0xbe) {
                    throw new IOException("invalid framework class file");
                }
                // dex2jar v2.4 emits Java 6 headers even for interface default
                // methods. Java 8 headers let javac read these signatures.
                if ((buffer[6] & 0xff) == 0 && (buffer[7] & 0xff) < 52) {
                    buffer[6] = 0;
                    buffer[7] = 52;
                }
                output.write(buffer, 0, 8);
                total += 8;
                int count;
                while ((count = input.read(buffer)) != -1) {
                    total += count;
                    if (total > MAX_UNCOMPRESSED) throw new IOException("framework classpath too large");
                    output.write(buffer, 0, count);
                }
                output.closeEntry();
            }
        }
        if (classes == 0) throw new IOException("framework conversion produced no classes");
    }
}
