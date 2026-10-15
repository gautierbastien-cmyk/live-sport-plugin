import Foundation

enum AppDefaults {
    static let serverURL = "https://bastien-trellis.duckdns.org"
}

/// Lecteur utilisé quand on choisit un flux.
enum PlayerChoice: String, CaseIterable, Identifiable {
    case ask
    case infuse
    case builtIn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return "Toujours demander"
        case .infuse: return "Infuse"
        case .builtIn: return "Lecteur intégré"
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
