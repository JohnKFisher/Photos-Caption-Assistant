from __future__ import annotations

from dataclasses import dataclass

import generate_immersive_mockups as base


OUT_DIR = base.OUT_DIR


@dataclass(frozen=True)
class Palette:
    accent: str
    ink: str
    muted: str
    overlay: str
    overlay_opacity: float
    bottom_shadow: str
    bottom_shadow_opacity: float
    hud_top: str
    hud_bottom: str
    hud_stroke: str
    hud_opacity: float
    dock_top: str
    dock_bottom: str
    dock_stroke: str
    dock_opacity: float
    panel_top: str
    panel_bottom: str
    panel_stroke: str
    chip_fill: str
    chip_stroke: str


@dataclass(frozen=True)
class Layout:
    dock_x: float
    dock_y: float
    dock_w: float
    dock_h: float
    caption_x: float
    caption_y: float
    info_x: float
    info_y: float
    info_w: float
    divider_x: float | None
    style: str
    pace_widths: tuple[float, float, float]


DEFAULT_LAYOUT = Layout(
    dock_x=38,
    dock_y=792,
    dock_w=1524,
    dock_h=194,
    caption_x=76,
    caption_y=824,
    info_x=970,
    info_y=820,
    info_w=510,
    divider_x=944,
    style="balanced",
    pace_widths=(128, 88, 84),
)


LEFT_BAND_LAYOUT = Layout(
    dock_x=36,
    dock_y=792,
    dock_w=1528,
    dock_h=194,
    caption_x=72,
    caption_y=822,
    info_x=1004,
    info_y=818,
    info_w=474,
    divider_x=968,
    style="left_band",
    pace_widths=(124, 86, 82),
)


SPLIT_BALANCE_LAYOUT = Layout(
    dock_x=40,
    dock_y=788,
    dock_w=1520,
    dock_h=202,
    caption_x=74,
    caption_y=820,
    info_x=854,
    info_y=808,
    info_w=628,
    divider_x=810,
    style="split_balance",
    pace_widths=(136, 92, 88),
)


SMOKE_LAYOUT = Layout(
    dock_x=40,
    dock_y=794,
    dock_w=1520,
    dock_h=190,
    caption_x=74,
    caption_y=824,
    info_x=978,
    info_y=818,
    info_w=500,
    divider_x=950,
    style="smoke",
    pace_widths=(126, 86, 82),
)


CRISP_LAYOUT = Layout(
    dock_x=38,
    dock_y=790,
    dock_w=1524,
    dock_h=198,
    caption_x=76,
    caption_y=822,
    info_x=960,
    info_y=816,
    info_w=520,
    divider_x=936,
    style="crisp",
    pace_widths=(130, 90, 86),
)


BALANCED_LAYOUT = Layout(
    dock_x=38,
    dock_y=790,
    dock_w=1524,
    dock_h=198,
    caption_x=76,
    caption_y=820,
    info_x=944,
    info_y=816,
    info_w=546,
    divider_x=920,
    style="balanced",
    pace_widths=(132, 90, 86),
)


def gradient(doc: base.Doc, top: str, bottom: str) -> str:
    return base.linear_gradient(doc, [(top, 0.0), (bottom, 1.0)], "0%", "0%", "0%", "100%")


def draw_background(doc: base.Doc, photo_href: str, palette: Palette) -> None:
    base.base_canvas(doc, "#05070a")
    doc.add(base.clipped_image(doc, 0, 0, base.W, base.H, photo_href, preserve="xMidYMid slice", opacity=1.0))
    overlay_fill = gradient(doc, palette.overlay, palette.overlay)
    doc.add(base.rect(0, 0, base.W, base.H, overlay_fill, opacity=palette.overlay_opacity))
    bottom_fill = gradient(doc, palette.bottom_shadow, "#03060a")
    doc.add(base.rect(0, base.H - 350, base.W, 350, bottom_fill, opacity=palette.bottom_shadow_opacity))


def top_hud(doc: base.Doc, palette: Palette, progress_card_w: float = 92) -> None:
    fill = gradient(doc, palette.hud_top, palette.hud_bottom)
    doc.add(base.rect(26, 24, base.W - 52, 82, fill, rx=24, stroke=palette.hud_stroke, opacity=palette.hud_opacity))
    doc.add(base.text(56, 58, base.DATA["filename"], 22, palette.ink, family=base.FONT_UI, weight=800))
    doc.add(
        base.text(
            56,
            88,
            base.DATA["source"] + "  •  " + base.DATA["captured"],
            15,
            palette.muted,
            family=base.FONT_UI,
            weight=650,
        )
    )
    progress_x = 1010
    for index, (label, value) in enumerate(base.DATA["progress"]):
        x = progress_x + index * (progress_card_w + 8)
        doc.add(
            base.compact_metric(
                x,
                36,
                progress_card_w,
                50,
                label,
                value,
                palette.panel_top,
                palette.ink,
                palette.muted,
                palette.panel_stroke,
            )
        )


def right_cluster(
    doc: base.Doc,
    layout: Layout,
    palette: Palette,
    *,
    chip_family: str = base.FONT_UI,
    mini_cards: bool = True,
) -> None:
    if layout.style == "split_balance":
        fill = gradient(doc, palette.panel_top, palette.panel_bottom)
        doc.add(base.rect(layout.info_x, layout.info_y, layout.info_w, 174, fill, rx=24, stroke=palette.panel_stroke, opacity=0.92))
        doc.add(base.text(layout.info_x + 26, layout.info_y + 28, "RUN PACE", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
        base.render_pace_row(
            doc,
            layout.info_x + 26,
            layout.info_y + 36,
            list(layout.pace_widths),
            40,
            palette.chip_fill,
            palette.ink,
            palette.muted,
            palette.chip_stroke,
        )
        doc.add(base.line(layout.info_x + 24, layout.info_y + 78, layout.info_x + layout.info_w - 24, layout.info_y + 78, palette.panel_stroke, stroke_width=1.0, opacity=0.35))
        doc.add(base.text(layout.info_x + 26, layout.info_y + 104, "KEYWORDS", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
        base.render_keyword_pills(doc, layout.info_x + 26, layout.info_y + 118, layout.info_w - 52, palette.chip_fill, palette.ink, palette.chip_stroke, family=chip_family)
        return

    if mini_cards:
        doc.add(base.text(layout.info_x, layout.info_y + 18, "RUN PACE", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
        base.render_pace_row(
            doc,
            layout.info_x,
            layout.info_y + 26,
            list(layout.pace_widths),
            38,
            palette.chip_fill,
            palette.ink,
            palette.muted,
            palette.chip_stroke,
        )
        doc.add(base.text(layout.info_x, layout.info_y + 84, "KEYWORDS", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
        base.render_keyword_pills(doc, layout.info_x, layout.info_y + 98, layout.info_w, palette.chip_fill, palette.ink, palette.chip_stroke, family=chip_family)
    else:
        doc.add(base.text(layout.info_x, layout.info_y + 24, "RUN PACE", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
        base.render_pace_row(
            doc,
            layout.info_x,
            layout.info_y + 34,
            list(layout.pace_widths),
            40,
            palette.chip_fill,
            palette.ink,
            palette.muted,
            palette.chip_stroke,
        )
        doc.add(base.text(layout.info_x, layout.info_y + 92, "KEYWORDS", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
        base.render_keyword_pills(doc, layout.info_x, layout.info_y + 106, layout.info_w, palette.chip_fill, palette.ink, palette.chip_stroke, family=chip_family)


def bold_caption(doc: base.Doc, layout: Layout, palette: Palette, variant: str) -> None:
    doc.add(base.text(layout.caption_x, layout.caption_y, "CAPTION", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
    if variant == "split_balance":
        lines = base.DATA["caption_three_lines"]
        size = 42
        line_height = 0.96
    elif variant == "balanced":
        lines = base.DATA["caption_lines"]
        size = 60
        line_height = 0.98
    else:
        lines = base.DATA["caption_lines"]
        size = 56
        line_height = 0.98
    doc.add(
        base.text_block(
            layout.caption_x,
            layout.caption_y + 54,
            lines,
            size,
            palette.ink,
            family=base.FONT_BLACK,
            weight=900,
            line_height=line_height,
        )
    )


def editorial_caption(doc: base.Doc, layout: Layout, palette: Palette, variant: str) -> None:
    doc.add(base.text(layout.caption_x, layout.caption_y, "CAPTION", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
    if variant == "split_balance":
        doc.add(base.text(layout.caption_x, layout.caption_y + 50, "group of soccer players", 48, palette.ink, family=base.FONT_SERIF, weight=700))
        doc.add(base.text(layout.caption_x, layout.caption_y + 102, "listening to coach", 42, palette.ink, family=base.FONT_UI, weight=760))
        doc.add(base.text(layout.caption_x, layout.caption_y + 148, "on field", 42, palette.ink, family=base.FONT_SERIF, weight=700))
    elif variant == "balanced":
        doc.add(base.text(layout.caption_x, layout.caption_y + 54, "group of soccer players", 54, palette.ink, family=base.FONT_SERIF, weight=700))
        doc.add(base.text(layout.caption_x, layout.caption_y + 110, "listening to coach on field", 46, palette.ink, family=base.FONT_UI, weight=760))
        doc.add(base.line(layout.caption_x, layout.caption_y + 130, layout.caption_x + 510, layout.caption_y + 130, palette.accent, stroke_width=1.2, opacity=0.55))
    else:
        doc.add(base.text(layout.caption_x, layout.caption_y + 54, "group of soccer players", 52, palette.ink, family=base.FONT_SERIF, weight=700))
        doc.add(base.text(layout.caption_x, layout.caption_y + 110, "listening to coach on field", 44, palette.ink, family=base.FONT_UI, weight=760))


def poster_caption(doc: base.Doc, layout: Layout, palette: Palette, variant: str) -> None:
    doc.add(base.text(layout.caption_x, layout.caption_y, "CAPTION", 12, palette.muted, family=base.FONT_UI, weight=800, letter_spacing=1.0))
    if variant == "split_balance":
        size = 56
        lines = base.DATA["caption_three_lines"]
    elif variant == "balanced":
        size = 64
        lines = base.DATA["caption_three_lines"]
    else:
        size = 60
        lines = base.DATA["caption_three_lines"]
    doc.add(
        base.text_block(
            layout.caption_x,
            layout.caption_y + 58,
            lines,
            size,
            palette.ink,
            family=base.FONT_BLACK,
            weight=900,
            line_height=0.90,
        )
    )


def dock(doc: base.Doc, layout: Layout, palette: Palette) -> None:
    fill = gradient(doc, palette.dock_top, palette.dock_bottom)
    doc.add(base.rect(layout.dock_x, layout.dock_y, layout.dock_w, layout.dock_h, fill, rx=32, stroke=palette.dock_stroke, opacity=palette.dock_opacity))
    if layout.divider_x is not None and layout.style != "split_balance":
        doc.add(base.line(layout.divider_x, layout.dock_y + 26, layout.divider_x, layout.dock_y + layout.dock_h - 26, palette.dock_stroke, stroke_width=1.0, opacity=0.45))


def draw_concept(doc: base.Doc, photo_href: str, family: str, variant: str) -> None:
    palette, layout = select_palette_and_layout(family, variant)
    draw_background(doc, photo_href, palette)
    dock(doc, layout, palette)
    top_hud(doc, palette, progress_card_w=90 if variant != "crisp_glass" else 92)

    chip_family = base.FONT_UI
    mini_cards = variant in {"split_balance", "crisp_glass", "balanced"}

    if family == "bold_sans":
        bold_caption(doc, layout, palette, variant_key(variant))
    elif family == "editorial_mix":
        editorial_caption(doc, layout, palette, variant_key(variant))
        chip_family = base.FONT_SERIF if variant != "crisp_glass" else base.FONT_UI
    else:
        poster_caption(doc, layout, palette, variant_key(variant))

    right_cluster(doc, layout, palette, chip_family=chip_family, mini_cards=mini_cards)
    base.close_button(doc, palette.ink, palette.hud_bottom, palette.hud_stroke)


def variant_key(variant: str) -> str:
    if "split_balance" in variant:
        return "split_balance"
    if "balanced" in variant:
        return "balanced"
    if "left_band" in variant:
        return "left_band"
    if "smoke_glass" in variant:
        return "smoke_glass"
    return "crisp_glass"


def select_palette_and_layout(family: str, variant: str) -> tuple[Palette, Layout]:
    layout_lookup = {
        "left_band": LEFT_BAND_LAYOUT,
        "split_balance": SPLIT_BALANCE_LAYOUT,
        "smoke_glass": SMOKE_LAYOUT,
        "crisp_glass": CRISP_LAYOUT,
        "balanced": BALANCED_LAYOUT,
    }
    layout = layout_lookup[variant_key(variant)]

    if family == "bold_sans":
        base_palette = {
            "accent": "#2f90b8",
            "ink": "#f7fbff",
            "muted": "#adc2cf",
        }
    elif family == "editorial_mix":
        base_palette = {
            "accent": "#8eaec1",
            "ink": "#f6f4ef",
            "muted": "#c5c9cc",
        }
    else:
        base_palette = {
            "accent": "#27a0c9",
            "ink": "#ffffff",
            "muted": "#b9d4df",
        }

    material = variant_key(variant)
    if material == "smoke_glass":
        return (
            Palette(
                accent=base_palette["accent"],
                ink=base_palette["ink"],
                muted=base_palette["muted"],
                overlay="#081018",
                overlay_opacity=0.22,
                bottom_shadow="#050b12",
                bottom_shadow_opacity=0.52,
                hud_top="#0a1117",
                hud_bottom="#0c141b",
                hud_stroke="#37515f",
                hud_opacity=0.84,
                dock_top="#081019",
                dock_bottom="#0a1117",
                dock_stroke="#324a58",
                dock_opacity=0.86,
                panel_top="#0e1a24",
                panel_bottom="#101c26",
                panel_stroke="#36505f",
                chip_fill="#112131",
                chip_stroke="#36505f",
            ),
            layout,
        )
    if material == "crisp_glass":
        return (
            Palette(
                accent=base_palette["accent"],
                ink=base_palette["ink"],
                muted=base_palette["muted"],
                overlay="#07111a",
                overlay_opacity=0.16,
                bottom_shadow="#04101a",
                bottom_shadow_opacity=0.42,
                hud_top="#0d1b26",
                hud_bottom="#10202d",
                hud_stroke="#5a89a0",
                hud_opacity=0.96,
                dock_top="#0c1823",
                dock_bottom="#10212e",
                dock_stroke="#5a89a0",
                dock_opacity=0.95,
                panel_top="#132736",
                panel_bottom="#173042",
                panel_stroke="#5f91aa",
                chip_fill="#163043",
                chip_stroke="#5f91aa",
            ),
            layout,
        )
    if material == "split_balance":
        return (
            Palette(
                accent=base_palette["accent"],
                ink=base_palette["ink"],
                muted=base_palette["muted"],
                overlay="#07111a",
                overlay_opacity=0.18,
                bottom_shadow="#04101a",
                bottom_shadow_opacity=0.45,
                hud_top="#0b1620",
                hud_bottom="#0f1b25",
                hud_stroke="#43697b",
                hud_opacity=0.92,
                dock_top="#0a141e",
                dock_bottom="#0d1823",
                dock_stroke="#466b7d",
                dock_opacity=0.93,
                panel_top="#11202f",
                panel_bottom="#132637",
                panel_stroke="#4d7688",
                chip_fill="#14293a",
                chip_stroke="#4d7688",
            ),
            layout,
        )
    if material == "balanced":
        return (
            Palette(
                accent=base_palette["accent"],
                ink=base_palette["ink"],
                muted=base_palette["muted"],
                overlay="#07111a",
                overlay_opacity=0.18,
                bottom_shadow="#04101a",
                bottom_shadow_opacity=0.46,
                hud_top="#0b1620",
                hud_bottom="#0f1c27",
                hud_stroke="#4b7082",
                hud_opacity=0.93,
                dock_top="#0b1520",
                dock_bottom="#0d1a26",
                dock_stroke="#4a7082",
                dock_opacity=0.94,
                panel_top="#112332",
                panel_bottom="#143043",
                panel_stroke="#50798c",
                chip_fill="#132a3a",
                chip_stroke="#50798c",
            ),
            layout,
        )
    return (
        Palette(
            accent=base_palette["accent"],
            ink=base_palette["ink"],
            muted=base_palette["muted"],
            overlay="#071018",
            overlay_opacity=0.18,
            bottom_shadow="#040f19",
            bottom_shadow_opacity=0.44,
            hud_top="#0b1520",
            hud_bottom="#0e1a25",
            hud_stroke="#446879",
            hud_opacity=0.92,
            dock_top="#0a131d",
            dock_bottom="#0d1722",
            dock_stroke="#46697a",
            dock_opacity=0.93,
            panel_top="#11212f",
            panel_bottom="#142637",
            panel_stroke="#4b7182",
            chip_fill="#142739",
            chip_stroke="#4b7182",
        ),
        layout,
    )


def make_concept(family: str, variant: str):
    def renderer(photo_href: str, blur_href: str) -> str:  # noqa: ARG001
        doc = base.Doc()
        draw_concept(doc, photo_href, family, variant)
        return base.make_svg(doc)

    return renderer


REFINEMENTS = [
    ("21_bold_sans_left_band", make_concept("bold_sans", "left_band")),
    ("22_bold_sans_split_balance", make_concept("bold_sans", "split_balance")),
    ("23_bold_sans_smoke_glass", make_concept("bold_sans", "smoke_glass")),
    ("24_bold_sans_crisp_glass", make_concept("bold_sans", "crisp_glass")),
    ("25_bold_sans_balanced", make_concept("bold_sans", "balanced")),
    ("26_editorial_mix_left_band", make_concept("editorial_mix", "left_band")),
    ("27_editorial_mix_split_balance", make_concept("editorial_mix", "split_balance")),
    ("28_editorial_mix_smoke_glass", make_concept("editorial_mix", "smoke_glass")),
    ("29_editorial_mix_crisp_glass", make_concept("editorial_mix", "crisp_glass")),
    ("30_editorial_mix_balanced", make_concept("editorial_mix", "balanced")),
    ("31_poster_scale_left_band", make_concept("poster_scale", "left_band")),
    ("32_poster_scale_split_balance", make_concept("poster_scale", "split_balance")),
    ("33_poster_scale_smoke_glass", make_concept("poster_scale", "smoke_glass")),
    ("34_poster_scale_crisp_glass", make_concept("poster_scale", "crisp_glass")),
    ("35_poster_scale_balanced", make_concept("poster_scale", "balanced")),
]


def main() -> None:
    photo_href, blur_href = base.ensure_sample_images()
    for slug, renderer in REFINEMENTS:
        svg_path = OUT_DIR / f"{slug}.svg"
        png_path = OUT_DIR / f"{slug}.png"
        svg_path.write_text(renderer(photo_href, blur_href), encoding="utf-8")
        base.render_png(svg_path, png_path)


if __name__ == "__main__":
    main()
