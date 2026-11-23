import ActivityKit
import Foundation

/// Shared between the app and the widget extension. ActivityKit matches the two
/// by this exact type, so both targets must compile it.
@available(iOS 16.2, *)
struct AuroraAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var position: Double
        var duration: Double
    }

    /// The video id, so a tap can deep-link to the right track.
    var videoId: String
}
