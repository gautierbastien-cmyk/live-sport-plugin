import SwiftUI
import UIKit

/// Flux prêt à être lu.
struct PlayableStream: Identifiable {
    let id = UUID()
    let url: URL
    let headers: [String: String]
    let title: String
}

/// Décide comment lire un flux : Infuse, lecteur intégré, ou lien externe.
@MainActor
final class PlaybackController: ObservableObject {
    @Published var pendingChoice: PlayableStream?
    @Published var builtInStream: PlayableStream?
    @Published var infuseMissing = false
    @Published var message: String?

    func play(_ stream: StreamItem, title: String) {
        switch stream.playback {
        case .direct(let url, let headers):
            let playable = PlayableStream(url: url, headers: headers, title: title)
            switch defaultPlayer {
            case .ask: pendingChoice = playable
            case .infuse: openInInfuse(playable)
            case .builtIn: builtInStream = playable
            }
        case .external(let url):
            UIApplication.shared.open(url)
        case .unsupported(let reason):
            message = reason
        }
    }

    func openInInfuse(_ stream: PlayableStream) {
        Task {
            if await !ExternalPlayer.openInInfuse(stream.url) { infuseMissing = true }
        }
    }

    func openBuiltIn(_ stream: PlayableStream) {
        builtInStream = stream
    }

    private var defaultPlayer: PlayerChoice {
        PlayerChoice(rawValue: UserDefaults.standard.string(forKey: "defaultPlayer") ?? "") ?? .ask
    }
}

/// Dialogues et lecteur plein écran, à poser une fois à la racine.
struct PlaybackPresenter: ViewModifier {
    @ObservedObject var playback: PlaybackController
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Lire avec…",
                                isPresented: Binding(get: { playback.pendingChoice != nil },
                                                     set: { if !$0 { playback.pendingChoice = nil } }),
                                titleVisibility: .visible,
                                presenting: playback.pendingChoice) { stream in
                Button("Infuse") { playback.openInInfuse(stream) }
                Button("Lecteur intégré") { playback.openBuiltIn(stream) }
                Button("Copier le lien") { UIPasteboard.general.url = stream.url }
                Button("Annuler", role: .cancel) {}
            } message: { stream in
                if stream.headers.isEmpty {
                    Text(stream.title)
                } else {
                    Text("\(stream.title)\n\nCe flux exige des en-têtes HTTP : Infuse risque d'échouer, préfère le lecteur intégré.")
                }
            }
            .alert("Infuse n'est pas installé", isPresented: $playback.infuseMissing) {
                Button("Ouvrir l'App Store") { openURL(ExternalPlayer.infuseAppStoreURL) }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Installe Infuse pour l'utiliser comme lecteur externe.")
            }
            .alert("Lecture impossible",
                   isPresented: Binding(get: { playback.message != nil }, set: { if !$0 { playback.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(playback.message ?? "")
            }
            .fullScreenCover(item: $playback.builtInStream) { stream in
                BuiltInPlayerView(stream: stream)
            }
    }
}
