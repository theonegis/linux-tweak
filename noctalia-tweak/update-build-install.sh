#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=${NOCTALIA_BUILD_DIR:-"${ROOT_DIR}/build-local"}
INSTALL=true

usage() {
  cat <<'EOF'
Usage: ./update-build-install.sh [--build-only]

  --build-only  Build and test the patched Arch package without installing it.

The script fetches Noctalia's latest main branch, applies the local clipboard
owner-handoff fix, runs the test suite, and builds the same package name used
by ArchLinuxCN: noctalia-git.
EOF
}

case ${1:-} in
  --build-only) INSTALL=false ;;
  -h|--help) usage; exit 0 ;;
  '') ;;
  *) usage >&2; exit 2 ;;
esac

for command in git makepkg meson ninja; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    printf 'error: missing command: %s\n' "${command}" >&2
    printf 'install prerequisites with: sudo pacman -S --needed base-devel git meson ninja nlohmann-json stb wayland-protocols\n' >&2
    exit 1
  fi
done

mkdir -p "${BUILD_DIR}"
cp "${ROOT_DIR}/PKGBUILD" "${BUILD_DIR}/PKGBUILD"
cp "${ROOT_DIR}/0001-fix-deferred-clipboard-orphan-adoption.patch" \
  "${BUILD_DIR}/0001-fix-deferred-clipboard-orphan-adoption.patch"

printf 'Building patched noctalia-git from the latest main branch...\n'
(
  cd "${BUILD_DIR}"
  if [[ "${INSTALL}" == true ]]; then
    makepkg --cleanbuild --syncdeps --force --install
  else
    makepkg --cleanbuild --syncdeps --force
  fi
)

PACKAGE_FILE=$(
  cd "${BUILD_DIR}"
  makepkg --packagelist | head -n 1
)
printf '\nBuilt package: %s\n' "${PACKAGE_FILE}"

if [[ "${INSTALL}" == true ]]; then
  printf 'Installed. Log out and back in (or restart Noctalia) before testing.\n'
fi
