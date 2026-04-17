import SwiftUI

struct PlayerView: View {
    @Bindable var playbackService: PlaybackService = .shared
    @State private var playlistItem: VideoItem?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        artworkSurface(maxWidth: min(max(geometry.size.width - 32, 260), 420))
                        titleBlock
                        playbackStatus
                        controls
                        saveButton
                        queueSection
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Player")
            .sheet(item: $playlistItem) { item in
                PlaylistPickerSheet(item: item)
            }
        }
    }

    @ViewBuilder
    private func artworkSurface(maxWidth: CGFloat) -> some View {
        if let artworkURL = playbackService.currentItem?.artworkURL {
            AsyncImage(url: artworkURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderArtwork
            }
            .frame(maxWidth: maxWidth)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        } else {
            placeholderArtwork
                .frame(maxWidth: maxWidth)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        }
    }

    private var placeholderArtwork: some View {
        LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: playbackService.isPlaying ? "waveform.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Audio player")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(playbackService.currentItem?.title ?? "Nessun audio in riproduzione")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(playbackService.currentItem?.channelTitle ?? "Seleziona un elemento con stream audio diretto")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playbackStatus: some View {
        VStack(spacing: 8) {
            Label(playbackService.isPlaying ? "In riproduzione" : (playbackService.isPlayerReady ? "In pausa" : "In caricamento"), systemImage: playbackService.isPlaying ? "waveform" : "pause.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if playbackService.duration > 0 {
                Text(timeLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 20) {
            Slider(value: $playbackService.progress, in: 0...1) { _ in
                playbackService.seek(to: playbackService.progress)
            }
            .tint(.orange)
            .disabled(playbackService.currentItem == nil || playbackService.duration == 0)

            HStack(spacing: 28) {
                Button(action: playbackService.playPrevious) {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(PlayerButtonStyle())
                .disabled(playbackService.currentItem == nil)

                Button(action: playbackService.togglePlayback) {
                    Image(systemName: playbackService.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PlayerButtonStyle(primary: true))
                .disabled(playbackService.currentItem == nil)

                Button(action: playbackService.playNext) {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(PlayerButtonStyle())
                .disabled(playbackService.currentItem == nil)
            }

            if let errorMessage = playbackService.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if let currentItem = playbackService.currentItem {
            Button {
                playlistItem = currentItem
            } label: {
                Label("Aggiungi a playlist", systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queue")
                .font(.headline)
            ForEach(playbackService.queue) { item in
                Button {
                    playbackService.play(item: item, queue: playbackService.queue)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(item == playbackService.currentItem ? .orange : .secondary.opacity(0.2))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Text(item.channelTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            playlistItem = item
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeLabel: String {
        let currentSeconds = playbackService.duration * playbackService.progress
        return "\(format(seconds: currentSeconds)) / \(format(seconds: playbackService.duration))"
    }

    private func format(seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct PlayerButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: primary ? 28 : 22, weight: .bold))
            .foregroundStyle(primary ? .white : .primary)
            .frame(width: primary ? 72 : 56, height: primary ? 72 : 56)
            .background(primary ? AnyShapeStyle(.orange) : AnyShapeStyle(.thinMaterial))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
