import CoreGraphics
import Foundation

// Modèles de l'API Jellyfin (Treillis). Les champs JSON sont en PascalCase ;
// `JSONDecoder.jellyfin` les convertit en camelCase.

struct BaseItem: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let type: String?
    let overview: String?
    let productionYear: Int?
    let officialRating: String?
    let communityRating: Double?
    let runTimeTicks: Int64?
    let genres: [String]?
    let isFolder: Bool?

    let seriesName: String?
    let seriesId: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?

    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let parentBackdropItemId: String?
    let parentThumbItemId: String?
    let seriesPrimaryImageTag: String?
    let primaryImageAspectRatio: Double?

    let userData: UserData?

    let taglines: [String]?
    let studios: [NamedItem]?
    let people: [Person]?
    let providerIds: [String: String]?
    let premiereDate: String?

    struct NamedItem: Decodable, Hashable {
        let name: String?
        let id: String?
    }

    struct Person: Decodable, Hashable, Identifiable {
        let id: String
        let name: String?
        let role: String?
        let type: String?
        let primaryImageTag: String?
    }

    /// Identifiant externe (Imdb, Tmdb, Tvdb), quelle que soit la casse de la clé.
    func providerId(_ provider: String) -> String? {
        providerIds?.first { $0.key.caseInsensitiveCompare(provider) == .orderedSame }?.value
    }

    struct UserData: Decodable, Hashable {
        let playedPercentage: Double?
        let played: Bool?
        let isFavorite: Bool?
    }

    static func == (lhs: BaseItem, rhs: BaseItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var title: String { name ?? "" }

    var isSeries: Bool { type == "Series" }
    var isEpisode: Bool { type == "Episode" }
    var isLiveChannel: Bool { type == "TvChannel" }

    /// Dossiers à parcourir (collections, saisons…) plutôt qu'à lire.
    var isBrowsable: Bool {
        guard let type else { return isFolder == true }
        return ["BoxSet", "Folder", "CollectionFolder", "UserView", "Playlist", "ManualPlaylistsFolder"].contains(type)
    }

    /// Tag d'image, quelle que soit la casse de la clé.
    func imageTag(_ type: String) -> String? {
        guard let imageTags else { return nil }
        return imageTags[type] ?? imageTags[type.prefix(1).lowercased() + type.dropFirst()]
    }

    var subtitle: String? {
        if isEpisode {
            var parts: [String] = []
            if let seriesName { parts.append(seriesName) }
            if let season = parentIndexNumber, let episode = indexNumber { parts.append("S\(season)E\(episode)") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        return productionYear.map { String($0) }
    }

    var infoLine: String {
        var parts: [String] = []
        if let productionYear { parts.append(String(productionYear)) }
        if let officialRating { parts.append(officialRating) }
        if let runTimeTicks, runTimeTicks > 0 {
            let minutes = Int(runTimeTicks / 600_000_000)
            parts.append(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
        }
        if let communityRating { parts.append(String(format: "★ %.1f", communityRating)) }
        if let genres, !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// Ratio de l'affiche (largeur / hauteur).
    var posterRatio: CGFloat {
        if isLiveChannel { return 1 }
        if isEpisode { return 16 / 9 }
        if let primaryImageAspectRatio, primaryImageAspectRatio > 0 { return CGFloat(primaryImageAspectRatio) }
        return 2 / 3
    }
}

struct ItemsResponse: Decodable {
    let items: [BaseItem]?
    let totalRecordCount: Int?
}

struct AuthenticationResult: Decodable {
    let accessToken: String
    let user: User
    let serverId: String?

    struct User: Decodable {
        let id: String
        let name: String?
    }
}

struct PlaybackInfoResponse: Decodable {
    let mediaSources: [MediaSource]?
    let playSessionId: String?
    let errorCode: String?
}

struct MediaSource: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let path: String?
    let container: String?
    let size: Int64?
    let bitrate: Int?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let transcodingUrl: String?
    let liveStreamId: String?
    let mediaStreams: [MediaStream]?

    struct MediaStream: Decodable, Hashable {
        let type: String?
        let displayTitle: String?
        let height: Int?
        let language: String?
    }

    var label: String {
        if let name, !name.isEmpty { return name }
        return container?.uppercased() ?? "Source"
    }

    var details: String? {
        var parts: [String] = []
        if let video = mediaStreams?.first(where: { $0.type == "Video" }) {
            parts.append(video.displayTitle ?? video.height.map { "\($0)p" } ?? "")
        }
        let audio = (mediaStreams ?? []).filter { $0.type == "Audio" }.compactMap { $0.language ?? $0.displayTitle }
        if !audio.isEmpty { parts.append("Audio : " + audio.prefix(4).joined(separator: ", ")) }
        if let size, size > 0 { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let container { parts.append(container.uppercased()) }
        let text = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

// MARK: - Décodage

struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) { self.init(stringValue) }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension JSONDecoder {
    /// Décodeur pour l'API Jellyfin : "ImageTags" → imageTags.
    static let jellyfin: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            let raw = keys.last?.stringValue ?? ""
            guard let first = raw.first else { return AnyCodingKey(raw) }
            return AnyCodingKey(first.lowercased() + raw.dropFirst())
        }
        return decoder
    }()
}
