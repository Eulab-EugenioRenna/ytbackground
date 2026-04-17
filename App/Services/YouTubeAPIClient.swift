import Foundation

struct YouTubeSearchResponse: Decodable {
    struct Item: Decodable {
        struct Identifier: Decodable {
            let videoId: String?
        }

        struct Snippet: Decodable {
            struct ThumbnailSet: Decodable {
                struct Thumbnail: Decodable { let url: String }
                let medium: Thumbnail?
                let high: Thumbnail?
            }

            let title: String
            let channelTitle: String
            let thumbnails: ThumbnailSet
        }

        let id: Identifier
        let snippet: Snippet
    }

    let items: [Item]
}

struct YouTubePlaylistResponse: Decodable {
    struct Item: Decodable {
        struct Snippet: Decodable {
            struct ResourceID: Decodable { let videoId: String }
            struct ThumbnailSet: Decodable {
                struct Thumbnail: Decodable { let url: String }
                let medium: Thumbnail?
                let high: Thumbnail?
            }

            let title: String
            let channelTitle: String
            let resourceId: ResourceID
            let thumbnails: ThumbnailSet
        }

        let snippet: Snippet
    }

    let items: [Item]
}

actor YouTubeAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchVideos(query: String) async throws -> [VideoItem] {
        guard !Configuration.youtubeAPIKey.isEmpty else {
            return []
        }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: Configuration.youtubeAPIKey)
        ]

        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
        return response.items.compactMap { item in
            guard let videoId = item.id.videoId else { return nil }
            return VideoItem(
                id: videoId,
                title: item.snippet.title,
                channelTitle: item.snippet.channelTitle,
                artworkURL: URL(string: item.snippet.thumbnails.high?.url ?? item.snippet.thumbnails.medium?.url ?? ""),
                pageURL: URL(string: "https://www.youtube.com/watch?v=\(videoId)")!,
                audioStreamURL: Configuration.audioStreamURL(for: videoId),
                durationText: nil,
                playlistID: nil
            )
        }
    }

    func importPlaylist(from url: URL) async throws -> [VideoItem] {
        guard !Configuration.youtubeAPIKey.isEmpty,
              let playlistID = YouTubeURLParser.playlistID(from: url) else {
            return []
        }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "key", value: Configuration.youtubeAPIKey)
        ]

        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(YouTubePlaylistResponse.self, from: data)
        return response.items.map { item in
            let videoId = item.snippet.resourceId.videoId
            return VideoItem(
                id: videoId,
                title: item.snippet.title,
                channelTitle: item.snippet.channelTitle,
                artworkURL: URL(string: item.snippet.thumbnails.high?.url ?? item.snippet.thumbnails.medium?.url ?? ""),
                pageURL: URL(string: "https://www.youtube.com/watch?v=\(videoId)")!,
                audioStreamURL: Configuration.audioStreamURL(for: videoId),
                durationText: nil,
                playlistID: playlistID
            )
        }
    }
}
