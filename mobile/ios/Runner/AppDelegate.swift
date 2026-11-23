import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry
      .registrar(forPlugin: "AuroraLiveActivityBridge") else { return }

    let channel = FlutterMethodChannel(
      name: "aurora/live_activity",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if #available(iOS 16.2, *) {
        AuroraLiveActivityManager.shared.handle(call, result: result)
      } else {
        result(FlutterError(code: "unsupported", message: "iOS 16.2+ required", details: nil))
      }
    }
  }
}
