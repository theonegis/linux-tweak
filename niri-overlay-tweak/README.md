# niri Mica overlays

For the reusable clone → modify → package → install workflow, see
[`WORKFLOW.zh-CN.md`](WORKFLOW.zh-CN.md). The old version-pinned patch is kept
only as the original Acrylic snapshot; the current Mica build uses
`apply-niri-acrylic.py` through `update-build-install.sh`.

This local Arch package rebuilds niri with a consistent blue-to-green Mica-like
appearance for its native text information overlays:

- the recent-window switcher's `Scope` panel;
- the screenshot UI help panel;
- the `Important Hotkeys` overlay.

The transformation uses Inter 15 px, black text, 24 px horizontal and 18 px
vertical padding, a lightly translucent pale-blue-to-pale-green Mica gradient,
a subtle environmental highlight, a fine inner border, and 16–18 px rounded
corners. It does not modify the niri configuration in the user's home directory.

## Build and install

Install the normal Arch build tools if necessary, then build as an ordinary
user:

```sh
sudo pacman -S --needed base-devel
cd /home/tanzhenyu/Developer/niri-overlay-acrylic
./update-build-install.sh
```

`niri-acrylic` provides and conflicts with `niri`, so pacman will ask to
replace the installed repository package. Log out and log back in after the
installation; restarting niri from inside the current graphical session is
not recommended.

## Adjust the look

The visual constants are generated near the beginning of each patched source
file. Edit `apply-niri-acrylic.py` before rebuilding if desired:

- `PANEL_PADDING_X/Y`, `PANEL_CORNER_RADIUS` and `FONT` affect the Scope panel;
- `PADDING_X/Y`, `CORNER_RADIUS`, `LINE_INTERVAL` and `FONT` affect Hotkeys;
- `PADDING_X/Y`, `PANEL_CORNER_RADIUS` and `FONT` affect the screenshot help panel;
- `add_color_stop_rgba(...)` controls the Mica gradient stops and opacity;
- `set_source_rgb(0., 0., 0.)` keeps the text black and high-contrast.

Run `./update-build-install.sh` again after changing the transformation.

## Updating niri

For a new stable niri release, run:

```sh
cd /home/tanzhenyu/Developer/niri-overlay-acrylic
./update-build-install.sh
```

The script selects the latest stable tag and applies the transformation
strictly. If upstream changes one of the three UI files, it stops before
writing partial changes so the matching anchors can be updated safely.
