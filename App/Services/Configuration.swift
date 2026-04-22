import Foundation

enum Configuration {
    static var youtubeAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_DATA_API_KEY") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var audioServerBaseURL: URL? {
        let rawValue = (Bundle.main.object(forInfoDictionaryKey: "AUDIO_SERVER_BASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }
        guard let url = URL(string: rawValue),
              let scheme = url.scheme,
              !scheme.isEmpty,
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return url
    }

    static func audioStreamURL(for videoID: String) -> URL? {
        guard let audioServerBaseURL else { return nil }
        // iOS AVPlayer does not reliably handle the raw WebM stream exposed by /audio/stream.
        // /audio/file responds with an actual MP3 file, which CoreMedia can play.
        var components = URLComponents(url: audioServerBaseURL.appendingPathComponent("audio/file"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "videoId", value: videoID)]
        return components?.url
    }

    static func resolvedAudioStreamURL(for videoID: String, fallback: URL?) -> URL? {
        audioStreamURL(for: videoID) ?? fallback
    }
}
