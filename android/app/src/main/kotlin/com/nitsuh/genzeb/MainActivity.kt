package com.nitsuh.genzeb

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** While true the app's own UI handles incoming SMS (in-app banner),
         *  so the background receiver stays out of the way. */
        @Volatile
        var isInForeground = false
    }

    private var channel: MethodChannel? = null
    private var launchTransaction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchTransaction = intent?.getStringExtra(MoneyNotifications.EXTRA_TRANSACTION_ID)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "genzeb/notifications").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLaunchTransaction" -> {
                        result.success(launchTransaction)
                        launchTransaction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val transactionId = intent.getStringExtra(MoneyNotifications.EXTRA_TRANSACTION_ID) ?: return
        channel?.invokeMethod("openTransaction", transactionId)
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }
}
