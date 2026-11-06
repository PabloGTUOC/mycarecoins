package com.carecoins.quickcore

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class QuickApiException(
    val status: Int,
    val code: String?,
    override val message: String,
    val params: Map<String, String> = emptyMap(),
    cause: Throwable? = null,
) : Exception(message, cause)

val Pair<QuickSnapshot, String>.snapshot: QuickSnapshot
    get() = first

val Pair<QuickSnapshot, String>.rawJson: String
    get() = second

class QuickApi(
    val apiBase: String,
    val deviceKey: String,
    private val appContext: Context? = null,
) {
    private fun endpointUrl(path: String): URL {
        val cleanBase = apiBase.trimEnd('/')
        val cleanPath = path.trimStart('/')
        return URL("$cleanBase/$cleanPath")
    }

    private suspend fun send(
        path: String,
        method: String,
        body: JSONObject? = null,
    ): String = withContext(Dispatchers.IO) {
        val conn = (endpointUrl(path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            setRequestProperty("Authorization", "Device $deviceKey")
            setRequestProperty("Accept", "application/json")
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (body != null) {
                val bytes = body.toString().toByteArray(Charsets.UTF_8)
                conn.outputStream.use { out ->
                    out.write(bytes)
                }
            }
            val status = conn.responseCode
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            val responseText = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()

            if (status == 401) {
                appContext?.let { QuickCore.disconnectLocally(it) }
                throw parseErrorBody(responseText, 401)
            }
            if (status !in 200..299) {
                throw parseErrorBody(responseText, status)
            }
            responseText
        } catch (e: QuickApiException) {
            throw e
        } catch (e: IOException) {
            throw QuickApiException(
                status = 0,
                code = null,
                message = e.message ?: "Network error",
                params = emptyMap(),
                cause = e,
            )
        } catch (e: Exception) {
            throw QuickApiException(
                status = 0,
                code = null,
                message = e.message ?: "Network error",
                params = emptyMap(),
                cause = e,
            )
        } finally {
            conn.disconnect()
        }
    }

    suspend fun snapshot(): Pair<QuickSnapshot, String> = withContext(Dispatchers.IO) {
        val raw = send(path = "/api/quick", method = "GET")
        val parsed = try {
            QuickSnapshot.fromJson(JSONObject(raw))
        } catch (e: Exception) {
            throw QuickApiException(
                status = 0,
                code = null,
                message = e.message ?: "Invalid snapshot JSON",
                params = emptyMap(),
                cause = e,
            )
        }
        Pair(parsed, raw)
    }

    suspend fun start(templateId: String, clientRef: String): QuickActionResult = withContext(Dispatchers.IO) {
        val idNum = templateId.toLongOrNull()
            ?: throw QuickApiException(0, null, "Invalid templateId: $templateId")
        val body = JSONObject()
            .put("templateId", idNum)
            .put("clientRef", clientRef)
        val raw = send(path = "/api/quick/start", method = "POST", body = body)
        decodeActionResult(raw)
    }

    suspend fun startNow(type: String, title: String, clientRef: String): QuickActionResult = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("type", type)
            .put("title", title)
            .put("clientRef", clientRef)
        val raw = send(path = "/api/quick/start", method = "POST", body = body)
        decodeActionResult(raw)
    }

    suspend fun done(templateId: String, clientRef: String): QuickActionResult = withContext(Dispatchers.IO) {
        val idNum = templateId.toLongOrNull()
            ?: throw QuickApiException(0, null, "Invalid templateId: $templateId")
        val body = JSONObject()
            .put("templateId", idNum)
            .put("clientRef", clientRef)
        val raw = send(path = "/api/quick/done", method = "POST", body = body)
        decodeActionResult(raw)
    }

    suspend fun stop(activityId: String): QuickActionResult = withContext(Dispatchers.IO) {
        val idNum = activityId.toLongOrNull()
            ?: throw QuickApiException(0, null, "Invalid activityId: $activityId")
        val body = JSONObject()
            .put("activityId", idNum)
        val raw = send(path = "/api/quick/stop", method = "POST", body = body)
        decodeActionResult(raw)
    }

    suspend fun undo(clientRef: String): QuickActionResult = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("clientRef", clientRef)
        val raw = send(path = "/api/quick/undo", method = "POST", body = body)
        decodeActionResult(raw)
    }

    private fun decodeActionResult(raw: String): QuickActionResult {
        return try {
            QuickActionResult.fromJson(JSONObject(raw))
        } catch (e: Exception) {
            throw QuickApiException(
                status = 0,
                code = null,
                message = e.message ?: "Invalid action response JSON",
                params = emptyMap(),
                cause = e,
            )
        }
    }

    companion object {
        const val TIMEOUT_MS = 15_000

        fun fromStore(context: Context): QuickApi? {
            val key = DeviceKeyStore.read(context)
            if (key.isNullOrBlank()) return null
            val apiBase = DeviceKeyStore.readApiBase(context)
            if (apiBase.isNullOrBlank()) return null
            return QuickApi(
                apiBase = apiBase.trimEnd('/'),
                deviceKey = key,
                appContext = context.applicationContext ?: context,
            )
        }

        fun newClientRef(): String = UUID.randomUUID().toString()

        fun parseErrorBody(rawBody: String?, defaultStatus: Int): QuickApiException {
            val trimmed = rawBody?.trim().orEmpty()
            if (trimmed.isEmpty()) {
                return QuickApiException(
                    status = defaultStatus,
                    code = null,
                    message = "HTTP $defaultStatus",
                    params = emptyMap(),
                )
            }
            val json = runCatching { JSONObject(trimmed) }.getOrNull()
                ?: return QuickApiException(
                    status = defaultStatus,
                    code = null,
                    message = rawBody ?: "HTTP $defaultStatus",
                    params = emptyMap(),
                )
            val message = if (json.has("error") && !json.isNull("error") && json.opt("error") is String) {
                json.getString("error")
            } else {
                "HTTP $defaultStatus"
            }
            val code = if (json.has("code") && !json.isNull("code") && json.opt("code") is String) {
                json.getString("code")
            } else {
                null
            }
            val params = mutableMapOf<String, String>()
            val rawParams = json.optJSONObject("params")
            if (rawParams != null) {
                val keys = rawParams.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    if (!rawParams.isNull(k)) {
                        params[k] = rawParams.get(k).toString()
                    }
                }
            }
            return QuickApiException(
                status = defaultStatus,
                code = code,
                message = message,
                params = params,
            )
        }
    }
}
