package com.carecoins.carecoins_flutter.wear

import android.content.Context

/**
 * Hooks invoked after each snapshot refresh or disconnect.
 * QA-4 adds complication updates, tile updates and reminder scheduling here.
 */
object WearHooks {
    fun onSnapshot(context: Context) {
        // No-op in QA-3; QA-4 populates this hook.
    }

    fun cancelReminders(context: Context) {
        // No-op in QA-3; QA-4 populates this hook.
    }
}
