import ActivityKit
import Flutter
import UIKit

/// Drives a Live Activity so the current track appears in the Dynamic Island
/// and on the lock screen as *our own* card.
///
/// Why this exists: the system Now Playing widget opens the app by resolving the
/// audio session through LaunchServices, which self-signed (Feather/AltStore)
/// installs cannot do, so tapping it does nothing. A Live Activity is our own
/// extension, so its `widgetURL` opens the app normally.
@available(iOS 16.2, *)
final class AuroraLiveActivityManager {
  static let shared = AuroraLiveActivityManager()

  private var activity: Activity<AuroraAttributes>?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start", "update":
      let args = call.arguments as? [String: Any] ?? [:]
      Task { await apply(args, result: result) }
    case "end":
      Task {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func apply(_ args: [String: Any], result: @escaping FlutterResult) async {
    let videoId = args["id"] as? String ?? ""
    let state = AuroraAttributes.ContentState(
      title: args["title"] as? String ?? "Unknown track",
      artist: args["artist"] as? String ?? "",
      isPlaying: args["isPlaying"] as? Bool ?? false,
      position: args["position"] as? Double ?? 0,
      duration: args["duration"] as? Double ?? 0
    )

    if let activity {
      await activity.update(.init(state: state, staleDate: nil))
      result(nil)
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(FlutterError(
        code: "disabled",
        message: "Live Activities are disabled for this app in iOS settings",
        details: nil))
      return
    }

    do {
      activity = try Activity.request(
        attributes: AuroraAttributes(videoId: videoId),
        content: .init(state: state, staleDate: nil),
        pushType: nil
      )
      result(nil)
    } catch {
      result(FlutterError(
        code: "start_failed",
        message: error.localizedDescription,
        details: nil))
    }
  }
}
