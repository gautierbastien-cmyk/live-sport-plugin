import Foundation

// MARK: - Modèles

struct TraktIds: Decodable, Hashable {
    let trakt: Int?
    let slug: String?
    let imdb: String?
    let tmdb: Int?
    let tvdb: Int?
}

struct TraktImages: Decodable, Hashable {
    let poster: [String]?
    let fanart: [String]?
    let thumb: [String]?
}

/// Film ou série renvoyé par Trakt (avec extended=full,images).
struct TraktMedia: Decodable, Hashable {
    let title: String?
    let year: Int?
    let ids: TraktIds
    let overview: String?
    let tagline: String?
    let rating: Double?
    let runtime: Int?
    let genres: [String]?
    let certification: String?
    let network: String?
    let images: TraktImages?
}

private struct TraktListEntry: Decodable {
    let type: String?
    let movie: TraktMedia?
    let show: TraktMedia?
}

/// Élément d'une liste Trakt, affiché dans les tuiles et ouvert dans sa fiche.
struct ExternalItem: Identifiable, Hashable {
    enum Kind: String { case movie, show }

    let kind: Kind
    let media: TraktMedia

    var id: String { "\(kind.rawValue)-\(media.ids.trakt ?? media.ids.tmdb ?? 0)-\(media.title ?? "")" }
    var title: String { media.title ?? "Sans titre" }

    var posterURL: URL? { Self.imageURL(media.images?.poster?.first) }
    var backdropURL: URL? { Self.imageURL(media.images?.fanart?.first ?? media.images?.thumb?.first) ?? posterURL }

    var infoLine: String {
        var parts: [String] = []
        if let year = media.year { parts.append(String(year)) }
        parts.append(kind == .movie ? "Film" : "Série")
        if let certification = media.certification, !certification.isEmpty { parts.append(certification) }
        if let runtime = media.runtime, runtime > 0 {
            parts.append(runtime >= 60 ? "\(runtime / 60) h \(runtime % 60) min" : "\(runtime) min")
        }
        if let rating = media.rating, rating > 0 { parts.append(String(format: "★ %.1f", rating)) }
        if let network = media.network, !network.isEmpty { parts.append(network) }
        return parts.joined(separator: " · ")
    }

    /// Trakt renvoie des chemins sans schéma (« media.trakt.tv/… »).
    private static func imageURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path.hasPrefix("http") ? path : "https://" + path)
    }
}

// MARK: - Configuration et jetons

/// Identifiants de l'application Trakt de l'utilisateur et jetons OAuth.
enum TraktAccount {
    private static let clientIdKey = "trakt.clientId"
    private static let clientSecretKey = "trakt.clientSecret"
    private static let expiresKey = "trakt.expiresAt"
    private static let accessAccount = "trakt.accessToken"
    private static let refreshAccount = "trakt.refreshToken"

    static var clientId: String {
        get { UserDefaults.standard.string(forKey: clientIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIdKey) }
    }

    static var clientSecret: String {
        get { UserDefaults.standard.string(forKey: clientSecretKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientSecretKey) }
    }

    static var isConfigured: Bool { !clientId.isEmpty }
    static var isConnected: Bool { Keychain.read(accessAccount) != nil }

    static var accessToken: String? { Keychain.read(accessAccount) }
    static var refreshToken: String? { Keychain.read(refreshAccount) }

    static var needsRefresh: Bool {
        let expires = UserDefaults.standard.double(forKey: expiresKey)
        return expires > 0 && Date().timeIntervalSince1970 > expires - 86_400
    }

    static func store(_ token: TraktToken) {
        Keychain.save(token.access_token, account: accessAccount)
        if let refresh = token.refresh_token { Keychain.save(refresh, account: refreshAccount) }
        let expires = Date().timeIntervalSince1970 + Double(token.expires_in ?? 7_776_000)
        UserDefaults.standard.set(expires, forKey: expiresKey)
    }

    static func disconnect() {
        Keychain.delete(accessAccount)
        Keychain.delete(refreshAccount)
        UserDefaults.standard.removeObject(forKey: expiresKey)
    }
}

struct TraktToken: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
}

struct TraktDeviceCode: Decodable {
    let device_code: String
    let user_code: String
    let verification_url: String
    let expires_in: Int
    let interval: Int
}

enum TraktError: LocalizedError {
    case notConfigured
    case notConnected
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Ajoute ton Client ID Trakt dans les Réglages."
        case .notConnected: return "Connecte ton compte Trakt dans les Réglages."
        case .http(401): return "Trakt a refusé l'accès : reconnecte ton compte dans les Réglages."
        case .http(404): return "Liste Trakt introuvable (privée ou supprimée ?)."
        case .http(let code): return "Erreur Trakt (\(code))."
        }
    }
}

// MARK: - Client

enum TraktClient {
    private static let base = "https://api.trakt.tv"
    private static let extended = "full,images"

    /// Liste publique d'un utilisateur Trakt.
    static func listItems(username: String, listId: String) async throws -> [ExternalItem] {
        let user = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return try await entries("/users/\(user)/lists/\(listId)/items/movie,show?extended=\(extended)&limit=250")
    }

    /// Watchlist de l'utilisateur connecté : "watchlist", "watchlist_movies" ou "watchlist_shows".
    static func watchlist(_ kind: String) async throws -> [ExternalItem] {
        guard TraktAccount.isConnected else { throw TraktError.notConnected }
        switch kind {
        case "watchlist_movies":
            return try await entries("/sync/watchlist/movies/rank?extended=\(extended)")
        case "watchlist_shows":
            return try await entries("/sync/watchlist/shows/rank?extended=\(extended)")
        default:
            async let movies = entries("/sync/watchlist/movies/rank?extended=\(extended)")
            async let shows = entries("/sync/watchlist/shows/rank?extended=\(extended)")
            return try await movies + shows
        }
    }

    // MARK: Connexion (OAuth « device code »)

    static func startDeviceAuth() async throws -> TraktDeviceCode {
        let data = try await send("/oauth/device/code", method: "POST",
                                  body: ["client_id": TraktAccount.clientId], authenticated: false)
        return try JSONDecoder().decode(TraktDeviceCode.self, from: data)
    }

    /// Renvoie le jeton une fois le code validé sur trakt.tv/activate, nil tant qu'il est en attente.
    static func pollDeviceToken(_ code: TraktDeviceCode) async throws -> TraktToken? {
        do {
            let data = try await send("/oauth/device/token", method: "POST", body: [
                "code": code.device_code,
                "client_id": TraktAccount.clientId,
                "client_secret": TraktAccount.clientSecret,
            ], authenticated: false)
            return try JSONDecoder().decode(TraktToken.self, from: data)
        } catch TraktError.http(let status) where status == 400 || status == 429 {
            return nil
        }
    }

    private static func refreshIfNeeded() async {
        guard TraktAccount.needsRefresh, let refresh = TraktAccount.refreshToken else { return }
        let body = [
            "refresh_token": refresh,
            "client_id": TraktAccount.clientId,
            "client_secret": TraktAccount.clientSecret,
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
            "grant_type": "refresh_token",
        ]
        if let data = try? await send("/oauth/token", method: "POST", body: body, authenticated: false),
           let token = try? JSONDecoder().decode(TraktToken.self, from: data) {
            TraktAccount.store(token)
        }
    }

    // MARK: HTTP

    private static func entries(_ path: String) async throws -> [ExternalItem] {
        await refreshIfNeeded()
        let data = try await send(path)
        let list = try JSONDecoder().decode(LossyList<TraktListEntry>.self, from: data).items
        return list.compactMap { entry in
            if let movie = entry.movie { return ExternalItem(kind: .movie, media: movie) }
            if let show = entry.show { return ExternalItem(kind: .show, media: show) }
            return nil
        }
    }

    private static func send(_ path: String, method: String = "GET", body: [String: String]? = nil,
                             authenticated: Bool = true) async throws -> Data {
        guard TraktAccount.isConfigured else { throw TraktError.notConfigured }
        guard let url = URL(string: base + path) else { throw TraktError.http(400) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(TraktAccount.clientId, forHTTPHeaderField: "trakt-api-key")
        if authenticated, let token = TraktAccount.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TraktError.http(http.statusCode)
        }
        return data
    }
}

/// Tableau JSON dont les éléments illisibles sont ignorés.
struct LossyList<Element: Decodable>: Decodable {
    let items: [Element]

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.items = items
    }
}
