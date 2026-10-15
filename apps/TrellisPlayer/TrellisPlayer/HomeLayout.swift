import Foundation

// Configuration de l'accueil exportée depuis Strand (StrandHome.json).
// Sections → groupes de tuiles → sources (collections du serveur Treillis,
// listes Trakt / MDBList, découvertes TMDB…).

struct HomeSection: Decodable, Identifiable {
    let id: String
    let isEnabled: Bool
    let sortOrder: Int
    let style: String
    let title: String?
    let source: SectionSource

    private enum CodingKeys: String, CodingKey { case id, isEnabled, sortOrder, style, title, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        style = (try? c.decode(String.self, forKey: .style)) ?? "row_classic"
        title = try? c.decode(String.self, forKey: .title)
        source = (try? c.decode(SectionSource.self, forKey: .source)) ?? .unsupported("?")
    }
}

enum SectionSource: Decodable {
    case continueWatching
    case group(TileGroup)
    case liveTVFavorites
    case liveTVRadio
    case unsupported(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let key = c.allKeys.first else {
            self = .unsupported("?")
            return
        }
        switch key.stringValue {
        case "continueWatching":
            self = .continueWatching
        case "group":
            let wrapper = try c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
            self = .group(try wrapper.decode(TileGroup.self, forKey: AnyCodingKey("_0")))
        case "liveTVFavoriteCategories", "liveTVFavorites":
            self = .liveTVFavorites
        case "liveTVRadio":
            self = .liveTVRadio
        default:
            self = .unsupported(key.stringValue)
        }
    }
}

struct TileGroup: Decodable {
    let title: String?
    let tileShape: String?
    let hideTitle: Bool?
    let contentSources: [Tile]
}

struct Tile: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let coverImageURL: String?
    let hideTitle: Bool?
    let tileShape: String?
    let sources: [TileSource]

    var coverURL: URL? { coverImageURL.flatMap { URL(string: $0) } }

    /// Collections du serveur, sans doublons (Strand les liste une fois par compte).
    var collectionIds: [String] {
        var seen = Set<String>()
        return sources.compactMap { source in
            if case .mediaServer(let id, _) = source, seen.insert(id).inserted { return id }
            return nil
        }
    }

    /// Sources non reliées au serveur (Trakt, TMDB, MDBList) : pas encore prises en charge.
    var externalSources: [String] {
        sources.compactMap { source in
            if case .external(let label) = source { return label }
            return nil
        }
    }

    static func == (lhs: Tile, rhs: Tile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum TileSource: Decodable {
    case mediaServer(collectionId: String, name: String?)
    case external(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let key = c.allKeys.first else {
            self = .external("?")
            return
        }
        let payload = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
        switch key.stringValue {
        case "mediaServer":
            let inner = try? payload?.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("_0"))
            guard let inner, let id = try? inner.decode(String.self, forKey: AnyCodingKey("collectionId")) else {
                self = .external("Serveur")
                return
            }
            self = .mediaServer(collectionId: id, name: try? inner.decode(String.self, forKey: AnyCodingKey("collectionName")))
        case "traktList", "traktBuiltIn":
            self = .external("Trakt")
        case "mdbListList":
            self = .external("MDBList")
        case "tmdbDiscover":
            self = .external("TMDB")
        default:
            self = .external(key.stringValue)
        }
    }
}

/// Charge la configuration : celle importée par l'utilisateur, sinon celle fournie avec l'app.
@MainActor
final class HomeLayoutStore: ObservableObject {
    @Published private(set) var sections: [HomeSection] = []
    @Published private(set) var isCustom = false

    private static var customURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("home-layout.json")
    }

    init() {
        reload()
    }

    func reload() {
        if let data = try? Data(contentsOf: Self.customURL), let sections = Self.decode(data) {
            self.sections = sections
            isCustom = true
        } else if let url = Bundle.main.url(forResource: "StrandHome", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let sections = Self.decode(data) {
            self.sections = sections
            isCustom = false
        }
    }

    /// Importe un export JSON de l'accueil Strand.
    func importLayout(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard Self.decode(data) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try data.write(to: Self.customURL, options: .atomic)
        reload()
    }

    func resetToDefault() {
        try? FileManager.default.removeItem(at: Self.customURL)
        reload()
    }

    private static func decode(_ data: Data) -> [HomeSection]? {
        guard let sections = try? JSONDecoder().decode([HomeSection].self, from: data), !sections.isEmpty else { return nil }
        return sections.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
    }
}
