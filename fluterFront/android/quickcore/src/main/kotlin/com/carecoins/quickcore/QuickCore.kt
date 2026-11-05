package com.carecoins.quickcore

import android.content.Context

/** File names and keys shared by the phone app, the widget and the Wear OS app. */
object QuickCore {
    const val SNAPSHOT_FILE = "quick.json"
    const val LAST_ACTION_FILE = "lastAction.json"
    const val PREFS_NAME = "carecoins.quick"
    const val KEY_ALIAS = "carecoins.deviceKey"
    const val PREF_DEVICE_KEY_ID = "deviceKeyId"
    const val PREF_API_BASE = "apiBase"
    const val PREF_LANGUAGE = "language"

    fun disconnectLocally(context: Context) {
        DeviceKeyStore.delete(context)
        SnapshotStore.clear(context)
        SnapshotStore.onChanged(context)
    }
}
