import UIKit

enum ExternalPlayer {
    static let infuseAppStoreURL = URL(string: "https://apps.apple.com/app/id1136220934")!

    /// infuse://x-callback-url/play?url=<URL encodée>
    static func infuseURL(for video: URL) -> URL? {
        URL(string: "infuse://x-callback-url/play?url=" + strictlyEncoded(video.absoluteString))
    }

    /// Ouvre la vidéo dans Infuse. Renvoie `false` si Infuse n'est pas installé.
    @MainActor
    static func openInInfuse(_ video: URL) async -> Bool {
        guard let url = infuseURL(for: video) else { return false }
        return await UIApplication.shared.open(url)
    }

    /// Encode tout sauf les caractères non réservés (RFC 3986), pour que les
    /// `&`, `=` et `?` de l'URL vidéo ne cassent pas le paramètre `url`.
    private static func strictlyEncoded(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
