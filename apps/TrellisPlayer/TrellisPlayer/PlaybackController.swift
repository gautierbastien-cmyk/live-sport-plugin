import SwiftUI
import UIKit

/// Flux prêt à être lu.
struct PlayableStream: Identifiable {
    let id = UUID()
    let title: String
    /// Fichier original, pour Infuse (lit tous les formats).
    let directURL: URL
    /// Version HLS, pour le lecteur intégré (AVPlayer).
    let builtInURL: URL
}

/// Récupère les sources d'un élément Treillis et l'ouvre dans le lecteur choisi.
@MainActor
final class PlaybackController: ObservableObject {
    @Published var pendingChoice: PlayableStream?
    @Published var builtInStream: PlayableStream?
    @Published var infuseMissing = false
    @Published var message: String?
    @Published var preparingItemId: String?

    /// Lecture d'un élément : demande ses sources et lit la première.
    func play(_ item: BaseItem, client: JellyfinClient) {
        guard preparingItemId == nil else { return }
        preparingItemId = item.id
        Task {
            defer { preparingItemId = nil }
            do {
                let info = try await client.playbackInfo(itemId: item.id)
                guard let source = info.mediaSources?.first else { throw JellyfinError.noSource }
                play(source, of: item, playSessionId: info.playSessionId, client: client)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// Lecture d'une source précise (quand l'élément en propose plusieurs).
    func play(_ source: MediaSource, of item: BaseItem, playSessionId: String?, client: JellyfinClient) {
        guard let direct = client.directStreamURL(itemId: item.id, source: source, playSessionId: playSessionId),
              let hls = client.hlsStreamURL(itemId: item.id, source: source, playSessionId: playSessionId) else {
            message = JellyfinError.noSource.localizedDescription
            return
        }
        let title = [item.seriesName, item.title].compactMap { $0 }.joined(separator: " · ")
        let stream = PlayableStream(title: title, directURL: direct, builtInURL: hls)
        switch defaultPlayer {
        case .ask: pendingChoice = stream
        case .infuse: openInInfuse(stream)
        case .builtIn: builtInStream = stream
        }
    }

    func openInInfuse(_ stream: PlayableStream) {
        Task {
            if await !ExternalPlayer.openInInfuse(stream.directURL) { infuseMissing = true }
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
            .overlay {
                if playback.preparingItemId != nil {
                    ProgressView("Préparation de la lecture…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .confirmationDialog("Lire avec…",
                                isPresented: Binding(get: { playback.pendingChoice != nil },
                                                     set: { if !$0 { playback.pendingChoice = nil } }),
                                titleVisibility: .visible,
                                presenting: playback.pendingChoice) { stream in
                Button("Infuse") { playback.openInInfuse(stream) }
                Button("Lecteur intégré") { playback.openBuiltIn(stream) }
                Button("Copier le lien") { UIPasteboard.general.url = stream.directURL }
                Button("Annuler", role: .cancel) {}
            } message: { stream in
                Text(stream.title)
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
