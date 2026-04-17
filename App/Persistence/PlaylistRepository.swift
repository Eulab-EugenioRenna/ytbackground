import Foundation
import SwiftData

@MainActor
final class PlaylistRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func playlists() throws -> [PlaylistRecord] {
        let descriptor = FetchDescriptor<PlaylistRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    func createPlaylist(title: String) throws -> PlaylistRecord {
        let playlist = PlaylistRecord(title: title)
        context.insert(playlist)
        try context.save()
        return playlist
    }

    func add(_ item: VideoItem, to playlist: PlaylistRecord) throws {
        let position = (playlist.items.map(\.position).max() ?? -1) + 1
        let record = PlaylistItemRecord(position: position, item: item)
        record.playlist = playlist
        playlist.updatedAt = .now
        context.insert(record)
        try context.save()
    }

    func importPlaylist(title: String, items: [VideoItem]) throws {
        let playlist = PlaylistRecord(title: title)
        context.insert(playlist)
        for (index, item) in items.enumerated() {
            let record = PlaylistItemRecord(position: index, item: item)
            record.playlist = playlist
            context.insert(record)
        }
        try context.save()
    }

    func rename(_ playlist: PlaylistRecord, title: String) throws {
        playlist.title = title
        playlist.updatedAt = .now
        try context.save()
    }

    func delete(_ playlist: PlaylistRecord) throws {
        context.delete(playlist)
        try context.save()
    }

    func deleteItem(_ item: PlaylistItemRecord, from playlist: PlaylistRecord) throws {
        context.delete(item)
        playlist.updatedAt = .now
        try context.save()
    }
}
