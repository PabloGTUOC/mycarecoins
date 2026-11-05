package com.carecoins.carecoins_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var extensionsBridge: ExtensionsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        extensionsBridge?.dispose()
        extensionsBridge = ExtensionsBridge.register(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        extensionsBridge?.dispose()
        extensionsBridge = null
        super.onDestroy()
    }
}
