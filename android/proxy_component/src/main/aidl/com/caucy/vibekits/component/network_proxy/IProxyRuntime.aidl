package com.caucy.vibekits.component.network_proxy;

import android.os.ParcelFileDescriptor;

interface IProxyRuntime {
    String version();
    boolean start(in ParcelFileDescriptor config);
    void stop();
    boolean running();
}
