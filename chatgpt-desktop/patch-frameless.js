"use strict";

const fs = require("node:fs");
const path = require("node:path");

const [appDir, assetsRoot] = process.argv.slice(2);
if (!appDir) {
  throw new Error("Usage: node patch-frameless.js APP_DIR [WEBVIEW_ASSETS_DIR]");
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function patchMainBundle(currentSource) {
  let source = currentSource;

  source = source.replace(
    /([A-Za-z_$][\w$]*)===`win32`\|\|\1===`linux`\?\{titleBarStyle:`hidden`,titleBarOverlay:\1===`linux`\?codexLinuxTitleBarOverlay\(([A-Za-z_$][\w$]*)\):([A-Za-z_$][\w$]*)\(\2\),\.\.\.([A-Za-z_$][\w$]*)===`quickChat`\?\{resizable:!0\}:\{\}\}:/g,
    (_match, platform, zoom, windowsOverlay, appearance) => {
      const quickChat = `...${appearance}===\`quickChat\`?{resizable:!0}:{}`;
      return `${platform}===\`win32\`?{titleBarStyle:\`hidden\`,titleBarOverlay:${windowsOverlay}(${zoom}),${quickChat}}:${platform}===\`linux\`?{titleBarStyle:\`hidden\`,${quickChat}}:`;
    },
  );

  source = source.replace(
    /([A-Za-z_$][\w$]*)===`win32`\|\|\1===`linux`\?\{titleBarStyle:`hidden`,titleBarOverlay:([A-Za-z_$][\w$]*)\(([A-Za-z_$][\w$]*)\),\.\.\.([A-Za-z_$][\w$]*)===`quickChat`\?\{resizable:!0\}:\{\}\}:/g,
    (_match, platform, overlay, zoom, appearance) => {
      const quickChat = `...${appearance}===\`quickChat\`?{resizable:!0}:{}`;
      return `${platform}===\`win32\`?{titleBarStyle:\`hidden\`,titleBarOverlay:${overlay}(${zoom}),${quickChat}}:${platform}===\`linux\`?{titleBarStyle:\`hidden\`,${quickChat}}:`;
    },
  );

  source = source.replace(
    /case`primary`:return ([A-Za-z_$][\w$]*)===`darwin`\?([A-Za-z_$][\w$]*)\?\{titleBarStyle:`hiddenInset`,trafficLightPosition:([A-Za-z_$][\w$]*)\(([A-Za-z_$][\w$]*)\)\}:\{vibrancy:`menu`,titleBarStyle:`hiddenInset`,trafficLightPosition:\3\(\4\)\}:\1===`win32`(\|\|\1===`linux`)?\?\{titleBarStyle:`hidden`,titleBarOverlay:([A-Za-z_$][\w$]*)\(\4\)\}:\{titleBarStyle:`default`\};/g,
    (_match, platform, opaque, trafficLight, zoom, _linuxCombined, overlay) =>
      `case\`primary\`:return ${platform}===\`darwin\`?${opaque}?{titleBarStyle:\`hiddenInset\`,trafficLightPosition:${trafficLight}(${zoom})}:{vibrancy:\`menu\`,titleBarStyle:\`hiddenInset\`,trafficLightPosition:${trafficLight}(${zoom})}:${platform}===\`win32\`?{titleBarStyle:\`hidden\`,titleBarOverlay:${overlay}(${zoom})}:${platform}===\`linux\`?{titleBarStyle:\`hidden\`}:{titleBarStyle:\`default\`};`,
  );

  const linuxOverlayBranch = new RegExp(
    `([A-Za-z_$][\\w$]*)===\`linux\`\\?\\{titleBarStyle:\`hidden\`,titleBarOverlay:codexLinuxTitleBarOverlay\\([^)]*\\)\\}:`,
    "g",
  );
  source = source.replace(
    linuxOverlayBranch,
    (_match, platform) => `${platform}===\`linux\`?{titleBarStyle:\`hidden\`}:`,
  );

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

  source = source.replace(
    /(install(?:Windows|ApplicationMenu)TitleBarOverlaySync)\(([A-Za-z_$][\w$]*),([A-Za-z_$][\w$]*)\)\{if\(process\.platform!==`win32`&&process\.platform!==`linux`\|\|\3!==`primary`&&\3!==`quickChat`\)return;let ([A-Za-z_$][\w$]*)=\(\)=>\{\2\.isDestroyed\(\)\|\|\2\.setTitleBarOverlay\(process\.platform===`linux`\?codexLinuxTitleBarOverlay\(this\.windowZooms\.get\(\2\.id\)\):([A-Za-z_$][\w$]*)\(this\.windowZooms\.get\(\2\.id\)\)\)\};return ([A-Za-z_$][\w$]*)\.nativeTheme\.on\(`updated`,\4\),\4\(\),\(\)=>\{\6\.nativeTheme\.off\(`updated`,\4\)\}\}/g,
    (_match, method, windowAlias, appearance, update, windowsOverlay, electron) =>
      `${method}(${windowAlias},${appearance}){if(process.platform!==\`win32\`||${appearance}!==\`primary\`&&${appearance}!==\`quickChat\`)return;let ${update}=()=>{${windowAlias}.isDestroyed()||${windowAlias}.setTitleBarOverlay(${windowsOverlay}(this.windowZooms.get(${windowAlias}.id)))};return ${electron}.nativeTheme.on(\`updated\`,${update}),${update}(),()=>{${electron}.nativeTheme.off(\`updated\`,${update})}}`,
  );

  // Official Linux package: Windows and Linux call the same overlay helper.
  source = source.replace(
    /(install(?:Windows|ApplicationMenu)TitleBarOverlaySync)\(([A-Za-z_$][\w$]*),([A-Za-z_$][\w$]*)\)\{if\(process\.platform!==`win32`&&process\.platform!==`linux`\|\|\3!==`primary`&&\3!==`quickChat`\)return;let ([A-Za-z_$][\w$]*)=\(\)=>\{\2\.isDestroyed\(\)\|\|\2\.setTitleBarOverlay\(([A-Za-z_$][\w$]*)\(this\.windowZooms\.get\(\2\.id\)\)\)\};return ([A-Za-z_$][\w$]*)\.nativeTheme\.on\(`updated`,\4\),\4\(\),\(\)=>\{\6\.nativeTheme\.off\(`updated`,\4\)\}\}/g,
    (_match, method, windowAlias, appearance, update, overlay, electron) =>
      `${method}(${windowAlias},${appearance}){if(process.platform!==\`win32\`||${appearance}!==\`primary\`&&${appearance}!==\`quickChat\`)return;let ${update}=()=>{${windowAlias}.isDestroyed()||${windowAlias}.setTitleBarOverlay(${overlay}(this.windowZooms.get(${windowAlias}.id)))};return ${electron}.nativeTheme.on(\`updated\`,${update}),${update}(),()=>{${electron}.nativeTheme.off(\`updated\`,${update})}}`,
  );

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
  result = result
    .split("case`win32`:case`linux`:return`application-menu`")
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

function collectJavaScriptFiles(root) {
  const files = [];
  const pending = [root];
  while (pending.length > 0) {
    const directory = pending.pop();
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) pending.push(file);
      else if (entry.isFile() && entry.name.endsWith(".js")) files.push(file);
    }
  }
  return files;
}

const buildDir = path.join(appDir, ".vite", "build");
const mainFiles = fs
  .readdirSync(buildDir)
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
    throw new Error(
      `Unsupported main-bundle layout in ${path.basename(file)}: ${residuals.join(", ")}`,
    );
  }
  if (patched !== source) {
    fs.writeFileSync(file, patched);
    mainChanged += 1;
  }
}
if (mainSeen !== 1) {
  throw new Error(`Expected exactly one ChatGPT main bundle, found ${mainSeen}`);
}

const changedAssets = [];
let relevantAssets = 0;
const assetFiles = assetsRoot && fs.existsSync(assetsRoot)
  ? collectJavaScriptFiles(assetsRoot)
  : [];
for (const file of assetFiles) {
  const source = fs.readFileSync(file, "utf8");
  const beforeResiduals = webviewResiduals(source);
  if (beforeResiduals.length === 0) continue;
  relevantAssets += 1;
  const patched = patchWebview(source);
  const afterResiduals = webviewResiduals(patched);
  if (afterResiduals.length > 0) {
    throw new Error(
      `Unsupported webview layout in ${path.basename(file)}: ${afterResiduals.join(", ")}`,
    );
  }
  fs.writeFileSync(file, patched);
  changedAssets.push(path.relative(assetsRoot, file));
}
if (relevantAssets > 1) {
  throw new Error(
    `Expected at most one relevant webview controls bundle, found ${relevantAssets}`,
  );
}

const status = { mainSeen, mainChanged, relevantAssets, changedAssets };
console.log(JSON.stringify(status, null, 2));
