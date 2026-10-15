import SwiftUI

struct RootView: View {
    @StateObject private var store = AddonStore()
    @StateObject private var playback = PlaybackController()
    @State private var tab = AppTab.home

    enum AppTab { case home, search, trellis, settings }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(openSettings: { tab = .settings }, openTrellis: { tab = .trellis })
                .tabItem { Label("Accueil", systemImage: "house") }
                .tag(AppTab.home)
            SearchView()
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            TrellisTabView()
                .tabItem { Label("Trellis", systemImage: "globe") }
                .tag(AppTab.trellis)
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environmentObject(store)
        .environmentObject(playback)
        .modifier(PlaybackPresenter(playback: playback))
        .task { await store.refresh() }
    }
}
