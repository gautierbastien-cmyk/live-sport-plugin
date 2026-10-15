import SwiftUI

struct ContentView: View {
    @AppStorage("serverURL") private var serverURL = AppDefaults.serverURL
    @AppStorage("defaultPlayer") private var defaultPlayer: PlayerChoice = .ask

    @StateObject private var browser = BrowserModel()
    @Environment(\.openURL) private var openURL

    @State private var showSettings = false
    @State private var showDetected = false
    @State private var choiceVideo: DetectedVideo?
    @State private var builtInVideo: DetectedVideo?
    @State private var builtInCookies: [HTTPCookie] = []
    @State private var infuseMissing = false
    /// Vidéos que l'utilisateur a choisi de laisser dans la page (on ne redemande pas).
    @State private var keptInPage: Set<URL> = []

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
                .navigationTitle(browser.pageTitle?.isEmpty == false ? browser.pageTitle! : "Trellis")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .onAppear { browser.loadIfNeeded(serverURL) }
        .onChange(of: serverURL) { _, newValue in browser.load(newValue) }
        .onReceive(browser.playRequests) { handlePlay($0) }
        .confirmationDialog("Lire la vidéo",
                            isPresented: Binding(get: { choiceVideo != nil }, set: { if !$0 { choiceVideo = nil } }),
                            titleVisibility: .visible,
                            presenting: choiceVideo) { video in
            Button("Ouvrir dans Infuse") { play(video, with: .infuse) }
            Button("Lecteur intégré") { play(video, with: .builtIn) }
            Button("Continuer dans la page") { keptInPage.insert(video.url) }
            Button("Annuler", role: .cancel) {}
        } message: { video in
            Text(video.displayName)
        }
        .alert("Infuse n'est pas installé", isPresented: $infuseMissing) {
            Button("Ouvrir l'App Store") { openURL(ExternalPlayer.infuseAppStoreURL) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Installe Infuse pour l'utiliser comme lecteur externe.")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onSignOut: { browser.clearWebsiteData(then: serverURL) })
        }
        .sheet(isPresented: $showDetected) {
            DetectedVideosView(videos: browser.detected,
                               onPlay: { video, choice in
                                   showDetected = false
                                   play(video, with: choice)
                               },
                               onClear: { browser.clearDetected() })
        }
        .fullScreenCover(item: $builtInVideo) { video in
            BuiltInPlayerView(video: video, cookies: builtInCookies)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }
                .disabled(!browser.canGoBack)
                .accessibilityLabel("Retour")
            Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("Recharger")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showDetected = true } label: {
                Label("Vidéos détectées (\(browser.detected.count))", systemImage: "play.rectangle.on.rectangle")
                    .labelStyle(.iconOnly)
                    .overlay(alignment: .topTrailing) {
                        if !browser.detected.isEmpty {
                            Text("\(browser.detected.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(.red))
                                .offset(x: 8, y: -6)
                        }
                    }
            }
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Réglages")
        }
    }

    private func handlePlay(_ video: DetectedVideo) {
        guard !keptInPage.contains(video.url) else { return }
        switch defaultPlayer {
        case .ask:
            if choiceVideo == nil, builtInVideo == nil { choiceVideo = video }
        case .infuse, .builtIn:
            play(video, with: defaultPlayer)
        case .web:
            break
        }
    }

    private func play(_ video: DetectedVideo, with choice: PlayerChoice) {
        switch choice {
        case .infuse:
            browser.pauseWebMedia()
            ExternalPlayer.openInInfuse(video.url) { opened in
                if !opened { infuseMissing = true }
            }
        case .builtIn:
            browser.pauseWebMedia()
            Task {
                builtInCookies = await browser.cookies()
                builtInVideo = video
            }
        case .ask, .web:
            break
        }
    }
}

/// Liste des vidéos repérées dans la page, avec le choix du lecteur.
private struct DetectedVideosView: View {
    let videos: [DetectedVideo]
    let onPlay: (DetectedVideo, PlayerChoice) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if videos.isEmpty {
                    ContentUnavailableView("Aucune vidéo détectée",
                                           systemImage: "film",
                                           description: Text("Lance une vidéo dans Trellis : son lien apparaîtra ici."))
                } else {
                    List(videos) { video in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.displayName).font(.headline)
                            Text(video.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            HStack {
                                Button("Infuse") { onPlay(video, .infuse) }
                                    .buttonStyle(.borderedProminent)
                                Button("Lecteur intégré") { onPlay(video, .builtIn) }
                                    .buttonStyle(.bordered)
                                Spacer()
                                ShareLink(item: video.url) { Image(systemName: "square.and.arrow.up") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Vidéos détectées")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Effacer") { onClear() }.disabled(videos.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
