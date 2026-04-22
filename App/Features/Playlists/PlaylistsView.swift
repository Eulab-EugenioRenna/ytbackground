import SwiftData
import SwiftUI

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistRecord.updatedAt, order: .reverse) private var playlists: [PlaylistRecord]
    @State private var importURL = ""
    @State private var showingCreateSheet = false
    @State private var newPlaylistTitle = ""
    @State private var importError: String?
    @State private var renamePlaylist: PlaylistRecord?
    @State private var renameTitle = ""
    private let apiClient = YouTubeAPIClient()

    var body: some View {
        NavigationStack {
            List {
                Section("Importa da YouTube") {
                    TextField("Incolla URL playlist", text: $importURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Importa playlist") {
                        Task { await importPlaylist() }
                    }
                }

                Section {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(playlist.title)
                                    .font(.headline)
                                Text("\(playlist.items.count) elementi")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Elimina", role: .destructive) {
                                deletePlaylist(playlist)
                            }
                            Button("Rinomina") {
                                renameTitle = playlist.title
                                renamePlaylist = playlist
                            }
                            .tint(.orange)
                        }
                    }
                } header: {
                    Text("Le tue playlist")
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Crea playlist")
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                NavigationStack {
                    Form {
                        TextField("Nome playlist", text: $newPlaylistTitle)
                    }
                    .navigationTitle("Nuova playlist")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { showingCreateSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Salva") {
                                let repository = PlaylistRepository(context: modelContext)
                                _ = try? repository.createPlaylist(title: newPlaylistTitle.isEmpty ? "Nuova playlist" : newPlaylistTitle)
                                newPlaylistTitle = ""
                                showingCreateSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("Import fallito", isPresented: .constant(importError != nil), actions: {
                Button("OK") { importError = nil }
            }, message: {
                Text(importError ?? "")
            })
            .alert("Rinomina playlist", isPresented: .constant(renamePlaylist != nil), actions: {
                TextField("Titolo", text: $renameTitle)
                Button("Annulla", role: .cancel) {
                    renamePlaylist = nil
                }
                Button("Salva") {
                    guard let renamePlaylist else { return }
                    let repository = PlaylistRepository(context: modelContext)
                    try? repository.rename(renamePlaylist, title: renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? renamePlaylist.title : renameTitle)
                    self.renamePlaylist = nil
                }
            }, message: {
                Text("Aggiorna il nome della playlist.")
            })
        }
    }

    private func importPlaylist() async {
        guard let url = URL(string: importURL) else {
            importError = "URL non valido."
            return
        }

        do {
            let items = try await apiClient.importPlaylist(from: url)
            let repository = PlaylistRepository(context: modelContext)
            try repository.importPlaylist(title: "Imported Playlist", items: items)
            AudioCacheStore.shared.enqueuePlaylistDownload(items: items)
            importURL = ""
        } catch {
            importError = error.localizedDescription
        }
    }

    private func deletePlaylist(_ playlist: PlaylistRecord) {
        let repository = PlaylistRepository(context: modelContext)
        try? repository.delete(playlist)
    }
}

private struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let playlist: PlaylistRecord

    var sortedItems: [PlaylistItemRecord] {
        playlist.items.sorted { $0.position < $1.position }
    }

    var body: some View {
        List(sortedItems, id: \.id) { item in
            Button {
                let queue = sortedItems.map(\.videoItem)
                PlaybackService.shared.play(item: item.videoItem, queue: queue)
            } label: {
                VideoRow(item: item.videoItem)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Elimina", role: .destructive) {
                    let repository = PlaylistRepository(context: modelContext)
                    try? repository.deleteItem(item, from: playlist)
                }
            }
        }
        .navigationTitle(playlist.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Play All") {
                    let queue = sortedItems.map(\.videoItem)
                    AudioCacheStore.shared.enqueuePlaylistDownload(items: queue)
                    PlaybackService.shared.replaceQueue(with: queue, autoplay: true)
                }
            }
        }
    }
}
