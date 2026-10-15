// Injecté dans chaque frame de la page Trellis (y compris les iframes).
// Repère les URLs vidéo (requêtes réseau, <video>, <source>) et prévient
// l'app native via window.webkit.messageHandlers.trellis.
(function () {
  if (window.__trellisSniffer) return;
  window.__trellisSniffer = true;

  var VIDEO_RE = /\.(m3u8|mp4|m4v|mkv|webm|mov|avi|mpd|ts)(\?|#|$)/i;
  var lastStream = null;
  var seen = {};

  function absolute(u) {
    try { return new URL(u, location.href).href; } catch (e) { return null; }
  }

  function post(type, url) {
    try {
      window.webkit.messageHandlers.trellis.postMessage({
        type: type,
        url: url,
        title: document.title || null
      });
    } catch (e) { /* hors WKWebView */ }
  }

  function found(u) {
    if (!u) return;
    if (typeof u !== 'string') {
      try { u = u.url || String(u); } catch (e) { return; }
    }
    var a = absolute(u);
    if (!a || !/^https?:/i.test(a) || !VIDEO_RE.test(a)) return;
    // Les segments .ts d'un flux HLS ne sont pas lisibles seuls.
    if (/\.ts(\?|#|$)/i.test(a) && lastStream) return;
    lastStream = a;
    if (seen[a]) return;
    seen[a] = true;
    post('found', a);
  }

  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input) {
      try { found(typeof input === 'string' ? input : input && input.url); } catch (e) {}
      return originalFetch.apply(this, arguments);
    };
  }

  var originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    try { found(String(url)); } catch (e) {}
    return originalOpen.apply(this, arguments);
  };

  var srcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
  if (srcDescriptor && srcDescriptor.set) {
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      configurable: true,
      enumerable: srcDescriptor.enumerable,
      get: srcDescriptor.get,
      set: function (v) {
        try { found(v); } catch (e) {}
        return srcDescriptor.set.call(this, v);
      }
    });
  }

  var originalSetAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (name, value) {
    try {
      if (name && String(name).toLowerCase() === 'src' &&
          (this instanceof HTMLMediaElement || this instanceof HTMLSourceElement)) {
        found(value);
      }
    } catch (e) {}
    return originalSetAttribute.apply(this, arguments);
  };

  // Quand une vidéo démarre, on envoie l'URL réellement lue. Avec hls.js la
  // source est un blob:, on se rabat alors sur le dernier flux détecté.
  document.addEventListener('play', function (event) {
    var el = event.target;
    if (!(el instanceof HTMLVideoElement)) return;
    var src = el.currentSrc || el.src;
    var url = src && /^https?:/i.test(src) ? absolute(src) : lastStream;
    post('play', url || null);
  }, true);

  function scan() {
    var nodes = document.querySelectorAll('video[src], video source[src]');
    for (var i = 0; i < nodes.length; i++) found(nodes[i].getAttribute('src'));
  }

  function observe() {
    scan();
    new MutationObserver(scan).observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['src']
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', observe);
  } else {
    observe();
  }
})();
