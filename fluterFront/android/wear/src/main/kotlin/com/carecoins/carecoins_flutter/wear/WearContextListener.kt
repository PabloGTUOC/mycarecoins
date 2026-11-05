package com.carecoins.carecoins_flutter.wear

import android.content.Context
import android.net.Uri
import android.util.Log
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.QuickCore
import com.carecoins.quickcore.SnapshotStore
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.tasks.await

class WearContextListener : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val appCtx = applicationContext ?: this
        try {
            for (event in dataEvents) {
                if (event.dataItem.uri.path != CONTEXT_PATH) continue
                when (event.type) {
                    DataEvent.TYPE_DELETED -> {
                        handleDisconnected(appCtx)
                    }
                    DataEvent.TYPE_CHANGED -> {
                        val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                        val deviceKey = dataMap.getString("deviceKey").orEmpty()
                        val apiBase = dataMap.getString("apiBase").orEmpty()
                        val snapshot = dataMap.getString("snapshot").orEmpty()
                        val language = dataMap.getString("language").orEmpty()
                        applyContextPayload(
                            context = appCtx,
                            deviceKey = deviceKey,
                            apiBase = apiBase,
                            snapshot = snapshot,
                            language = language,
                        )
                    }
                }
            }
        } catch (t: Throwable) {
            Log.d(TAG, "onDataChanged ignored: ${t.message}")
        }
    }

    companion object {
        private const val TAG = "WearContextListener"
        const val CONTEXT_PATH = "/carecoins/context"

        fun applyContextPayload(
            context: Context,
            deviceKey: String,
            apiBase: String,
            snapshot: String,
            language: String,
        ) {
            val appCtx = context.applicationContext ?: context
            if (deviceKey.isBlank() || apiBase.isBlank()) {
                handleDisconnected(appCtx)
                return
            }
            DeviceKeyStore.store(
                context = appCtx,
                key = deviceKey,
                apiBase = apiBase,
            )
            if (snapshot.isNotBlank() && snapshot != "{}") {
                SnapshotStore.save(appCtx, snapshot)
            }
            L10n.setLanguage(appCtx, language)
            WearRefreshWorker.schedule(appCtx)
            WearHooks.onSnapshot(appCtx)
            WearStore.onContextChanged(appCtx)
        }

        fun handleDisconnected(context: Context) {
            val appCtx = context.applicationContext ?: context
            QuickCore.disconnectLocally(appCtx)
            WearHooks.cancelReminders(appCtx)
            WearRefreshWorker.cancel(appCtx)
            WearHooks.onSnapshot(appCtx)
            WearStore.onContextChanged(appCtx)
        }

        suspend fun readCurrentDataItemAtLaunch(context: Context) {
            val appCtx = context.applicationContext ?: context
            try {
                val uri = Uri.Builder()
                    .scheme(PutDataRequest.WEAR_URI_SCHEME)
                    .path(CONTEXT_PATH)
                    .build()
                val buffer = Wearable.getDataClient(appCtx)
                    .getDataItems(uri, DataClient.FILTER_LITERAL)
                    .await()
                try {
                    for (item in buffer) {
                        if (item.uri.path == CONTEXT_PATH) {
                            val dataMap = DataMapItem.fromDataItem(item).dataMap
                            val deviceKey = dataMap.getString("deviceKey").orEmpty()
                            val apiBase = dataMap.getString("apiBase").orEmpty()
                            val snapshot = dataMap.getString("snapshot").orEmpty()
                            val language = dataMap.getString("language").orEmpty()
                            applyContextPayload(
                                context = appCtx,
                                deviceKey = deviceKey,
                                apiBase = apiBase,
                                snapshot = snapshot,
                                language = language,
                            )
                        }
                    }
                } finally {
                    buffer.release()
                }
            } catch (t: Throwable) {
                Log.d(TAG, "readCurrentDataItemAtLaunch ignored: ${t.message}")
            }
        }
    }
}
