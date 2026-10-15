# Trellis Player (iPhone / iPad / Mac)

Client SwiftUI pour le serveur **Treillis** (API Jellyfin), avec la page d'accueil de
**Strand** et **Infuse** comme lecteur externe.

## Fonctionnement

- **Connexion** : adresse du serveur (`https://bastien-trellis.duckdns.org` par défaut),
  nom d'utilisateur et mot de passe — les mêmes que dans Strand. Le jeton est gardé dans le
  trousseau iOS.
- **Accueil** : reproduit l'export Strand `TrellisPlayer/StrandHome.json` (sections, tuiles,
  images de couverture) :
  - *Reprendre la lecture* (`continueWatching`) ;
  - rangées de tuiles (`collections_row`) : une tuile ouvre la grille de toutes ses
    collections Treillis (`mediaServer`) ;
  - *Catégories favorites* / *Radio* : chaînes TV en direct favorites et radios.
- **Fiche** : film/épisode (bouton Lecture + choix de la source quand il y en a plusieurs),
  série (saisons et épisodes), collection (grille).
- **Recherche** dans tout le serveur.
- **Réglages** : compte, lecteur par défaut, import d'un nouvel export Strand (.json).

À la lecture, l'app demande les sources au serveur (`/Items/{id}/PlaybackInfo`) puis ouvre :
- **Infuse** avec le fichier original : `infuse://x-callback-url/play?url=<…/Videos/{id}/stream?static=true&api_key=…>` ;
- ou le **lecteur intégré** avec la version HLS (`master.m3u8`).

## Installer sur ton iPhone

1. Sur un Mac avec **Xcode 16** ou plus récent, ouvre `TrellisPlayer.xcodeproj`.
2. Cible *TrellisPlayer* → **Signing & Capabilities** → choisis ton compte Apple dans *Team*.
3. Branche l'iPhone, sélectionne-le en haut de Xcode, puis ▶︎ (**Run**).
4. Sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → fais confiance à ton
   compte développeur.

## Limites

- Les tuiles construites sur **Trakt**, **TMDB Discover** ou **MDBList** (Watchlist, une partie
  des Genres, Acteurs, Réalisateurs et Collections) ne sont pas encore prises en charge :
  elles s'affichent mais restent vides.
- Avec un compte Apple gratuit, l'app doit être réinstallée depuis Xcode tous les 7 jours.
