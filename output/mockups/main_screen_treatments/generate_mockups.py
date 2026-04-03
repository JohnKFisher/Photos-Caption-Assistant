from __future__ import annotations

import html
import math
from dataclasses import dataclass
from pathlib import Path


OUT_DIR = Path("/Users/jkfisher/Resilio Sync/Family Documents/Codex/PhotoDescriptionCreator/output/mockups/main_screen_treatments")
W = 1600
H = 1000


@dataclass(frozen=True)
class Frame:
    x: float
    y: float
    w: float
    h: float

    def px(self, value: float) -> float:
        return self.x + (value / W) * self.w

    def py(self, value: float) -> float:
        return self.y + (value / H) * self.h

    def pw(self, value: float) -> float:
        return (value / W) * self.w

    def ph(self, value: float) -> float:
        return (value / H) * self.h

    def font(self, value: float) -> float:
        return max(8, min(self.w / W, self.h / H) * value)


FONT_SANS = "Arial"
FONT_UI = "Helvetica"
FONT_MONO = "Courier"
FONT_SERIF = "Georgia"


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def rect(x, y, w, h, fill, rx=18, stroke=None, stroke_width=1.5, opacity=1.0):
    attrs = [
        f'x="{x:.2f}"',
        f'y="{y:.2f}"',
        f'width="{w:.2f}"',
        f'height="{h:.2f}"',
        f'fill="{fill}"',
        f'rx="{rx:.2f}"',
        f'opacity="{opacity:.3f}"',
    ]
    if stroke:
        attrs.append(f'stroke="{stroke}"')
        attrs.append(f'stroke-width="{stroke_width:.2f}"')
    return "<rect " + " ".join(attrs) + " />"


def line(x1, y1, x2, y2, stroke, stroke_width=2, opacity=1.0, dash=None):
    attrs = [
        f'x1="{x1:.2f}"',
        f'y1="{y1:.2f}"',
        f'x2="{x2:.2f}"',
        f'y2="{y2:.2f}"',
        f'stroke="{stroke}"',
        f'stroke-width="{stroke_width:.2f}"',
        f'opacity="{opacity:.3f}"',
        'stroke-linecap="round"',
    ]
    if dash:
        attrs.append(f'stroke-dasharray="{dash}"')
    return "<line " + " ".join(attrs) + " />"


def circle(cx, cy, r, fill, opacity=1.0, stroke=None, stroke_width=1.5):
    attrs = [
        f'cx="{cx:.2f}"',
        f'cy="{cy:.2f}"',
        f'r="{r:.2f}"',
        f'fill="{fill}"',
        f'opacity="{opacity:.3f}"',
    ]
    if stroke:
        attrs.append(f'stroke="{stroke}"')
        attrs.append(f'stroke-width="{stroke_width:.2f}"')
    return "<circle " + " ".join(attrs) + " />"


def text(x, y, content, size, fill, family=FONT_SANS, weight=500, anchor="start", opacity=1.0):
    return (
        f'<text x="{x:.2f}" y="{y:.2f}" fill="{fill}" font-family="{family}" '
        f'font-size="{size:.2f}" font-weight="{weight}" text-anchor="{anchor}" '
        f'opacity="{opacity:.3f}">{esc(content)}</text>'
    )


def group(items):
    return "".join(items)


def window_shell(frame: Frame, bg_fill: str, border: str, accent: str, concept_title: str, family=FONT_SANS):
    items = [
        rect(frame.x, frame.y, frame.w, frame.h, bg_fill, rx=min(frame.w, frame.h) * 0.03, stroke=border, stroke_width=2),
        rect(frame.x, frame.y, frame.w, frame.ph(56), "#ffffff", rx=min(frame.w, frame.h) * 0.03, opacity=0.0),
        circle(frame.px(36), frame.py(31), frame.ph(7), "#ff5f57"),
        circle(frame.px(58), frame.py(31), frame.ph(7), "#febc2e"),
        circle(frame.px(80), frame.py(31), frame.ph(7), "#28c840"),
        text(frame.px(114), frame.py(36), "Photos Caption Assistant", frame.font(20), accent, family=family, weight=700),
        text(frame.px(1480), frame.py(36), concept_title, frame.font(15), accent, family=family, weight=600, anchor="end", opacity=0.72),
    ]
    return items


def pill(x, y, w, h, label, fill, fg, family=FONT_UI, weight=600):
    return [
        rect(x, y, w, h, fill, rx=h / 2),
        text(x + w / 2, y + h * 0.68, label, h * 0.43, fg, family=family, weight=weight, anchor="middle"),
    ]


def button(x, y, w, h, label, fill, fg, family=FONT_UI, stroke=None, weight=650):
    parts = [rect(x, y, w, h, fill, rx=h * 0.34, stroke=stroke, stroke_width=1.5 if stroke else 0)]
    parts.append(text(x + w / 2, y + h * 0.64, label, h * 0.42, fg, family=family, weight=weight, anchor="middle"))
    return parts


def labeled_card(x, y, w, h, title_text, subtitle, fill, border, title_fill, subtitle_fill, family=FONT_SANS):
    parts = [rect(x, y, w, h, fill, rx=24, stroke=border)]
    parts.append(text(x + 24, y + 34, title_text, 22, title_fill, family=family, weight=700))
    if subtitle:
        parts.append(text(x + 24, y + 58, subtitle, 13, subtitle_fill, family=FONT_UI, weight=500))
    return parts


def mini_setting_card(x, y, w, h, title_text, body, fill, border, title_fill, body_fill, icon_fill=None, family=FONT_SANS):
    parts = [rect(x, y, w, h, fill, rx=20, stroke=border)]
    if icon_fill:
        parts.append(circle(x + 26, y + 28, 10, icon_fill, opacity=0.95))
        title_x = x + 46
    else:
        title_x = x + 20
    parts.append(text(title_x, y + 34, title_text, 18, title_fill, family=family, weight=700))
    parts.append(text(x + 20, y + 62, body, 13, body_fill, family=FONT_UI, weight=500))
    return parts


def progress_bar(x, y, w, h, progress_fill, track_fill, fraction=0.58):
    parts = [rect(x, y, w, h, track_fill, rx=h / 2)]
    parts.append(rect(x, y, w * fraction, h, progress_fill, rx=h / 2))
    return parts


def preview_tile(x, y, w, h, bg, border, title_fill, muted_fill, accent, family=FONT_SANS):
    parts = [rect(x, y, w, h, bg, rx=24, stroke=border)]
    parts.append(rect(x + 18, y + 18, w * 0.34, h - 36, "#d8e5ef", rx=18))
    parts.append(circle(x + w * 0.17, y + h * 0.36, min(w, h) * 0.07, "#9cb7c7"))
    parts.append(rect(x + 18, y + h * 0.60, w * 0.34, h * 0.18, "#a4c1d1", rx=14))
    tx = x + w * 0.40
    parts.append(text(tx, y + 38, "Last Completed Item", 20, title_fill, family=family, weight=700))
    parts.append(text(tx, y + 68, "IMG_1187.HEIC", 18, title_fill, family=FONT_UI, weight=650))
    parts.append(text(tx, y + 102, "Source", 13, muted_fill, family=FONT_UI, weight=700))
    parts.append(text(tx, y + 124, "Album: Family Spring Walk", 14, title_fill, family=FONT_UI, weight=500))
    parts.append(text(tx, y + 156, "Caption", 13, muted_fill, family=FONT_UI, weight=700))
    parts.append(text(tx, y + 178, "Two children leaning toward a white-blossoming tree on a bright April afternoon.", 14, title_fill, family=FONT_UI, weight=500))
    parts.append(text(tx, y + 214, "Keywords", 13, muted_fill, family=FONT_UI, weight=700))
    parts.append(text(tx, y + 236, "spring, blossoms, siblings, backyard, sunlight", 14, accent, family=FONT_UI, weight=600))
    return parts


def quiet_utility(frame: Frame):
    bg = "#eef1f4"
    ink = "#18212b"
    muted = "#5f6c79"
    border = "#d8dde3"
    accent = "#3f6d90"
    parts = window_shell(frame, bg, border, ink, "Quiet Utility")
    parts.append(rect(frame.px(30), frame.py(78), frame.pw(1540), frame.ph(70), "#f9fbfc", rx=22, stroke="#dde3e8"))
    for i, label in enumerate(["Automation", "Qwen 2.5VL 7B", "Picker"]):
        parts += pill(frame.px(52 + i * 168), frame.py(96), frame.pw(144), frame.ph(32), label, "#e7edf2", ink)
    parts.append(text(frame.px(1500), frame.py(117), "Local-first. Conservative writes. Photos ready.", frame.font(14), muted, family=FONT_UI, anchor="end"))

    left_x = frame.px(46)
    left_y = frame.py(174)
    left_w = frame.pw(1040)
    right_x = frame.px(1110)
    right_w = frame.pw(444)
    main_h = frame.ph(624)
    parts += labeled_card(left_x, left_y, left_w, main_h, "Run Setup", "One calm working column.", "#ffffff", border, ink, muted)
    parts += labeled_card(right_x, left_y, right_w, frame.ph(410), "Run Summary", "Always visible safeguards.", "#fcfdfd", border, ink, muted)
    parts += mini_setting_card(left_x + 28, left_y + 74, left_w - 56, 114, "Source", "Album | Family Spring Walk", "#f7f9fb", "#e3e8ee", ink, muted, icon_fill="#8fb2c8")
    parts += mini_setting_card(left_x + 28, left_y + 204, left_w - 56, 92, "Capture Date Filter", "Off", "#f7f9fb", "#e3e8ee", ink, muted, icon_fill="#d4b57d")
    parts += mini_setting_card(left_x + 28, left_y + 312, left_w - 56, 92, "Processing Order", "Photos order (recommended)", "#f7f9fb", "#e3e8ee", ink, muted, icon_fill="#93c4ab")
    parts += mini_setting_card(left_x + 28, left_y + 420, left_w - 56, 112, "Overwrite Behavior", "Preserve external metadata unless item-by-item confirmation is granted.", "#f7f9fb", "#e3e8ee", ink, muted, icon_fill="#caa4a2")
    parts += progress_bar(left_x + 28, left_y + 562, left_w - 56, 18, accent, "#d9e3ea", fraction=0.67)
    parts.append(text(left_x + 28, left_y + 606, "Run Progress  •  1,248 discovered  •  835 processed  •  ETA 12:40", 15, muted, family=FONT_MONO, weight=500))

    parts.append(text(right_x + 24, left_y + 90, "Source", 13, muted, family=FONT_UI, weight=700))
    parts.append(text(right_x + 24, left_y + 112, "Album: Family Spring Walk", 16, ink, family=FONT_UI))
    parts.append(text(right_x + 24, left_y + 156, "Count", 13, muted, family=FONT_UI, weight=700))
    parts.append(text(right_x + 24, left_y + 178, "Estimated 1,248 items", 16, ink, family=FONT_UI))
    parts.append(text(right_x + 24, left_y + 222, "Writes", 13, muted, family=FONT_UI, weight=700))
    parts.append(text(right_x + 24, left_y + 244, "Captions and keywords back into Apple Photos", 15, ink, family=FONT_UI))
    parts.append(rect(right_x + 24, left_y + 286, right_w - 48, 64, "#f7efcf", rx=16, stroke="#ead595"))
    parts.append(text(right_x + 42, left_y + 326, "Confirmation required before wider overwrite behavior.", 15, "#7a5d1c", family=FONT_UI, weight=600))

    parts += preview_tile(right_x, left_y + 430, right_w, frame.ph(368), "#ffffff", border, ink, muted, accent)

    tray_y = frame.py(834)
    parts.append(rect(frame.px(30), tray_y, frame.pw(1540), frame.ph(132), "#fbfcfd", rx=24, stroke="#dbe1e7"))
    parts.append(text(frame.px(60), tray_y + frame.ph(42), "Ready with confirmation", frame.font(22), ink, family=FONT_SANS, weight=700))
    parts.append(text(frame.px(60), tray_y + frame.ph(74), "The summary and warnings stay visible before Start.", frame.font(14), muted, family=FONT_UI))
    parts += button(frame.px(1050), tray_y + frame.ph(34), frame.pw(148), frame.ph(44), "Reload", "#eef3f7", ink, stroke="#d8e0e8")
    parts += button(frame.px(1214), tray_y + frame.ph(34), frame.pw(162), frame.ph(44), "Retry Failed", "#ffffff", ink, stroke="#d7dee7")
    parts += button(frame.px(1392), tray_y + frame.ph(28), frame.pw(142), frame.ph(56), "Start Run", accent, "#ffffff")
    return group(parts)


def inspector_split(frame: Frame):
    bg = "#f4f6f8"
    ink = "#1b2630"
    muted = "#65727e"
    border = "#d8dee6"
    accent = "#446b86"
    parts = window_shell(frame, bg, border, ink, "Inspector Split")
    rail_x = frame.px(26)
    rail_y = frame.py(82)
    rail_w = frame.pw(120)
    parts.append(rect(rail_x, rail_y, rail_w, frame.ph(884), "#eaeef2", rx=24, stroke="#d7dde4"))
    for idx, label in enumerate(["Scope", "Run", "Data", "Diag"]):
        cy = rail_y + 48 + idx * 118
        parts.append(circle(rail_x + rail_w / 2, cy, 24, "#dce6ed" if idx == 0 else "#f8fafb", stroke="#ced8e0"))
        parts.append(text(rail_x + rail_w / 2, cy + 54, label, 14, muted, family=FONT_UI, weight=650, anchor="middle"))

    center_x = frame.px(168)
    center_w = frame.pw(980)
    right_x = frame.px(1168)
    right_w = frame.pw(406)
    parts += labeled_card(center_x, rail_y, center_w, frame.ph(580), "Main Setup", "Native three-pane utility layout.", "#ffffff", border, ink, muted)
    parts += labeled_card(right_x, rail_y, right_w, frame.ph(580), "Run Summary", "Finder-style always-open inspector.", "#fcfdfe", border, ink, muted)
    sections = [
        ("Source", "Album  •  Family Spring Walk"),
        ("Capture Date Filter", "April 1, 2025  to  today"),
        ("Processing Order", "Photos order (recommended)"),
        ("Overwrite Behavior", "Preserve non-app metadata by default"),
    ]
    y = rail_y + 72
    for title_text, body in sections:
        parts += mini_setting_card(center_x + 24, y, center_w - 48, 102, title_text, body, "#f8fafb", "#e3e8ee", ink, muted, icon_fill="#99b6c9")
        y += 116

    for i, line_text in enumerate([
        "Album: Family Spring Walk",
        "Estimated count: 1,248 items",
        "Writes: captions + keywords",
        "Model: qwen2.5vl:7b",
        "Ollama: installed locally",
    ]):
        parts.append(text(right_x + 24, rail_y + 88 + i * 52, line_text, 16, ink if i == 0 else muted, family=FONT_UI, weight=650 if i == 0 else 500))
    parts.append(rect(right_x + 24, rail_y + 360, right_w - 48, 64, "#f8efca", rx=16, stroke="#ecd485"))
    parts.append(text(right_x + 44, rail_y + 400, "Whole-library runs and wider overwrites still require confirmation.", 14, "#6f571f", family=FONT_UI, weight=650))

    prog_y = frame.py(686)
    parts += labeled_card(center_x, prog_y, frame.pw(1380), frame.ph(280), "Progress + Preview", "Shared bottom band across the whole app.", "#ffffff", border, ink, muted)
    parts += progress_bar(center_x + 26, prog_y + 72, frame.pw(480), 18, accent, "#dde7ee", fraction=0.61)
    for idx, stat in enumerate(["Discovered 1248", "Processed 835", "Changed 642", "Failed 12", "ETA 12:40"]):
        parts.append(text(center_x + 26 + idx * 138, prog_y + 128, stat, 16, muted if idx != 2 else ink, family=FONT_MONO, weight=600))
    parts += preview_tile(center_x + frame.pw(530), prog_y + 48, frame.pw(820), frame.ph(188), "#f9fbfc", "#e3e8ee", ink, muted, accent)
    return group(parts)


def checklist_launchpad(frame: Frame):
    bg = "#f5f5f1"
    ink = "#23241f"
    muted = "#6f7068"
    border = "#dfdfd8"
    accent = "#5f7f53"
    parts = window_shell(frame, bg, border, ink, "Checklist Launchpad")
    parts.append(text(frame.px(54), frame.py(116), "Everything you need before Start, framed as four completion cards.", frame.font(18), muted, family=FONT_UI))

    grid = [
        ("1  Source", "Album selected. Scope estimate ready.", "#edf6ea"),
        ("2  Filter", "No capture-date restriction enabled.", "#f9f2dc"),
        ("3  Order", "Photos order for fastest start.", "#e9f0f8"),
        ("4  Overwrite", "Conservative writes. External metadata preserved.", "#f6ebea"),
    ]
    xs = [frame.px(52), frame.px(824)]
    ys = [frame.py(168), frame.py(404)]
    idx = 0
    for row in range(2):
        for col in range(2):
            x = xs[col]
            y = ys[row]
            title_text, body, fill = grid[idx]
            parts += mini_setting_card(x, y, frame.pw(700), frame.ph(190), title_text, body, fill, "#d9ddd5", ink, muted, icon_fill="#6e9c60")
            parts.append(circle(x + frame.pw(642), y + frame.ph(44), frame.ph(16), "#76b56a"))
            parts.append(text(x + frame.pw(642), y + frame.ph(50), "✓", frame.font(18), "#ffffff", family=FONT_UI, weight=800, anchor="middle"))
            idx += 1

    summary_x = frame.px(52)
    summary_y = frame.py(650)
    summary_w = frame.pw(980)
    parts += labeled_card(summary_x, summary_y, summary_w, frame.ph(210), "Preflight", "Locked behind the checklist but always visible.", "#ffffff", border, ink, muted)
    parts.append(rect(summary_x + 24, summary_y + 72, summary_w - 48, 60, "#f7efc8", rx=16, stroke="#e9d486"))
    parts.append(text(summary_x + 44, summary_y + 110, "Confirmation needed because non-app metadata could be overwritten later.", 16, "#70591e", family=FONT_UI, weight=650))
    parts += progress_bar(summary_x + 24, summary_y + 154, summary_w - 48, 16, accent, "#dde4d8", fraction=0.73)

    preview_x = frame.px(1064)
    parts += preview_tile(preview_x, summary_y, frame.pw(488), frame.ph(210), "#ffffff", border, ink, muted, accent)

    tray_y = frame.py(892)
    parts.append(rect(frame.px(52), tray_y, frame.pw(1500), frame.ph(76), "#1f2b22", rx=18))
    parts.append(text(frame.px(80), tray_y + frame.ph(46), "Checklist complete  •  Start remains visually gated by preflight.", frame.font(18), "#f4f5ef", family=FONT_UI, weight=600))
    parts += button(frame.px(1366), tray_y + frame.ph(16), frame.pw(160), frame.ph(46), "Start Run", "#84b46c", "#102014")
    return group(parts)


def monospace_ops(frame: Frame):
    bg = "#101417"
    ink = "#d7e2ea"
    muted = "#86a2af"
    border = "#26333c"
    accent = "#72d698"
    warning = "#f1c96a"
    parts = window_shell(frame, bg, border, ink, "Monospace Ops", family=FONT_MONO)
    parts.append(rect(frame.px(28), frame.py(84), frame.pw(1544), frame.ph(888), "#0f1316", rx=28, stroke="#1a242c"))
    for x in [220, 760, 1210]:
        parts.append(line(frame.px(x), frame.py(116), frame.px(x), frame.py(930), "#23303a", stroke_width=2))
    for y in [180, 356, 538, 720]:
        parts.append(line(frame.px(40), frame.py(y), frame.px(1550), frame.py(y), "#1e2931", stroke_width=2))
    parts.append(text(frame.px(60), frame.py(148), "SOURCE", frame.font(20), accent, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(264), frame.py(148), "RUN SUMMARY", frame.font(20), accent, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(806), frame.py(148), "PROGRESS / LAST ITEM", frame.font(20), accent, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(60), frame.py(222), "mode             album", 18, ink, family=FONT_MONO))
    parts.append(text(frame.px(60), frame.py(258), "selection        Family Spring Walk", 18, ink, family=FONT_MONO))
    parts.append(text(frame.px(60), frame.py(294), "date filter      off", 18, ink, family=FONT_MONO))
    parts.append(text(frame.px(60), frame.py(330), "overwrite        conservative", 18, ink, family=FONT_MONO))
    parts.append(text(frame.px(264), frame.py(222), "count            est. 1248", 18, ink, family=FONT_MONO))
    parts.append(text(frame.px(264), frame.py(258), "writes           captions + keywords", 18, ink, family=FONT_MONO))
    parts.append(text(frame.px(264), frame.py(294), "ollama           local / ready", 18, ink, family=FONT_MONO))
    parts.append(text(frame.px(264), frame.py(330), "warning          confirmation required", 18, warning, family=FONT_MONO, weight=700))
    parts += progress_bar(frame.px(806), frame.py(204), frame.pw(664), 24, accent, "#1e2f28", fraction=0.66)
    for idx, stat in enumerate(["DISC 1248", "PROC 835", "CHGD 642", "FAIL 12", "ETA 12:40"]):
        parts.append(text(frame.px(806 + idx * 134), frame.py(286), stat, 18, ink if idx != 3 else warning, family=FONT_MONO, weight=700))
    parts.append(rect(frame.px(806), frame.py(336), frame.pw(256), frame.ph(278), "#172028", rx=22, stroke="#2d4251"))
    parts.append(rect(frame.px(826), frame.py(356), frame.pw(216), frame.ph(172), "#24313b", rx=16))
    parts.append(text(frame.px(1088), frame.py(370), "IMG_1187.HEIC", frame.font(18), ink, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(1088), frame.py(416), "CAPTION", frame.font(15), muted, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(1088), frame.py(448), "children under white blossoms", frame.font(16), ink, family=FONT_MONO))
    parts.append(text(frame.px(1088), frame.py(494), "KEYWORDS", frame.font(15), muted, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(1088), frame.py(526), "spring, siblings, sunlight", frame.font(16), accent, family=FONT_MONO))
    parts.append(rect(frame.px(52), frame.py(770), frame.pw(1490), frame.ph(94), "#11191f", rx=18, stroke="#25343d"))
    parts.append(text(frame.px(72), frame.py(826), "> start-run  --scope album --safe-writes true", frame.font(22), accent, family=FONT_MONO, weight=700))
    parts += button(frame.px(1260), frame.py(790), frame.pw(122), frame.ph(52), "RETRY", "#172028", accent, family=FONT_MONO, stroke="#2f4652")
    parts += button(frame.px(1400), frame.py(790), frame.pw(126), frame.ph(52), "START", accent, "#07150d", family=FONT_MONO)
    return group(parts)


def glass_sheet(frame: Frame):
    bg = "#d9e7ef"
    ink = "#173041"
    muted = "#557286"
    accent = "#4b8cb3"
    parts = window_shell(frame, bg, "#c6dae5", ink, "Glass Sheet")
    parts.append(circle(frame.px(1360), frame.py(160), frame.ph(180), "#bde0ef", opacity=0.65))
    parts.append(circle(frame.px(240), frame.py(800), frame.ph(220), "#e8f4f7", opacity=0.55))

    def glass(x, y, w, h):
        return rect(x, y, w, h, "#ffffff", rx=28, stroke="#ffffff", stroke_width=1.2, opacity=0.42)

    parts.append(glass(frame.px(48), frame.py(146), frame.pw(996), frame.ph(652)))
    parts.append(glass(frame.px(1074), frame.py(146), frame.pw(478), frame.ph(652)))
    parts.append(glass(frame.px(48), frame.py(822), frame.pw(1504), frame.ph(138)))
    parts.append(text(frame.px(76), frame.py(194), "A calm glass workspace with the preview tile doing most of the visual work.", frame.font(20), muted, family=FONT_UI))
    cards = [
        ("Source", "Album / Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Order", "Photos order"),
        ("Overwrite", "External metadata protected"),
    ]
    y = frame.py(236)
    for title_text, body in cards:
        parts += mini_setting_card(frame.px(76), y, frame.pw(940), frame.ph(102), title_text, body, "#ffffff", "#dfeff5", ink, muted, icon_fill="#7db2cc")
        y += frame.ph(122)
    parts += progress_bar(frame.px(76), frame.py(706), frame.pw(940), frame.ph(16), accent, "#d6e7ef", fraction=0.63)
    parts.append(text(frame.px(76), frame.py(750), "835 processed  •  642 changed  •  12 failed  •  ETA 12:40", frame.font(15), muted, family=FONT_UI))

    parts += preview_tile(frame.px(1098), frame.py(214), frame.pw(430), frame.ph(310), "#ffffff", "#ddebf2", ink, muted, accent)
    parts += labeled_card(frame.px(1098), frame.py(544), frame.pw(430), frame.ph(254), "Run Summary", "Slim right inspector.", "#ffffff", "#ddebf2", ink, muted)
    parts.append(text(frame.px(1122), frame.py(628), "Count  •  Estimated 1,248 items", frame.font(16), ink, family=FONT_UI, weight=600))
    parts.append(text(frame.px(1122), frame.py(670), "Writes  •  Captions and keywords", frame.font(16), ink, family=FONT_UI, weight=600))
    parts.append(rect(frame.px(1122), frame.py(702), frame.pw(380), frame.ph(56), "#edf4d8", rx=16, stroke="#d8e7aa"))
    parts.append(text(frame.px(1144), frame.py(736), "Safer defaults remain visible and explicit.", frame.font(14), "#607136", family=FONT_UI, weight=650))

    parts += button(frame.px(1220), frame.py(856), frame.pw(132), frame.ph(48), "Retry", "#ffffff", ink, stroke="#d9ecf4")
    parts += button(frame.px(1372), frame.py(848), frame.pw(156), frame.ph(60), "Start Run", accent, "#ffffff")
    return group(parts)


def native_pro(frame: Frame):
    bg = "#eff2f5"
    ink = "#15202b"
    muted = "#5f6d79"
    border = "#d8dee5"
    accent = "#3f7ba3"
    parts = window_shell(frame, bg, border, ink, "Native Pro")
    parts.append(rect(frame.px(42), frame.py(88), frame.pw(1516), frame.ph(112), "#ffffff", rx=28, stroke="#dde4ea"))
    parts.append(text(frame.px(70), frame.py(132), "A refined production-ready evolution of the current screen.", frame.font(20), muted, family=FONT_UI))
    for i, label in enumerate(["Automation ready", "Model ready", "Picker supported"]):
        parts += pill(frame.px(1030 + i * 166), frame.py(108), frame.pw(150), frame.ph(34), label, "#e8f1f6", accent)

    board_y = frame.py(228)
    cols = [frame.px(42), frame.px(555), frame.px(1068)]
    titles = [("1", "Scope"), ("2", "Safeguards"), ("3", "Run")]
    for idx, (x, (step, label)) in enumerate(zip(cols, titles)):
        parts.append(rect(x, board_y, frame.pw(460), frame.ph(140), "#ffffff", rx=24, stroke="#dde4ea"))
        parts.append(circle(x + 32, board_y + 36, 16, "#dce8ef" if idx != 2 else "#d6ecf4"))
        parts.append(text(x + 32, board_y + 42, step, 16, accent, family=FONT_UI, weight=800, anchor="middle"))
        parts.append(text(x + 58, board_y + 42, label, 24, ink, family=FONT_SANS, weight=700))
    parts.append(text(cols[0] + 24, board_y + 92, "Album selected. Filter off. Photos order.", 15, muted, family=FONT_UI))
    parts.append(text(cols[1] + 24, board_y + 92, "Run summary remains pinned while warnings stay readable.", 15, muted, family=FONT_UI))
    parts.append(text(cols[2] + 24, board_y + 92, "Progress, recent errors, and preview remain on one screen.", 15, muted, family=FONT_UI))

    main_x = frame.px(42)
    main_y = frame.py(392)
    parts += labeled_card(main_x, main_y, frame.pw(980), frame.ph(500), "Setup", "Better hierarchy without changing the workflow.", "#ffffff", border, ink, muted)
    cards = [
        ("Source", "Album  •  Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Processing Order", "Photos order (recommended)"),
        ("Overwrite Behavior", "App-owned only unless confirmed"),
    ]
    y = main_y + 74
    for title_text, body in cards:
        parts += mini_setting_card(main_x + 24, y, frame.pw(932), frame.ph(94), title_text, body, "#f8fafc", "#e3e9ef", ink, muted, icon_fill="#8fb9d1")
        y += frame.ph(112)
    parts += progress_bar(main_x + 24, main_y + frame.ph(448), frame.pw(932), frame.ph(14), accent, "#dde7ee", fraction=0.68)

    right_x = frame.px(1054)
    parts += labeled_card(right_x, main_y, frame.pw(504), frame.ph(300), "Run Summary", "Pinned safeguards inspector.", "#ffffff", border, ink, muted)
    parts.append(rect(right_x + 24, main_y + 168, frame.pw(456), frame.ph(64), "#f7efcf", rx=18, stroke="#e9d38c"))
    parts.append(text(right_x + 44, main_y + 206, "Confirmation required before broader overwrite behavior.", 14, "#6d561a", family=FONT_UI, weight=650))
    parts += preview_tile(right_x, main_y + frame.ph(324), frame.pw(504), frame.ph(256), "#ffffff", border, ink, muted, accent)

    tray_y = frame.py(912)
    parts.append(rect(frame.px(42), tray_y, frame.pw(1516), frame.ph(58), "#ffffff", rx=18, stroke="#dde4ea"))
    parts.append(text(frame.px(68), tray_y + frame.ph(36), "Ready with confirmation", frame.font(17), ink, family=FONT_UI, weight=700))
    parts += button(frame.px(1204), tray_y + frame.ph(10), frame.pw(130), frame.ph(38), "Resume", "#ffffff", ink, stroke="#d9e3ea")
    parts += button(frame.px(1352), tray_y + frame.ph(10), frame.pw(182), frame.ph(38), "Start Run", accent, "#ffffff")
    return group(parts)


def workflow_board(frame: Frame):
    bg = "#eef4f4"
    ink = "#193133"
    muted = "#5b7477"
    border = "#d9e5e4"
    accent = "#4b9a93"
    parts = window_shell(frame, bg, border, ink, "Workflow Board")
    x_positions = [frame.px(42), frame.px(552), frame.px(1062)]
    titles = [
        ("1", "Choose Scope", "Pick source, filter, order."),
        ("2", "Confirm Rules", "Read summary and warnings."),
        ("3", "Run", "Monitor live progress and preview."),
    ]
    for idx, (x, (step, label, desc)) in enumerate(zip(x_positions, titles)):
        parts.append(rect(x, frame.py(154), frame.pw(470), frame.ph(650), "#ffffff", rx=28, stroke="#cfe1df"))
        parts.append(circle(x + 36, frame.py(200), 18, "#d2eeeb" if idx == 1 else "#ebf4f4"))
        parts.append(text(x + 36, frame.py(206), step, 17, accent, family=FONT_UI, weight=800, anchor="middle"))
        parts.append(text(x + 66, frame.py(206), label, 26, ink, family=FONT_SANS, weight=700))
        parts.append(text(x + 28, frame.py(242), desc, 15, muted, family=FONT_UI))
    for i in range(2):
        parts.append(line(frame.px(502 + i * 510), frame.py(478), frame.px(544 + i * 510), frame.py(478), accent, stroke_width=5))
        parts.append(line(frame.px(532 + i * 510), frame.py(463), frame.px(544 + i * 510), frame.py(478), accent, stroke_width=5))
        parts.append(line(frame.px(532 + i * 510), frame.py(493), frame.px(544 + i * 510), frame.py(478), accent, stroke_width=5))
    cards = [
        ("Source", "Album / Family Spring Walk"),
        ("Filter", "Off"),
        ("Order", "Photos order"),
        ("Overwrite", "Conservative"),
    ]
    y = frame.py(284)
    for title_text, body in cards:
        parts += mini_setting_card(frame.px(72), y, frame.pw(410), frame.ph(92), title_text, body, "#f7fbfb", "#dae9e7", ink, muted, icon_fill="#82c3bc")
        y += frame.ph(104)
    parts += labeled_card(frame.px(582), frame.py(284), frame.pw(410), frame.ph(214), "Run Summary", "Warnings stay visible here.", "#fdfefd", "#dce8e7", ink, muted)
    parts.append(rect(frame.px(606), frame.py(390), frame.pw(362), frame.ph(60), "#fff4cd", rx=16, stroke="#ecd486"))
    parts.append(text(frame.px(628), frame.py(425), "Confirmation needed before broader metadata overwrite.", 14, "#6b581d", family=FONT_UI, weight=650))
    parts += labeled_card(frame.px(582), frame.py(520), frame.pw(410), frame.ph(236), "Blocking / Notes", "Everything explained in one stage.", "#fdfefd", "#dce8e7", ink, muted)
    parts.append(text(frame.px(606), frame.py(602), "Photos automation available", 15, ink, family=FONT_UI, weight=600))
    parts.append(text(frame.px(606), frame.py(638), "Qwen model installed locally", 15, ink, family=FONT_UI, weight=600))
    parts.append(text(frame.px(606), frame.py(674), "Ready to start once confirmed", 15, accent, family=FONT_UI, weight=700))
    parts += progress_bar(frame.px(1092), frame.py(286), frame.pw(410), frame.ph(18), accent, "#dbeae8", fraction=0.64)
    for idx, stat in enumerate(["Disc 1248", "Proc 835", "Changed 642", "Fail 12"]):
        parts.append(text(frame.px(1092 + idx * 100), frame.py(340), stat, 16, ink if idx != 3 else "#b96f42", family=FONT_MONO, weight=700))
    parts += preview_tile(frame.px(1092), frame.py(376), frame.pw(410), frame.ph(254), "#fdfefd", "#dce8e7", ink, muted, accent)
    parts += button(frame.px(1322), frame.py(690), frame.pw(180), frame.ph(60), "Start Run", accent, "#ffffff")
    return group(parts)


def album_workbench(frame: Frame):
    bg = "#f2f0ea"
    ink = "#2a241d"
    muted = "#786c60"
    border = "#e0d8ce"
    accent = "#8f6b42"
    parts = window_shell(frame, bg, border, ink, "Album Workbench")
    left_x = frame.px(42)
    center_x = frame.px(330)
    right_x = frame.px(1068)
    parts.append(rect(left_x, frame.py(150), frame.pw(250), frame.ph(810), "#faf8f4", rx=28, stroke="#ddd6cb"))
    parts.append(text(left_x + 24, frame.py(194), "Albums", frame.font(24), ink, family=FONT_SANS, weight=700))
    album_names = ["Family Spring Walk", "Birthday Dinner", "Lake Weekend", "Garden May", "Videos To Review"]
    for idx, name in enumerate(album_names):
        y = frame.py(236 + idx * 92)
        fill = "#efe4d4" if idx == 0 else "#ffffff"
        parts.append(rect(left_x + 18, y, frame.pw(214), frame.ph(72), fill, rx=18, stroke="#e7ddcf"))
        parts.append(text(left_x + 38, y + frame.ph(32), name, frame.font(16), ink, family=FONT_UI, weight=650))
        parts.append(text(left_x + 38, y + frame.ph(54), f"{[1248, 382, 460, 278, 91][idx]} items", frame.font(13), muted, family=FONT_UI))

    parts += labeled_card(center_x, frame.py(150), frame.pw(700), frame.ph(810), "Workbench", "Source browsing on the left, detailed configuration in the middle.", "#ffffff", "#dfd7cb", ink, muted)
    y = frame.py(224)
    for title_text, body in [
        ("Source", "Album / Family Spring Walk"),
        ("Date Filter", "Off"),
        ("Order", "Photos order"),
        ("Overwrite", "Preserve external metadata"),
        ("Queued Albums", "Optional secondary workflow"),
    ]:
        parts += mini_setting_card(center_x + 24, y, frame.pw(652), frame.ph(100), title_text, body, "#faf8f5", "#e6ded3", ink, muted, icon_fill="#c59d71")
        y += frame.ph(118)

    parts += labeled_card(right_x, frame.py(150), frame.pw(490), frame.ph(312), "Run Summary", "The inspector mirrors the active album and safety posture.", "#fffdfb", "#dfd7cb", ink, muted)
    parts.append(text(right_x + 24, frame.py(238), "Count  •  Estimated 1,248 items", frame.font(16), ink, family=FONT_UI, weight=650))
    parts.append(text(right_x + 24, frame.py(278), "Writes  •  Captions + keywords", frame.font(16), ink, family=FONT_UI, weight=650))
    parts.append(rect(right_x + 24, frame.py(316), frame.pw(442), frame.ph(72), "#f7eccf", rx=18, stroke="#ead69a"))
    parts.append(text(right_x + 48, frame.py(360), "Review overwrite rules before Start.", frame.font(15), "#6a5723", family=FONT_UI, weight=650))
    parts += preview_tile(right_x, frame.py(486), frame.pw(490), frame.ph(304), "#fffdfb", "#dfd7cb", ink, muted, accent)
    parts += progress_bar(right_x + 24, frame.py(824), frame.pw(442), frame.ph(18), accent, "#e6ddd4", fraction=0.71)
    parts.append(text(right_x + 24, frame.py(872), "835 processed  •  642 changed  •  12 failed", frame.font(15), muted, family=FONT_MONO))
    parts += button(right_x + frame.pw(260), frame.py(894), frame.pw(206), frame.ph(54), "Start Run", accent, "#ffffff")
    return group(parts)


def operations_console(frame: Frame):
    bg = "#eaf0f2"
    ink = "#182730"
    muted = "#617580"
    border = "#d6e0e4"
    accent = "#2f7d8b"
    parts = window_shell(frame, bg, border, ink, "Operations Console")
    parts.append(rect(frame.px(42), frame.py(92), frame.pw(1516), frame.ph(106), "#162831", rx=26))
    kpis = [
        ("Automation", "Ready"),
        ("Model", "Local"),
        ("Pending", "413"),
        ("Rate", "6.1/min"),
        ("ETA", "12:40"),
    ]
    for idx, (label, value) in enumerate(kpis):
        x = frame.px(72 + idx * 288)
        parts.append(text(x, frame.py(132), label, frame.font(14), "#7ea0ae", family=FONT_UI, weight=700))
        parts.append(text(x, frame.py(170), value, frame.font(26), "#edf8fb", family=FONT_MONO, weight=700))
    main_x = frame.px(42)
    main_y = frame.py(226)
    parts += labeled_card(main_x, main_y, frame.pw(1000), frame.ph(734), "Setup", "A denser operator-oriented control surface.", "#ffffff", border, ink, muted)
    y = main_y + 76
    for title_text, body in [
        ("Source", "Album / Family Spring Walk"),
        ("Date Filter", "Off"),
        ("Order", "Photos order (recommended)"),
        ("Overwrite", "External metadata protected"),
    ]:
        parts += mini_setting_card(main_x + 26, y, frame.pw(948), frame.ph(108), title_text, body, "#f7fbfc", "#dfe8eb", ink, muted, icon_fill="#86b7bf")
        y += frame.ph(126)
    parts += progress_bar(main_x + 26, main_y + frame.ph(630), frame.pw(948), frame.ph(18), accent, "#dce9ec", fraction=0.66)
    parts.append(text(main_x + 26, main_y + frame.ph(676), "Throughput 6.1/min  •  Elapsed 02:18:14  •  ETA 00:12:40", frame.font(16), muted, family=FONT_MONO))

    utility_x = frame.px(1070)
    parts += labeled_card(utility_x, main_y, frame.pw(488), frame.ph(252), "Utility Column", "Recent errors, retry, resume, diagnostics.", "#ffffff", border, ink, muted)
    parts.append(rect(utility_x + 24, main_y + 90, frame.pw(440), frame.ph(54), "#fff0e4", rx=16, stroke="#edc596"))
    parts.append(text(utility_x + 44, main_y + 122, "12 recent failures in latest batch", frame.font(15), "#9d5a2f", family=FONT_UI, weight=650))
    parts += button(utility_x + 24, main_y + 170, frame.pw(170), frame.ph(46), "Retry Failed", "#ffffff", ink, stroke="#d8e3e7")
    parts += button(utility_x + 212, main_y + 170, frame.pw(176), frame.ph(46), "Resume 413", "#eaf5f6", accent, stroke="#cae5e8")
    parts += preview_tile(utility_x, main_y + frame.ph(276), frame.pw(488), frame.ph(318), "#ffffff", border, ink, muted, accent)
    parts += labeled_card(utility_x, main_y + frame.ph(614), frame.pw(488), frame.ph(120), "Diagnostics", "Write batch 20  •  Analysis x4  •  Stage overlaps visible.", "#ffffff", border, ink, muted)
    parts += button(utility_x + frame.pw(286), main_y + frame.ph(650), frame.pw(178), frame.ph(54), "Start Run", accent, "#ffffff")
    return group(parts)


def guided_stage_manager(frame: Frame):
    bg = "#f3f2f7"
    ink = "#1e2030"
    muted = "#6a6f88"
    border = "#ddddef"
    accent = "#6f7ee8"
    parts = window_shell(frame, bg, border, ink, "Guided Stage Manager")
    top_y = frame.py(126)
    step_w = frame.pw(458)
    for idx, (label, desc) in enumerate([
        ("Choose Scope", "Editable"),
        ("Confirm Rules", "Active"),
        ("Run", "Ready"),
    ]):
        x = frame.px(56 + idx * 496)
        fill = "#e8ebff" if idx == 1 else "#ffffff"
        stroke = "#cdd4ff" if idx == 1 else "#e0e2ef"
        parts.append(rect(x, top_y, step_w, frame.ph(84), fill, rx=24, stroke=stroke))
        parts.append(circle(x + 34, top_y + 42, 16, "#cfd6ff" if idx == 1 else "#eff1fb"))
        parts.append(text(x + 34, top_y + 48, str(idx + 1), 16, accent, family=FONT_UI, weight=800, anchor="middle"))
        parts.append(text(x + 60, top_y + 40, label, frame.font(22), ink, family=FONT_SANS, weight=700))
        parts.append(text(x + 60, top_y + 62, desc, frame.font(13), muted, family=FONT_UI))

    big_x = frame.px(56)
    big_y = frame.py(244)
    parts += labeled_card(big_x, big_y, frame.pw(920), frame.ph(650), "Current Stage: Confirm Rules", "The stepper makes the flow easier to read without turning it into a rigid wizard.", "#ffffff", border, ink, muted)
    parts += labeled_card(frame.px(1008), big_y, frame.pw(536), frame.ph(300), "Always Editable", "Scope and overwrite controls remain reachable.", "#ffffff", border, ink, muted)
    parts += labeled_card(frame.px(1008), frame.py(566), frame.pw(536), frame.ph(328), "Run Panel", "The operator can still monitor preview and progress here.", "#ffffff", border, ink, muted)
    y = big_y + 94
    for title_text, body in [
        ("Source", "Album / Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Processing Order", "Photos order"),
        ("Overwrite Behavior", "Conservative defaults"),
    ]:
        parts += mini_setting_card(big_x + 28, y, frame.pw(864), frame.ph(98), title_text, body, "#f8f9ff", "#e6e7f2", ink, muted, icon_fill="#b9c2ff")
        y += frame.ph(114)
    parts.append(rect(frame.px(1032), big_y + 92, frame.pw(488), frame.ph(84), "#fff4cb", rx=18, stroke="#ecd387"))
    parts.append(text(frame.px(1056), big_y + 142, "Summary warning stays visible while the user edits any stage.", frame.font(15), "#6d571c", family=FONT_UI, weight=650))
    parts += preview_tile(frame.px(1032), frame.py(620), frame.pw(488), frame.ph(196), "#fafbff", "#e3e5f2", ink, muted, accent)
    parts += button(frame.px(1334), frame.py(834), frame.pw(186), frame.ph(54), "Start Run", accent, "#ffffff")
    return group(parts)


def darkroom_table(frame: Frame):
    bg = "#2a241e"
    ink = "#f4ece0"
    muted = "#c8b6a0"
    border = "#4a4137"
    accent = "#d09d65"
    paper = "#efe3cf"
    parts = window_shell(frame, bg, border, ink, "Darkroom Table", family=FONT_SERIF)
    parts.append(rect(frame.px(24), frame.py(82), frame.pw(1552), frame.ph(892), "#2b241e", rx=30, stroke="#463c34"))
    parts.append(rect(frame.px(56), frame.py(156), frame.pw(900), frame.ph(566), "#3a2f26", rx=28, stroke="#514438"))
    parts.append(rect(frame.px(84), frame.py(184), frame.pw(844), frame.ph(510), paper, rx=14, stroke="#d2c1ab"))
    parts.append(text(frame.px(118), frame.py(228), "FIELD NOTES", frame.font(14), "#7b6248", family=FONT_MONO, weight=700))
    y = frame.py(270)
    for title_text, body in [
        ("Source", "Album / Family Spring Walk"),
        ("Date Filter", "Off"),
        ("Order", "Photos order"),
        ("Overwrite", "Conservative"),
    ]:
        parts.append(text(frame.px(118), y, title_text.upper(), frame.font(16), "#8b6a49", family=FONT_MONO, weight=700))
        parts.append(text(frame.px(286), y, body, frame.font(18), "#342719", family=FONT_SERIF, weight=600))
        parts.append(line(frame.px(116), y + frame.ph(12), frame.px(876), y + frame.ph(12), "#d5c5b2", stroke_width=1.6))
        y += frame.ph(88)
    parts.append(rect(frame.px(1012), frame.py(152), frame.pw(508), frame.ph(314), "#14110d", rx=28, stroke="#544536"))
    parts.append(rect(frame.px(1044), frame.py(184), frame.pw(444), frame.ph(250), "#f0ddba", rx=12))
    parts.append(circle(frame.px(1158), frame.py(306), frame.ph(82), "#d3b68f"))
    parts.append(text(frame.px(1266), frame.py(224), "LIGHTBOX PREVIEW", frame.font(18), ink, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(1266), frame.py(270), "IMG_1187.HEIC", frame.font(20), ink, family=FONT_SERIF, weight=700))
    parts.append(text(frame.px(1266), frame.py(318), "children beneath bright white blossoms", frame.font(17), muted, family=FONT_SERIF, weight=600))
    parts.append(rect(frame.px(1012), frame.py(500), frame.pw(508), frame.ph(222), paper, rx=12, stroke="#d0bea5"))
    parts.append(text(frame.px(1050), frame.py(550), "WORK ORDER", frame.font(18), "#875b35", family=FONT_MONO, weight=800))
    parts.append(text(frame.px(1050), frame.py(598), "Confirm overwrite behavior before the run begins.", frame.font(18), "#3c2d1e", family=FONT_SERIF, weight=600))
    parts.append(rect(frame.px(1208), frame.py(642), frame.pw(236), frame.ph(50), "#c44c3d", rx=8, opacity=0.86))
    parts.append(text(frame.px(1326), frame.py(674), "STAMPED: REVIEW", frame.font(16), "#fff3ed", family=FONT_MONO, weight=800, anchor="middle"))
    parts.append(rect(frame.px(56), frame.py(764), frame.pw(1464), frame.ph(158), "#332921", rx=28, stroke="#514438"))
    parts += progress_bar(frame.px(94), frame.py(818), frame.pw(822), frame.ph(18), accent, "#5a4738", fraction=0.64)
    parts.append(text(frame.px(94), frame.py(874), "835 processed  •  642 changed  •  12 failed  •  ETA 12:40", frame.font(18), muted, family=FONT_MONO))
    parts += button(frame.px(1212), frame.py(802), frame.pw(268), frame.ph(64), "Start Run", accent, "#20150c", family=FONT_MONO)
    return group(parts)


def control_room(frame: Frame):
    bg = "#0b1115"
    ink = "#e6f4fa"
    muted = "#7ba3b4"
    border = "#1d313a"
    accent = "#2bd0e5"
    alert = "#ff8b57"
    parts = window_shell(frame, bg, border, ink, "Control Room", family=FONT_UI)
    parts.append(rect(frame.px(36), frame.py(96), frame.pw(1528), frame.ph(122), "#0f1b21", rx=28, stroke="#1d3038"))
    parts.append(text(frame.px(64), frame.py(148), "RUN STATE: READY WITH CONFIRMATION", frame.font(28), accent, family=FONT_MONO, weight=800))
    parts.append(text(frame.px(64), frame.py(186), "Photos  ->  Ollama  ->  Analysis  ->  Writeback", frame.font(18), muted, family=FONT_MONO))
    for i, label in enumerate(["PHOTOS", "OLLAMA", "ANALYSIS", "WRITEBACK"]):
        x = frame.px(82 + i * 284)
        parts.append(rect(x, frame.py(272), frame.pw(230), frame.ph(138), "#111e24", rx=24, stroke="#24414c"))
        parts.append(circle(x + frame.pw(38), frame.py(324), frame.ph(16), "#16343d", stroke="#2bd0e5"))
        parts.append(text(x + frame.pw(68), frame.py(334), label, frame.font(19), ink, family=FONT_MONO, weight=700))
        parts.append(text(x + frame.pw(68), frame.py(370), ["Library ready", "Model local", "4 workers", "Conservative"][i], frame.font(15), muted, family=FONT_MONO))
        if i < 3:
            parts.append(line(x + frame.pw(236), frame.py(324), x + frame.pw(270), frame.py(324), accent, stroke_width=4))
    parts.append(circle(frame.px(1292), frame.py(612), frame.ph(118), "#102730", stroke="#3dd7e7", stroke_width=5))
    parts.append(circle(frame.px(1292), frame.py(612), frame.ph(86), "#143642", stroke="#2b8897", stroke_width=3))
    parts.append(text(frame.px(1292), frame.py(602), "START", frame.font(28), ink, family=FONT_MONO, weight=800, anchor="middle"))
    parts.append(text(frame.px(1292), frame.py(636), "RUN", frame.font(28), ink, family=FONT_MONO, weight=800, anchor="middle"))
    parts.append(rect(frame.px(58), frame.py(456), frame.pw(820), frame.ph(246), "#0f1b21", rx=24, stroke="#213640"))
    parts.append(text(frame.px(84), frame.py(502), "COMMAND SURFACE", frame.font(22), accent, family=FONT_MONO, weight=700))
    for idx, line_text in enumerate([
        "scope        album / Family Spring Walk",
        "filter       off",
        "order        photos order",
        "overwrite    conservative",
    ]):
        parts.append(text(frame.px(84), frame.py(560 + idx * 44), line_text, frame.font(18), ink, family=FONT_MONO))
    parts.append(rect(frame.px(58), frame.py(730), frame.pw(820), frame.ph(178), "#0f1b21", rx=24, stroke="#213640"))
    parts.append(text(frame.px(84), frame.py(776), "ALERT MODULES", frame.font(22), alert, family=FONT_MONO, weight=700))
    parts.append(rect(frame.px(84), frame.py(804), frame.pw(766), frame.ph(62), "#2a1b16", rx=16, stroke="#744936"))
    parts.append(text(frame.px(108), frame.py(842), "Confirmation required before broader metadata overwrite.", frame.font(16), "#ffb28d", family=FONT_MONO, weight=700))
    parts.append(rect(frame.px(936), frame.py(744), frame.pw(620), frame.ph(164), "#0f1b21", rx=24, stroke="#213640"))
    parts += progress_bar(frame.px(968), frame.py(788), frame.pw(556), frame.ph(20), accent, "#17323b", fraction=0.67)
    parts.append(text(frame.px(968), frame.py(854), "DISC 1248   PROC 835   CHANGED 642   FAIL 12   ETA 12:40", frame.font(17), ink, family=FONT_MONO, weight=700))
    return group(parts)


def gallery_mosaic(frame: Frame):
    bg = "#f4efe8"
    ink = "#2a231d"
    muted = "#7a6c60"
    border = "#e1d6ca"
    accent = "#b3774f"
    parts = window_shell(frame, bg, border, ink, "Gallery Mosaic")
    tiles = [
        (50, 150, 460, 220, "Source", "Album / Family Spring Walk", "#ffffff"),
        (530, 150, 500, 220, "Run Summary", "Warnings and counts stay pinned.", "#fffaf5"),
        (1050, 150, 500, 320, "Last Completed Item", "Hero preview tile", "#ffffff"),
        (50, 390, 300, 190, "Date Filter", "Off", "#fffdfb"),
        (370, 390, 300, 190, "Order", "Photos order", "#fffdfb"),
        (690, 390, 340, 190, "Overwrite", "Conservative", "#fffdfb"),
        (50, 600, 620, 310, "Queued Albums", "Optional workflow queue", "#ffffff"),
        (690, 600, 340, 310, "Diagnostics", "Stage timings", "#fffaf5"),
        (1050, 490, 500, 420, "Run Progress", "KPIs, errors, action buttons", "#ffffff"),
    ]
    for x0, y0, w0, h0, title_text, body, fill in tiles:
        x = frame.px(x0)
        y = frame.py(y0)
        w = frame.pw(w0)
        h = frame.ph(h0)
        parts.append(rect(x, y, w, h, fill, rx=26, stroke="#e3d8cd"))
        parts.append(text(x + 24, y + 38, title_text, 22, ink, family=FONT_SANS, weight=700))
        parts.append(text(x + 24, y + 64, body, 14, muted, family=FONT_UI))
    parts.append(rect(frame.px(1080), frame.py(198), frame.pw(440), frame.ph(220), "#ead7c5", rx=18))
    parts.append(circle(frame.px(1190), frame.py(286), frame.ph(68), "#d2b39d"))
    parts.append(text(frame.px(1068), frame.py(560), "Disc 1248", frame.font(18), ink, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(1220), frame.py(560), "Proc 835", frame.font(18), ink, family=FONT_MONO, weight=700))
    parts.append(text(frame.px(1362), frame.py(560), "ETA 12:40", frame.font(18), ink, family=FONT_MONO, weight=700))
    parts.append(rect(frame.px(1078), frame.py(620), frame.pw(444), frame.ph(62), "#fff2e6", rx=16, stroke="#e8c39f"))
    parts.append(text(frame.px(1100), frame.py(658), "12 recent failures need review.", frame.font(15), "#9d5a2f", family=FONT_UI, weight=650))
    parts += button(frame.px(1270), frame.py(820), frame.pw(252), frame.ph(56), "Start Run", accent, "#ffffff")
    return group(parts)


def orbital_command(frame: Frame):
    bg = "#eef2fa"
    ink = "#1d2540"
    muted = "#6a7391"
    border = "#d7dff5"
    accent = "#6f82ff"
    parts = window_shell(frame, bg, border, ink, "Orbital Command")
    cx = frame.px(780)
    cy = frame.py(540)
    outer_r = frame.ph(255)
    mid_r = frame.ph(175)
    inner_r = frame.ph(92)
    parts.append(circle(cx, cy, outer_r, "none", stroke="#cfd8ff", stroke_width=3))
    parts.append(circle(cx, cy, mid_r, "none", stroke="#dbe2ff", stroke_width=2.5, opacity=0.9))
    parts.append(circle(cx, cy, inner_r, "#6f82ff", stroke="#5d71ef", stroke_width=4))
    parts.append(text(cx, cy - 8, "START", frame.font(30), "#ffffff", family=FONT_UI, weight=800, anchor="middle"))
    parts.append(text(cx, cy + 32, "RUN", frame.font(30), "#ffffff", family=FONT_UI, weight=800, anchor="middle"))
    orbit_labels = [
        (0, "Source", "Album"),
        (72, "Safeguards", "Pinned"),
        (144, "Capabilities", "Ready"),
        (216, "Progress", "Live"),
        (288, "Preview", "Latest item"),
    ]
    for angle_deg, title_text, body in orbit_labels:
        angle = math.radians(angle_deg - 90)
        ox = cx + math.cos(angle) * mid_r
        oy = cy + math.sin(angle) * mid_r
        parts.append(circle(ox, oy, frame.ph(58), "#ffffff", stroke="#d8def8", stroke_width=2.5))
        parts.append(text(ox, oy - 4, title_text, frame.font(16), ink, family=FONT_UI, weight=700, anchor="middle"))
        parts.append(text(ox, oy + 20, body, frame.font(12), muted, family=FONT_UI, weight=600, anchor="middle"))
    parts += labeled_card(frame.px(52), frame.py(170), frame.pw(390), frame.ph(280), "Selected Orbit", "Every orbit opens a focused detail panel.", "#ffffff", border, ink, muted)
    parts.append(text(frame.px(80), frame.py(248), "Source  •  Album / Family Spring Walk", frame.font(17), ink, family=FONT_UI, weight=650))
    parts.append(text(frame.px(80), frame.py(292), "Filter  •  Off", frame.font(17), ink, family=FONT_UI, weight=650))
    parts.append(text(frame.px(80), frame.py(336), "Order   •  Photos order", frame.font(17), ink, family=FONT_UI, weight=650))
    parts += labeled_card(frame.px(1124), frame.py(170), frame.pw(424), frame.ph(300), "Run Summary", "Implementable, but intentionally strange.", "#ffffff", border, ink, muted)
    parts.append(rect(frame.px(1148), frame.py(298), frame.pw(376), frame.ph(68), "#f6efc8", rx=18, stroke="#e9d281"))
    parts.append(text(frame.px(1172), frame.py(338), "Confirmation still required before wider writes.", frame.font(14), "#69551d", family=FONT_UI, weight=650))
    parts += preview_tile(frame.px(1124), frame.py(508), frame.pw(424), frame.ph(320), "#ffffff", border, ink, muted, accent)
    parts.append(text(frame.px(80), frame.py(760), "This is the most experimental concept here, but it is still buildable as a main-screen shell.", frame.font(15), muted, family=FONT_UI))
    return group(parts)


def museum_labels(frame: Frame):
    bg = "#f6f3ec"
    ink = "#241f19"
    muted = "#7b6e62"
    border = "#e0d8cb"
    accent = "#a57247"
    parts = window_shell(frame, bg, border, ink, "Museum Labels", family=FONT_SERIF)
    hero_x = frame.px(360)
    hero_y = frame.py(150)
    hero_w = frame.pw(880)
    hero_h = frame.ph(650)
    parts.append(rect(hero_x, hero_y, hero_w, hero_h, "#fdfbf8", rx=28, stroke="#e2d8ca"))
    parts.append(rect(hero_x + 28, hero_y + 28, hero_w - 56, hero_h - 56, "#ede3d4", rx=18))
    parts.append(circle(hero_x + hero_w * 0.42, hero_y + hero_h * 0.45, frame.ph(106), "#d7b89d"))
    plaques = [
        (frame.px(74), frame.py(186), frame.pw(238), frame.ph(128), "Source", "Album / Family Spring Walk"),
        (frame.px(74), frame.py(356), frame.pw(238), frame.ph(128), "Order", "Photos order"),
        (frame.px(74), frame.py(526), frame.pw(238), frame.ph(164), "Overwrite Rules", "Conservative writes, visible before start"),
        (frame.px(1276), frame.py(220), frame.pw(244), frame.ph(154), "Run Summary", "Estimated 1,248 items"),
        (frame.px(1276), frame.py(424), frame.pw(244), frame.ph(154), "Progress", "835 processed / ETA 12:40"),
        (frame.px(1276), frame.py(628), frame.pw(244), frame.ph(154), "Actions", "Retry / Resume / Start"),
    ]
    for x, y, w0, h0, title_text, body in plaques:
        parts.append(rect(x, y, w0, h0, "#fffdf9", rx=18, stroke="#e1d8cb"))
        parts.append(text(x + 18, y + 34, title_text, 18, accent, family=FONT_MONO, weight=700))
        parts.append(text(x + 18, y + 68, body, 16, ink, family=FONT_SERIF, weight=600))
    parts.append(text(hero_x + 40, hero_y + hero_h + 56, "Main-screen hero preview with functional annotation plaques orbiting the image.", frame.font(18), muted, family=FONT_UI))
    parts += button(frame.px(1302), frame.py(712), frame.pw(184), frame.ph(52), "Start Run", accent, "#fff8f1", family=FONT_UI)
    return group(parts)


def hybrid_quiet_workbench(frame: Frame):
    bg = "#eef2f5"
    ink = "#182430"
    muted = "#617180"
    border = "#d8e0e8"
    accent = "#4b7ea3"
    parts = window_shell(frame, bg, border, ink, "Hybrid A")
    parts.append(rect(frame.px(38), frame.py(92), frame.pw(1524), frame.ph(106), "#fbfcfd", rx=26, stroke="#dde4ea"))
    parts.append(text(frame.px(64), frame.py(136), "Quiet Utility + Native Pro + Album Workbench", frame.font(24), ink, family=FONT_SANS, weight=750))
    parts.append(text(frame.px(64), frame.py(172), "Calm main column, pinned safeguards, and a dedicated album browser.", frame.font(16), muted, family=FONT_UI))
    for i, label in enumerate(["Automation ready", "Model ready", "Picker supported"]):
        parts += pill(frame.px(1080 + i * 150), frame.py(112), frame.pw(132), frame.ph(32), label, "#e9f0f5", accent)

    browser_x = frame.px(42)
    main_y = frame.py(224)
    browser_w = frame.pw(236)
    setup_x = frame.px(300)
    setup_w = frame.pw(760)
    right_x = frame.px(1084)
    right_w = frame.pw(474)

    parts += labeled_card(browser_x, main_y, browser_w, frame.ph(692), "Albums", "Chooser stays visible.", "#f9fbfc", border, ink, muted)
    album_names = ["Family Spring Walk", "Birthday Dinner", "Lake Weekend", "Garden May", "Videos To Review"]
    counts = [1248, 382, 460, 278, 91]
    for idx, (name, count) in enumerate(zip(album_names, counts)):
        y = main_y + 78 + idx * 102
        fill = "#eaf2f7" if idx == 0 else "#ffffff"
        stroke = "#cfdeea" if idx == 0 else "#e0e6eb"
        parts.append(rect(browser_x + 18, y, browser_w - 36, 80, fill, rx=18, stroke=stroke))
        parts.append(text(browser_x + 36, y + 34, name, 16, ink, family=FONT_UI, weight=650))
        parts.append(text(browser_x + 36, y + 58, f"{count} items", 13, muted, family=FONT_UI))

    parts += labeled_card(setup_x, main_y, setup_w, frame.ph(692), "Setup", "Quiet vertical stack with stronger hierarchy.", "#ffffff", border, ink, muted)
    cards = [
        ("Source", "Album / Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Processing Order", "Photos order (recommended)"),
        ("Overwrite Behavior", "Preserve external metadata unless confirmed"),
    ]
    y = main_y + 78
    for title_text, body in cards:
        parts += mini_setting_card(setup_x + 24, y, setup_w - 48, 108, title_text, body, "#f7fafc", "#e3eaf0", ink, muted, icon_fill="#8db3cb")
        y += 124
    parts += progress_bar(setup_x + 24, main_y + 626, setup_w - 48, 16, accent, "#dee8ef", fraction=0.68)
    parts.append(text(setup_x + 24, main_y + 666, "835 processed  •  642 changed  •  12 failed  •  ETA 12:40", 15, muted, family=FONT_MONO))

    parts += labeled_card(right_x, main_y, right_w, frame.ph(300), "Run Summary", "Pinned safeguards stay readable before Start.", "#ffffff", border, ink, muted)
    parts.append(text(right_x + 24, main_y + 94, "Album  •  Family Spring Walk", 16, ink, family=FONT_UI, weight=650))
    parts.append(text(right_x + 24, main_y + 136, "Estimated 1,248 items", 16, ink, family=FONT_UI, weight=650))
    parts.append(text(right_x + 24, main_y + 178, "Writes  •  captions + keywords", 16, ink, family=FONT_UI, weight=650))
    parts.append(rect(right_x + 24, main_y + 212, right_w - 48, 64, "#f8efcf", rx=16, stroke="#ead48c"))
    parts.append(text(right_x + 48, main_y + 251, "Confirmation required before broader metadata overwrite.", 14, "#6f581d", family=FONT_UI, weight=650))
    parts += preview_tile(right_x, main_y + 324, right_w, frame.ph(368), "#ffffff", border, ink, muted, accent)

    tray_y = frame.py(934)
    parts.append(rect(frame.px(42), tray_y, frame.pw(1516), frame.ph(44), "#fbfcfd", rx=18, stroke="#dde4ea"))
    parts.append(text(frame.px(70), tray_y + frame.ph(28), "Ready with confirmation", frame.font(16), ink, family=FONT_UI, weight=700))
    parts += button(frame.px(1220), tray_y + frame.ph(5), frame.pw(126), frame.ph(34), "Resume", "#ffffff", ink, stroke="#d8e1e8")
    parts += button(frame.px(1364), tray_y + frame.ph(3), frame.pw(168), frame.ph(38), "Start Run", accent, "#ffffff")
    return group(parts)


def hybrid_glass_browser(frame: Frame):
    bg = "#dbe8ee"
    ink = "#163145"
    muted = "#5b7688"
    accent = "#4a8eb7"
    parts = window_shell(frame, bg, "#c9dce7", ink, "Hybrid B")
    parts.append(circle(frame.px(1320), frame.py(168), frame.ph(190), "#c8e3ef", opacity=0.6))
    parts.append(circle(frame.px(260), frame.py(820), frame.ph(220), "#eef8fb", opacity=0.55))

    def glass(x, y, w, h):
        return rect(x, y, w, h, "#ffffff", rx=28, stroke="#ffffff", stroke_width=1.1, opacity=0.44)

    browser_x = frame.px(44)
    setup_x = frame.px(296)
    right_x = frame.px(1110)
    top_y = frame.py(108)
    parts.append(glass(frame.px(44), top_y, frame.pw(1512), frame.ph(86)))
    parts.append(text(frame.px(70), frame.py(154), "Glass Sheet + Album Workbench", frame.font(25), ink, family=FONT_SANS, weight=760))
    parts.append(text(frame.px(70), frame.py(184), "Softened frosted treatment with a more practical album browser.", frame.font(15), muted, family=FONT_UI))
    parts.append(glass(browser_x, frame.py(222), frame.pw(220), frame.ph(704)))
    parts.append(glass(setup_x, frame.py(222), frame.pw(782), frame.ph(704)))
    parts.append(glass(right_x, frame.py(222), frame.pw(446), frame.ph(704)))
    parts.append(text(browser_x + 20, frame.py(264), "Albums", frame.font(22), ink, family=FONT_SANS, weight=700))
    for idx, name in enumerate(["Family Spring Walk", "Birthday Dinner", "Lake Weekend", "Garden May", "Videos To Review"]):
        y = frame.py(302 + idx * 112)
        parts.append(rect(browser_x + 16, y, frame.pw(188), frame.ph(84), "#ffffff", rx=18, stroke="#e0eef3", opacity=0.76))
        parts.append(text(browser_x + 34, y + frame.ph(34), name, frame.font(15), ink, family=FONT_UI, weight=650))
    parts.append(text(setup_x + 24, frame.py(264), "Run Setup", frame.font(22), ink, family=FONT_SANS, weight=700))
    y = frame.py(304)
    for title_text, body in [
        ("Source", "Album / Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Processing Order", "Photos order (recommended)"),
        ("Overwrite Behavior", "Preserve external metadata unless confirmed"),
    ]:
        parts += mini_setting_card(setup_x + 22, y, frame.pw(738), frame.ph(100), title_text, body, "#ffffff", "#ddecf3", ink, muted, icon_fill="#9cc4d7")
        y += frame.ph(118)
    parts += progress_bar(setup_x + 22, frame.py(838), frame.pw(738), frame.ph(16), accent, "#d7e8ef", fraction=0.63)
    parts.append(text(setup_x + 22, frame.py(882), "Throughput 6.1/min  •  Elapsed 02:18:14  •  ETA 12:40", frame.font(15), muted, family=FONT_MONO))
    parts.append(text(right_x + 22, frame.py(264), "Run Summary", frame.font(22), ink, family=FONT_SANS, weight=700))
    parts.append(rect(right_x + 22, frame.py(316), frame.pw(402), frame.ph(68), "#edf4d8", rx=18, stroke="#d8e7aa", opacity=0.86))
    parts.append(text(right_x + 44, frame.py(356), "Safer defaults stay visually foregrounded.", frame.font(14), "#607136", family=FONT_UI, weight=650))
    parts += preview_tile(right_x + 10, frame.py(410), frame.pw(426), frame.ph(332), "#ffffff", "#ddecf3", ink, muted, accent)
    parts += button(right_x + frame.pw(248), frame.py(840), frame.pw(176), frame.ph(56), "Start Run", accent, "#ffffff")
    return group(parts)


def hybrid_native_browser(frame: Frame):
    bg = "#eff2f5"
    ink = "#16222d"
    muted = "#61707c"
    border = "#d9e1e7"
    accent = "#4a7fa6"
    parts = window_shell(frame, bg, border, ink, "Hybrid C")
    parts.append(rect(frame.px(40), frame.py(92), frame.pw(1520), frame.ph(92), "#ffffff", rx=24, stroke="#dee5eb"))
    parts.append(text(frame.px(66), frame.py(138), "Native Pro + Album Workbench", frame.font(26), ink, family=FONT_SANS, weight=760))
    parts.append(text(frame.px(66), frame.py(168), "Most implementation-ready option: polished, quiet, and explicitly safety-first.", frame.font(15), muted, family=FONT_UI))

    browser_x = frame.px(42)
    browser_w = frame.pw(250)
    main_x = frame.px(316)
    main_w = frame.pw(738)
    right_x = frame.px(1078)
    right_w = frame.pw(480)
    y0 = frame.py(214)
    h0 = frame.ph(716)

    parts += labeled_card(browser_x, y0, browser_w, h0, "Album Browser", "Pinned while you configure the run.", "#fafbfc", border, ink, muted)
    for idx, name in enumerate(["Family Spring Walk", "Birthday Dinner", "Lake Weekend", "Garden May", "Videos To Review"]):
        y = y0 + 82 + idx * 104
        fill = "#edf4f8" if idx == 0 else "#ffffff"
        parts.append(rect(browser_x + 16, y, browser_w - 32, 80, fill, rx=18, stroke="#dfe6eb"))
        parts.append(text(browser_x + 34, y + 34, name, 15, ink, family=FONT_UI, weight=650))

    parts += labeled_card(main_x, y0, main_w, h0, "Setup", "Current structure, cleaned up rather than reinvented.", "#ffffff", border, ink, muted)
    cards = [
        ("Source", "Album / Family Spring Walk"),
        ("Capture Date Filter", "Off"),
        ("Processing Order", "Photos order (recommended)"),
        ("Overwrite Behavior", "Preserve external metadata unless confirmed"),
        ("Queued Albums", "Optional secondary workflow"),
    ]
    y = y0 + 82
    for title_text, body in cards:
        parts += mini_setting_card(main_x + 22, y, main_w - 44, 92, title_text, body, "#f8fafc", "#e4ebf0", ink, muted, icon_fill="#8db4cb")
        y += 108
    parts += progress_bar(main_x + 22, y0 + 654, main_w - 44, 15, accent, "#dce7ee", fraction=0.66)
    parts.append(text(main_x + 22, y0 + 694, "Run progress and preview stay below or to the right without hiding safeguards.", 14, muted, family=FONT_UI))

    parts += labeled_card(right_x, y0, right_w, frame.ph(286), "Run Summary", "Pinned inspector with clear confirmation callouts.", "#ffffff", border, ink, muted)
    parts.append(rect(right_x + 22, y0 + 180, right_w - 44, 64, "#f8efcf", rx=16, stroke="#ead48c"))
    parts.append(text(right_x + 44, y0 + 218, "Confirmation required before broader metadata overwrite.", 14, "#6f581d", family=FONT_UI, weight=650))
    parts += preview_tile(right_x, y0 + 312, right_w, frame.ph(404), "#ffffff", border, ink, muted, accent)
    parts += button(right_x + frame.pw(292), frame.py(948), frame.pw(186), frame.ph(40), "Start Run", accent, "#ffffff")
    return group(parts)


CONCEPTS = [
    ("01_quiet_utility", "Quiet Utility", quiet_utility),
    ("02_inspector_split", "Inspector Split", inspector_split),
    ("03_checklist_launchpad", "Checklist Launchpad", checklist_launchpad),
    ("04_monospace_ops", "Monospace Ops", monospace_ops),
    ("05_glass_sheet", "Glass Sheet", glass_sheet),
    ("06_native_pro", "Native Pro", native_pro),
    ("07_workflow_board", "Workflow Board", workflow_board),
    ("08_album_workbench", "Album Workbench", album_workbench),
    ("09_operations_console", "Operations Console", operations_console),
    ("10_guided_stage_manager", "Guided Stage Manager", guided_stage_manager),
    ("11_darkroom_table", "Darkroom Table", darkroom_table),
    ("12_control_room", "Control Room", control_room),
    ("13_gallery_mosaic", "Gallery Mosaic", gallery_mosaic),
    ("14_orbital_command", "Orbital Command", orbital_command),
    ("15_museum_labels", "Museum Labels", museum_labels),
]

HYBRIDS = [
    ("16_hybrid_quiet_workbench", "Hybrid A — Quiet Workbench", hybrid_quiet_workbench),
    ("17_hybrid_glass_browser", "Hybrid B — Glass Browser", hybrid_glass_browser),
    ("18_hybrid_native_browser", "Hybrid C — Native Browser", hybrid_native_browser),
]


def make_svg(content: str, width: int, height: int) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" fill="none">'
        f'{content}</svg>'
    )


def render_full(concept_func) -> str:
    frame = Frame(0, 0, W, H)
    return make_svg(concept_func(frame), W, H)


def render_contact_sheet() -> str:
    sheet_w = 1800
    sheet_h = 2900
    margin = 48
    gap = 32
    cols = 3
    rows = 5
    tile_w = (sheet_w - margin * 2 - gap * (cols - 1)) / cols
    tile_h = (sheet_h - margin * 2 - gap * (rows - 1)) / rows
    pieces = [rect(0, 0, sheet_w, sheet_h, "#f3f4f7", rx=0)]
    pieces.append(text(margin, 42, "Photos Caption Assistant — Main Screen Treatments", 30, "#1b2230", family=FONT_SANS, weight=800))
    pieces.append(text(sheet_w - margin, 42, "15 locally rendered mockups", 17, "#6b7280", family=FONT_UI, weight=600, anchor="end"))
    for index, (slug, title_text, concept_func) in enumerate(CONCEPTS):
        row = index // cols
        col = index % cols
        x = margin + col * (tile_w + gap)
        y = margin + row * (tile_h + gap) + 24
        pieces.append(rect(x, y, tile_w, tile_h, "#ffffff", rx=26, stroke="#d9dce3"))
        pieces.append(text(x + 18, y + 34, f"{index + 1:02d}  {title_text}", 17, "#1d2430", family=FONT_SANS, weight=750))
        inner = Frame(x + 14, y + 52, tile_w - 28, tile_h - 66)
        pieces.append(concept_func(inner))
    return make_svg(group(pieces), sheet_w, sheet_h)


def render_subset_sheet(title_text: str, concepts) -> str:
    sheet_w = 1800
    sheet_h = 2100
    margin = 54
    gap = 34
    cols = 2
    rows = 3
    tile_w = (sheet_w - margin * 2 - gap * (cols - 1)) / cols
    tile_h = (sheet_h - margin * 2 - 60 - gap * (rows - 1)) / rows
    pieces = [rect(0, 0, sheet_w, sheet_h, "#f3f4f7", rx=0)]
    pieces.append(text(margin, 48, f"Photos Caption Assistant — {title_text}", 31, "#1b2230", family=FONT_SANS, weight=800))
    pieces.append(text(sheet_w - margin, 48, "Main screen concepts", 17, "#6b7280", family=FONT_UI, weight=600, anchor="end"))
    for index, (_, concept_name, concept_func) in enumerate(concepts):
        row = index // cols
        col = index % cols
        x = margin + col * (tile_w + gap)
        y = margin + row * (tile_h + gap) + 70
        pieces.append(rect(x, y, tile_w, tile_h, "#ffffff", rx=28, stroke="#d9dce3"))
        pieces.append(text(x + 20, y + 38, f"{index + 1}. {concept_name}", 18, "#1d2430", family=FONT_SANS, weight=760))
        inner = Frame(x + 14, y + 56, tile_w - 28, tile_h - 72)
        pieces.append(concept_func(inner))
    return make_svg(group(pieces), sheet_w, sheet_h)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for slug, _, concept_func in CONCEPTS + HYBRIDS:
        svg_path = OUT_DIR / f"{slug}.svg"
        svg_path.write_text(render_full(concept_func), encoding="utf-8")

    contact_svg = OUT_DIR / "contact_sheet.svg"
    contact_svg.write_text(render_contact_sheet(), encoding="utf-8")
    (OUT_DIR / "minimal_sheet.svg").write_text(render_subset_sheet("Minimal Treatments", CONCEPTS[:5]), encoding="utf-8")
    (OUT_DIR / "normal_sheet.svg").write_text(render_subset_sheet("Normal Treatments", CONCEPTS[5:10]), encoding="utf-8")
    (OUT_DIR / "out_there_sheet.svg").write_text(render_subset_sheet("Completely Out There Treatments", CONCEPTS[10:]), encoding="utf-8")
    (OUT_DIR / "selected_hybrids_sheet.svg").write_text(render_subset_sheet("Selected Hybrid Directions", HYBRIDS), encoding="utf-8")


if __name__ == "__main__":
    main()
