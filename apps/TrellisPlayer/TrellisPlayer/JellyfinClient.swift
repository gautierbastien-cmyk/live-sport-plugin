import Foundation

enum JellyfinError: LocalizedError {
    case invalidServer
    case http(Int)
    case noSource

    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Adresse du serveur invalide."
        case .http(401): return "Identifiant ou mot de passe incorrect, ou session expirée."
        case .http(403): return "Accès refusé par le serveur."
        case .http(404): return "Introuvable sur le serveur."
        case .http(let code): return "Erreur du serveur (\(code))."
        case .noSource: return "Aucune source de lecture disponible."
        }
    }
}

/// Client de l'API Jellyfin exposée par Treillis.
struct JellyfinClient {
    let server: URL
    let token: String?
    let userId: String?

    static let clientName = "Trellis Player"
    static let version = "1.0"

    static var deviceId: String {
        let key = "jellyfin.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    private static let itemFields = "Overview,Genres,PrimaryImageAspectRatio,ProductionYear,OfficialRating,CommunityRating,RunTimeTicks"
    private static let detailFields = itemFields + ",People,Studios,Taglines,ProviderIds,PremiereDate"

    // MARK: - Authentification

    var authorizationHeader: String {
        var value = "MediaBrowser Client=\"\(Self.clientName)\", Device=\"iOS\", DeviceId=\"\(Self.deviceId)\", Version=\"\(Self.version)\""
        if let token { value += ", Token=\"\(token)\"" }
        return value
    }

    func authenticate(username: String, password: String) async throws -> AuthenticationResult {
        let body = ["Username": username, "Pw": password]
        let data = try await send("Users/AuthenticateByName", method: "POST", body: body)
        return try JSONDecoder.jellyfin.decode(AuthenticationResult.self, from: data)
    }

    func logout() async {
        _ = try? await send("Sessions/Logout", method: "POST")
    }

    // MARK: - Contenus

    /// Contenu d'une collection (tuile Strand) ou d'un dossier.
    func items(parentId: String, limit: Int = 100) async throws -> [BaseItem] {
        try await userItems(query: [
            "ParentId": parentId,
            "Limit": String(limit),
            "Fields": Self.itemFields,
            "EnableImageTypes": "Primary,Backdrop,Thumb",
            "ImageTypeLimit": "1",
        ])
    }

    func search(_ term: String) async throws -> [BaseItem] {
        try await userItems(query: [
            "SearchTerm": term,
            "IncludeItemTypes": "Movie,Series,Episode,TvChannel",
            "Recursive": "true",
            "Limit": "60",
            "Fields": Self.itemFields,
        ])
    }

    /// Retrouve sur Treillis un film ou une série venant de Trakt : d'abord par
    /// identifiant IMDb/TMDB, sinon par titre et année.
    func findMatch(for external: ExternalItem) async throws -> BaseItem? {
        let results = try await userItems(query: [
            "SearchTerm": external.title,
            "IncludeItemTypes": external.kind == .movie ? "Movie" : "Series",
            "Recursive": "true",
            "Limit": "20",
            "Fields": Self.itemFields + ",ProviderIds",
        ])
        let ids = external.media.ids
        if let imdb = ids.imdb, let match = results.first(where: { $0.providerId("Imdb") == imdb }) {
            return match
        }
        if let tmdb = ids.tmdb, let match = results.first(where: { $0.providerId("Tmdb") == String(tmdb) }) {
            return match
        }
        let sameTitle = results.filter { ($0.name ?? "").localizedCaseInsensitiveCompare(external.title) == .orderedSame }
        if let year = external.media.year,
           let match = sameTitle.first(where: { $0.productionYear.map { abs($0 - year) <= 1 } ?? false }) {
            return match
        }
        return sameTitle.first ?? (results.count == 1 ? results.first : nil)
    }

    /// « Reprendre la lecture ».
    func resumeItems() async throws -> [BaseItem] {
        guard let userId else { return [] }
        let query = ["Limit": "24", "MediaTypes": "Video", "Fields": Self.itemFields,
                     "EnableImageTypes": "Primary,Backdrop,Thumb"]
        do {
            return try await decodeItems("UserItems/Resume", query: query.merging(["UserId": userId]) { $1 })
        } catch JellyfinError.http(404) {
            return try await decodeItems("Users/\(userId)/Items/Resume", query: query)
        }
    }

    func item(id: String) async throws -> BaseItem {
        guard let userId else { throw JellyfinError.http(401) }
        do {
            let data = try await send("Items/\(id)", query: ["UserId": userId, "Fields": Self.detailFields])
            return try JSONDecoder.jellyfin.decode(BaseItem.self, from: data)
        } catch JellyfinError.http(let code) where code == 404 || code == 405 {
            let data = try await send("Users/\(userId)/Items/\(id)", query: ["Fields": Self.detailFields])
            return try JSONDecoder.jellyfin.decode(BaseItem.self, from: data)
        }
    }

    func seasons(seriesId: String) async throws -> [BaseItem] {
        try await decodeItems("Shows/\(seriesId)/Seasons", query: ["UserId": userId ?? "", "Fields": Self.itemFields])
    }

    func episodes(seriesId: String, seasonId: String) async throws -> [BaseItem] {
        try await decodeItems("Shows/\(seriesId)/Episodes",
                              query: ["UserId": userId ?? "", "SeasonId": seasonId, "Fields": Self.itemFields])
    }

    /// Chaînes de TV en direct : radios, ou chaînes favorites.
    func channels(radio: Bool) async throws -> [BaseItem] {
        var query = ["UserId": userId ?? "", "Limit": "60", "EnableImageTypes": "Primary"]
        if radio {
            query["Type"] = "Radio"
        } else {
            query["IsFavorite"] = "true"
        }
        return try await decodeItems("LiveTv/Channels", query: query)
    }

    // MARK: - Lecture

    func playbackInfo(itemId: String) async throws -> PlaybackInfoResponse {
        // Profil minimal : on accepte tout en lecture directe (Infuse lit tous les formats).
        let body: [String: Any] = [
            "UserId": userId ?? "",
            "AutoOpenLiveStream": true,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "DeviceProfile": [
                "MaxStreamingBitrate": 200_000_000,
                "DirectPlayProfiles": [["Type": "Video"], ["Type": "Audio"]],
                "TranscodingProfiles": [[
                    "Type": "Video", "Container": "ts", "Protocol": "hls",
                    "VideoCodec": "h264", "AudioCodec": "aac", "Context": "Streaming",
                ]],
            ] as [String: Any],
        ]
        let data = try await send("Items/\(itemId)/PlaybackInfo", method: "POST",
                                  query: ["UserId": userId ?? "", "AutoOpenLiveStream": "true"], body: body)
        return try JSONDecoder.jellyfin.decode(PlaybackInfoResponse.self, from: data)
    }

    /// Flux original (pour Infuse, qui lit tout).
    func directStreamURL(itemId: String, source: MediaSource, playSessionId: String?) -> URL? {
        var query = [
            "static": "true",
            "MediaSourceId": source.id,
            "DeviceId": Self.deviceId,
            "api_key": token ?? "",
        ]
        if let playSessionId { query["PlaySessionId"] = playSessionId }
        if let liveStreamId = source.liveStreamId { query["LiveStreamId"] = liveStreamId }
        let container = source.container?.split(separator: ",").first.map(String.init)
        let path = container.map { "Videos/\(itemId)/stream.\($0)" } ?? "Videos/\(itemId)/stream"
        return makeURL(path, query: query)
    }

    /// Flux HLS compatible AVPlayer (lecteur intégré).
    func hlsStreamURL(itemId: String, source: MediaSource, playSessionId: String?) -> URL? {
        if let transcodingUrl = source.transcodingUrl,
           let url = URL(string: transcodingUrl, relativeTo: server.appendingPathComponent("/")) {
            return url.absoluteURL
        }
        var query = [
            "MediaSourceId": source.id,
            "DeviceId": Self.deviceId,
            "api_key": token ?? "",
            "VideoCodec": "h264,hevc",
            "AudioCodec": "aac,ac3,eac3",
            "SegmentContainer": "ts",
            "TranscodingMaxAudioChannels": "6",
        ]
        if let playSessionId { query["PlaySessionId"] = playSessionId }
        if let liveStreamId = source.liveStreamId { query["LiveStreamId"] = liveStreamId }
        return makeURL("Videos/\(itemId)/master.m3u8", query: query)
    }

    func imageURL(itemId: String, type: String = "Primary", tag: String? = nil, maxWidth: Int = 500) -> URL? {
        var query = ["maxWidth": String(maxWidth), "quality": "90"]
        if let tag { query["tag"] = tag }
        return makeURL("Items/\(itemId)/Images/\(type)", query: query)
    }

    /// Image paysage pour « Reprendre la lecture » et les épisodes.
    func landscapeImageURL(for item: BaseItem, maxWidth: Int = 600) -> URL? {
        if let tag = item.imageTag("Thumb") {
            return imageURL(itemId: item.id, type: "Thumb", tag: tag, maxWidth: maxWidth)
        }
        if item.isEpisode, let tag = item.imageTag("Primary") {
            return imageURL(itemId: item.id, type: "Primary", tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.backdropImageTags?.first {
            return imageURL(itemId: item.id, type: "Backdrop", tag: tag, maxWidth: maxWidth)
        }
        if let parent = item.parentThumbItemId {
            return imageURL(itemId: parent, type: "Thumb", maxWidth: maxWidth)
        }
        if let parent = item.parentBackdropItemId ?? item.seriesId {
            return imageURL(itemId: parent, type: "Backdrop", maxWidth: maxWidth)
        }
        return imageURL(itemId: item.id, type: "Primary", maxWidth: maxWidth)
    }

    func posterURL(for item: BaseItem, maxWidth: Int = 400) -> URL? {
        imageURL(itemId: item.id, type: "Primary", tag: item.imageTag("Primary"), maxWidth: maxWidth)
    }

    func backdropURL(for item: BaseItem, maxWidth: Int = 1200) -> URL? {
        if let tag = item.backdropImageTags?.first {
            return imageURL(itemId: item.id, type: "Backdrop", tag: tag, maxWidth: maxWidth)
        }
        if let parent = item.parentBackdropItemId ?? item.seriesId {
            return imageURL(itemId: parent, type: "Backdrop", maxWidth: maxWidth)
        }
        return posterURL(for: item, maxWidth: maxWidth)
    }

    // MARK: - HTTP

    /// /Items?UserId= (Jellyfin 10.9+), avec repli sur /Users/{id}/Items.
    private func userItems(query: [String: String]) async throws -> [BaseItem] {
        guard let userId else { throw JellyfinError.http(401) }
        do {
            return try await decodeItems("Items", query: query.merging(["UserId": userId]) { $1 })
        } catch JellyfinError.http(let code) where code == 404 || code == 405 {
            return try await decodeItems("Users/\(userId)/Items", query: query)
        }
    }

    private func decodeItems(_ path: String, query: [String: String]) async throws -> [BaseItem] {
        let data = try await send(path, query: query)
        // Certaines routes renvoient directement un tableau.
        if let array = try? JSONDecoder.jellyfin.decode([BaseItem].self, from: data) { return array }
        return try JSONDecoder.jellyfin.decode(ItemsResponse.self, from: data).items ?? []
    }

    private func makeURL(_ path: String, query: [String: String]) -> URL? {
        var base = server.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + "/" + path) else { return nil }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    private func send(_ path: String, method: String = "GET", query: [String: String] = [:],
                      body: Any? = nil) async throws -> Data {
        guard let url = makeURL(path, query: query) else { throw JellyfinError.invalidServer }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Emby-Token") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await Self.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw JellyfinError.http(http.statusCode)
        }
        return data
    }
}
