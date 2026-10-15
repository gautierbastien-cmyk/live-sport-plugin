import SwiftUI

struct RootView: View {
    @AppStorage("serverURL") private var serverURL = AppDefaults.serverURL

    @StateObject private var store = AddonStore()
    @StateObject private var playback = PlaybackController()
    @StateObject private var browser = BrowserModel()
    @State private var tab = AppTab.home

    enum AppTab { case home, search, trellis, settings }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(openTrellis: { tab = .trellis })
                .tabItem { Label("Accueil", systemImage: "house") }
                .tag(AppTab.home)
            SearchView()
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            TrellisTabView(openHome: { tab = .home })
                .tabItem { Label("Trellis", systemImage: "globe") }
                .tag(AppTab.trellis)
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environmentObject(store)
        .environmentObject(playback)
        .environmentObject(browser)
        .modifier(PlaybackPresenter(playback: playback))
        .onAppear {
            // Première utilisation : on commence par la connexion à Trellis.
            if store.addons.isEmpty { tab = .trellis }
            browser.loadIfNeeded(serverURL)
        }
        .onChange(of: serverURL) { _, newValue in browser.load(newValue) }
        .onReceive(browser.discoveredManifests) { link in
            Task { await store.addDiscovered(link) }
        }
        .task {
            await browser.syncCookies()
            await store.refresh()
        }
    }
}
