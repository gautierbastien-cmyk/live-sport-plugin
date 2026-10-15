import CoreGraphics
import Foundation

// Modèles du protocole d'addon Stremio (manifest, catalogues, metas, flux).
// Le décodage est volontairement tolérant : un champ inattendu ne doit pas
// faire échouer tout un catalogue.

struct AddonManifest: Decodable, Hashable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let logo: String?
    let types: [String]
    let catalogs: [CatalogDefinition]
    let resources: [ResourceDefinition]
    let idPrefixes: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, name, version, description, logo, types, catalogs, resources, idPrefixes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.lenientString(.name) ?? id
        version = c.lenientString(.version)
        description = c.lenientString(.description)
        logo = c.lenientString(.logo)
        types = (try? c.decode([String].self, forKey: .types)) ?? []
        catalogs = (try? c.decode(LossyArray<CatalogDefinition>.self, forKey: .catalogs).items) ?? []
        resources = (try? c.decode(LossyArray<ResourceDefinition>.self, forKey: .resources).items) ?? []
        idPrefixes = try? c.decode([String].self, forKey: .idPrefixes)
    }

    /// L'addon sait-il répondre à `resource` (meta, stream…) pour ce type et cet identifiant ?
    func supports(_ resource: String, type: String, id: String) -> Bool {
        guard let definition = resources.first(where: { $0.name == resource }) else { return false }
        guard (definition.types ?? types).contains(type) else { return false }
        guard let prefixes = definition.idPrefixes ?? idPrefixes, !prefixes.isEmpty else { return true }
        return prefixes.contains { id.hasPrefix($0) }
    }
}

struct ResourceDefinition: Decodable, Hashable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?

    private enum CodingKeys: String, CodingKey { case name, types, idPrefixes }

    init(from decoder: Decoder) throws {
        // Une ressource est soit une simple chaîne ("stream"), soit un objet.
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.name = name
            types = nil
            idPrefixes = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        types = try? c.decode([String].self, forKey: .types)
        idPrefixes = try? c.decode([String].self, forKey: .idPrefixes)
    }
}

struct ExtraDefinition: Decodable, Hashable {
    let name: String
    let isRequired: Bool
    let options: [String]?

    private enum CodingKeys: String, CodingKey { case name, isRequired, options }

    init(name: String, isRequired: Bool, options: [String]?) {
        self.name = name
        self.isRequired = isRequired
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        isRequired = (try? c.decode(Bool.self, forKey: .isRequired)) ?? false
        options = try? c.decode([String].self, forKey: .options)
    }
}

struct CatalogDefinition: Decodable, Hashable {
    let type: String
    let id: String
    let name: String?
    let extra: [ExtraDefinition]

    private enum CodingKeys: String, CodingKey { case type, id, name, extra, extraRequired, extraSupported }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        id = try c.decode(String.self, forKey: .id)
        name = c.lenientString(.name)
        if let extra = try? c.decode(LossyArray<ExtraDefinition>.self, forKey: .extra).items {
            self.extra = extra
        } else {
            // Ancien format : extraRequired / extraSupported.
            let required = (try? c.decode([String].self, forKey: .extraRequired)) ?? []
            let supported = (try? c.decode([String].self, forKey: .extraSupported)) ?? []
            extra = supported.map { ExtraDefinition(name: $0, isRequired: required.contains($0), options: nil) }
                + required.filter { !supported.contains($0) }.map { ExtraDefinition(name: $0, isRequired: true, options: nil) }
        }
    }

    var title: String { name ?? id }

    var supportsSearch: Bool { extra.contains { $0.name == "search" } }

    /// Paramètres à envoyer pour afficher le catalogue sans saisie, ou nil si
    /// le catalogue exige une recherche ou une valeur qu'on ne peut pas deviner.
    var browseExtras: [(name: String, value: String)]? {
        extras(search: nil)
    }

    /// Paramètres pour une recherche dans ce catalogue.
    func searchExtras(_ query: String) -> [(name: String, value: String)]? {
        guard supportsSearch else { return nil }
        return extras(search: query)
    }

    private func extras(search: String?) -> [(name: String, value: String)]? {
        var result: [(name: String, value: String)] = []
        if let search { result.append((name: "search", value: search)) }
        for definition in extra where definition.isRequired && definition.name != "search" {
            switch definition.name {
            case "skip":
                result.append((name: "skip", value: "0"))
            default:
                guard let first = definition.options?.first else { return nil }
                result.append((name: definition.name, value: first))
            }
        }
        if search == nil, extra.contains(where: { $0.name == "search" && $0.isRequired }) { return nil }
        return result
    }
}

struct MetaVideo: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let season: Int?
    let episode: Int?
    let released: String?
    let thumbnail: String?
    let overview: String?

    private enum CodingKeys: String, CodingKey { case id, title, name, season, episode, released, thumbnail, overview, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenientString(.title) ?? c.lenientString(.name) ?? id
        season = c.lenientInt(.season)
        episode = c.lenientInt(.episode)
        released = c.lenientString(.released)
        thumbnail = c.lenientString(.thumbnail)
        overview = c.lenientString(.overview) ?? c.lenientString(.description)
    }

    var label: String {
        if let season, let episode { return "S\(season)E\(episode) · \(title)" }
        return title
    }
}

struct MetaItem: Decodable, Hashable, Identifiable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let posterShape: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let genres: [String]
    let videos: [MetaVideo]

    private enum CodingKeys: String, CodingKey {
        case id, type, name, poster, posterShape, background, logo, description, releaseInfo, genres, videos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = c.lenientString(.type) ?? "other"
        name = c.lenientString(.name) ?? id
        poster = c.lenientString(.poster)
        posterShape = c.lenientString(.posterShape)
        background = c.lenientString(.background)
        logo = c.lenientString(.logo)
        description = c.lenientString(.description)
        releaseInfo = c.lenientString(.releaseInfo)
        genres = (try? c.decode([String].self, forKey: .genres)) ?? []
        videos = (try? c.decode(LossyArray<MetaVideo>.self, forKey: .videos).items) ?? []
    }

    var posterURL: URL? { poster.flatMap { URL(string: $0) } }
    var backgroundURL: URL? { (background ?? poster).flatMap { URL(string: $0) } }

    var posterAspectRatio: CGFloat {
        switch posterShape {
        case "landscape": return 16 / 9
        case "square": return 1
        default: return 2 / 3
        }
    }
}

struct StreamItem: Decodable, Hashable, Identifiable {
    let id = UUID()
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let externalUrl: String?
    let ytId: String?
    let infoHash: String?
    /// En-têtes HTTP exigés par le flux (behaviorHints.proxyHeaders.request).
    let headers: [String: String]

    private enum CodingKeys: String, CodingKey {
        case name, title, description, url, externalUrl, ytId, infoHash, behaviorHints
    }
    private enum HintKeys: String, CodingKey { case proxyHeaders }
    private enum ProxyKeys: String, CodingKey { case request }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenientString(.name)
        title = c.lenientString(.title)
        description = c.lenientString(.description)
        url = c.lenientString(.url)
        externalUrl = c.lenientString(.externalUrl)
        ytId = c.lenientString(.ytId)
        infoHash = c.lenientString(.infoHash)
        let hints = try? c.nestedContainer(keyedBy: HintKeys.self, forKey: .behaviorHints)
        let proxy = try? hints?.nestedContainer(keyedBy: ProxyKeys.self, forKey: .proxyHeaders)
        headers = (try? proxy?.decode([String: String].self, forKey: .request)) ?? [:]
    }

    enum Playback {
        case direct(URL, headers: [String: String])
        case external(URL)
        case unsupported(String)
    }

    var playback: Playback {
        if let url, let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") {
            return .direct(parsed, headers: headers)
        }
        if let ytId, let parsed = URL(string: "https://www.youtube.com/watch?v=\(ytId)") {
            return .external(parsed)
        }
        if let externalUrl, let parsed = URL(string: externalUrl) {
            return .external(parsed)
        }
        if infoHash != nil {
            return .unsupported("Les flux torrent ne sont pas pris en charge.")
        }
        return .unsupported("Ce flux ne contient pas de lien lisible.")
    }

    var heading: String {
        name?.replacingOccurrences(of: "\n", with: " ") ?? "Flux"
    }

    var details: String? {
        let text = description ?? title
        guard let text, !text.isEmpty, text != name else { return nil }
        return text
    }

    static func == (lhs: StreamItem, rhs: StreamItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Décodage tolérant

/// Tableau qui ignore les éléments impossibles à décoder au lieu d'échouer.
struct LossyArray<Element: Decodable>: Decodable {
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

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }
}
