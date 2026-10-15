# Trellis Player (iPhone / iPad / Mac)

App SwiftUI pour regarder le contenu des **addons hébergés sur Trellis** (format Stremio),
avec **Infuse** comme lecteur externe.

## Fonctionnement

- **Accueil** : une rangée par catalogue de chaque addon ajouté. Touche une affiche pour voir
  la fiche, les épisodes (séries) et les flux disponibles.
- **Recherche** : cherche dans tous les catalogues qui acceptent la recherche.
- **Trellis** : affiche ton serveur (`https://bastien-trellis.duckdns.org` par défaut).
  Toucher « Installer » sur un addon (lien `stremio://…` ou `…/manifest.json`) l'ajoute à l'app.
- **Réglages** : liste des addons (ajout en collant le lien `manifest.json`, suppression,
  réordonnancement), lecteur par défaut, adresse du serveur.

Quand tu touches un flux, l'app propose **Infuse**, **Lecteur intégré** ou **Copier le lien**
(ou utilise directement le lecteur par défaut choisi dans les Réglages).
Infuse est ouvert via `infuse://x-callback-url/play?url=<lien encodé>`.

## Installer sur ton iPhone

1. Sur un Mac avec **Xcode 16** ou plus récent, ouvre `TrellisPlayer.xcodeproj`.
2. Cible *TrellisPlayer* → **Signing & Capabilities** → choisis ton compte Apple dans *Team*.
3. Branche l'iPhone, sélectionne-le en haut de Xcode, puis ▶︎ (**Run**).
4. Sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → fais confiance à ton
   compte développeur.

## Limites

- **Infuse ne reçoit que l'URL du flux**, sans en-têtes HTTP. Les flux qui exigent un
  Referer/User-Agent (`behaviorHints.proxyHeaders`, signalés en orange) risquent d'échouer
  dans Infuse : utilise le *Lecteur intégré*, qui envoie ces en-têtes.
- Les flux torrent (`infoHash`) ne sont pas pris en charge.
- Avec un compte Apple gratuit, l'app doit être réinstallée depuis Xcode tous les 7 jours.
