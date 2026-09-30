#!/usr/bin/env bash
# Prepare une release GitHub a partir de la version de pubspec.yaml (seule
# source : version affichee dans l'app, versionName/versionCode Android,
# tag v<version>, nom de l'APK et titre de la release).
#
# Avant : monter `version:` dans pubspec.yaml et ajouter la section
# "## <version>" au CHANGELOG, puis commiter.
#
# Usage: ./scripts/release.sh
#
# Construit l'APK signe, pousse main et cree la release en BROUILLON (notes
# = section du CHANGELOG + installation + avertissement). Le tag n'est cree
# qu'a la publication du brouillon depuis GitHub, apres relecture.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { echo "Erreur : $*" >&2; exit 1; }

version=$(sed -n 's/^version: *\([0-9][0-9.]*\)+[0-9]*$/\1/p' pubspec.yaml)
[[ -n "$version" ]] || die "version illisible dans pubspec.yaml (attendu : X.Y.Z+N)"
tag="v$version"
apk="MyAuto-Pilot-$version.apk"

[[ "$(git branch --show-current)" == main ]] || die "a lancer depuis main"
[[ -z "$(git status --porcelain)" ]] || die "modifications non commitees"
git fetch --quiet --tags origin
! git rev-parse -q --verify "refs/tags/$tag" > /dev/null || die "le tag $tag existe deja"
! gh release view "$tag" > /dev/null 2>&1 || die "une release $tag existe deja"
[[ -f android/key.properties ]] || die "android/key.properties absent : l'APK serait signe avec la cle de debug"

notes=$(awk -v v="## $version" '$0 == v {on = 1; next} on && /^## / {exit} on' CHANGELOG.md)
[[ -n "${notes//[[:space:]]/}" ]] || die "pas de section \"## $version\" dans CHANGELOG.md"

echo "Release $tag : build de l'APK signe..."
./scripts/flutter.sh build apk --release
out=build/release
mkdir -p "$out"
cp build/app/outputs/flutter-apk/app-release.apk "$out/$apk"
(cd "$out" && sha256sum "$apk" > "$apk.sha256")
sha=$(cut -d' ' -f1 "$out/$apk.sha256")

cat > "$out/notes.md" <<EOF
## Nouveautés
$notes

## Installation

Téléchargez \`$apk\` ci-dessous et installez-le (Android 7 ou plus récent), par-dessus une version précédente le cas échéant : même signature, vos réglages sont conservés. **Ouvrez l'application une fois après la mise à jour** pour reprogrammer les envois du pilotage. Pour les mises à jour, vous pouvez suivre ce dépôt avec [Obtainium](https://github.com/ImranR98/Obtainium).

Empreinte SHA-256 de l'APK :
\`\`\`
$sha
\`\`\`

## Avertissement

Application **non officielle**, ni affiliée à Renault ni approuvée par Renault. Elle utilise l'accès non documenté de MyRenault, que Renault peut modifier ou couper, et **modifie les réglages de charge** de votre véhicule. Fournie sans aucune garantie (GPL-3.0) : à utiliser à vos risques, en gardant le mode sécurisé tant que vous n'avez pas confiance.
EOF

echo
echo "APK : $out/$apk"
echo "SHA-256 : $sha"
echo "Notes : $out/notes.md"
read -r -p "Pousser main et creer la release $tag en brouillon ? [o/N] " answer
[[ "$answer" == [oO] ]] || { echo "Abandon (rien n'a ete pousse)."; exit 0; }

git push origin main
gh release create "$tag" --draft --target main \
  --title "MyAuto Pilot $version (bêta)" \
  --notes-file "$out/notes.md" \
  "$out/$apk" "$out/$apk.sha256"
echo "Brouillon cree : relire puis publier depuis GitHub (cree le tag $tag)."
