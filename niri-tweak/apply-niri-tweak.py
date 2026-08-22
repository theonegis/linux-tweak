#!/usr/bin/env python3
"""Apply local overlay, gesture, and session tweaks to a niri checkout.

The source transformations are intentionally strict.  A changed upstream
anchor stops the script before any file is written, so a new niri release
cannot silently receive a partial patch.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


class TransformError(RuntimeError):
    pass


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise TransformError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def panel_helpers() -> str:
    return '''fn rounded_rectangle(cr: &cairo::Context, x: f64, y: f64, width: f64, height: f64, radius: f64) {
    let radius = radius.min(width / 2.).min(height / 2.);
    let x2 = x + width;
    let y2 = y + height;

    cr.new_sub_path();
    cr.arc(
        x2 - radius,
        y + radius,
        radius,
        -std::f64::consts::FRAC_PI_2,
        0.,
    );
    cr.arc(
        x2 - radius,
        y2 - radius,
        radius,
        0.,
        std::f64::consts::FRAC_PI_2,
    );
    cr.arc(
        x + radius,
        y2 - radius,
        radius,
        std::f64::consts::FRAC_PI_2,
        std::f64::consts::PI,
    );
    cr.arc(
        x + radius,
        y + radius,
        radius,
        std::f64::consts::PI,
        std::f64::consts::PI * 1.5,
    );
    cr.close_path();
}

fn paint_rounded_panel(
    cr: &cairo::Context,
    width: i32,
    height: i32,
    scale: f64,
    border: niri_config::Border,
) -> Result<(), cairo::Error> {
    let width = f64::from(width);
    let height = f64::from(height);
    let border_width = (border.width * scale).round().max(0.);
    let inset = border_width / 2.;
    let radius = 16. * scale;

    rounded_rectangle(
        cr,
        inset,
        inset,
        width - border_width,
        height - border_width,
        radius - inset,
    );
    cr.set_source_rgb(0.1, 0.1, 0.1);
    cr.fill_preserve()?;
    let color = border.active_color;
    cr.set_source_rgba(
        f64::from(color.r),
        f64::from(color.g),
        f64::from(color.b),
        f64::from(color.a),
    );
    if border_width > 0. {
        cr.set_line_width(border_width);
        cr.stroke()
    } else {
        cr.new_path();
        Ok(())
    }
}
'''


def transform_hotkeys(text: str) -> str:
    if 'const FONT: &str = "sans 14px";' not in text:
        raise TransformError("hotkey overlay no longer uses the generic system font")
    text = replace_once(text, "const BORDER: i32 = 4;\n", "", "hotkey border constant")
    text = replace_once(
        text,
        "\nfn render(\n",
        "\n" + panel_helpers() + "\nfn render(\n",
        "hotkey rounded-panel helpers",
    )
    text = replace_once(
        text,
        'attrs.insert(AttrString::new_family("Monospace"));',
        'attrs.insert(AttrString::new_family("Sans"));',
        "hotkey keycap font",
    )
    if text.count("face='monospace'") != 2:
        raise TransformError("hotkey action font: expected exactly two matches")
    text = text.replace("face='monospace'", "face='sans'")
    text = replace_once(
        text,
        "    cr.set_source_rgb(0.1, 0.1, 0.1);\n    cr.paint()?;",
        "    paint_rounded_panel(&cr, width, height, scale, config.layout.border)?;",
        "hotkey background",
    )
    text = replace_once(
        text,
        "    cr.move_to(0., 0.);\n"
        "    cr.line_to(width.into(), 0.);\n"
        "    cr.line_to(width.into(), height.into());\n"
        "    cr.line_to(0., height.into());\n"
        "    cr.line_to(0., 0.);\n"
        "    cr.set_source_rgb(0.5, 0.8, 1.0);\n"
        "    // Keep the border width even to avoid blurry edges.\n"
        "    cr.set_line_width((f64::from(BORDER) / 2. * scale).round() * 2.);\n"
        "    cr.stroke()?;\n",
        "",
        "hotkey square border",
    )
    return text


def transform_mru(text: str) -> str:
    if 'const FONT: &str = "sans 14px";' not in text:
        raise TransformError("MRU overlay no longer uses the generic system font")
    text = replace_once(
        text,
        "/// Border size of the scope indication panel.\nconst PANEL_BORDER: i32 = 4;\n\n",
        "",
        "MRU border constant",
    )
    text = replace_once(
        text,
        "\nfn render_panel(",
        "\n" + panel_helpers() + "\nfn render_panel(",
        "MRU rounded-panel helpers",
    )
    text = replace_once(text, "face='mono'", "face='sans'", "MRU keycap font")
    text = replace_once(
        text,
        "struct ScopePanel {\n"
        "    scale: f64,\n"
        "    textures: Option<Option<[MruTexture; 3]>>,\n"
        "}",
        "struct ScopePanel {\n"
        "    scale: f64,\n"
        "    border: niri_config::Border,\n"
        "    textures: Option<Option<[MruTexture; 3]>>,\n"
        "}",
        "MRU cached border config",
    )
    text = replace_once(
        text,
        "        let panel_texture =\n"
        "            self.scope_panel\n"
        "                .borrow_mut()\n"
        "                .get(ctx.as_gles().renderer, scale, self.wmru.scope);",
        "        let border = self.config.borrow().layout.border;\n"
        "        let panel_texture = self.scope_panel.borrow_mut().get(\n"
        "            ctx.as_gles().renderer,\n"
        "            scale,\n"
        "            self.wmru.scope,\n"
        "            border,\n"
        "        );",
        "MRU border config lookup",
    )
    text = replace_once(
        text,
        "        scale: f64,\n"
        "        scope: MruScope,\n"
        "    ) -> Option<MruTexture> {\n"
        "        if self.scale != scale {\n"
        "            self.textures = None;\n"
        "            self.scale = scale;\n"
        "        }\n\n"
        "        self.textures\n"
        "            .get_or_insert_with(|| generate_scope_panels(renderer, scale).ok())",
        "        scale: f64,\n"
        "        scope: MruScope,\n"
        "        border: niri_config::Border,\n"
        "    ) -> Option<MruTexture> {\n"
        "        if self.scale != scale || self.border != border {\n"
        "            self.textures = None;\n"
        "            self.scale = scale;\n"
        "            self.border = border;\n"
        "        }\n\n"
        "        self.textures\n"
        "            .get_or_insert_with(|| generate_scope_panels(renderer, scale, border).ok())",
        "MRU cache invalidation",
    )
    text = replace_once(
        text,
        "fn generate_scope_panels(\n"
        "    renderer: &mut GlesRenderer,\n"
        "    scale: f64,\n"
        ") -> anyhow::Result<[MruTexture; 3]> {",
        "fn generate_scope_panels(\n"
        "    renderer: &mut GlesRenderer,\n"
        "    scale: f64,\n"
        "    border: niri_config::Border,\n"
        ") -> anyhow::Result<[MruTexture; 3]> {",
        "MRU panel generator border",
    )
    text = replace_once(
        text,
        "        render_panel(renderer, scale, &make_panel_text(0))?,\n"
        "        render_panel(renderer, scale, &make_panel_text(1))?,\n"
        "        render_panel(renderer, scale, &make_panel_text(2))?,",
        "        render_panel(renderer, scale, &make_panel_text(0), border)?,\n"
        "        render_panel(renderer, scale, &make_panel_text(1), border)?,\n"
        "        render_panel(renderer, scale, &make_panel_text(2), border)?,",
        "MRU render-panel border arguments",
    )
    text = replace_once(
        text,
        "fn render_panel(renderer: &mut GlesRenderer, scale: f64, text: &str) -> anyhow::Result<MruTexture> {",
        "fn render_panel(\n"
        "    renderer: &mut GlesRenderer,\n"
        "    scale: f64,\n"
        "    text: &str,\n"
        "    border: niri_config::Border,\n"
        ") -> anyhow::Result<MruTexture> {",
        "MRU render-panel signature",
    )
    text = replace_once(
        text,
        "    cr.set_source_rgb(0.1, 0.1, 0.1);\n    cr.paint()?;",
        "    paint_rounded_panel(&cr, width, height, scale, border)?;",
        "MRU background",
    )
    text = replace_once(
        text,
        "    cr.move_to(0., 0.);\n"
        "    cr.line_to(width.into(), 0.);\n"
        "    cr.line_to(width.into(), height.into());\n"
        "    cr.line_to(0., height.into());\n"
        "    cr.line_to(0., 0.);\n"
        "    cr.set_source_rgb(0.5, 0.5, 0.5);\n"
        "    cr.set_line_width((f64::from(PANEL_BORDER) / 2. * scale).round() * 2.);\n"
        "    cr.stroke()?;\n\n",
        "",
        "MRU square border",
    )
    return text


def transform_screenshot(text: str) -> str:
    if 'const FONT: &str = "sans 14px";' not in text:
        raise TransformError("screenshot overlay no longer uses the generic system font")
    text = replace_once(text, "const BORDER: i32 = 4;\n", "", "screenshot border constant")
    text = replace_once(
        text,
        "\nfn render_panel(",
        "\n" + panel_helpers() + "\nfn render_panel(",
        "screenshot rounded-panel helpers",
    )
    if text.count("face='mono'") != 4:
        raise TransformError("screenshot keycap font: expected exactly four matches")
    text = text.replace("face='mono'", "face='sans'")
    text = replace_once(
        text,
        "        let output_data = screenshots\n"
        "            .into_iter()",
        "        let border = config.borrow().layout.border;\n"
        "        let output_data = screenshots\n"
        "            .into_iter()",
        "screenshot border config lookup",
    )
    text = replace_once(
        text,
        "                    render_panel(renderer, scale, text)",
        "                    render_panel(renderer, scale, text, border)",
        "screenshot render-panel border argument",
    )
    text = replace_once(
        text,
        "fn render_panel(\n"
        "    renderer: &mut GlesRenderer,\n"
        "    scale: f64,\n"
        "    text: &str,\n"
        ") -> anyhow::Result<TextureBuffer<GlesTexture>> {",
        "fn render_panel(\n"
        "    renderer: &mut GlesRenderer,\n"
        "    scale: f64,\n"
        "    text: &str,\n"
        "    border: niri_config::Border,\n"
        ") -> anyhow::Result<TextureBuffer<GlesTexture>> {",
        "screenshot render-panel signature",
    )
    text = replace_once(
        text,
        "    // Keep the border width even to avoid blurry edges.\n"
        "    let border_width = (f64::from(BORDER) / 2. * scale).round() * 2.;",
        "    let border_width = (border.width * scale).round().max(0.);",
        "screenshot configured border width",
    )
    text = replace_once(
        text,
        "    cr.set_source_rgb(0.1, 0.1, 0.1);\n    cr.paint()?;",
        "    paint_rounded_panel(&cr, width, height, scale, border)?;",
        "screenshot background",
    )
    text = replace_once(
        text,
        "    cr.move_to(0., 0.);\n"
        "    cr.line_to(width.into(), 0.);\n"
        "    cr.line_to(width.into(), height.into());\n"
        "    cr.line_to(0., height.into());\n"
        "    cr.line_to(0., 0.);\n"
        "    cr.set_source_rgb(0.3, 0.3, 0.3);\n"
        "    cr.set_line_width(border_width);\n"
        "    cr.stroke()?;\n",
        "",
        "screenshot square border",
    )
    return text


def transform_gestures(cargo: str, input_rs: str, niri_rs: str) -> tuple[str, str, str]:
    cargo = replace_once(
        cargo,
        'input = { version = "0.10.0", features = ["libinput_1_21"] }',
        'input = { version = "0.10.0", features = ["libinput_1_28"] }',
        "libinput Rust feature level",
    )

    input_rs = replace_once(
        input_rs,
        "pub const DOUBLE_CLICK_TIME: Duration = Duration::from_millis(400);",
        "pub const DOUBLE_CLICK_TIME: Duration = Duration::from_millis(400);\n"
        "const FOUR_FINGER_PINCH_IN_THRESHOLD: f64 = 0.8;\n"
        "const FOUR_FINGER_PINCH_OUT_THRESHOLD: f64 = 1.2;",
        "four-finger pinch thresholds",
    )
    input_rs = replace_once(
        input_rs,
        "        if event.fingers() == 3 {\n"
        "            self.niri.gesture_swipe_3f_cumulative = Some((0., 0.));\n\n"
        "            // We handled this event.\n"
        "            return;\n"
        "        } else if event.fingers() == 4 {\n"
        "            self.niri.layout.overview_gesture_begin();\n"
        "            self.niri.queue_redraw_all();\n\n"
        "            // We handled this event.\n"
        "            return;\n"
        "        }",
        "        // Three-finger motion is handled by libinput as a left-button drag.\n"
        "        // Four fingers inherit niri's original three-finger workspace/view gestures.\n"
        "        if event.fingers() == 4 {\n"
        "            self.niri.gesture_swipe_3f_cumulative = Some((0., 0.));\n\n"
        "            // We handled this event.\n"
        "            return;\n"
        "        }",
        "four-finger swipe remap",
    )
    input_rs = replace_once(
        input_rs,
        "        let _ = device.config_tap_set_enabled(c.tap);",
        "        let _ = device.config_tap_set_enabled(c.tap);\n\n"
        "        // Enable libinput's native macOS-style three-finger left-button drag.\n"
        "        if device.config_3fg_drag_get_finger_count() >= 3 {\n"
        "            let _ =\n"
        "                device.config_3fg_drag_set_enabled(input::ThreeFingerDragState::EnabledThreeFinger);\n"
        "        }",
        "native three-finger drag",
    )

    input_rs = replace_once(
        input_rs,
        "    fn on_gesture_pinch_begin<I: InputBackend>(&mut self, event: I::GesturePinchBeginEvent) {\n"
        "        let serial = SERIAL_COUNTER.next_serial();",
        "    fn on_gesture_pinch_begin<I: InputBackend>(&mut self, event: I::GesturePinchBeginEvent) {\n"
        "        if event.fingers() == 4 {\n"
        "            self.niri.gesture_pinch_4f_triggered = Some(false);\n"
        "            return;\n"
        "        }\n\n"
        "        let serial = SERIAL_COUNTER.next_serial();",
        "four-finger pinch begin",
    )
    input_rs = replace_once(
        input_rs,
        "    fn on_gesture_pinch_update<I: InputBackend>(&mut self, event: I::GesturePinchUpdateEvent) {\n"
        "        let pointer = self.niri.seat.get_pointer().unwrap();",
        "    fn on_gesture_pinch_update<I: InputBackend>(&mut self, event: I::GesturePinchUpdateEvent) {\n"
        "        if self.niri.gesture_pinch_4f_triggered.is_some() {\n"
        "            let open = if self.niri.gesture_pinch_4f_triggered == Some(false) {\n"
        "                if event.scale() <= FOUR_FINGER_PINCH_IN_THRESHOLD {\n"
        "                    Some(true)\n"
        "                } else if event.scale() >= FOUR_FINGER_PINCH_OUT_THRESHOLD {\n"
        "                    Some(false)\n"
        "                } else {\n"
        "                    None\n"
        "                }\n"
        "            } else {\n"
        "                None\n"
        "            };\n\n"
        "            if let Some(open) = open {\n"
        "                self.niri.gesture_pinch_4f_triggered = Some(true);\n"
        "                let changed = if open {\n"
        "                    self.niri.layout.open_overview()\n"
        "                } else {\n"
        "                    self.niri.layout.close_overview()\n"
        "                };\n"
        "                if changed {\n"
        "                    self.niri.queue_redraw_all();\n"
        "                }\n"
        "            }\n\n"
        "            return;\n"
        "        }\n\n"
        "        let pointer = self.niri.seat.get_pointer().unwrap();",
        "four-finger pinch update",
    )
    input_rs = replace_once(
        input_rs,
        "    fn on_gesture_pinch_end<I: InputBackend>(&mut self, event: I::GesturePinchEndEvent) {\n"
        "        let serial = SERIAL_COUNTER.next_serial();",
        "    fn on_gesture_pinch_end<I: InputBackend>(&mut self, event: I::GesturePinchEndEvent) {\n"
        "        if self.niri.gesture_pinch_4f_triggered.take().is_some() {\n"
        "            return;\n"
        "        }\n\n"
        "        let serial = SERIAL_COUNTER.next_serial();",
        "four-finger pinch end",
    )

    niri_rs = replace_once(
        niri_rs,
        "    pub gesture_swipe_3f_cumulative: Option<(f64, f64)>,",
        "    pub gesture_swipe_3f_cumulative: Option<(f64, f64)>,\n"
        "    /// Some(false) while a four-finger pinch is waiting for its threshold.\n"
        "    pub gesture_pinch_4f_triggered: Option<bool>,",
        "four-finger pinch state field",
    )
    niri_rs = replace_once(
        niri_rs,
        "            gesture_swipe_3f_cumulative: None,",
        "            gesture_swipe_3f_cumulative: None,\n"
        "            gesture_pinch_4f_triggered: None,",
        "four-finger pinch state initialization",
    )
    return cargo, input_rs, niri_rs


def transform_session(text: str) -> str:
    old = "    systemctl --user import-environment"
    new = (
        "    systemctl --user import-environment "
        "$(printenv | cut -d'=' -f1 | tr '\\n' ' ')"
    )
    if old in text and new not in text:
        text = replace_once(text, old, new, "niri-session environment import")

    marker = "    # Clear retained Linux VT text immediately before niri takes over."
    start = "    systemctl --user --wait start niri.service"
    if marker not in text and start in text:
        block = (
            marker
            + "\n    case \"$(tty 2>/dev/null)\" in\n"
            + "    /dev/tty[0-9]*)\n"
            + "        printf '\\033[H\\033[2J\\033[3J' > /dev/tty 2>/dev/null || :\n"
            + "        ;;\n"
            + "    esac\n\n"
            + start
        )
        text = replace_once(text, start, block, "niri-session VT clear")
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="path to the niri source checkout")
    args = parser.parse_args()
    source = args.source.expanduser().resolve()

    paths = {
        "hotkey": source / "src/ui/hotkey_overlay.rs",
        "mru": source / "src/ui/mru.rs",
        "screenshot": source / "src/ui/screenshot_ui.rs",
        "input": source / "src/input/mod.rs",
        "niri": source / "src/niri.rs",
        "cargo": source / "Cargo.toml",
        "session": source / "resources/niri-session",
    }
    for path in paths.values():
        if not path.is_file():
            parser.error(f"not a niri source checkout; missing {path}")

    original = {name: path.read_text(encoding="utf-8") for name, path in paths.items()}
    transformed = dict(original)

    style_markers = [
        "fn paint_rounded_panel(" in original[name]
        for name in ("hotkey", "mru", "screenshot")
    ]
    if any(style_markers) and not all(style_markers):
        raise TransformError("source tree has a partially applied overlay style")
    if not all(style_markers):
        transformed["hotkey"] = transform_hotkeys(original["hotkey"])
        transformed["mru"] = transform_mru(original["mru"])
        transformed["screenshot"] = transform_screenshot(original["screenshot"])

    gesture_markers = (
        'features = ["libinput_1_28"]' in original["cargo"],
        "config_3fg_drag_set_enabled" in original["input"],
        "gesture_pinch_4f_triggered" in original["niri"],
    )
    if any(gesture_markers) and not all(gesture_markers):
        raise TransformError("source tree has a partially applied gesture patch")
    if not all(gesture_markers):
        transformed["cargo"], transformed["input"], transformed["niri"] = (
            transform_gestures(original["cargo"], original["input"], original["niri"])
        )

    transformed["session"] = transform_session(original["session"])

    # All transformations succeeded in memory; only now write changed files.
    changed = []
    for name, text in transformed.items():
        if text != original[name]:
            paths[name].write_text(text, encoding="utf-8")
            changed.append(paths[name].relative_to(source))

    if changed:
        for path in changed:
            print(f"updated {path}")
    else:
        print("all niri tweaks are already applied")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TransformError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
