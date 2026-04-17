import Foundation

struct YouTubePlayerResponse: Decodable {
    struct PlayabilityStatus: Decodable {
        let status: String?
        let reason: String?
    }

    struct StreamingData: Decodable {
        struct Format: Decodable {
            let mimeType: String?
            let url: String?
            let signatureCipher: String?
            let cipher: String?
            let bitrate: Int?
        }

        let adaptiveFormats: [Format]?
        let formats: [Format]?
        let hlsManifestUrl: String?
    }

    let playabilityStatus: PlayabilityStatus?
    let streamingData: StreamingData?
}

actor YouTubeStreamResolver {
    private struct ClientConfiguration {
        let name: String
        let version: String
        let extraClientFields: [String: Any]
        let extraBodyFields: [String: Any]
    }

    private let session: URLSession
    private let decoder = JSONDecoder()

    private let clientConfigurations: [ClientConfiguration] = [
        ClientConfiguration(
            name: "IOS",
            version: "19.09.3",
            extraClientFields: ["deviceModel": "iPhone14,3", "osName": "iPhone", "osVersion": "17.4.1"],
            extraBodyFields: [:]
        ),
        ClientConfiguration(
            name: "ANDROID",
            version: "19.08.35",
            extraClientFields: ["androidSdkVersion": 34, "osName": "Android", "osVersion": "14"],
            extraBodyFields: [:]
        ),
        ClientConfiguration(
            name: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
            version: "2.0",
            extraClientFields: ["clientScreen": "EMBED"],
            extraBodyFields: ["thirdParty": ["embedUrl": "https://www.youtube.com/"]]
        )
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolveStreamURL(for videoID: String) async throws -> URL? {
        for configuration in clientConfigurations {
            if let streamURL = try await resolveWithPlayerAPI(for: videoID, configuration: configuration) {
                return streamURL
            }
        }

        return try await resolveFromWatchPage(for: videoID)
    }

    private func resolveWithPlayerAPI(for videoID: String, configuration: ClientConfiguration) async throws -> URL? {
        let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/watch?v=\(videoID)", forHTTPHeaderField: "Referer")
        request.setValue(configuration.name, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(configuration.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("com.google.ios.youtube/19.09.3 (iPhone14,3; U; CPU iOS 17_4_1 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var client: [String: Any] = [
            "clientName": configuration.name,
            "clientVersion": configuration.version,
            "hl": "en",
            "timeZone": "UTC"
        ]
        configuration.extraClientFields.forEach { client[$0.key] = $0.value }

        var body: [String: Any] = [
            "context": ["client": client],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        configuration.extraBodyFields.forEach { body[$0.key] = $0.value }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(YouTubePlayerResponse.self, from: data)

        if let hlsManifestURL = response.streamingData?.hlsManifestUrl.flatMap(URL.init(string:)) {
            return hlsManifestURL
        }

        let formats = (response.streamingData?.adaptiveFormats ?? []) + (response.streamingData?.formats ?? [])
        let audioFormats = formats
            .filter { $0.mimeType?.contains("audio/") == true || $0.mimeType?.contains("mp4") == true }
            .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }

        for format in audioFormats {
            if let url = resolvedURL(from: format) {
                return url
            }
        }

        return nil
    }

    private func resolvedURL(from format: YouTubePlayerResponse.StreamingData.Format) -> URL? {
        if let url = format.url.flatMap(URL.init(string:)) {
            return url
        }

        let cipher = format.signatureCipher ?? format.cipher
        guard let cipher else { return nil }
        var components = URLComponents()
        components.query = cipher
        let queryItems = components.queryItems ?? []
        guard let urlValue = queryItems.first(where: { $0.name == "url" })?.value,
              var urlComponents = URLComponents(string: urlValue) else {
            return nil
        }

        if let signature = queryItems.first(where: { $0.name == "sig" || $0.name == "signature" })?.value {
            let signatureName = queryItems.first(where: { $0.name == "sp" })?.value ?? "signature"
            var items = urlComponents.queryItems ?? []
            items.append(URLQueryItem(name: signatureName, value: signature))
            urlComponents.queryItems = items
            return urlComponents.url
        }

        return urlComponents.url
    }

    private func resolveFromWatchPage(for videoID: String) async throws -> URL? {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoID)")!)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8),
              let playerResponse = extractPlayerResponse(from: html),
              let playerData = playerResponse.data(using: .utf8) else {
            return nil
        }

        let response = try decoder.decode(YouTubePlayerResponse.self, from: playerData)
        let formats = (response.streamingData?.adaptiveFormats ?? []) + (response.streamingData?.formats ?? [])
        let audioFormats = formats
            .filter { $0.mimeType?.contains("audio/") == true || $0.mimeType?.contains("mp4") == true }
            .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }

        for format in audioFormats {
            if let url = resolvedURL(from: format) {
                return url
            }
        }

        return response.streamingData?.hlsManifestUrl.flatMap(URL.init(string:))
    }

    private func extractPlayerResponse(from html: String) -> String? {
        let markers = ["var ytInitialPlayerResponse = ", "ytInitialPlayerResponse = "]

        for marker in markers {
            guard let markerRange = html.range(of: marker) else { continue }
            let payloadStart = markerRange.upperBound
            guard let scriptEnd = html[payloadStart...].range(of: ";</script>") else { continue }
            return String(html[payloadStart..<scriptEnd.lowerBound])
        }

        return nil
    }
}
