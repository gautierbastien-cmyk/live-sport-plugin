import SwiftUI

/// Accueil façon Strand : sections dans l'ordre de la configuration importée.
struct HomeView: View {
    @EnvironmentObject private var layout: HomeLayoutStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(layout.sections) { section in
                        SectionView(section: section)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Accueil")
            .appNavigation()
        }
    }
}

private struct SectionView: View {
    let section: HomeSection

    var body: some View {
        switch section.source {
        case .continueWatching:
            ContinueWatchingRow(title: section.title ?? "Reprendre la lecture")
        case .group(let group):
            TileRow(title: section.title ?? group.title ?? "", tiles: group.contentSources)
        case .liveTVFavorites:
            ChannelRow(title: section.title ?? "Chaînes favorites", radio: false, wide: section.style == "row_wide")
        case .liveTVRadio:
            ChannelRow(title: section.title ?? "Radio", radio: true, wide: section.style == "row_wide")
        case .unsupported:
            EmptyView()
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .padding(.horizontal)
    }
}

// MARK: - Tuiles

/// Rangée de tuiles larges (Découverte, Streaming Services, Studios…).
private struct TileRow: View {
    let title: String
    let tiles: [Tile]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty { SectionHeader(title: title) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(tiles) { tile in
                        NavigationLink(value: tile) {
                            TileCard(tile: tile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct TileCard: View {
    let tile: Tile

    private var size: CGSize {
        switch tile.tileShape {
        case "poster": return CGSize(width: 130, height: 195)
        case "square": return CGSize(width: 150, height: 150)
        default: return CGSize(width: 260, height: 146)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: tile.coverURL, placeholder: "square.stack")
            if tile.hideTitle != true || tile.coverURL == nil {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                Text(tile.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(tile.title)
    }
}

/// Contenu d'une tuile : ses collections Treillis et ses listes Trakt réunies.
struct TileView: View {
    let tile: Tile

    @EnvironmentObject private var session: Session
    @State private var items: [BaseItem] = []
    @State private var traktItems: [ExternalItem] = []
    @State private var loading = true
    @State private var errors: [String] = []

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding(.top, 60)
            } else if items.isEmpty && traktItems.isEmpty {
                ContentUnavailableView {
                    Label("Rien à afficher", systemImage: "square.stack")
                } description: {
                    Text(emptyMessage)
                }
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !items.isEmpty { ItemGrid(items: items) }
                    if !traktItems.isEmpty { ExternalGrid(items: traktItems) }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(tile.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var emptyMessage: String {
        if let error = errors.first { return error }
        if tile.collectionIds.isEmpty, tile.traktSources.isEmpty, let kind = tile.externalSources.first {
            return "Cette tuile utilise une liste \(kind), qui n'est pas encore prise en charge par l'app."
        }
        return "Cette collection est vide pour le moment."
    }

    private func load() async {
        let client = session.client
        let ids = tile.collectionIds
        let trakt = tile.traktSources
        var serverResults: [Int: [BaseItem]] = [:]
        var traktResults: [Int: [ExternalItem]] = [:]
        var failures: [String] = []

        await withTaskGroup(of: (Int, Result<[BaseItem], Error>).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    do { return (index, .success(try await client.items(parentId: id))) }
                    catch { return (index, .failure(error)) }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let list): serverResults[index] = list
                case .failure(let error): failures.append(error.localizedDescription)
                }
            }
        }

        await withTaskGroup(of: (Int, Result<[ExternalItem], Error>).self) { group in
            for (index, source) in trakt.enumerated() {
                group.addTask {
                    do {
                        switch source {
                        case .traktList(let username, let listId):
                            return (index, .success(try await TraktClient.listItems(username: username, listId: listId)))
                        case .traktBuiltIn(let kind):
                            return (index, .success(try await TraktClient.watchlist(kind)))
                        default:
                            return (index, .success([]))
                        }
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let list): traktResults[index] = list
                case .failure(let error): failures.append(error.localizedDescription)
                }
            }
        }

        var seen = Set<String>()
        items = ids.indices.flatMap { serverResults[$0] ?? [] }.filter { seen.insert($0.id).inserted }
        traktItems = trakt.indices.flatMap { traktResults[$0] ?? [] }.filter { seen.insert($0.id).inserted }
        errors = failures
        loading = false
    }
}

// MARK: - Reprendre la lecture

private struct ContinueWatchingRow: View {
    let title: String

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var playback: PlaybackController
    @State private var items: [BaseItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                // Garde la rangée dans la hiérarchie pour que .task se déclenche.
                Color.clear.frame(height: 1)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(items) { item in
                                Button {
                                    playback.play(item, client: session.client)
                                } label: {
                                    ResumeCard(item: item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    NavigationLink(value: item) {
                                        Label("Voir la fiche", systemImage: "info.circle")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        items = (try? await session.client.resumeItems()) ?? []
    }
}

private struct ResumeCard: View {
    let item: BaseItem
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: session.client.landscapeImageURL(for: item))
                    .frame(width: 260, height: 146)
                if let progress = item.userData?.playedPercentage {
                    GeometryReader { proxy in
                        Capsule().fill(.white.opacity(0.35))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white).frame(width: proxy.size.width * progress / 100)
                            }
                    }
                    .frame(height: 4)
                    .padding(8)
                }
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 260, height: 146)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.seriesName ?? item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let subtitle = item.isEpisode ? item.title : item.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 260, alignment: .leading)
    }
}

// MARK: - TV en direct

private struct ChannelRow: View {
    let title: String
    let radio: Bool
    let wide: Bool

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var playback: PlaybackController
    @State private var channels: [BaseItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if channels.isEmpty {
                // Garde la rangée dans la hiérarchie pour que .task se déclenche.
                Color.clear.frame(height: 1)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(channels) { channel in
                                Button {
                                    playback.play(channel, client: session.client)
                                } label: {
                                    VStack(spacing: 6) {
                                        RemoteImage(url: session.client.posterURL(for: channel, maxWidth: 300),
                                                    placeholder: radio ? "radio" : "tv")
                                            .scaledToFit()
                                            .padding(12)
                                            .frame(width: wide ? 200 : 120, height: wide ? 112 : 120)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        Text(channel.title).font(.caption).lineLimit(1)
                                            .frame(width: wide ? 200 : 120)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        channels = (try? await session.client.channels(radio: radio)) ?? []
    }
}
