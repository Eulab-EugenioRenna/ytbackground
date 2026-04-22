import SwiftData
import SwiftUI

struct RootView: View {
    private enum Tab: Hashable {
        case search
        case player
        case playlists
        case settings
    }

    @Bindable private var playbackService = PlaybackService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .search

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                SearchView()
                    .tag(Tab.search)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                PlayerView()
                    .tag(Tab.player)
                    .tabItem {
                        Label("Player", systemImage: "play.circle")
                    }

                PlaylistsView()
                    .tag(Tab.playlists)
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }

                SettingsView()
                    .tag(Tab.settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }

            if let currentItem = playbackService.currentItem {
                MiniPlayerBar(item: currentItem, isPlaying: playbackService.isPlaying) {
                    playbackService.togglePlayback()
                } onOpen: {
                    selectedTab = .player
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 56)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            if let sharedURL = SharedStore.consumeSharedURL() {
                await handleSharedURL(sharedURL)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "ytbackground" else { return }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let shared = components.queryItems?.first(where: { $0.name == "shared" })?.value,
               let decoded = URL(string: shared) {
                Task { await handleSharedURL(decoded) }
            }
        }
    }

    private func handleSharedURL(_ url: URL) async {
        let apiClient = YouTubeAPIClient()
        if let videoID = YouTubeURLParser.videoID(from: url) {
            let item = VideoItem(
                id: videoID,
                title: "Shared YouTube Video",
                channelTitle: "Imported",
                artworkURL: nil,
                pageURL: url,
                audioStreamURL: nil,
                durationText: nil,
                playlistID: nil
            )
            playbackService.enqueue(item)
            selectedTab = .player
        } else if YouTubeURLParser.playlistID(from: url) != nil {
            let repository = PlaylistRepository(context: modelContext)
            let items = (try? await apiClient.importPlaylist(from: url)) ?? []
            try? repository.importPlaylist(title: "Shared Playlist", items: items)
            AudioCacheStore.shared.enqueuePlaylistDownload(items: items)
        }
    }
}

private struct MiniPlayerBar: View {
    let item: VideoItem
    let isPlaying: Bool
    let action: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture(perform: onOpen)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .onTapGesture(perform: onOpen)

            Spacer()

            Button(action: action) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
