#!/usr/bin/env bash
set -euo pipefail

# Reapply the frameless Codex titlebar patch after a codex-desktop-linux update.
# The patcher is deliberately conservative: unknown upstream layouts abort
# before any installed file is changed.

readonly app_root="${CODEX_DESKTOP_ROOT:-/opt/codex-desktop}"
readonly asar_file="$app_root/resources/app.asar"
readonly assets_root="$app_root/content/webview/assets"
readonly state_root="${XDG_STATE_HOME:-$HOME/.local/state}/codex-frameless-titlebar"
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
            "  --restore   restore the backup for the currently installed version"
        exit 0
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        exit 2
        ;;
esac

for command_name in asar node rg pacman sha256sum sudo; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command is missing: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ ! -r "$asar_file" || ! -d "$assets_root" ]]; then
    printf 'Codex installation was not found below %s\n' "$app_root" >&2
    exit 1
fi

package_version="$(pacman -Q codex-desktop-linux 2>/dev/null | awk '{print $2}')"
if [[ -z "$package_version" ]]; then
    printf 'The pacman package codex-desktop-linux is not installed.\n' >&2
    exit 1
fi

codex_is_running() {
    pgrep -f '/opt/codex-desktop/(electron|start\.sh)|/opt/codex-desktop/resources/app\.asar' >/dev/null 2>&1
}

restore_backup() {
    if codex_is_running; then
        printf 'Codex is still running. Fully quit it, including its tray process.\n' >&2
        exit 1
    fi
    if [[ ! -r "$backup_dir/app.asar" || ! -r "$backup_dir/package-version" || ! -r "$backup_dir/assets.list" ]]; then
        printf 'No complete backup exists in %s\n' "$backup_dir" >&2
        exit 1
    fi

    backup_version="$(<"$backup_dir/package-version")"
    if [[ "$backup_version" != "$package_version" ]]; then
        printf 'Backup version %s does not match installed version %s; refusing to restore.\n' \
            "$backup_version" "$package_version" >&2
        exit 1
    fi

    sudo -v
    sudo install -o root -g root -m 0644 "$backup_dir/app.asar" "$asar_file"
    while IFS= read -r relative_path; do
        [[ -n "$relative_path" ]] || continue
        if [[ "$relative_path" == /* || "$relative_path" == *..* ]]; then
            printf 'Unsafe path in backup manifest: %s\n' "$relative_path" >&2
            exit 1
        fi
        sudo install -o root -g root -m 0644 \
            "$backup_dir/assets/$relative_path" "$assets_root/$relative_path"
    done < "$backup_dir/assets.list"
    printf 'Restored the original files for codex-desktop-linux %s.\n' "$package_version"
}

if [[ "$mode" == "restore" ]]; then
    restore_backup
    exit 0
fi

if [[ "$mode" == "patch" ]] && codex_is_running; then
    printf 'Codex is still running. Fully quit it, including its tray process, then rerun this script.\n' >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-frameless.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

printf 'Inspecting codex-desktop-linux %s...\n' "$package_version"

# Repacking must preserve every external ASAR file. The current Linux package
# unpacks native Node modules only. Abort if a future package adds another kind.
asar list -i "$asar_file" > "$work_dir/original-asar-list"
if awk '/^unpack/ && $NF !~ /\.node$/ { found=1 } END { exit found ? 0 : 1 }' \
    "$work_dir/original-asar-list"; then
    printf 'The updated ASAR contains an unknown non-.node unpacked file.\n' >&2
    printf 'No installed file was changed; the script needs to be adapted for this release.\n' >&2
    exit 1
fi

printf 'Extracting the application archive...\n'
asar extract "$asar_file" "$work_dir/app"

rg -l -0 \
    'showApplicationMenu|applicationMenu:Object\.freeze|includes\(`linux`\).*applicationMenu' \
    "$assets_root" -g '*.js' > "$work_dir/webview-candidates" || true

mkdir -p "$work_dir/patched-assets"

node - "$work_dir/app" "$assets_root" "$work_dir/webview-candidates" \
    "$work_dir/patched-assets" "$work_dir/assets.list" "$work_dir/patch-status.json" <<'NODE'
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const [appDir, assetsRoot, candidatesFile, stagedAssetsRoot, manifestFile, statusFile] = process.argv.slice(2);

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function patchMainBundle(currentSource) {
  let source = currentSource;

  // Current combined quickChat/primary branch: Linux and Windows share one
  // object, with a Linux-specific overlay helper selected inside it.
  source = source.replace(
    /([A-Za-z_$][\w$]*)===`win32`\|\|\1===`linux`\?\{titleBarStyle:`hidden`,titleBarOverlay:\1===`linux`\?codexLinuxTitleBarOverlay\(([A-Za-z_$][\w$]*)\):([A-Za-z_$][\w$]*)\(\2\),\.\.\.([A-Za-z_$][\w$]*)===`quickChat`\?\{resizable:!0\}:\{\}\}:/g,
    (_match, platform, zoom, windowsOverlay, appearance) => {
      const quickChat = `...${appearance}===\`quickChat\`?{resizable:!0}:{}`;
      return `${platform}===\`win32\`?{titleBarStyle:\`hidden\`,titleBarOverlay:${windowsOverlay}(${zoom}),${quickChat}}:${platform}===\`linux\`?{titleBarStyle:\`hidden\`,${quickChat}}:`;
    },
  );

  // Older combined branch where both platforms called the same helper.
  source = source.replace(
    /([A-Za-z_$][\w$]*)===`win32`\|\|\1===`linux`\?\{titleBarStyle:`hidden`,titleBarOverlay:([A-Za-z_$][\w$]*)\(([A-Za-z_$][\w$]*)\),\.\.\.([A-Za-z_$][\w$]*)===`quickChat`\?\{resizable:!0\}:\{\}\}:/g,
    (_match, platform, overlay, zoom, appearance) => {
      const quickChat = `...${appearance}===\`quickChat\`?{resizable:!0}:{}`;
      return `${platform}===\`win32\`?{titleBarStyle:\`hidden\`,titleBarOverlay:${overlay}(${zoom}),${quickChat}}:${platform}===\`linux\`?{titleBarStyle:\`hidden\`,${quickChat}}:`;
    },
  );

  // Older primary-only branch.
  source = source.replace(
    /case`primary`:return ([A-Za-z_$][\w$]*)===`darwin`\?([A-Za-z_$][\w$]*)\?\{titleBarStyle:`hiddenInset`,trafficLightPosition:([A-Za-z_$][\w$]*)\(([A-Za-z_$][\w$]*)\)\}:\{vibrancy:`menu`,titleBarStyle:`hiddenInset`,trafficLightPosition:\3\(\4\)\}:\1===`win32`(\|\|\1===`linux`)?\?\{titleBarStyle:`hidden`,titleBarOverlay:([A-Za-z_$][\w$]*)\(\4\)\}:\{titleBarStyle:`default`\};/g,
    (_match, platform, opaque, trafficLight, zoom, _linuxCombined, overlay) =>
      `case\`primary\`:return ${platform}===\`darwin\`?${opaque}?{titleBarStyle:\`hiddenInset\`,trafficLightPosition:${trafficLight}(${zoom})}:{vibrancy:\`menu\`,titleBarStyle:\`hiddenInset\`,trafficLightPosition:${trafficLight}(${zoom})}:${platform}===\`win32\`?{titleBarStyle:\`hidden\`,titleBarOverlay:${overlay}(${zoom})}:${platform}===\`linux\`?{titleBarStyle:\`hidden\`}:{titleBarStyle:\`default\`};`,
  );

  const linuxOverlayBranch = new RegExp(
    `([A-Za-z_$][\\w$]*)===\`linux\`\\?\\{titleBarStyle:\`hidden\`,titleBarOverlay:codexLinuxTitleBarOverlay\\([^)]*\\)\\}:`,
    "g",
  );
  source = source.replace(linuxOverlayBranch, (_match, platform) =>
    `${platform}===\`linux\`?{titleBarStyle:\`hidden\`}:`,
  );

  // Zoom-change paths must not call setTitleBarOverlay on a Linux window that
  // was created without an overlay.
  source = source.replace(
    /\(process\.platform===`win32`\|\|process\.platform===`linux`\)&&\(this\.windowZooms\.set\(([A-Za-z_$][\w$]*)\.id,([A-Za-z_$][\w$]*)\),\1\.setTitleBarOverlay\(([A-Za-z_$][\w$]*)\(\2\)\)\)/g,
    (_match, windowAlias, zoomAlias, overlay) =>
      `process.platform===\`win32\`&&(this.windowZooms.set(${windowAlias}.id,${zoomAlias}),${windowAlias}.setTitleBarOverlay(${overlay}(${zoomAlias})))`,
  );

  const linuxZoomTernary = new RegExp(
    "\\(process\\.platform===`win32`\\|\\|process\\.platform===`linux`\\)&&\\(this\\.windowZooms\\.set\\(([A-Za-z_$][\\w$]*)\\.id,([A-Za-z_$][\\w$]*)\\),\\1\\.setTitleBarOverlay\\(process\\.platform===`linux`\\?" +
      escapeRegExp("codexLinuxTitleBarOverlay") +
      "\\([^)]*\\):([A-Za-z_$][\\w$]*)\\(\\2\\)\\)\\)",
    "g",
  );
  source = source.replace(
    linuxZoomTernary,
    (_match, windowAlias, zoomAlias, overlay) =>
      `process.platform===\`win32\`&&(this.windowZooms.set(${windowAlias}.id,${zoomAlias}),${windowAlias}.setTitleBarOverlay(${overlay}(${zoomAlias})))`,
  );

  // Current theme-sync method includes quickChat as well as primary.
  source = source.replace(
    /(install(?:Windows|ApplicationMenu)TitleBarOverlaySync)\(([A-Za-z_$][\w$]*),([A-Za-z_$][\w$]*)\)\{if\(process\.platform!==`win32`&&process\.platform!==`linux`\|\|\3!==`primary`&&\3!==`quickChat`\)return;let ([A-Za-z_$][\w$]*)=\(\)=>\{\2\.isDestroyed\(\)\|\|\2\.setTitleBarOverlay\(process\.platform===`linux`\?codexLinuxTitleBarOverlay\(this\.windowZooms\.get\(\2\.id\)\):([A-Za-z_$][\w$]*)\(this\.windowZooms\.get\(\2\.id\)\)\)\};return ([A-Za-z_$][\w$]*)\.nativeTheme\.on\(`updated`,\4\),\4\(\),\(\)=>\{\6\.nativeTheme\.off\(`updated`,\4\)\}\}/g,
    (_match, method, windowAlias, appearance, update, windowsOverlay, electron) =>
      `${method}(${windowAlias},${appearance}){if(process.platform!==\`win32\`||${appearance}!==\`primary\`&&${appearance}!==\`quickChat\`)return;let ${update}=()=>{${windowAlias}.isDestroyed()||${windowAlias}.setTitleBarOverlay(${windowsOverlay}(this.windowZooms.get(${windowAlias}.id)))};return ${electron}.nativeTheme.on(\`updated\`,${update}),${update}(),()=>{${electron}.nativeTheme.off(\`updated\`,${update})}}`,
  );

  // Older primary-only theme-sync method.
  source = source.replace(
    /(install(?:Windows|ApplicationMenu)TitleBarOverlaySync)\(([A-Za-z_$][\w$]*),([A-Za-z_$][\w$]*)\)\{if\(\(process\.platform!==`win32`&&process\.platform!==`linux`\)\|\|\3!==`primary`\)return;let ([A-Za-z_$][\w$]*)=\(\)=>\{\2\.isDestroyed\(\)\|\|\2\.setTitleBarOverlay\(process\.platform===`linux`\?codexLinuxTitleBarOverlay\(this\.windowZooms\.get\(\2\.id\)\):([A-Za-z_$][\w$]*)\(this\.windowZooms\.get\(\2\.id\)\)\)\};return ([A-Za-z_$][\w$]*)\.nativeTheme\.on\(`updated`,\4\),\4\(\),\(\)=>\{\6\.nativeTheme\.off\(`updated`,\4\)\}\}/g,
    (_match, method, windowAlias, appearance, update, windowsOverlay, electron) =>
      `${method}(${windowAlias},${appearance}){if(process.platform!==\`win32\`||${appearance}!==\`primary\`)return;let ${update}=()=>{${windowAlias}.isDestroyed()||${windowAlias}.setTitleBarOverlay(${windowsOverlay}(this.windowZooms.get(${windowAlias}.id)))};return ${electron}.nativeTheme.on(\`updated\`,${update}),${update}(),()=>{${electron}.nativeTheme.off(\`updated\`,${update})}}`,
  );

  return source;
}

function mainResiduals(source) {
  const residuals = [];
  const start = Math.max(
    source.indexOf("case`quickChat`:case`primary`"),
    source.indexOf("case`primary`"),
  );
  if (start >= 0) {
    const end = source.indexOf(";case`secondary`", start);
    const branch = source.slice(start, end >= 0 ? end : start + 5000);
    if (/([A-Za-z_$][\w$]*)===`win32`\|\|\1===`linux`\?\{[^;]{0,1800}titleBarOverlay:/.test(branch)) {
      residuals.push("combined Windows/Linux titleBarOverlay branch");
    }
    if (/===`linux`\?\{titleBarStyle:`hidden`,titleBarOverlay:/.test(branch)) {
      residuals.push("Linux titleBarOverlay branch");
    }
    if (/titleBarOverlay:[A-Za-z_$][\w$]*===`linux`\?/.test(branch)) {
      residuals.push("Linux titleBarOverlay property selector");
    }
  }

  const zoomMatch = /setWindowZoom\([A-Za-z_$][\w$]*,[A-Za-z_$][\w$]*\)\{/.exec(source);
  const zoomAt = zoomMatch?.index ?? -1;
  if (zoomAt >= 0) {
    const zoom = source.slice(zoomAt, zoomAt + 1800);
    if (/platform===`win32`\|\|process\.platform===`linux`/.test(zoom) && /setTitleBarOverlay/.test(zoom)) {
      residuals.push("Linux zoom overlay update");
    }
  }

  const syncMatch = /install(?:Windows|ApplicationMenu)TitleBarOverlaySync\([A-Za-z_$][\w$]*,[A-Za-z_$][\w$]*\)\{if/.exec(source);
  const syncAt = syncMatch?.index ?? -1;
  if (syncAt >= 0) {
    const sync = source.slice(syncAt, syncAt + 1800);
    if (/platform!==`win32`&&process\.platform!==`linux`/.test(sync)) {
      residuals.push("Linux native-theme overlay sync");
    }
  }
  return residuals;
}

function patchWebview(source) {
  let result = source.replace(
    /applicationMenu:Object\.freeze\(\{left:0,right:\d+\}\)/g,
    "applicationMenu:Object.freeze({left:0,right:0})",
  );
  result = result.split("case`win32`:case`linux`:return`application-menu`")
    .join("case`win32`:return`application-menu`;case`linux`:return`native`");
  result = result.replace(
    /([A-Za-z_$][\w$]*)\.includes\(`win`\)\|\|([A-Za-z_$][\w$]*)\.includes\(`windows`\)\|\|\1\.includes\(`linux`\)\?([A-Za-z_$][\w$]*)\?\?([A-Za-z_$][\w$]*)\.applicationMenu:\4\.default/g,
    (_match, platform, userAgent, fallback, layout) =>
      `${platform}.includes(\`win\`)||${userAgent}.includes(\`windows\`)?${fallback}??${layout}.applicationMenu:${layout}.default`,
  );
  result = result.replace(
    /function ([A-Za-z_$][\w$]*)\(\)\{return ([A-Za-z_$][\w$]*)\(\)&&window\.electronBridge\?\.showApplicationMenu!=null\}/g,
    (_match, functionName) => `function ${functionName}(){return!1}`,
  );
  return result;
}

function webviewResiduals(source) {
  const residuals = [];
  if (/function [A-Za-z_$][\w$]*\(\)\{return [^}]{0,200}showApplicationMenu!=null\}/.test(source)) {
    residuals.push("Linux application-menu bridge");
  }
  if (/includes\(`linux`\)\?[^:;]{0,240}applicationMenu:/.test(source)) {
    residuals.push("Linux application-menu layout gate");
  }
  if (source.includes("case`win32`:case`linux`:return`application-menu`")) {
    residuals.push("Linux application-menu chrome mapping");
  }
  return residuals;
}

const buildDir = path.join(appDir, ".vite", "build");
const mainFiles = fs.readdirSync(buildDir)
  .filter((name) => name.endsWith(".js"))
  .map((name) => path.join(buildDir, name));

let mainSeen = 0;
let mainChanged = 0;
for (const file of mainFiles) {
  const source = fs.readFileSync(file, "utf8");
  const looksLikeMain =
    source.includes("case`quickChat`:case`primary`") ||
    (source.includes("setWindowZoom(") && source.includes("TitleBarOverlaySync("));
  if (!looksLikeMain) continue;
  mainSeen += 1;
  const patched = patchMainBundle(source);
  const residuals = mainResiduals(patched);
  if (residuals.length > 0) {
    throw new Error(`Unsupported main-bundle layout in ${path.basename(file)}: ${residuals.join(", ")}`);
  }
  if (patched !== source) {
    fs.writeFileSync(file, patched);
    mainChanged += 1;
  }
}
if (mainSeen !== 1) {
  throw new Error(`Expected exactly one Codex main bundle, found ${mainSeen}`);
}

const candidateBuffer = fs.readFileSync(candidatesFile);
const candidateFiles = candidateBuffer.length === 0
  ? []
  : candidateBuffer.toString("utf8").split("\0").filter(Boolean);
const changedAssets = [];
let relevantAssets = 0;
for (const file of candidateFiles) {
  const source = fs.readFileSync(file, "utf8");
  const beforeResiduals = webviewResiduals(source);
  if (beforeResiduals.length === 0) continue;
  relevantAssets += 1;
  const patched = patchWebview(source);
  const afterResiduals = webviewResiduals(patched);
  if (afterResiduals.length > 0) {
    throw new Error(`Unsupported webview layout in ${path.basename(file)}: ${afterResiduals.join(", ")}`);
  }
  const relative = path.relative(assetsRoot, file);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`Unsafe webview asset path: ${file}`);
  }
  const staged = path.join(stagedAssetsRoot, relative);
  fs.mkdirSync(path.dirname(staged), { recursive: true });
  fs.writeFileSync(staged, patched);
  changedAssets.push(relative);
}

if (relevantAssets > 1) {
  throw new Error(`Expected at most one relevant webview controls bundle, found ${relevantAssets}`);
}

changedAssets.sort();
fs.writeFileSync(manifestFile, changedAssets.length > 0 ? `${changedAssets.join("\n")}\n` : "");
const status = { mainSeen, mainChanged, relevantAssets, changedAssets };
fs.writeFileSync(statusFile, `${JSON.stringify(status, null, 2)}\n`);
console.log(JSON.stringify(status, null, 2));
NODE

main_changed="$(node -p 'require(process.argv[1]).mainChanged' "$work_dir/patch-status.json")"
assets_changed="$(node -p 'require(process.argv[1]).changedAssets.length' "$work_dir/patch-status.json")"

if [[ "$main_changed" -eq 0 && "$assets_changed" -eq 0 ]]; then
    printf 'This Codex version is already frameless; no change is necessary.\n'
    exit 0
fi

if [[ "$main_changed" -gt 0 ]]; then
    printf 'Repacking and validating the application archive...\n'
    asar pack "$work_dir/app" "$work_dir/app.asar" --unpack '**/*.node'
    asar list -i "$work_dir/app.asar" > "$work_dir/patched-asar-list"
    LC_ALL=C sort "$work_dir/original-asar-list" > "$work_dir/original-asar-list.sorted"
    LC_ALL=C sort "$work_dir/patched-asar-list" > "$work_dir/patched-asar-list.sorted"
    if ! cmp -s "$work_dir/original-asar-list.sorted" "$work_dir/patched-asar-list.sorted"; then
        printf 'Repacked ASAR layout differs from the installed archive. Nothing was installed.\n' >&2
        diff -u "$work_dir/original-asar-list.sorted" "$work_dir/patched-asar-list.sorted" | head -80 >&2 || true
        exit 1
    fi
fi

if [[ "$mode" == "dry-run" ]]; then
    printf 'Dry run passed. This version can be patched safely; no installed file was changed.\n'
    exit 0
fi

printf 'Creating a rollback backup...\n'
mkdir -p "$state_root"
backup_new="$state_root/backup.new.$$"
rm -rf -- "$backup_new"
mkdir -p "$backup_new/assets"
cp --reflink=auto "$asar_file" "$backup_new/app.asar"
printf '%s\n' "$package_version" > "$backup_new/package-version"
cp "$work_dir/assets.list" "$backup_new/assets.list"
while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    mkdir -p "$backup_new/assets/$(dirname "$relative_path")"
    cp --reflink=auto "$assets_root/$relative_path" "$backup_new/assets/$relative_path"
done < "$work_dir/assets.list"
rm -rf -- "$backup_dir"
mv "$backup_new" "$backup_dir"

printf 'Installing the validated patch...\n'
sudo -v
install_failed=0
if [[ "$main_changed" -gt 0 ]]; then
    sudo install -o root -g root -m 0644 "$work_dir/app.asar" "$asar_file" || install_failed=1
fi
if [[ "$install_failed" -eq 0 ]]; then
    while IFS= read -r relative_path; do
        [[ -n "$relative_path" ]] || continue
        sudo install -o root -g root -m 0644 \
            "$work_dir/patched-assets/$relative_path" "$assets_root/$relative_path" || {
                install_failed=1
                break
            }
    done < "$work_dir/assets.list"
fi

if [[ "$install_failed" -ne 0 ]]; then
    printf 'Installation failed; restoring the backup...\n' >&2
    sudo install -o root -g root -m 0644 "$backup_dir/app.asar" "$asar_file"
    while IFS= read -r relative_path; do
        [[ -n "$relative_path" ]] || continue
        sudo install -o root -g root -m 0644 \
            "$backup_dir/assets/$relative_path" "$assets_root/$relative_path"
    done < "$backup_dir/assets.list"
    exit 1
fi

if [[ "$main_changed" -gt 0 ]]; then
    installed_hash="$(sha256sum "$asar_file" | awk '{print $1}')"
    patched_hash="$(sha256sum "$work_dir/app.asar" | awk '{print $1}')"
    if [[ "$installed_hash" != "$patched_hash" ]]; then
        printf 'Installed ASAR failed checksum verification; use --restore immediately.\n' >&2
        exit 1
    fi
fi

printf '\nPatch installed for codex-desktop-linux %s.\n' "$package_version"
printf 'After the next Codex update, fully quit Codex and run this same script again.\n'
printf 'Rollback command: %s --restore\n' "$0"
