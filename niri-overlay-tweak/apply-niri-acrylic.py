#!/usr/bin/env python3
"""Apply the Mica style and local session fixes to niri.

The transformation is intentionally strict: every expected upstream fragment
for the visual changes must occur exactly once. If a future niri release
changes the relevant UI code, the script aborts before writing any source
file. Session fixes are conditional and are skipped when their exact upstream
anchors no longer exist.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


NIRI_SESSION_IMPORT_OLD = "    systemctl --user import-environment"
NIRI_SESSION_IMPORT_NEW = (
    "    systemctl --user import-environment "
    "$(printenv | cut -d'=' -f1 | tr '\\n' ' ')"
)
NIRI_SESSION_START = "    systemctl --user --wait start niri.service"
NIRI_SESSION_VT_CLEAR_MARKER = (
    "    # Clear retained Linux VT text immediately before niri takes over."
)
NIRI_SESSION_VT_CLEAR_LINES = (
    NIRI_SESSION_VT_CLEAR_MARKER,
    "    # Leave pseudo-terminals and nested sessions untouched.",
    '    case "$(tty 2>/dev/null)" in',
    "    /dev/tty[0-9]*)",
    "        printf '\\033[H\\033[2J\\033[3J' > /dev/tty 2>/dev/null || :",
    "        ;;",
    "    esac",
    "",
)


HOTKEY_HELPERS = r'''
fn rounded_rectangle(cr: &cairo::Context, x: f64, y: f64, width: f64, height: f64, radius: f64) {
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

fn paint_mica_panel(
    cr: &cairo::Context,
    width: i32,
    height: i32,
    scale: f64,
) -> Result<(), cairo::Error> {
    let width = f64::from(width);
    let height = f64::from(height);
    let radius = CORNER_RADIUS * scale;

    // Mica-like blue-to-green base: soft, bright and more opaque than acrylic.
    rounded_rectangle(cr, 0., 0., width, height, radius);
    let base = cairo::LinearGradient::new(0., 0., width, height);
    base.add_color_stop_rgba(0., 0.820, 0.910, 0.970, 0.97);
    base.add_color_stop_rgba(0.52, 0.890, 0.950, 0.930, 0.96);
    base.add_color_stop_rgba(1., 0.820, 0.930, 0.850, 0.95);
    cr.set_source(&base)?;
    cr.fill()?;

    // A broad top-left glow gives the material quiet environmental depth.
    cr.save()?;
    rounded_rectangle(cr, 0., 0., width, height, radius);
    cr.clip();
    let glow_radius = width.max(height) * 0.9;
    let glow = cairo::RadialGradient::new(0., 0., 0., 0., 0., glow_radius);
    glow.add_color_stop_rgba(0., 1., 1., 1., 0.24);
    glow.add_color_stop_rgba(1., 0.82, 0.88, 0.92, 0.0);
    cr.set_source(&glow)?;
    cr.paint()?;
    cr.restore()?;

    let border_width = (f64::from(BORDER) * scale).round().max(1.);
    let inset = border_width / 2.;
    rounded_rectangle(
        cr,
        inset,
        inset,
        width - border_width,
        height - border_width,
        radius - inset,
    );
    cr.set_source_rgba(1., 1., 1., 0.84);
    cr.set_line_width(border_width);
    cr.stroke()
}
'''.lstrip()


MRU_HELPERS = HOTKEY_HELPERS.replace(
    "let radius = CORNER_RADIUS * scale;",
    "let radius = PANEL_CORNER_RADIUS * scale;",
).replace(
    "f64::from(BORDER)",
    "f64::from(PANEL_BORDER)",
)


SCREENSHOT_HELPERS = HOTKEY_HELPERS.replace(
    "let radius = CORNER_RADIUS * scale;",
    "let radius = PANEL_CORNER_RADIUS * scale;",
)


class TransformError(RuntimeError):
    pass


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise TransformError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise TransformError(f"{label}: expected exactly one match, found {count}")
    return updated


def transform_niri_session_import(text: str) -> tuple[str, str]:
    """Replace niri's deprecated blanket systemd environment import.

    Passing every current variable name preserves niri's existing import-all
    behaviour while avoiding systemd's no-argument deprecation warning. The
    exact-line checks keep the transform idempotent and avoid guessing if
    upstream changes the command independently.
    """

    lines = text.splitlines(keepends=True)
    old_indexes = [
        index
        for index, line in enumerate(lines)
        if line.rstrip("\r\n") == NIRI_SESSION_IMPORT_OLD
    ]
    new_indexes = [
        index
        for index, line in enumerate(lines)
        if line.rstrip("\r\n") == NIRI_SESSION_IMPORT_NEW
    ]

    if len(old_indexes) > 1:
        raise TransformError(
            "niri-session environment import: expected at most one deprecated "
            f"command, found {len(old_indexes)}"
        )
    if len(new_indexes) > 1:
        raise TransformError(
            "niri-session environment import: expected at most one replacement "
            f"command, found {len(new_indexes)}"
        )
    if old_indexes and new_indexes:
        raise TransformError(
            "niri-session environment import: deprecated and replacement "
            "commands are both active"
        )
    if new_indexes:
        return text, "already-applied"
    if not old_indexes:
        return text, "not-needed"

    index = old_indexes[0]
    line = lines[index]
    if line.endswith("\r\n"):
        ending = "\r\n"
    elif line.endswith("\n"):
        ending = "\n"
    elif line.endswith("\r"):
        ending = "\r"
    else:
        ending = ""
    lines[index] = NIRI_SESSION_IMPORT_NEW + ending
    return "".join(lines), "applied"


def transform_niri_session_vt_clear(text: str) -> tuple[str, str]:
    """Clear retained Linux VT contents at the final graphical handoff.

    The insertion is anchored to niri's exact systemd start command. It is
    restricted to numbered Linux virtual terminals, so launching niri from a
    pseudo-terminal or nested session does not clear that terminal.
    """

    lines = text.splitlines(keepends=True)
    start_indexes = [
        index
        for index, line in enumerate(lines)
        if line.rstrip("\r\n") == NIRI_SESSION_START
    ]
    marker_indexes = [
        index
        for index, line in enumerate(lines)
        if line.rstrip("\r\n") == NIRI_SESSION_VT_CLEAR_MARKER
    ]

    if len(start_indexes) > 1:
        raise TransformError(
            "niri-session VT clear: expected at most one systemd start command, "
            f"found {len(start_indexes)}"
        )
    if len(marker_indexes) > 1:
        raise TransformError(
            "niri-session VT clear: expected at most one inserted marker, "
            f"found {len(marker_indexes)}"
        )
    if marker_indexes:
        if len(start_indexes) != 1 or marker_indexes[0] >= start_indexes[0]:
            raise TransformError("niri-session VT clear: partial or invalid insertion")
        return text, "already-applied"
    if not start_indexes:
        return text, "not-needed"

    index = start_indexes[0]
    line = lines[index]
    if line.endswith("\r\n"):
        ending = "\r\n"
    elif line.endswith("\n"):
        ending = "\n"
    elif line.endswith("\r"):
        ending = "\r"
    else:
        ending = ""
    separator = ending or "\n"
    insertion = [item + separator for item in NIRI_SESSION_VT_CLEAR_LINES]
    insertion.append(NIRI_SESSION_START + ending)
    lines[index : index + 1] = insertion
    return "".join(lines), "applied"


def transform_hotkeys(text: str) -> str:
    text = sub_once(
        text,
        r"^const PADDING: i32 = \d+;$",
        "const PADDING_X: i32 = 24;\nconst PADDING_Y: i32 = 18;",
        "Hotkeys padding",
    )
    text = sub_once(text, r'^const FONT: &str = "[^"]+";$', 'const FONT: &str = "Inter 15px";', "Hotkeys font")
    text = sub_once(
        text,
        r"^const BORDER: i32 = \d+;$",
        "const BORDER: i32 = 1;\nconst CORNER_RADIUS: f64 = 18.;",
        "Hotkeys border/radius",
    )
    text = sub_once(text, r"^const LINE_INTERVAL: i32 = \d+;$", "const LINE_INTERVAL: i32 = 6;", "Hotkeys line spacing")
    text = replace_once(
        text,
        "    let padding: i32 = to_physical_precise_round(scale, PADDING);",
        "    let padding_x: i32 = to_physical_precise_round(scale, PADDING_X);\n"
        "    let padding_y: i32 = to_physical_precise_round(scale, PADDING_Y);",
        "Hotkeys scaled padding",
    )
    text = replace_once(
        text,
        "    let mut width = key_width + padding + action_width;",
        "    let mut width = key_width + padding_x + action_width;",
        "Hotkeys content width",
    )
    text = replace_once(
        text,
        "        + title_size.1\n        + padding;",
        "        + title_size.1\n        + padding_y;",
        "Hotkeys title spacing",
    )
    text = replace_once(
        text,
        "    width += padding * 2;\n    height += padding * 2;",
        "    width += padding_x * 2;\n    height += padding_y * 2;",
        "Hotkeys outer padding",
    )
    text = replace_once(
        text,
        "    cr.move_to(padding.into(), padding.into());",
        "    cr.move_to(padding_x.into(), padding_y.into());",
        "Hotkeys initial position",
    )
    text = replace_once(
        text,
        "    cr.move_to(((width - title_size.0) / 2).into(), padding.into());",
        "    cr.move_to(((width - title_size.0) / 2).into(), padding_y.into());",
        "Hotkeys title position",
    )
    text = replace_once(
        text,
        "    cr.move_to(padding.into(), (padding + title_size.1 + padding).into());",
        "    cr.move_to(\n"
        "        padding_x.into(),\n"
        "        (padding_y + title_size.1 + padding_y).into(),\n"
        "    );",
        "Hotkeys entries position",
    )
    text = replace_once(
        text,
        "        cr.rel_move_to((key_width + padding).into(), 0.);",
        "        cr.rel_move_to((key_width + padding_x).into(), 0.);",
        "Hotkeys action position",
    )
    text = replace_once(
        text,
        "            (-(key_width + padding)).into(),",
        "            (-(key_width + padding_x)).into(),",
        "Hotkeys next-row position",
    )
    text = replace_once(text, "\nfn render(\n", f"\n{HOTKEY_HELPERS}\nfn render(\n", "Hotkeys render function")
    text = replace_once(
        text,
        '    attrs.insert(AttrString::new_family("Monospace"));\n'
        "    attrs.insert(AttrColor::new_background(12000, 12000, 12000));",
        '    attrs.insert(AttrString::new_family("Inter"));\n'
        "    attrs.insert(AttrColor::new_background(54000, 58600, 57000));",
        "Hotkeys keycap style",
    )
    action_keycap_old = "<span face='monospace' bgcolor='#000000'>{}</span>"
    action_keycap_new = (
        "<span face='Inter' weight='600' fgcolor='#000000' "
        "bgcolor='#D2E4DE'>{}</span>"
    )
    if text.count(action_keycap_old) != 2:
        raise TransformError("Hotkeys action keycap style: expected exactly two matches")
    text = text.replace(action_keycap_old, action_keycap_new)
    text = replace_once(
        text,
        "    cr.set_source_rgb(0.1, 0.1, 0.1);\n    cr.paint()?;",
        "    paint_mica_panel(&cr, width, height, scale)?;",
        "Hotkeys background",
    )
    text = replace_once(
        text,
        "    layout.set_font_description(Some(&font));\n\n    cr.set_source_rgb(1., 1., 1.);",
        "    layout.set_font_description(Some(&font));\n\n    cr.set_source_rgb(0., 0., 0.);",
        "Hotkeys text colour",
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
        "Hotkeys original square border",
    )
    return text


def transform_mru(text: str) -> str:
    text = sub_once(
        text,
        r"^const PANEL_PADDING: i32 = \d+;$",
        "const PANEL_PADDING_X: i32 = 24;\nconst PANEL_PADDING_Y: i32 = 18;",
        "Scope padding",
    )
    text = sub_once(
        text,
        r"^const PANEL_BORDER: i32 = \d+;$",
        "const PANEL_BORDER: i32 = 1;\n\n/// Corner radius of the scope indication panel.\nconst PANEL_CORNER_RADIUS: f64 = 16.;",
        "Scope border/radius",
    )
    text = sub_once(text, r'^const FONT: &str = "[^"]+";$', 'const FONT: &str = "Inter 15px";', "Scope font")
    text = replace_once(
        text,
        "            let padding = round_logical_in_physical(scale, f64::from(PANEL_PADDING));",
        "            let padding = round_logical_in_physical(scale, f64::from(PANEL_PADDING_Y));",
        "Scope screen offset",
    )
    text = sub_once(
        text,
        r'^        let span_unselected = "[^"]+";$',
        '        let span_unselected = "<span fgcolor=\'#000000\'>";',
        "Scope secondary text",
    )
    text = sub_once(
        text,
        r'^        let span_shortcut = "[^"]+";$',
        '        let span_shortcut = "<span face=\'Inter\' weight=\'600\' fgcolor=\'#000000\' bgcolor=\'#D2E4DE\' letter_spacing=\'5000\'><b>";',
        "Scope keycap style",
    )
    text = replace_once(
        text,
        "\nfn render_panel(",
        f"\n{MRU_HELPERS}\nfn render_panel(",
        "Scope render function",
    )
    text = replace_once(
        text,
        "    let padding: i32 = to_physical_precise_round(scale, PANEL_PADDING);",
        "    let padding_x: i32 = to_physical_precise_round(scale, PANEL_PADDING_X);\n"
        "    let padding_y: i32 = to_physical_precise_round(scale, PANEL_PADDING_Y);",
        "Scope scaled padding",
    )
    text = replace_once(
        text,
        "    width += padding * 2;\n    height += padding * 2;",
        "    width += padding_x * 2;\n    height += padding_y * 2;",
        "Scope outer padding",
    )
    text = replace_once(
        text,
        "    let padding = f64::from(padding);\n\n    cr.move_to(padding, padding);",
        "    let padding_x = f64::from(padding_x);\n"
        "    let padding_y = f64::from(padding_y);\n\n"
        "    cr.move_to(padding_x, padding_y);",
        "Scope content position",
    )
    text = replace_once(
        text,
        "    cr.set_source_rgb(0.1, 0.1, 0.1);\n    cr.paint()?;",
        "    paint_mica_panel(&cr, width, height, scale)?;",
        "Scope background",
    )
    text = replace_once(
        text,
        "    layout.set_markup(text);\n\n    cr.set_source_rgb(1., 1., 1.);\n"
        "    pangocairo::functions::show_layout(&cr, &layout);",
        "    layout.set_markup(text);\n\n    cr.set_source_rgb(0., 0., 0.);\n"
        "    pangocairo::functions::show_layout(&cr, &layout);",
        "Scope text colour",
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
        "Scope original square border",
    )
    return text


def transform_screenshot(text: str) -> str:
    text = sub_once(
        text,
        r"^const PADDING: i32 = \d+;$",
        "const PADDING_X: i32 = 24;\nconst PADDING_Y: i32 = 18;",
        "Screenshot padding",
    )
    text = sub_once(
        text,
        r'^const FONT: &str = "[^"]+";$',
        'const FONT: &str = "Inter 15px";',
        "Screenshot font",
    )
    text = sub_once(
        text,
        r"^const BORDER: i32 = \d+;$",
        "const BORDER: i32 = 1;\nconst PANEL_CORNER_RADIUS: f64 = 16.;",
        "Screenshot border/radius",
    )
    text = text.replace(
        "<span face='mono' bgcolor='#2C2C2C'> Space </span>",
        "<span face='Inter' weight='600' fgcolor='#000000' "
        "bgcolor='#D2E4DE' letter_spacing='2500'> Space </span>",
    )
    text = text.replace(
        "<span face='mono' bgcolor='#2C2C2C'> P </span>",
        "<span face='Inter' weight='600' fgcolor='#000000' "
        "bgcolor='#D2E4DE' letter_spacing='2500'> P </span>",
    )
    if text.count("face='Inter' weight='600'") != 4:
        raise TransformError("Screenshot keycap style: expected exactly four replacements")

    text = replace_once(
        text,
        "    let padding: i32 = to_physical_precise_round(scale, PADDING);\n"
        "    let x = max(0, (output_data.size.w - panel_size.w) / 2);\n"
        "    let y = max(0, output_data.size.h - panel_size.h - padding * 2);",
        "    let padding_y: i32 = to_physical_precise_round(scale, PADDING_Y);\n"
        "    let x = max(0, (output_data.size.w - panel_size.w) / 2);\n"
        "    let y = max(0, output_data.size.h - panel_size.h - padding_y * 2);",
        "Screenshot screen offset",
    )
    text = replace_once(
        text,
        "    let padding: i32 = to_physical_precise_round(scale, PADDING);\n"
        "    let radius = to_physical_precise_round::<i32>(scale, RADIUS) - 2;\n\n"
        "    let xc = padding + radius;",
        "    let padding_x: i32 = to_physical_precise_round(scale, PADDING_X);\n"
        "    let radius = to_physical_precise_round::<i32>(scale, RADIUS) - 2;\n\n"
        "    let xc = padding_x + radius;",
        "Screenshot capture hitbox",
    )
    text = replace_once(
        text,
        "\nfn render_panel(",
        f"\n{SCREENSHOT_HELPERS}\nfn render_panel(",
        "Screenshot render function",
    )
    text = replace_once(
        text,
        "    let padding: i32 = to_physical_precise_round(scale, PADDING);",
        "    let padding_x: i32 = to_physical_precise_round(scale, PADDING_X);\n"
        "    let padding_y: i32 = to_physical_precise_round(scale, PADDING_Y);",
        "Screenshot scaled padding",
    )
    text = replace_once(
        text,
        "    width += padding + radius * 2 + padding - half_border_width + padding;\n"
        "    height = max(height, radius * 2);\n"
        "    height += padding * 2;",
        "    width += padding_x + radius * 2 + padding_x - half_border_width + padding_x;\n"
        "    height = max(height, radius * 2);\n"
        "    height += padding_y * 2;",
        "Screenshot panel dimensions",
    )
    text = replace_once(
        text,
        "    cr.set_source_rgb(0.1, 0.1, 0.1);\n    cr.paint()?;",
        "    paint_mica_panel(&cr, width, height, scale)?;",
        "Screenshot background",
    )
    text = replace_once(
        text,
        "    let padding = f64::from(padding);\n"
        "    let half_border_width = f64::from(half_border_width);",
        "    let padding_x = f64::from(padding_x);\n"
        "    let padding_y = f64::from(padding_y);\n"
        "    let half_border_width = f64::from(half_border_width);",
        "Screenshot floating padding",
    )
    text = replace_once(
        text,
        "    cr.arc(padding + r, yc, r, 0., TAU);\n"
        "    cr.set_source_rgb(1., 1., 1.);",
        "    cr.arc(padding_x + r, yc, r, 0., TAU);\n"
        "    cr.set_source_rgb(0., 0., 0.);",
        "Screenshot capture outer ring",
    )
    text = replace_once(
        text,
        "    cr.arc(padding + r, yc, r - circle_stroke, 0., TAU);\n"
        "    cr.set_source_rgb(0.1, 0.1, 0.1);",
        "    cr.arc(padding_x + r, yc, r - circle_stroke, 0., TAU);\n"
        "    cr.set_source_rgb(0.84, 0.91, 0.88);",
        "Screenshot capture middle ring",
    )
    text = replace_once(
        text,
        "    cr.arc(padding + r, yc, r - circle_stroke * 2., 0., TAU);\n"
        "    cr.set_source_rgb(1., 1., 1.);",
        "    cr.arc(padding_x + r, yc, r - circle_stroke * 2., 0., TAU);\n"
        "    cr.set_source_rgb(0., 0., 0.);",
        "Screenshot capture centre",
    )
    text = replace_once(
        text,
        "    cr.move_to(padding + r * 2. + padding - half_border_width, padding);",
        "    cr.move_to(\n"
        "        padding_x + r * 2. + padding_x - half_border_width,\n"
        "        padding_y,\n"
        "    );",
        "Screenshot text position",
    )
    text = replace_once(
        text,
        "    cr.set_source_rgb(1., 1., 1.);\n"
        "    pangocairo::functions::show_layout(&cr, &layout);",
        "    cr.set_source_rgb(0., 0., 0.);\n"
        "    pangocairo::functions::show_layout(&cr, &layout);",
        "Screenshot text colour",
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
        "Screenshot original square border",
    )
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="path to the niri source checkout")
    args = parser.parse_args()

    source = args.source.expanduser().resolve()
    hotkey_path = source / "src/ui/hotkey_overlay.rs"
    mru_path = source / "src/ui/mru.rs"
    screenshot_path = source / "src/ui/screenshot_ui.rs"
    session_path = source / "resources/niri-session"
    style_paths = (hotkey_path, mru_path, screenshot_path)
    for path in (*style_paths, session_path):
        if not path.is_file():
            parser.error(f"not a niri source checkout; missing {path}")

    originals = {
        hotkey_path: hotkey_path.read_text(encoding="utf-8"),
        mru_path: mru_path.read_text(encoding="utf-8"),
        screenshot_path: screenshot_path.read_text(encoding="utf-8"),
        session_path: session_path.read_text(encoding="utf-8"),
    }
    style_patched = ["fn paint_mica_panel(" in originals[path] for path in style_paths]
    if any(style_patched) and not all(style_patched):
        raise TransformError("source tree is only partially patched; reset it before retrying")
    if any("fn paint_acrylic_panel(" in originals[path] for path in style_paths):
        raise TransformError(
            "legacy Acrylic changes detected; run update-build-install.sh so niri-src "
            "is reset before applying the Mica style"
        )

    # Complete every transform in memory first. No file is written if one fails.
    transformed = dict(originals)
    if not all(style_patched):
        transformed.update(
            {
                hotkey_path: transform_hotkeys(originals[hotkey_path]),
                mru_path: transform_mru(originals[mru_path]),
                screenshot_path: transform_screenshot(originals[screenshot_path]),
            }
        )
    transformed[session_path], import_status = transform_niri_session_import(
        originals[session_path]
    )
    transformed[session_path], vt_clear_status = transform_niri_session_vt_clear(
        transformed[session_path]
    )

    changed = {
        path: text for path, text in transformed.items() if text != originals[path]
    }
    for path, text in changed.items():
        path.write_text(text, encoding="utf-8")

    if not all(style_patched):
        print(f"applied Mica style to {hotkey_path.relative_to(source)}")
        print(f"applied Mica style to {mru_path.relative_to(source)}")
        print(f"applied Mica style to {screenshot_path.relative_to(source)}")
    else:
        print("niri Mica style is already applied")

    if import_status == "applied":
        print(f"updated systemd environment import in {session_path.relative_to(source)}")
    elif import_status == "already-applied":
        print("niri-session systemd environment fix is already applied")
    else:
        print("deprecated niri-session environment import not found; left it unchanged")

    if vt_clear_status == "applied":
        print(f"added final Linux VT clear to {session_path.relative_to(source)}")
    elif vt_clear_status == "already-applied":
        print("niri-session final Linux VT clear is already applied")
    else:
        print("niri-session systemd start anchor not found; did not add a VT clear")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TransformError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
