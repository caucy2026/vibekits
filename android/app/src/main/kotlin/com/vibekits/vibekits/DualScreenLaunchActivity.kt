package com.vibekits.vibekits

import android.app.Activity
import android.app.ActivityOptions
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display

/**
 * Lightweight launcher router derived from the KEMI dual-screen startup rules.
 * It never creates a Flutter engine, which prevents a launcher task born on D2
 * from contaminating the D0 controller task.
 */
class DualScreenLaunchActivity : Activity() {
    private var internalDisplayTransfer = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sourceDisplayId = display?.displayId ?: windowManager.defaultDisplay.displayId
        internalDisplayTransfer = true
        if (sourceDisplayId == Display.DEFAULT_DISPLAY) {
            launchPrimaryOnDefaultDisplay()
            finishAndRemoveTask()
            return
        }

        // OEM launchers bind the temporary task to the tapped display. Remove
        // that task first, then allow WindowManager a short release interval.
        finishAndRemoveTask()
        Handler(Looper.getMainLooper()).postDelayed(
            { launchPrimaryOnDefaultDisplay() },
            DISPLAY_TASK_RELEASE_DELAY_MS,
        )
    }

    override fun onUserLeaveHint() {
        if (!internalDisplayTransfer) super.onUserLeaveHint()
    }

    private fun launchPrimaryOnDefaultDisplay() {
        val intent = Intent(applicationContext, MainActivity::class.java)
            .setAction(MainActivity.ACTION_DUAL_SCREEN)
            .putExtra(MainActivity.EXTRA_DUAL_MODE, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        try {
            val options = ActivityOptions.makeBasic().apply {
                launchDisplayId = Display.DEFAULT_DISPLAY
            }
            applicationContext.startActivity(intent, options.toBundle())
        } catch (_: Exception) {
            applicationContext.startActivity(intent)
        }
    }

    companion object {
        private const val DISPLAY_TASK_RELEASE_DELAY_MS = 400L
    }
}
