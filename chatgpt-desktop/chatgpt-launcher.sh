#!/usr/bin/env bash
set -euo pipefail

user_flags=()
ozone_flags=()

config_home="${XDG_CONFIG_HOME:-${HOME:-}/.config}"
flags_file="${config_home}/chatgpt-flags.conf"

if [[ -r "${flags_file}" ]]; then
    while IFS= read -r flag_line || [[ -n "${flag_line}" ]]; do
        flag_line="${flag_line%%#*}"
        read -r -a flag_parts <<<"${flag_line}"
        user_flags+=("${flag_parts[@]}")
    done < "${flags_file}"
fi

# Electron may otherwise choose XWayland, which looks blurry with fractional
# scaling. An explicit user/command-line platform flag always wins.
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    ozone_flags=(--ozone-platform=wayland)
fi

for flag in "${user_flags[@]}" "$@"; do
    case "${flag}" in
        --ozone-platform=*|--ozone-platform-hint=*) ozone_flags=() ;;
    esac
done

exec /usr/lib/chatgpt/ChatGPT "${ozone_flags[@]}" "${user_flags[@]}" "$@"

