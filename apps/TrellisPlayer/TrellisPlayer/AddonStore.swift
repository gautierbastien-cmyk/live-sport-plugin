import Foundation

/// Addon installé : son lien de manifest et le manifest chargé.
struct InstalledAddon: Identifiable, Hashable {
    let manifestURL: URL
    var manifest: AddonManifest?
    var error: String?

    var id: URL { manifestURL }
    var name: String { manifest?.name ?? manifestURL.host ?? manifestURL.absoluteString }
}

/// Liste des addons, sauvegardée dans UserDefaults.
@MainActor
final class AddonStore: ObservableObject {
    @Published private(set) var addons: [InstalledAddon]

    private static let storageKey = "addonManifestURLs"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        addons = saved.compactMap { URL(string: $0) }.map { InstalledAddon(manifestURL: $0) }
    }

    /// Recharge tous les manifests (au lancement ou en tirant pour rafraîchir).
    func refresh() async {
        await withTaskGroup(of: (URL, Result<AddonManifest, Error>).self) { group in
            for addon in addons {
                group.addTask {
                    do { return (addon.manifestURL, .success(try await AddonClient.fetchManifest(addon.manifestURL))) }
                    catch { return (addon.manifestURL, .failure(error)) }
                }
            }
            for await (url, result) in group {
                guard let index = addons.firstIndex(where: { $0.manifestURL == url }) else { continue }
                switch result {
                case .success(let manifest):
                    addons[index].manifest = manifest
                    addons[index].error = nil
                case .failure(let error):
                    addons[index].error = error.localizedDescription
                }
            }
        }
    }

    /// Ajoute un addon à partir d'un lien collé ou intercepté. Renvoie son nom.
    @discardableResult
    func add(_ input: String) async throws -> String {
        guard let url = AddonClient.manifestURL(from: input) else { throw AddonError.invalidURL(input) }
        guard !addons.contains(where: { $0.manifestURL == url }) else { throw AddonError.alreadyInstalled }
        let manifest = try await AddonClient.fetchManifest(url)
        addons.append(InstalledAddon(manifestURL: url, manifest: manifest))
        save()
        return manifest.name
    }

    func remove(atOffsets offsets: IndexSet) {
        addons.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        addons.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Addons capables de fournir `resource` pour cet élément, dans l'ordre de la liste.
    func addons(supporting resource: String, type: String, id: String) -> [InstalledAddon] {
        addons.filter { $0.manifest?.supports(resource, type: type, id: id) == true }
    }

    private func save() {
        UserDefaults.standard.set(addons.map(\.manifestURL.absoluteString), forKey: Self.storageKey)
    }
}
