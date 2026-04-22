import Foundation
import Observation
import OSLog

#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class AudioCacheStore {
    static let shared = AudioCacheStore()

    private struct CachedAudioEntry: Codable {
        var videoID: String
        var relativePath: String
        var originalURL: String
        var title: String
        var createdAt: Date
        var lastAccessedAt: Date
        var byteSize: Int64
    }

    private enum QueueSource: String, Codable {
        case playback
        case playlist
    }

    private struct QueueJob: Codable, Hashable {
        var videoID: String
        var remoteURL: URL
        var title: String
        var source: QueueSource
    }

    private let logger = Logger(subsystem: "com.eulab.ytbackground", category: "AudioCache")
    private let fileManager = FileManager.default
    private let metadataURL: URL
    private let cacheDirectory: URL
    private let queueStateKey = "audio-cache.queue"

#if canImport(UIKit)
    @ObservationIgnored private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
#endif

    var cacheSizeBytes: Int64 = 0
    var queuedVideoIDs: [String] = []
    var activeVideoID: String?

    @ObservationIgnored private var metadata: [String: CachedAudioEntry] = [:]
    @ObservationIgnored private var queue: [QueueJob] = []
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    private init() {
        cacheDirectory = AppGroup.containerURL.appendingPathComponent("AudioCache", isDirectory: true)
        metadataURL = cacheDirectory.appendingPathComponent("cache-index.json")

        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create audio cache directory: \(error.localizedDescription, privacy: .public)")
        }

        loadMetadata()
        loadQueueState()
        recomputeCacheSize()
        processQueueIfNeeded()
    }

    func cachedFileURL(for item: VideoItem) -> URL? {
        guard let entry = metadata[item.id] else { return nil }

        let fileURL = cacheDirectory.appendingPathComponent(entry.relativePath)
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            metadata[item.id] = nil
            persistMetadata()
            recomputeCacheSize()
            return nil
        }

        var updatedEntry = entry
        updatedEntry.lastAccessedAt = .now
        metadata[item.id] = updatedEntry
        persistMetadata()
        return fileURL
    }

    func preparePlaybackURL(for item: VideoItem) async throws -> URL {
        if let cachedURL = cachedFileURL(for: item) {
            logger.info("Using cached audio file. videoID=\(item.id, privacy: .public) path=\(cachedURL.path(percentEncoded: false), privacy: .public)")
            return cachedURL
        }

        guard let remoteURL = Configuration.resolvedAudioStreamURL(for: item.id, fallback: item.audioStreamURL) else {
            throw URLError(.badURL)
        }

        return try await downloadNow(item: item, remoteURL: remoteURL)
    }

    func enqueuePlaylistDownload(items: [VideoItem]) {
        let jobs = items.compactMap { item -> QueueJob? in
            guard metadata[item.id] == nil,
                  !queuedVideoIDs.contains(item.id),
                  activeVideoID != item.id,
                  let remoteURL = Configuration.resolvedAudioStreamURL(for: item.id, fallback: item.audioStreamURL) else {
                return nil
            }

            return QueueJob(videoID: item.id, remoteURL: remoteURL, title: item.title, source: .playlist)
        }

        guard !jobs.isEmpty else { return }
        queue.append(contentsOf: jobs)
        syncQueueState()
        processQueueIfNeeded()
    }

    func clearCache() throws {
        activeTask?.cancel()
        activeTask = nil
        activeVideoID = nil
        queue.removeAll()
        queuedVideoIDs.removeAll()
        AppGroup.defaults.removeObject(forKey: queueStateKey)

        if fileManager.fileExists(atPath: cacheDirectory.path(percentEncoded: false)) {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for url in contents where url.lastPathComponent != metadataURL.lastPathComponent {
                try? fileManager.removeItem(at: url)
            }
        }

        metadata.removeAll()
        persistMetadata()
        recomputeCacheSize()
    }

    private func downloadNow(item: VideoItem, remoteURL: URL) async throws -> URL {
        beginBackgroundTaskIfNeeded()
        activeTask?.cancel()
        activeVideoID = item.id
        syncQueueState()
        defer {
            activeVideoID = nil
            activeTask = nil
            endBackgroundTaskIfNeeded()
            syncQueueState()
            processQueueIfNeeded()
        }

        let task = Task<URL, Error> {
            try await download(item: item, remoteURL: remoteURL)
        }
        activeTask = Task {
            _ = try? await task.value
        }
        return try await task.value
    }

    private func processQueueIfNeeded() {
        guard activeVideoID == nil,
              activeTask == nil,
              let nextJob = queue.first else {
            return
        }

        queue.removeFirst()
        syncQueueState()
        activeVideoID = nextJob.videoID
        syncQueueState()

        activeTask = Task { [weak self] in
            guard let self else { return }
            self.beginBackgroundTaskIfNeeded()
            defer {
                Task { @MainActor in
                    self.endBackgroundTaskIfNeeded()
                    self.activeVideoID = nil
                    self.activeTask = nil
                    self.syncQueueState()
                    self.processQueueIfNeeded()
                }
            }

            do {
                let item = VideoItem(
                    id: nextJob.videoID,
                    title: nextJob.title,
                    channelTitle: "",
                    artworkURL: nil,
                    pageURL: URL(string: "https://youtube.com/watch?v=\(nextJob.videoID)")!,
                    audioStreamURL: nextJob.remoteURL,
                    durationText: nil,
                    playlistID: nil
                )
                _ = try await self.download(item: item, remoteURL: nextJob.remoteURL)
            } catch is CancellationError {
            } catch {
                self.logger.error("Queued audio download failed. videoID=\(nextJob.videoID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func download(item: VideoItem, remoteURL: URL) async throws -> URL {
        logger.info("Downloading audio for cache. videoID=\(item.id, privacy: .public) url=\(remoteURL.absoluteString, privacy: .public)")
        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let suggestedFileName = httpResponse.suggestedFilename ?? remoteURL.lastPathComponent
        let sanitizedBaseName = item.id.replacingOccurrences(of: "/", with: "_")
        let fileExtension = URL(fileURLWithPath: suggestedFileName).pathExtension.isEmpty ? "mp3" : URL(fileURLWithPath: suggestedFileName).pathExtension
        let relativePath = "\(sanitizedBaseName).\(fileExtension)"
        let destinationURL = cacheDirectory.appendingPathComponent(relativePath)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        let size = (try? destinationURL.resourceValues(forKeys: Set([URLResourceKey.fileSizeKey])).fileSize).map(Int64.init) ?? httpResponse.expectedContentLength

        metadata[item.id] = CachedAudioEntry(
            videoID: item.id,
            relativePath: relativePath,
            originalURL: remoteURL.absoluteString,
            title: item.title,
            createdAt: .now,
            lastAccessedAt: .now,
            byteSize: size
        )
        persistMetadata()
        recomputeCacheSize()
        logger.info("Cached audio file saved. videoID=\(item.id, privacy: .public) path=\(destinationURL.path(percentEncoded: false), privacy: .public) bytes=\(size, privacy: .public)")
        return destinationURL
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: CachedAudioEntry].self, from: data) else {
            metadata = [:]
            syncQueueState()
            return
        }

        metadata = decoded.filter { _, entry in
            fileManager.fileExists(atPath: cacheDirectory.appendingPathComponent(entry.relativePath).path(percentEncoded: false))
        }
        persistMetadata()
        syncQueueState()
    }

    private func persistMetadata() {
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    private func recomputeCacheSize() {
        cacheSizeBytes = metadata.values.reduce(into: 0) { partialResult, entry in
            partialResult += entry.byteSize
        }
    }

    private func syncQueueState() {
        queuedVideoIDs = queue.map(\.videoID)
        persistQueueState()
    }

    private func loadQueueState() {
        guard let data = AppGroup.defaults.data(forKey: queueStateKey),
              let storedQueue = try? JSONDecoder().decode([QueueJob].self, from: data) else {
            queue = []
            queuedVideoIDs = []
            return
        }

        queue = storedQueue.filter { metadata[$0.videoID] == nil }
        queuedVideoIDs = queue.map(\.videoID)
        persistQueueState()
    }

    private func persistQueueState() {
        if queue.isEmpty {
            AppGroup.defaults.removeObject(forKey: queueStateKey)
            return
        }

        if let data = try? JSONEncoder().encode(queue) {
            AppGroup.defaults.set(data, forKey: queueStateKey)
        }
    }

#if canImport(UIKit)
    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AudioCacheDownload") { [weak self] in
            Task { @MainActor in
                self?.activeTask?.cancel()
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
#else
    private func beginBackgroundTaskIfNeeded() {}
    private func endBackgroundTaskIfNeeded() {}
#endif
}
