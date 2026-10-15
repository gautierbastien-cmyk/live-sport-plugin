import AVKit
import SwiftUI

/// Lecteur AVPlayer plein écran. Contrairement à Infuse, il peut envoyer les
/// en-têtes HTTP (Referer, User-Agent…) exigés par certains flux.
struct BuiltInPlayerView: View {
    let stream: PlayableStream

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
            .accessibilityLabel("Fermer")
        }
        .onAppear {
            var options: [String: Any] = [:]
            if !stream.headers.isEmpty {
                options["AVURLAssetHTTPHeaderFieldsKey"] = stream.headers
            }
            let asset = AVURLAsset(url: stream.url, options: options)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
