from __future__ import annotations

import html
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path("/Users/jkfisher/Resilio Sync/Family Documents/Codex/PhotoDescriptionCreator")
OUT_DIR = ROOT / "output/mockups/immersive_view_treatments"
W = 1600
H = 1000
CHROME_BIN = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

SCREENSHOT_DIR = Path(
    "/var/folders/pg/mm_g1q1j69x21gzg9qk7x8d00000gn/T/TemporaryItems/NSIRD_screencaptureui_7QSs4H"
)
SCREENSHOT_GLOB = "Screenshot 2026-04-03 at 1.02.20*AM.png"
SCREENSHOT_CROP = (1660, 1240, 150, 300)

SAMPLE_PHOTO_PATH = OUT_DIR / "sample_soccer_photo.png"
SAMPLE_BLUR_PATH = OUT_DIR / "sample_soccer_photo_blur.png"

FONT_SANS = "Arial"
FONT_UI = "Helvetica"
FONT_SERIF = "Georgia"
FONT_MONO = "Courier New"
FONT_BLACK = "Arial Black"

DATA = {
    "filename": "IMG_9415.HEIC",
    "source": "First game",
    "captured": "Mar 29, 2026 at 11:14 AM",
    "caption_lines": [
        "group of soccer players",
        "listening to coach on field",
    ],
    "caption_three_lines": [
        "group of soccer players",
        "listening to coach",
        "on field",
    ],
    "keywords": [
        "group",
        "soccer",
        "players",
        "coach",
        "field",
        "listening",
        "uniforms",
        "outdoor",
        "training",
    ],
    "progress": [
        ("Discovered", "12"),
        ("Processed", "1"),
        ("Changed", "1"),
        ("Skipped", "0"),
        ("Failed", "0"),
    ],
    "pace": [
        ("Rate", "0.58 items/min"),
        ("Elapsed", "01:43"),
        ("ETA", "18:53"),
    ],
}


@dataclass
class Doc:
    defs: list[str]
    parts: list[str]
    counter: int = 0

    def __init__(self) -> None:
        self.defs = []
        self.parts = []
        self.counter = 0

    def next_id(self, prefix: str) -> str:
        self.counter += 1
        return f"{prefix}{self.counter}"

    def define(self, *items: str) -> None:
        self.defs.extend(items)

    def add(self, *items: str) -> None:
        self.parts.extend(items)


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def fmt(value: float) -> str:
    return f"{value:.2f}"


def rect(
    x: float,
    y: float,
    w: float,
    h: float,
    fill: str,
    rx: float = 0,
    stroke: str | None = None,
    stroke_width: float = 1.5,
    opacity: float = 1.0,
) -> str:
    attrs = [
        f'x="{fmt(x)}"',
        f'y="{fmt(y)}"',
        f'width="{fmt(w)}"',
        f'height="{fmt(h)}"',
        f'fill="{fill}"',
        f'rx="{fmt(rx)}"',
        f'opacity="{opacity:.3f}"',
    ]
    if stroke:
        attrs.append(f'stroke="{stroke}"')
        attrs.append(f'stroke-width="{fmt(stroke_width)}"')
    return "<rect " + " ".join(attrs) + " />"


def circle(
    cx: float,
    cy: float,
    r: float,
    fill: str,
    opacity: float = 1.0,
    stroke: str | None = None,
    stroke_width: float = 1.5,
) -> str:
    attrs = [
        f'cx="{fmt(cx)}"',
        f'cy="{fmt(cy)}"',
        f'r="{fmt(r)}"',
        f'fill="{fill}"',
        f'opacity="{opacity:.3f}"',
    ]
    if stroke:
        attrs.append(f'stroke="{stroke}"')
        attrs.append(f'stroke-width="{fmt(stroke_width)}"')
    return "<circle " + " ".join(attrs) + " />"


def line(
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    stroke: str,
    stroke_width: float = 1.5,
    opacity: float = 1.0,
    dash: str | None = None,
) -> str:
    attrs = [
        f'x1="{fmt(x1)}"',
        f'y1="{fmt(y1)}"',
        f'x2="{fmt(x2)}"',
        f'y2="{fmt(y2)}"',
        f'stroke="{stroke}"',
        f'stroke-width="{fmt(stroke_width)}"',
        f'opacity="{opacity:.3f}"',
        'stroke-linecap="round"',
    ]
    if dash:
        attrs.append(f'stroke-dasharray="{dash}"')
    return "<line " + " ".join(attrs) + " />"


def text(
    x: float,
    y: float,
    content: str,
    size: float,
    fill: str,
    family: str = FONT_SANS,
    weight: int = 500,
    anchor: str = "start",
    opacity: float = 1.0,
    letter_spacing: float | None = None,
) -> str:
    attrs = [
        f'x="{fmt(x)}"',
        f'y="{fmt(y)}"',
        f'fill="{fill}"',
        f'font-family="{family}"',
        f'font-size="{fmt(size)}"',
        f'font-weight="{weight}"',
        f'text-anchor="{anchor}"',
        f'opacity="{opacity:.3f}"',
    ]
    if letter_spacing is not None:
        attrs.append(f'letter-spacing="{fmt(letter_spacing)}"')
    return "<text " + " ".join(attrs) + f">{esc(content)}</text>"


def text_block(
    x: float,
    y: float,
    lines: list[str],
    size: float,
    fill: str,
    family: str = FONT_SANS,
    weight: int = 700,
    anchor: str = "start",
    opacity: float = 1.0,
    line_height: float = 1.18,
) -> str:
    attrs = [
        f'x="{fmt(x)}"',
        f'y="{fmt(y)}"',
        f'fill="{fill}"',
        f'font-family="{family}"',
        f'font-size="{fmt(size)}"',
        f'font-weight="{weight}"',
        f'text-anchor="{anchor}"',
        f'opacity="{opacity:.3f}"',
    ]
    pieces = ["<text " + " ".join(attrs) + ">"]
    for index, line_text in enumerate(lines):
        dy = "0" if index == 0 else fmt(size * line_height)
        pieces.append(f'<tspan x="{fmt(x)}" dy="{dy}">{esc(line_text)}</tspan>')
    pieces.append("</text>")
    return "".join(pieces)


def file_uri(path: Path) -> str:
    return str(path.resolve())


def clipped_image(
    doc: Doc,
    x: float,
    y: float,
    w: float,
    h: float,
    href: str,
    rx: float = 0,
    preserve: str = "xMidYMid slice",
    opacity: float = 1.0,
    stroke: str | None = None,
    stroke_width: float = 1.5,
) -> str:
    clip_id = doc.next_id("clip")
    doc.define(
        f'<clipPath id="{clip_id}">{rect(x, y, w, h, "#ffffff", rx=rx)}</clipPath>'
    )
    parts = [
        (
            f'<image href="{href}" xlink:href="{href}" x="{fmt(x)}" y="{fmt(y)}" '
            f'width="{fmt(w)}" height="{fmt(h)}" preserveAspectRatio="{preserve}" '
            f'clip-path="url(#{clip_id})" opacity="{opacity:.3f}" />'
        )
    ]
    if stroke:
        parts.append(rect(x, y, w, h, "none", rx=rx, stroke=stroke, stroke_width=stroke_width))
    return "".join(parts)


def linear_gradient(doc: Doc, colors: list[tuple[str, float]], x1: str, y1: str, x2: str, y2: str) -> str:
    grad_id = doc.next_id("lg")
    stops = "".join(
        f'<stop offset="{offset * 100:.1f}%" stop-color="{color}" />'
        for color, offset in colors
    )
    doc.define(
        f'<linearGradient id="{grad_id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{stops}</linearGradient>'
    )
    return f"url(#{grad_id})"


def radial_gradient(doc: Doc, colors: list[tuple[str, float]], cx: str = "50%", cy: str = "50%", r: str = "70%") -> str:
    grad_id = doc.next_id("rg")
    stops = "".join(
        f'<stop offset="{offset * 100:.1f}%" stop-color="{color}" />'
        for color, offset in colors
    )
    doc.define(f'<radialGradient id="{grad_id}" cx="{cx}" cy="{cy}" r="{r}">{stops}</radialGradient>')
    return f"url(#{grad_id})"


def close_button(doc: Doc, fill: str, bg: str, ring: str, x: float = W - 64, y: float = 58) -> None:
    doc.add(circle(x, y, 22, bg, opacity=0.86, stroke=ring, stroke_width=1.5))
    doc.add(line(x - 7, y - 7, x + 7, y + 7, fill, stroke_width=2.3))
    doc.add(line(x + 7, y - 7, x - 7, y + 7, fill, stroke_width=2.3))


def pill(x: float, y: float, w: float, h: float, label: str, fill: str, fg: str, family: str = FONT_UI, weight: int = 650, stroke: str | None = None, opacity: float = 1.0) -> str:
    return (
        rect(x, y, w, h, fill, rx=h / 2, stroke=stroke, opacity=opacity)
        + text(x + w / 2, y + h * 0.67, label, h * 0.44, fg, family=family, weight=weight, anchor="middle")
    )


def metric_card(x: float, y: float, w: float, h: float, label: str, value: str, fill: str, fg: str, muted: str, stroke: str | None = None) -> str:
    return (
        rect(x, y, w, h, fill, rx=14, stroke=stroke)
        + text(x + 14, y + 22, label, 11, muted, family=FONT_UI, weight=700)
        + text(x + 14, y + 46, value, 18, fg, family=FONT_UI, weight=700)
    )


def compact_metric(x: float, y: float, w: float, h: float, label: str, value: str, fill: str, fg: str, muted: str, stroke: str | None = None) -> str:
    return (
        rect(x, y, w, h, fill, rx=12, stroke=stroke)
        + text(x + 12, y + 18, label, 10, muted, family=FONT_UI, weight=700)
        + text(x + 12, y + 36, value, 13, fg, family=FONT_UI, weight=700)
    )


def render_progress_grid(
    doc: Doc,
    x: float,
    y: float,
    card_w: float,
    card_h: float,
    gap: float,
    fill: str,
    fg: str,
    muted: str,
    stroke: str | None = None,
) -> None:
    for index, (label, value) in enumerate(DATA["progress"]):
        doc.add(metric_card(x + index * (card_w + gap), y, card_w, card_h, label, value, fill, fg, muted, stroke))


def render_pace_row(
    doc: Doc,
    x: float,
    y: float,
    widths: list[float],
    h: float,
    fill: str,
    fg: str,
    muted: str,
    stroke: str | None = None,
) -> None:
    cursor = x
    for width, (label, value) in zip(widths, DATA["pace"], strict=True):
        doc.add(compact_metric(cursor, y, width, h, label, value, fill, fg, muted, stroke))
        cursor += width + 10


def render_keyword_pills(
    doc: Doc,
    x: float,
    y: float,
    max_width: float,
    fill: str,
    fg: str,
    stroke: str | None = None,
    family: str = FONT_UI,
) -> None:
    cursor_x = x
    cursor_y = y
    row_h = 36
    for keyword in DATA["keywords"]:
        width = max(76, 26 + len(keyword) * 9)
        if cursor_x + width > x + max_width:
            cursor_x = x
            cursor_y += row_h + 10
        doc.add(pill(cursor_x, cursor_y, width, row_h, keyword, fill, fg, family=family, stroke=stroke))
        cursor_x += width + 12


def render_label_value(
    doc: Doc,
    x: float,
    y: float,
    label: str,
    value: str,
    label_fill: str,
    value_fill: str,
    label_size: float = 11,
    value_size: float = 15,
    family: str = FONT_UI,
    value_family: str | None = None,
) -> None:
    doc.add(text(x, y, label, label_size, label_fill, family=FONT_UI, weight=700, letter_spacing=0.8))
    doc.add(text(x, y + 24, value, value_size, value_fill, family=value_family or family, weight=700 if value_size >= 20 else 600))


def ensure_sample_images() -> tuple[str, str]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    screenshot_path = next(iter(SCREENSHOT_DIR.glob(SCREENSHOT_GLOB)), None)

    if not SAMPLE_PHOTO_PATH.exists():
        if screenshot_path is None or not screenshot_path.exists():
            raise FileNotFoundError("Sample screenshot was not found and no cached sample photo exists.")
        crop_w, crop_h, crop_x, crop_y = SCREENSHOT_CROP
        subprocess.run(
            [
                "magick",
                str(screenshot_path),
                "-crop",
                f"{crop_w}x{crop_h}+{crop_x}+{crop_y}",
                "+repage",
                str(SAMPLE_PHOTO_PATH),
            ],
            check=True,
        )

    if not SAMPLE_BLUR_PATH.exists():
        subprocess.run(
            [
                "magick",
                str(SAMPLE_PHOTO_PATH),
                "-resize",
                f"{W}x{H}^",
                "-gravity",
                "center",
                "-extent",
                f"{W}x{H}",
                "-gaussian-blur",
                "0x18",
                "-brightness-contrast",
                "-5x-12",
                str(SAMPLE_BLUR_PATH),
            ],
            check=True,
        )

    return file_uri(SAMPLE_PHOTO_PATH), file_uri(SAMPLE_BLUR_PATH)


def base_canvas(doc: Doc, fill: str = "#0b0d10") -> None:
    doc.add(rect(0, 0, W, H, fill))


def render_current_split(
    doc: Doc,
    photo_href: str,
    blur_href: str,
    *,
    panel_fill: str,
    panel_stroke: str,
    ink: str,
    muted: str,
    accent: str,
    background_overlay: str,
    background_opacity: float,
    photo_backdrop: str,
    photo_backdrop_stroke: str,
    photo_backdrop_opacity: float,
    caption_size: float,
    frameless: bool = False,
    rail: bool = False,
    cinematic: bool = False,
) -> None:
    base_canvas(doc, "#06080c")
    doc.add(clipped_image(doc, 0, 0, W, H, blur_href, preserve="xMidYMid slice", opacity=0.58 if cinematic else 0.44))
    doc.add(rect(0, 0, W, H, background_overlay, opacity=background_opacity))
    doc.add(rect(0, H - 220, W, 240, "#4a5317", opacity=0.16 if cinematic else 0.10))

    photo_x = 52
    photo_y = 62
    photo_w = 800 if not rail else 830
    photo_h = 700 if not rail else 680
    if not frameless:
        doc.add(rect(photo_x, photo_y, photo_w, photo_h, photo_backdrop, rx=34, stroke=photo_backdrop_stroke, opacity=photo_backdrop_opacity))
        doc.add(clipped_image(doc, photo_x + 22, photo_y + 24, photo_w - 44, photo_h - 82, photo_href, rx=24, opacity=1.0))
    else:
        doc.add(rect(photo_x + 10, photo_y + 8, photo_w - 20, photo_h - 16, "#000000", rx=30, opacity=0.10))
        doc.add(clipped_image(doc, photo_x, photo_y, photo_w, photo_h, photo_href, rx=22, opacity=1.0, stroke="#7f92a7", stroke_width=1.4))

    right_x = 888 if not rail else 918
    top_y = 64

    if rail:
        doc.add(rect(872, 46, 670, 84, panel_fill, rx=26, stroke=panel_stroke, opacity=0.95))
        render_label_value(doc, 904, 74, "FILE", DATA["filename"], muted, ink, value_size=18)
        render_label_value(doc, 1110, 74, "SOURCE", DATA["source"], muted, ink, value_size=18)
        render_label_value(doc, 1304, 74, "CAPTURED", DATA["captured"], muted, ink, value_size=16)
        top_y = 154
    else:
        render_label_value(doc, right_x, top_y, "FILE", DATA["filename"], muted, ink, value_size=18)
        render_label_value(doc, right_x, top_y + 76, "SOURCE", DATA["source"], muted, ink, value_size=18)
        render_label_value(doc, right_x, top_y + 152, "CAPTURED", DATA["captured"], muted, ink, value_size=16)
        top_y += 248

    doc.add(text(right_x, top_y, "RUN PROGRESS", 12, muted, family=FONT_UI, weight=800, letter_spacing=1.0))
    render_progress_grid(doc, right_x, top_y + 16, 112, 54, 12, panel_fill, ink, muted, panel_stroke)

    doc.add(text(right_x, top_y + 102, "RUN PACE", 12, muted, family=FONT_UI, weight=800, letter_spacing=1.0))
    render_pace_row(doc, right_x, top_y + 118, [104, 74, 72], 42, panel_fill, ink, muted, panel_stroke)

    doc.add(text(right_x, top_y + 196, "CAPTION", 12, muted, family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(
        text_block(
            right_x,
            top_y + 258,
            DATA["caption_lines"],
            caption_size,
            ink,
            family=FONT_SANS if not cinematic else FONT_SERIF,
            weight=800 if caption_size >= 42 else 700,
            line_height=1.03,
        )
    )

    keyword_label_y = top_y + 406 if caption_size < 48 else top_y + 426
    doc.add(text(right_x, keyword_label_y, "KEYWORDS", 12, muted, family=FONT_UI, weight=800, letter_spacing=1.0))
    render_keyword_pills(doc, right_x, keyword_label_y + 18, 540, panel_fill, ink, panel_stroke)
    close_button(doc, ink, "#ffffff", panel_stroke)


def concept_01_edge_tuned_current(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    render_current_split(
        doc,
        photo_href,
        blur_href,
        panel_fill="#34393e",
        panel_stroke="#586168",
        ink="#f3f6f8",
        muted="#aeb7bf",
        accent="#7b8e9d",
        background_overlay="#0a0d10",
        background_opacity=0.58,
        photo_backdrop="#646d73",
        photo_backdrop_stroke="#7b8389",
        photo_backdrop_opacity=0.48,
        caption_size=62,
    )
    return make_svg(doc)


def concept_02_soft_rail_current(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    render_current_split(
        doc,
        photo_href,
        blur_href,
        panel_fill="#f3f7fb",
        panel_stroke="#d5e0e8",
        ink="#eef5fb",
        muted="#bfccd5",
        accent="#93b7d2",
        background_overlay="#0e1318",
        background_opacity=0.56,
        photo_backdrop="#dfe7ed",
        photo_backdrop_stroke="#eef4f8",
        photo_backdrop_opacity=0.18,
        caption_size=54,
        rail=True,
    )
    return make_svg(doc)


def concept_03_caption_forward_current(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    render_current_split(
        doc,
        photo_href,
        blur_href,
        panel_fill="#2e3438",
        panel_stroke="#596169",
        ink="#f6f7f8",
        muted="#a3adb5",
        accent="#7f919c",
        background_overlay="#090b0d",
        background_opacity=0.62,
        photo_backdrop="#7b8184",
        photo_backdrop_stroke="#959ca1",
        photo_backdrop_opacity=0.32,
        caption_size=70,
    )
    return make_svg(doc)


def concept_04_frameless_media_current(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    render_current_split(
        doc,
        photo_href,
        blur_href,
        panel_fill="#272c31",
        panel_stroke="#4f5963",
        ink="#f4f7fb",
        muted="#aab5c0",
        accent="#7d8e9c",
        background_overlay="#0a0d12",
        background_opacity=0.54,
        photo_backdrop="#000000",
        photo_backdrop_stroke="#8092a3",
        photo_backdrop_opacity=0.0,
        caption_size=58,
        frameless=True,
    )
    return make_svg(doc)


def concept_05_quiet_cinematic_current(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    render_current_split(
        doc,
        photo_href,
        blur_href,
        panel_fill="#1f2622",
        panel_stroke="#556158",
        ink="#f6f5ee",
        muted="#b9c2b1",
        accent="#a8b48d",
        background_overlay="#09100a",
        background_opacity=0.64,
        photo_backdrop="#7f8a71",
        photo_backdrop_stroke="#98a58a",
        photo_backdrop_opacity=0.18,
        caption_size=58,
        cinematic=True,
    )
    return make_svg(doc)


def concept_06_bottom_dock_overlay(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#060709")
    doc.add(clipped_image(doc, 0, 0, W, H, blur_href, preserve="xMidYMid slice", opacity=0.88))
    doc.add(rect(0, 0, W, H, "#091017", opacity=0.40))
    doc.add(clipped_image(doc, 120, 74, 1360, 726, photo_href, rx=28, preserve="xMidYMid slice", stroke="#9ca8b6", stroke_width=1.2))
    doc.add(rect(72, 710, 1456, 224, "#0f151bcc", rx=30, stroke="#41505d"))
    doc.add(text(110, 760, DATA["filename"], 24, "#eef4f9", family=FONT_SANS, weight=800))
    doc.add(text(110, 792, DATA["source"] + "  •  " + DATA["captured"], 16, "#b6c2cd", family=FONT_UI, weight=600))
    doc.add(text_block(110, 860, DATA["caption_lines"], 48, "#ffffff", family=FONT_SANS, weight=800, line_height=1.02))
    render_keyword_pills(doc, 880, 762, 560, "#2c3642", "#edf3f8", "#485564")
    render_progress_grid(doc, 880, 842, 102, 50, 10, "#202932", "#edf3f8", "#a7b5c1", "#43505e")
    render_pace_row(doc, 110, 908, [140, 100, 96], 44, "#202932", "#edf3f8", "#a7b5c1", "#43505e")
    close_button(doc, "#eef4f9", "#10161dcc", "#586677")
    return make_svg(doc)


def concept_07_editorial_drawer(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#0c1015")
    doc.add(clipped_image(doc, 0, 0, W, H, blur_href, preserve="xMidYMid slice", opacity=0.34))
    doc.add(rect(0, 0, W, H, "#0d1117", opacity=0.42))
    doc.add(clipped_image(doc, 52, 52, 992, 896, photo_href, rx=26, preserve="xMidYMid slice", stroke="#8d98a4", stroke_width=1.2))
    doc.add(rect(1062, 38, 498, 924, "#f5f0e8dd", rx=34, stroke="#dfd3c5"))
    doc.add(text(1102, 108, DATA["filename"], 24, "#1c1712", family=FONT_UI, weight=800))
    render_label_value(doc, 1102, 154, "SOURCE", DATA["source"], "#907b68", "#2b231b", value_size=18, family=FONT_UI)
    render_label_value(doc, 1102, 220, "CAPTURED", DATA["captured"], "#907b68", "#2b231b", value_size=16, family=FONT_UI)
    doc.add(text(1102, 320, "CAPTION", 12, "#907b68", family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(text_block(1102, 382, DATA["caption_three_lines"], 42, "#19130d", family=FONT_SERIF, weight=700, line_height=1.06))
    doc.add(line(1102, 520, 1518, 520, "#d6c9ba", stroke_width=1.2))
    doc.add(text(1102, 558, "RUN PROGRESS", 12, "#907b68", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_progress_grid(doc, 1102, 576, 74, 64, 8, "#fffcf7", "#231b14", "#8a7665", "#ddd2c5")
    doc.add(text(1102, 676, "RUN PACE", 12, "#907b68", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_pace_row(doc, 1102, 694, [144, 84, 84], 46, "#fffcf7", "#231b14", "#8a7665", "#ddd2c5")
    doc.add(text(1102, 782, "KEYWORDS", 12, "#907b68", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_keyword_pills(doc, 1102, 802, 390, "#ece1d4", "#31271d", "#d7cabc", family=FONT_SERIF)
    close_button(doc, "#201912", "#f5f0e8", "#d9cdc0")
    return make_svg(doc)


def concept_08_top_hud_bottom_story(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#050608")
    doc.add(clipped_image(doc, 0, 0, W, H, photo_href, preserve="xMidYMid slice", opacity=1.0))
    doc.add(rect(0, 0, W, H, "#020406", opacity=0.18))
    doc.add(rect(28, 26, 1544, 88, "#071018cc", rx=26, stroke="#3a5567"))
    doc.add(text(66, 62, DATA["filename"], 22, "#eef6fc", family=FONT_UI, weight=800))
    doc.add(text(66, 92, DATA["source"] + "  •  " + DATA["captured"], 15, "#a4b8c7", family=FONT_UI, weight=600))
    render_progress_grid(doc, 820, 42, 116, 54, 10, "#11212d", "#eaf6ff", "#9fb8ca", "#3b5766")
    doc.add(rect(64, 746, 1472, 196, "#0b1116dd", rx=32, stroke="#334550"))
    doc.add(text(104, 790, "CAPTION", 12, "#8fa4b3", family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(text_block(104, 850, DATA["caption_lines"], 58, "#ffffff", family=FONT_BLACK, weight=900, line_height=1.00))
    render_pace_row(doc, 1000, 786, [144, 96, 90], 46, "#11212d", "#eaf6ff", "#9fb8ca", "#3b5766")
    render_keyword_pills(doc, 1000, 846, 430, "#1b2c39", "#eef6fc", "#415869")
    close_button(doc, "#eef6fc", "#081017cc", "#355163")
    return make_svg(doc)


def concept_09_floating_cards(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#091015")
    doc.add(clipped_image(doc, 0, 0, W, H, blur_href, preserve="xMidYMid slice", opacity=0.54))
    doc.add(rect(0, 0, W, H, "#0d1319", opacity=0.48))
    doc.add(clipped_image(doc, 320, 108, 960, 626, photo_href, rx=34, preserve="xMidYMid slice", stroke="#93a5b3", stroke_width=1.4))
    doc.add(rect(108, 96, 280, 134, "#111922dd", rx=26, stroke="#40515f"))
    doc.add(text(134, 136, DATA["filename"], 20, "#ecf6ff", family=FONT_UI, weight=800))
    doc.add(text(134, 164, DATA["source"], 16, "#aec0ce", family=FONT_UI, weight=700))
    doc.add(text(134, 192, DATA["captured"], 14, "#aec0ce", family=FONT_UI, weight=600))
    doc.add(rect(1196, 126, 292, 190, "#111922dd", rx=26, stroke="#40515f"))
    doc.add(text(1224, 162, "RUN PROGRESS", 12, "#9fb3c1", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_progress_grid(doc, 1224, 182, 74, 54, 8, "#1c2834", "#edf7ff", "#a1b5c2", "#4a5a67")
    doc.add(rect(132, 746, 660, 178, "#101821dd", rx=30, stroke="#40515f"))
    doc.add(text(164, 786, "CAPTION", 12, "#9fb3c1", family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(text_block(164, 846, DATA["caption_lines"], 46, "#fdfefe", family=FONT_SANS, weight=800, line_height=1.02))
    doc.add(rect(890, 748, 566, 176, "#101821dd", rx=30, stroke="#40515f"))
    doc.add(text(920, 786, "KEYWORDS", 12, "#9fb3c1", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_keyword_pills(doc, 920, 806, 490, "#1c2834", "#edf7ff", "#4a5a67")
    close_button(doc, "#edf7ff", "#0c151dcc", "#445664")
    return make_svg(doc)


def concept_10_split_magazine(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#111014")
    bg_grad = linear_gradient(doc, [("#17131a", 0.0), ("#0d1115", 1.0)], "0%", "0%", "100%", "100%")
    doc.add(rect(0, 0, W, H, bg_grad))
    doc.add(rect(0, 0, 530, H, "#f3efe7"))
    doc.add(rect(530, 0, W - 530, H, "#0e1318"))
    doc.add(clipped_image(doc, 596, 68, 934, 864, photo_href, rx=26, preserve="xMidYMid slice", stroke="#8594a1", stroke_width=1.2))
    doc.add(text(78, 114, DATA["filename"], 22, "#292118", family=FONT_UI, weight=800))
    doc.add(text(78, 144, DATA["source"] + "  •  " + DATA["captured"], 15, "#6d5e50", family=FONT_UI, weight=600))
    doc.add(text(78, 226, "CAPTION", 12, "#9b7d60", family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(text_block(78, 302, DATA["caption_three_lines"], 52, "#1b150f", family=FONT_SERIF, weight=700, line_height=1.08))
    doc.add(line(78, 472, 450, 472, "#d7cbbf", stroke_width=1.4))
    doc.add(text(78, 518, "RUN PROGRESS", 12, "#9b7d60", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_progress_grid(doc, 78, 542, 88, 58, 8, "#fffaf3", "#241c13", "#8a755f", "#dbd0c3")
    doc.add(text(78, 644, "RUN PACE", 12, "#9b7d60", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_pace_row(doc, 78, 664, [152, 92, 90], 46, "#fffaf3", "#241c13", "#8a755f", "#dbd0c3")
    doc.add(text(78, 754, "KEYWORDS", 12, "#9b7d60", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_keyword_pills(doc, 78, 776, 380, "#f0e4d6", "#2d2318", "#d4c5b6", family=FONT_SERIF)
    close_button(doc, "#ecf4fa", "#10161d", "#455362")
    return make_svg(doc)


def concept_11_poster_type(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#060709")
    doc.add(clipped_image(doc, 0, 0, W, H, photo_href, preserve="xMidYMid slice", opacity=1.0))
    doc.add(rect(0, 0, W, H, "#06080b", opacity=0.26))
    doc.add(rect(0, 610, W, 390, "#07090bdd", opacity=0.72))
    doc.add(text_block(80, 692, DATA["caption_three_lines"], 82, "#fbfbfa", family=FONT_BLACK, weight=900, line_height=0.98))
    doc.add(text(82, 928, DATA["filename"], 20, "#f3f6f8", family=FONT_UI, weight=800))
    doc.add(text(280, 928, DATA["source"] + "  •  " + DATA["captured"], 16, "#cad2d8", family=FONT_UI, weight=600))
    render_progress_grid(doc, 900, 842, 116, 56, 10, "#0f151bcc", "#f2f6fa", "#c0cbd3", "#45515d")
    render_keyword_pills(doc, 900, 916, 580, "#171d24dd", "#f2f6fa", "#48535f")
    close_button(doc, "#f3f6f8", "#0b1015cc", "#44505c")
    return make_svg(doc)


def concept_12_museum_labels(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#e7e1d7")
    soft_grad = linear_gradient(doc, [("#f4efe8", 0.0), ("#ddd4c6", 1.0)], "0%", "0%", "100%", "100%")
    doc.add(rect(0, 0, W, H, soft_grad))
    doc.add(rect(360, 112, 880, 708, "#f8f5ef", rx=34, stroke="#d6cbbb"))
    doc.add(clipped_image(doc, 430, 178, 740, 560, photo_href, rx=18, preserve="xMidYMid slice", stroke="#cbbda9", stroke_width=1.0))
    doc.add(rect(136, 174, 214, 126, "#fffdf9", rx=22, stroke="#d6cbbb"))
    render_label_value(doc, 160, 208, "WORK", DATA["filename"], "#a0764a", "#231a12", value_size=18, family=FONT_SERIF)
    render_label_value(doc, 160, 254, "SOURCE", DATA["source"], "#a0764a", "#231a12", value_size=16, family=FONT_SERIF)
    doc.add(rect(1260, 198, 220, 132, "#fffdf9", rx=22, stroke="#d6cbbb"))
    render_label_value(doc, 1284, 232, "CAPTURED", DATA["captured"], "#a0764a", "#231a12", value_size=16, family=FONT_SERIF)
    doc.add(rect(146, 604, 234, 198, "#fffdf9", rx=22, stroke="#d6cbbb"))
    doc.add(text(170, 642, "RUN PROGRESS", 12, "#a0764a", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_progress_grid(doc, 170, 664, 92, 54, 8, "#f7f1e8", "#231a12", "#8f7558", "#d6cbbb")
    doc.add(rect(1260, 592, 226, 240, "#fffdf9", rx=22, stroke="#d6cbbb"))
    doc.add(text(1284, 628, "CAPTION", 12, "#a0764a", family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(text_block(1284, 684, DATA["caption_three_lines"], 28, "#231a12", family=FONT_SERIF, weight=700, line_height=1.10))
    doc.add(text(1284, 790, "KEYWORDS", 12, "#a0764a", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_keyword_pills(doc, 1284, 808, 180, "#efe3d2", "#2b1f14", "#d3c4b1", family=FONT_SERIF)
    close_button(doc, "#241a12", "#fffdf9", "#d6cbbb")
    return make_svg(doc)


def concept_13_broadcast_mode(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#071014")
    doc.add(clipped_image(doc, 0, 0, W, H, photo_href, preserve="xMidYMid slice", opacity=0.92))
    doc.add(rect(0, 0, W, H, "#031217", opacity=0.30))
    doc.add(rect(36, 30, 1528, 70, "#061722dd", rx=20, stroke="#1f7ea7"))
    doc.add(text(60, 74, DATA["filename"], 24, "#f4fbff", family=FONT_BLACK, weight=900))
    doc.add(text(430, 74, DATA["source"] + "  •  " + DATA["captured"], 16, "#a6d7f1", family=FONT_UI, weight=700))
    render_progress_grid(doc, 952, 42, 110, 46, 8, "#0c2633", "#effaff", "#93c9e5", "#2784aa")
    doc.add(rect(44, 762, 1512, 164, "#07151dcc", rx=18, stroke="#2582aa"))
    doc.add(text(66, 802, "CAPTION", 12, "#9bd4ef", family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(text_block(66, 860, DATA["caption_lines"], 52, "#ffffff", family=FONT_BLACK, weight=900, line_height=1.0))
    doc.add(rect(1120, 780, 404, 56, "#0c2633", rx=14, stroke="#2784aa"))
    doc.add(text(1142, 816, "RATE  0.58 items/min   ELAPSED  01:43   ETA  18:53", 16, "#f1fbff", family=FONT_MONO, weight=700))
    render_keyword_pills(doc, 1120, 850, 390, "#0c2633", "#effaff", "#2784aa")
    close_button(doc, "#effaff", "#071722dd", "#2784aa")
    return make_svg(doc)


def concept_14_darkroom_strip(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#120607")
    doc.add(rect(0, 0, W, H, "#15090a"))
    doc.add(rect(0, 0, W, H, "#2f1012", opacity=0.24))
    doc.add(rect(64, 68, 826, 864, "#1a1412", rx=28, stroke="#5d4440"))
    doc.add(clipped_image(doc, 108, 116, 738, 640, photo_href, rx=14, preserve="xMidYMid slice", stroke="#7c6059", stroke_width=1.0))
    for index in range(5):
        x = 110 + index * 144
        doc.add(rect(x, 794, 116, 92, "#251a18", rx=14, stroke="#5d4440"))
        doc.add(clipped_image(doc, x + 8, 802, 100, 76, photo_href, rx=10, preserve="xMidYMid slice", opacity=0.70))
    doc.add(rect(936, 82, 596, 830, "#110d0ccc", rx=28, stroke="#5d4440"))
    doc.add(text(980, 136, DATA["filename"], 24, "#f8f1eb", family=FONT_UI, weight=800))
    render_label_value(doc, 980, 186, "SOURCE", DATA["source"], "#b08b82", "#f8f1eb", value_size=18)
    render_label_value(doc, 980, 248, "CAPTURED", DATA["captured"], "#b08b82", "#f8f1eb", value_size=16)
    doc.add(text(980, 344, "RUN PROGRESS", 12, "#b08b82", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_progress_grid(doc, 980, 362, 92, 58, 8, "#211816", "#fff7ef", "#b79a92", "#5d4440")
    doc.add(text(980, 458, "RUN PACE", 12, "#b08b82", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_pace_row(doc, 980, 476, [150, 92, 92], 46, "#211816", "#fff7ef", "#b79a92", "#5d4440")
    doc.add(text(980, 562, "CAPTION", 12, "#b08b82", family=FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(text_block(980, 622, DATA["caption_three_lines"], 36, "#fff7ef", family=FONT_SERIF, weight=700, line_height=1.08))
    doc.add(text(980, 766, "KEYWORDS", 12, "#b08b82", family=FONT_UI, weight=800, letter_spacing=1.0))
    render_keyword_pills(doc, 980, 786, 490, "#241a18", "#fff7ef", "#5d4440", family=FONT_MONO)
    close_button(doc, "#fff7ef", "#211816", "#5d4440")
    return make_svg(doc)


def concept_15_holographic_hud(photo_href: str, blur_href: str) -> str:
    doc = Doc()
    base_canvas(doc, "#03070a")
    hud_grad = radial_gradient(doc, [("#0d2a34", 0.0), ("#041117", 0.6), ("#020609", 1.0)], cx="48%", cy="40%", r="82%")
    doc.add(rect(0, 0, W, H, hud_grad))
    doc.add(clipped_image(doc, 146, 112, 820, 620, photo_href, rx=30, preserve="xMidYMid slice", stroke="#34d2df", stroke_width=2.0))
    doc.add(rect(136, 102, 840, 640, "none", rx=34, stroke="#60f4ff", stroke_width=1.0, opacity=0.65))
    doc.add(rect(1024, 76, 492, 142, "#06131acc", rx=26, stroke="#2ad0df"))
    doc.add(text(1054, 118, DATA["filename"], 24, "#e8fbff", family=FONT_MONO, weight=800))
    doc.add(text(1054, 150, DATA["source"], 18, "#7ce7f0", family=FONT_MONO, weight=700))
    doc.add(text(1054, 182, DATA["captured"], 16, "#7ce7f0", family=FONT_MONO, weight=700))
    doc.add(rect(1036, 250, 472, 170, "#06131acc", rx=24, stroke="#2ad0df"))
    doc.add(text(1064, 288, "RUN PROGRESS", 12, "#84eff6", family=FONT_MONO, weight=800, letter_spacing=1.2))
    render_progress_grid(doc, 1064, 306, 84, 54, 8, "#0d2530", "#edfeff", "#8ce7ef", "#2ad0df")
    doc.add(rect(1036, 452, 472, 190, "#06131acc", rx=24, stroke="#2ad0df"))
    doc.add(text(1064, 490, "CAPTION", 12, "#84eff6", family=FONT_MONO, weight=800, letter_spacing=1.2))
    doc.add(text_block(1064, 552, DATA["caption_three_lines"], 34, "#f7ffff", family=FONT_SANS, weight=800, line_height=1.06))
    doc.add(rect(150, 782, 1358, 136, "#06131acc", rx=28, stroke="#2ad0df"))
    doc.add(text(186, 822, "RUN PACE", 12, "#84eff6", family=FONT_MONO, weight=800, letter_spacing=1.2))
    render_pace_row(doc, 186, 840, [172, 106, 100], 46, "#0d2530", "#edfeff", "#8ce7ef", "#2ad0df")
    doc.add(text(600, 822, "KEYWORDS", 12, "#84eff6", family=FONT_MONO, weight=800, letter_spacing=1.2))
    render_keyword_pills(doc, 600, 840, 846, "#0d2530", "#edfeff", "#2ad0df", family=FONT_MONO)
    close_button(doc, "#e8fbff", "#07141bcc", "#2ad0df")
    return make_svg(doc)


CONCEPTS = [
    ("01_edge_tuned_current", concept_01_edge_tuned_current),
    ("02_soft_rail_current", concept_02_soft_rail_current),
    ("03_caption_forward_current", concept_03_caption_forward_current),
    ("04_frameless_media_current", concept_04_frameless_media_current),
    ("05_quiet_cinematic_current", concept_05_quiet_cinematic_current),
    ("06_bottom_dock_overlay", concept_06_bottom_dock_overlay),
    ("07_editorial_drawer", concept_07_editorial_drawer),
    ("08_top_hud_bottom_story", concept_08_top_hud_bottom_story),
    ("09_floating_cards", concept_09_floating_cards),
    ("10_split_magazine", concept_10_split_magazine),
    ("11_poster_type", concept_11_poster_type),
    ("12_museum_labels", concept_12_museum_labels),
    ("13_broadcast_mode", concept_13_broadcast_mode),
    ("14_darkroom_strip", concept_14_darkroom_strip),
    ("15_holographic_hud", concept_15_holographic_hud),
]


def make_svg(doc: Doc) -> str:
    defs = f"<defs>{''.join(doc.defs)}</defs>" if doc.defs else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{W}" height="{H}" viewBox="0 0 {W} {H}" fill="none">{defs}{"".join(doc.parts)}</svg>'
    )


def render_png(svg_path: Path, png_path: Path) -> None:
    html_wrapper = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    html, body {{
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #05070a;
    }}
    iframe {{
      display: block;
      width: 100vw;
      height: 100vh;
      border: 0;
    }}
  </style>
</head>
<body>
  <iframe src="{svg_path.resolve().as_uri()}" aria-hidden="true"></iframe>
</body>
</html>
"""
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as handle:
        handle.write(html_wrapper)
        html_path = Path(handle.name)
    try:
        subprocess.run(
            [
                str(CHROME_BIN),
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                f"--window-size={W},{H}",
                "--force-device-scale-factor=1",
                f"--screenshot={png_path}",
                html_path.resolve().as_uri(),
            ],
            check=True,
        )
    finally:
        html_path.unlink(missing_ok=True)


def main() -> None:
    photo_href, blur_href = ensure_sample_images()
    for slug, renderer in CONCEPTS:
        svg_path = OUT_DIR / f"{slug}.svg"
        png_path = OUT_DIR / f"{slug}.png"
        svg_path.write_text(renderer(photo_href, blur_href), encoding="utf-8")
        render_png(svg_path, png_path)


if __name__ == "__main__":
    main()
