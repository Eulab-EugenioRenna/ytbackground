import Foundation

struct VideoItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var channelTitle: String
    var artworkURL: URL?
    var pageURL: URL
    var audioStreamURL: URL?
    var durationText: String?
    var playlistID: String?
}

struct PlaybackSnapshot: Codable {
    var current: VideoItem?
    var queue: [VideoItem]
    var isPlaying: Bool
    var progress: Double
    var updatedAt: Date
}
