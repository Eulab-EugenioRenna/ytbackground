import Foundation
import SwiftData

@Model
final class PlaylistRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PlaylistItemRecord.playlist) var items: [PlaylistItemRecord]

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = []
    }
}

@Model
final class PlaylistItemRecord {
    @Attribute(.unique) var id: UUID
    var position: Int
    var videoID: String
    var title: String
    var channelTitle: String
    var artworkURLString: String?
    var pageURLString: String
    var audioStreamURLString: String?
    var durationText: String?
    var playlist: PlaylistRecord?

    init(id: UUID = UUID(), position: Int, item: VideoItem) {
        self.id = id
        self.position = position
        self.videoID = item.id
        self.title = item.title
        self.channelTitle = item.channelTitle
        self.artworkURLString = item.artworkURL?.absoluteString
        self.pageURLString = item.pageURL.absoluteString
        self.audioStreamURLString = item.audioStreamURL?.absoluteString
        self.durationText = item.durationText
    }

    var videoItem: VideoItem {
        VideoItem(
            id: videoID,
            title: title,
            channelTitle: channelTitle,
            artworkURL: artworkURLString.flatMap(URL.init(string:)),
            pageURL: URL(string: pageURLString) ?? URL(string: "https://youtube.com/watch?v=\(videoID)")!,
            audioStreamURL: audioStreamURLString.flatMap(URL.init(string:)),
            durationText: durationText,
            playlistID: playlist?.id.uuidString
        )
    }
}
