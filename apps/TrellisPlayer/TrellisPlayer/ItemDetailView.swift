import SwiftUI

/// Fiche d'un film, d'une série, d'un épisode ou d'une collection.
struct ItemDetailView: View {
    let item: BaseItem

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var playback: PlaybackController

    @State private var full: BaseItem?
    @State private var seasons: [BaseItem] = []
    @State private var selectedSeason: String?
    @State private var episodes: [BaseItem] = []
    @State private var children: [BaseItem] = []
    @State private var sources: [MediaSource] = []
    @State private var playSessionId: String?

    private var current: BaseItem { full ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if current.isSeries {
                    seasonsSection
                } else if current.isBrowsable {
                    ItemGrid(items: children)
                } else {
                    playSection
                }
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: session.client.backdropURL(for: current))
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .center, endPoint: .bottom)
                }

            VStack(alignment: .leading, spacing: 8) {
                if let seriesName = current.seriesName, current.isEpisode {
                    Text(seriesName).font(.headline).foregroundStyle(.secondary)
                }
                Text(current.title).font(.largeTitle.bold())
                if let tagline = current.taglines?.first, !tagline.isEmpty {
                    Text(tagline).font(.subheadline.italic()).foregroundStyle(.secondary)
                }
                if current.isEpisode, let season = current.parentIndexNumber, let number = current.indexNumber {
                    Text("Saison \(season) · Épisode \(number)").font(.subheadline).foregroundStyle(.secondary)
                }
                if !current.infoLine.isEmpty {
                    Text(current.infoLine).font(.subheadline).foregroundStyle(.secondary)
                }
                if let overview = current.overview, !overview.isEmpty {
                    Text(overview).font(.callout)
                }
                if let studios = current.studios?.compactMap(\.name), !studios.isEmpty {
                    Text("Studio : " + studios.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            castRow
        }
    }

    /// Réalisateurs et acteurs principaux.
    @ViewBuilder
    private var castRow: some View {
        let people = (current.people ?? []).filter { ["Actor", "Director", "GuestStar"].contains($0.type ?? "") }
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Distribution").font(.headline).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(people.prefix(25)) { person in
                            VStack(spacing: 4) {
                                RemoteImage(url: session.client.imageURL(itemId: person.id, type: "Primary",
                                                                         tag: person.primaryImageTag, maxWidth: 200),
                                            placeholder: "person.fill")
                                    .frame(width: 72, height: 72)
                                    .clipShape(Circle())
                                Text(person.name ?? "").font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                Text(person.type == "Director" ? "Réalisation" : (person.role ?? ""))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 84)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Lecture

    private var playSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if let first = sources.first {
                    playback.play(first, of: current, playSessionId: playSessionId, client: session.client)
                } else {
                    playback.play(current, client: session.client)
                }
            } label: {
                Label(current.userData?.playedPercentage != nil ? "Reprendre" : "Lecture", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            if sources.count > 1 {
                Text("Sources (\(sources.count))").font(.headline).padding(.horizontal)
                ForEach(sources) { source in
                    Button {
                        playback.play(source, of: current, playSessionId: playSessionId, client: session.client)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "play.circle").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.label).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                                if let details = source.details {
                                    Text(details).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Séries

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !seasons.isEmpty {
                Picker("Saison", selection: $selectedSeason) {
                    ForEach(seasons) { season in
                        Text(season.title).tag(Optional(season.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
            }
            ForEach(episodes) { episode in
                NavigationLink(value: episode) {
                    HStack(alignment: .top, spacing: 12) {
                        RemoteImage(url: session.client.landscapeImageURL(for: episode, maxWidth: 400))
                            .frame(width: 140, height: 79)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.indexNumber.map { "\($0). \(episode.title)" } ?? episode.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            if let overview = episode.overview {
                                Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: selectedSeason) { _, _ in
            Task { await loadEpisodes() }
        }
    }

    // MARK: - Chargement

    private func load() async {
        let client = session.client
        if full == nil, let loaded = try? await client.item(id: item.id) {
            full = loaded
        }
        if current.isSeries {
            if seasons.isEmpty {
                seasons = (try? await client.seasons(seriesId: current.id)) ?? []
                selectedSeason = seasons.first(where: { $0.indexNumber != 0 })?.id ?? seasons.first?.id
            }
        } else if current.isBrowsable {
            if children.isEmpty {
                children = (try? await client.items(parentId: current.id)) ?? []
            }
        } else if sources.isEmpty, !current.isLiveChannel {
            // Les chaînes en direct ouvrent leur flux au moment de la lecture seulement.
            if let info = try? await client.playbackInfo(itemId: current.id) {
                sources = info.mediaSources ?? []
                playSessionId = info.playSessionId
            }
        }
    }

    private func loadEpisodes() async {
        guard let selectedSeason else { return }
        episodes = (try? await session.client.episodes(seriesId: current.id, seasonId: selectedSeason)) ?? []
    }
}
