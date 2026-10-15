import SwiftUI

/// Accueil : une rangée par catalogue de chaque addon.
struct HomeView: View {
    let openSettings: () -> Void
    let openTrellis: () -> Void

    @EnvironmentObject private var store: AddonStore

    var body: some View {
        NavigationStack {
            Group {
                if store.addons.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun addon", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("Ajoute tes addons Trellis : touche « Installer » dans l'onglet Trellis, ou colle le lien manifest.json dans les Réglages.")
                    } actions: {
                        Button("Ouvrir Trellis", action: openTrellis)
                            .buttonStyle(.borderedProminent)
                        Button("Coller un lien", action: openSettings)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(store.addons) { addon in
                                if let error = addon.error, addon.manifest == nil {
                                    Label("\(addon.name) : \(error)", systemImage: "exclamationmark.triangle")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal)
                                }
                                if let manifest = addon.manifest {
                                    ForEach(manifest.catalogs, id: \.self) { catalog in
                                        if let extras = catalog.browseExtras {
                                            CatalogRow(addon: addon, catalog: catalog, extras: extras)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Trellis")
            .navigationDestination(for: MetaItem.self) { MetaDetailView(item: $0) }
            .navigationDestination(for: EpisodeRoute.self) { StreamsView(route: $0) }
        }
    }
}

/// Recherche dans tous les catalogues qui l'acceptent.
struct SearchView: View {
    @EnvironmentObject private var store: AddonStore
    @State private var text = ""
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if query.isEmpty {
                        ContentUnavailableView("Rechercher", systemImage: "magnifyingglass",
                                               description: Text("Cherche dans les catalogues de tes addons."))
                    } else {
                        ForEach(store.addons) { addon in
                            if let manifest = addon.manifest {
                                ForEach(manifest.catalogs, id: \.self) { catalog in
                                    if let extras = catalog.searchExtras(query) {
                                        CatalogRow(addon: addon, catalog: catalog, extras: extras, hideWhenEmpty: true)
                                            .id("\(addon.id)|\(catalog.type)|\(catalog.id)|\(query)")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Recherche")
            .searchable(text: $text, prompt: "Film, série, chaîne…")
            .onSubmit(of: .search) { query = text.trimmingCharacters(in: .whitespaces) }
            .navigationDestination(for: MetaItem.self) { MetaDetailView(item: $0) }
            .navigationDestination(for: EpisodeRoute.self) { StreamsView(route: $0) }
        }
    }
}

/// Rangée horizontale d'affiches pour un catalogue.
struct CatalogRow: View {
    let addon: InstalledAddon
    let catalog: CatalogDefinition
    let extras: [(name: String, value: String)]
    var hideWhenEmpty = false

    @State private var items: [MetaItem] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        if hideWhenEmpty, loaded, items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalog.title).font(.title3.bold())
                    Text("\(addon.name) · \(catalog.type)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                } else if !loaded {
                    ProgressView().padding(.horizontal)
                } else if items.isEmpty {
                    Text("Vide pour le moment.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    PosterCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard !loaded else { return }
        do {
            let metas = try await AddonClient.catalog(addon: addon.manifestURL, type: catalog.type,
                                                      id: catalog.id, extras: extras)
            var seen = Set<String>()
            items = metas.filter { seen.insert($0.id).inserted }
        } catch {
            // Rangée sortie de l'écran avant la fin du chargement : on réessaiera.
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

struct PosterCard: View {
    let item: MetaItem

    private var width: CGFloat { item.posterAspectRatio > 1 ? 220 : 120 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: item.posterURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "film").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: width, height: width / item.posterAspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
        }
    }
}
