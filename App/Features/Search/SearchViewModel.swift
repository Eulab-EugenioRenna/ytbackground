import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [VideoItem] = []
    var isLoading = false
    var errorMessage: String?

    private let apiClient = YouTubeAPIClient()

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            results = try await apiClient.searchVideos(query: trimmed)
            if results.isEmpty, Configuration.youtubeAPIKey.isEmpty {
                errorMessage = "Inserisci YOUTUBE_DATA_API_KEY in Config/Debug.xcconfig o Release.xcconfig."
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
