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
        ignored.remove(url.absoluteString)
        addons.append(InstalledAddon(manifestURL: url, manifest: manifest))
        save()
        return manifest.name
    }

    /// Ajoute sans bruit un addon repéré dans l'interface Trellis. Les liens
    /// invalides ou inaccessibles sont ignorés (on réessaiera à la prochaine page).
    func addDiscovered(_ link: String) async {
        guard let url = AddonClient.manifestURL(from: link),
              !addons.contains(where: { $0.manifestURL == url }),
              !inFlight.contains(url),
              !ignored.contains(url.absoluteString) else { return }
        inFlight.insert(url)
        defer { inFlight.remove(url) }
        guard let manifest = try? await AddonClient.fetchManifest(url),
              !addons.contains(where: { $0.manifestURL == url }) else { return }
        addons.append(InstalledAddon(manifestURL: url, manifest: manifest))
        save()
    }

    private var inFlight: Set<URL> = []

    /// Addons supprimés à la main : la découverte automatique ne les rajoute pas.
    private var ignored: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.ignoredKey) }
    }
    private static let ignoredKey = "ignoredAddonManifestURLs"

    func remove(atOffsets offsets: IndexSet) {
        for index in offsets { ignored.insert(addons[index].manifestURL.absoluteString) }
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
