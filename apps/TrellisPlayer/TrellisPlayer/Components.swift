import SwiftUI

/// Image distante avec fond neutre pendant le chargement ou en cas d'échec.
struct RemoteImage: View {
    let url: URL?
    var placeholder = "film"

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color(.secondarySystemBackground))
                    Image(systemName: placeholder).font(.title2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Affiche d'un film, d'une série ou d'une chaîne.
struct PosterCard: View {
    let item: BaseItem
    var width: CGFloat = 120

    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: item.posterRatio > 1 ? session.client.landscapeImageURL(for: item)
                                                  : session.client.posterURL(for: item),
                        placeholder: item.isLiveChannel ? "tv" : "film")
                .frame(width: width, height: width / item.posterRatio)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
    }
}

/// Grille d'éléments (contenu d'une tuile, recherche, collection).
struct ItemGrid: View {
    let items: [BaseItem]

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    GridCell(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private struct GridCell: View {
        let item: BaseItem
        @EnvironmentObject private var session: Session

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: session.client.posterURL(for: item),
                                    placeholder: item.isLiveChannel ? "tv" : "film")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(item.title).font(.caption).lineLimit(2)
            }
        }
    }
}

/// Destinations de navigation communes (fiche d'un élément, contenu d'une tuile).
struct AppNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: BaseItem.self) { ItemDetailView(item: $0) }
            .navigationDestination(for: Tile.self) { TileView(tile: $0) }
    }
}

extension View {
    func appNavigation() -> some View { modifier(AppNavigation()) }
}
