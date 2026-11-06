package com.carecoins.carecoins_flutter.quick

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import com.carecoins.carecoins_flutter.MainActivity
import com.carecoins.carecoins_flutter.R
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.Palette
import com.carecoins.quickcore.QuickNotificationState
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.QuickSurfaceState
import java.time.Instant

object QuickNotification {
    const val CHANNEL_ID = "quick_task"
    const val NOTIFICATION_ID = 4201
    const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    private const val REQ_CONTENT = 100
    private const val REQ_STOP = 101

    fun sync(
        context: Context,
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
    ) {
        val appCtx = context.applicationContext ?: context
        val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        val state = QuickSurfaceState.pickNotification(snapshot, now)
        if (state !is QuickNotificationState.Running) {
            nm.cancel(NOTIFICATION_ID)
            return
        }

        if (!hasPostPermission(appCtx)) {
            return
        }

        ensureChannel(appCtx, nm)
        val notification = buildNotification(appCtx, state)
        nm.notify(NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        val appCtx = context.applicationContext ?: context
        val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        nm.cancel(NOTIFICATION_ID)
    }

    private fun hasPostPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun ensureChannel(context: Context, nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelName = L10n.t(context, "android.channel.quick")
            val channel = NotificationChannel(
                CHANNEL_ID,
                channelName,
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun contentPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            REQ_CONTENT,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionPendingIntent(
        context: Context,
        requestCode: Int,
        action: String,
        activityId: String,
    ): PendingIntent {
        val intent = Intent(context, QuickActionReceiver::class.java).apply {
            putExtra(QuickActionReceiver.EXTRA_ACTION, action)
            putExtra(QuickActionReceiver.EXTRA_ID, activityId)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildAction(
        context: Context,
        title: String,
        pendingIntent: PendingIntent,
    ): Notification.Action {
        val icon = Icon.createWithResource(context, R.drawable.ic_stat_carecoins)
        return Notification.Action.Builder(icon, title, pendingIntent).build()
    }

    private fun buildNotification(
        context: Context,
        state: QuickNotificationState.Running,
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder
            .setSmallIcon(R.drawable.ic_stat_carecoins)
            .setContentIntent(contentPendingIntent(context))
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setContentTitle(state.title)
            .setOngoing(true)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setWhen(state.startedAt.toEpochMilli())
            .setColor(Palette.primary.toInt())
            .addAction(
                buildAction(
                    context,
                    L10n.t(context, "widget.stop"),
                    actionPendingIntent(
                        context,
                        REQ_STOP,
                        QuickActionReceiver.ACTION_STOP,
                        state.activityId,
                    ),
                ),
            )
        if (Build.VERSION.SDK_INT >= 36) {
            setRequestPromotedOngoing(builder, true)
        }

        return builder.build()
    }

    private fun setRequestPromotedOngoing(builder: Notification.Builder, promoted: Boolean) {
        if (Build.VERSION.SDK_INT >= 36) {
            builder.extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, promoted)
            runCatching {
                val method = Notification.Builder::class.java.getMethod(
                    "setRequestPromotedOngoing",
                    Boolean::class.javaPrimitiveType,
                )
                method.invoke(builder, promoted)
            }
        }
    }
}
