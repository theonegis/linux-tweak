#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=${FCITX5_BUILD_DIR:-"${ROOT_DIR}/build-local"}
INSTALL=true

case ${1:-} in
  --build-only) INSTALL=false ;;
  -h|--help)
    printf 'Usage: %s [--build-only]\n' "$0"
    exit 0
    ;;
  '') ;;
  *) printf 'error: unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

mkdir -p "$BUILD_DIR"
cp "$ROOT_DIR/PKGBUILD" "$BUILD_DIR/PKGBUILD"
cp "$ROOT_DIR/0001-label-keyboard-us-as-ying.patch" "$BUILD_DIR/"

(
  cd "$BUILD_DIR"
  if [[ "$INSTALL" == true ]]; then
    makepkg --cleanbuild --syncdeps --force --install
  else
    makepkg --cleanbuild --syncdeps --force
  fi
)

PACKAGE_FILE=$(cd "$BUILD_DIR" && makepkg --packagelist | head -n 1)
printf '\nBuilt package: %s\n' "$PACKAGE_FILE"

if [[ "$INSTALL" == true ]]; then
  fcitx5 -r -d
  printf 'Installed and restarted Fcitx5. Switch to English once to refresh the tray icon.\n'
fi
