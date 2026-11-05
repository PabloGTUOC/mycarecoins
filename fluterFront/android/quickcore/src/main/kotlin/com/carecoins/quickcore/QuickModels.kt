package com.carecoins.quickcore

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

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

    fun startedTask(now: Instant = Instant.now()): Upcoming? {
        return upcoming.firstOrNull { item ->
            item.status == "approved" &&
                !item.startsAt.isAfter(now) &&
                item.endsAt != null &&
                now.isBefore(item.endsAt)
        }
    }

    fun awaitingConfirmation(now: Instant = Instant.now()): Upcoming? {
        val twoHoursAgo = now.minusSeconds(2 * 3600L)
        return upcoming.firstOrNull { item ->
            item.status == "approved" &&
                item.endsAt != null &&
                !item.endsAt.isAfter(now) &&
                !item.startsAt.isBefore(twoHoursAgo)
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
        failed,
        cancelled;

        companion object {
            val STARTED get() = started
            val LOGGED get() = logged
            val STOPPED get() = stopped
            val UNDONE get() = undone
            val FAILED get() = failed
            val CANCELLED get() = cancelled

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
