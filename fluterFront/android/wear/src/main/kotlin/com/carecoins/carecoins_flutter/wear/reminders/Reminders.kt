package com.carecoins.carecoins_flutter.wear.reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.QuickCore
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.QuickSurfaceState
import com.carecoins.quickcore.SnapshotStore
import java.time.Instant

object Reminders {
    const val PREF_ENABLED = "watch.reminders.enabled"
    const val PREF_SCHEDULED_IDS = "watch.reminders.scheduledIds"
    const val PREF_AUTH_REQUESTED = "watch.reminders.authRequested"

    const val CHANNEL_ID = "reminders"
    const val ACTION_REMIND = "com.carecoins.carecoins_flutter.wear.action.REMIND"
    const val ACTION_SNOOZE = "com.carecoins.carecoins_flutter.wear.action.SNOOZE"

    const val EXTRA_UPCOMING_ID = "upcomingId"
    const val EXTRA_TITLE = "title"
    const val EXTRA_STARTS_AT_MILLIS = "startsAtMillis"

    const val WINDOW_LENGTH_MILLIS = 60_000L
    const val SNOOZE_DELAY_MILLIS = 5 * 60_000L

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(QuickCore.PREFS_NAME, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean {
        val appCtx = context.applicationContext ?: context
        return prefs(appCtx).getBoolean(PREF_ENABLED, true)
    }

    fun setEnabled(
        context: Context,
        enabled: Boolean,
        now: Instant = Instant.now(),
    ) {
        val appCtx = context.applicationContext ?: context
        prefs(appCtx).edit().putBoolean(PREF_ENABLED, enabled).apply()
        if (enabled) {
            val snapshot = if (DeviceKeyStore.isConnected(appCtx)) SnapshotStore.load(appCtx) else null
            reschedule(appCtx, snapshot, now)
        } else {
            cancelAll(appCtx)
        }
    }

    fun consumeFirstLaunchPermissionRequest(context: Context): Boolean {
        val appCtx = context.applicationContext ?: context
        val sp = prefs(appCtx)
        if (sp.getBoolean(PREF_AUTH_REQUESTED, false)) {
            return false
        }
        sp.edit().putBoolean(PREF_AUTH_REQUESTED, true).apply()
        return true
    }

    fun notificationIdFor(upcomingId: String): Int =
        (upcomingId.hashCode() and 0x7FFFFFFF).coerceAtLeast(1000)

    private fun alarmIntent(
        context: Context,
        upcomingId: String,
        title: String? = null,
        startsAtMillis: Long? = null,
    ): Intent {
        return Intent(context, ReminderReceiver::class.java).apply {
            action = ACTION_REMIND
            data = Uri.parse("carecoins://reminder/$upcomingId")
            putExtra(EXTRA_UPCOMING_ID, upcomingId)
            if (title != null) putExtra(EXTRA_TITLE, title)
            if (startsAtMillis != null) putExtra(EXTRA_STARTS_AT_MILLIS, startsAtMillis)
        }
    }

    fun cancelAll(context: Context) {
        val appCtx = context.applicationContext ?: context
        val sp = prefs(appCtx)
        val storedIds = sp.getStringSet(PREF_SCHEDULED_IDS, emptySet()).orEmpty()
        val alarmManager = appCtx.getSystemService(AlarmManager::class.java)
        if (alarmManager != null) {
            for (id in storedIds) {
                runCatching {
                    val intent = alarmIntent(appCtx, id)
                    val pendingIntent = PendingIntent.getBroadcast(
                        appCtx,
                        id.hashCode(),
                        intent,
                        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                    )
                    if (pendingIntent != null) {
                        alarmManager.cancel(pendingIntent)
                        pendingIntent.cancel()
                    }
                }
            }
        }
        sp.edit().remove(PREF_SCHEDULED_IDS).apply()
    }

    fun reschedule(
        context: Context,
        snapshot: QuickSnapshot? = SnapshotStore.load(context),
        now: Instant = Instant.now(),
    ) {
        val appCtx = context.applicationContext ?: context
        cancelAll(appCtx)

        val connected = DeviceKeyStore.isConnected(appCtx)
        val enabled = isEnabled(appCtx)
        val reminders = QuickSurfaceState.selectReminders(
            snapshot = snapshot,
            now = now,
            enabled = enabled,
            connected = connected,
        )
        if (reminders.isEmpty()) return

        val alarmManager = appCtx.getSystemService(AlarmManager::class.java) ?: return
        val scheduledIds = linkedSetOf<String>()

        for (item in reminders) {
            runCatching {
                val intent = alarmIntent(
                    context = appCtx,
                    upcomingId = item.id,
                    title = item.title,
                    startsAtMillis = item.startsAt.toEpochMilli(),
                )
                val pendingIntent = PendingIntent.getBroadcast(
                    appCtx,
                    item.id.hashCode(),
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                alarmManager.setWindow(
                    AlarmManager.RTC_WAKEUP,
                    item.at.toEpochMilli(),
                    WINDOW_LENGTH_MILLIS,
                    pendingIntent,
                )
                scheduledIds.add(item.id)
            }
        }

        prefs(appCtx).edit().putStringSet(PREF_SCHEDULED_IDS, scheduledIds).apply()
    }

    fun scheduleSnooze(
        context: Context,
        upcomingId: String,
        title: String,
        startsAtMillis: Long,
        now: Instant = Instant.now(),
    ) {
        val appCtx = context.applicationContext ?: context
        if (!isEnabled(appCtx) || !DeviceKeyStore.isConnected(appCtx)) return
        val alarmManager = appCtx.getSystemService(AlarmManager::class.java) ?: return
        val triggerAtMillis = now.toEpochMilli() + SNOOZE_DELAY_MILLIS
        runCatching {
            val intent = alarmIntent(
                context = appCtx,
                upcomingId = upcomingId,
                title = title,
                startsAtMillis = startsAtMillis,
            )
            val pendingIntent = PendingIntent.getBroadcast(
                appCtx,
                upcomingId.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.setWindow(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                WINDOW_LENGTH_MILLIS,
                pendingIntent,
            )
            val sp = prefs(appCtx)
            val updated = sp.getStringSet(PREF_SCHEDULED_IDS, emptySet()).orEmpty().toMutableSet()
            updated.add(upcomingId)
            sp.edit().putStringSet(PREF_SCHEDULED_IDS, updated).apply()
        }
    }
}
