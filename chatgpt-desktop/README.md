# ChatGPT Desktop for Arch Linux

This directory repackages OpenAI's official x86-64 Debian package as a normal
Arch Linux package named `chatgpt-desktop`. You can keep the official top-right
window buttons (the default) or remove them during the build.

The installer reads OpenAI's Debian repository index first, downloads the exact
versioned package from `persistent.oaistatic.com`, and verifies both its byte
size and SHA-256 before building. If a future Electron bundle no longer matches
the known title-bar layout, packaging stops without installing it.

## Install or update

Fully quit ChatGPT/Codex Desktop, then run from a terminal:

```bash
cd /home/tanzhenyu/Developer/linux-tweak/chatgpt-desktop
./install.sh
```

The default command keeps the official minimize, maximize/restore, and close
buttons. These two commands make the choice explicit:

```bash
./install.sh --with-buttons
./install.sh --without-buttons
```

You can switch modes later by fully quitting ChatGPT and rerunning the installer
with the other option. The same command also downloads and installs future
official Debian updates.

The script installs build/runtime dependencies through pacman and may ask for
your sudo password. It also replaces conflicting older ChatGPT/Codex Desktop
packages after pacman asks for confirmation. Keep at least 5 GiB of free space
in the workspace for the download, extracted application, and package build.

## Launch and optional flags

Launch `ChatGPT` from the desktop menu or run `chatgpt`. Native Wayland mode is
selected automatically in a Wayland session. Put one optional Electron flag per
line in `~/.config/chatgpt-flags.conf`; command-line flags take precedence.

Removing the window controls is most suitable for a tiling compositor. On a
traditional floating desktop you will need keyboard shortcuts or the window
menu to minimize, maximize, or close the window.

## Uninstall

```bash
sudo pacman -Rns chatgpt-desktop
```
