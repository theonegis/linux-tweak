#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly index_url='https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages'
readonly repository_root='https://persistent.oaistatic.com/codex-app-prod/linux/deb'

usage() {
    printf '%s\n' \
        'Usage: ./install.sh [--with-buttons|--without-buttons]' \
        '' \
        '  --with-buttons       Keep the official top-right window buttons (default).' \
        '  --without-buttons    Hide the top-right window buttons.' \
        '  -h, --help           Show this help.'
}

titlebar_buttons='show'
if (( $# > 1 )); then
    usage >&2
    exit 2
fi
if (( $# == 1 )); then
    case "$1" in
        --with-buttons)
            titlebar_buttons='show'
            ;;
        --without-buttons)
            titlebar_buttons='hide'
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
fi
readonly titlebar_buttons

if [[ "$(uname -s)" != 'Linux' || "$(uname -m)" != 'x86_64' ]]; then
    printf 'This installer supports only x86_64 Arch Linux.\n' >&2
    exit 1
fi
if [[ ! -r /etc/arch-release ]]; then
    printf 'This installer is intended for Arch Linux and its derivatives.\n' >&2
    exit 1
fi
if (( EUID == 0 )); then
    printf 'Do not run this script as root; makepkg refuses to build as root.\n' >&2
    exit 1
fi

available_kib="$(df -Pk "${script_dir}" | awk 'NR == 2 { print $4 }')"
required_kib=$((5 * 1024 * 1024))
if [[ ! "${available_kib}" =~ ^[0-9]+$ ]] || (( available_kib < required_kib )); then
    printf 'At least 5 GiB of free workspace disk space is required.\n' >&2
    exit 1
fi
if pgrep -f '/usr/lib/chatgpt/ChatGPT|/opt/codex-desktop/(electron|start\.sh)' >/dev/null 2>&1; then
    printf '%s\n' \
        'ChatGPT/Codex Desktop is running.' \
        'Fully quit it (including any tray process), then run this installer again.' >&2
    exit 1
fi

printf 'Installing Arch build prerequisites...\n'
sudo pacman -S --needed base-devel curl libarchive xz asar

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/chatgpt-arch-installer.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT

printf 'Reading the official OpenAI Debian repository index...\n'
curl --fail --location --retry 3 --silent --show-error \
    --output "${work_dir}/Packages" "${index_url}"

field() {
    local name="$1"
    awk -F ': ' -v key="${name}" '$1 == key { print $2; exit }' "${work_dir}/Packages"
}

version="$(field Version)"
filename="$(field Filename)"
expected_size="$(field Size)"
expected_sha256="$(field SHA256)"
package="$(field Package)"
architecture="$(field Architecture)"
maintainer="$(field Maintainer)"

[[ "${package}" == 'chatgpt' ]] || { printf 'Unexpected package: %s\n' "${package}" >&2; exit 1; }
[[ "${architecture}" == 'amd64' ]] || { printf 'Unexpected architecture: %s\n' "${architecture}" >&2; exit 1; }
[[ "${maintainer}" == OpenAI* ]] || { printf 'Unexpected maintainer: %s\n' "${maintainer}" >&2; exit 1; }
[[ "${version}" =~ ^[0-9]+([.][0-9]+)+$ ]] || { printf 'Unsafe version: %s\n' "${version}" >&2; exit 1; }
[[ "${filename}" =~ ^pool/main/c/chatgpt/chatgpt_[0-9.]+_amd64[.]deb$ ]] || {
    printf 'Unsafe repository filename: %s\n' "${filename}" >&2
    exit 1
}
[[ "${expected_size}" =~ ^[0-9]+$ ]] || { printf 'Invalid package size.\n' >&2; exit 1; }
[[ "${expected_sha256}" =~ ^[0-9a-f]{64}$ ]] || { printf 'Invalid SHA-256.\n' >&2; exit 1; }

download_part="${script_dir}/.download-${version}.part"
deb_file="${script_dir}/chatgpt_amd64.deb"
download_url="${repository_root}/${filename}"

if [[ -r "${deb_file}" ]] && \
   [[ "$(stat -c '%s' "${deb_file}")" == "${expected_size}" ]] && \
   [[ "$(sha256sum "${deb_file}" | awk '{print $1}')" == "${expected_sha256}" ]]; then
    printf 'Using the already verified ChatGPT %s download.\n' "${version}"
else
    printf 'Downloading official ChatGPT %s (%s bytes)...\n' "${version}" "${expected_size}"
    curl --fail --location --retry 3 --continue-at - \
        --output "${download_part}" "${download_url}"

    actual_size="$(stat -c '%s' "${download_part}")"
    actual_sha256="$(sha256sum "${download_part}" | awk '{print $1}')"
    if [[ "${actual_size}" != "${expected_size}" || "${actual_sha256}" != "${expected_sha256}" ]]; then
        printf '%s\n' 'Downloaded package failed the official size/SHA-256 check.' >&2
        exit 1
    fi
    mv -f "${download_part}" "${deb_file}"
fi

printf 'Building and installing the pacman package...\n'
cd "${script_dir}"
CHATGPT_TITLEBAR_BUTTONS="${titlebar_buttons}" \
    makepkg --syncdeps --install --clean --cleanbuild --force

if [[ "${titlebar_buttons}" == 'hide' ]]; then
    printf '\nInstalled ChatGPT %s without the top-right title-bar buttons.\n' "${version}"
else
    printf '\nInstalled ChatGPT %s with the official top-right title-bar buttons.\n' "${version}"
fi
printf 'Launch it from the application menu or run: chatgpt\n'
