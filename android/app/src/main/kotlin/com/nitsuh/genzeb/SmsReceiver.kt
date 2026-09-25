package com.nitsuh.genzeb

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Declared in the manifest, so it runs even when the app is closed. Hands
 * bank/wallet SMS to the Dart parser in a headless engine, which books the
 * transaction and posts a "money in / money out" notification.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        // The open app handles it itself (in-app banner, same ledger).
        if (MainActivity.isInForeground) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        // Multipart messages arrive as several PDUs from one sender.
        val bodies = LinkedHashMap<String, StringBuilder>()
        for (part in parts) {
            val sender = part?.originatingAddress?.trim().orEmpty()
            if (sender.isEmpty()) continue
            bodies.getOrPut(sender) { StringBuilder() }.append(part.messageBody.orEmpty())
        }
        // Cheap pre-filter: people text from full phone numbers; banks and
        // wallets use names or short codes. Don't start an engine for chats.
        val receivedAt = System.currentTimeMillis()
        val messages = bodies
            .filterKeys { !isPersonalNumber(it) }
            .map { (sender, body) ->
                mapOf("sender" to sender, "body" to body.toString(), "receivedAt" to receivedAt)
            }
        if (messages.isEmpty()) return

        val pending = goAsync()
        BackgroundSmsRunner.run(context.applicationContext, messages) { pending.finish() }
    }

    private fun isPersonalNumber(sender: String): Boolean {
        val digits = sender.removePrefix("+")
        return digits.length >= 9 && digits.all { it.isDigit() }
    }
}
