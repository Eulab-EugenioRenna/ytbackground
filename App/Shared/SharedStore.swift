import Foundation

enum SharedStore {
    private static let snapshotKey = "playback.snapshot"
    private static let sharedURLKey = "shared.url"

    static func save(snapshot: PlaybackSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            AppGroup.defaults.set(data, forKey: snapshotKey)
        }
    }

    static func loadSnapshot() -> PlaybackSnapshot {
        guard let data = AppGroup.defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data) else {
            return PlaybackSnapshot(current: nil, queue: [], isPlaying: false, progress: 0, updatedAt: .now)
        }

        return snapshot
    }

    static func saveSharedURL(_ url: URL) {
        AppGroup.defaults.set(url.absoluteString, forKey: sharedURLKey)
    }

    static func consumeSharedURL() -> URL? {
        defer { AppGroup.defaults.removeObject(forKey: sharedURLKey) }
        guard let value = AppGroup.defaults.string(forKey: sharedURLKey) else { return nil }
        return URL(string: value)
    }
}
