#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=${NIRI_REPO_DIR:-"${ROOT_DIR}/niri-src"}
BUILD_DIR=${NIRI_BUILD_DIR:-"${ROOT_DIR}/build-local"}
REMOTE=${NIRI_REMOTE:-https://github.com/niri-wm/niri.git}
INSTALL=true

usage() {
  cat <<'EOF'
Usage: ./update-build-install.sh [--build-only]

  --build-only  Build the Arch package but do not install it.

The managed niri-src checkout is disposable. Every run discards tracked
changes in that checkout before switching to the newest stable release tag.
Keep your style changes in apply-niri-acrylic.py, not inside niri-src.

Set NIRI_TAG=v26.04 to build a specific stable release instead of the newest.
EOF
}

case ${1:-} in
  --build-only) INSTALL=false ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; exit 2 ;;
esac

for command in git python3 makepkg rustc cargo; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    printf 'error: missing command: %s\n' "${command}" >&2
    printf 'install prerequisites with: sudo pacman -S --needed base-devel git rust clang inter-font\n' >&2
    exit 1
  fi
done

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  printf 'Cloning niri into %s\n' "${REPO_DIR}"
  git clone --filter=blob:none "${REMOTE}" "${REPO_DIR}"
fi

printf 'Fetching upstream tags...\n'
git -C "${REPO_DIR}" fetch --tags --prune origin

if [[ -n "${NIRI_TAG:-}" ]]; then
  LATEST_TAG=${NIRI_TAG}
else
  LATEST_TAG=$(git -C "${REPO_DIR}" for-each-ref \
    --count=1 \
    --sort=-version:refname \
    --format='%(refname:short)' \
    'refs/tags/v[0-9]*')
fi
if [[ -z "${LATEST_TAG}" ]]; then
  printf 'error: no stable niri release tag was found\n' >&2
  exit 1
fi
if ! git -C "${REPO_DIR}" rev-parse --verify --quiet "refs/tags/${LATEST_TAG}^{commit}" >/dev/null; then
  printf 'error: niri tag does not exist: %s\n' "${LATEST_TAG}" >&2
  exit 1
fi

printf 'Preparing clean source at %s...\n' "${LATEST_TAG}"
# This checkout is owned by this workflow. The force switch deliberately
# removes the style changes left by the preceding build.
git -C "${REPO_DIR}" switch --detach --force "${LATEST_TAG}"
git -C "${REPO_DIR}" reset --hard "${LATEST_TAG}"

python3 "${ROOT_DIR}/apply-niri-acrylic.py" "${REPO_DIR}"
git -C "${REPO_DIR}" diff --check

PKGVER=${LATEST_TAG#v}
COMMIT=$(git -C "${REPO_DIR}" rev-parse --short=7 HEAD)

mkdir -p "${BUILD_DIR}"
cp "${ROOT_DIR}/PKGBUILD.local" "${BUILD_DIR}/PKGBUILD"

export NIRI_SRC="${REPO_DIR}"
export NIRI_PKGVER="${PKGVER}"
export NIRI_COMMIT="${COMMIT}"

printf 'Building niri Mica overlays %s (%s)...\n' "${PKGVER}" "${COMMIT}"
(
  cd "${BUILD_DIR}"
  makepkg --syncdeps --force
)

PACKAGE_FILE=$(
  cd "${BUILD_DIR}"
  makepkg --packagelist | head -n 1
)

if [[ "${INSTALL}" == true ]]; then
  printf 'Installing %s...\n' "${PACKAGE_FILE}"
  sudo pacman -U "${PACKAGE_FILE}"
  printf '\nInstalled. Log out and log back in to start the new niri binary.\n'
else
  printf '\nBuilt package: %s\n' "${PACKAGE_FILE}"
fi
