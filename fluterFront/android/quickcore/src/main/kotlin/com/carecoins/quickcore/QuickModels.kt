package com.carecoins.quickcore

import android.content.Context
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

data class FlexibleString(val value: String) {
    companion object {
        fun from(raw: Any?): String {
            return when (raw) {
                null, JSONObject.NULL -> throw JSONException("Expected String or number for FlexibleString, got null")
                is String -> raw
                is Int, is Long -> raw.toString()
                is Number -> {
                    val dbl = raw.toDouble()
                    val lng = raw.toLong()
                    if (dbl == lng.toDouble()) lng.toString() else raw.toString()
                }
                else -> throw JSONException("Expected String or number for FlexibleString, got ${raw::class.java}")
            }
        }
    }
}

data class FlexibleInt(val value: Int) {
    companion object {
        fun from(raw: Any?): Int {
            return when (raw) {
                null, JSONObject.NULL -> throw JSONException("Expected Int or numeric string for FlexibleInt, got null")
                is Int -> raw
                is Number -> raw.toInt()
                is String -> raw.toIntOrNull()
                    ?: raw.toDoubleOrNull()?.toInt()
                    ?: throw JSONException("Cannot parse Int from string: $raw")
                else -> throw JSONException("Expected Int or numeric string for FlexibleInt, got ${raw::class.java}")
            }
        }
    }
}

fun JSONObject.getFlexibleString(key: String): String {
    if (!has(key) || isNull(key)) {
        throw JSONException("Missing required key: $key")
    }
    return FlexibleString.from(get(key))
}

fun JSONObject.optFlexibleString(key: String): String? {
    if (!has(key) || isNull(key)) return null
    return FlexibleString.from(get(key))
}

fun JSONObject.getFlexibleInt(key: String): Int {
    if (!has(key) || isNull(key)) {
        throw JSONException("Missing required key: $key")
    }
    return FlexibleInt.from(get(key))
}

fun JSONObject.optFlexibleInt(key: String): Int? {
    if (!has(key) || isNull(key)) return null
    return FlexibleInt.from(get(key))
}

internal fun JSONObject.optNullableString(key: String): String? {
    if (!has(key) || isNull(key)) return null
    val raw = opt(key)
    return if (raw is String) raw else raw?.toString()
}

internal fun JSONObject.optNullableBoolean(key: String): Boolean? {
    if (!has(key) || isNull(key)) return null
    return when (val raw = opt(key)) {
        is Boolean -> raw
        is String -> raw.toBooleanStrictOrNull()
        else -> null
    }
}

internal fun parseIsoInstant(dateStr: String): Instant {
    runCatching { return Instant.parse(dateStr) }
    runCatching { return OffsetDateTime.parse(dateStr).toInstant() }
    runCatching {
        val fallback = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ")
        return OffsetDateTime.parse(dateStr, fallback).toInstant()
    }
    runCatching {
        val fallbackShort = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssZ")
        return OffsetDateTime.parse(dateStr, fallbackShort).toInstant()
    }
    throw JSONException("Invalid ISO 8601 date string: $dateStr")
}

internal fun JSONObject.getInstant(key: String): Instant {
    if (!has(key) || isNull(key)) {
        throw JSONException("Missing required date key: $key")
    }
    return parseIsoInstant(getString(key))
}

internal fun JSONObject.optInstant(key: String): Instant? {
    if (!has(key) || isNull(key)) return null
    val str = optNullableString(key) ?: return null
    if (str.isEmpty()) return null
    return parseIsoInstant(str)
}

data class QuickSnapshot(
    val family: Family,
    val balance: Int,
    val needsYou: Int,
    val tasks: List<Task>,
    val upcoming: List<Upcoming>,
    val running: Running?,
    val serverTime: Instant,
) {
    data class Family(
        val id: String,
        val name: String,
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("id", id)
            .put("name", name)

        companion object {
            fun fromJson(json: JSONObject): Family {
                return Family(
                    id = json.getFlexibleString("id"),
                    name = json.getString("name"),
                )
            }
        }
    }

    data class Task(
        val id: String,
        val title: String,
        val type: String,
        val durationMinutes: Int,
        val coinValue: Int,
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("id", id)
            .put("title", title)
            .put("type", type)
            .put("durationMinutes", durationMinutes)
            .put("coinValue", coinValue)

        companion object {
            fun fromJson(json: JSONObject): Task {
                return Task(
                    id = json.getFlexibleString("id"),
                    title = json.getString("title"),
                    type = json.getString("type"),
                    durationMinutes = json.getFlexibleInt("durationMinutes"),
                    coinValue = json.getFlexibleInt("coinValue"),
                )
            }
        }
    }

    data class Upcoming(
        val id: String,
        val title: String,
        val type: String,
        val startsAt: Instant,
        val endsAt: Instant?,
        val status: String,
    ) {
        fun toJson(): JSONObject = JSONObject().apply {
            put("id", id)
            put("title", title)
            put("type", type)
            put("startsAt", startsAt.toString())
            if (endsAt != null) put("endsAt", endsAt.toString()) else put("endsAt", JSONObject.NULL)
            put("status", status)
        }

        companion object {
            fun fromJson(json: JSONObject): Upcoming {
                return Upcoming(
                    id = json.getFlexibleString("id"),
                    title = json.getString("title"),
                    type = json.getString("type"),
                    startsAt = json.getInstant("startsAt"),
                    endsAt = json.optInstant("endsAt"),
                    status = json.getString("status"),
                )
            }
        }
    }

    data class Running(
        val id: String,
        val title: String,
        val type: String,
        val startedAt: Instant,
        val clientRef: String?,
    ) {
        fun toJson(): JSONObject = JSONObject().apply {
            put("id", id)
            put("title", title)
            put("type", type)
            put("startedAt", startedAt.toString())
            if (clientRef != null) put("clientRef", clientRef) else put("clientRef", JSONObject.NULL)
        }

        companion object {
            fun fromJson(json: JSONObject): Running {
                return Running(
                    id = json.getFlexibleString("id"),
                    title = json.getString("title"),
                    type = json.getString("type"),
                    startedAt = json.getInstant("startedAt"),
                    clientRef = json.optNullableString("clientRef"),
                )
            }
        }
    }

    fun nextUpcoming(now: Instant = Instant.now()): Upcoming? {
        return upcoming.firstOrNull { item ->
            item.startsAt.isAfter(now)
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("family", family.toJson())
        put("balance", balance)
        put("needsYou", needsYou)
        put("tasks", JSONArray(tasks.map { it.toJson() }))
        put("upcoming", JSONArray(upcoming.map { it.toJson() }))
        if (running != null) put("running", running.toJson()) else put("running", JSONObject.NULL)
        put("serverTime", serverTime.toString())
    }

    companion object {
        fun fromJson(json: JSONObject): QuickSnapshot {
            val familyJson = json.getJSONObject("family")
            val tasksArray = json.getJSONArray("tasks")
            val tasksList = buildList(tasksArray.length()) {
                for (i in 0 until tasksArray.length()) {
                    add(Task.fromJson(tasksArray.getJSONObject(i)))
                }
            }
            val upcomingArray = json.getJSONArray("upcoming")
            val upcomingList = buildList(upcomingArray.length()) {
                for (i in 0 until upcomingArray.length()) {
                    add(Upcoming.fromJson(upcomingArray.getJSONObject(i)))
                }
            }
            val runningObj = if (json.has("running") && !json.isNull("running")) {
                Running.fromJson(json.getJSONObject("running"))
            } else {
                null
            }
            return QuickSnapshot(
                family = Family.fromJson(familyJson),
                balance = json.getFlexibleInt("balance"),
                needsYou = json.getFlexibleInt("needsYou"),
                tasks = tasksList,
                upcoming = upcomingList,
                running = runningObj,
                serverTime = json.getInstant("serverTime"),
            )
        }

        fun fromJson(rawJson: String): QuickSnapshot = fromJson(JSONObject(rawJson))
    }
}

typealias Family = QuickSnapshot.Family
typealias Task = QuickSnapshot.Task
typealias Upcoming = QuickSnapshot.Upcoming
typealias Running = QuickSnapshot.Running

data class QuickActivity(
    val id: String,
    val title: String? = null,
    val type: String? = null,
    val status: String? = null,
    val startsAt: Instant? = null,
    val endsAt: Instant? = null,
    val runningSince: Instant? = null,
    val clientRef: String? = null,
    val durationMinutes: Int? = null,
    val coinValue: Int? = null,
) {
    companion object {
        fun fromJson(json: JSONObject): QuickActivity {
            return QuickActivity(
                id = json.getFlexibleString("id"),
                title = json.optNullableString("title"),
                type = json.optNullableString("type"),
                status = json.optNullableString("status"),
                startsAt = json.optInstant("starts_at") ?: json.optInstant("startsAt"),
                endsAt = json.optInstant("ends_at") ?: json.optInstant("endsAt"),
                runningSince = json.optInstant("running_since") ?: json.optInstant("runningSince"),
                clientRef = json.optNullableString("client_ref") ?: json.optNullableString("clientRef"),
                durationMinutes = json.optFlexibleInt("duration_minutes") ?: json.optFlexibleInt("durationMinutes"),
                coinValue = json.optFlexibleInt("coin_value") ?: json.optFlexibleInt("coinValue"),
            )
        }

        fun fromJson(rawJson: String): QuickActivity = fromJson(JSONObject(rawJson))
    }
}

data class QuickActionResult(
    val activity: QuickActivity? = null,
    val replayed: Boolean = false,
    val warning: String? = null,
    val undone: Boolean = false,
    val completed: Boolean? = null,
    val coinsAwarded: Int? = null,
    val cancelled: Boolean = false,
) {
    companion object {
        fun fromJson(json: JSONObject): QuickActionResult {
            val activity = if (json.has("activity")) {
                if (!json.isNull("activity")) {
                    runCatching { QuickActivity.fromJson(json.getJSONObject("activity")) }.getOrNull()
                } else {
                    null
                }
            } else if (json.has("id") && !json.isNull("id")) {
                runCatching { QuickActivity.fromJson(json) }.getOrNull()
            } else {
                null
            }
            return QuickActionResult(
                activity = activity,
                replayed = json.optNullableBoolean("replayed") ?: false,
                warning = json.optNullableString("warning"),
                undone = json.optNullableBoolean("undone") ?: false,
                completed = json.optNullableBoolean("completed"),
                coinsAwarded = json.optFlexibleInt("coinsAwarded"),
                cancelled = json.optNullableBoolean("cancelled") ?: false,
            )
        }

        fun fromJson(rawJson: String): QuickActionResult = fromJson(JSONObject(rawJson))
    }
}

data class LastAction(
    val kind: Kind,
    val taskId: String? = null,
    val activityId: String? = null,
    val clientRef: String? = null,
    val message: String? = null,
    val at: Instant = Instant.now(),
) {
    enum class Kind {
        started,
        logged,
        stopped,
        undone,
        failed;

        companion object {
            val STARTED get() = started
            val LOGGED get() = logged
            val STOPPED get() = stopped
            val UNDONE get() = undone
            val FAILED get() = failed

            fun fromString(value: String): Kind {
                return entries.firstOrNull { it.name.equals(value, ignoreCase = true) }
                    ?: throw JSONException("Unknown LastAction.Kind: $value")
            }
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("kind", kind.name)
        if (taskId != null) put("taskId", taskId)
        if (activityId != null) put("activityId", activityId)
        if (clientRef != null) put("clientRef", clientRef)
        if (message != null) put("message", message)
        put("at", at.toString())
    }

    companion object {
        fun fromJson(json: JSONObject): LastAction {
            return LastAction(
                kind = Kind.fromString(json.getString("kind")),
                taskId = json.optFlexibleString("taskId"),
                activityId = json.optFlexibleString("activityId"),
                clientRef = json.optNullableString("clientRef"),
                message = json.optNullableString("message"),
                at = json.getInstant("at"),
            )
        }

        fun fromJson(rawJson: String): LastAction = fromJson(JSONObject(rawJson))
    }
}

sealed interface QuickBannerState {
    data object None : QuickBannerState
    data class Running(val running: QuickSnapshot.Running) : QuickBannerState
}

enum class QuickNotificationActionKind {
    STOP,
}

data class QuickNotificationAction(
    val kind: QuickNotificationActionKind,
    val activityId: String,
)

sealed interface QuickNotificationState {
    data object None : QuickNotificationState
    data class Running(
        val activityId: String,
        val title: String,
        val startedAt: Instant,
        val ongoing: Boolean = true,
        val actions: List<QuickNotificationAction> = listOf(
            QuickNotificationAction(QuickNotificationActionKind.STOP, activityId),
        ),
    ) : QuickNotificationState
}

sealed interface WearSection {
    data class Running(val running: QuickSnapshot.Running) : WearSection
    data object Now : WearSection
    data class Tasks(val tasks: List<QuickSnapshot.Task>) : WearSection
    data class Coins(val balance: Int) : WearSection
}

sealed interface WearNextState {
    data object NotConnected : WearNextState
    data class Running(val running: QuickSnapshot.Running) : WearNextState
    data class NextUpcoming(val upcoming: QuickSnapshot.Upcoming) : WearNextState
    data object NoTasks : WearNextState
}

data class ScheduledReminder(
    val id: String,
    val at: Instant,
    val title: String = "",
    val startsAt: Instant = at.plusSeconds(15 * 60L),
)

data class PendingAction(
    val kind: Kind,
    val taskId: String? = null,
    val activityId: String? = null,
    val type: String? = null,
    val title: String? = null,
    val clientRef: String = QuickApi.newClientRef(),
    val createdAt: Instant = Instant.now(),
    val id: String = clientRef.ifEmpty { UUID.randomUUID().toString() },
) {
    enum class Kind {
        start,
        done,
        startNow,
        stop;

        companion object {
            fun fromString(value: String): Kind {
                return entries.firstOrNull { it.name.equals(value, ignoreCase = true) }
                    ?: throw JSONException("Unknown PendingAction.Kind: $value")
            }
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("kind", kind.name)
        if (taskId != null) put("taskId", taskId)
        if (activityId != null) put("activityId", activityId)
        if (type != null) put("type", type)
        if (title != null) put("title", title)
        put("clientRef", clientRef)
        put("createdAt", createdAt.toString())
    }

    companion object {
        fun fromJson(json: JSONObject): PendingAction {
            val clientRef = json.optNullableString("clientRef").orEmpty()
                .ifEmpty { json.optFlexibleString("id").orEmpty() }
                .ifEmpty { QuickApi.newClientRef() }
            val id = json.optFlexibleString("id").orEmpty().ifEmpty { clientRef }
            return PendingAction(
                id = id,
                kind = Kind.fromString(json.getString("kind")),
                taskId = json.optFlexibleString("taskId"),
                activityId = json.optFlexibleString("activityId"),
                type = json.optNullableString("type"),
                title = json.optNullableString("title"),
                clientRef = clientRef,
                createdAt = json.getInstant("createdAt"),
            )
        }
    }
}

object PendingActionQueue {
    const val FILE_NAME = QuickCore.PENDING_ACTIONS_FILE
    const val MAX_AGE_SECONDS = 12 * 3600L

    fun pruneAndDedupe(
        actions: List<PendingAction>,
        now: Instant = Instant.now(),
    ): List<PendingAction> {
        val cutoff = now.minusSeconds(MAX_AGE_SECONDS)
        val seenRefs = HashSet<String>()
        return buildList {
            for (action in actions) {
                if (action.createdAt.isBefore(cutoff)) continue
                val key = action.clientRef.ifEmpty { action.id }
                if (seenRefs.add(key)) {
                    add(action)
                }
            }
        }
    }

    fun enqueue(
        existing: List<PendingAction>,
        action: PendingAction,
        now: Instant = Instant.now(),
    ): List<PendingAction> {
        return pruneAndDedupe(existing + action, now)
    }

    private fun resolveFilesDir(context: Context?): File {
        return context?.filesDir ?: SnapshotStore.fallbackFilesDir
    }

    fun load(context: Context, now: Instant = Instant.now()): List<PendingAction> =
        load(resolveFilesDir(context), now)

    fun load(
        filesDir: File = SnapshotStore.fallbackFilesDir,
        now: Instant = Instant.now(),
    ): List<PendingAction> {
        val file = File(filesDir, FILE_NAME)
        if (!file.exists()) return emptyList()
        val rawList = runCatching {
            val arr = JSONArray(file.readText(Charsets.UTF_8))
            buildList(arr.length()) {
                for (i in 0 until arr.length()) {
                    add(PendingAction.fromJson(arr.getJSONObject(i)))
                }
            }
        }.getOrElse { return emptyList() }
        val pruned = pruneAndDedupe(rawList, now)
        if (pruned.size != rawList.size) {
            save(filesDir, pruned)
        }
        return pruned
    }

    fun save(context: Context, actions: List<PendingAction>) =
        save(resolveFilesDir(context), actions)

    fun save(
        filesDir: File = SnapshotStore.fallbackFilesDir,
        actions: List<PendingAction>,
    ) {
        runCatching {
            filesDir.mkdirs()
            val arr = JSONArray(actions.map { it.toJson() })
            File(filesDir, FILE_NAME).writeText(arr.toString(), Charsets.UTF_8)
        }
    }

    fun enqueue(
        context: Context,
        action: PendingAction,
        now: Instant = Instant.now(),
    ): List<PendingAction> = enqueue(resolveFilesDir(context), action, now)

    fun enqueue(
        filesDir: File = SnapshotStore.fallbackFilesDir,
        action: PendingAction,
        now: Instant = Instant.now(),
    ): List<PendingAction> {
        val updated = enqueue(load(filesDir, now), action, now)
        save(filesDir, updated)
        return updated
    }

    fun clear(context: Context) = clear(resolveFilesDir(context))

    fun clear(filesDir: File = SnapshotStore.fallbackFilesDir) {
        runCatching {
            File(filesDir, FILE_NAME).delete()
        }
    }
}

data class QuickWidgetLayout(
    val isWide: Boolean,
    val rowHeightDp: Int,
    val showFooter: Boolean,
    val showNext: Boolean,
    val verticalPaddingDp: Int = QuickSurfaceState.DEFAULT_PADDING_DP,
    val gapDp: Int = QuickSurfaceState.DEFAULT_GAP_DP,
    val showSeeAll: Boolean = false,
)

object QuickSurfaceState {
    const val MAX_REMINDERS = 20
    const val REMINDER_LEAD_SECONDS = 15 * 60L
    const val CHIP_EXPIRY_BUFFER_SECONDS = 1L
    const val SMALL_TALL_MIN_WIDTH_DP = 160
    const val SMALL_TALL_MIN_HEIGHT_DP = 180
    const val SMALL_DEFAULT_ROW_COUNT = 1
    const val SMALL_TALL_ROW_COUNT = 3
    const val SMALL_TALL_RUNNING_ROW_COUNT = 1
    const val WIDE_WIDTH_DP = 220
    const val WIDE_FOOTER_MIN_HEIGHT_DP = 200
    const val NEXT_LINE_MIN_HEIGHT_DP = 300
    const val HEADER_HEIGHT_DP = 28
    const val WIDE_ROW_HEIGHT_DP = 52
    const val NARROW_ROW_HEIGHT_DP = 64
    const val RUNNING_BANNER_HEIGHT_DP = 64
    const val CHIP_HEIGHT_DP = 30
    const val FOOTER_HEIGHT_DP = 40
    const val NEXT_LINE_HEIGHT_DP = 18
    const val SEE_ALL_HEIGHT_DP = 24
    const val DEFAULT_PADDING_DP = 12
    const val DEFAULT_GAP_DP = 6
    const val TIGHT_PADDING_DP = 10
    const val TIGHT_GAP_DP = 4
    const val MAX_EMPTY_SPACE_DP = 40
    /** Glance drops children beyond this count in a single Column / Row. */
    const val GLANCE_MAX_CHILDREN = 10
    /** Worst case body: banner + chip + 6 rows + next + see-all = 10 children. */
    const val MAX_TASK_ROWS = 6
    private val EXCLUDED_REMINDER_STATUSES = setOf(
        "completed",
        "rejected",
        "cancelled",
        "canceled",
    )

    fun computeWidgetLayout(
        widthDp: Float,
        heightDp: Float,
        taskCount: Int = 0,
        hasRunning: Boolean = false,
        hasLastAction: Boolean = false,
        hasNextUpcoming: Boolean = false,
    ): QuickWidgetLayout {
        val isWide = widthDp >= WIDE_WIDTH_DP
        val rowHeight = if (isWide) WIDE_ROW_HEIGHT_DP else NARROW_ROW_HEIGHT_DP
        val rowStep = rowHeight + DEFAULT_GAP_DP
        val safeHeight = if (heightDp > 0f) heightDp.toInt() else 180

        // Header, banner and chip are always counted; the footer never depends on the chip.
        var used = HEADER_HEIGHT_DP
        if (hasRunning) used += DEFAULT_GAP_DP + RUNNING_BANNER_HEIGHT_DP
        if (hasLastAction) used += DEFAULT_GAP_DP + CHIP_HEIGHT_DP
        val available = (safeHeight - 2 * DEFAULT_PADDING_DP - used).coerceAtLeast(0)
        val footerCost = DEFAULT_GAP_DP + FOOTER_HEIGHT_DP

        fun slotsFor(space: Int): Int = space.coerceAtLeast(0) / rowStep

        val empty = taskCount <= 0 && !hasRunning
        val showFooter: Boolean
        val slots: Int
        when {
            hasRunning -> {
                showFooter = false
                slots = slotsFor(available)
            }
            empty -> {
                showFooter = true
                slots = 0
            }
            isWide -> {
                showFooter = safeHeight >= WIDE_FOOTER_MIN_HEIGHT_DP
                slots = slotsFor(available - if (showFooter) footerCost else 0)
            }
            else -> {
                val withFooter = slotsFor(available - footerCost)
                showFooter = withFooter >= 2
                slots = if (showFooter) withFooter else slotsFor(available)
            }
        }

        var showNext = false
        var showSeeAll = false
        if (isWide && !hasRunning && !empty && taskCount < slots) {
            var spare = (available - if (showFooter) footerCost else 0) - taskCount * rowStep
            if (hasNextUpcoming && spare >= DEFAULT_GAP_DP + NEXT_LINE_HEIGHT_DP) {
                showNext = true
                spare -= DEFAULT_GAP_DP + NEXT_LINE_HEIGHT_DP
            }
            if (spare >= DEFAULT_GAP_DP + SEE_ALL_HEIGHT_DP) {
                showSeeAll = true
            }
        }

        return QuickWidgetLayout(
            isWide = isWide,
            rowHeightDp = rowHeight,
            showFooter = showFooter,
            showNext = showNext,
            verticalPaddingDp = DEFAULT_PADDING_DP,
            gapDp = DEFAULT_GAP_DP,
            showSeeAll = showSeeAll,
        )
    }

    /** Children of the widget's root Column for the given state (mirrors QuickWidget.kt).
     * Items inside LazyColumn do not count toward Glance's 10-child limit. */
    fun rootChildCount(
        layout: QuickWidgetLayout,
        hasRunning: Boolean = false,
        hasLastAction: Boolean = false,
    ): Int {
        var n = 2 // HeaderBar + LazyColumn
        if (hasRunning) n++
        if (hasLastAction) n++
        if (layout.showFooter) n++
        return n
    }

    /** Children of the widget's body container for the given state (mirrors QuickWidget.kt). */
    fun bodyChildCount(
        layout: QuickWidgetLayout,
        taskCount: Int = 0,
        hasRunning: Boolean = false,
        hasLastAction: Boolean = false,
        hasNextUpcoming: Boolean = false,
    ): Int = rootChildCount(layout, hasRunning, hasLastAction)

    fun chipExpiryInstant(
        actionAt: Instant,
        undoWindowSeconds: Long = SnapshotStore.UNDO_WINDOW_SECONDS,
    ): Instant {
        return actionAt.plusSeconds(undoWindowSeconds + CHIP_EXPIRY_BUFFER_SECONDS)
    }

    fun chipExpiryInstant(
        action: LastAction,
        undoWindowSeconds: Long = SnapshotStore.UNDO_WINDOW_SECONDS,
    ): Instant = chipExpiryInstant(action.at, undoWindowSeconds)

    fun chipExpiryDelayMillis(
        actionAt: Instant,
        now: Instant = Instant.now(),
        undoWindowSeconds: Long = SnapshotStore.UNDO_WINDOW_SECONDS,
    ): Long {
        val expiry = chipExpiryInstant(actionAt, undoWindowSeconds)
        return Duration.between(now, expiry).toMillis().coerceAtLeast(0L)
    }

    fun isSmallTallBucket(widthDp: Int, heightDp: Int): Boolean {
        return widthDp >= SMALL_TALL_MIN_WIDTH_DP && heightDp >= SMALL_TALL_MIN_HEIGHT_DP
    }

    fun isSmallTallBucket(widthDp: Float, heightDp: Float): Boolean {
        return widthDp >= SMALL_TALL_MIN_WIDTH_DP && heightDp >= SMALL_TALL_MIN_HEIGHT_DP
    }

    fun smallLayoutRowCount(
        isTallBucket: Boolean,
        hasRunning: Boolean = false,
    ): Int {
        return if (isTallBucket) {
            if (hasRunning) SMALL_TALL_RUNNING_ROW_COUNT else SMALL_TALL_ROW_COUNT
        } else {
            if (hasRunning) 0 else SMALL_DEFAULT_ROW_COUNT
        }
    }

    fun smallLayoutRowCount(
        widthDp: Int,
        heightDp: Int,
        hasRunning: Boolean = false,
    ): Int = smallLayoutRowCount(
        isTallBucket = isSmallTallBucket(widthDp, heightDp),
        hasRunning = hasRunning,
    )

    fun smallLayoutRowCount(
        widthDp: Float,
        heightDp: Float,
        hasRunning: Boolean = false,
    ): Int = smallLayoutRowCount(
        isTallBucket = isSmallTallBucket(widthDp, heightDp),
        hasRunning = hasRunning,
    )

    fun smallLayoutRowCount(heightDp: Int, hasRunning: Boolean = false): Int {
        return smallLayoutRowCount(
            isTallBucket = heightDp >= SMALL_TALL_MIN_HEIGHT_DP,
            hasRunning = hasRunning,
        )
    }

    fun smallLayoutRowCount(heightDp: Float, hasRunning: Boolean = false): Int {
        return smallLayoutRowCount(
            isTallBucket = heightDp >= SMALL_TALL_MIN_HEIGHT_DP,
            hasRunning = hasRunning,
        )
    }

    fun pickBanner(snapshot: QuickSnapshot?, now: Instant = Instant.now()): QuickBannerState {
        if (snapshot == null) return QuickBannerState.None
        snapshot.running?.let { return QuickBannerState.Running(it) }
        return QuickBannerState.None
    }

    fun pickNext(
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
        connected: Boolean = snapshot != null,
    ): WearNextState {
        if (!connected || snapshot == null) return WearNextState.NotConnected
        snapshot.running?.let { return WearNextState.Running(it) }
        snapshot.nextUpcoming(now)?.let { return WearNextState.NextUpcoming(it) }
        return WearNextState.NoTasks
    }

    fun selectReminders(
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
        enabled: Boolean = true,
        connected: Boolean = true,
    ): List<ScheduledReminder> {
        if (!enabled || !connected || snapshot == null) return emptyList()
        return snapshot.upcoming
            .asSequence()
            .filter { it.status.lowercase() !in EXCLUDED_REMINDER_STATUSES }
            .mapNotNull { item ->
                val reminderAt = item.startsAt.minusSeconds(REMINDER_LEAD_SECONDS)
                if (reminderAt.isAfter(now)) {
                    ScheduledReminder(
                        id = item.id,
                        at = reminderAt,
                        title = item.title,
                        startsAt = item.startsAt,
                    )
                } else {
                    null
                }
            }
            .take(MAX_REMINDERS)
            .toList()
    }

    fun nextTimelineInstants(
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
    ): List<Instant> {
        if (snapshot == null) return emptyList()
        return snapshot.upcoming
            .asSequence()
            .map { it.startsAt }
            .filter { it.isAfter(now) }
            .distinct()
            .sorted()
            .take(3)
            .toList()
    }

    fun wearSections(
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
    ): List<WearSection> {
        if (snapshot == null) return emptyList()
        return buildList {
            when (val banner = pickBanner(snapshot, now)) {
                is QuickBannerState.Running -> add(WearSection.Running(banner.running))
                QuickBannerState.None -> Unit
            }
            if (snapshot.running == null) {
                add(WearSection.Now)
            }
            if (snapshot.tasks.isNotEmpty()) {
                add(WearSection.Tasks(snapshot.tasks))
            }
            add(WearSection.Coins(snapshot.balance))
        }
    }

    fun pickNotification(
        snapshot: QuickSnapshot?,
        now: Instant = Instant.now(),
    ): QuickNotificationState {
        if (snapshot == null) return QuickNotificationState.None
        snapshot.running?.let { running ->
            return QuickNotificationState.Running(
                activityId = running.id,
                title = running.title,
                startedAt = running.startedAt,
            )
        }
        return QuickNotificationState.None
    }
}
