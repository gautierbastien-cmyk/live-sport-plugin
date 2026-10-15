# Trellis Player (iPhone / iPad / Mac)

App SwiftUI qui ouvre ton serveur **Trellis** (`https://bastien-trellis.duckdns.org` par défaut)
et permet de lire les vidéos avec **Infuse** comme lecteur externe.

## Fonctionnement

- L'app affiche Trellis dans un navigateur intégré : tu te connectes comme d'habitude,
  la session (cookies) est conservée entre deux lancements.
- Un script injecté dans la page repère les vidéos (`.m3u8`, `.mp4`, `.mkv`…) chargées par
  le lecteur du site, y compris dans les iframes.
- Quand une vidéo démarre, l'app propose : **Ouvrir dans Infuse**, **Lecteur intégré**
  (AVPlayer, avec les cookies de ta session) ou **Continuer dans la page**.
  Le choix par défaut se règle dans ⚙️ → *Lecteur par défaut*.
- Le bouton 🎞 de la barre liste toutes les vidéos détectées (lecture, partage du lien).
- ⚙️ permet aussi de changer l'adresse du serveur et de se déconnecter.

Infuse est ouvert via `infuse://x-callback-url/play?url=<lien encodé>`.

## Installer sur ton iPhone

1. Sur un Mac avec **Xcode 16** ou plus récent, ouvre `TrellisPlayer.xcodeproj`.
2. Clique sur le projet → cible *TrellisPlayer* → **Signing & Capabilities** → choisis ton
   compte Apple dans *Team* (un compte gratuit suffit). Si l'identifiant est refusé, change
   le *Bundle Identifier* (ex. `com.tonnom.trellisplayer`).
3. Branche l'iPhone, sélectionne-le en haut de Xcode, puis ▶︎ (**Run**).
4. Sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → fais confiance à ton
   compte développeur.

Sur un Mac Apple Silicon, tu peux aussi choisir la destination *My Mac (Designed for iPad)*.

## Limites

- **Infuse ne reçoit que l'URL du flux**, sans cookies ni en-têtes. Si Trellis protège ses
  flux par la session (cookie) plutôt que par un jeton dans l'URL, Infuse affichera une
  erreur : utilise alors le *Lecteur intégré*, qui transmet les cookies.
- Pas de version Apple TV : tvOS n'a pas de navigateur intégré. Depuis l'iPhone, Infuse ou
  le lecteur intégré peuvent envoyer la vidéo vers l'Apple TV via AirPlay.
- Avec un compte Apple gratuit, l'app doit être réinstallée depuis Xcode tous les 7 jours.
