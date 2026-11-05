package com.carecoins.carecoins_flutter.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.wear.compose.material3.Text

// Phase A0 placeholder. QA-4 replaces it with the task list.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { Text("CareCoins") }
    }
}
