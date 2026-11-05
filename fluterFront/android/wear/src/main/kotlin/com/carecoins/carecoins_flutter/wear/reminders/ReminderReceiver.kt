package com.carecoins.carecoins_flutter.wear.reminders

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import com.carecoins.carecoins_flutter.wear.MainActivity
import com.carecoins.carecoins_flutter.wear.R
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.SnapshotStore
import java.time.Instant

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appCtx = context.applicationContext ?: context
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                val snapshot = SnapshotStore.load(appCtx)
                Reminders.reschedule(appCtx, snapshot, Instant.now())
            }
            Reminders.ACTION_REMIND -> {
                handleRemind(appCtx, intent)
            }
            Reminders.ACTION_SNOOZE -> {
                handleSnooze(appCtx, intent)
            }
        }
    }

    private fun handleRemind(context: Context, intent: Intent) {
        if (!Reminders.isEnabled(context)) return
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val upcomingId = intent.getStringExtra(Reminders.EXTRA_UPCOMING_ID).orEmpty()
        if (upcomingId.isEmpty()) return

        val snapshotItem = SnapshotStore.load(context)?.upcoming?.firstOrNull { it.id == upcomingId }
        val title = intent.getStringExtra(Reminders.EXTRA_TITLE)
            ?.takeIf { it.isNotBlank() }
            ?: snapshotItem?.title
            ?: return
        val startsAtMillis = intent.getLongExtra(
            Reminders.EXTRA_STARTS_AT_MILLIS,
            snapshotItem?.startsAt?.toEpochMilli() ?: System.currentTimeMillis(),
        )
        val startsAt = Instant.ofEpochMilli(startsAtMillis)

        val notificationManager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureChannel(context, notificationManager)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            context,
            upcomingId.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val snoozeIntent = Intent(context, ReminderReceiver::class.java).apply {
            action = Reminders.ACTION_SNOOZE
            data = Uri.parse("carecoins://reminder-snooze/$upcomingId")
            putExtra(Reminders.EXTRA_UPCOMING_ID, upcomingId)
            putExtra(Reminders.EXTRA_TITLE, title)
            putExtra(Reminders.EXTRA_STARTS_AT_MILLIS, startsAtMillis)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            upcomingId.hashCode(),
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val icon = Icon.createWithResource(context, R.drawable.ic_stat_carecoins)
        val openAction = Notification.Action.Builder(
            icon,
            L10n.t(context, "watch.reminder.open"),
            openPendingIntent,
        ).build()
        val snoozeAction = Notification.Action.Builder(
            icon,
            L10n.t(context, "watch.reminder.snooze"),
            snoozePendingIntent,
        ).build()

        val bodyText = L10n.t(context, "watch.reminder.body", L10n.shortTime(context, startsAt))
        val notification = Notification.Builder(context, Reminders.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_carecoins)
            .setContentTitle(title)
            .setContentText(bodyText)
            .setContentIntent(openPendingIntent)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setLocalOnly(true)
            .addAction(openAction)
            .addAction(snoozeAction)
            .build()

        notificationManager.notify(Reminders.notificationIdFor(upcomingId), notification)
    }

    private fun handleSnooze(context: Context, intent: Intent) {
        val upcomingId = intent.getStringExtra(Reminders.EXTRA_UPCOMING_ID).orEmpty()
        if (upcomingId.isEmpty()) return

        val notificationManager = context.getSystemService(NotificationManager::class.java)
        notificationManager?.cancel(Reminders.notificationIdFor(upcomingId))

        val snapshotItem = SnapshotStore.load(context)?.upcoming?.firstOrNull { it.id == upcomingId }
        val title = intent.getStringExtra(Reminders.EXTRA_TITLE)
            ?.takeIf { it.isNotBlank() }
            ?: snapshotItem?.title
            ?: return
        val startsAtMillis = intent.getLongExtra(
            Reminders.EXTRA_STARTS_AT_MILLIS,
            snapshotItem?.startsAt?.toEpochMilli() ?: System.currentTimeMillis(),
        )

        Reminders.scheduleSnooze(
            context = context,
            upcomingId = upcomingId,
            title = title,
            startsAtMillis = startsAtMillis,
            now = Instant.now(),
        )
    }

    private fun ensureChannel(context: Context, notificationManager: NotificationManager) {
        val channelName = L10n.t(context, "watch.reminders.toggle")
        val channel = NotificationChannel(
            Reminders.CHANNEL_ID,
            channelName,
            NotificationManager.IMPORTANCE_HIGH,
        )
        notificationManager.createNotificationChannel(channel)
    }
}
