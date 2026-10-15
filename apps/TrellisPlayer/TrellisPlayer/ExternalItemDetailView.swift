import SwiftUI

/// Fiche d'un film ou d'une série venant de Trakt : métadonnées Trakt, puis
/// recherche de l'équivalent sur Treillis pour pouvoir le lire.
struct ExternalItemDetailView: View {
    let item: ExternalItem

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var playback: PlaybackController

    @State private var match: BaseItem?
    @State private var searching = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: item.backdropURL)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .center, endPoint: .bottom)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.largeTitle.bold())
                    if let tagline = item.media.tagline, !tagline.isEmpty {
                        Text(tagline).font(.subheadline.italic()).foregroundStyle(.secondary)
                    }
                    if !item.infoLine.isEmpty {
                        Text(item.infoLine).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let genres = item.media.genres, !genres.isEmpty {
                        Text(genres.map { $0.capitalized }.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let overview = item.media.overview, !overview.isEmpty {
                        Text(overview).font(.callout).padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                availability.padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await findMatch() }
    }

    @ViewBuilder
    private var availability: some View {
        if searching {
            HStack(spacing: 8) {
                ProgressView()
                Text("Recherche sur Treillis…").foregroundStyle(.secondary)
            }
        } else if let match {
            VStack(spacing: 10) {
                if item.kind == .movie {
                    Button {
                        playback.play(match, client: session.client)
                    } label: {
                        Label("Lecture", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                NavigationLink(value: match) {
                    Label(item.kind == .movie ? "Voir la fiche Treillis (sources)" : "Voir les saisons et épisodes",
                          systemImage: item.kind == .movie ? "info.circle" : "list.bullet")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        } else {
            Label("Introuvable sur Treillis pour le moment.", systemImage: "exclamationmark.magnifyingglass")
                .foregroundStyle(.secondary)
        }
    }

    private func findMatch() async {
        guard searching else { return }
        match = try? await session.client.findMatch(for: item)
        searching = false
    }
}
