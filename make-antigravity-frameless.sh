#!/usr/bin/env bash
set -euo pipefail

# Reapply the frameless Antigravity titlebar patch after updating/reinstalling.
# Removes top-right window control buttons (minimize, maximize, close) on Linux.

readonly package_name="${ANTIGRAVITY_PACKAGE:-antigravity}"
readonly app_root="${ANTIGRAVITY_ROOT:-/opt/Antigravity}"
readonly asar_file="$app_root/resources/app.asar"
readonly state_root="${XDG_STATE_HOME:-$HOME/.local/state}/antigravity-frameless-titlebar"
readonly backup_dir="$state_root/backup"

mode="patch"
case "${1:-}" in
    "") ;;
    --dry-run) mode="dry-run" ;;
    --restore) mode="restore" ;;
    -h|--help)
        printf '%s\n' \
            "Usage: $(basename "$0") [--dry-run|--restore]" \
            "" \
            "  no option   inspect, patch, validate, back up, and install" \
            "  --dry-run   perform every validation without installing" \
            "  --restore   restore the backup for the currently installed version" \
            "" \
            "Environment overrides:" \
            "  ANTIGRAVITY_ROOT     installed app directory (default: $app_root)" \
            "  ANTIGRAVITY_PACKAGE  pacman package name (default: $package_name)"
        exit 0
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        exit 2
        ;;
esac

for command_name in asar node sha256sum sudo; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command is missing: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ ! -r "$asar_file" ]]; then
    printf 'The installed Antigravity application archive was not found at %s\n' "$asar_file" >&2
    exit 1
fi

package_version=""
if command -v pacman >/dev/null 2>&1; then
    package_version="$(pacman -Q "$package_name" 2>/dev/null | awk '{print $2}' || true)"
fi

antigravity_is_running() {
    pgrep -f '/opt/Antigravity/antigravity|/opt/Antigravity/resources/app\.asar' >/dev/null 2>&1
}

restore_backup() {
    if antigravity_is_running; then
        printf 'Antigravity is still running. Fully quit it before restoring.\n' >&2
        exit 1
    fi
    if [[ ! -r "$backup_dir/app.asar" ]]; then
        printf 'No backup exists in %s\n' "$backup_dir" >&2
        exit 1
    fi

    if [[ -n "$package_version" && -r "$backup_dir/package-version" ]]; then
        backup_version="$(<"$backup_dir/package-version")"
        if [[ "$backup_version" != "$package_version" ]]; then
            printf 'Backup version (%s) does not match installed package version (%s); refusing to restore.\n' \
                "$backup_version" "$package_version" >&2
            exit 1
        fi
    fi

    sudo -v
    sudo install -o root -g root -m 0644 "$backup_dir/app.asar" "$asar_file"
    printf 'Restored original app.asar from backup.\n'
}

if [[ "$mode" == "restore" ]]; then
    restore_backup
    exit 0
fi

if [[ "$mode" == "patch" ]] && antigravity_is_running; then
    printf 'Antigravity is currently running. Please close Antigravity and rerun this script.\n' >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/antigravity-frameless.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

printf 'Inspecting Antigravity archive at %s...\n' "$asar_file"

printf 'Extracting app.asar...\n'
asar extract "$asar_file" "$work_dir/app"

node - "$work_dir/app" "$work_dir/patch-status.json" <<'NODE'
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const [appDir, statusFile] = process.argv.slice(2);
const utilsFile = path.join(appDir, "dist", "utils.js");

if (!fs.existsSync(utilsFile)) {
  throw new Error(`Required file dist/utils.js not found at ${utilsFile}`);
}

let source = fs.readFileSync(utilsFile, "utf8");

// Pattern matching titleBarOverlay option in createWindow()
const overlayPattern = /titleBarOverlay:\s*isMacOS\(\)\s*\?\s*false\s*:\s*\{[\s\S]*?\},?/g;

let alreadyPatched = false;
let changed = false;

if (overlayPattern.test(source)) {
  const patched = source.replace(overlayPattern, "titleBarOverlay: false,");
  fs.writeFileSync(utilsFile, patched);
  changed = true;
} else if (source.includes("titleBarOverlay: false")) {
  alreadyPatched = true;
} else {
  throw new Error("Could not find titleBarOverlay pattern in dist/utils.js. The app structure may have changed.");
}

const status = { alreadyPatched, changed };
fs.writeFileSync(statusFile, JSON.stringify(status, null, 2));
console.log(JSON.stringify(status, null, 2));
NODE

already_patched="$(node -p 'require(process.argv[1]).alreadyPatched' "$work_dir/patch-status.json")"
changed="$(node -p 'require(process.argv[1]).changed' "$work_dir/patch-status.json")"

if [[ "$already_patched" == "true" ]]; then
    printf 'Antigravity is already frameless (titleBarOverlay is false); no change necessary.\n'
    exit 0
fi

if [[ "$changed" != "true" ]]; then
    printf 'Patch failed to apply.\n' >&2
    exit 1
fi

printf 'Repacking application archive...\n'
asar pack "$work_dir/app" "$work_dir/app.asar" --unpack '**/*.node'

if [[ "$mode" == "dry-run" ]]; then
    printf 'Dry run passed. Antigravity can be patched safely; no installed files were modified.\n'
    exit 0
fi

printf 'Creating a backup...\n'
mkdir -p "$state_root"
backup_new="$state_root/backup.new.$$"
rm -rf -- "$backup_new"
mkdir -p "$backup_new"
cp --reflink=auto "$asar_file" "$backup_new/app.asar"
if [[ -n "$package_version" ]]; then
    printf '%s\n' "$package_version" > "$backup_new/package-version"
fi
rm -rf -- "$backup_dir"
mv "$backup_new" "$backup_dir"

printf 'Installing patched app.asar...\n'
sudo -v
sudo install -o root -g root -m 0644 "$work_dir/app.asar" "$asar_file"

installed_hash="$(sha256sum "$asar_file" | awk '{print $1}')"
patched_hash="$(sha256sum "$work_dir/app.asar" | awk '{print $1}')"
if [[ "$installed_hash" != "$patched_hash" ]]; then
    printf 'Installed ASAR failed checksum verification; restoring backup immediately...\n' >&2
    sudo install -o root -g root -m 0644 "$backup_dir/app.asar" "$asar_file"
    exit 1
fi

printf '\nFrameless patch successfully installed for Antigravity.\n'
printf 'Rollback command: %s --restore\n' "$0"
