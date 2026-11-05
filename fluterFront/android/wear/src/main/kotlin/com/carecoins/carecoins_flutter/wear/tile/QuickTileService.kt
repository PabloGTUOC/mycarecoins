package com.carecoins.carecoins_flutter.wear.tile

import android.content.ComponentName
import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.wrap
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material3.ButtonColors
import androidx.wear.protolayout.material3.CircularProgressIndicatorDefaults
import androidx.wear.protolayout.material3.ColorScheme
import androidx.wear.protolayout.material3.MaterialScope
import androidx.wear.protolayout.material3.ProgressIndicatorColors
import androidx.wear.protolayout.material3.Typography
import androidx.wear.protolayout.material3.circularProgressIndicator
import androidx.wear.protolayout.material3.materialScope
import androidx.wear.protolayout.material3.primaryLayout
import androidx.wear.protolayout.material3.text
import androidx.wear.protolayout.material3.textEdgeButton
import androidx.wear.protolayout.modifiers.clickable
import androidx.wear.protolayout.types.LayoutColor
import androidx.wear.protolayout.types.LayoutString
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.carecoins.carecoins_flutter.wear.MainActivity
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.Palette
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.QuickSurfaceState
import com.carecoins.quickcore.SnapshotStore
import com.carecoins.quickcore.WearNextState
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.time.Duration
import java.time.Instant

class QuickTileService : TileService() {
    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> {
        val ctx = applicationContext ?: this
        val now = Instant.now()
        val snapshot = SnapshotStore.load(ctx)
        val deviceParams = requestParams.deviceConfiguration

        val timelineBuilder = TimelineBuilders.Timeline.Builder()
        val defaultLayout = buildTileLayout(
            context = ctx,
            deviceParameters = deviceParams,
            snapshot = snapshot,
            atTime = now,
        )
        timelineBuilder.addTimelineEntry(
            TimelineBuilders.TimelineEntry.fromLayoutElement(defaultLayout),
        )

        val instants = QuickSurfaceState.nextTimelineInstants(snapshot, now)
        for (i in instants.indices) {
            val start = instants[i]
            val end = if (i + 1 < instants.size) {
                instants[i + 1]
            } else {
                start.plusSeconds(DEFAULT_LAST_ENTRY_DURATION_SECONDS)
            }
            if (!start.isBefore(end)) continue
            val entryLayout = buildTileLayout(
                context = ctx,
                deviceParameters = deviceParams,
                snapshot = snapshot,
                atTime = start,
            )
            val interval = TimelineBuilders.TimeInterval.Builder()
                .setStartMillis(start.toEpochMilli())
                .setEndMillis(end.toEpochMilli())
                .build()
            val entry = TimelineBuilders.TimelineEntry.Builder()
                .setValidity(interval)
                .setLayout(LayoutElementBuilders.Layout.fromLayoutElement(entryLayout))
                .build()
            timelineBuilder.addTimelineEntry(entry)
        }

        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setFreshnessIntervalMillis(FRESHNESS_INTERVAL_MILLIS)
            .setTileTimeline(timelineBuilder.build())
            .build()
        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val resources = ResourceBuilders.Resources.Builder()
            .setVersion(RESOURCES_VERSION)
            .build()
        return Futures.immediateFuture(resources)
    }

    companion object {
        private const val RESOURCES_VERSION = "1"
        const val FRESHNESS_INTERVAL_MILLIS = 15 * 60_000L
        private const val DEFAULT_LAST_ENTRY_DURATION_SECONDS = 2 * 3600L

        private val TileColorScheme = ColorScheme(
            primary = LayoutColor(Palette.primary.toInt()),
            onPrimary = LayoutColor(0xFFFFFFFF.toInt()),
            primaryContainer = LayoutColor(Palette.primaryInk.toInt()),
            onPrimaryContainer = LayoutColor(0xFFFFFFFF.toInt()),
            secondary = LayoutColor(Palette.coin.toInt()),
            onSecondary = LayoutColor(Palette.ink.toInt()),
            secondaryContainer = LayoutColor(Palette.coinInk.toInt()),
            onSecondaryContainer = LayoutColor(Palette.coinSoft.toInt()),
            tertiary = LayoutColor(Palette.success.toInt()),
            onTertiary = LayoutColor(0xFFFFFFFF.toInt()),
            tertiaryContainer = LayoutColor(Palette.successInk.toInt()),
            onTertiaryContainer = LayoutColor(0xFFFFFFFF.toInt()),
            background = LayoutColor(Palette.ink.toInt()),
            onBackground = LayoutColor(0xFFFFFFFF.toInt()),
            onSurface = LayoutColor(0xFFFFFFFF.toInt()),
            onSurfaceVariant = LayoutColor(Palette.inkMuted.toInt()),
            error = LayoutColor(Palette.danger.toInt()),
            onError = LayoutColor(0xFFFFFFFF.toInt()),
        )

        fun buildTileLayout(
            context: Context,
            deviceParameters: DeviceParametersBuilders.DeviceParameters,
            snapshot: QuickSnapshot?,
            atTime: Instant,
        ): LayoutElementBuilders.LayoutElement {
            val state = QuickSurfaceState.pickNext(
                snapshot = snapshot,
                now = atTime,
                connected = snapshot != null,
            )
            val openClickable = clickable(openAppAction(context))

            return materialScope(
                context = context,
                deviceConfiguration = deviceParameters,
                allowDynamicTheme = false,
                defaultColorScheme = TileColorScheme,
            ) {
                primaryLayout(
                    titleSlot = if (snapshot != null) {
                        { buildBalancePill(context, snapshot.balance) }
                    } else {
                        null
                    },
                    mainSlot = {
                        buildMainSlot(
                            context = context,
                            state = state,
                            atTime = atTime,
                        )
                    },
                    bottomSlot = {
                        buildBottomButton(
                            context = context,
                            state = state,
                        )
                    },
                    onClick = openClickable,
                )
            }
        }

        private fun MaterialScope.buildBalancePill(
            context: Context,
            balance: Int,
        ): LayoutElementBuilders.LayoutElement {
            val pillModifiers = ModifiersBuilders.Modifiers.Builder()
                .setBackground(
                    ModifiersBuilders.Background.Builder()
                        .setColor(ColorBuilders.argb(Palette.coinInk.toInt()))
                        .setCorner(
                            ModifiersBuilders.Corner.Builder()
                                .setRadius(dp(12f))
                                .build(),
                        )
                        .build(),
                )
                .setPadding(
                    ModifiersBuilders.Padding.Builder()
                        .setStart(dp(8f))
                        .setEnd(dp(8f))
                        .setTop(dp(2f))
                        .setBottom(dp(2f))
                        .build(),
                )
                .build()

            return LayoutElementBuilders.Box.Builder()
                .setWidth(wrap())
                .setHeight(wrap())
                .setModifiers(pillModifiers)
                .addContent(
                    text(
                        text = LayoutString(L10n.t(context, "watch.coins", balance)),
                        typography = Typography.LABEL_MEDIUM,
                        color = LayoutColor(Palette.coin.toInt()),
                        maxLines = 1,
                    ),
                )
                .build()
        }

        private fun MaterialScope.buildMainSlot(
            context: Context,
            state: WearNextState,
            atTime: Instant,
        ): LayoutElementBuilders.LayoutElement {
            return when (state) {
                is WearNextState.Running -> {
                    val sinceText = L10n.t(
                        context,
                        "android.tile.since",
                        L10n.shortTime(context, state.running.startedAt),
                    )
                    LayoutElementBuilders.Column.Builder()
                        .setWidth(wrap())
                        .setHeight(wrap())
                        .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                        .addContent(
                            text(
                                text = LayoutString(state.running.title),
                                typography = Typography.TITLE_MEDIUM,
                                color = LayoutColor(0xFFFFFFFF.toInt()),
                                maxLines = 2,
                            ),
                        )
                        .addContent(
                            LayoutElementBuilders.Spacer.Builder()
                                .setHeight(dp(4f))
                                .build(),
                        )
                        .addContent(
                            text(
                                text = LayoutString(sinceText),
                                typography = Typography.BODY_SMALL,
                                color = LayoutColor(Palette.dangerOnDark.toInt()),
                                maxLines = 1,
                            ),
                        )
                        .build()
                }
                is WearNextState.Started -> {
                    val totalMillis = Duration.between(state.started.startsAt, state.endsAt)
                        .toMillis()
                        .coerceAtLeast(1L)
                    val elapsedMillis = Duration.between(state.started.startsAt, atTime)
                        .toMillis()
                        .coerceIn(0L, totalMillis)
                    val progress = (elapsedMillis.toFloat() / totalMillis.toFloat()).coerceIn(0f, 1f)
                    val untilText = L10n.t(
                        context,
                        "widget.until",
                        L10n.shortTime(context, state.endsAt),
                    )
                    val progressColors = ProgressIndicatorColors(
                        indicatorColor = LayoutColor(Palette.successOnDark.toInt()),
                        trackColor = LayoutColor(Palette.successInk.toInt()),
                    )

                    LayoutElementBuilders.Row.Builder()
                        .setWidth(wrap())
                        .setHeight(wrap())
                        .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
                        .addContent(
                            circularProgressIndicator(
                                staticProgress = progress,
                                strokeWidth = CircularProgressIndicatorDefaults.SMALL_STROKE_WIDTH,
                                colors = progressColors,
                                size = dp(32f),
                            ),
                        )
                        .addContent(
                            LayoutElementBuilders.Spacer.Builder()
                                .setWidth(dp(8f))
                                .build(),
                        )
                        .addContent(
                            LayoutElementBuilders.Column.Builder()
                                .setWidth(wrap())
                                .setHeight(wrap())
                                .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
                                .addContent(
                                    text(
                                        text = LayoutString(state.started.title),
                                        typography = Typography.TITLE_SMALL,
                                        color = LayoutColor(0xFFFFFFFF.toInt()),
                                        maxLines = 2,
                                    ),
                                )
                                .addContent(
                                    text(
                                        text = LayoutString(untilText),
                                        typography = Typography.BODY_EXTRA_SMALL,
                                        color = LayoutColor(Palette.successOnDark.toInt()),
                                        maxLines = 1,
                                    ),
                                )
                                .build(),
                        )
                        .build()
                }
                is WearNextState.Confirm -> {
                    val prompt = L10n.t(context, "widget.didYouFinish", state.awaiting.title)
                    text(
                        text = LayoutString(prompt),
                        typography = Typography.TITLE_SMALL,
                        color = LayoutColor(0xFFFFFFFF.toInt()),
                        maxLines = 3,
                    )
                }
                is WearNextState.NextUpcoming -> {
                    val nextStr = L10n.t(
                        context,
                        "widget.next",
                        state.upcoming.title,
                        L10n.shortTime(context, state.upcoming.startsAt),
                    )
                    text(
                        text = LayoutString(nextStr),
                        typography = Typography.TITLE_SMALL,
                        color = LayoutColor(0xFFFFFFFF.toInt()),
                        maxLines = 3,
                    )
                }
                WearNextState.NoTasks -> {
                    text(
                        text = LayoutString(L10n.t(context, "widget.noTasks")),
                        typography = Typography.BODY_MEDIUM,
                        color = LayoutColor(Palette.inkMuted.toInt()),
                        maxLines = 3,
                    )
                }
                WearNextState.NotConnected -> {
                    text(
                        text = LayoutString(L10n.t(context, "watch.connect.title")),
                        typography = Typography.TITLE_SMALL,
                        color = LayoutColor(0xFFFFFFFF.toInt()),
                        maxLines = 3,
                    )
                }
            }
        }

        private fun MaterialScope.buildBottomButton(
            context: Context,
            state: WearNextState,
        ): LayoutElementBuilders.LayoutElement {
            val opensApp = state is WearNextState.Running ||
                state is WearNextState.Started ||
                state is WearNextState.Confirm ||
                state is WearNextState.NotConnected

            return if (opensApp) {
                textEdgeButton(
                    onClick = clickable(openAppAction(context)),
                    colors = ButtonColors(
                        containerColor = LayoutColor(Palette.primaryInk.toInt()),
                        labelColor = LayoutColor(0xFFFFFFFF.toInt()),
                    ),
                ) {
                    text(
                        text = LayoutString(L10n.t(context, "watch.reminder.open")),
                        maxLines = 1,
                    )
                }
            } else {
                textEdgeButton(
                    onClick = clickable(careNowAction(context)),
                    colors = ButtonColors(
                        containerColor = LayoutColor(Palette.primary.toInt()),
                        labelColor = LayoutColor(0xFFFFFFFF.toInt()),
                    ),
                ) {
                    text(
                        text = LayoutString(L10n.t(context, "widget.careNow")),
                        maxLines = 1,
                    )
                }
            }
        }

        private fun openAppAction(context: Context): ActionBuilders.LaunchAction {
            return ActionBuilders.launchAction(
                ComponentName(context, MainActivity::class.java),
            )
        }

        private fun careNowAction(context: Context): ActionBuilders.LaunchAction {
            return ActionBuilders.launchAction(
                ComponentName(context, MainActivity::class.java),
                mapOf(
                    MainActivity.EXTRA_START_NOW_TYPE to ActionBuilders.stringExtra("care"),
                ),
            )
        }
    }
}
