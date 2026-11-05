package com.carecoins.carecoins_flutter.wear

import android.content.ComponentName
import android.content.Context
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.carecoins.carecoins_flutter.wear.complication.BalanceComplicationService
import com.carecoins.carecoins_flutter.wear.complication.NextComplicationService
import com.carecoins.carecoins_flutter.wear.reminders.Reminders
import com.carecoins.carecoins_flutter.wear.tile.QuickTileService
import com.carecoins.quickcore.DeviceKeyStore
import com.carecoins.quickcore.SnapshotStore
import java.time.Instant

object WearHooks {
    fun onSnapshot(context: Context) {
        val appCtx = context.applicationContext ?: context
        runCatching {
            ComplicationDataSourceUpdateRequester.create(
                appCtx,
                ComponentName(appCtx, BalanceComplicationService::class.java),
            ).requestUpdateAll()
        }
        runCatching {
            ComplicationDataSourceUpdateRequester.create(
                appCtx,
                ComponentName(appCtx, NextComplicationService::class.java),
            ).requestUpdateAll()
        }
        runCatching {
            TileService.getUpdater(appCtx).requestUpdate(QuickTileService::class.java)
        }
        val snapshot = if (DeviceKeyStore.isConnected(appCtx)) SnapshotStore.load(appCtx) else null
        Reminders.reschedule(appCtx, snapshot, Instant.now())
    }

    fun cancelReminders(context: Context) {
        val appCtx = context.applicationContext ?: context
        Reminders.cancelAll(appCtx)
    }
}
