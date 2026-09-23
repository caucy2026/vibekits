package org.fcitx.fcitx5.android.common.ipc;

import org.fcitx.fcitx5.android.common.ipc.IKBoardOverlayCallback;

interface IKBoardOverlayService {
    int getCapabilities();
    boolean show(long requestId, String sessionId, int sourceDisplayId,
        int targetDisplayId, int targetWidth, int targetHeight, int keyboardHeight,
        IKBoardOverlayCallback callback);
    void hide(long requestId, String sessionId);
}
