package com.burnrate.burnrate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var offlineCoachChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        offlineCoachChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OfflineCoachChannel.CHANNEL,
        )
        offlineCoachChannel.setMethodCallHandler(
            OfflineCoachChannel(applicationContext),
        )
    }
}
