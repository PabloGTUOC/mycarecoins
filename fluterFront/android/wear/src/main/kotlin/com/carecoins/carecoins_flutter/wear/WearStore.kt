package com.carecoins.carecoins_flutter.wear

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.LastAction
import com.carecoins.quickcore.PendingAction
import com.carecoins.quickcore.PendingActionQueue
import com.carecoins.quickcore.QuickApi
import com.carecoins.quickcore.QuickApiException
import com.carecoins.quickcore.QuickCore
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.SnapshotStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.concurrent.TimeUnit

data class WearState(
    val connected: Boolean = false,
    val snapshot: QuickSnapshot? = null,
    val lastAction: LastAction? = null,
    val pending: List<PendingAction> = emptyList(),
    val busy: Boolean = false,
    val error: String? = null,
)

object WearStore {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val refreshMutex = Mutex()
    private var errorClearJob: Job? = null

    private val _state = MutableStateFlow(WearState())
    val state: StateFlow<WearState> = _state.asStateFlow()

    fun reloadFromDisk(context: Context, now: Instant = Instant.now()) {
        val appCtx = context.applicationContext ?: context
        val connected = QuickApi.fromStore(appCtx) != null
        val snapshot = if (connected) SnapshotStore.load(appCtx) else null
        val lastAction = if (connected) SnapshotStore.lastAction(appCtx, now) else null
        val pending = if (connected) PendingActionQueue.load(appCtx, now) else emptyList()
        _state.update { current ->
            current.copy(
                connected = connected,
                snapshot = snapshot,
                lastAction = lastAction,
                pending = pending,
            )
        }
    }

    fun onContextChanged(context: Context) {
        val appCtx = context.applicationContext ?: context
        reloadFromDisk(appCtx)
        if (_state.value.connected) {
            WearRefreshWorker.schedule(appCtx)
            scope.launch {
                refresh(appCtx)
            }
        } else {
            WearHooks.cancelReminders(appCtx)
            WearRefreshWorker.cancel(appCtx)
            WearHooks.onSnapshot(appCtx)
        }
    }

    fun errorMessage(context: Context, error: Throwable): String {
        if (error is QuickApiException) {
            return when {
                error.code == "scheduleOverlap" -> {
                    val title = error.params["title"].orEmpty()
                    L10n.t(context, "widget.error.overlap", title)
                }
                error.code == "quickTaskAlreadyRunning" -> {
                    val title = error.params["title"].orEmpty()
                    L10n.t(context, "widget.error.alreadyRunning", title)
                }
                error.code == "quickUndoExpired" -> {
                    L10n.t(context, "widget.error.undoExpired")
                }
                error.code == "quickCancelRunning" -> {
                    L10n.t(context, "widget.error.cancelRunning")
                }
                error.status == 401 -> {
                    L10n.t(context, "widget.error.revoked")
                }
                else -> {
                    L10n.t(context, "widget.error.generic")
                }
            }
        }
        return L10n.t(context, "widget.error.generic")
    }

    private fun vibrate(context: Context, effectId: Int) {
        runCatching {
            val vibrator = context.getSystemService(Vibrator::class.java)
            vibrator?.vibrate(VibrationEffect.createPredefined(effectId))
        }
    }

    fun hapticSuccess(context: Context) {
        vibrate(context, VibrationEffect.EFFECT_CLICK)
    }

    fun hapticFailure(context: Context) {
        vibrate(context, VibrationEffect.EFFECT_DOUBLE_CLICK)
    }

    private fun showErrorToast(message: String) {
        errorClearJob?.cancel()
        _state.update { it.copy(error = message) }
        errorClearJob = scope.launch {
            delay(4_000L)
            _state.update { current ->
                if (current.error == message) current.copy(error = null) else current
            }
        }
    }

    private fun recordAction(context: Context, action: LastAction) {
        val appCtx = context.applicationContext ?: context
        SnapshotStore.recordAction(appCtx, action)
        _state.update { it.copy(lastAction = action) }
        val msg = action.message
        if (action.kind == LastAction.Kind.failed && !msg.isNullOrEmpty()) {
            showErrorToast(msg)
        }
    }

    private fun handleUnauthorized(context: Context) {
        val appCtx = context.applicationContext ?: context
        QuickCore.disconnectLocally(appCtx)
        WearHooks.cancelReminders(appCtx)
        WearRefreshWorker.cancel(appCtx)
        reloadFromDisk(appCtx)
        WearHooks.onSnapshot(appCtx)
    }

    private fun enqueuePending(context: Context, action: PendingAction) {
        val appCtx = context.applicationContext ?: context
        val updated = PendingActionQueue.enqueue(appCtx, action)
        _state.update { it.copy(pending = updated) }
    }

    suspend fun refresh(context: Context) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        refreshMutex.withLock {
            val api = QuickApi.fromStore(appCtx)
            if (api == null) {
                handleUnauthorized(appCtx)
                return@withLock
            }
            _state.update { it.copy(busy = true) }
            try {
                val (_, rawJson) = api.snapshot()
                SnapshotStore.save(appCtx, rawJson)
                val flushedAny = flushQueueInternal(appCtx, api)
                if (flushedAny) {
                    val (_, refreshedRaw) = api.snapshot()
                    SnapshotStore.save(appCtx, refreshedRaw)
                }
                reloadFromDisk(appCtx)
                WearRefreshWorker.schedule(appCtx)
                WearHooks.onSnapshot(appCtx)
            } catch (e: QuickApiException) {
                if (e.status == 401) {
                    handleUnauthorized(appCtx)
                } else {
                    reloadFromDisk(appCtx)
                }
            } catch (_: Throwable) {
                reloadFromDisk(appCtx)
            } finally {
                _state.update { it.copy(busy = false) }
            }
        }
    }

    private suspend fun flushQueueInternal(context: Context, api: QuickApi): Boolean {
        var queue = PendingActionQueue.load(context).toMutableList()
        if (queue.isEmpty()) return false
        var flushedAny = false

        while (queue.isNotEmpty()) {
            val item = queue.first()
            try {
                when (item.kind) {
                    PendingAction.Kind.start -> {
                        val taskId = item.taskId
                        if (taskId.isNullOrEmpty()) {
                            queue.removeAt(0)
                            PendingActionQueue.save(context, queue)
                            continue
                        }
                        val res = api.start(templateId = taskId, clientRef = item.clientRef)
                        recordAction(
                            context,
                            LastAction(
                                kind = LastAction.Kind.started,
                                taskId = taskId,
                                activityId = res.activity?.id,
                                clientRef = item.clientRef,
                            ),
                        )
                    }
                    PendingAction.Kind.done -> {
                        val taskId = item.taskId
                        if (taskId.isNullOrEmpty()) {
                            queue.removeAt(0)
                            PendingActionQueue.save(context, queue)
                            continue
                        }
                        api.done(templateId = taskId, clientRef = item.clientRef)
                        recordAction(
                            context,
                            LastAction(
                                kind = LastAction.Kind.logged,
                                taskId = taskId,
                                clientRef = item.clientRef,
                            ),
                        )
                    }
                    PendingAction.Kind.finish -> {
                        val activityId = item.activityId
                        if (activityId.isNullOrEmpty()) {
                            queue.removeAt(0)
                            PendingActionQueue.save(context, queue)
                            continue
                        }
                        api.finish(activityId = activityId)
                        recordAction(
                            context,
                            LastAction(
                                kind = LastAction.Kind.logged,
                                activityId = activityId,
                            ),
                        )
                    }
                    PendingAction.Kind.cancel -> {
                        val activityId = item.activityId
                        if (activityId.isNullOrEmpty()) {
                            queue.removeAt(0)
                            PendingActionQueue.save(context, queue)
                            continue
                        }
                        api.cancel(activityId = activityId)
                        recordAction(
                            context,
                            LastAction(
                                kind = LastAction.Kind.cancelled,
                                activityId = activityId,
                            ),
                        )
                    }
                    PendingAction.Kind.startNow -> {
                        val type = item.type ?: "care"
                        val titleKey = if (type == "household") "widget.title.household" else "widget.title.care"
                        val title = item.title?.takeIf { it.isNotBlank() } ?: L10n.t(context, titleKey)
                        val res = api.startNow(type = type, title = title, clientRef = item.clientRef)
                        recordAction(
                            context,
                            LastAction(
                                kind = LastAction.Kind.started,
                                activityId = res.activity?.id,
                                clientRef = item.clientRef,
                            ),
                        )
                    }
                    PendingAction.Kind.stop -> {
                        val activityId = item.activityId
                        if (activityId.isNullOrEmpty()) {
                            queue.removeAt(0)
                            PendingActionQueue.save(context, queue)
                            continue
                        }
                        api.stop(activityId = activityId)
                        recordAction(
                            context,
                            LastAction(
                                kind = LastAction.Kind.stopped,
                                activityId = activityId,
                            ),
                        )
                    }
                }
                flushedAny = true
                queue.removeAt(0)
                PendingActionQueue.save(context, queue)
            } catch (e: QuickApiException) {
                if (e.status == 0) {
                    // Network error: keep remaining items in queue
                    break
                } else if (e.status == 401) {
                    throw e
                } else {
                    queue.removeAt(0)
                    PendingActionQueue.save(context, queue)
                    recordAction(
                        context,
                        LastAction(
                            kind = LastAction.Kind.failed,
                            message = errorMessage(context, e),
                        ),
                    )
                }
            } catch (t: Throwable) {
                queue.removeAt(0)
                PendingActionQueue.save(context, queue)
                recordAction(
                    context,
                    LastAction(
                        kind = LastAction.Kind.failed,
                        message = errorMessage(context, t),
                    ),
                )
            }
        }
        return flushedAny
    }

    suspend fun start(context: Context, taskId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            handleUnauthorized(appCtx)
            hapticFailure(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        _state.update { it.copy(busy = true) }
        try {
            val result = api.start(templateId = taskId, clientRef = clientRef)
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.started,
                    taskId = taskId,
                    activityId = result.activity?.id,
                    clientRef = clientRef,
                ),
            )
            hapticSuccess(appCtx)
            refresh(appCtx)
        } catch (e: QuickApiException) {
            when (e.status) {
                0 -> {
                    enqueuePending(
                        appCtx,
                        PendingAction(
                            kind = PendingAction.Kind.start,
                            taskId = taskId,
                            clientRef = clientRef,
                        ),
                    )
                }
                401 -> {
                    handleUnauthorized(appCtx)
                    hapticFailure(appCtx)
                }
                else -> {
                    recordAction(
                        appCtx,
                        LastAction(
                            kind = LastAction.Kind.failed,
                            message = errorMessage(appCtx, e),
                        ),
                    )
                    hapticFailure(appCtx)
                }
            }
        } catch (t: Throwable) {
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.failed,
                    message = errorMessage(appCtx, t),
                ),
            )
            hapticFailure(appCtx)
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }

    suspend fun done(context: Context, taskId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            handleUnauthorized(appCtx)
            hapticFailure(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        _state.update { it.copy(busy = true) }
        try {
            api.done(templateId = taskId, clientRef = clientRef)
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.logged,
                    taskId = taskId,
                    clientRef = clientRef,
                ),
            )
            hapticSuccess(appCtx)
            refresh(appCtx)
        } catch (e: QuickApiException) {
            when (e.status) {
                0 -> {
                    enqueuePending(
                        appCtx,
                        PendingAction(
                            kind = PendingAction.Kind.done,
                            taskId = taskId,
                            clientRef = clientRef,
                        ),
                    )
                }
                401 -> {
                    handleUnauthorized(appCtx)
                    hapticFailure(appCtx)
                }
                else -> {
                    recordAction(
                        appCtx,
                        LastAction(
                            kind = LastAction.Kind.failed,
                            message = errorMessage(appCtx, e),
                        ),
                    )
                    hapticFailure(appCtx)
                }
            }
        } catch (t: Throwable) {
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.failed,
                    message = errorMessage(appCtx, t),
                ),
            )
            hapticFailure(appCtx)
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }

    suspend fun finish(context: Context, activityId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            handleUnauthorized(appCtx)
            hapticFailure(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        _state.update { it.copy(busy = true) }
        try {
            api.finish(activityId = activityId)
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.logged,
                    activityId = activityId,
                ),
            )
            hapticSuccess(appCtx)
            refresh(appCtx)
        } catch (e: QuickApiException) {
            when (e.status) {
                0 -> {
                    enqueuePending(
                        appCtx,
                        PendingAction(
                            kind = PendingAction.Kind.finish,
                            activityId = activityId,
                            clientRef = clientRef,
                        ),
                    )
                }
                401 -> {
                    handleUnauthorized(appCtx)
                    hapticFailure(appCtx)
                }
                else -> {
                    recordAction(
                        appCtx,
                        LastAction(
                            kind = LastAction.Kind.failed,
                            message = errorMessage(appCtx, e),
                        ),
                    )
                    hapticFailure(appCtx)
                }
            }
        } catch (t: Throwable) {
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.failed,
                    message = errorMessage(appCtx, t),
                ),
            )
            hapticFailure(appCtx)
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }

    suspend fun cancel(context: Context, activityId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            handleUnauthorized(appCtx)
            hapticFailure(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        _state.update { it.copy(busy = true) }
        try {
            api.cancel(activityId = activityId)
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.cancelled,
                    activityId = activityId,
                ),
            )
            hapticSuccess(appCtx)
            refresh(appCtx)
        } catch (e: QuickApiException) {
            when (e.status) {
                0 -> {
                    enqueuePending(
                        appCtx,
                        PendingAction(
                            kind = PendingAction.Kind.cancel,
                            activityId = activityId,
                            clientRef = clientRef,
                        ),
                    )
                }
                401 -> {
                    handleUnauthorized(appCtx)
                    hapticFailure(appCtx)
                }
                else -> {
                    recordAction(
                        appCtx,
                        LastAction(
                            kind = LastAction.Kind.failed,
                            message = errorMessage(appCtx, e),
                        ),
                    )
                    hapticFailure(appCtx)
                }
            }
        } catch (t: Throwable) {
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.failed,
                    message = errorMessage(appCtx, t),
                ),
            )
            hapticFailure(appCtx)
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }

    suspend fun startNow(
        context: Context,
        type: String,
        title: String? = null,
    ) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            handleUnauthorized(appCtx)
            hapticFailure(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        val defaultTitleKey = if (type == "household") "widget.title.household" else "widget.title.care"
        val effectiveTitle = title?.trim().orEmpty().ifEmpty { L10n.t(appCtx, defaultTitleKey) }
        _state.update { it.copy(busy = true) }
        try {
            val result = api.startNow(type = type, title = effectiveTitle, clientRef = clientRef)
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.started,
                    activityId = result.activity?.id,
                    clientRef = clientRef,
                ),
            )
            hapticSuccess(appCtx)
            refresh(appCtx)
        } catch (e: QuickApiException) {
            when (e.status) {
                0 -> {
                    enqueuePending(
                        appCtx,
                        PendingAction(
                            kind = PendingAction.Kind.startNow,
                            type = type,
                            title = effectiveTitle,
                            clientRef = clientRef,
                        ),
                    )
                }
                401 -> {
                    handleUnauthorized(appCtx)
                    hapticFailure(appCtx)
                }
                else -> {
                    recordAction(
                        appCtx,
                        LastAction(
                            kind = LastAction.Kind.failed,
                            message = errorMessage(appCtx, e),
                        ),
                    )
                    hapticFailure(appCtx)
                }
            }
        } catch (t: Throwable) {
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.failed,
                    message = errorMessage(appCtx, t),
                ),
            )
            hapticFailure(appCtx)
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }

    suspend fun stop(context: Context, activityId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            handleUnauthorized(appCtx)
            hapticFailure(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        _state.update { it.copy(busy = true) }
        try {
            api.stop(activityId = activityId)
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.stopped,
                    activityId = activityId,
                ),
            )
            hapticSuccess(appCtx)
            refresh(appCtx)
        } catch (e: QuickApiException) {
            when (e.status) {
                0 -> {
                    enqueuePending(
                        appCtx,
                        PendingAction(
                            kind = PendingAction.Kind.stop,
                            activityId = activityId,
                            clientRef = clientRef,
                        ),
                    )
                }
                401 -> {
                    handleUnauthorized(appCtx)
                    hapticFailure(appCtx)
                }
                else -> {
                    recordAction(
                        appCtx,
                        LastAction(
                            kind = LastAction.Kind.failed,
                            message = errorMessage(appCtx, e),
                        ),
                    )
                    hapticFailure(appCtx)
                }
            }
        } catch (t: Throwable) {
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.failed,
                    message = errorMessage(appCtx, t),
                ),
            )
            hapticFailure(appCtx)
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }

    suspend fun undo(context: Context) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        if (!SnapshotStore.canUndo(appCtx)) return@withContext
        val ref = SnapshotStore.lastAction(appCtx)?.clientRef
        if (ref.isNullOrEmpty()) return@withContext
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            handleUnauthorized(appCtx)
            hapticFailure(appCtx)
            return@withContext
        }
        _state.update { it.copy(busy = true) }
        try {
            api.undo(clientRef = ref)
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.undone,
                    clientRef = ref,
                ),
            )
            hapticSuccess(appCtx)
            refresh(appCtx)
        } catch (e: QuickApiException) {
            if (e.status == 401) {
                handleUnauthorized(appCtx)
            } else {
                recordAction(
                    appCtx,
                    LastAction(
                        kind = LastAction.Kind.failed,
                        message = errorMessage(appCtx, e),
                    ),
                )
            }
            hapticFailure(appCtx)
        } catch (t: Throwable) {
            recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.failed,
                    message = errorMessage(appCtx, t),
                ),
            )
            hapticFailure(appCtx)
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }
}

class WearRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        if (!DeviceKeyStore.isConnected(applicationContext)) {
            cancel(applicationContext)
            return Result.success()
        }
        WearStore.refresh(applicationContext)
        return Result.success()
    }

    companion object {
        const val WORK_NAME = "wear-refresh-periodic"

        fun schedule(context: Context) {
            val appCtx = context.applicationContext ?: context
            runCatching {
                val request = PeriodicWorkRequestBuilder<WearRefreshWorker>(30, TimeUnit.MINUTES)
                    .build()
                WorkManager.getInstance(appCtx).enqueueUniquePeriodicWork(
                    WORK_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    request,
                )
            }
        }

        fun cancel(context: Context) {
            val appCtx = context.applicationContext ?: context
            runCatching {
                WorkManager.getInstance(appCtx).cancelUniqueWork(WORK_NAME)
            }
        }
    }
}
