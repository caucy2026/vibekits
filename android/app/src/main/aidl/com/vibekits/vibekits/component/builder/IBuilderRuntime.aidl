package com.vibekits.vibekits.component.builder;

import android.os.ParcelFileDescriptor;

interface IBuilderRuntime {
    String getRuntimeStatus();
    String startBuild(String taskId, String expectedPackageName,
        in ParcelFileDescriptor sourceZip, in ParcelFileDescriptor outputApk);
    String getBuildStatus(String taskId);
    void cancelBuild(String taskId);
}
