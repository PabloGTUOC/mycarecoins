package com.carecoins.carecoins_flutter.quick

import android.content.Context
import android.os.Build
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
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.appWidgetBackground
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
import androidx.glance.unit.ColorProvider as UnitColorProvider
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
        val SMALL_TALL_SIZE = DpSize(160.dp, 180.dp)
        val MEDIUM_SIZE = DpSize(250.dp, 110.dp)
        val LARGE_SIZE = DpSize(250.dp, 250.dp)

        fun toElapsedRealtimeBase(instant: Instant, now: Instant = Instant.now()): Long {
            val deltaMillis = instant.toEpochMilli() - now.toEpochMilli()
            return SystemClock.elapsedRealtime() + deltaMillis
        }
    }

    override val sizeMode: SizeMode = SizeMode.Exact

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
    val background: UnitColorProvider = ColorProvider(
        day = Color(Palette.widgetBackground(false)),
        night = Color(Palette.widgetBackground(true)),
    )
    val tile: UnitColorProvider = ColorProvider(
        day = Color(Palette.widgetTile(false)),
        night = Color(Palette.widgetTile(true)),
    )
    val textPrimary: UnitColorProvider = ColorProvider(
        day = Color(Palette.widgetText(false)),
        night = Color(Palette.widgetText(true)),
    )
    val textSecondary: UnitColorProvider = ColorProvider(
        day = Color(Palette.widgetSecondaryText(false)),
        night = Color(Palette.widgetSecondaryText(true)),
    )
    val primary: UnitColorProvider = ColorProvider(
        day = Color(Palette.primary),
        night = Color(Palette.primary),
    )
    val primarySoft: UnitColorProvider = ColorProvider(
        day = Color(Palette.primarySoft),
        night = Color(Palette.primarySoft),
    )
    val primaryInk: UnitColorProvider = ColorProvider(
        day = Color(Palette.primaryInk),
        night = Color(Palette.primaryInk),
    )
    val success: UnitColorProvider = ColorProvider(
        day = Color(Palette.success),
        night = Color(Palette.success),
    )
    val successSoft: UnitColorProvider = ColorProvider(
        day = Color(Palette.successSoft),
        night = Color(Palette.successSoft),
    )
    val successInk: UnitColorProvider = ColorProvider(
        day = Color(Palette.successInk),
        night = Color(Palette.successInk),
    )
    val warningSoft: UnitColorProvider = ColorProvider(
        day = Color(Palette.warningSoft),
        night = Color(Palette.warningSoft),
    )
    val warningInk: UnitColorProvider = ColorProvider(
        day = Color(Palette.warningInk),
        night = Color(Palette.warningInk),
    )
    val danger: UnitColorProvider = ColorProvider(
        day = Color(Palette.danger),
        night = Color(Palette.danger),
    )
    val dangerSoft: UnitColorProvider = ColorProvider(
        day = Color(Palette.dangerSoft),
        night = Color(Palette.dangerSoft),
    )
    val dangerInk: UnitColorProvider = ColorProvider(
        day = Color(Palette.dangerInk),
        night = Color(Palette.dangerInk),
    )
    val coin: UnitColorProvider = ColorProvider(
        day = Color(Palette.coin),
        night = Color(Palette.coin),
    )
    val coinSoft: UnitColorProvider = ColorProvider(
        day = Color(Palette.coinSoft),
        night = Color(Palette.coinSoft),
    )
    val coinInk: UnitColorProvider = ColorProvider(
        day = Color(Palette.coinInk),
        night = Color(Palette.coinInk),
    )
    val white: UnitColorProvider = ColorProvider(
        day = Color.White,
        night = Color.White,
    )
    val white85: UnitColorProvider = ColorProvider(
        day = Color(0xD9FFFFFF),
        night = Color(0xD9FFFFFF),
    )
}

private fun GlanceModifier.widgetOuterCornerRadius(): GlanceModifier =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        this.cornerRadius(android.R.dimen.system_app_widget_background_radius)
    } else {
        this.cornerRadius(16.dp)
    }

private fun GlanceModifier.widgetInnerCornerRadius(): GlanceModifier =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        this.cornerRadius(android.R.dimen.system_app_widget_inner_radius)
    } else {
        this.cornerRadius(16.dp)
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
    val banner = QuickSurfaceState.pickBanner(snapshot, now)
    val hasRunning = banner is QuickBannerState.Running
    val nextUpcoming = snapshot?.nextUpcoming(now)
    val taskCount = snapshot?.tasks?.size ?: 0

    val layout = QuickSurfaceState.computeWidgetLayout(
        widthDp = size.width.value,
        heightDp = size.height.value,
        taskCount = taskCount,
        hasRunning = hasRunning,
        hasLastAction = lastAction != null,
        hasNextUpcoming = nextUpcoming != null,
    )

    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .widgetOuterCornerRadius()
            .background(WidgetColors.background)
            .padding(horizontal = 12.dp, vertical = layout.verticalPaddingDp.dp),
    ) {
        if (!connected) {
            NotConnectedContent(context)
        } else {
            ConnectedWidgetContent(
                context = context,
                snapshot = snapshot,
                banner = banner,
                now = now,
                lastAction = lastAction,
                canUndo = canUndo,
                nextUpcoming = nextUpcoming,
                layout = layout,
            )
        }
    }
}

@Composable
private fun NotConnectedContent(context: Context) {
    val openAppText = L10n.t(context, "widget.openApp")
    Box(
        modifier = GlanceModifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .widgetInnerCornerRadius()
                .background(WidgetColors.tile)
                .padding(horizontal = 12.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Image(
                provider = ImageProvider(R.drawable.ic_widget_coin),
                contentDescription = null,
                modifier = GlanceModifier.size(32.dp),
            )
            Spacer(modifier = GlanceModifier.height(8.dp))
            Text(
                text = L10n.t(context, "widget.notConnected"),
                style = TextStyle(
                    color = WidgetColors.textPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center,
                ),
            )
            Spacer(modifier = GlanceModifier.height(10.dp))
            Box(
                modifier = GlanceModifier
                    .cornerRadius(999.dp)
                    .background(WidgetColors.primary)
                    .clickable(actionStartActivity<MainActivity>())
                    .padding(horizontal = 14.dp, vertical = 6.dp)
                    .semantics { contentDescription = openAppText },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = openAppText,
                    style = TextStyle(
                        color = WidgetColors.white,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                    ),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun ConnectedWidgetContent(
    context: Context,
    snapshot: QuickSnapshot?,
    banner: QuickBannerState,
    now: Instant,
    lastAction: LastAction?,
    canUndo: Boolean,
    nextUpcoming: QuickSnapshot.Upcoming?,
    layout: com.carecoins.quickcore.QuickWidgetLayout,
) {
    val gap = layout.gapDp.dp
    val balance = snapshot?.balance ?: 0
    val needsYou = snapshot?.needsYou ?: 0
    val tasks = snapshot?.tasks.orEmpty()
    val hasRunning = banner is QuickBannerState.Running

    Column(modifier = GlanceModifier.fillMaxSize()) {
        HeaderBar(
            context = context,
            balance = balance,
            needsYou = needsYou,
            isWide = layout.isWide,
        )

        if (banner is QuickBannerState.Running) {
            Spacer(modifier = GlanceModifier.height(gap))
            RunningBannerView(context = context, running = banner.running, now = now)
        }

        if (lastAction != null) {
            Spacer(modifier = GlanceModifier.height(gap))
            FeedbackChipView(context = context, action = lastAction, canUndo = canUndo)
        }

        if (tasks.isEmpty() && !hasRunning) {
            Spacer(modifier = GlanceModifier.height(gap))
            NoTasksTile(context = context)
        } else {
            val visibleTasks = tasks.take(layout.maxTaskRows)
            for (task in visibleTasks) {
                Spacer(modifier = GlanceModifier.height(gap))
                TaskRowTile(
                    context = context,
                    task = task,
                    isWide = layout.isWide,
                    rowHeightDp = layout.rowHeightDp,
                )
            }
        }

        if (layout.showNext || layout.showFooter) {
            Spacer(modifier = GlanceModifier.defaultWeight())
        }

        if (layout.showNext && nextUpcoming != null) {
            Spacer(modifier = GlanceModifier.height(gap))
            NextUpcomingLine(context = context, next = nextUpcoming)
        }

        if (layout.showFooter) {
            Spacer(modifier = GlanceModifier.height(gap))
            FooterQuickStartRow(context = context, isWide = layout.isWide)
        }
    }
}

@Composable
private fun HeaderBar(
    context: Context,
    balance: Int,
    needsYou: Int,
    isWide: Boolean,
) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(28.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BalancePill(context = context, balance = balance)
        Spacer(modifier = GlanceModifier.defaultWeight())
        if (needsYou > 0) {
            NeedsYouIndicator(context = context, needsYou = needsYou, isWide = isWide)
        }
    }
}

@Composable
private fun BalancePill(context: Context, balance: Int) {
    val a11yLabel = L10n.t(context, "widget.a11y.balance", balance)
    Row(
        modifier = GlanceModifier
            .height(28.dp)
            .cornerRadius(999.dp)
            .background(WidgetColors.coinSoft)
            .clickable(actionStartActivity<MainActivity>())
            .padding(horizontal = 10.dp)
            .semantics { contentDescription = a11yLabel },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            provider = ImageProvider(R.drawable.ic_widget_coin),
            contentDescription = null,
            modifier = GlanceModifier.size(14.dp),
        )
        Spacer(modifier = GlanceModifier.width(5.dp))
        Text(
            text = "$balance",
            style = TextStyle(
                color = WidgetColors.coinInk,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
    }
}

@Composable
private fun NeedsYouIndicator(
    context: Context,
    needsYou: Int,
    isWide: Boolean,
) {
    val label = L10n.t(context, "widget.needsYou", needsYou)
    if (isWide) {
        Box(
            modifier = GlanceModifier
                .height(28.dp)
                .cornerRadius(999.dp)
                .background(WidgetColors.primarySoft)
                .clickable(actionStartActivity<MainActivity>())
                .padding(horizontal = 10.dp)
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = label,
                style = TextStyle(
                    color = WidgetColors.primaryInk,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        }
    } else {
        Box(
            modifier = GlanceModifier
                .size(20.dp)
                .cornerRadius(10.dp)
                .background(WidgetColors.primary)
                .clickable(actionStartActivity<MainActivity>())
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "$needsYou",
                style = TextStyle(
                    color = WidgetColors.white,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                ),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun TaskRowTile(
    context: Context,
    task: QuickSnapshot.Task,
    isWide: Boolean,
    rowHeightDp: Int,
) {
    val isHousehold = task.type.equals("household", ignoreCase = true)
    val btnSize = if (isWide) 36.dp else 32.dp
    val btnRadius = if (isWide) 18.dp else 16.dp
    val glyphSize = if (isWide) 18.dp else 16.dp
    val startA11y = L10n.t(context, "widget.a11y.start", task.title, task.durationMinutes)
    val doneA11y = L10n.t(context, "widget.a11y.done", task.title)

    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(rowHeightDp.dp)
            .widgetInnerCornerRadius()
            .background(WidgetColors.tile)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isWide) {
            val circleFill = if (isHousehold) WidgetColors.warningSoft else WidgetColors.primarySoft
            val glyphTint = if (isHousehold) WidgetColors.warningInk else WidgetColors.primaryInk
            val iconRes = if (isHousehold) R.drawable.ic_widget_household else R.drawable.ic_widget_care
            Box(
                modifier = GlanceModifier
                    .size(32.dp)
                    .cornerRadius(16.dp)
                    .background(circleFill),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    provider = ImageProvider(iconRes),
                    contentDescription = null,
                    modifier = GlanceModifier.size(18.dp),
                    colorFilter = ColorFilter.tint(glyphTint),
                )
            }
            Spacer(modifier = GlanceModifier.width(10.dp))
        }

        Column(
            modifier = GlanceModifier.defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = task.title,
                style = TextStyle(
                    color = WidgetColors.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
            Text(
                text = L10n.t(context, "widget.row.meta", task.durationMinutes, task.coinValue),
                style = TextStyle(
                    color = WidgetColors.textSecondary,
                    fontSize = 12.sp,
                ),
                maxLines = 1,
            )
        }

        Spacer(modifier = GlanceModifier.width(6.dp))

        CircleIconButton(
            size = btnSize,
            radius = btnRadius,
            glyphSize = glyphSize,
            iconRes = R.drawable.ic_widget_play,
            bgColor = WidgetColors.primary,
            tintColor = WidgetColors.white,
            a11y = startA11y,
            onClick = actionRunCallback<StartTaskActionCallback>(
                actionParametersOf(QuickTaskIdParam to task.id),
            ),
        )

        Spacer(modifier = GlanceModifier.width(6.dp))

        CircleIconButton(
            size = btnSize,
            radius = btnRadius,
            glyphSize = glyphSize,
            iconRes = R.drawable.ic_widget_check,
            bgColor = WidgetColors.successSoft,
            tintColor = WidgetColors.successInk,
            a11y = doneA11y,
            onClick = actionRunCallback<DoneTaskActionCallback>(
                actionParametersOf(QuickTaskIdParam to task.id),
            ),
        )
    }
}

@Composable
private fun CircleIconButton(
    size: androidx.compose.ui.unit.Dp,
    radius: androidx.compose.ui.unit.Dp,
    glyphSize: androidx.compose.ui.unit.Dp,
    iconRes: Int,
    bgColor: UnitColorProvider,
    tintColor: UnitColorProvider,
    a11y: String,
    onClick: Action,
) {
    Box(
        modifier = GlanceModifier
            .size(size)
            .cornerRadius(radius)
            .background(bgColor)
            .clickable(onClick)
            .semantics { contentDescription = a11y },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            provider = ImageProvider(iconRes),
            contentDescription = a11y,
            modifier = GlanceModifier.size(glyphSize),
            colorFilter = ColorFilter.tint(tintColor),
        )
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
    val isHousehold = running.type.equals("household", ignoreCase = true)
    val categoryTitle = if (isHousehold) {
        L10n.t(context, "widget.title.household")
    } else if (running.type.equals("care", ignoreCase = true) || running.title.isBlank()) {
        L10n.t(context, "widget.title.care")
    } else {
        running.title
    }
    val firstLine = L10n.t(context, "widget.running.label", categoryTitle)
    val stopLabel = L10n.t(context, "widget.stop")

    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(64.dp)
            .widgetInnerCornerRadius()
            .background(WidgetColors.primary)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = GlanceModifier.defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = firstLine,
                style = TextStyle(
                    color = WidgetColors.white85,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            AndroidRemoteViews(remoteViews = remoteViews)
        }
        Spacer(modifier = GlanceModifier.width(8.dp))
        Row(
            modifier = GlanceModifier
                .height(36.dp)
                .cornerRadius(999.dp)
                .background(WidgetColors.white)
                .clickable(
                    actionRunCallback<StopTaskActionCallback>(
                        actionParametersOf(QuickActivityIdParam to running.id),
                    ),
                )
                .padding(horizontal = 12.dp)
                .semantics { contentDescription = stopLabel },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(
                provider = ImageProvider(R.drawable.ic_widget_stop),
                contentDescription = null,
                modifier = GlanceModifier.size(16.dp),
                colorFilter = ColorFilter.tint(WidgetColors.primaryInk),
            )
            Spacer(modifier = GlanceModifier.width(4.dp))
            Text(
                text = stopLabel,
                style = TextStyle(
                    color = WidgetColors.primaryInk,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
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
        LastAction.Kind.failed -> action.message ?: L10n.t(context, "widget.error.generic")
    }
    val bgColor = if (isFailure) WidgetColors.dangerSoft else WidgetColors.successSoft
    val inkColor = if (isFailure) WidgetColors.dangerInk else WidgetColors.successInk
    val undoLabel = L10n.t(context, "widget.undo")

    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(30.dp)
            .cornerRadius(999.dp)
            .background(bgColor)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            provider = ImageProvider(R.drawable.ic_widget_check),
            contentDescription = null,
            modifier = GlanceModifier.size(14.dp),
            colorFilter = ColorFilter.tint(inkColor),
        )
        Spacer(modifier = GlanceModifier.width(6.dp))
        Text(
            text = chipText,
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(
                color = inkColor,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        val ref = action.clientRef
        if (canUndo && !ref.isNullOrEmpty()) {
            Spacer(modifier = GlanceModifier.width(6.dp))
            Text(
                text = undoLabel,
                modifier = GlanceModifier
                    .clickable(
                        actionRunCallback<UndoActionCallback>(
                            actionParametersOf(QuickClientRefParam to ref),
                        ),
                    )
                    .padding(horizontal = 4.dp, vertical = 2.dp)
                    .semantics { contentDescription = undoLabel },
                style = TextStyle(
                    color = WidgetColors.primaryInk,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun NoTasksTile(context: Context) {
    Box(
        modifier = GlanceModifier
            .fillMaxWidth()
            .widgetInnerCornerRadius()
            .background(WidgetColors.tile)
            .clickable(actionStartActivity<MainActivity>())
            .padding(horizontal = 12.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = L10n.t(context, "widget.noTasks"),
            style = TextStyle(
                color = WidgetColors.textSecondary,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

@Composable
private fun NextUpcomingLine(
    context: Context,
    next: QuickSnapshot.Upcoming,
) {
    Text(
        text = L10n.t(
            context,
            "widget.next",
            next.title,
            L10n.shortTime(context, next.startsAt),
        ),
        style = TextStyle(
            color = WidgetColors.textSecondary,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
        ),
        maxLines = 1,
    )
}

@Composable
private fun FooterQuickStartRow(
    context: Context,
    isWide: Boolean,
) {
    val careLabel = L10n.t(context, "widget.careNow")
    if (isWide) {
        val householdLabel = L10n.t(context, "widget.householdNow")
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(40.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(modifier = GlanceModifier.defaultWeight()) {
                TonalPillButton(
                    text = careLabel,
                    iconRes = R.drawable.ic_widget_care_add,
                    bgColor = WidgetColors.primarySoft,
                    inkColor = WidgetColors.primaryInk,
                    onClick = actionRunCallback<StartNowActionCallback>(
                        actionParametersOf(QuickTypeParam to "care"),
                    ),
                )
            }
            Spacer(modifier = GlanceModifier.width(6.dp))
            Box(modifier = GlanceModifier.defaultWeight()) {
                TonalPillButton(
                    text = householdLabel,
                    iconRes = R.drawable.ic_widget_household,
                    bgColor = WidgetColors.warningSoft,
                    inkColor = WidgetColors.warningInk,
                    onClick = actionRunCallback<StartNowActionCallback>(
                        actionParametersOf(QuickTypeParam to "household"),
                    ),
                )
            }
        }
    } else {
        TonalPillButton(
            text = careLabel,
            iconRes = R.drawable.ic_widget_care_add,
            bgColor = WidgetColors.primarySoft,
            inkColor = WidgetColors.primaryInk,
            onClick = actionRunCallback<StartNowActionCallback>(
                actionParametersOf(QuickTypeParam to "care"),
            ),
        )
    }
}

@Composable
private fun TonalPillButton(
    text: String,
    iconRes: Int,
    bgColor: UnitColorProvider,
    inkColor: UnitColorProvider,
    onClick: Action,
) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(40.dp)
            .cornerRadius(999.dp)
            .background(bgColor)
            .clickable(onClick)
            .padding(horizontal = 12.dp)
            .semantics { contentDescription = text },
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            provider = ImageProvider(iconRes),
            contentDescription = null,
            modifier = GlanceModifier.size(18.dp),
            colorFilter = ColorFilter.tint(inkColor),
        )
        Spacer(modifier = GlanceModifier.width(6.dp))
        Text(
            text = text,
            style = TextStyle(
                color = inkColor,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            ),
            maxLines = 1,
        )
    }
}
