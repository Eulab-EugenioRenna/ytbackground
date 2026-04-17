import SwiftData
import SwiftUI

private func playbackURL(for item: VideoItem) -> URL? {
    item.audioStreamURL ?? Configuration.audioStreamURL(for: item.id)
}

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var playlistItem: VideoItem?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.results.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Cerca su YouTube",
                        systemImage: "magnifyingglass.circle",
                        description: Text("Trova un video, riproducilo nell'app o salvalo in una playlist persistente.")
                    )
                } else {
                    List(viewModel.results) { item in
                        VideoRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if playbackURL(for: item) != nil {
                                    PlaybackService.shared.play(item: item, queue: viewModel.results)
                                }
                            }
                            .contextMenu {
                                Button("Riproduci") {
                                    PlaybackService.shared.play(item: item, queue: viewModel.results)
                                }
                                .disabled(playbackURL(for: item) == nil)
                                Button("Aggiungi alla coda") {
                                    PlaybackService.shared.enqueue(item)
                                }
                                Button("Aggiungi a playlist") {
                                    playlistItem = item
                                }
                            }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Video, artisti, podcast")
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Ricerca in corso")
                }
            }
            .task(id: viewModel.query) {
                if viewModel.query.count > 2 {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await viewModel.search()
                }
            }
            .alert("Errore", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("OK") { viewModel.errorMessage = nil }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .sheet(item: $playlistItem) { item in
                PlaylistPickerSheet(item: item)
            }
        }
    }
}

struct VideoRow: View {
    let item: VideoItem

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [.orange.opacity(0.6), .pink.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.channelTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(item.durationText ?? "Ready to play")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if playbackURL(for: item) == nil {
                    Label("Stream audio non disponibile", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.channelTitle)")
    }
}
