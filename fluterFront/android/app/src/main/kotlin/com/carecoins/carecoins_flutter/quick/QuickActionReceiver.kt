package com.carecoins.carecoins_flutter.quick

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class QuickActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra(EXTRA_ACTION) ?: return
        val id = intent.getStringExtra(EXTRA_ID).orEmpty()
        val pendingResult = goAsync()
        val appCtx = context.applicationContext ?: context
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                when (action) {
                    ACTION_START -> if (id.isNotEmpty()) QuickActions.start(appCtx, id)
                    ACTION_DONE -> QuickActions.done(appCtx, id)
                    ACTION_FINISH -> if (id.isNotEmpty()) QuickActions.finish(appCtx, id)
                    ACTION_CANCEL -> if (id.isNotEmpty()) QuickActions.cancel(appCtx, id)
                    ACTION_START_NOW -> QuickActions.startNow(appCtx, id.ifEmpty { "care" })
                    ACTION_STOP -> if (id.isNotEmpty()) QuickActions.stop(appCtx, id)
                    ACTION_UNDO -> QuickActions.undo(appCtx, id.takeIf { it.isNotEmpty() })
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        const val EXTRA_ACTION = "com.carecoins.carecoins_flutter.quick.EXTRA_ACTION"
        const val EXTRA_ID = "com.carecoins.carecoins_flutter.quick.EXTRA_ID"

        const val ACTION_START = "start"
        const val ACTION_DONE = "done"
        const val ACTION_FINISH = "finish"
        const val ACTION_CANCEL = "cancel"
        const val ACTION_START_NOW = "start_now"
        const val ACTION_STOP = "stop"
        const val ACTION_UNDO = "undo"
    }
}
