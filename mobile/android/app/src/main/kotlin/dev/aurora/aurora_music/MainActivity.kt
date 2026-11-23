package dev.aurora.aurora_music

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (not FlutterActivity) is required so media buttons and
// the Android Auto / notification session talk to the running Flutter engine.
class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aurora/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        AuroraWidgetProvider.refresh(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
