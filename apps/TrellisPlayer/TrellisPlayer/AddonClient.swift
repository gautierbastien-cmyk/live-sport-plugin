import Foundation

enum AddonError: LocalizedError {
    case invalidURL(String)
    case http(Int)
    case alreadyInstalled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let input): return "Lien d'addon invalide : \(input)"
        case .http(401), .http(403): return "Accès refusé par le serveur (lien d'addon incomplet ou expiré ?)."
        case .http(404): return "Introuvable sur le serveur (404)."
        case .http(let code): return "Erreur du serveur (\(code))."
        case .alreadyInstalled: return "Cet addon est déjà ajouté."
        }
    }
}

/// Appels HTTP vers un addon Stremio : /manifest.json, /catalog, /meta, /stream.
enum AddonClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Transforme ce que l'utilisateur colle (https://…/manifest.json, stremio://…,
    /// lien web.stremio.com/#/addons?addon=…) en URL de manifest.
    static func manifestURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "addon="), text.contains("stremio.com") {
            let encoded = String(text[range.upperBound...]).components(separatedBy: "&").first ?? ""
            text = encoded.removingPercentEncoding ?? encoded
        }
        if text.lowercased().hasPrefix("stremio://") {
            text = "https://" + text.dropFirst("stremio://".count)
        }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard var url = URL(string: text), url.host != nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        if url.lastPathComponent != "manifest.json" {
            url.appendPathComponent("manifest.json")
        }
        return url
    }

    static func fetchManifest(_ url: URL) async throws -> AddonManifest {
        try await get(url, as: AddonManifest.self)
    }

    static func catalog(addon manifestURL: URL, type: String, id: String,
                        extras: [(name: String, value: String)]) async throws -> [MetaItem] {
        var path = "catalog/\(encode(type))/\(encode(id))"
        if !extras.isEmpty {
            path += "/" + extras.map { "\(encode($0.name))=\(encode($0.value))" }.joined(separator: "&")
        }
        let response = try await get(resourceURL(manifestURL, path), as: CatalogResponse.self)
        return response.metas
    }

    static func meta(addon manifestURL: URL, type: String, id: String) async throws -> MetaItem? {
        let path = "meta/\(encode(type))/\(encode(id))"
        return try await get(resourceURL(manifestURL, path), as: MetaResponse.self).meta
    }

    static func streams(addon manifestURL: URL, type: String, id: String) async throws -> [StreamItem] {
        let path = "stream/\(encode(type))/\(encode(id))"
        return try await get(resourceURL(manifestURL, path), as: StreamResponse.self).streams
    }

    // MARK: - Détails

    /// https://hote/chemin/manifest.json → https://hote/chemin/<path>.json
    private static func resourceURL(_ manifestURL: URL, _ path: String) throws -> URL {
        var base = manifestURL.absoluteString
        if let query = base.firstIndex(of: "?") { base = String(base[..<query]) }
        if base.hasSuffix("/manifest.json") { base.removeLast("/manifest.json".count) }
        guard let url = URL(string: base + "/" + path + ".json") else {
            throw AddonError.invalidURL(base + "/" + path)
        }
        return url
    }

    private static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AddonError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private struct CatalogResponse: Decodable {
        let metas: [MetaItem]
        private enum CodingKeys: String, CodingKey { case metas }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            metas = (try? c.decode(LossyArray<MetaItem>.self, forKey: .metas).items) ?? []
        }
    }

    private struct MetaResponse: Decodable {
        let meta: MetaItem?
    }

    private struct StreamResponse: Decodable {
        let streams: [StreamItem]
        private enum CodingKeys: String, CodingKey { case streams }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            streams = (try? c.decode(LossyArray<StreamItem>.self, forKey: .streams).items) ?? []
        }
    }
}
