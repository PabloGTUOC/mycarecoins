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
import com.carecoins.quickcore.QuickCore
import com.carecoins.quickcore.QuickNotificationState
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.QuickSurfaceState
import java.time.Instant

object QuickNotification {
    const val CHANNEL_ID = "quick_task"
    const val NOTIFICATION_ID = 4201
    const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"
    private const val PREF_SHOWN_STARTED_ID = "notificationShownStartedId"

    private const val REQ_CONTENT = 100
    private const val REQ_STOP = 101
    private const val REQ_FINISH = 102
    private const val REQ_CANCEL = 103

    private fun prefs(context: Context) =
        context.getSharedPreferences(QuickCore.PREFS_NAME, Context.MODE_PRIVATE)

    fun getShownStartedId(context: Context): String? {
        return runCatching {
            prefs(context).getString(PREF_SHOWN_STARTED_ID, null)?.takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    private fun setShownStartedId(context: Context, id: String?) {
        runCatching {
            val edit = prefs(context).edit()
            if (id.isNullOrEmpty()) {
                edit.remove(PREF_SHOWN_STARTED_ID)
            } else {
                edit.putString(PREF_SHOWN_STARTED_ID, id)
            }
            edit.apply()
        }
    }

    fun sync(
        context: Context,
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
    ) {
        val appCtx = context.applicationContext ?: context
        val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        val shownStartedId = getShownStartedId(appCtx)
        val state = QuickSurfaceState.pickNotification(snapshot, now, shownStartedId)

        when (state) {
            is QuickNotificationState.None -> {
                setShownStartedId(appCtx, null)
                nm.cancel(NOTIFICATION_ID)
                return
            }
            is QuickNotificationState.Running -> {
                setShownStartedId(appCtx, null)
            }
            is QuickNotificationState.Started -> {
                setShownStartedId(appCtx, state.activityId)
                QuickRefresh.scheduleAt(appCtx, state.endsAt)
            }
            is QuickNotificationState.Confirm -> {
                // Keep shownStartedId while confirming so subsequent refreshes stay in Confirm
            }
        }

        if (!hasPostPermission(appCtx)) {
            return
        }

        ensureChannel(appCtx, nm)
        val notification = buildNotification(appCtx, state, now)
        nm.notify(NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        val appCtx = context.applicationContext ?: context
        setShownStartedId(appCtx, null)
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
        state: QuickNotificationState,
        now: Instant,
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

        when (state) {
            is QuickNotificationState.Running -> {
                builder
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
            }

            is QuickNotificationState.Started -> {
                val untilText = L10n.t(
                    context,
                    "widget.until",
                    L10n.shortTime(context, state.endsAt),
                )
                val totalSeconds = ((state.endsAt.epochSecond - state.startsAt.epochSecond).coerceAtLeast(1L)).toInt()
                val elapsedSeconds = ((now.epochSecond - state.startsAt.epochSecond).coerceIn(0L, totalSeconds.toLong())).toInt()

                builder
                    .setContentTitle(state.title)
                    .setSubText(untilText)
                    .setOngoing(true)
                    .setShowWhen(true)
                    .setUsesChronometer(true)
                    .setChronometerCountDown(true)
                    .setWhen(state.endsAt.toEpochMilli())
                    .setProgress(totalSeconds, elapsedSeconds, false)
                    .setColor(Palette.success.toInt())
                    .addAction(
                        buildAction(
                            context,
                            L10n.t(context, "widget.done"),
                            actionPendingIntent(
                                context,
                                REQ_FINISH,
                                QuickActionReceiver.ACTION_FINISH,
                                state.activityId,
                            ),
                        ),
                    )

                if (Build.VERSION.SDK_INT >= 36) {
                    applyStartedLiveUpdate(context, builder, totalSeconds, elapsedSeconds)
                }
            }

            is QuickNotificationState.Confirm -> {
                builder
                    .setContentTitle(L10n.t(context, "widget.didYouFinish", state.title))
                    .setOngoing(false)
                    .setShowWhen(false)
                    .setUsesChronometer(false)
                    .setColor(Palette.warning.toInt())
                    .addAction(
                        buildAction(
                            context,
                            L10n.t(context, "widget.done"),
                            actionPendingIntent(
                                context,
                                REQ_FINISH,
                                QuickActionReceiver.ACTION_FINISH,
                                state.activityId,
                            ),
                        ),
                    )
                    .addAction(
                        buildAction(
                            context,
                            L10n.t(context, "widget.notDone"),
                            actionPendingIntent(
                                context,
                                REQ_CANCEL,
                                QuickActionReceiver.ACTION_CANCEL,
                                state.activityId,
                            ),
                        ),
                    )
            }

            is QuickNotificationState.None -> Unit
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

    private fun applyStartedLiveUpdate(
        context: Context,
        builder: Notification.Builder,
        totalSeconds: Int,
        elapsedSeconds: Int,
    ) {
        if (Build.VERSION.SDK_INT >= 36) {
            setRequestPromotedOngoing(builder, true)
            runCatching {
                val safeTotal = totalSeconds.coerceAtLeast(1)
                val safeElapsed = elapsedSeconds.coerceIn(0, safeTotal)
                val remainingSeconds = (safeTotal - safeElapsed).coerceAtLeast(0)
                val style = Notification.ProgressStyle()
                    .setStyledByProgress(true)
                    .setProgressTrackerIcon(
                        Icon.createWithResource(context, R.drawable.ic_stat_carecoins),
                    )
                if (safeElapsed > 0) {
                    style.addProgressSegment(
                        Notification.ProgressStyle.Segment(safeElapsed)
                            .setColor(Palette.success.toInt()),
                    )
                }
                if (remainingSeconds > 0) {
                    style.addProgressSegment(
                        Notification.ProgressStyle.Segment(remainingSeconds),
                    )
                }
                style.setProgress(safeElapsed)
                builder.setStyle(style)
            }
        }
    }
}
