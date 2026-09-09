package ffi

import android.content.Context

/** Narrow JNI surface exported by the source-built RustDesk transport core. */
object FFI {
    init {
        System.loadLibrary("rustdesk")
    }

    external fun init(context: Context)
    external fun startHarnessServer(appDir: String)
    external fun harnessStatus(): String
    external fun harnessConnections(): String
    external fun harnessAuthorize(connectionId: Int): Boolean
    external fun harnessReject(connectionId: Int): Boolean
    external fun harnessOpenTunnel(
        routingId: String,
        localPort: Int,
        remotePort: Int,
        forceRelay: Boolean,
    ): String
    external fun harnessCloseTunnel(localPort: Int): Boolean
}
