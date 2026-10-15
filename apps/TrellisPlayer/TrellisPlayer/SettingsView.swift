import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = AppDefaults.serverURL
    @AppStorage("defaultPlayer") private var defaultPlayer: PlayerChoice = .ask

    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftURL = ""
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $draftURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Serveur Trellis")
                } footer: {
                    if draftURL.normalizedServerURL == nil {
                        Text("Adresse invalide.").foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Lecteur par défaut", selection: $defaultPlayer) {
                        ForEach(PlayerChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                } header: {
                    Text("Lecture")
                } footer: {
                    Text("Quand une vidéo démarre dans Trellis, elle est ouverte avec ce lecteur. "
                         + "Infuse reçoit uniquement l'adresse du flux : si le serveur exige d'être connecté "
                         + "pour lire le flux, utilise le lecteur intégré.")
                }

                Section {
                    Link("Installer Infuse (App Store)", destination: ExternalPlayer.infuseAppStoreURL)
                }

                Section {
                    Button("Se déconnecter de Trellis", role: .destructive) {
                        confirmSignOut = true
                    }
                } footer: {
                    Text("Efface les cookies et le cache du site.")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if let url = draftURL.normalizedServerURL {
                            serverURL = url.absoluteString
                        }
                        dismiss()
                    }
                    .disabled(draftURL.normalizedServerURL == nil)
                }
            }
            .confirmationDialog("Se déconnecter de Trellis ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) {
                    onSignOut()
                    dismiss()
                }
            }
            .onAppear { draftURL = serverURL }
        }
    }
}
