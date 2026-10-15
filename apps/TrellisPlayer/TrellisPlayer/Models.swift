import Foundation

enum AppDefaults {
    static let serverURL = "https://bastien-trellis.duckdns.org"
}

/// Vidéo repérée dans la page Trellis.
struct DetectedVideo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let pageTitle: String?

    var displayName: String {
        if let pageTitle, !pageTitle.isEmpty { return pageTitle }
        return url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent
    }
}

/// Lecteur utilisé quand une vidéo démarre dans la page.
enum PlayerChoice: String, CaseIterable, Identifiable {
    case ask
    case infuse
    case builtIn
    case web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return "Toujours demander"
        case .infuse: return "Infuse"
        case .builtIn: return "Lecteur intégré"
        case .web: return "Lecteur de la page"
        }
    }
}

extension String {
    /// Ajoute https:// si l'utilisateur a saisi seulement un nom d'hôte.
    var normalizedServerURL: URL? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }
}
