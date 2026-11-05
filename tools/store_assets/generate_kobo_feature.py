#!/usr/bin/env python3
"""Generate the Kobo Google Play feature graphic from checked-in art assets."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
ASSET_ROOT = ROOT / "apps" / "mobile" / "assets" / "kobo"
CANVAS = (1024, 500)
PAPER = (250, 243, 230)
RED = (199, 54, 46)
NAVY = (36, 58, 90)
BROWN = (91, 58, 34)
MUSTARD = (212, 161, 38)


def required_asset(relative_path: str) -> Image.Image:
    path = ASSET_ROOT / relative_path
    if not path.is_file():
        raise FileNotFoundError(f"Required Kobo artwork is missing: {path}")
    with Image.open(path) as original:
        original.load()
        return original.convert("RGBA")


def label_font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    if not path.is_file():
        raise FileNotFoundError(f"Required Japanese font is missing: {path}")
    return ImageFont.truetype(str(path), size)


def art_in_box(
    canvas: Image.Image, image: Image.Image, x: int, y: int, width: int, height: int
) -> None:
    fitted = ImageOps.contain(image, (width, height), Image.Resampling.LANCZOS)
    left = x + (width - fitted.width) // 2
    top = y + (height - fitted.height) // 2
    canvas.paste(fitted, (left, top), fitted)


def generate(font_path: Path, output: Path) -> None:
    image = Image.new("RGB", CANVAS, PAPER)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 15, 499), fill=RED)
    draw.rectangle((22, 18, 1002, 481), outline=(224, 206, 178), width=3)

    draw.rounded_rectangle((56, 72, 617, 123), radius=22, fill=NAVY)
    draw.text(
        (82, 78), "自分だけの小さな道具を作る",
        font=label_font(font_path, 28), fill=PAPER,
    )
    draw.text(
        (56, 141), "みんアプ工房",
        font=label_font(font_path, 79), fill=NAVY,
        stroke_width=1, stroke_fill=NAVY,
    )
    draw.text(
        (61, 271), "今日、なに作る？",
        font=label_font(font_path, 40), fill=RED,
    )
    draw.text(
        (63, 345), "作る・使う・みんなで楽しむ",
        font=label_font(font_path, 26), fill=BROWN,
    )
    draw.line((61, 416, 601, 416), fill=MUSTARD, width=6)

    draw.rounded_rectangle((672, 64, 966, 438), radius=24, fill=(243, 226, 195))
    draw.rounded_rectangle((680, 72, 958, 430), radius=18, outline=RED, width=4)
    art_in_box(image, required_asset("hero_sign.png"), 693, 98, 252, 166)
    icons = (
        ("categories/gourmet.png", 699),
        ("categories/drink_izakaya.png", 784),
        ("categories/games.png", 869),
    )
    for asset, x in icons:
        draw.rounded_rectangle(
            (x, 301, x + 74, 375), radius=14,
            fill=PAPER, outline=(213, 190, 149), width=2,
        )
        art_in_box(image, required_asset(asset), x + 8, 309, 58, 58)

    if image.mode != "RGB" or image.size != CANVAS:
        raise AssertionError(f"Unexpected feature image: {image.mode} {image.size}")
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, format="PNG", optimize=True)
    print(f"Wrote {output} ({image.width}x{image.height}, {image.mode})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    generate(args.font, args.output)


if __name__ == "__main__":
    main()
