import AVKit
import SwiftUI

/// Lecteur AVPlayer plein écran, avec les cookies de la session Trellis.
struct BuiltInPlayerView: View {
    let video: DetectedVideo
    let cookies: [HTTPCookie]

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
            let asset = AVURLAsset(url: video.url, options: [AVURLAssetHTTPCookiesKey: cookies])
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
