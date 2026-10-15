import Combine
import WebKit

/// Requête vue passer dans l'interface Trellis (écran de diagnostic).
struct LoggedRequest: Identifiable {
    let id = UUID()
    let method: String
    let url: String
    let status: Int
}

/// Jeton `Authorization` utilisé par l'interface Trellis, réutilisé par l'app
/// pour interroger les addons hébergés sur le même serveur.
enum TrellisAuth {
    private static func key(_ host: String) -> String { "trellis.authorization.\(host)" }

    static func save(_ value: String, host: String) {
        UserDefaults.standard.set(value, forKey: key(host))
    }

    static func header(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        return UserDefaults.standard.string(forKey: key(host))
    }

    static func clear(host: String) {
        UserDefaults.standard.removeObject(forKey: key(host))
    }

    static func hasToken(for serverURL: String) -> Bool {
        serverURL.normalizedServerURL.flatMap(header(for:)) != nil
    }
}

/// Pilote le WKWebView qui affiche Trellis. Une fois connecté, il repère les
/// addons hébergés (liens manifest.json), la session (cookies, jeton) et les
/// transmet à l'app, qui charge ensuite tout elle-même.
@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var pageTitle: String?
    @Published private(set) var requests: [LoggedRequest] = []
    @Published var loadError: String?

    /// Liens d'addons découverts (ou touchés « Installer ») à ajouter.
    let discoveredManifests = PassthroughSubject<String, Never>()

    let webView: WKWebView
    private var observers: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        let controller = configuration.userContentController
        if let scriptURL = Bundle.main.url(forResource: "TrellisSniffer", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        controller.add(WeakScriptMessageHandler(self), name: "trellis")

        webView.navigationDelegate = self
        webView.uiDelegate = self

        observers = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.isLoading = webView.isLoading }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.pageTitle = webView.title }
            },
        ]
    }

    func load(_ serverURL: String) {
        guard let url = serverURL.normalizedServerURL else {
            loadError = "Adresse du serveur invalide : \(serverURL)"
            return
        }
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    func loadIfNeeded(_ serverURL: String) {
        if webView.url == nil { load(serverURL) }
    }

    func reload() { webView.reload() }
    func goBack() { webView.goBack() }

    /// Copie les cookies de la session Trellis vers URLSession, pour que l'app
    /// puisse interroger les addons protégés par la connexion.
    func syncCookies() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// Déconnexion : efface cookies, cache et jeton.
    func signOut(serverURL: String) {
        if let host = serverURL.normalizedServerURL?.host {
            TrellisAuth.clear(host: host)
            for cookie in HTTPCookieStorage.shared.cookies ?? [] where host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        requests.removeAll()
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in self?.load(serverURL) }
        }
    }

    static func isAddonLink(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "stremio" { return true }
        if url.lastPathComponent == "manifest.json" { return true }
        let text = url.absoluteString
        return text.contains("stremio.com") && text.contains("addon=")
    }

    fileprivate func handleMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "manifest":
            if let url = dict["url"] as? String { discoveredManifests.send(url) }
        case "auth":
            if let value = dict["value"] as? String, let host = webView.url?.host {
                TrellisAuth.save(value, host: host)
                probeServerManifest()
            }
        case "request":
            let entry = LoggedRequest(method: dict["method"] as? String ?? "GET",
                                      url: dict["url"] as? String ?? "?",
                                      status: dict["status"] as? Int ?? 0)
            requests.insert(entry, at: 0)
            if requests.count > 50 { requests.removeLast(requests.count - 50) }
        default:
            break
        }
    }

    /// Le serveur Trellis peut exposer lui-même un manifest (il répondait
    /// « Unauthorized » sans connexion) : on le tente à chaque page chargée.
    private func probeServerManifest() {
        guard let url = webView.url, let scheme = url.scheme, let host = url.host else { return }
        let port = url.port.map { ":\($0)" } ?? ""
        discoveredManifests.send("\(scheme)://\(host)\(port)/manifest.json")
    }
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url, Self.isAddonLink(url) {
            discoveredManifests.send(url.absoluteString)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadError = nil
        Task {
            await syncCookies()
            probeServerManifest()
        }
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        // Annulations volontaires (nouvelle navigation, lien intercepté) : rien à signaler.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        loadError = error.localizedDescription
    }
}

// MARK: - WKUIDelegate

extension BrowserModel: WKUIDelegate {
    /// Les liens target="_blank" s'ouvrent dans la même vue.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if Self.isAddonLink(url) {
                discoveredManifests.send(url.absoluteString)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
}

// MARK: - Messages JavaScript

/// Évite le cycle de rétention WKUserContentController → handler → modèle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var model: BrowserModel?

    init(_ model: BrowserModel) {
        self.model = model
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated {
            model?.handleMessage(body)
        }
    }
}
