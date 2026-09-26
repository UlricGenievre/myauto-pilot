#!/usr/bin/env bash
# Wrapper pour lancer les commandes flutter/dart dans le conteneur Docker,
# sans installer le SDK Flutter sur la machine hote.
#
# Usage:
#   ./scripts/flutter.sh pub get
#   ./scripts/flutter.sh analyze
#   ./scripts/flutter.sh test
#   ./scripts/flutter.sh devices
#   ./scripts/flutter.sh run -d <device-id>
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Pour run/build/test, injecte automatiquement les cles API depuis .env
# (voir .env.example) via --dart-define-from-file. Ce flag n'est pas
# reconnu par les autres sous-commandes (analyze, pub, devices...), donc on
# ne l'ajoute que la ou il s'applique.
EXTRA_ARGS=()
case "${1:-}" in
  run|build|test)
    if [[ -f .env ]]; then
      EXTRA_ARGS=(--dart-define-from-file=.env)
    fi
    ;;
esac

docker compose run --rm flutter flutter "$@" "${EXTRA_ARGS[@]}"
