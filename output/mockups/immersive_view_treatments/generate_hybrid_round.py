from __future__ import annotations

from pathlib import Path

import generate_immersive_mockups as base


OUT_DIR = base.OUT_DIR


def top_hud(doc: base.Doc, accent: str, panel_fill: str, stroke: str, ink: str, muted: str) -> None:
    doc.add(base.rect(26, 24, base.W - 52, 82, panel_fill, rx=24, stroke=stroke, opacity=0.92))
    doc.add(base.text(56, 60, base.DATA["filename"], 22, ink, family=base.FONT_UI, weight=800))
    doc.add(
        base.text(
            56,
            90,
            base.DATA["source"] + "  •  " + base.DATA["captured"],
            15,
            muted,
            family=base.FONT_UI,
            weight=650,
        )
    )
    base.render_progress_grid(doc, 800, 38, 114, 52, 10, "#10202c", ink, muted, stroke)
    doc.add(base.rect(786, 34, 2, 62, accent, opacity=0.65))


def bottom_dock(
    doc: base.Doc,
    *,
    y: float,
    h: float,
    panel_fill: str,
    stroke: str,
    ink: str,
    muted: str,
    caption_size: float,
    caption_family: str,
    bold: int = 850,
) -> None:
    doc.add(base.rect(52, y, base.W - 104, h, panel_fill, rx=30, stroke=stroke, opacity=0.94))
    doc.add(base.text(88, y + 40, "CAPTION", 12, muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(
        base.text_block(
            88,
            y + 96,
            base.DATA["caption_lines"],
            caption_size,
            ink,
            family=caption_family,
            weight=bold,
            line_height=1.0,
        )
    )
    base.render_pace_row(doc, 968, y + 46, [142, 96, 92], 46, "#132230", ink, muted, stroke)
    doc.add(base.text(968, y + 116, "KEYWORDS", 12, muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
    base.render_keyword_pills(doc, 968, y + 134, 500, "#132230", ink, stroke)


def compact_overlay_card(
    doc: base.Doc,
    *,
    x: float,
    y: float,
    w: float,
    h: float,
    title: str,
    stroke: str,
    panel_fill: str,
    ink: str,
    muted: str,
) -> None:
    doc.add(base.rect(x, y, w, h, panel_fill, rx=24, stroke=stroke, opacity=0.94))
    doc.add(base.text(x + 26, y + 36, title, 12, muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))


def concept_16_dock_hud_fusion(photo_href: str, blur_href: str) -> str:
    doc = base.Doc()
    base.base_canvas(doc, "#04070a")
    doc.add(base.clipped_image(doc, 0, 0, base.W, base.H, photo_href, preserve="xMidYMid slice", opacity=1.0))
    doc.add(base.rect(0, 0, base.W, base.H, "#050a0f", opacity=0.22))
    doc.add(base.rect(0, base.H - 260, base.W, 260, "#0b0f14", opacity=0.22))
    top_hud(doc, "#2e89b4", "#09121acc", "#3e6276", "#eef7ff", "#a8bdca")
    bottom_dock(
        doc,
        y=706,
        h=244,
        panel_fill="#0a1017dd",
        stroke="#3f6073",
        ink="#f6fbff",
        muted="#a8bdca",
        caption_size=54,
        caption_family=base.FONT_BLACK,
        bold=900,
    )
    base.close_button(doc, "#eef7ff", "#0b131ccc", "#446577")
    return base.make_svg(doc)


def concept_17_poster_dock_broadcast(photo_href: str, blur_href: str) -> str:
    doc = base.Doc()
    base.base_canvas(doc, "#050608")
    doc.add(base.clipped_image(doc, 0, 0, base.W, base.H, photo_href, preserve="xMidYMid slice", opacity=1.0))
    doc.add(base.rect(0, 0, base.W, base.H, "#04070b", opacity=0.28))
    doc.add(base.rect(40, 40, 408, 60, "#06141dcc", rx=18, stroke="#257ea4"))
    doc.add(base.text(64, 78, base.DATA["filename"], 24, "#f4fbff", family=base.FONT_UI, weight=800))
    doc.add(base.rect(1010, 40, 510, 60, "#06141dcc", rx=18, stroke="#257ea4"))
    base.render_progress_grid(doc, 1030, 46, 88, 48, 8, "#0d2431", "#eefaff", "#99cbe5", "#257ea4")
    doc.add(base.rect(0, 594, base.W, 406, "#05080ccc", opacity=0.72))
    doc.add(base.text(72, 642, "CAPTION", 12, "#9ad0e8", family=base.FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(base.text_block(72, 730, base.DATA["caption_three_lines"], 86, "#ffffff", family=base.FONT_BLACK, weight=900, line_height=0.95))
    doc.add(base.rect(1086, 634, 430, 148, "#081821dd", rx=24, stroke="#257ea4"))
    doc.add(base.text(1114, 670, "SOURCE", 12, "#9ad0e8", family=base.FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(base.text(1114, 700, base.DATA["source"], 20, "#f4fbff", family=base.FONT_UI, weight=700))
    doc.add(base.text(1114, 736, base.DATA["captured"], 17, "#c3e5f7", family=base.FONT_UI, weight=600))
    doc.add(base.rect(1086, 800, 430, 118, "#081821dd", rx=24, stroke="#257ea4"))
    doc.add(base.text(1114, 836, "RUN PACE", 12, "#9ad0e8", family=base.FONT_UI, weight=800, letter_spacing=1.0))
    base.render_pace_row(doc, 1114, 854, [140, 92, 88], 42, "#0d2431", "#eefaff", "#99cbe5", "#257ea4")
    base.render_keyword_pills(doc, 72, 930, 940, "#0d2431", "#eefaff", "#257ea4")
    base.close_button(doc, "#eefaff", "#08161fcc", "#257ea4")
    return base.make_svg(doc)


def concept_18_story_hud_live(photo_href: str, blur_href: str) -> str:
    doc = base.Doc()
    base.base_canvas(doc, "#04070b")
    doc.add(base.clipped_image(doc, 0, 0, base.W, base.H, photo_href, preserve="xMidYMid slice", opacity=1.0))
    doc.add(base.rect(0, 0, base.W, base.H, "#05090e", opacity=0.20))
    top_hud(doc, "#2789b4", "#08131bcc", "#2f6d88", "#eef8ff", "#a8c6d8")
    doc.add(base.rect(44, 782, 1512, 170, "#08131bdd", rx=30, stroke="#2f6d88"))
    doc.add(base.text(82, 820, "CAPTION", 12, "#a8c6d8", family=base.FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(base.text_block(82, 886, base.DATA["caption_lines"], 64, "#ffffff", family=base.FONT_BLACK, weight=900, line_height=0.98))
    doc.add(base.rect(980, 806, 526, 58, "#0c2130", rx=18, stroke="#2f6d88"))
    doc.add(base.text(1006, 844, "LIVE RUN  •  RATE 0.58/MIN  •  ETA 18:53", 17, "#eef8ff", family=base.FONT_MONO, weight=700))
    base.render_keyword_pills(doc, 980, 882, 500, "#0c2130", "#eef8ff", "#2f6d88")
    base.close_button(doc, "#eef8ff", "#09151dcc", "#2f6d88")
    return base.make_svg(doc)


def concept_19_scorebug_poster(photo_href: str, blur_href: str) -> str:
    doc = base.Doc()
    base.base_canvas(doc, "#050608")
    doc.add(base.clipped_image(doc, 0, 0, base.W, base.H, blur_href, preserve="xMidYMid slice", opacity=0.92))
    doc.add(base.clipped_image(doc, 88, 92, 1424, 736, photo_href, rx=30, preserve="xMidYMid slice", stroke="#7c96a8", stroke_width=1.2))
    doc.add(base.rect(88, 92, 1424, 736, "#020407", rx=30, opacity=0.16))
    doc.add(base.rect(118, 120, 520, 64, "#07131bcc", rx=18, stroke="#257ea4"))
    doc.add(base.text(148, 160, base.DATA["filename"] + "  •  " + base.DATA["source"], 22, "#f2faff", family=base.FONT_UI, weight=800))
    doc.add(base.rect(1058, 120, 422, 64, "#07131bcc", rx=18, stroke="#257ea4"))
    base.render_pace_row(doc, 1080, 132, [132, 90, 86], 40, "#0c2230", "#eefaff", "#9ecee5", "#257ea4")
    doc.add(base.rect(88, 680, 1424, 148, "#061019dd", rx=0))
    doc.add(base.text(128, 716, "CAPTION", 12, "#9ecee5", family=base.FONT_UI, weight=800, letter_spacing=1.0))
    doc.add(base.text_block(128, 786, base.DATA["caption_lines"], 72, "#ffffff", family=base.FONT_BLACK, weight=900, line_height=0.96))
    doc.add(base.rect(88, 852, 1424, 94, "#07131bcc", rx=24, stroke="#257ea4"))
    base.render_progress_grid(doc, 118, 874, 108, 48, 10, "#0c2230", "#eefaff", "#9ecee5", "#257ea4")
    base.render_keyword_pills(doc, 736, 878, 706, "#0c2230", "#eefaff", "#257ea4")
    base.close_button(doc, "#eefaff", "#08161fcc", "#257ea4")
    return base.make_svg(doc)


def concept_20_console_cinema(photo_href: str, blur_href: str) -> str:
    doc = base.Doc()
    base.base_canvas(doc, "#04070a")
    doc.add(base.clipped_image(doc, 0, 0, base.W, base.H, photo_href, preserve="xMidYMid slice", opacity=1.0))
    doc.add(base.rect(0, 0, base.W, base.H, "#021018", opacity=0.18))
    doc.add(base.rect(38, 34, base.W - 76, 70, "#061620cc", rx=22, stroke="#2782aa"))
    doc.add(base.text(62, 77, base.DATA["filename"], 23, "#eef9ff", family=base.FONT_MONO, weight=800))
    doc.add(base.text(310, 77, base.DATA["captured"], 16, "#9dd2ea", family=base.FONT_MONO, weight=700))
    base.render_progress_grid(doc, 900, 45, 104, 48, 8, "#0b2533", "#eef9ff", "#9dd2ea", "#2782aa")
    doc.add(base.rect(58, 642, 780, 242, "#07131bdd", rx=30, stroke="#2782aa"))
    doc.add(base.text(92, 682, "CAPTION", 12, "#9dd2ea", family=base.FONT_MONO, weight=800, letter_spacing=1.1))
    doc.add(base.text_block(92, 754, base.DATA["caption_three_lines"], 66, "#ffffff", family=base.FONT_BLACK, weight=900, line_height=0.95))
    doc.add(base.rect(876, 642, 666, 242, "#07131bdd", rx=30, stroke="#2782aa"))
    doc.add(base.text(910, 682, "PACE + KEYWORDS", 12, "#9dd2ea", family=base.FONT_MONO, weight=800, letter_spacing=1.1))
    base.render_pace_row(doc, 910, 708, [150, 98, 92], 44, "#0b2533", "#eef9ff", "#9dd2ea", "#2782aa")
    base.render_keyword_pills(doc, 910, 774, 580, "#0b2533", "#eef9ff", "#2782aa", family=base.FONT_MONO)
    base.close_button(doc, "#eef9ff", "#071722dd", "#2782aa")
    return base.make_svg(doc)


HYBRIDS = [
    ("16_dock_hud_fusion", concept_16_dock_hud_fusion),
    ("17_poster_dock_broadcast", concept_17_poster_dock_broadcast),
    ("18_story_hud_live", concept_18_story_hud_live),
    ("19_scorebug_poster", concept_19_scorebug_poster),
    ("20_console_cinema", concept_20_console_cinema),
]


def main() -> None:
    photo_href, blur_href = base.ensure_sample_images()
    for slug, renderer in HYBRIDS:
        svg_path = OUT_DIR / f"{slug}.svg"
        png_path = OUT_DIR / f"{slug}.png"
        svg_path.write_text(renderer(photo_href, blur_href), encoding="utf-8")
        base.render_png(svg_path, png_path)


if __name__ == "__main__":
    main()
