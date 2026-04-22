import AVFoundation
import ActivityKit
import Foundation
import MediaPlayer
import Observation
import OSLog

#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class PlaybackService {
    static let shared = PlaybackService()
    @ObservationIgnored private let logger = Logger(subsystem: "com.eulab.ytbackground", category: "Playback")
    @ObservationIgnored private let audioCache = AudioCacheStore.shared

    var currentItem: VideoItem?
    var queue: [VideoItem] = []
    var isPlaying = false
    var progress: Double = 0
    var duration: Double = 0
    var errorMessage: String?
    var isPlayerReady = false

    @ObservationIgnored private var player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var currentItemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemEndedObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var localPlaybackTask: Task<Void, Never>?
    @ObservationIgnored private var localPlaybackVideoID: String?
    @ObservationIgnored private var currentArtworkURL: URL?
    @ObservationIgnored private var currentArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var liveActivity: Activity<PlaybackActivityAttributes>?
    @ObservationIgnored private var lastLiveActivityUpdateAt: Date = .distantPast

    init() {
        restoreSnapshot()
        configurePlayerObservers()
        configureRemoteCommands()
        configureAudioSessionObservers()
    }

    func play(item: VideoItem, queue: [VideoItem]? = nil) {
        localPlaybackTask?.cancel()
        localPlaybackTask = nil
        localPlaybackVideoID = nil

        if let queue {
            self.queue = queue
        } else if self.queue.isEmpty {
            self.queue = [item]
        }

        currentItem = item
        progress = 0
        duration = 0
        isPlaying = false
        isPlayerReady = false
        errorMessage = nil
        player.replaceCurrentItem(with: nil)

        guard let streamURL = Configuration.resolvedAudioStreamURL(for: item.id, fallback: item.audioStreamURL) else {
            logger.error("Missing valid audio stream URL. baseURL=\(String(describing: Configuration.audioServerBaseURL), privacy: .public) videoID=\(item.id, privacy: .public) fallback=\(String(describing: item.audioStreamURL), privacy: .public)")
            playerDidFail(message: "Questo elemento non ha uno stream audio diretto disponibile.")
            updateNowPlayingInfo()
            refreshLiveActivity(force: true)
            persistSnapshot()
            return
        }

        localPlaybackVideoID = item.id
        errorMessage = audioCache.cachedFileURL(for: item) == nil ? "Scarico audio in locale..." : nil
        logger.info("Preparing local playback. baseURL=\(String(describing: Configuration.audioServerBaseURL), privacy: .public) streamURL=\(streamURL.absoluteString, privacy: .public) videoID=\(item.id, privacy: .public)")

        localPlaybackTask = Task { [weak self] in
            guard let self else { return }

            do {
                let localURL = try await self.audioCache.preparePlaybackURL(for: item)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.currentItem?.id == item.id else { return }
                    self.logger.info("Starting local playback. videoID=\(item.id, privacy: .public) localURL=\(localURL.path(percentEncoded: false), privacy: .public)")
                    self.errorMessage = nil
                    self.startPlayback(url: localURL)
                    self.updateNowPlayingInfo()
                    self.refreshLiveActivity(force: true)
                    self.persistSnapshot()
                }
            } catch is CancellationError {
                await MainActor.run {
                    if self.localPlaybackVideoID == item.id {
                        self.localPlaybackVideoID = nil
                    }
                }
            } catch {
                await MainActor.run {
                    if self.localPlaybackVideoID == item.id {
                        self.localPlaybackVideoID = nil
                    }
                    self.playerDidFail(message: error.localizedDescription)
                }
            }
        }

        updateNowPlayingInfo()
        refreshLiveActivity(force: true)
        persistSnapshot()
    }

    func togglePlayback() {
        guard currentItem != nil else { return }

        if isPlaying {
            player.pause()
        } else if player.currentItem != nil {
            player.play()
        } else if let currentItem {
            play(item: currentItem, queue: queue)
        }

        updateNowPlayingInfo()
        refreshLiveActivity(force: true)
    }

    func playNext() {
        guard let currentItem,
              let index = queue.firstIndex(of: currentItem),
              queue.indices.contains(index + 1) else {
            isPlaying = false
            updateNowPlayingInfo()
            refreshLiveActivity(force: true)
            persistSnapshot()
            return
        }

        play(item: queue[index + 1], queue: queue)
    }

    func playPrevious() {
        guard let currentItem,
              let index = queue.firstIndex(of: currentItem),
              queue.indices.contains(index - 1) else { return }

        play(item: queue[index - 1], queue: queue)
    }

    func enqueue(_ item: VideoItem) {
        queue.append(item)
        persistSnapshot()
    }

    func replaceQueue(with items: [VideoItem], autoplay: Bool = false) {
        queue = items
        if autoplay, let first = items.first {
            play(item: first, queue: items)
        } else {
            persistSnapshot()
        }
    }

    func seek(to progress: Double) {
        guard duration > 0 else { return }

        self.progress = progress
        let seconds = duration * progress
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
        updateNowPlayingInfo()
        refreshLiveActivity(force: true)
        persistSnapshot()
    }

    func playerDidFail(message: String) {
        logger.error("Playback failed: \(message, privacy: .public)")
        isPlaying = false
        isPlayerReady = false
        errorMessage = message
        updateNowPlayingInfo()
        refreshLiveActivity(force: true)
        persistSnapshot()
    }

    private func configurePlayerObservers() {
        timeControlObservation = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                self.isPlaying = player.timeControlStatus == .playing
                if player.timeControlStatus == .playing {
                    self.errorMessage = nil
                }
                self.updateNowPlayingInfo()
                self.refreshLiveActivity()
                self.persistSnapshot()
            }
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = time.seconds
                guard seconds.isFinite else { return }

                if self.duration > 0 {
                    self.progress = min(max(seconds / self.duration, 0), 1)
                }

                self.updateNowPlayingInfo()
                self.refreshLiveActivity()
                self.persistSnapshot()
            }
        }
    }

    private func observeCurrentItem(_ playerItem: AVPlayerItem) {
        currentItemStatusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    Task {
                        let loadedDuration = try? await item.asset.load(.duration)
                        await MainActor.run {
                            let seconds = loadedDuration?.seconds ?? 0
                            self.duration = seconds.isFinite ? seconds : 0
                            self.isPlayerReady = true
                            self.errorMessage = nil
                            self.updateNowPlayingInfo()
                            self.refreshLiveActivity(force: true)
                            self.persistSnapshot()
                        }
                    }
                case .failed:
                    self.logger.error("AVPlayerItem failed. error=\(item.error?.localizedDescription ?? "unknown", privacy: .public) url=\(((item.asset as? AVURLAsset)?.url.absoluteString ?? "n/a"), privacy: .public)")
                    self.playerDidFail(message: item.error?.localizedDescription ?? "Impossibile avviare la riproduzione audio.")
                default:
                    self.isPlayerReady = false
                }
            }
        }

        if let itemEndedObserver {
            NotificationCenter.default.removeObserver(itemEndedObserver)
        }
        itemEndedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.progress = 1
                self?.persistSnapshot()
                self?.playNext()
            }
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if !self.isPlaying {
                    self.togglePlayback()
                }
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if self.isPlaying {
                    self.togglePlayback()
                }
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.playNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.playPrevious()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent,
                  self.duration > 0 else {
                return .commandFailed
            }

            Task { @MainActor in
                self.seek(to: min(max(event.positionTime / self.duration, 0), 1))
            }
            return .success
        }
    }

    private func configureAudioSessionObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawValue) else {
                return
            }

            Task { @MainActor in
                switch type {
                case .began:
                    self.player.pause()
                    self.isPlaying = false
                    self.updateNowPlayingInfo()
                    self.refreshLiveActivity(force: true)
                case .ended:
                    let optionsRawValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRawValue)
                    if options.contains(.shouldResume), self.currentItem != nil {
                        self.player.play()
                    }
                @unknown default:
                    break
                }
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue) else {
                return
            }

            Task { @MainActor in
                if reason == .oldDeviceUnavailable, self.isPlaying {
                    self.player.pause()
                    self.isPlaying = false
                    self.updateNowPlayingInfo()
                    self.refreshLiveActivity(force: true)
                }
            }
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let existingNowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: currentItem.title,
            MPMediaItemPropertyArtist: currentItem.channelTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: duration * progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if currentArtworkURL == currentItem.artworkURL,
           let currentArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = currentArtwork
        } else if let existingArtwork = existingNowPlayingInfo[MPMediaItemPropertyArtwork] {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = existingArtwork
        }

        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        loadArtworkIfNeeded(for: currentItem)
    }

    private func startPlayback(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        observeCurrentItem(playerItem)
        player.replaceCurrentItem(with: playerItem)
        player.play()
    }

    private func loadArtworkIfNeeded(for item: VideoItem) {
        if currentArtworkURL != item.artworkURL {
            currentArtworkURL = nil
            currentArtwork = nil
        }

        if currentArtworkURL == item.artworkURL, currentArtwork != nil {
            return
        }

        artworkTask?.cancel()
        guard let artworkURL = item.artworkURL else { return }

        artworkTask = Task { [weak self] in
            guard let self,
                  let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  let image = UIImage(data: data) else {
                return
            }

            await MainActor.run {
                guard self.currentItem?.artworkURL == artworkURL else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.currentArtworkURL = artworkURL
                self.currentArtwork = artwork
                var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        }
    }

    private func persistSnapshot() {
        SharedStore.save(snapshot: PlaybackSnapshot(current: currentItem, queue: queue, isPlaying: isPlaying, progress: progress, updatedAt: .now))
    }

    private func restoreSnapshot() {
        let snapshot = SharedStore.loadSnapshot()
        currentItem = snapshot.current
        queue = snapshot.queue
        isPlaying = snapshot.isPlaying
        progress = snapshot.progress
    }

    private func refreshLiveActivity(force: Bool = false) {
#if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let currentItem else {
            endLiveActivity()
            return
        }

        let now = Date()
        guard force || now.timeIntervalSince(lastLiveActivityUpdateAt) >= 15 else { return }
        lastLiveActivityUpdateAt = now

        let state = PlaybackActivityAttributes.ContentState(
            title: currentItem.title,
            channelTitle: currentItem.channelTitle,
            artworkURLString: currentItem.artworkURL?.absoluteString,
            isPlaying: isPlaying,
            progress: progress,
            duration: duration
        )

        Task {
            if let liveActivity {
                await liveActivity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                liveActivity = try? Activity.request(
                    attributes: PlaybackActivityAttributes(id: currentItem.id),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            }
        }
#endif
    }

    private func endLiveActivity() {
#if canImport(ActivityKit)
        guard let liveActivity else { return }

        Task {
            await liveActivity.end(ActivityContent(state: liveActivity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
#endif
    }
}
