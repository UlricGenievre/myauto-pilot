# Developpement

## Architecture

```
lib/
  background/        Reveils Android + notifications du pilotage (version web vide)
  core/
    api/             Clients Gigya (auth) et Kamereon, cles Renault (renault-api)
    charge_plan/     Calcul des plages (ChargePlanner) et pilotage (ChargePilot)
    models/          Vehicule, batterie, reglages de charge, parametrage...
    storage/         Stockage securise (session, cles, parametrage, etat du pilote)
    widgets/         Composants d'interface reutilisables
  features/
    about/           Avertissement du premier lancement, "A propos"
    auth/            Connexion (choix du pays), cles Renault
    charge_plan/     Onglet Pilotage et ecran Reglages
    location/        Carte
    remote_actions/  Actions a distance
    schedule/        Reglages relus sur le vehicule
    vehicle_status/  Batterie, resume du pilotage
```

Etat gere avec Riverpod, appels HTTP avec Dio, pas de generation de code
(pas de `build_runner`) pour garder le workflow simple avec Docker. La
logique de pilotage (`core/charge_plan/`) est en Dart pur et couverte par
les tests (`./scripts/flutter.sh test`).

## Environnement de dev : tout dans Docker, minimum sur WSL

Objectif : n'installer sur WSL que ce qui doit obligatoirement tourner sur
l'hote (le serveur `adb`, qui doit voir le telephone en USB). Tout le reste
(SDK Flutter, build, tests) tourne dans un conteneur Docker.

### 1. Prerequis Windows (une fois)

1. Installer [usbipd-win](https://github.com/dorssel/usbipd-win) :
   `winget install usbipd`
2. Brancher le telephone Android, activer le **debogage USB** (options
   developpeur)
3. Partager le peripherique :
   ```powershell
   usbipd list
   usbipd bind --busid <BUSID>
   usbipd attach --wsl --busid <BUSID>
   ```

### 2. Prerequis WSL

```bash
sudo apt install -y adb linux-tools-generic hwdata
sudo update-alternatives --install /usr/local/bin/usbip usbip /usr/lib/linux-tools/*-generic/usbip 20
```

(Le paquet `usbip` n'existe pas directement dans les depots WSL2 puisque le
kernel est un build specifique Microsoft : `linux-tools-generic` fournit un
binaire `usbip` compatible malgre la difference de version.)

Verifier que le telephone est vu :

```bash
adb devices -l
```

(Accepter la popup d'autorisation de debogage USB sur le telephone la
premiere fois.)

### 3. Commandes de dev (via Docker, aucune install Flutter native)

```bash
./scripts/flutter.sh pub get       # installer les dependances
./scripts/flutter.sh analyze       # analyse statique
./scripts/flutter.sh test          # tests
./scripts/flutter.sh devices       # doit lister le telephone (adb via reseau host)
./scripts/flutter.sh run -d <device-id>
./scripts/flutter.sh run -d web-server --web-port=8090 --web-hostname=0.0.0.0 # Pour usage depuis navigateur
```

L'image est construite localement (`Dockerfile`, au premier lancement ou
apres `docker compose build`) : SDK Flutter a version fixe
(`FLUTTER_VERSION`, somme SHA-256 verifiee), NDK et plateformes Android
prechargees. Pour monter de version Flutter, modifier `FLUTTER_VERSION` et
`FLUTTER_SHA256` puis reconstruire.

Le conteneur tourne avec `network_mode: host` : le client `adb` embarque
dans l'image Flutter parle directement au serveur `adb` de l'hote sur
`127.0.0.1:5037`, qui lui gere le telephone partage via usbipd. Ce mode
suppose un Docker Engine natif sous WSL2 (ex: paquet `docker.io`/`docker-ce`
installe directement dans la distro) ; avec Docker Desktop et son backend
WSL2, `network_mode: host` peut se comporter differemment et necessiter un
reglage reseau specifique.

Pour construire l'APK de release :

```bash
./scripts/flutter.sh build apk --release
```

Signature : si `android/key.properties` (et le keystore qu'il designe)
existe, l'APK est signe avec cette cle ; sinon avec la cle de debug. Ces
fichiers ne sont jamais versionnes.

Pour Google Play, construire un bundle (AAB) :

```bash
./scripts/flutter.sh build appbundle --release
# -> build/app/outputs/bundle/release/app-release.aab
```

Il est signe avec la cle d'upload decrite par `android/upload.properties`
(meme format que `key.properties`) si ce fichier existe, sinon comme l'APK.
Google Play re-signe les bundles avec la cle de l'app, la meme que celle des
APK publies sur GitHub : un utilisateur peut passer d'un canal a l'autre
sans reinstaller.
