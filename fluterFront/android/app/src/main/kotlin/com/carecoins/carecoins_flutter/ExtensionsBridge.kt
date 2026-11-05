package com.carecoins.carecoins_flutter

import android.content.Context
import com.carecoins.carecoins_flutter.quick.QuickRefresh
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.QuickApi
import com.carecoins.quickcore.QuickApiException
import com.carecoins.quickcore.SnapshotStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ExtensionsBridge(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(true)
            }

            "storeDeviceKey" -> {
                val key = call.argument<String>("key")
                val deviceKeyId = call.argument<String>("deviceKeyId")
                val apiBase = call.argument<String>("apiBase")
                if (key == null || deviceKeyId == null || apiBase == null) {
                    result.error(
                        "invalid_arguments",
                        "Missing arguments for storeDeviceKey",
                        null,
                    )
                    return
                }
                scope.launch {
                    val outcome = withContext(Dispatchers.IO) {
                        DeviceKeyStore.store(
                            context = context,
                            key = key,
                            deviceKeyId = deviceKeyId,
                            apiBase = apiBase,
                        )
                        val res = refreshInternal()
                        if (res == "ok") {
                            QuickRefresh.schedule(context)
                        }
                        res
                    }
                    result.success(outcome)
                }
            }

            "status" -> {
                scope.launch {
                    val statusMap = withContext(Dispatchers.IO) {
                        val key = DeviceKeyStore.read(context)
                        val deviceKeyId = DeviceKeyStore.readDeviceKeyId(context)
                        val connected = !key.isNullOrEmpty() && !deviceKeyId.isNullOrEmpty()
                        mapOf<String, Any?>(
                            "connected" to connected,
                            "deviceKeyId" to if (connected) deviceKeyId else null,
                        )
                    }
                    result.success(statusMap)
                }
            }

            "refresh" -> {
                scope.launch {
                    val outcome = withContext(Dispatchers.IO) {
                        refreshInternal()
                    }
                    result.success(outcome)
                }
            }

            "clear" -> {
                scope.launch {
                    withContext(Dispatchers.IO) {
                        clearInternal()
                    }
                    result.success(null)
                }
            }

            "setLanguage" -> {
                val code = call.argument<String>("code")
                scope.launch {
                    withContext(Dispatchers.IO) {
                        L10n.setLanguage(context, code)
                        SnapshotStore.onChanged(context)
                        val key = DeviceKeyStore.read(context)
                        if (!key.isNullOrEmpty()) {
                            WearSync.pushContext(
                                context = context,
                                deviceKey = key,
                                language = L10n.getLanguage(context).orEmpty(),
                            )
                        }
                    }
                    result.success(null)
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private suspend fun refreshInternal(): String {
        val key = DeviceKeyStore.read(context)
        val apiBase = DeviceKeyStore.readApiBase(context)
        if (key.isNullOrEmpty() || apiBase.isNullOrEmpty()) {
            return "none"
        }
        return try {
            val api = QuickApi(apiBase = apiBase, deviceKey = key, appContext = context)
            val (_, rawJson) = api.snapshot()
            SnapshotStore.save(context, rawJson)
            SnapshotStore.onChanged(context)
            WearSync.pushContext(
                context = context,
                deviceKey = key,
                apiBase = apiBase,
                snapshot = rawJson,
                language = L10n.getLanguage(context).orEmpty(),
            )
            "ok"
        } catch (e: QuickApiException) {
            if (e.status == 401) {
                clearInternal()
                "revoked"
            } else {
                "failed"
            }
        } catch (_: Throwable) {
            "failed"
        }
    }

    private suspend fun clearInternal() {
        DeviceKeyStore.delete(context)
        SnapshotStore.clear(context)
        QuickRefresh.cancelAll(context)
        SnapshotStore.onChanged(context)
        WearSync.clearContext(context)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    companion object {
        const val CHANNEL_NAME = "carecoins/extensions"

        fun register(context: Context, messenger: BinaryMessenger): ExtensionsBridge {
            val appCtx = context.applicationContext ?: context
            QuickRefresh.ensureWired()
            if (DeviceKeyStore.isConnected(appCtx)) {
                QuickRefresh.schedule(appCtx)
            }
            val channel = MethodChannel(messenger, CHANNEL_NAME)
            val bridge = ExtensionsBridge(appCtx, channel)
            channel.setMethodCallHandler(bridge)
            return bridge
        }
    }
}
