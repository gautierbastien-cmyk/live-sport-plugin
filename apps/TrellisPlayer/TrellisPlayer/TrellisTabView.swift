import SwiftUI

/// Onglet de connexion à Trellis. Une fois connecté, l'app repère toute seule
/// les addons hébergés et les ajoute à l'Accueil.
struct TrellisTabView: View {
    let openHome: () -> Void

    @AppStorage("serverURL") private var serverURL = AppDefaults.serverURL

    @EnvironmentObject private var store: AddonStore
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        NavigationStack {
            WebView(webView: browser.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if browser.isLoading {
                        ProgressView().padding(8)
                    }
                }
                .overlay {
                    if let error = browser.loadError {
                        ContentUnavailableView {
                            Label("Trellis inaccessible", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Réessayer") { browser.load(serverURL) }
                                .buttonStyle(.borderedProminent)
                        }
                        .background(.background)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !store.addons.isEmpty {
                        Button(action: openHome) {
                            Label(store.addons.count == 1 ? "1 addon trouvé · Voir le contenu"
                                                          : "\(store.addons.count) addons trouvés · Voir le contenu",
                                  systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.bottom, 24)
                    }
                }
                .navigationTitle(browser.pageTitle?.isEmpty == false ? browser.pageTitle! : "Trellis")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!browser.canGoBack)
                            .accessibilityLabel("Retour")
                        Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Recharger")
                    }
                }
        }
    }
}
