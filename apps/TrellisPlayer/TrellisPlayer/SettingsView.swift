import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("defaultPlayer") private var defaultPlayer: PlayerChoice = .ask

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var layout: HomeLayoutStore

    @State private var importing = false
    @State private var importError: String?
    @State private var confirmSignOut = false
    @State private var traktClientId = TraktAccount.clientId
    @State private var traktSecret = TraktAccount.clientSecret
    @State private var traktConnected = TraktAccount.isConnected
    @State private var showTraktConnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Compte") {
                    LabeledContent("Serveur", value: session.serverURL?.host ?? "—")
                    LabeledContent("Utilisateur", value: session.userName ?? "—")
                    Button("Se déconnecter", role: .destructive) { confirmSignOut = true }
                }

                Section {
                    Picker("Lecteur par défaut", selection: $defaultPlayer) {
                        ForEach(PlayerChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    Link("Installer Infuse (App Store)", destination: ExternalPlayer.infuseAppStoreURL)
                } header: {
                    Text("Lecture")
                } footer: {
                    Text("Infuse lit le fichier original. Le lecteur intégré utilise une version adaptée par le serveur.")
                }

                Section {
                    TextField("Client ID", text: $traktClientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: traktClientId) { _, value in TraktAccount.clientId = value }
                    SecureField("Client Secret", text: $traktSecret)
                        .onChange(of: traktSecret) { _, value in TraktAccount.clientSecret = value }
                    if traktConnected {
                        LabeledContent("Compte", value: "connecté")
                        Button("Déconnecter Trakt", role: .destructive) {
                            TraktAccount.disconnect()
                            traktConnected = false
                        }
                    } else {
                        Button("Connecter mon compte Trakt") { showTraktConnect = true }
                            .disabled(traktClientId.isEmpty || traktSecret.isEmpty)
                    }
                } header: {
                    Text("Trakt")
                } footer: {
                    Text("Crée une application sur trakt.tv/oauth/applications (Redirect URI : urn:ietf:wg:oauth:2.0:oob) et colle son Client ID et son Client Secret. Le Client ID suffit pour les listes publiques ; la connexion du compte est nécessaire pour la Watchlist.")
                }

                Section {
                    LabeledContent("Configuration", value: layout.isCustom ? "importée" : "Strand (par défaut)")
                    LabeledContent("Sections", value: String(layout.sections.count))
                    Button("Importer un export Strand (.json)") { importing = true }
                    if layout.isCustom {
                        Button("Revenir à la configuration par défaut") { layout.resetToDefault() }
                    }
                } header: {
                    Text("Page d'accueil")
                } footer: {
                    if let importError {
                        Text(importError).foregroundStyle(.red)
                    } else {
                        Text("Les tuiles basées sur TMDB ou MDBList ne sont pas encore prises en charge.")
                    }
                }
            }
            .navigationTitle("Réglages")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    try layout.importLayout(from: result.get())
                    importError = nil
                } catch {
                    importError = "Import impossible : ce fichier n'est pas un export d'accueil Strand."
                }
            }
            .sheet(isPresented: $showTraktConnect, onDismiss: { traktConnected = TraktAccount.isConnected }) {
                TraktConnectView()
            }
            .confirmationDialog("Se déconnecter de Treillis ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) { session.signOut() }
            }
        }
    }
}

/// Connexion Trakt par code : l'utilisateur saisit le code sur trakt.tv/activate.
private struct TraktConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var code: TraktDeviceCode?
    @State private var error: String?
    @State private var connected = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if connected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green)
                    Text("Compte Trakt connecté").font(.title3.bold())
                } else if let error {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                    Text(error).multilineTextAlignment(.center)
                } else if let code {
                    Text("Va sur cette page et saisis le code :").foregroundStyle(.secondary)
                    Button(code.verification_url) {
                        if let url = URL(string: code.verification_url) { openURL(url) }
                    }
                    Text(code.user_code)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copier le code") { UIPasteboard.general.string = code.user_code }
                        .buttonStyle(.bordered)
                    ProgressView("En attente de validation…").padding(.top)
                } else {
                    ProgressView()
                }
            }
            .padding()
            .navigationTitle("Connexion Trakt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(connected ? "OK" : "Annuler") { dismiss() }
                }
            }
            .task { await run() }
        }
    }

    private func run() async {
        do {
            let code = try await TraktClient.startDeviceAuth()
            self.code = code
            let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
            while Date() < deadline {
                try await Task.sleep(nanoseconds: UInt64(max(code.interval, 5)) * 1_000_000_000)
                if let token = try await TraktClient.pollDeviceToken(code) {
                    TraktAccount.store(token)
                    connected = true
                    return
                }
            }
            error = "Le code a expiré. Réessaie."
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
