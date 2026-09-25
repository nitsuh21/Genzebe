package com.nitsuh.genzeb

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Starts `smsBackgroundMain` in a short-lived headless Flutter engine. */
object BackgroundSmsRunner {
    // Background broadcasts may run for up to a minute; stop well before.
    private const val TIMEOUT_MS = 40_000L

    fun run(context: Context, messages: List<Map<String, Any>>, onDone: () -> Unit) {
        val handler = Handler(Looper.getMainLooper())
        handler.post {
            var finished = false
            var engine: FlutterEngine? = null
            fun finish() {
                if (finished) return
                finished = true
                engine?.destroy()
                onDone()
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)
                val created = FlutterEngine(context)
                engine = created
                MethodChannel(created.dartExecutor.binaryMessenger, "genzeb/background")
                    .setMethodCallHandler { call, result ->
                        when (call.method) {
                            "ready" -> result.success(messages)
                            "notify" -> {
                                @Suppress("UNCHECKED_CAST")
                                MoneyNotifications.show(context, call.arguments as Map<String, Any?>)
                                result.success(null)
                            }
                            "done" -> {
                                result.success(null)
                                handler.post { finish() }
                            }
                            else -> result.notImplemented()
                        }
                    }
                handler.postDelayed({ finish() }, TIMEOUT_MS)
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "smsBackgroundMain"),
                )
            } catch (error: Exception) {
                android.util.Log.w("Genzeb", "Background SMS engine failed", error)
                finish()
            }
        }
    }
}
