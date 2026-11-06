package com.carecoins.carecoins_flutter.wear.complication

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountUpTimeReference
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingTimelineComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.TimeInterval
import androidx.wear.watchface.complications.datasource.TimelineEntry
import com.carecoins.carecoins_flutter.wear.MainActivity
import com.carecoins.carecoins_flutter.wear.R
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.QuickSurfaceState
import com.carecoins.quickcore.SnapshotStore
import com.carecoins.quickcore.WearNextState
import java.time.Instant

class NextComplicationService : SuspendingTimelineComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val ctx = applicationContext ?: this
        val now = Instant.now()
        val previewState = WearNextState.NextUpcoming(
            upcoming = QuickSnapshot.Upcoming(
                id = "preview",
                title = L10n.t(ctx, "widget.title.care"),
                type = "care",
                startsAt = now.plusSeconds(15 * 60L),
                endsAt = now.plusSeconds(30 * 60L),
                status = "approved",
            ),
        )
        return buildNextData(
            context = ctx,
            type = type,
            state = previewState,
            includeTapAction = false,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationDataTimeline? {
        val ctx = applicationContext ?: this
        val now = Instant.now()
        val snapshot = SnapshotStore.load(ctx)
        val nowState = QuickSurfaceState.pickNext(snapshot, now, connected = snapshot != null)
        val currentPlanned = if (snapshot?.running == null) snapshot?.currentPlanned(now) else null
        val defaultData = buildNextData(
            context = ctx,
            type = request.complicationType,
            state = nowState,
            currentPlanned = currentPlanned,
            includeTapAction = true,
        ) ?: return null

        val entries = getTimelineEntries(
            context = ctx,
            type = request.complicationType,
            snapshot = snapshot,
            now = now,
        )
        return ComplicationDataTimeline(
            defaultComplicationData = defaultData,
            timelineEntries = entries,
        )
    }

    fun getTimelineEntries(
        context: Context,
        type: ComplicationType,
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
    ): List<TimelineEntry> {
        if (snapshot == null) return emptyList()
        val boundary = QuickSurfaceState.nextBoundary(snapshot, now)
        val instants = buildList {
            if (boundary != null && boundary.isAfter(now)) {
                add(boundary)
            }
            addAll(QuickSurfaceState.nextTimelineInstants(snapshot, now))
        }.distinct().sorted().take(3)
        if (instants.isEmpty()) return emptyList()

        return buildList(instants.size) {
            for (i in instants.indices) {
                val start = instants[i]
                val end = if (i + 1 < instants.size) {
                    instants[i + 1]
                } else {
                    start.plusSeconds(DEFAULT_LAST_ENTRY_DURATION_SECONDS)
                }
                if (!start.isBefore(end)) continue
                val stateAtStart = QuickSurfaceState.pickNext(snapshot, start, connected = true)
                val currentAtStart = if (snapshot.running == null) snapshot.currentPlanned(start) else null
                val data = buildNextData(
                    context = context,
                    type = type,
                    state = stateAtStart,
                    currentPlanned = currentAtStart,
                    includeTapAction = true,
                ) ?: continue
                add(TimelineEntry(TimeInterval(start, end), data))
            }
        }
    }

    companion object {
        private const val REQUEST_CODE_OPEN = 3002
        private const val DEFAULT_LAST_ENTRY_DURATION_SECONDS = 2 * 3600L

        fun buildNextData(
            context: Context,
            type: ComplicationType,
            state: WearNextState,
            currentPlanned: QuickSnapshot.Upcoming? = null,
            includeTapAction: Boolean,
        ): ComplicationData? {
            if (type != ComplicationType.SHORT_TEXT && type != ComplicationType.LONG_TEXT) {
                return null
            }

            val icon = MonochromaticImage.Builder(
                Icon.createWithResource(context, R.drawable.ic_stat_carecoins),
            ).build()
            val tapAction = if (includeTapAction) openAppPendingIntent(context) else null

            val text: ComplicationText
            val title: ComplicationText?
            val contentDescription: ComplicationText

            if (state is WearNextState.Running) {
                title = PlainComplicationText.Builder(state.running.title).build()
                text = TimeDifferenceComplicationText.Builder(
                    TimeDifferenceStyle.STOPWATCH,
                    CountUpTimeReference(state.running.startedAt),
                ).build()
                contentDescription = PlainComplicationText.Builder(
                    L10n.t(context, "widget.running", state.running.title),
                ).build()
            } else if (currentPlanned != null) {
                val fullText = L10n.t(context, "widget_now_planned_short", currentPlanned.title)
                contentDescription = PlainComplicationText.Builder(fullText).build()
                if (type == ComplicationType.SHORT_TEXT) {
                    text = PlainComplicationText.Builder(L10n.t(context, "watch_now_label")).build()
                    title = PlainComplicationText.Builder(currentPlanned.title).build()
                } else {
                    text = PlainComplicationText.Builder(fullText).build()
                    title = null
                }
            } else {
                when (state) {
                    is WearNextState.Running -> error("Handled above")
                    is WearNextState.NextUpcoming -> {
                        val shortStart = L10n.shortTime(context, state.upcoming.startsAt)
                        val nextStr = L10n.t(context, "widget.next", state.upcoming.title, shortStart)
                        title = null
                        text = PlainComplicationText.Builder(nextStr).build()
                        contentDescription = text
                    }
                    WearNextState.NothingPlanned -> {
                        val str = L10n.t(context, "watch.nothingPlanned")
                        title = null
                        text = PlainComplicationText.Builder(str).build()
                        contentDescription = text
                    }
                    WearNextState.NoTasks -> {
                        val noTasksStr = L10n.t(context, "widget.noTasks")
                        title = null
                        text = PlainComplicationText.Builder(noTasksStr).build()
                        contentDescription = text
                    }
                    WearNextState.NotConnected -> {
                        val notConnectedStr = L10n.t(context, "widget.notConnected")
                        title = null
                        text = PlainComplicationText.Builder(notConnectedStr).build()
                        contentDescription = text
                    }
                }
            }

            return when (type) {
                ComplicationType.SHORT_TEXT -> {
                    ShortTextComplicationData.Builder(text, contentDescription)
                        .setTitle(title)
                        .setMonochromaticImage(icon)
                        .setTapAction(tapAction)
                        .build()
                }
                else -> {
                    LongTextComplicationData.Builder(text, contentDescription)
                        .setTitle(title)
                        .setMonochromaticImage(icon)
                        .setTapAction(tapAction)
                        .build()
                }
            }
        }

        private fun openAppPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                REQUEST_CODE_OPEN,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
