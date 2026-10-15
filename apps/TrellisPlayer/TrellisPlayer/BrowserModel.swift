import Combine
import WebKit

/// Pilote le WKWebView de l'onglet Trellis. La connexion se fait dans la page
/// (cookies conservés) ; les liens d'installation d'addon (stremio://…,
/// …/manifest.json) sont interceptés pour ajouter l'addon dans l'app.
@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var pageTitle: String?
    @Published var loadError: String?

    /// Émis quand la page ouvre un lien d'installation d'addon.
    let addonLinks = PassthroughSubject<String, Never>()

    let webView: WKWebView
    private var observers: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        super.init()

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

    /// Supprime cookies et cache (déconnexion de Trellis).
    func clearWebsiteData(then serverURL: String) {
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
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url, Self.isAddonLink(url) {
            addonLinks.send(url.absoluteString)
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
                addonLinks.send(url.absoluteString)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
}
