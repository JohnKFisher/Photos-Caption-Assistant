from __future__ import annotations

from pathlib import Path

import generate_mockups as gm


OUT_DIR = Path("/Users/jkfisher/Resilio Sync/Family Documents/Codex/PhotoDescriptionCreator/output/mockups/main_screen_treatments")
W = gm.W
H = gm.H


def album_browser(frame: gm.Frame, x: float, y: float, w: float, h: float, fill: str, border: str, ink: str, muted: str, active_fill: str) -> str:
    parts = gm.labeled_card(x, y, w, h, "Albums", "Chooser stays visible.", fill, border, ink, muted)
    names = ["Family Spring Walk", "Birthday Dinner", "Lake Weekend", "Garden May", "Videos To Review"]
    counts = ["1248 items", "382 items", "460 items", "278 items", "91 items"]
    card_y = y + 78
    for idx, (name, count) in enumerate(zip(names, counts)):
        row_fill = active_fill if idx == 0 else "#ffffff"
        row_border = "#d4e0e8" if idx == 0 else border
        parts.append(gm.rect(x + 16, card_y + idx * 102, w - 32, 80, row_fill, rx=18, stroke=row_border))
        parts.append(gm.text(x + 34, card_y + 34 + idx * 102, name, 16, ink, family=gm.FONT_UI, weight=650))
        parts.append(gm.text(x + 34, card_y + 56 + idx * 102, count, 13, muted, family=gm.FONT_UI, weight=500))
    return gm.group(parts)


def setup_stack(frame: gm.Frame, x: float, y: float, w: float, h: float, fill: str, border: str, ink: str, muted: str, accent: str, title_text: str, subtitle: str) -> str:
    parts = gm.labeled_card(x, y, w, h, title_text, subtitle, fill, border, ink, muted)
    rows = [
        ("Source", "Album / Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Processing Order", "Photos order (recommended)"),
        ("Overwrite Behavior", "Preserve external metadata unless confirmed"),
        ("Queued Albums", "Optional secondary workflow"),
    ]
    row_y = y + 80
    for idx, (label, body) in enumerate(rows):
        parts += gm.mini_setting_card(
            x + 22,
            row_y + idx * 104,
            w - 44,
            88,
            label,
            body,
            "#f8fafc",
            "#e4ebf0",
            ink,
            muted,
            icon_fill=accent,
        )
    parts += gm.progress_bar(x + 22, y + h - 64, w - 44, 15, "#4c7ea4", "#dbe6ee", fraction=0.66)
    parts.append(gm.text(x + 22, y + h - 28, "Run progress and preview stay visible without hiding safeguards.", 14, muted, family=gm.FONT_UI))
    return gm.group(parts)


def right_summary(frame: gm.Frame, x: float, y: float, w: float, h: float, fill: str, border: str, ink: str, muted: str, accent: str, preview_h: float, warning_y: float) -> str:
    parts = gm.labeled_card(x, y, w, h, "Run Summary", "Pinned safeguards stay readable before Start.", fill, border, ink, muted)
    parts.append(gm.text(x + 24, y + 92, "Album  •  Family Spring Walk", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.text(x + 24, y + 132, "Estimated 1,248 items", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.text(x + 24, y + 172, "Writes  •  captions + keywords", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.rect(x + 24, y + warning_y, w - 48, 60, "#f8efcf", rx=16, stroke="#ead48c"))
    parts.append(gm.text(x + 44, y + warning_y + 37, "Confirmation required before broader metadata overwrite.", 14, "#6f581d", family=gm.FONT_UI, weight=650))
    parts += gm.preview_tile(x, y + h - preview_h, w, preview_h, fill, border, ink, muted, accent)
    return gm.group(parts)


def variant_a1(frame: gm.Frame) -> str:
    bg = "#eef2f5"
    ink = "#182430"
    muted = "#617180"
    border = "#d8e0e8"
    accent = "#90b5ce"
    parts = gm.window_shell(frame, bg, border, ink, "A1 Balanced")
    parts.append(gm.rect(frame.px(38), frame.py(92), frame.pw(1524), frame.ph(104), "#fbfcfd", rx=26, stroke="#dde4ea"))
    parts.append(gm.text(frame.px(64), frame.py(136), "Quiet Workbench — Balanced", frame.font(25), ink, family=gm.FONT_SANS, weight=760))
    parts.append(gm.text(frame.px(64), frame.py(170), "Even emphasis across browser, setup, summary, and preview.", frame.font(15), muted, family=gm.FONT_UI))
    parts += gm.pill(frame.px(1220), frame.py(114), frame.pw(120), frame.ph(30), "Low risk", "#edf3f7", "#4b7ea3")
    parts += gm.pill(frame.px(1352), frame.py(114), frame.pw(182), frame.ph(30), "Good first build", "#edf3f7", "#4b7ea3")

    browser_x = frame.px(42)
    setup_x = frame.px(308)
    right_x = frame.px(1088)
    y0 = frame.py(220)
    h0 = frame.ph(714)
    parts.append(album_browser(frame, browser_x, y0, frame.pw(240), h0, "#f9fbfc", border, ink, muted, "#eaf2f7"))
    parts.append(setup_stack(frame, setup_x, y0, frame.pw(748), h0, "#ffffff", border, ink, muted, accent, "Setup", "Quiet vertical stack with stronger hierarchy."))
    parts.append(right_summary(frame, right_x, y0, frame.pw(470), h0, "#ffffff", border, ink, muted, "#4b7ea3", preview_h=360, warning_y=204))
    return gm.group(parts)


def variant_a2(frame: gm.Frame) -> str:
    bg = "#ecf1f4"
    ink = "#1a2833"
    muted = "#677685"
    border = "#dce5eb"
    accent = "#9bbfd4"
    parts = gm.window_shell(frame, bg, border, ink, "A2 Soft")
    parts.append(gm.circle(frame.px(1340), frame.py(170), frame.ph(180), "#d7ebf3", opacity=0.42))
    parts.append(gm.circle(frame.px(240), frame.py(850), frame.ph(220), "#f5fbfd", opacity=0.55))
    parts.append(gm.rect(frame.px(38), frame.py(92), frame.pw(1524), frame.ph(104), "#ffffff", rx=26, stroke="#e6eef2", opacity=0.76))
    parts.append(gm.text(frame.px(64), frame.py(136), "Quiet Workbench — Softened", frame.font(25), ink, family=gm.FONT_SANS, weight=760))
    parts.append(gm.text(frame.px(64), frame.py(170), "Same structure, slightly more atmospheric and glassy.", frame.font(15), muted, family=gm.FONT_UI))
    browser_x = frame.px(46)
    setup_x = frame.px(306)
    right_x = frame.px(1102)
    y0 = frame.py(222)
    h0 = frame.ph(706)
    parts.append(album_browser(frame, browser_x, y0, frame.pw(220), h0, "#ffffff", border, ink, muted, "#eef6fa"))
    parts.append(setup_stack(frame, setup_x, y0, frame.pw(772), h0, "#ffffff", border, ink, muted, accent, "Setup", "More softness without losing the production structure."))
    parts.append(right_summary(frame, right_x, y0, frame.pw(454), h0, "#ffffff", border, ink, muted, "#4a8bb1", preview_h=350, warning_y=196))
    parts.append(gm.rect(frame.px(42), frame.py(944), frame.pw(1514), frame.ph(36), "#ffffff", rx=18, stroke="#e3ebf0", opacity=0.72))
    parts.append(gm.text(frame.px(70), frame.py(967), "Visual tone is gentler, but the safety summary still reads first.", frame.font(14), muted, family=gm.FONT_UI))
    return gm.group(parts)


def variant_a3(frame: gm.Frame) -> str:
    bg = "#eef2f5"
    ink = "#17232d"
    muted = "#60707c"
    border = "#d7e0e8"
    accent = "#8fb3ca"
    parts = gm.window_shell(frame, bg, border, ink, "A3 Preview-Forward")
    parts.append(gm.rect(frame.px(38), frame.py(92), frame.pw(1524), frame.ph(104), "#fbfcfd", rx=26, stroke="#dde4ea"))
    parts.append(gm.text(frame.px(64), frame.py(136), "Quiet Workbench — Preview Forward", frame.font(25), ink, family=gm.FONT_SANS, weight=760))
    parts.append(gm.text(frame.px(64), frame.py(170), "Keeps the calm structure but gives the finished output more presence.", frame.font(15), muted, family=gm.FONT_UI))
    parts += gm.pill(frame.px(1298), frame.py(114), frame.pw(236), frame.ph(30), "Best if preview matters most", "#edf3f7", "#4b7ea3")

    browser_x = frame.px(42)
    setup_x = frame.px(308)
    right_x = frame.px(1066)
    y0 = frame.py(220)
    h0 = frame.ph(714)
    parts.append(album_browser(frame, browser_x, y0, frame.pw(232), h0, "#f9fbfc", border, ink, muted, "#eaf2f7"))
    parts.append(setup_stack(frame, setup_x, y0, frame.pw(720), h0, "#ffffff", border, ink, muted, accent, "Setup", "Slightly tighter setup to make room for a larger result pane."))
    parts += gm.labeled_card(right_x, y0, frame.pw(492), h0, "Run Summary", "Preview gets more of the screen without losing safeguards.", "#ffffff", border, ink, muted)
    parts.append(gm.text(right_x + 24, y0 + 88, "Album  •  Family Spring Walk", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.text(right_x + 24, y0 + 126, "Estimated 1,248 items", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.rect(right_x + 24, y0 + 154, frame.pw(444), 56, "#f8efcf", rx=16, stroke="#ead48c"))
    parts.append(gm.text(right_x + 44, y0 + 189, "Confirmation required before broader metadata overwrite.", 14, "#6f581d", family=gm.FONT_UI, weight=650))
    parts += gm.preview_tile(right_x, y0 + 238, frame.pw(492), 478, "#ffffff", border, ink, muted, "#4b7ea3")
    return gm.group(parts)


VARIANTS = [
    ("a_refined_1_balanced", "A Refined 1 — Balanced", variant_a1),
    ("a_refined_2_soft", "A Refined 2 — Soft", variant_a2),
    ("a_refined_3_preview_forward", "A Refined 3 — Preview Forward", variant_a3),
]


def final_preview_forward(frame: gm.Frame) -> str:
    bg = "#eef3f6"
    ink = "#17232d"
    muted = "#5f707d"
    border = "#d8e1e9"
    accent = "#4b7ea5"
    soft = "#eef5f9"
    parts = gm.window_shell(frame, bg, border, ink, "Locked Concept")

    parts.append(gm.rect(frame.px(34), frame.py(88), frame.pw(1532), frame.ph(108), "#fbfcfd", rx=28, stroke="#dee6ec"))
    parts.append(gm.text(frame.px(62), frame.py(134), "Quiet Workbench — Preview Forward", frame.font(27), ink, family=gm.FONT_SANS, weight=780))
    parts.append(gm.text(frame.px(62), frame.py(168), "Album browser stays pinned, safeguards stay visible, and the finished result gets more of the screen.", frame.font(16), muted, family=gm.FONT_UI))
    parts += gm.pill(frame.px(1286), frame.py(114), frame.pw(248), frame.ph(32), "Chosen direction", soft, accent)

    browser_x = frame.px(40)
    browser_y = frame.py(216)
    browser_w = frame.pw(224)
    browser_h = frame.ph(700)
    parts.append(album_browser(frame, browser_x, browser_y, browser_w, browser_h, "#f9fbfc", border, ink, muted, "#eaf2f7"))

    setup_x = frame.px(286)
    setup_y = browser_y
    setup_w = frame.pw(624)
    setup_h = browser_h
    parts += gm.labeled_card(setup_x, setup_y, setup_w, setup_h, "Setup", "Slightly tightened setup to make room for a larger result pane.", "#ffffff", border, ink, muted)
    rows = [
        ("Source", "Album / Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Processing Order", "Photos order (recommended)"),
        ("Overwrite Behavior", "Preserve external metadata unless confirmed"),
        ("Queued Albums", "Optional secondary workflow"),
    ]
    row_y = setup_y + 82
    for idx, (label, body) in enumerate(rows):
        parts += gm.mini_setting_card(
            setup_x + 22,
            row_y + idx * 104,
            setup_w - 44,
            88,
            label,
            body,
            "#f8fafc",
            "#e4ebf0",
            ink,
            muted,
            icon_fill="#8fb4ca",
        )
    parts += gm.progress_bar(setup_x + 22, setup_y + setup_h - 66, setup_w - 44, 16, accent, "#dce7ee", fraction=0.66)
    parts.append(gm.text(setup_x + 22, setup_y + setup_h - 30, "Run progress remains visible here even when the right pane expands.", 14, muted, family=gm.FONT_UI))

    right_x = frame.px(932)
    right_y = browser_y
    right_w = frame.pw(626)
    right_h = browser_h
    parts += gm.labeled_card(right_x, right_y, right_w, right_h, "Run Summary + Preview", "The right pane carries both the safety summary and the result, with preview clearly prioritized.", "#ffffff", border, ink, muted)
    parts.append(gm.text(right_x + 24, right_y + 86, "Album  •  Family Spring Walk", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.text(right_x + 24, right_y + 122, "Estimated 1,248 items", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.text(right_x + 24, right_y + 158, "Writes  •  captions + keywords", 16, ink, family=gm.FONT_UI, weight=650))
    parts.append(gm.rect(right_x + 24, right_y + 188, right_w - 48, 62, "#f8efcf", rx=16, stroke="#ead48c"))
    parts.append(gm.text(right_x + 46, right_y + 226, "Confirmation required before broader metadata overwrite.", 14, "#6f581d", family=gm.FONT_UI, weight=650))

    preview_shell_y = right_y + 276
    preview_shell_h = right_h - 364
    parts.append(gm.rect(right_x + 18, preview_shell_y, right_w - 36, preview_shell_h, "#f9fbfc", rx=24, stroke="#dfe7ed"))
    parts.append(gm.text(right_x + 40, preview_shell_y + 36, "Last Completed Item", 21, ink, family=gm.FONT_SANS, weight=720))
    parts.append(gm.text(right_x + 40, preview_shell_y + 62, "Main-screen emphasis moves here without turning the screen into immersive mode.", 14, muted, family=gm.FONT_UI))
    img_x = right_x + 40
    img_y = preview_shell_y + 88
    img_w = (right_w - 96) * 0.44
    img_h = preview_shell_h - 128
    parts.append(gm.rect(img_x, img_y, img_w, img_h, "#dce8f0", rx=22, stroke="#d0dee8"))
    parts.append(gm.circle(img_x + img_w * 0.5, img_y + img_h * 0.36, min(img_w, img_h) * 0.17, "#aec6d5"))
    parts.append(gm.rect(img_x + 18, img_y + img_h - 82, img_w - 36, 58, "#9fbcd0", rx=18))
    tx = img_x + img_w + 28
    parts.append(gm.text(tx, img_y + 24, "IMG_1187.HEIC", 20, ink, family=gm.FONT_UI, weight=700))
    parts.append(gm.text(tx, img_y + 58, "Source", 13, muted, family=gm.FONT_UI, weight=700))
    parts.append(gm.text(tx, img_y + 80, "Album: Family Spring Walk", 14, ink, family=gm.FONT_UI))
    parts.append(gm.text(tx, img_y + 118, "Caption", 13, muted, family=gm.FONT_UI, weight=700))
    parts.append(gm.text(tx, img_y + 142, "Two children leaning toward a white-blossoming tree on a bright April afternoon.", 15, ink, family=gm.FONT_UI, weight=500))
    parts.append(gm.text(tx, img_y + 196, "Keywords", 13, muted, family=gm.FONT_UI, weight=700))
    parts.append(gm.text(tx, img_y + 220, "spring, blossoms, siblings, backyard, sunlight", 15, accent, family=gm.FONT_UI, weight=650))
    parts.append(gm.text(tx, img_y + 274, "Run pace", 13, muted, family=gm.FONT_UI, weight=700))
    parts.append(gm.text(tx, img_y + 298, "835 processed  •  642 changed  •  12 failed", 15, ink, family=gm.FONT_MONO, weight=650))
    parts.append(gm.text(tx, img_y + 332, "Elapsed 02:18:14  •  ETA 12:40", 15, ink, family=gm.FONT_MONO, weight=650))

    tray_y = frame.py(934)
    parts.append(gm.rect(frame.px(40), tray_y, frame.pw(1518), frame.ph(48), "#fbfcfd", rx=20, stroke="#dde5eb"))
    parts.append(gm.text(frame.px(68), tray_y + frame.ph(30), "Ready with confirmation", frame.font(17), ink, family=gm.FONT_UI, weight=700))
    parts.append(gm.text(frame.px(290), tray_y + frame.ph(30), "Preview-forward main screen with safeguards still pinned.", frame.font(14), muted, family=gm.FONT_UI))
    parts += gm.button(frame.px(1214), tray_y + frame.ph(7), frame.pw(118), frame.ph(34), "Reload", "#ffffff", ink, stroke="#d8e2e9")
    parts += gm.button(frame.px(1350), tray_y + frame.ph(7), frame.pw(186), frame.ph(34), "Start Run", accent, "#ffffff")

    callout_fill = "#edf5fa"
    callout_border = "#d2e3ed"
    parts.append(gm.rect(frame.px(76), frame.py(912), frame.pw(150), frame.ph(34), callout_fill, rx=17, stroke=callout_border))
    parts.append(gm.text(frame.px(151), frame.py(934), "Pinned browser", frame.font(13), accent, family=gm.FONT_UI, weight=700, anchor="middle"))
    parts.append(gm.rect(frame.px(548), frame.py(912), frame.pw(198), frame.ph(34), callout_fill, rx=17, stroke=callout_border))
    parts.append(gm.text(frame.px(647), frame.py(934), "Compact setup stack", frame.font(13), accent, family=gm.FONT_UI, weight=700, anchor="middle"))
    parts.append(gm.rect(frame.px(1142), frame.py(912), frame.pw(232), frame.ph(34), callout_fill, rx=17, stroke=callout_border))
    parts.append(gm.text(frame.px(1258), frame.py(934), "Larger result emphasis", frame.font(13), accent, family=gm.FONT_UI, weight=700, anchor="middle"))
    return gm.group(parts)


def render_final_sheet() -> str:
    sheet_w = 1800
    sheet_h = 1240
    margin = 52
    pieces = [gm.rect(0, 0, sheet_w, sheet_h, "#f3f4f7", rx=0)]
    pieces.append(gm.text(margin, 48, "Photos Caption Assistant — Locked Direction", 30, "#1b2230", family=gm.FONT_SANS, weight=800))
    pieces.append(gm.text(sheet_w - margin, 48, "Quiet Workbench / Preview Forward", 17, "#6b7280", family=gm.FONT_UI, weight=600, anchor="end"))
    pieces.append(gm.rect(margin, 84, sheet_w - margin * 2, 1080, "#ffffff", rx=30, stroke="#d9dce3"))
    inner = gm.Frame(margin + 18, 106, sheet_w - margin * 2 - 36, 1036)
    pieces.append(final_preview_forward(inner))
    return gm.make_svg(gm.group(pieces), sheet_w, sheet_h)


def render_svg(concept_func) -> str:
    frame = gm.Frame(0, 0, W, H)
    return gm.make_svg(concept_func(frame), W, H)


def render_sheet() -> str:
    sheet_w = 1800
    sheet_h = 1800
    margin = 52
    gap = 34
    tile_w = (sheet_w - margin * 2 - gap) / 2
    tile_h = 760
    pieces = [gm.rect(0, 0, sheet_w, sheet_h, "#f3f4f7", rx=0)]
    pieces.append(gm.text(margin, 48, "Photos Caption Assistant — Hybrid A Refinements", 30, "#1b2230", family=gm.FONT_SANS, weight=800))
    pieces.append(gm.text(sheet_w - margin, 48, "Calm workbench direction", 17, "#6b7280", family=gm.FONT_UI, weight=600, anchor="end"))
    positions = [
        (margin, 94),
        (margin + tile_w + gap, 94),
        ((sheet_w - tile_w) / 2, 94 + tile_h + gap),
    ]
    for idx, ((slug, title_text, concept_func), (x, y)) in enumerate(zip(VARIANTS, positions), start=1):
        pieces.append(gm.rect(x, y, tile_w, tile_h, "#ffffff", rx=28, stroke="#d9dce3"))
        pieces.append(gm.text(x + 20, y + 38, f"{idx}. {title_text}", 18, "#1d2430", family=gm.FONT_SANS, weight=760))
        inner = gm.Frame(x + 14, y + 56, tile_w - 28, tile_h - 72)
        pieces.append(concept_func(inner))
    return gm.make_svg(gm.group(pieces), sheet_w, sheet_h)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for slug, _, concept_func in VARIANTS:
        (OUT_DIR / f"{slug}.svg").write_text(render_svg(concept_func), encoding="utf-8")
    (OUT_DIR / "hybrid_a_refinements_sheet.svg").write_text(render_sheet(), encoding="utf-8")
    (OUT_DIR / "a_locked_preview_forward.svg").write_text(render_svg(final_preview_forward), encoding="utf-8")
    (OUT_DIR / "a_locked_preview_forward_board.svg").write_text(render_final_sheet(), encoding="utf-8")


if __name__ == "__main__":
    main()
