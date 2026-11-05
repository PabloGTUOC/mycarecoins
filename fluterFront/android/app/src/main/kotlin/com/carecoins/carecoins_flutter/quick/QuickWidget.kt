package com.carecoins.carecoins_flutter.quick

import android.content.Context
import android.os.SystemClock
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.carecoins.carecoins_flutter.MainActivity
import com.carecoins.carecoins_flutter.R
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.LastAction
import com.carecoins.quickcore.Palette
import com.carecoins.quickcore.QuickBannerState
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.QuickSurfaceState
import com.carecoins.quickcore.SnapshotStore
import java.time.Instant

val QuickTaskIdParam = ActionParameters.Key<String>("taskId")
val QuickActivityIdParam = ActionParameters.Key<String>("activityId")
val QuickTypeParam = ActionParameters.Key<String>("type")
val QuickClientRefParam = ActionParameters.Key<String>("clientRef")

class StartTaskActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val taskId = parameters[QuickTaskIdParam] ?: return
        QuickActions.start(context, taskId)
    }
}

class DoneTaskActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val taskId = parameters[QuickTaskIdParam].orEmpty()
        QuickActions.done(context, taskId)
    }
}

class FinishTaskActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val activityId = parameters[QuickActivityIdParam] ?: return
        QuickActions.finish(context, activityId)
    }
}

class CancelTaskActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val activityId = parameters[QuickActivityIdParam] ?: return
        QuickActions.cancel(context, activityId)
    }
}

class StartNowActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val type = parameters[QuickTypeParam] ?: "care"
        QuickActions.startNow(context, type)
    }
}

class StopTaskActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val activityId = parameters[QuickActivityIdParam] ?: return
        QuickActions.stop(context, activityId)
    }
}

class UndoActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val clientRef = parameters[QuickClientRefParam]
        QuickActions.undo(context, clientRef)
    }
}

class QuickWidget : GlanceAppWidget() {
    companion object {
        val SMALL_SIZE = DpSize(110.dp, 110.dp)
        val SMALL_TALL_SIZE = DpSize(180.dp, 220.dp)
        val MEDIUM_SIZE = DpSize(250.dp, 110.dp)
        val LARGE_SIZE = DpSize(250.dp, 250.dp)

        fun toElapsedRealtimeBase(instant: Instant, now: Instant = Instant.now()): Long {
            val deltaMillis = instant.toEpochMilli() - now.toEpochMilli()
            return SystemClock.elapsedRealtime() + deltaMillis
        }
    }

    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(SMALL_SIZE, SMALL_TALL_SIZE, MEDIUM_SIZE, LARGE_SIZE),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val appCtx = context.applicationContext ?: context
        QuickRefresh.ensureWired()

        provideContent {
            val version by SnapshotStore.version.collectAsState()
            val connected = remember(version) { DeviceKeyStore.isConnected(appCtx) }
            val snapshot = remember(version, connected) {
                if (connected) SnapshotStore.load(appCtx) else null
            }
            val now = remember(version) { Instant.now() }
            val lastAction = remember(version, connected, now) {
                if (connected) SnapshotStore.lastAction(appCtx, now) else null
            }
            val canUndo = remember(version, connected, now) {
                if (connected) SnapshotStore.canUndo(appCtx, now) else false
            }

            WidgetContent(
                context = appCtx,
                connected = connected,
                snapshot = snapshot,
                now = now,
                lastAction = lastAction,
                canUndo = canUndo,
            )
        }
    }
}

private object WidgetColors {
    val surface = ColorProvider(
        day = Color(Palette.widgetBackground(false)),
        night = Color(Palette.widgetBackground(true)),
    )
    val textPrimary = ColorProvider(
        day = Color(Palette.widgetText(false)),
        night = Color(Palette.widgetText(true)),
    )
    val textSecondary = ColorProvider(
        day = Color(Palette.widgetSecondaryText(false)),
        night = Color(Palette.widgetSecondaryText(true)),
    )
    val primary = ColorProvider(Color(Palette.primary))
    val primarySoft = ColorProvider(Color(Palette.primarySoft))
    val primaryInk = ColorProvider(Color(Palette.primaryInk))
    val success = ColorProvider(Color(Palette.success))
    val successSoft = ColorProvider(Color(Palette.successSoft))
    val successInk = ColorProvider(Color(Palette.successInk))
    val warningSoft = ColorProvider(Color(Palette.warningSoft))
    val danger = ColorProvider(Color(Palette.danger))
    val dangerSoft = ColorProvider(Color(Palette.dangerSoft))
    val dangerInk = ColorProvider(Color(Palette.dangerInk))
    val coin = ColorProvider(Color(Palette.coin))
    val coinSoft = ColorProvider(Color(Palette.coinSoft))
    val coinInk = ColorProvider(Color(Palette.coinInk))
    val white = ColorProvider(Color.White)
}

@Composable
private fun WidgetContent(
    context: Context,
    connected: Boolean,
    snapshot: QuickSnapshot?,
    now: Instant,
    lastAction: LastAction?,
    canUndo: Boolean,
) {
    val size = LocalSize.current
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .cornerRadius(16.dp)
            .background(WidgetColors.surface)
            .padding(10.dp),
    ) {
        if (!connected) {
            NotConnectedContent(context)
        } else if (snapshot == null) {
            EmptyTasksContent(context)
        } else {
            val isSmall = size.width < MEDIUM_SIZE_THRESHOLD_WIDTH
            val isLarge = size.height >= LARGE_SIZE_THRESHOLD_HEIGHT
            when {
                isSmall -> SmallWidgetContent(context, snapshot, now, lastAction, canUndo)
                isLarge -> LargeWidgetContent(context, snapshot, now, lastAction, canUndo)
                else -> MediumWidgetContent(context, snapshot, now, lastAction, canUndo)
            }
        }
    }
}

private val MEDIUM_SIZE_THRESHOLD_WIDTH = 200.dp
private val LARGE_SIZE_THRESHOLD_HEIGHT = 200.dp

@Composable
private fun NotConnectedContent(context: Context) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .clickable(actionStartActivity<MainActivity>()),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = L10n.t(context, "widget.notConnected"),
            style = TextStyle(
                color = WidgetColors.primary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

@Composable
private fun EmptyTasksContent(context: Context) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .clickable(actionStartActivity<MainActivity>()),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = L10n.t(context, "widget.noTasks"),
            style = TextStyle(
                color = WidgetColors.textSecondary,
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

@Composable
private fun BalancePill(context: Context, balance: Int) {
    val a11yLabel = L10n.t(context, "widget.a11y.balance", balance)
    Row(
        modifier = GlanceModifier
            .cornerRadius(999.dp)
            .background(WidgetColors.coinSoft)
            .padding(horizontal = 8.dp, vertical = 2.dp)
            .semantics { contentDescription = a11yLabel },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "$balance",
            style = TextStyle(
                color = WidgetColors.coinInk,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
        Spacer(modifier = GlanceModifier.width(4.dp))
        Box(
            modifier = GlanceModifier
                .size(6.dp)
                .cornerRadius(3.dp)
                .background(WidgetColors.coin),
        ) {}
    }
}

@Composable
private fun HeaderBar(context: Context, snapshot: QuickSnapshot) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BalancePill(context, snapshot.balance)
        Spacer(modifier = GlanceModifier.defaultWeight())
        if (snapshot.needsYou > 0) {
            Text(
                text = L10n.t(context, "widget.needsYou", snapshot.needsYou),
                style = TextStyle(
                    color = WidgetColors.textSecondary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
        } else if (snapshot.family.name.isNotEmpty()) {
            Text(
                text = snapshot.family.name,
                style = TextStyle(
                    color = WidgetColors.textSecondary,
                    fontSize = 11.sp,
                ),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun BannerSlot(
    context: Context,
    banner: QuickBannerState,
    now: Instant,
    isSmall: Boolean,
) {
    when (banner) {
        is QuickBannerState.Running -> RunningBannerView(context, banner.running, now)
        is QuickBannerState.Started -> StartedBannerView(context, banner.started, now, isSmall)
        is QuickBannerState.Confirm -> ConfirmBannerView(context, banner.awaiting, isSmall)
        is QuickBannerState.None -> Unit
    }
}

@Composable
private fun RunningBannerView(
    context: Context,
    running: QuickSnapshot.Running,
    now: Instant,
) {
    val base = QuickWidget.toElapsedRealtimeBase(running.startedAt, now)
    val remoteViews = RemoteViews(context.packageName, R.layout.quick_widget_chronometer_up).apply {
        setChronometer(R.id.quick_chronometer, base, null, true)
    }

    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .cornerRadius(10.dp)
            .background(WidgetColors.dangerSoft)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = L10n.t(context, "widget.running", running.title),
                style = TextStyle(
                    color = WidgetColors.textPrimary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            AndroidRemoteViews(remoteViews = remoteViews)
        }
        Spacer(modifier = GlanceModifier.width(6.dp))
        CapsuleButton(
            text = L10n.t(context, "widget.stop"),
            textColor = WidgetColors.white,
            bgColor = WidgetColors.danger,
            a11y = L10n.t(context, "widget.stop"),
            onClick = actionRunCallback<StopTaskActionCallback>(
                actionParametersOf(QuickActivityIdParam to running.id),
            ),
        )
    }
}

@Composable
private fun StartedBannerView(
    context: Context,
    started: QuickSnapshot.Upcoming,
    now: Instant,
    isSmall: Boolean,
) {
    val endsAt = started.endsAt ?: started.startsAt.plusSeconds(15 * 60L)
    val base = QuickWidget.toElapsedRealtimeBase(endsAt, now)
    val remoteViews = RemoteViews(context.packageName, R.layout.quick_widget_chronometer_countdown).apply {
        setChronometerCountDown(R.id.quick_chronometer_countdown, true)
        setChronometer(R.id.quick_chronometer_countdown, base, null, true)
    }
    val untilText = L10n.t(context, "widget.until", L10n.shortTime(context, endsAt))

    if (isSmall) {
        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .cornerRadius(10.dp)
                .background(WidgetColors.successSoft)
                .padding(8.dp),
        ) {
            Text(
                text = started.title,
                style = TextStyle(
                    color = WidgetColors.textPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AndroidRemoteViews(remoteViews = remoteViews)
                Spacer(modifier = GlanceModifier.width(4.dp))
                Text(
                    text = untilText,
                    style = TextStyle(
                        color = WidgetColors.textSecondary,
                        fontSize = 10.sp,
                    ),
                    maxLines = 1,
                )
            }
            Spacer(modifier = GlanceModifier.height(4.dp))
            CapsuleButton(
                text = L10n.t(context, "widget.done"),
                textColor = WidgetColors.white,
                bgColor = WidgetColors.success,
                a11y = L10n.t(context, "widget.a11y.done", started.title),
                fillWidth = true,
                onClick = actionRunCallback<FinishTaskActionCallback>(
                    actionParametersOf(QuickActivityIdParam to started.id),
                ),
            )
        }
    } else {
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .cornerRadius(10.dp)
                .background(WidgetColors.successSoft)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = started.title,
                        style = TextStyle(
                            color = WidgetColors.textPrimary,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        maxLines = 1,
                    )
                    Spacer(modifier = GlanceModifier.width(6.dp))
                    Text(
                        text = untilText,
                        style = TextStyle(
                            color = WidgetColors.textSecondary,
                            fontSize = 10.sp,
                        ),
                        maxLines = 1,
                    )
                }
                AndroidRemoteViews(remoteViews = remoteViews)
            }
            Spacer(modifier = GlanceModifier.width(6.dp))
            CapsuleButton(
                text = L10n.t(context, "widget.done"),
                textColor = WidgetColors.white,
                bgColor = WidgetColors.success,
                a11y = L10n.t(context, "widget.a11y.done", started.title),
                onClick = actionRunCallback<FinishTaskActionCallback>(
                    actionParametersOf(QuickActivityIdParam to started.id),
                ),
            )
        }
    }
}

@Composable
private fun ConfirmBannerView(
    context: Context,
    awaiting: QuickSnapshot.Upcoming,
    isSmall: Boolean,
) {
    val prompt = L10n.t(context, "widget.didYouFinish", awaiting.title)
    if (isSmall) {
        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .cornerRadius(10.dp)
                .background(WidgetColors.warningSoft)
                .padding(8.dp),
        ) {
            Text(
                text = prompt,
                style = TextStyle(
                    color = WidgetColors.textPrimary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 2,
            )
            Spacer(modifier = GlanceModifier.height(6.dp))
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(modifier = GlanceModifier.defaultWeight()) {
                    CapsuleButton(
                        text = L10n.t(context, "widget.done"),
                        textColor = WidgetColors.white,
                        bgColor = WidgetColors.success,
                        a11y = L10n.t(context, "widget.a11y.done", awaiting.title),
                        fillWidth = true,
                        onClick = actionRunCallback<FinishTaskActionCallback>(
                            actionParametersOf(QuickActivityIdParam to awaiting.id),
                        ),
                    )
                }
                Spacer(modifier = GlanceModifier.width(6.dp))
                Box(modifier = GlanceModifier.defaultWeight()) {
                    OutlinedDangerButton(
                        text = L10n.t(context, "widget.notDone"),
                        fillWidth = true,
                        onClick = actionRunCallback<CancelTaskActionCallback>(
                            actionParametersOf(QuickActivityIdParam to awaiting.id),
                        ),
                    )
                }
            }
        }
    } else {
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .cornerRadius(10.dp)
                .background(WidgetColors.warningSoft)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = prompt,
                modifier = GlanceModifier.defaultWeight(),
                style = TextStyle(
                    color = WidgetColors.textPrimary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            Spacer(modifier = GlanceModifier.width(6.dp))
            CapsuleButton(
                text = L10n.t(context, "widget.done"),
                textColor = WidgetColors.white,
                bgColor = WidgetColors.success,
                a11y = L10n.t(context, "widget.a11y.done", awaiting.title),
                onClick = actionRunCallback<FinishTaskActionCallback>(
                    actionParametersOf(QuickActivityIdParam to awaiting.id),
                ),
            )
            Spacer(modifier = GlanceModifier.width(6.dp))
            OutlinedDangerButton(
                text = L10n.t(context, "widget.notDone"),
                onClick = actionRunCallback<CancelTaskActionCallback>(
                    actionParametersOf(QuickActivityIdParam to awaiting.id),
                ),
            )
        }
    }
}

@Composable
private fun TaskRowView(context: Context, task: QuickSnapshot.Task) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = GlanceModifier.defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = task.title,
                style = TextStyle(
                    color = WidgetColors.textPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
            Spacer(modifier = GlanceModifier.width(4.dp))
            Text(
                text = "${task.durationMinutes} min",
                style = TextStyle(
                    color = WidgetColors.textSecondary,
                    fontSize = 10.sp,
                ),
                maxLines = 1,
            )
        }
        Spacer(modifier = GlanceModifier.width(6.dp))
        CapsuleButton(
            text = L10n.t(context, "widget.start"),
            textColor = WidgetColors.white,
            bgColor = WidgetColors.primary,
            a11y = L10n.t(context, "widget.a11y.start", task.title, task.durationMinutes),
            onClick = actionRunCallback<StartTaskActionCallback>(
                actionParametersOf(QuickTaskIdParam to task.id),
            ),
        )
        Spacer(modifier = GlanceModifier.width(6.dp))
        CapsuleButton(
            text = L10n.t(context, "widget.done"),
            textColor = WidgetColors.primaryInk,
            bgColor = WidgetColors.primarySoft,
            a11y = L10n.t(context, "widget.a11y.done", task.title),
            onClick = actionRunCallback<DoneTaskActionCallback>(
                actionParametersOf(QuickTaskIdParam to task.id),
            ),
        )
    }
}

@Composable
private fun NowButtonsRowView(context: Context) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = GlanceModifier.defaultWeight()) {
            OutlinedPrimaryButton(
                text = L10n.t(context, "widget.careNow"),
                fillWidth = true,
                onClick = actionRunCallback<StartNowActionCallback>(
                    actionParametersOf(QuickTypeParam to "care"),
                ),
            )
        }
        Spacer(modifier = GlanceModifier.width(8.dp))
        Box(modifier = GlanceModifier.defaultWeight()) {
            OutlinedPrimaryButton(
                text = L10n.t(context, "widget.householdNow"),
                fillWidth = true,
                onClick = actionRunCallback<StartNowActionCallback>(
                    actionParametersOf(QuickTypeParam to "household"),
                ),
            )
        }
    }
}

@Composable
private fun FeedbackChipView(
    context: Context,
    action: LastAction,
    canUndo: Boolean,
) {
    val isFailure = action.kind == LastAction.Kind.failed
    val chipText = when (action.kind) {
        LastAction.Kind.started -> L10n.t(context, "widget.started")
        LastAction.Kind.logged -> L10n.t(context, "widget.logged")
        LastAction.Kind.stopped -> L10n.t(context, "widget.stopped")
        LastAction.Kind.undone -> L10n.t(context, "widget.undone")
        LastAction.Kind.cancelled -> L10n.t(context, "widget.notDone.done")
        LastAction.Kind.failed -> action.message ?: L10n.t(context, "widget.error.generic")
    }
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .cornerRadius(10.dp)
            .background(if (isFailure) WidgetColors.dangerSoft else WidgetColors.successSoft)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = chipText,
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(
                color = if (isFailure) WidgetColors.dangerInk else WidgetColors.successInk,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        val ref = action.clientRef
        if (canUndo && !ref.isNullOrEmpty()) {
            Spacer(modifier = GlanceModifier.width(6.dp))
            CapsuleButton(
                text = L10n.t(context, "widget.undo"),
                textColor = WidgetColors.primary,
                bgColor = WidgetColors.white,
                a11y = L10n.t(context, "widget.undo"),
                onClick = actionRunCallback<UndoActionCallback>(
                    actionParametersOf(QuickClientRefParam to ref),
                ),
            )
        }
    }
}

@Composable
private fun CapsuleButton(
    text: String,
    textColor: ColorProvider,
    bgColor: ColorProvider,
    a11y: String,
    fillWidth: Boolean = false,
    compact: Boolean = false,
    onClick: androidx.glance.action.Action,
) {
    val baseModifier = if (fillWidth) {
        GlanceModifier.fillMaxWidth()
    } else {
        GlanceModifier
    }
    Box(
        modifier = baseModifier
            .cornerRadius(999.dp)
            .background(bgColor)
            .clickable(onClick)
            .padding(
                horizontal = if (compact) 8.dp else 10.dp,
                vertical = if (compact) 3.dp else 4.dp,
            )
            .semantics { contentDescription = a11y },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = TextStyle(
                color = textColor,
                fontSize = if (compact) 10.sp else 11.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            ),
            maxLines = 1,
        )
    }
}

private val SMALL_ROW_DONE_MIN_WIDTH = 160.dp

@Composable
private fun SmallTaskRowView(
    context: Context,
    task: QuickSnapshot.Task,
    showDone: Boolean,
) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = task.title,
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(
                color = WidgetColors.textPrimary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
        Spacer(modifier = GlanceModifier.width(4.dp))
        CapsuleButton(
            text = L10n.t(context, "widget.start"),
            textColor = WidgetColors.white,
            bgColor = WidgetColors.primary,
            a11y = L10n.t(context, "widget.a11y.start", task.title, task.durationMinutes),
            compact = true,
            onClick = actionRunCallback<StartTaskActionCallback>(
                actionParametersOf(QuickTaskIdParam to task.id),
            ),
        )
        if (showDone) {
            Spacer(modifier = GlanceModifier.width(4.dp))
            CapsuleButton(
                text = L10n.t(context, "widget.done"),
                textColor = WidgetColors.primaryInk,
                bgColor = WidgetColors.primarySoft,
                a11y = L10n.t(context, "widget.a11y.done", task.title),
                compact = true,
                onClick = actionRunCallback<DoneTaskActionCallback>(
                    actionParametersOf(QuickTaskIdParam to task.id),
                ),
            )
        }
    }
}

@Composable
private fun OutlinedDangerButton(
    text: String,
    fillWidth: Boolean = false,
    onClick: androidx.glance.action.Action,
) {
    val baseModifier = if (fillWidth) {
        GlanceModifier.fillMaxWidth()
    } else {
        GlanceModifier
    }
    Box(
        modifier = baseModifier
            .background(ImageProvider(R.drawable.bg_capsule_outlined_danger))
            .clickable(onClick)
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .semantics { contentDescription = text },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = TextStyle(
                color = WidgetColors.danger,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            ),
            maxLines = 1,
        )
    }
}

@Composable
private fun OutlinedPrimaryButton(
    text: String,
    fillWidth: Boolean = false,
    onClick: androidx.glance.action.Action,
) {
    val baseModifier = if (fillWidth) {
        GlanceModifier.fillMaxWidth()
    } else {
        GlanceModifier
    }
    Box(
        modifier = baseModifier
            .background(ImageProvider(R.drawable.bg_capsule_outlined_primary))
            .clickable(onClick)
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .semantics { contentDescription = text },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = TextStyle(
                color = WidgetColors.primary,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
            ),
            maxLines = 1,
        )
    }
}

@Composable
private fun SmallWidgetContent(
    context: Context,
    snapshot: QuickSnapshot,
    now: Instant,
    lastAction: LastAction?,
    canUndo: Boolean,
) {
    val size = LocalSize.current
    val rowCount = QuickSurfaceState.smallLayoutRowCount(size.height.value)
    val banner = QuickSurfaceState.pickBanner(snapshot, now)
    val isFailureChip = lastAction?.kind == LastAction.Kind.failed

    Column(modifier = GlanceModifier.fillMaxSize()) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Spacer(modifier = GlanceModifier.defaultWeight())
            BalancePill(context, snapshot.balance)
        }
        Spacer(modifier = GlanceModifier.height(6.dp))

        if (rowCount > 1) {
            val hasBanner = banner != QuickBannerState.None
            if (hasBanner) {
                BannerSlot(context, banner, now, isSmall = true)
                Spacer(modifier = GlanceModifier.height(4.dp))
            }
            if (lastAction != null && !isFailureChip) {
                FeedbackChipView(context, lastAction, canUndo)
                Spacer(modifier = GlanceModifier.height(4.dp))
            }
            if (lastAction != null && isFailureChip) {
                FeedbackChipView(context, lastAction, canUndo)
            } else {
                val visibleTasks = snapshot.tasks.take(rowCount)
                if (visibleTasks.isEmpty() && !hasBanner) {
                    Text(
                        text = L10n.t(context, "widget.noTasks"),
                        style = TextStyle(
                            color = WidgetColors.textSecondary,
                            fontSize = 11.sp,
                        ),
                    )
                } else {
                    val showDone = size.width >= SMALL_ROW_DONE_MIN_WIDTH
                    for (task in visibleTasks) {
                        SmallTaskRowView(context, task, showDone = showDone)
                    }
                }
            }
        } else if (banner != QuickBannerState.None) {
            BannerSlot(context, banner, now, isSmall = true)
            if (lastAction != null) {
                Spacer(modifier = GlanceModifier.height(4.dp))
                FeedbackChipView(context, lastAction, canUndo)
            }
        } else {
            val topTask = snapshot.tasks.firstOrNull()
            if (topTask != null) {
                if (lastAction != null && !isFailureChip) {
                    FeedbackChipView(context, lastAction, canUndo)
                    Spacer(modifier = GlanceModifier.height(4.dp))
                }
                Text(
                    text = topTask.title,
                    style = TextStyle(
                        color = WidgetColors.textPrimary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    maxLines = if (lastAction != null && !isFailureChip) 1 else 2,
                )
                Spacer(modifier = GlanceModifier.height(if (lastAction != null && !isFailureChip) 4.dp else 6.dp))
                if (lastAction != null && isFailureChip) {
                    FeedbackChipView(context, lastAction, canUndo)
                } else {
                    Row(
                        modifier = GlanceModifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(modifier = GlanceModifier.defaultWeight()) {
                            CapsuleButton(
                                text = L10n.t(context, "widget.start"),
                                textColor = WidgetColors.white,
                                bgColor = WidgetColors.primary,
                                a11y = L10n.t(context, "widget.a11y.start", topTask.title, topTask.durationMinutes),
                                fillWidth = true,
                                onClick = actionRunCallback<StartTaskActionCallback>(
                                    actionParametersOf(QuickTaskIdParam to topTask.id),
                                ),
                            )
                        }
                        Spacer(modifier = GlanceModifier.width(6.dp))
                        Box(modifier = GlanceModifier.defaultWeight()) {
                            CapsuleButton(
                                text = L10n.t(context, "widget.done"),
                                textColor = WidgetColors.primaryInk,
                                bgColor = WidgetColors.primarySoft,
                                a11y = L10n.t(context, "widget.a11y.done", topTask.title),
                                fillWidth = true,
                                onClick = actionRunCallback<DoneTaskActionCallback>(
                                    actionParametersOf(QuickTaskIdParam to topTask.id),
                                ),
                            )
                        }
                    }
                }
            } else if (lastAction != null) {
                FeedbackChipView(context, lastAction, canUndo)
            } else {
                Text(
                    text = L10n.t(context, "widget.noTasks"),
                    style = TextStyle(
                        color = WidgetColors.textSecondary,
                        fontSize = 11.sp,
                    ),
                )
            }
        }
    }
}

@Composable
private fun MediumWidgetContent(
    context: Context,
    snapshot: QuickSnapshot,
    now: Instant,
    lastAction: LastAction?,
    canUndo: Boolean,
) {
    val banner = QuickSurfaceState.pickBanner(snapshot, now)
    val hasBanner = banner != QuickBannerState.None
    val visibleTasks = snapshot.tasks.take(2)

    Column(modifier = GlanceModifier.fillMaxSize()) {
        HeaderBar(context, snapshot)
        Spacer(modifier = GlanceModifier.height(4.dp))

        if (hasBanner) {
            BannerSlot(context, banner, now, isSmall = false)
        } else if (lastAction != null) {
            FeedbackChipView(context, lastAction, canUndo)
        } else {
            NowButtonsRowView(context)
        }

        Spacer(modifier = GlanceModifier.height(4.dp))

        if (visibleTasks.isEmpty() && !hasBanner) {
            Text(
                text = L10n.t(context, "widget.noTasks"),
                style = TextStyle(
                    color = WidgetColors.textSecondary,
                    fontSize = 11.sp,
                ),
                maxLines = 1,
            )
        } else {
            for (task in visibleTasks) {
                TaskRowView(context, task)
            }
        }

        if (hasBanner && lastAction != null) {
            Spacer(modifier = GlanceModifier.height(4.dp))
            FeedbackChipView(context, lastAction, canUndo)
        }
    }
}

@Composable
private fun LargeWidgetContent(
    context: Context,
    snapshot: QuickSnapshot,
    now: Instant,
    lastAction: LastAction?,
    canUndo: Boolean,
) {
    val banner = QuickSurfaceState.pickBanner(snapshot, now)
    val hasBanner = banner != QuickBannerState.None
    val visibleTasks = snapshot.tasks.take(6)

    Column(modifier = GlanceModifier.fillMaxSize()) {
        HeaderBar(context, snapshot)
        Spacer(modifier = GlanceModifier.height(4.dp))

        if (hasBanner) {
            BannerSlot(context, banner, now, isSmall = false)
            Spacer(modifier = GlanceModifier.height(4.dp))
        }

        NowButtonsRowView(context)
        Spacer(modifier = GlanceModifier.height(4.dp))

        if (visibleTasks.isEmpty() && !hasBanner) {
            Text(
                text = L10n.t(context, "widget.noTasks"),
                style = TextStyle(
                    color = WidgetColors.textSecondary,
                    fontSize = 11.sp,
                ),
                maxLines = 1,
            )
        } else {
            for (task in visibleTasks) {
                TaskRowView(context, task)
            }
        }

        Spacer(modifier = GlanceModifier.defaultWeight())

        if (lastAction != null) {
            FeedbackChipView(context, lastAction, canUndo)
        } else {
            val next = snapshot.nextUpcoming(now)
            if (next != null) {
                Text(
                    text = L10n.t(
                        context,
                        "widget.next",
                        next.title,
                        L10n.shortTime(context, next.startsAt),
                    ),
                    style = TextStyle(
                        color = WidgetColors.textSecondary,
                        fontSize = 11.sp,
                    ),
                    maxLines = 1,
                )
            }
        }
    }
}
