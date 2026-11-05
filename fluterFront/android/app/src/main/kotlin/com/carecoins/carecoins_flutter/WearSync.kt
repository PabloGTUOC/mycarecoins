package com.carecoins.carecoins_flutter

import android.content.Context
import android.net.Uri
import android.util.Log
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.SnapshotStore
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

object WearSync {
    private const val TAG = "WearSync"
    const val CONTEXT_PATH = "/carecoins/context"

    suspend fun pushContext(
        context: Context,
        deviceKey: String = DeviceKeyStore.read(context).orEmpty(),
        apiBase: String = DeviceKeyStore.readApiBase(context).orEmpty(),
        snapshot: String = SnapshotStore.loadRaw(context) ?: "{}",
        language: String = L10n.getLanguage(context).orEmpty(),
    ) {
        try {
            val putReq = PutDataMapRequest.create(CONTEXT_PATH).apply {
                dataMap.putString("deviceKey", deviceKey)
                dataMap.putString("apiBase", apiBase)
                dataMap.putString("snapshot", snapshot)
                dataMap.putString("language", language)
                dataMap.putLong("sentAt", System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(context).putDataItem(putReq).await()
        } catch (t: Throwable) {
            Log.d(TAG, "WearSync.pushContext ignored: ${t.message}")
        }
    }

    suspend fun clearContext(context: Context) {
        try {
            val uri = Uri.Builder()
                .scheme(PutDataRequest.WEAR_URI_SCHEME)
                .path(CONTEXT_PATH)
                .build()
            Wearable.getDataClient(context)
                .deleteDataItems(uri, DataClient.FILTER_LITERAL)
                .await()
        } catch (t: Throwable) {
            Log.d(TAG, "WearSync.clearContext ignored: ${t.message}")
        }
    }
}
