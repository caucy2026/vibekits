package org.fcitx.fcitx5.android.common.ipc;

import android.os.Bundle;

oneway interface IKBoardOverlayCallback {
    void onReady(long requestId, String sessionId, int virtualDisplayId);
    void onInput(long requestId, String sessionId, String operation, String text,
        int arg1, int arg2, in Bundle extras);
    void onClosed(long requestId, String sessionId, int reason);
}
