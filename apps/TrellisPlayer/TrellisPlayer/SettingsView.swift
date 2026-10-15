import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = AppDefaults.serverURL
    @AppStorage("defaultPlayer") private var defaultPlayer: PlayerChoice = .ask

    @EnvironmentObject private var store: AddonStore
    @EnvironmentObject private var browser: BrowserModel

    @State private var newAddon = ""
    @State private var adding = false
    @State private var addError: String?
    @State private var draftServer = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.addons) { addon in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addon.name)
                            if let version = addon.manifest?.version {
                                Text("v\(version)").font(.caption).foregroundStyle(.secondary)
                            }
                            if let error = addon.error {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                            Text(addon.manifestURL.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .onDelete { store.remove(atOffsets: $0) }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }

                    TextField("https://…/manifest.json", text: $newAddon)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addNewAddon)
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { newAddon = first }
                        }
                        .labelStyle(.titleAndIcon)
                        Spacer()
                        if adding {
                            ProgressView()
                        } else {
                            Button("Ajouter", action: addNewAddon)
                                .disabled(newAddon.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Addons")
                } footer: {
                    if let addError {
                        Text(addError).foregroundStyle(.red)
                    } else {
                        Text("Les addons de Trellis sont ajoutés automatiquement une fois connecté. Tu peux aussi coller un lien manifest.json. Balaie vers la gauche pour supprimer.")
                    }
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
                    Text("Infuse reçoit uniquement l'adresse du flux. Si un flux exige des en-têtes (signalé en orange), utilise le lecteur intégré.")
                }

                Section {
                    TextField("https://…", text: $draftServer)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            if let url = draftServer.normalizedServerURL { serverURL = url.absoluteString }
                        }
                    Button("Se déconnecter de Trellis", role: .destructive) {
                        browser.signOut(serverURL: serverURL)
                    }
                } header: {
                    Text("Trellis")
                }

                Section {
                    LabeledContent("Jeton de connexion", value: TrellisAuth.hasToken(for: serverURL) ? "récupéré" : "aucun")
                    if browser.requests.isEmpty {
                        Text("Aucune requête vue. Ouvre l'onglet Trellis et connecte-toi.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(browser.requests) { request in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(request.method) · \(request.status)")
                                .font(.caption.bold())
                                .foregroundStyle((200..<300).contains(request.status) ? Color.secondary : Color.red)
                            Text(request.url)
                                .font(.caption2.monospaced())
                                .lineLimit(2)
                        }
                    }
                } header: {
                    Text("Diagnostic Trellis")
                } footer: {
                    Text("Si aucun addon n'est trouvé après connexion, envoie une capture de cette liste.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar { EditButton() }
            .refreshable { await store.refresh() }
            .onAppear { draftServer = serverURL }
        }
    }

    private func addNewAddon() {
        let input = newAddon
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty, !adding else { return }
        adding = true
        addError = nil
        Task {
            do {
                try await store.add(input)
                newAddon = ""
            } catch {
                addError = error.localizedDescription
            }
            adding = false
        }
    }
}
