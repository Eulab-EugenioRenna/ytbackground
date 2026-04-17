import SwiftData
import SwiftUI

struct PlaylistPickerSheet: View {
    let item: VideoItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistRecord.updatedAt, order: .reverse) private var playlists: [PlaylistRecord]

    @State private var newPlaylistTitle = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Nuova playlist") {
                    TextField("Nome playlist", text: $newPlaylistTitle)
                    Button("Crea e aggiungi") {
                        createPlaylistAndAddItem()
                    }
                }

                Section("Aggiungi a playlist") {
                    if playlists.isEmpty {
                        Text("Crea una playlist per salvare rapidamente questo video.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                add(item, to: playlist)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.title)
                                            .foregroundStyle(.primary)
                                        Text("\(playlist.items.count) elementi")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Aggiungi a playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
            .alert("Errore", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
    }

    private func createPlaylistAndAddItem() {
        let repository = PlaylistRepository(context: modelContext)

        do {
            let playlist = try repository.createPlaylist(title: newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.title : newPlaylistTitle)
            try repository.add(item, to: playlist)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ item: VideoItem, to playlist: PlaylistRecord) {
        let repository = PlaylistRepository(context: modelContext)

        do {
            try repository.add(item, to: playlist)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
