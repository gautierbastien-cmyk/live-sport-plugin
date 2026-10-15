import SwiftUI

/// Élément dont on veut les flux (un film, une chaîne, ou un épisode).
struct EpisodeRoute: Hashable {
    let type: String
    let id: String
    let title: String
}

/// Fiche d'un élément : description, épisodes ou flux.
struct MetaDetailView: View {
    let item: MetaItem

    @EnvironmentObject private var store: AddonStore
    @State private var meta: MetaItem?

    private var current: MetaItem { meta ?? item }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowInsets(EdgeInsets())

            let videos = current.videos
            if videos.count > 1 {
                ForEach(seasons(of: videos), id: \.self) { season in
                    Section(season.map { $0 == 0 ? "Bonus" : "Saison \($0)" } ?? "Vidéos") {
                        ForEach(videos.filter { $0.season == season }) { video in
                            NavigationLink(value: EpisodeRoute(type: current.type, id: video.id,
                                                               title: "\(current.name) · \(video.label)")) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.label)
                                    if let released = video.released?.prefix(10) {
                                        Text(released).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                StreamsSection(route: EpisodeRoute(type: current.type, id: videos.first?.id ?? current.id,
                                                   title: current.name))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMeta() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: current.backgroundURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 200)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(current.name).font(.title2.bold())
                let infos = ([current.releaseInfo].compactMap { $0 } + current.genres.prefix(3)).joined(separator: " · ")
                if !infos.isEmpty {
                    Text(infos).font(.subheadline).foregroundStyle(.secondary)
                }
                if let description = current.description, !description.isEmpty {
                    Text(description).font(.callout)
                }
            }
            .padding([.horizontal, .bottom])
        }
    }

    private func seasons(of videos: [MetaVideo]) -> [Int?] {
        var result: [Int?] = []
        for video in videos where !result.contains(video.season) {
            result.append(video.season)
        }
        // Saisons dans l'ordre, bonus (saison 0) et vidéos sans saison à la fin.
        return result.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (let l?, let r?): return (l == 0 ? Int.max : l) < (r == 0 ? Int.max : r)
            case (.some, .none): return true
            default: return false
            }
        }
    }

    /// Charge la fiche complète (épisodes, description) auprès du premier addon qui la fournit.
    private func loadMeta() async {
        guard meta == nil else { return }
        for addon in store.addons(supporting: "meta", type: item.type, id: item.id) {
            if let full = try? await AddonClient.meta(addon: addon.manifestURL, type: item.type, id: item.id) {
                meta = full
                return
            }
        }
    }
}

/// Écran des flux d'un épisode.
struct StreamsView: View {
    let route: EpisodeRoute

    var body: some View {
        List {
            StreamsSection(route: route)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Interroge tous les addons qui fournissent des flux pour cet élément.
struct StreamsSection: View {
    let route: EpisodeRoute

    @EnvironmentObject private var store: AddonStore
    @EnvironmentObject private var playback: PlaybackController
    @State private var results: [(addon: String, streams: [StreamItem], error: String?)] = []
    @State private var loading = true

    var body: some View {
        if loading {
            Section("Flux") {
                HStack {
                    ProgressView()
                    Text("Recherche des flux…").foregroundStyle(.secondary)
                }
            }
            .task(id: route) { await load() }
        } else if results.allSatisfy({ $0.streams.isEmpty }) {
            Section("Flux") {
                Text(results.isEmpty ? "Aucun addon ne fournit de flux pour ce contenu."
                                     : "Aucun flux disponible pour le moment.")
                    .foregroundStyle(.secondary)
                ForEach(results.indices, id: \.self) { index in
                    if let error = results[index].error {
                        Text("\(results[index].addon) : \(error)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Réessayer") { loading = true }
            }
        } else {
            ForEach(results.indices, id: \.self) { index in
                let result = results[index]
                if !result.streams.isEmpty {
                    Section(result.addon) {
                        ForEach(result.streams) { stream in
                            Button {
                                playback.play(stream, title: route.title)
                            } label: {
                                StreamRow(stream: stream)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        let type = route.type
        let id = route.id
        let addons = store.addons(supporting: "stream", type: type, id: id)
        var collected: [(addon: String, streams: [StreamItem], error: String?)] = []
        await withTaskGroup(of: (Int, [StreamItem], String?).self) { group in
            for (index, addon) in addons.enumerated() {
                let url = addon.manifestURL
                group.addTask {
                    do {
                        return (index, try await AddonClient.streams(addon: url, type: type, id: id), nil)
                    } catch {
                        return (index, [], error.localizedDescription)
                    }
                }
            }
            var byIndex: [Int: ([StreamItem], String?)] = [:]
            for await (index, streams, error) in group {
                byIndex[index] = (streams, error)
            }
            for (index, addon) in addons.enumerated() {
                let entry = byIndex[index] ?? ([], nil)
                collected.append((addon: addon.name, streams: entry.0, error: entry.1))
            }
        }
        if Task.isCancelled { return }
        results = collected
        loading = false
    }
}

struct StreamRow: View {
    let stream: StreamItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(stream.heading).font(.body.weight(.semibold))
                if let details = stream.details {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }
                if !stream.headers.isEmpty {
                    Label("En-têtes requis : lecteur intégré conseillé", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch stream.playback {
        case .direct: return "play.circle.fill"
        case .external: return "safari"
        case .unsupported: return "xmark.circle"
        }
    }
}
