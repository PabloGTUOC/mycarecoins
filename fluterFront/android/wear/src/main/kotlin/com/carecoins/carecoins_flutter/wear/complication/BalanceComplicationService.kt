package com.carecoins.carecoins_flutter.wear.complication

import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService

/** Minimal stub for QA-3; QA-4 implements the balance complication data source. */
class BalanceComplicationService : SuspendingComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType): ComplicationData? = null

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? = null
}
