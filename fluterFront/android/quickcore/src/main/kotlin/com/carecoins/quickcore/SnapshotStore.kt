package com.carecoins.quickcore

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

object SnapshotStore {
    const val SNAPSHOT_FILE = QuickCore.SNAPSHOT_FILE
    const val LAST_ACTION_FILE = QuickCore.LAST_ACTION_FILE
    const val UNDO_WINDOW_SECONDS = 30L
    private const val UNDO_WINDOW_MILLIS = 30_000L

    private val versionCounter = AtomicLong(0L)
    private val _version = MutableStateFlow(0L)
    val version: StateFlow<Long> = _version.asStateFlow()

    fun bumpVersion(): Long {
        val next = versionCounter.incrementAndGet()
        _version.value = next
        return next
    }

    val listeners = CopyOnWriteArrayList<(Context) -> Unit>()
    val actionListeners = CopyOnWriteArrayList<(Context, LastAction) -> Unit>()
    private var onChangedCallback: ((Context) -> Unit)? = null

    var onChanged: (Context) -> Unit
        get() = { context ->
            bumpVersion()
            runCatching { onChangedCallback?.invoke(context) }
            for (listener in listeners) {
                runCatching { listener(context) }
            }
        }
        set(value) {
            onChangedCallback = value
        }

    fun addOnChangedListener(listener: (Context) -> Unit) {
        listeners.add(listener)
    }

    fun removeOnChangedListener(listener: (Context) -> Unit) {
        listeners.remove(listener)
    }

    fun addOnActionRecordedListener(listener: (Context, LastAction) -> Unit) {
        actionListeners.add(listener)
    }

    fun removeOnActionRecordedListener(listener: (Context, LastAction) -> Unit) {
        actionListeners.remove(listener)
    }

    internal var fallbackFilesDir: File by lazyFallbackDir()

    private fun lazyFallbackDir(): kotlin.properties.ReadWriteProperty<Any?, File> =
        object : kotlin.properties.ReadWriteProperty<Any?, File> {
            private var dir: File? = null
            override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): File {
                val existing = dir
                if (existing != null) return existing
                val created = Files.createTempDirectory("carecoins-quickcore").toFile().apply {
                    deleteOnExit()
                }
                dir = created
                return created
            }

            override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: File) {
                dir = value
            }
        }

    private fun resolveFilesDir(context: Context?): File {
        return context?.filesDir ?: fallbackFilesDir
    }

    fun load(context: Context): QuickSnapshot? = load(resolveFilesDir(context))

    fun load(filesDir: File = fallbackFilesDir): QuickSnapshot? {
        val file = File(filesDir, SNAPSHOT_FILE)
        if (!file.exists()) return null
        return runCatching {
            val raw = file.readText(Charsets.UTF_8)
            QuickSnapshot.fromJson(JSONObject(raw))
        }.getOrNull()
    }

    fun loadRaw(context: Context): String? = loadRaw(resolveFilesDir(context))

    fun loadRaw(filesDir: File = fallbackFilesDir): String? {
        val file = File(filesDir, SNAPSHOT_FILE)
        if (!file.exists()) return null
        return runCatching { file.readText(Charsets.UTF_8) }.getOrNull()
    }

    fun save(context: Context, rawJson: String): Boolean = save(resolveFilesDir(context), rawJson)

    fun save(rawJson: String): Boolean = save(fallbackFilesDir, rawJson)

    fun save(filesDir: File, rawJson: String): Boolean {
        val valid = runCatching { QuickSnapshot.fromJson(JSONObject(rawJson)) }.isSuccess
        if (!valid) return false
        return runCatching {
            filesDir.mkdirs()
            val file = File(filesDir, SNAPSHOT_FILE)
            file.writeText(rawJson, Charsets.UTF_8)
            bumpVersion()
            true
        }.getOrDefault(false)
    }

    fun recordAction(context: Context, action: LastAction) {
        recordAction(resolveFilesDir(context), action)
        for (listener in actionListeners) {
            runCatching { listener(context, action) }
        }
    }

    fun recordAction(action: LastAction) = recordAction(fallbackFilesDir, action)

    fun recordAction(filesDir: File, action: LastAction) {
        runCatching {
            filesDir.mkdirs()
            val file = File(filesDir, LAST_ACTION_FILE)
            file.writeText(action.toJson().toString(), Charsets.UTF_8)
        }
        bumpVersion()
    }

    fun lastAction(context: Context, now: Instant = Instant.now()): LastAction? =
        lastAction(resolveFilesDir(context), now)

    fun lastAction(now: Instant = Instant.now()): LastAction? =
        lastAction(fallbackFilesDir, now)

    fun lastAction(filesDir: File, now: Instant = Instant.now()): LastAction? {
        val file = File(filesDir, LAST_ACTION_FILE)
        if (!file.exists()) return null
        val action = runCatching {
            LastAction.fromJson(JSONObject(file.readText(Charsets.UTF_8)))
        }.getOrNull() ?: return null
        val elapsedMillis = Duration.between(action.at, now).toMillis()
        return if (elapsedMillis in 0..UNDO_WINDOW_MILLIS) action else null
    }

    fun clearLastAction(context: Context) = clearLastAction(resolveFilesDir(context))

    fun clearLastAction() = clearLastAction(fallbackFilesDir)

    fun clearLastAction(filesDir: File) {
        runCatching {
            File(filesDir, LAST_ACTION_FILE).delete()
        }
        bumpVersion()
    }

    fun clear(context: Context) = clear(resolveFilesDir(context))

    fun clear(filesDir: File = fallbackFilesDir) {
        runCatching {
            File(filesDir, SNAPSHOT_FILE).delete()
            File(filesDir, LAST_ACTION_FILE).delete()
        }
        bumpVersion()
    }

    fun canUndo(context: Context, now: Instant = Instant.now()): Boolean =
        canUndo(resolveFilesDir(context), now)

    fun canUndo(now: Instant = Instant.now()): Boolean =
        canUndo(fallbackFilesDir, now)

    fun canUndo(filesDir: File, now: Instant = Instant.now()): Boolean {
        val action = lastAction(filesDir, now) ?: return false
        if (action.kind != LastAction.Kind.started && action.kind != LastAction.Kind.logged) {
            return false
        }
        return !action.clientRef.isNullOrEmpty()
    }
}
