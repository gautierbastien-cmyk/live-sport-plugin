// Injecté dans l'interface Trellis. Repère, une fois connecté :
//  - les liens d'addons (…/manifest.json, stremio://…) dans les réponses du
//    serveur et dans la page ;
//  - l'en-tête Authorization envoyé par l'interface (jeton de session) ;
//  - la liste des requêtes (diagnostic).
// Tout est transmis à l'app via window.webkit.messageHandlers.trellis.
(function () {
  if (window.__trellisSniffer) return;
  window.__trellisSniffer = true;

  var ABSOLUTE_RE = /(?:https?|stremio):\/\/[^\s"'<>\\]+?\/manifest\.json/gi;
  var RELATIVE_RE = /["'(](\/[^\s"'<>\\]*?\/manifest\.json)/gi;
  var seen = {};
  var lastAuth = null;

  function post(message) {
    try { window.webkit.messageHandlers.trellis.postMessage(message); } catch (e) { /* hors WKWebView */ }
  }

  function absolute(u) {
    try { return new URL(u, location.href).href; } catch (e) { return null; }
  }

  function report(url) {
    if (!url || seen[url]) return;
    seen[url] = true;
    post({ type: 'manifest', url: url });
  }

  function scanText(text) {
    if (!text || typeof text !== 'string' || text.indexOf('manifest.json') === -1) return;
    // Les URLs peuvent être échappées dans du JSON (\/).
    text = text.replace(/\\\//g, '/');
    var m;
    ABSOLUTE_RE.lastIndex = 0;
    while ((m = ABSOLUTE_RE.exec(text))) report(m[0]);
    RELATIVE_RE.lastIndex = 0;
    while ((m = RELATIVE_RE.exec(text))) report(absolute(m[1]));
  }

  function noteAuth(value) {
    if (!value || value === lastAuth) return;
    lastAuth = value;
    post({ type: 'auth', value: String(value) });
  }

  function sameOrigin(url) {
    var a = absolute(url);
    return !!a && a.indexOf(location.origin) === 0;
  }

  function headerFrom(headers, name) {
    if (!headers) return null;
    try {
      if (typeof headers.get === 'function') return headers.get(name);
      if (Array.isArray(headers)) {
        for (var i = 0; i < headers.length; i++) {
          if (String(headers[i][0]).toLowerCase() === name) return headers[i][1];
        }
        return null;
      }
      for (var key in headers) {
        if (key.toLowerCase() === name) return headers[key];
      }
    } catch (e) {}
    return null;
  }

  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : (input && input.url) || String(input);
      var method = (init && init.method) || (input && input.method) || 'GET';
      if (sameOrigin(url)) {
        noteAuth(headerFrom(init && init.headers, 'authorization') ||
                 headerFrom(input && input.headers, 'authorization'));
      }
      scanText(url);
      return originalFetch.apply(this, arguments).then(function (response) {
        try {
          post({ type: 'request', method: String(method).toUpperCase(), url: absolute(url), status: response.status });
          var type = (response.headers.get('content-type') || '').toLowerCase();
          if (type.indexOf('json') !== -1 || type.indexOf('text') !== -1) {
            response.clone().text().then(scanText, function () {});
          }
        } catch (e) {}
        return response;
      });
    };
  }

  var originalOpen = XMLHttpRequest.prototype.open;
  var originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__trellis = { method: String(method).toUpperCase(), url: absolute(String(url)) };
    this.addEventListener('load', function () {
      try {
        post({ type: 'request', method: this.__trellis.method, url: this.__trellis.url, status: this.status });
        if (this.responseType === '' || this.responseType === 'text') scanText(this.responseText);
      } catch (e) {}
    });
    return originalOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
    try {
      if (String(name).toLowerCase() === 'authorization' && this.__trellis && sameOrigin(this.__trellis.url)) {
        noteAuth(value);
      }
    } catch (e) {}
    return originalSetHeader.apply(this, arguments);
  };

  function scanPage() {
    try {
      var nodes = document.querySelectorAll('a[href], input, textarea, code, pre');
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        scanText(n.getAttribute('href') ? '"' + n.getAttribute('href') + '"' : '');
        if ('value' in n) scanText(String(n.value));
      }
      scanText(document.body ? document.body.innerText : '');
    } catch (e) {}
  }

  var pending = null;
  function scheduleScan() {
    if (pending) return;
    pending = setTimeout(function () { pending = null; scanPage(); }, 500);
  }

  function start() {
    scanPage();
    new MutationObserver(scheduleScan).observe(document.documentElement, {
      childList: true, subtree: true, characterData: true, attributes: true
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
