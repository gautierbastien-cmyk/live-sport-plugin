import SwiftUI

/// Onglet qui affiche le site Trellis. Toucher « Installer » sur un addon l'ajoute à l'app.
struct TrellisTabView: View {
    @AppStorage("serverURL") private var serverURL = AppDefaults.serverURL

    @EnvironmentObject private var store: AddonStore
    @StateObject private var browser = BrowserModel()

    @State private var pendingLink: String?
    @State private var resultMessage: String?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            WebView(webView: browser.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if browser.isLoading || adding {
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
        .onAppear { browser.loadIfNeeded(serverURL) }
        .onChange(of: serverURL) { _, newValue in browser.load(newValue) }
        .onReceive(browser.addonLinks) { pendingLink = $0 }
        .alert("Ajouter cet addon ?",
               isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }),
               presenting: pendingLink) { link in
            Button("Ajouter") { add(link) }
            Button("Annuler", role: .cancel) {}
        } message: { link in
            Text(AddonClient.manifestURL(from: link)?.absoluteString ?? link)
        }
        .alert("Addons",
               isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func add(_ link: String) {
        adding = true
        Task {
            do {
                let name = try await store.add(link)
                resultMessage = "« \(name) » a été ajouté. Ses catalogues sont dans l'onglet Accueil."
            } catch {
                resultMessage = error.localizedDescription
            }
            adding = false
        }
    }
}
