package com.vibekits.vibekits

import android.app.Presentation
import android.content.Context
import android.content.DialogInterface
import android.graphics.Canvas
import android.graphics.Color
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import android.view.Display
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.Window
import android.view.WindowInsets
import android.widget.FrameLayout
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The only authoritative Flutter window. In dual-display mode its FlutterView
 * is laid out once at 1920x2560: D2 presents Y=0..1279 and D0 clips
 * Y=1280..2559. There is no second Flutter engine, route or application state.
 */
open class MainActivity : FlutterActivity() {
    private val channelName = "vibekits/credentials"
    private val displayChannelName = "vibekits/display"
    private val keyAlias = "VibekitsAndroidCredentialKey"
    private val preferencesName = "vibekits_secure_credentials"
    private var continuousDisplay: ContinuousDisplayCoordinator? = null

    protected val isDualMode: Boolean
        get() = intent?.getBooleanExtra(EXTRA_DUAL_MODE, false) == true

    // Texture rendering is required because the D2 Presentation draws the
    // authoritative Flutter View into a second hardware Canvas. SurfaceView
    // content cannot participate in View.draw(Canvas).
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyImmersiveCanvas(window)
        if (isDualMode) {
            continuousDisplay = ContinuousDisplayCoordinator(this)
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        applyImmersiveCanvas(window)
        window.decorView.post { continuousDisplay?.attach() }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyImmersiveCanvas(window)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        window.decorView.post { continuousDisplay?.attach() }
    }

    @Deprecated("Deprecated in Android")
    override fun onBackPressed() {
        if (isDualMode) {
            finishAndRemoveTask()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        continuousDisplay?.release()
        continuousDisplay = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    val key = call.argument<String>("key") ?: ""
                    require(key.matches(Regex("[A-Za-z0-9._-]{1,128}"))) {
                        "Invalid credential key"
                    }
                    when (call.method) {
                        "read" -> result.success(readCredential(key))
                        "write" -> {
                            val value = call.argument<String>("value") ?: ""
                            require(value.toByteArray(Charsets.UTF_8).size <= 8192) {
                                "Credential is too large"
                            }
                            if (value.isEmpty()) deleteCredential(key) else writeCredential(key, value)
                            result.success(null)
                        }
                        "delete" -> {
                            deleteCredential(key)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("CREDENTIAL_ERROR", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, displayChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDisplayContext" -> {
                        continuousDisplay?.attach()
                        result.success(mapOf(
                            "mode" to if (continuousDisplay?.isContinuous == true) "dual" else "single",
                            "role" to if (continuousDisplay?.isContinuous == true) "continuous_canvas" else "primary",
                            "displayId" to (display?.displayId ?: Display.DEFAULT_DISPLAY),
                            "virtualWidth" to 1920,
                            "virtualHeight" to 2560,
                            "viewportTop" to if (continuousDisplay?.isContinuous == true) 1280 else 0,
                            "viewportHeight" to 1280,
                        ))
                    }
                    "exitDualScreen" -> {
                        finishAndRemoveTask()
                        result.success(null)
                    }
                    "exitApp" -> {
                        finishAndRemoveTask()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun writeCredential(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val packed = ByteBuffer.allocate(4 + cipher.iv.size + encrypted.size)
            .putInt(cipher.iv.size)
            .put(cipher.iv)
            .put(encrypted)
            .array()
        getSharedPreferences(preferencesName, MODE_PRIVATE)
            .edit()
            .putString(key, Base64.encodeToString(packed, Base64.NO_WRAP))
            .apply()
    }

    private fun readCredential(key: String): String? {
        val encoded = getSharedPreferences(preferencesName, MODE_PRIVATE)
            .getString(key, null) ?: return null
        val packed = ByteBuffer.wrap(Base64.decode(encoded, Base64.NO_WRAP))
        val ivSize = packed.int
        require(ivSize in 12..32 && packed.remaining() > ivSize) { "Invalid credential data" }
        val iv = ByteArray(ivSize).also { packed.get(it) }
        val encrypted = ByteArray(packed.remaining()).also { packed.get(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    private fun deleteCredential(key: String) {
        getSharedPreferences(preferencesName, MODE_PRIVATE).edit().remove(key).apply()
    }

    companion object {
        const val ACTION_DUAL_SCREEN = "com.vibekits.vibekits.action.DUAL_SCREEN"
        const val ACTION_SINGLE_SCREEN = "com.vibekits.vibekits.action.SINGLE_SCREEN"
        const val EXTRA_DUAL_MODE = "vibekits.dual_screen"
        const val PREFERRED_COMPANION_DISPLAY_ID = 2
    }
}

/** Long-press launcher shortcut. It remains on the physical display tapped by the user. */
class SingleScreenActivity : MainActivity()

/**
 * KEMI continuous-canvas implementation: one FlutterView and state tree, two
 * physical viewports. D2 draws the upper half; the D0 host window sees the
 * translated lower half. D2 input is dispatched directly to the same source.
 */
private class ContinuousDisplayCoordinator(private val activity: MainActivity) :
    DisplayManager.DisplayListener {
    private val displayManager = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private val handler = Handler(Looper.getMainLooper())
    private var source: View? = null
    private var presentation: ContinuousCanvasPresentation? = null
    private var releasing = false
    private var listenerRegistered = false
    private var retryCount = 0
    private val retryAttach = Runnable { attach() }

    val isContinuous: Boolean
        get() = presentation?.isShowing == true

    fun attach() {
        if (releasing || presentation?.isShowing == true) return
        if (!listenerRegistered) {
            displayManager.registerDisplayListener(this, handler)
            listenerRegistered = true
        }
        val displays = displayManager.displays.joinToString { display ->
            "id=${display.displayId},state=${display.state}," +
                "mode=${display.mode.physicalWidth}x${display.mode.physicalHeight}"
        }
        Log.i(TAG, "attach displays=[$displays]")
        val target = eligibleDisplay() ?: run {
            Log.w(TAG, "no eligible 1920x1280 presentation display")
            restoreSingleScreen()
            if (retryCount++ < MAX_ATTACH_RETRIES) {
                handler.removeCallbacks(retryAttach)
                handler.postDelayed(retryAttach, ATTACH_RETRY_MS)
            }
            return
        }
        handler.removeCallbacks(retryAttach)
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val authoritative = content?.getChildAt(0) ?: run {
            Log.w(TAG, "authoritative Flutter root is not attached yet")
            if (retryCount++ < MAX_ATTACH_RETRIES) {
                handler.postDelayed(retryAttach, ATTACH_RETRY_MS)
            }
            return
        }
        source = authoritative
        authoritative.layoutParams = (authoritative.layoutParams ?: FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            CANVAS_HEIGHT,
        )).apply {
            width = ViewGroup.LayoutParams.MATCH_PARENT
            height = CANVAS_HEIGHT
        }
        authoritative.translationY = -VIEWPORT_HEIGHT.toFloat()
        authoritative.requestLayout()
        activity.window.decorView.requestLayout()

        try {
            presentation = ContinuousCanvasPresentation(
                activity,
                target,
                authoritative,
                onUnexpectedDismiss = { activity.finishAndRemoveTask() },
            ).also {
                it.show()
                applyImmersiveCanvas(it.window)
            }
            retryCount = 0
            Log.i(TAG, "continuous canvas active: D2=0..1279 D0=1280..2559")
        } catch (error: Exception) {
            Log.e(TAG, "failed to show continuous canvas on display ${target.displayId}", error)
            restoreSingleScreen()
            if (retryCount++ < MAX_ATTACH_RETRIES) {
                handler.postDelayed(retryAttach, ATTACH_RETRY_MS)
            }
        }
    }

    private fun eligibleDisplay(): Display? = displayManager.displays
        .asSequence()
        .filter { it.displayId != Display.DEFAULT_DISPLAY && it.state == Display.STATE_ON }
        .filter { display ->
            display.mode.physicalWidth == CANVAS_WIDTH &&
                display.mode.physicalHeight == VIEWPORT_HEIGHT
        }
        .sortedWith(compareBy<Display> { it.displayId != MainActivity.PREFERRED_COMPANION_DISPLAY_ID }
            .thenBy { it.displayId })
        .firstOrNull()

    private fun restoreSingleScreen() {
        source?.let { view ->
            view.translationY = 0f
            view.layoutParams = view.layoutParams.apply {
                width = ViewGroup.LayoutParams.MATCH_PARENT
                height = ViewGroup.LayoutParams.MATCH_PARENT
            }
            view.requestLayout()
        }
    }

    fun release() {
        if (releasing) return
        releasing = true
        handler.removeCallbacks(retryAttach)
        if (listenerRegistered) {
            runCatching { displayManager.unregisterDisplayListener(this) }
            listenerRegistered = false
        }
        presentation?.releaseFromHost()
        presentation = null
        restoreSingleScreen()
        source = null
    }

    override fun onDisplayAdded(displayId: Int) {
        activity.window.decorView.post { attach() }
    }

    override fun onDisplayRemoved(displayId: Int) {
        if (presentation?.display?.displayId == displayId) {
            presentation?.releaseFromHost()
            presentation = null
            restoreSingleScreen()
        }
    }

    override fun onDisplayChanged(displayId: Int) = Unit

    companion object {
        const val CANVAS_WIDTH = 1920
        const val VIEWPORT_HEIGHT = 1280
        const val CANVAS_HEIGHT = 2560
        const val ATTACH_RETRY_MS = 250L
        const val MAX_ATTACH_RETRIES = 12
        const val TAG = "VibekitsContinuous"
    }
}

private class ContinuousCanvasPresentation(
    context: Context,
    display: Display,
    source: View,
    private val onUnexpectedDismiss: () -> Unit,
) : Presentation(context, display), DialogInterface.OnDismissListener {
    private val surface = ContinuousCanvasSurface(context, source)
    private var hostRelease = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window?.setBackgroundDrawableResource(android.R.color.black)
        setContentView(
            surface,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        window?.decorView?.post { applyImmersiveCanvas(window) }
        setOnDismissListener(this)
    }

    fun releaseFromHost() {
        hostRelease = true
        surface.release()
        if (isShowing) dismiss()
    }

    override fun onDismiss(dialog: DialogInterface?) {
        surface.release()
        if (!hostRelease) onUnexpectedDismiss()
    }
}

private class ContinuousCanvasSurface(context: Context, private val source: View) : View(context) {
    private var drawingSource = false
    private var frameScheduled = false
    private var released = false
    private val drawListener = ViewTreeObserver.OnDrawListener {
        if (!drawingSource) requestCoalescedFrame()
    }

    init {
        setBackgroundColor(Color.BLACK)
        isFocusable = true
        isFocusableInTouchMode = true
        source.viewTreeObserver.addOnDrawListener(drawListener)
        requestCoalescedFrame()
    }

    private fun requestCoalescedFrame() {
        if (released || frameScheduled) return
        frameScheduled = true
        postOnAnimation {
            frameScheduled = false
            if (!released) invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (released) return
        if (source.width < ContinuousDisplayCoordinator.CANVAS_WIDTH ||
            source.height < ContinuousDisplayCoordinator.CANVAS_HEIGHT
        ) {
            requestCoalescedFrame()
            return
        }
        drawingSource = true
        try {
            source.draw(canvas)
        } finally {
            drawingSource = false
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (released) return false
        val logicalEvent = MotionEvent.obtain(event)
        return try {
            source.dispatchTouchEvent(logicalEvent)
        } finally {
            logicalEvent.recycle()
        }
    }

    fun release() {
        if (released) return
        released = true
        if (source.viewTreeObserver.isAlive) {
            source.viewTreeObserver.removeOnDrawListener(drawListener)
        }
    }
}

@Suppress("DEPRECATION")
private fun applyImmersiveCanvas(window: Window?) {
    window ?: return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        window.setDecorFitsSystemWindows(false)
        window.insetsController?.apply {
            hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
            systemBarsBehavior =
                android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    } else {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }
}
