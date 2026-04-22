import SwiftUI

struct SettingsView: View {
    @Bindable private var audioCache = AudioCacheStore.shared
    @State private var clearError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Cache audio") {
                    LabeledContent("Spazio occupato") {
                        Text(formattedSize(audioCache.cacheSizeBytes))
                    }

                    if let activeVideoID = audioCache.activeVideoID {
                        LabeledContent("Download attivo") {
                            Text(activeVideoID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !audioCache.queuedVideoIDs.isEmpty {
                        LabeledContent("In coda") {
                            Text("\(audioCache.queuedVideoIDs.count)")
                        }
                    }

                    Button("Pulisci cache", role: .destructive) {
                        do {
                            try audioCache.clearCache()
                            clearError = nil
                        } catch {
                            clearError = error.localizedDescription
                        }
                    }
                }

                Section("Playlist") {
                    Text("I brani delle playlist vengono scaricati in coda e restano disponibili nella cache persistente per la riproduzione locale.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Pulizia cache fallita", isPresented: .constant(clearError != nil), actions: {
                Button("OK") { clearError = nil }
            }, message: {
                Text(clearError ?? "")
            })
        }
    }

    private func formattedSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
