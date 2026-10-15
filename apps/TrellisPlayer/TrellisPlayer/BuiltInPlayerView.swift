import AVKit
import SwiftUI

/// Lecteur AVPlayer plein écran, sur la version HLS fournie par le serveur.
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
            let player = AVPlayer(url: stream.builtInURL)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
