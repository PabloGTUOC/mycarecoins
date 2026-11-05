package com.carecoins.carecoins_flutter.quick

import android.content.Context
import android.service.quicksettings.TileService
import android.content.ComponentName
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.carecoins.carecoins_flutter.WearSync
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.LastAction
import com.carecoins.quickcore.QuickApi
import com.carecoins.quickcore.QuickApiException
import com.carecoins.quickcore.QuickSnapshot
import com.carecoins.quickcore.SnapshotStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

object QuickActions {
    fun widgetMessage(context: Context, error: Throwable): String {
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

    suspend fun start(context: Context, templateId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = L10n.t(appCtx, "widget.error.revoked")),
            )
            QuickRefresh.updateSurfaces(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        try {
            val result = api.start(templateId = templateId, clientRef = clientRef)
            SnapshotStore.recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.started,
                    taskId = templateId,
                    activityId = result.activity?.id,
                    clientRef = clientRef,
                ),
            )
            QuickRefresh.refreshNow(appCtx)
        } catch (t: Throwable) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = widgetMessage(appCtx, t)),
            )
            QuickRefresh.updateSurfaces(appCtx)
        }
    }

    suspend fun done(context: Context, templateId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = L10n.t(appCtx, "widget.error.revoked")),
            )
            QuickRefresh.updateSurfaces(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        try {
            if (templateId.isEmpty()) {
                val title = L10n.t(appCtx, "widget.title.care")
                val result = api.startNow(type = "care", title = title, clientRef = clientRef)
                SnapshotStore.recordAction(
                    appCtx,
                    LastAction(
                        kind = LastAction.Kind.started,
                        activityId = result.activity?.id,
                        clientRef = clientRef,
                    ),
                )
            } else {
                api.done(templateId = templateId, clientRef = clientRef)
                SnapshotStore.recordAction(
                    appCtx,
                    LastAction(
                        kind = LastAction.Kind.logged,
                        taskId = templateId,
                        clientRef = clientRef,
                    ),
                )
            }
            QuickRefresh.refreshNow(appCtx)
        } catch (t: Throwable) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = widgetMessage(appCtx, t)),
            )
            QuickRefresh.updateSurfaces(appCtx)
        }
    }

    suspend fun finish(context: Context, activityId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = L10n.t(appCtx, "widget.error.revoked")),
            )
            QuickRefresh.updateSurfaces(appCtx)
            return@withContext
        }
        try {
            api.finish(activityId = activityId)
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.logged, activityId = activityId),
            )
            val refreshed = QuickRefresh.refreshNow(appCtx)
            if (refreshed == null) {
                QuickNotification.cancel(appCtx)
            }
        } catch (t: Throwable) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = widgetMessage(appCtx, t)),
            )
            QuickRefresh.updateSurfaces(appCtx)
        }
    }

    suspend fun cancel(context: Context, activityId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = L10n.t(appCtx, "widget.error.revoked")),
            )
            QuickRefresh.updateSurfaces(appCtx)
            return@withContext
        }
        try {
            api.cancel(activityId = activityId)
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.cancelled, activityId = activityId),
            )
            val refreshed = QuickRefresh.refreshNow(appCtx)
            if (refreshed == null) {
                QuickNotification.cancel(appCtx)
            }
        } catch (t: Throwable) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = widgetMessage(appCtx, t)),
            )
            QuickRefresh.updateSurfaces(appCtx)
        }
    }

    suspend fun startNow(context: Context, type: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = L10n.t(appCtx, "widget.error.revoked")),
            )
            QuickRefresh.updateSurfaces(appCtx)
            return@withContext
        }
        val clientRef = QuickApi.newClientRef()
        val titleKey = if (type == "household") "widget.title.household" else "widget.title.care"
        val title = L10n.t(appCtx, titleKey)
        try {
            val result = api.startNow(type = type, title = title, clientRef = clientRef)
            SnapshotStore.recordAction(
                appCtx,
                LastAction(
                    kind = LastAction.Kind.started,
                    activityId = result.activity?.id,
                    clientRef = clientRef,
                ),
            )
            QuickRefresh.refreshNow(appCtx)
        } catch (t: Throwable) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = widgetMessage(appCtx, t)),
            )
            QuickRefresh.updateSurfaces(appCtx)
        }
    }

    suspend fun stop(context: Context, activityId: String) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = L10n.t(appCtx, "widget.error.revoked")),
            )
            QuickRefresh.updateSurfaces(appCtx)
            return@withContext
        }
        try {
            api.stop(activityId = activityId)
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.stopped, activityId = activityId),
            )
            val refreshed = QuickRefresh.refreshNow(appCtx)
            if (refreshed == null) {
                QuickNotification.cancel(appCtx)
            }
        } catch (t: Throwable) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = widgetMessage(appCtx, t)),
            )
            QuickRefresh.updateSurfaces(appCtx)
        }
    }

    suspend fun undo(context: Context, clientRef: String? = null) = withContext(Dispatchers.IO) {
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = L10n.t(appCtx, "widget.error.revoked")),
            )
            QuickRefresh.updateSurfaces(appCtx)
            return@withContext
        }
        val ref = clientRef?.takeIf { it.isNotEmpty() }
            ?: SnapshotStore.lastAction(appCtx)?.clientRef
        if (ref.isNullOrEmpty()) {
            return@withContext
        }
        try {
            api.undo(clientRef = ref)
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.undone, clientRef = ref),
            )
            val refreshed = QuickRefresh.refreshNow(appCtx)
            if (refreshed == null) {
                QuickNotification.cancel(appCtx)
            }
        } catch (t: Throwable) {
            SnapshotStore.recordAction(
                appCtx,
                LastAction(kind = LastAction.Kind.failed, message = widgetMessage(appCtx, t)),
            )
            QuickRefresh.updateSurfaces(appCtx)
        }
    }
}

object QuickRefresh {
    const val PERIODIC_WORK_NAME = "quick-refresh-periodic"
    const val AT_END_WORK_NAME = "quick-at-end"
    private val wired = AtomicBoolean(false)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun ensureWired() {
        if (wired.compareAndSet(false, true)) {
            SnapshotStore.addOnChangedListener { ctx ->
                val appCtx = ctx.applicationContext ?: ctx
                scope.launch {
                    if (!DeviceKeyStore.isConnected(appCtx)) {
                        cancelAll(appCtx)
                    } else {
                        updateSurfaces(appCtx)
                    }
                }
            }
        }
    }

    suspend fun refreshNow(context: Context): QuickSnapshot? = withContext(Dispatchers.IO) {
        ensureWired()
        val appCtx = context.applicationContext ?: context
        val api = QuickApi.fromStore(appCtx)
        if (api == null) {
            cancelAll(appCtx)
            updateSurfaces(appCtx, null)
            return@withContext null
        }
        try {
            val (snapshot, rawJson) = api.snapshot()
            SnapshotStore.save(appCtx, rawJson)
            updateSurfaces(appCtx, snapshot)
            val key = DeviceKeyStore.read(appCtx).orEmpty()
            val apiBase = DeviceKeyStore.readApiBase(appCtx).orEmpty()
            if (key.isNotEmpty()) {
                WearSync.pushContext(
                    context = appCtx,
                    deviceKey = key,
                    apiBase = apiBase,
                    snapshot = rawJson,
                    language = L10n.getLanguage(appCtx).orEmpty(),
                )
            }
            snapshot
        } catch (e: QuickApiException) {
            if (e.status == 401) {
                cancelAll(appCtx)
                WearSync.clearContext(appCtx)
            }
            val cached = SnapshotStore.load(appCtx)
            updateSurfaces(appCtx, cached)
            null
        } catch (_: Throwable) {
            val cached = SnapshotStore.load(appCtx)
            updateSurfaces(appCtx, cached)
            null
        }
    }

    suspend fun updateSurfaces(
        context: Context,
        snapshot: QuickSnapshot? = SnapshotStore.load(context),
        now: Instant = Instant.now(),
    ) {
        val appCtx = context.applicationContext ?: context
        runCatching {
            QuickWidget().updateAll(appCtx)
        }
        runCatching {
            QuickNotification.sync(appCtx, snapshot, now)
        }
        runCatching {
            TileService.requestListeningState(
                appCtx,
                ComponentName(appCtx, CareNowTileService::class.java),
            )
        }
    }

    fun schedule(context: Context) {
        ensureWired()
        val appCtx = context.applicationContext ?: context
        runCatching {
            val request = PeriodicWorkRequestBuilder<QuickRefreshWorker>(30, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(appCtx).enqueueUniquePeriodicWork(
                PERIODIC_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }

    fun scheduleAt(context: Context, instant: Instant) {
        ensureWired()
        val appCtx = context.applicationContext ?: context
        runCatching {
            val delayMillis = Duration.between(Instant.now(), instant).toMillis().coerceAtLeast(0L)
            val request = OneTimeWorkRequestBuilder<QuickRefreshWorker>()
                .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
                .build()
            WorkManager.getInstance(appCtx).enqueueUniqueWork(
                AT_END_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }
    }

    fun cancelAll(context: Context) {
        val appCtx = context.applicationContext ?: context
        runCatching {
            val wm = WorkManager.getInstance(appCtx)
            wm.cancelUniqueWork(PERIODIC_WORK_NAME)
            wm.cancelUniqueWork(AT_END_WORK_NAME)
        }
        runCatching {
            QuickNotification.cancel(appCtx)
        }
        scope.launch {
            runCatching { QuickWidget().updateAll(appCtx) }
            runCatching {
                TileService.requestListeningState(
                    appCtx,
                    ComponentName(appCtx, CareNowTileService::class.java),
                )
            }
        }
    }
}

class QuickRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        QuickRefresh.ensureWired()
        if (!DeviceKeyStore.isConnected(applicationContext)) {
            QuickRefresh.cancelAll(applicationContext)
            return Result.success()
        }
        QuickRefresh.refreshNow(applicationContext)
        return Result.success()
    }
}
