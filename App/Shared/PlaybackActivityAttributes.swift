#if canImport(ActivityKit)
import ActivityKit

struct PlaybackActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var channelTitle: String
        var artworkURLString: String?
        var isPlaying: Bool
        var progress: Double
        var duration: Double
    }

    var id: String
}
#endif
