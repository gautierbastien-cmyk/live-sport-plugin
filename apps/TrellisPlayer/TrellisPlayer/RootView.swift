import SwiftUI

struct RootView: View {
    @StateObject private var session = Session()
    @StateObject private var layout = HomeLayoutStore()
    @StateObject private var playback = PlaybackController()

    var body: some View {
        Group {
            if session.isSignedIn {
                TabView {
                    HomeView()
                        .tabItem { Label("Accueil", systemImage: "house") }
                    SearchView()
                        .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                    SettingsView()
                        .tabItem { Label("Réglages", systemImage: "gearshape") }
                }
                .modifier(PlaybackPresenter(playback: playback))
            } else {
                LoginView()
            }
        }
        .environmentObject(session)
        .environmentObject(layout)
        .environmentObject(playback)
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: Session

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Serveur", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Nom d'utilisateur", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                        .onSubmit(signIn)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Les mêmes identifiants que dans Strand.")
                    }
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text("Se connecter").bold() }
                            Spacer()
                        }
                    }
                    .disabled(working || username.isEmpty || server.normalizedServerURL == nil)
                }
            }
            .navigationTitle("Treillis")
            .onAppear { if server.isEmpty { server = session.lastServer } }
        }
    }

    private func signIn() {
        guard !working else { return }
        working = true
        error = nil
        Task {
            do {
                try await session.signIn(server: server, username: username, password: password)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
