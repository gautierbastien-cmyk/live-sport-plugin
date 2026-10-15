import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("defaultPlayer") private var defaultPlayer: PlayerChoice = .ask

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var layout: HomeLayoutStore

    @State private var importing = false
    @State private var importError: String?
    @State private var confirmSignOut = false

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
                        Text("Les tuiles basées sur Trakt, TMDB ou MDBList ne sont pas encore prises en charge.")
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
            .confirmationDialog("Se déconnecter de Treillis ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) { session.signOut() }
            }
        }
    }
}
