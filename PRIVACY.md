# Politique de confidentialité — MyAuto Pilot

*English version below.*

Dernière mise à jour : 26 septembre 2026.

MyAuto Pilot est une application Android indépendante, sans serveur ni
compte propre. Cette page décrit les données qu'elle manipule et avec qui
elle communique.

## Données traitées

| Donnée | Usage | Où elle se trouve |
|---|---|---|
| Adresse e-mail et mot de passe MyRenault | Ouvrir la session auprès de Renault, une seule fois à la connexion | **Jamais enregistrés** : transmis directement aux serveurs Renault |
| Jetons de session Renault, identifiants de compte Renault | Rester connecté, accéder aux données du véhicule | Sur le téléphone, chiffrés (stockage sécurisé Android) |
| Données du véhicule : VIN, modèle, batterie, autonomie, position, état de charge et de climatisation, réglages de charge | Affichage et pilotage de la charge | Lues auprès de Renault à la demande ; seuls le VIN et le code modèle du véhicule piloté sont conservés, sur le téléphone |
| Vos réglages : plages d'heures creuses, objectifs de charge, historique des derniers envois | Calcul et envoi des plages de charge | Sur le téléphone uniquement |
| Pays de votre compte et clés d'accès aux services Renault | Connexion aux serveurs Renault de votre pays | Sur le téléphone, chiffrés |

L'application ne contient **aucune statistique d'usage, aucun outil de suivi,
aucune publicité, aucun rapport de plantage envoyé**. Le développeur n'a accès
à aucune de ces données.

## Communications

L'application communique uniquement avec :

- les **serveurs Renault** (Gigya/SAP pour la connexion, Kamereon pour les
  données et réglages du véhicule), avec vos identifiants de session ;
  voir la politique de confidentialité de Renault pour leur traitement ;
- **GitHub** (`raw.githubusercontent.com`), pour télécharger les clés
  d'accès aux services Renault publiées par le projet
  [renault-api](https://github.com/hacf-fr/renault-api) : aucune donnée
  personnelle n'est envoyée ;
- **OpenStreetMap** (`tile.openstreetmap.org`), pour les fonds de carte de
  l'onglet Localisation : comme pour tout site web, votre adresse IP et la
  zone de carte affichée sont visibles de ce service
  ([politique d'OpenStreetMap](https://osmfoundation.org/wiki/Privacy_Policy)).

Toutes ces communications sont chiffrées (HTTPS).

## Autorisations Android

- **Internet** : communications ci-dessus.
- **Notifications** : confirmation et résultat des envois de plages, rappel
  du soir.
- **Alarmes et rappels** : envoyer chaque plage à l'heure prévue.
- **Démarrage automatique** : reprogrammer les envois après un redémarrage
  du téléphone.

## Conservation et suppression

Les données restent sur votre téléphone tant que l'application est
installée. **Se déconnecter** efface la session Renault ; **désinstaller**
l'application (ou effacer ses données dans les réglages Android) supprime
tout. L'application ne crée aucun compte : votre compte MyRenault se gère
auprès de Renault.

## Enfants

L'application s'adresse aux titulaires d'un compte MyRenault et n'est pas
destinée aux enfants.

## Contact

Questions et signalements :
[issues du projet](https://github.com/UlricGenievre/myauto-pilot/issues).
Toute modification de cette politique est publiée sur cette page.

---

# Privacy policy — MyAuto Pilot

Last updated: September 26, 2026.

MyAuto Pilot is an independent Android app with no server and no account of
its own.

**Data handled**

- Your **MyRenault e-mail and password** are sent directly to Renault's
  servers once, to sign in, and are **never stored**.
- Renault **session tokens and account identifiers**, your **account
  country** and **Renault service keys** are stored encrypted on the phone.
- **Vehicle data** (VIN, model, battery, range, location, charging and
  climate status, charging settings) is read from Renault on demand; only
  the VIN and model code of the piloted vehicle are kept, on the phone.
- Your **settings** (off-peak windows, charging targets, recent send
  history) stay on the phone.

There are **no analytics, trackers, ads or crash reports**. The developer has
no access to any of this data.

**Network**: the app only talks to **Renault** servers (sign-in, vehicle data
and settings), **GitHub** (`raw.githubusercontent.com`, to download Renault
service keys published by the [renault-api](https://github.com/hacf-fr/renault-api)
project; no personal data sent) and **OpenStreetMap** (`tile.openstreetmap.org`,
map tiles; your IP address and the displayed map area are visible to it).
All traffic uses HTTPS.

**Permissions**: Internet, notifications (send confirmations and results),
alarms & reminders (sending at the exact time), run at startup (rescheduling
after a reboot).

**Retention and deletion**: data stays on the phone while the app is
installed. Signing out deletes the Renault session; uninstalling the app (or
clearing its data) deletes everything. The app creates no account.

**Children**: not intended for children.

**Contact**: [project issues](https://github.com/UlricGenievre/myauto-pilot/issues).
Changes to this policy are published on this page.
