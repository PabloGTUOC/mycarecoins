package com.carecoins.carecoins_flutter.wear

import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AlertDialog
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.Card
import androidx.wear.compose.material3.CardDefaults
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.LinearProgressIndicator
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.OutlinedButton
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TimeText
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.LastAction
import com.carecoins.quickcore.Palette
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.QuickSurfaceState
import com.carecoins.quickcore.SnapshotStore
import com.carecoins.quickcore.WearSection
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WearStore.reloadFromDisk(applicationContext)
        setContent {
            WearApp()
        }
    }

    override fun onResume() {
        super.onResume()
        WearStore.reloadFromDisk(applicationContext)
    }
}

private val WearColorScheme = ColorScheme(
    primary = Color(Palette.primary),
    onPrimary = Color.White,
    primaryContainer = Color(Palette.primaryInk),
    onPrimaryContainer = Color.White,
    secondary = Color(Palette.coin),
    onSecondary = Color(Palette.ink),
    secondaryContainer = Color(Palette.coinInk),
    onSecondaryContainer = Color(Palette.coinSoft),
    tertiary = Color(Palette.success),
    onTertiary = Color.White,
    background = Color(Palette.ink),
    onBackground = Color.White,
    onSurface = Color.White,
    onSurfaceVariant = Color(Palette.inkMuted),
    error = Color(Palette.danger),
    onError = Color.White,
)

private sealed interface ConfirmDialogState {
    data class LogWhole(val started: QuickSnapshot.Upcoming) : ConfirmDialogState
    data class NotDone(val awaiting: QuickSnapshot.Upcoming) : ConfirmDialogState
    data class StartNow(val type: String, val customTitle: String = "") : ConfirmDialogState
    data class StartTask(val task: QuickSnapshot.Task) : ConfirmDialogState
}

private const val REMOTE_INPUT_KEY = "custom_title"
private const val ACTION_REMOTE_INPUT = "android.support.wearable.input.action.REMOTE_INPUT"
private const val EXTRA_REMOTE_INPUTS = "android.support.wearable.input.extra.REMOTE_INPUTS"
private const val EXTRA_TITLE = "android.support.wearable.input.extra.TITLE"

private fun createRemoteInputIntent(context: Context): Intent {
    val label = L10n.t(context, "watch.titleOptional")
    val remoteInput = RemoteInput.Builder(REMOTE_INPUT_KEY)
        .setLabel(label)
        .build()
    return Intent(ACTION_REMOTE_INPUT).apply {
        putExtra(EXTRA_REMOTE_INPUTS, arrayOf(remoteInput))
        putExtra(EXTRA_TITLE, label)
    }
}

private fun formatDurationClock(duration: Duration): String {
    val totalSeconds = duration.seconds.coerceAtLeast(0L)
    val hours = totalSeconds / 3600L
    val minutes = (totalSeconds % 3600L) / 60L
    val seconds = totalSeconds % 60L
    return if (hours > 0L) {
        String.format("%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format("%02d:%02d", minutes, seconds)
    }
}

private fun lastActionLabel(context: Context, action: LastAction): String {
    return when (action.kind) {
        LastAction.Kind.started -> L10n.t(context, "widget.started")
        LastAction.Kind.logged -> L10n.t(context, "widget.logged")
        LastAction.Kind.stopped -> L10n.t(context, "widget.stopped")
        LastAction.Kind.undone -> L10n.t(context, "widget.undone")
        LastAction.Kind.cancelled -> L10n.t(context, "widget.notDone.done")
        LastAction.Kind.failed -> action.message ?: L10n.t(context, "widget.error.generic")
    }
}

@Composable
fun WearApp() {
    val context = LocalContext.current
    val state by WearStore.state.collectAsState()
    val scope = rememberCoroutineScope()

    var nowEpochMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var dialogState by remember { mutableStateOf<ConfirmDialogState?>(null) }

    LaunchedEffect(Unit) {
        WearContextListener.readCurrentDataItemAtLaunch(context)
        WearStore.reloadFromDisk(context)
        if (WearStore.state.value.connected) {
            WearStore.refresh(context)
        }
    }

    // Tick every second while visible to drive the running elapsed timer,
    // the started task countdown & progress bar, undo window expiry, and
    // minute-boundary re-evaluation so Started flips to Confirm at endsAt.
    LaunchedEffect(Unit) {
        while (true) {
            nowEpochMillis = System.currentTimeMillis()
            delay(1_000L)
        }
    }

    val remoteInputLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        val results = result.data?.let { RemoteInput.getResultsFromIntent(it) }
        val text = results?.getCharSequence(REMOTE_INPUT_KEY)?.toString()?.trim().orEmpty()
        val current = dialogState
        if (current is ConfirmDialogState.StartNow) {
            dialogState = current.copy(customTitle = text)
        }
    }

    val now = Instant.ofEpochMilli(nowEpochMillis)
    val columnState = rememberTransformingLazyColumnState()

    MaterialTheme(colorScheme = WearColorScheme) {
        AppScaffold(
            timeText = { TimeText() },
            modifier = Modifier.background(Color(Palette.ink)),
        ) {
            ScreenScaffold(
                scrollState = columnState,
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(Palette.ink)),
            ) { contentPadding ->
                if (!state.connected) {
                    NotConnectedList(
                        context = context,
                        columnState = columnState,
                        contentPadding = contentPadding,
                    )
                } else {
                    val sections = QuickSurfaceState.wearSections(state.snapshot, now)
                    val activeLastAction = state.lastAction?.takeIf { action ->
                        action.kind != LastAction.Kind.failed &&
                            Duration.between(action.at, now).seconds in 0..SnapshotStore.UNDO_WINDOW_SECONDS
                    }
                    val canUndo = SnapshotStore.canUndo(context, now)

                    TransformingLazyColumn(
                        state = columnState,
                        contentPadding = contentPadding,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        // Error toast at the top (shown for 4s)
                        val errorText = state.error
                        if (!errorText.isNullOrEmpty()) {
                            item(key = "error_toast") {
                                Card(
                                    onClick = {},
                                    enabled = false,
                                    colors = CardDefaults.cardColors(
                                        containerColor = Color(Palette.dangerInk),
                                        contentColor = Color.White,
                                    ),
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(
                                        text = errorText,
                                        color = Color(Palette.dangerOnDark),
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        textAlign = TextAlign.Center,
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                }
                            }
                        }

                        // Last action chip with Undo while canUndo
                        if (activeLastAction != null) {
                            item(key = "last_action_chip") {
                                LastActionChip(
                                    context = context,
                                    action = activeLastAction,
                                    canUndo = canUndo,
                                    busy = state.busy,
                                    onUndo = {
                                        scope.launch { WearStore.undo(context) }
                                    },
                                )
                            }
                        }

                        // Sections in canonical order
                        items(sections) { section ->
                            when (section) {
                                is WearSection.Running -> {
                                    val isPending = state.pending.any { it.activityId == section.running.id }
                                    RunningSectionCard(
                                        context = context,
                                        running = section.running,
                                        now = now,
                                        isPending = isPending,
                                        busy = state.busy,
                                        onStop = {
                                            scope.launch {
                                                WearStore.stop(context, section.running.id)
                                            }
                                        },
                                    )
                                }
                                is WearSection.Started -> {
                                    val isPending = state.pending.any { it.activityId == section.started.id }
                                    StartedSectionCard(
                                        context = context,
                                        started = section.started,
                                        now = now,
                                        isPending = isPending,
                                        busy = state.busy,
                                        onDoneClick = {
                                            dialogState = ConfirmDialogState.LogWhole(section.started)
                                        },
                                    )
                                }
                                is WearSection.Confirm -> {
                                    val isPending = state.pending.any { it.activityId == section.awaiting.id }
                                    ConfirmSectionCard(
                                        context = context,
                                        awaiting = section.awaiting,
                                        isPending = isPending,
                                        busy = state.busy,
                                        onDone = {
                                            scope.launch {
                                                WearStore.finish(context, section.awaiting.id)
                                            }
                                        },
                                        onNotDoneClick = {
                                            dialogState = ConfirmDialogState.NotDone(section.awaiting)
                                        },
                                    )
                                }
                                is WearSection.Now -> {
                                    val isPendingNow = state.pending.any {
                                        it.kind == com.carecoins.quickcore.PendingAction.Kind.startNow
                                    }
                                    NowSectionView(
                                        context = context,
                                        isPending = isPendingNow,
                                        busy = state.busy,
                                        onSelectType = { type ->
                                            dialogState = ConfirmDialogState.StartNow(type = type)
                                        },
                                    )
                                }
                                is WearSection.Tasks -> {
                                    TasksSectionView(
                                        context = context,
                                        tasks = section.tasks,
                                        pending = state.pending,
                                        busy = state.busy,
                                        onStartClick = { task ->
                                            dialogState = ConfirmDialogState.StartTask(task)
                                        },
                                        onDoneClick = { task ->
                                            scope.launch {
                                                WearStore.done(context, task.id)
                                            }
                                        },
                                    )
                                }
                                is WearSection.Coins -> {
                                    CoinsSectionCard(
                                        context = context,
                                        balance = section.balance,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Confirmation dialogs
            when (val dlg = dialogState) {
                is ConfirmDialogState.LogWhole -> {
                    val endsAt = dlg.started.endsAt ?: dlg.started.startsAt.plusSeconds(15 * 60L)
                    val minutes = max(
                        1,
                        (Duration.between(dlg.started.startsAt, endsAt).seconds / 60.0).roundToInt(),
                    )
                    AlertDialog(
                        visible = true,
                        onDismissRequest = { dialogState = null },
                        title = {
                            Text(
                                text = L10n.t(context, "watch.logWhole", dlg.started.title, minutes),
                                textAlign = TextAlign.Center,
                                color = Color.White,
                            )
                        },
                        confirmButton = {
                            Button(
                                onClick = {
                                    val id = dlg.started.id
                                    dialogState = null
                                    scope.launch { WearStore.finish(context, id) }
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(Palette.success),
                                    contentColor = Color.White,
                                ),
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text(L10n.t(context, "widget.done"))
                            }
                        },
                        dismissButton = {
                            OutlinedButton(
                                onClick = { dialogState = null },
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text("×")
                            }
                        },
                    )
                }
                is ConfirmDialogState.NotDone -> {
                    AlertDialog(
                        visible = true,
                        onDismissRequest = { dialogState = null },
                        title = {
                            Text(
                                text = L10n.t(context, "watch.notDone.confirm", dlg.awaiting.title),
                                textAlign = TextAlign.Center,
                                color = Color.White,
                            )
                        },
                        confirmButton = {
                            Button(
                                onClick = {
                                    val id = dlg.awaiting.id
                                    dialogState = null
                                    scope.launch { WearStore.cancel(context, id) }
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(Palette.danger),
                                    contentColor = Color.White,
                                ),
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text(L10n.t(context, "widget.notDone"))
                            }
                        },
                        dismissButton = {
                            OutlinedButton(
                                onClick = { dialogState = null },
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text("×")
                            }
                        },
                    )
                }
                is ConfirmDialogState.StartNow -> {
                    val defaultTitleKey = if (dlg.type == "household") {
                        "widget.title.household"
                    } else {
                        "widget.title.care"
                    }
                    val headerTitle = L10n.t(context, defaultTitleKey)
                    val optionalLabel = dlg.customTitle.ifEmpty { L10n.t(context, "watch.titleOptional") }
                    AlertDialog(
                        visible = true,
                        onDismissRequest = { dialogState = null },
                        title = {
                            Text(
                                text = headerTitle,
                                textAlign = TextAlign.Center,
                                color = Color.White,
                            )
                        },
                        text = {
                            OutlinedButton(
                                onClick = {
                                    runCatching {
                                        remoteInputLauncher.launch(createRemoteInputIntent(context))
                                    }
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 48.dp),
                            ) {
                                Text(
                                    text = optionalLabel,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    color = if (dlg.customTitle.isEmpty()) Color(Palette.inkMuted) else Color.White,
                                )
                            }
                        },
                        confirmButton = {
                            Button(
                                onClick = {
                                    val type = dlg.type
                                    val customTitle = dlg.customTitle
                                    dialogState = null
                                    scope.launch {
                                        WearStore.startNow(context, type = type, title = customTitle)
                                    }
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(Palette.primary),
                                    contentColor = Color.White,
                                ),
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text(L10n.t(context, "widget.start"))
                            }
                        },
                        dismissButton = {
                            OutlinedButton(
                                onClick = { dialogState = null },
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text("×")
                            }
                        },
                    )
                }
                is ConfirmDialogState.StartTask -> {
                    val endInstant = now.plusSeconds(dlg.task.durationMinutes * 60L)
                    val rangeText = L10n.t(
                        context,
                        "watch.addsToCalendar",
                        L10n.shortTime(context, now),
                        L10n.shortTime(context, endInstant),
                    )
                    AlertDialog(
                        visible = true,
                        onDismissRequest = { dialogState = null },
                        title = {
                            Text(
                                text = dlg.task.title,
                                textAlign = TextAlign.Center,
                                color = Color.White,
                            )
                        },
                        text = {
                            Text(
                                text = rangeText,
                                textAlign = TextAlign.Center,
                                color = Color(Palette.inkMuted),
                                fontSize = 12.sp,
                            )
                        },
                        confirmButton = {
                            Button(
                                onClick = {
                                    val taskId = dlg.task.id
                                    dialogState = null
                                    scope.launch { WearStore.start(context, taskId) }
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(Palette.primary),
                                    contentColor = Color.White,
                                ),
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text(L10n.t(context, "widget.start"))
                            }
                        },
                        dismissButton = {
                            OutlinedButton(
                                onClick = { dialogState = null },
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) {
                                Text("×")
                            }
                        },
                    )
                }
                null -> Unit
            }
        }
    }
}

@Composable
private fun NotConnectedList(
    context: Context,
    columnState: androidx.wear.compose.foundation.lazy.TransformingLazyColumnState,
    contentPadding: PaddingValues,
) {
    TransformingLazyColumn(
        state = columnState,
        contentPadding = contentPadding,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        item(key = "connect_title") {
            Text(
                text = L10n.t(context, "watch.connect.title"),
                color = Color.White,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp),
            )
        }
        item(key = "connect_body") {
            Text(
                text = L10n.t(context, "watch.connect.body"),
                color = Color(Palette.inkMuted),
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp),
            )
        }
    }
}

@Composable
private fun LastActionChip(
    context: Context,
    action: LastAction,
    canUndo: Boolean,
    busy: Boolean,
    onUndo: () -> Unit,
) {
    Card(
        onClick = {},
        enabled = false,
        colors = CardDefaults.cardColors(
            containerColor = Color(Palette.primaryInk),
            contentColor = Color.White,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = lastActionLabel(context, action),
                color = Color(Palette.successOnDark),
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (canUndo) {
                FilledTonalButton(
                    onClick = onUndo,
                    enabled = !busy,
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = Color(Palette.primary),
                        contentColor = Color.White,
                    ),
                    modifier = Modifier
                        .padding(start = 6.dp)
                        .heightIn(min = 48.dp),
                ) {
                    Text(
                        text = L10n.t(context, "widget.undo"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

@Composable
private fun RunningSectionCard(
    context: Context,
    running: QuickSnapshot.Running,
    now: Instant,
    isPending: Boolean,
    busy: Boolean,
    onStop: () -> Unit,
) {
    val elapsed = Duration.between(running.startedAt, now).coerceAtLeast(Duration.ZERO)
    Card(
        onClick = {},
        enabled = false,
        colors = CardDefaults.cardColors(
            containerColor = Color(Palette.dangerInk).copy(alpha = 0.35f),
            contentColor = Color.White,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = running.title,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = formatDurationClock(elapsed),
                color = Color(Palette.dangerOnDark),
                fontSize = 18.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
            )
            if (isPending) {
                Text(
                    text = L10n.t(context, "watch.pending"),
                    color = Color(Palette.warning),
                    fontSize = 12.sp,
                )
            }
            Button(
                onClick = onStop,
                enabled = !busy,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(Palette.danger),
                    contentColor = Color.White,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp),
            ) {
                Text(
                    text = L10n.t(context, "widget.stop"),
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun StartedSectionCard(
    context: Context,
    started: QuickSnapshot.Upcoming,
    now: Instant,
    isPending: Boolean,
    busy: Boolean,
    onDoneClick: () -> Unit,
) {
    val endsAt = started.endsAt ?: started.startsAt.plusSeconds(15 * 60L)
    val remaining = Duration.between(now, endsAt).coerceAtLeast(Duration.ZERO)
    val totalMillis = Duration.between(started.startsAt, endsAt).toMillis().coerceAtLeast(1L)
    val elapsedMillis = Duration.between(started.startsAt, now).toMillis().coerceIn(0L, totalMillis)
    val progress = (elapsedMillis.toFloat() / totalMillis.toFloat()).coerceIn(0f, 1f)

    Card(
        onClick = {},
        enabled = false,
        colors = CardDefaults.cardColors(
            containerColor = Color(Palette.successInk).copy(alpha = 0.35f),
            contentColor = Color.White,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = started.title,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = formatDurationClock(remaining),
                color = Color(Palette.successOnDark),
                fontSize = 18.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
            )
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp),
            )
            Text(
                text = L10n.t(context, "widget.until", L10n.shortTime(context, endsAt)),
                color = Color(Palette.inkMuted),
                fontSize = 12.sp,
            )
            if (isPending) {
                Text(
                    text = L10n.t(context, "watch.pending"),
                    color = Color(Palette.warning),
                    fontSize = 12.sp,
                )
            }
            Button(
                onClick = onDoneClick,
                enabled = !busy,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(Palette.success),
                    contentColor = Color.White,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .semantics {
                        contentDescription = L10n.t(context, "widget.a11y.done", started.title)
                    },
            ) {
                Text(
                    text = L10n.t(context, "widget.done"),
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun ConfirmSectionCard(
    context: Context,
    awaiting: QuickSnapshot.Upcoming,
    isPending: Boolean,
    busy: Boolean,
    onDone: () -> Unit,
    onNotDoneClick: () -> Unit,
) {
    Card(
        onClick = {},
        enabled = false,
        colors = CardDefaults.cardColors(
            containerColor = Color(Palette.primaryInk).copy(alpha = 0.4f),
            contentColor = Color.White,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = L10n.t(context, "widget.didYouFinish", awaiting.title),
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (isPending) {
                Text(
                    text = L10n.t(context, "watch.pending"),
                    color = Color(Palette.warning),
                    fontSize = 12.sp,
                )
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Button(
                    onClick = onDone,
                    enabled = !busy,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(Palette.success),
                        contentColor = Color.White,
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp),
                ) {
                    Text(
                        text = L10n.t(context, "widget.done"),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                OutlinedButton(
                    onClick = onNotDoneClick,
                    enabled = !busy,
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp),
                ) {
                    Text(
                        text = L10n.t(context, "widget.notDone"),
                        color = Color(Palette.dangerOnDark),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun NowSectionView(
    context: Context,
    isPending: Boolean,
    busy: Boolean,
    onSelectType: (String) -> Unit,
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        ListHeader(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = L10n.t(context, "watch.now"),
                color = Color(Palette.inkMuted),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (isPending) {
            Text(
                text = L10n.t(context, "watch.pending"),
                color = Color(Palette.warning),
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            FilledTonalButton(
                onClick = { onSelectType("care") },
                enabled = !busy,
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = Color(Palette.primaryInk),
                    contentColor = Color.White,
                ),
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 48.dp),
            ) {
                Text(
                    text = L10n.t(context, "widget.careNow"),
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            FilledTonalButton(
                onClick = { onSelectType("household") },
                enabled = !busy,
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = Color(Palette.primaryInk),
                    contentColor = Color.White,
                ),
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 48.dp),
            ) {
                Text(
                    text = L10n.t(context, "widget.householdNow"),
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun TasksSectionView(
    context: Context,
    tasks: List<QuickSnapshot.Task>,
    pending: List<com.carecoins.quickcore.PendingAction>,
    busy: Boolean,
    onStartClick: (QuickSnapshot.Task) -> Unit,
    onDoneClick: (QuickSnapshot.Task) -> Unit,
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        ListHeader(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = L10n.t(context, "watch.tasks"),
                color = Color(Palette.inkMuted),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        for (task in tasks) {
            val isPending = pending.any { it.taskId == task.id }
            Card(
                onClick = {},
                enabled = false,
                colors = CardDefaults.cardColors(
                    containerColor = Color(Palette.textPrimary),
                    contentColor = Color.White,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = task.title,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "${task.durationMinutes} min",
                            color = Color(Palette.inkMuted),
                            fontSize = 12.sp,
                        )
                        Text(
                            text = "•",
                            color = Color(Palette.inkMuted),
                            fontSize = 12.sp,
                        )
                        Text(
                            text = L10n.t(context, "watch.coins", task.coinValue),
                            color = Color(Palette.coin),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    if (isPending) {
                        Text(
                            text = L10n.t(context, "watch.pending"),
                            color = Color(Palette.warning),
                            fontSize = 12.sp,
                        )
                    }
                    Spacer(modifier = Modifier.height(2.dp))
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Button(
                            onClick = { onStartClick(task) },
                            enabled = !busy,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color(Palette.primary),
                                contentColor = Color.White,
                            ),
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 48.dp)
                                .semantics {
                                    contentDescription = L10n.t(
                                        context,
                                        "widget.a11y.start",
                                        task.title,
                                        task.durationMinutes,
                                    )
                                },
                        ) {
                            Text(
                                text = L10n.t(context, "widget.start"),
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Button(
                            onClick = { onDoneClick(task) },
                            enabled = !busy,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color(Palette.success),
                                contentColor = Color.White,
                            ),
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 48.dp)
                                .semantics {
                                    contentDescription = L10n.t(context, "widget.a11y.done", task.title)
                                },
                        ) {
                            Text(
                                text = L10n.t(context, "widget.done"),
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CoinsSectionCard(
    context: Context,
    balance: Int,
) {
    Card(
        onClick = {},
        enabled = false,
        colors = CardDefaults.cardColors(
            containerColor = Color(Palette.coinInk),
            contentColor = Color(Palette.coinSoft),
        ),
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = L10n.t(context, "widget.a11y.balance", balance)
            },
    ) {
        Text(
            text = L10n.t(context, "watch.coins", balance),
            color = Color(Palette.coin),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
