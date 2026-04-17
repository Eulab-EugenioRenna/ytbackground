import Foundation

enum Configuration {
    static var youtubeAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_DATA_API_KEY") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var audioServerBaseURL: URL? {
        let rawValue = (Bundle.main.object(forInfoDictionaryKey: "AUDIO_SERVER_BASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }
        return URL(string: rawValue)
    }

    static func audioStreamURL(for videoID: String) -> URL? {
        guard let audioServerBaseURL else { return nil }
        var components = URLComponents(url: audioServerBaseURL.appendingPathComponent("audio/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "videoId", value: videoID)]
        return components?.url
    }
}
