import Foundation
import Security

/// Connexion au serveur Treillis (Jellyfin). Le jeton est rangé dans le trousseau.
@MainActor
final class Session: ObservableObject {
    @Published private(set) var serverURL: URL?
    @Published private(set) var userId: String?
    @Published private(set) var userName: String?
    @Published private(set) var token: String?

    private enum Keys {
        static let server = "jellyfin.server"
        static let userId = "jellyfin.userId"
        static let userName = "jellyfin.userName"
        static let tokenAccount = "jellyfin.token"
    }

    init() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: Keys.server).flatMap { URL(string: $0) }
        userId = defaults.string(forKey: Keys.userId)
        userName = defaults.string(forKey: Keys.userName)
        token = Keychain.read(Keys.tokenAccount)
    }

    var isSignedIn: Bool { serverURL != nil && token != nil && userId != nil }

    var client: JellyfinClient {
        JellyfinClient(server: serverURL ?? URL(string: AppDefaults.serverURL)!, token: token, userId: userId)
    }

    var lastServer: String {
        UserDefaults.standard.string(forKey: Keys.server) ?? AppDefaults.serverURL
    }

    func signIn(server: String, username: String, password: String) async throws {
        guard let url = server.normalizedServerURL else { throw JellyfinError.invalidServer }
        let result = try await JellyfinClient(server: url, token: nil, userId: nil)
            .authenticate(username: username, password: password)

        let defaults = UserDefaults.standard
        defaults.set(url.absoluteString, forKey: Keys.server)
        defaults.set(result.user.id, forKey: Keys.userId)
        defaults.set(result.user.name ?? username, forKey: Keys.userName)
        Keychain.save(result.accessToken, account: Keys.tokenAccount)

        serverURL = url
        userId = result.user.id
        userName = result.user.name ?? username
        token = result.accessToken
    }

    func signOut() {
        let client = self.client
        Task { await client.logout() }
        Keychain.delete(Keys.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Keys.userId)
        UserDefaults.standard.removeObject(forKey: Keys.userName)
        token = nil
        userId = nil
        userName = nil
    }
}

/// Accès minimal au trousseau iOS pour une chaîne.
enum Keychain {
    private static let service = "TrellisPlayer"

    static func save(_ value: String, account: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
