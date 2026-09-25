package com.nitsuh.genzeb

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/** Posts "money in / money out" system notifications. */
object MoneyNotifications {
    const val EXTRA_TRANSACTION_ID = "genzeb.transactionId"
    private const val CHANNEL_ID = "money_alerts"
    private const val BRAND_COLOR = 0xFF4E5AE8.toInt()

    fun show(context: Context, args: Map<String, Any?>) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return // the in-app alert is still recorded
        }
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureChannel(context, manager)

        val id = (args["id"] as? Number)?.toInt() ?: return
        val title = args["title"] as? String ?: return
        val text = args["text"] as? String ?: ""
        val publicText = args["publicText"] as? String ?: title
        val transactionId = args["transactionId"] as? String

        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (transactionId != null) putExtra(EXTRA_TRANSACTION_ID, transactionId)
        }
        val tap = PendingIntent.getActivity(
            context, id, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Lock screen: direction + institution only, never the amount.
        val publicVersion = builder(context)
            .setSmallIcon(R.drawable.ic_stat_genzeb)
            .setColor(BRAND_COLOR)
            .setContentTitle("Genzeb")
            .setContentText(publicText)
            .build()

        val notification = builder(context)
            .setSmallIcon(R.drawable.ic_stat_genzeb)
            .setColor(BRAND_COLOR)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .build()
        manager.notify(id, notification)
    }

    @Suppress("DEPRECATION")
    private fun builder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < 26) return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Money in / money out",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "An alert each time a bank or wallet SMS records a transaction"
            },
        )
    }
}
