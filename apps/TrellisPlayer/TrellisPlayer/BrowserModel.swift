import Combine
import WebKit

/// Pilote le WKWebView qui affiche Trellis et collecte les vidéos détectées.
/// La connexion à Trellis se fait dans la page : les cookies restent stockés
/// dans le magasin persistant de WebKit entre deux lancements.
@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var detected: [DetectedVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var pageTitle: String?
    @Published var loadError: String?

    /// Émis quand une vidéo démarre (lecture dans la page ou lien direct).
    let playRequests = PassthroughSubject<DetectedVideo, Never>()

    let webView: WKWebView
    private var observers: [NSKeyValueObservation] = []

    private static let videoExtensions: Set<String> = ["m3u8", "mp4", "m4v", "mkv", "webm", "mov", "avi", "mpd"]
    private static let videoMimeTypes: Set<String> = [
        "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl",
        "application/dash+xml",
    ]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        let controller = configuration.userContentController
        if let scriptURL = Bundle.main.url(forResource: "VideoSniffer", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
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

    func clearDetected() { detected.removeAll() }

    /// Met en pause les vidéos de la page avant de passer la main à un autre lecteur.
    func pauseWebMedia() {
        webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(function(m){m.pause()})")
        // Les lecteurs sont souvent dans des iframes : on les met en pause aussi.
        for frame in pendingFrames {
            webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(function(m){m.pause()})",
                                       in: frame, in: .page) { _ in }
        }
        pendingFrames.removeAll()
    }

    /// Cookies de la session Trellis, transmis au lecteur intégré.
    func cookies() async -> [HTTPCookie] {
        await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    }

    /// Supprime cookies et cache (déconnexion de Trellis).
    func clearWebsiteData(then serverURL: String) {
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                self?.clearDetected()
                self?.load(serverURL)
            }
        }
    }

    // MARK: - Détection

    private var pendingFrames: [WKFrameInfo] = []

    @discardableResult
    private func register(_ url: URL, title: String?) -> DetectedVideo {
        if let existing = detected.first(where: { $0.url == url }) { return existing }
        let video = DetectedVideo(url: url, pageTitle: title ?? pageTitle)
        detected.insert(video, at: 0)
        return video
    }

    fileprivate func handleMessage(_ body: Any, frame: WKFrameInfo) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        let title = dict["title"] as? String
        let url = (dict["url"] as? String).flatMap(URL.init(string:))

        switch type {
        case "found":
            if let url { register(url, title: title) }
        case "play":
            guard let url = url ?? detected.first?.url else { return }
            if !frame.isMainFrame { pendingFrames.append(frame) }
            playRequests.send(register(url, title: title))
        default:
            break
        }
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isVideoResponse(_ response: URLResponse) -> Bool {
        guard let mime = response.mimeType?.lowercased() else { return false }
        return mime.hasPrefix("video/") || videoMimeTypes.contains(mime)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Un lien qui pointe directement vers un fichier vidéo : on le confie au lecteur choisi.
        if let url = navigationAction.request.url, Self.isVideoURL(url),
           navigationAction.targetFrame?.isMainFrame ?? true {
            playRequests.send(register(url, title: nil))
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, Self.isVideoResponse(navigationResponse.response),
           let url = navigationResponse.response.url {
            playRequests.send(register(url, title: nil))
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
        // Annulations volontaires (nouvelle navigation, vidéo interceptée) : rien à signaler.
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
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - Messages JavaScript

/// Évite le cycle de rétention WKUserContentController → handler → WKWebView.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var model: BrowserModel?

    init(_ model: BrowserModel) {
        self.model = model
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let body = message.body
        let frame = message.frameInfo
        MainActor.assumeIsolated {
            model?.handleMessage(body, frame: frame)
        }
    }
}
