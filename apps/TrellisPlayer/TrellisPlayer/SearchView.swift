import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var session: Session

    @State private var text = ""
    @State private var results: [BaseItem] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if searching {
                    ProgressView().padding(.top, 60)
                } else if results.isEmpty {
                    ContentUnavailableView(searched ? "Aucun résultat" : "Rechercher",
                                           systemImage: "magnifyingglass",
                                           description: Text(searched ? "Essaie un autre titre."
                                                                      : "Films, séries et chaînes de Treillis."))
                        .padding(.top, 40)
                } else {
                    ItemGrid(items: results).padding(.vertical)
                }
            }
            .navigationTitle("Recherche")
            .searchable(text: $text, prompt: "Titre…")
            .onSubmit(of: .search) { Task { await search() } }
            .appNavigation()
        }
    }

    private func search() async {
        let term = text.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        searching = true
        results = (try? await session.client.search(term)) ?? []
        searching = false
        searched = true
    }
}
