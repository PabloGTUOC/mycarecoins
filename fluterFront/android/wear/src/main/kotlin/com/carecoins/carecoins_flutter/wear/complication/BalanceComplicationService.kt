package com.carecoins.carecoins_flutter.wear.complication

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.carecoins.carecoins_flutter.wear.MainActivity
import com.carecoins.carecoins_flutter.wear.R
import com.carecoins.quickcore.L10n
import com.carecoins.quickcore.SnapshotStore

class BalanceComplicationService : SuspendingComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val ctx = applicationContext ?: this
        return buildBalanceData(
            context = ctx,
            type = type,
            balance = 120,
            includeTapAction = false,
        )
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val ctx = applicationContext ?: this
        val snapshot = SnapshotStore.load(ctx)
        return buildBalanceData(
            context = ctx,
            type = request.complicationType,
            balance = snapshot?.balance,
            includeTapAction = true,
        )
    }

    companion object {
        private const val REQUEST_CODE_OPEN = 3001

        fun buildBalanceData(
            context: Context,
            type: ComplicationType,
            balance: Int?,
            includeTapAction: Boolean,
        ): ComplicationData? {
            val icon = MonochromaticImage.Builder(
                Icon.createWithResource(context, R.drawable.ic_stat_carecoins),
            ).build()
            val tapAction = if (includeTapAction) openAppPendingIntent(context) else null

            return when (type) {
                ComplicationType.SHORT_TEXT -> {
                    val textStr = balance?.toString() ?: "--"
                    val descStr = if (balance != null) {
                        L10n.t(context, "widget.a11y.balance", balance)
                    } else {
                        L10n.t(context, "widget.notConnected")
                    }
                    ShortTextComplicationData.Builder(
                        text = PlainComplicationText.Builder(textStr).build(),
                        contentDescription = PlainComplicationText.Builder(descStr).build(),
                    )
                        .setMonochromaticImage(icon)
                        .setTapAction(tapAction)
                        .build()
                }
                ComplicationType.LONG_TEXT -> {
                    val textStr = if (balance != null) {
                        L10n.t(context, "widget.coins", balance)
                    } else {
                        L10n.t(context, "widget.notConnected")
                    }
                    val descStr = if (balance != null) {
                        L10n.t(context, "widget.a11y.balance", balance)
                    } else {
                        textStr
                    }
                    LongTextComplicationData.Builder(
                        text = PlainComplicationText.Builder(textStr).build(),
                        contentDescription = PlainComplicationText.Builder(descStr).build(),
                    )
                        .setMonochromaticImage(icon)
                        .setTapAction(tapAction)
                        .build()
                }
                else -> null
            }
        }

        private fun openAppPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                REQUEST_CODE_OPEN,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
