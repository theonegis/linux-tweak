#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=${NOCTALIA_GREETER_BUILD_DIR:-"${ROOT_DIR}/build-local"}
INSTALL=true

usage() {
  cat <<'EOF'
Usage: ./update-build-install.sh [--build-only]

  --build-only  Build the patched Arch package but do not install it.

The script fetches the latest noctalia-greeter main branch, applies the local
shutdown, quiet-console and VT handoff patches, and builds the same package
name used by ArchLinuxCN: noctalia-greeter-git.
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
    printf 'install prerequisites with: sudo pacman -S --needed base-devel git meson ninja wayland-protocols\n' >&2
    exit 1
  fi
done

mkdir -p "${BUILD_DIR}"
cp "${ROOT_DIR}/PKGBUILD" "${BUILD_DIR}/PKGBUILD"
cp "${ROOT_DIR}/noctalia-greeter-git.install" \
  "${BUILD_DIR}/noctalia-greeter-git.install"
cp "${ROOT_DIR}/0001-clean-up-keyboard-listeners-before-shutdown.patch" \
  "${BUILD_DIR}/0001-clean-up-keyboard-listeners-before-shutdown.patch"
cp "${ROOT_DIR}/0002-clear-vt-before-starting-greeter.patch" \
  "${BUILD_DIR}/0002-clear-vt-before-starting-greeter.patch"
cp "${ROOT_DIR}/0003-clear-vt-after-compositor-shutdown.patch" \
  "${BUILD_DIR}/0003-clear-vt-after-compositor-shutdown.patch"
cp "${ROOT_DIR}/0004-silence-routine-console-output.patch" \
  "${BUILD_DIR}/0004-silence-routine-console-output.patch"

printf 'Building patched noctalia-greeter-git from the latest main branch...\n'
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
  printf 'Installed. Reboot to test the greeter handoff and shutdown cleanup.\n'
fi
