#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys

import install_ios_app_icon as base
import install_ios_app_icon_shared_files as shared


def _girls_icon_source() -> Path:
    mobile_dir = Path(__file__).resolve().parent.parent
    source = mobile_dir.parent / "web" / "girls-assets" / "brand_icon.png"
    if not source.is_file():
        base.fail(f"Girls brand icon does not exist: {source}")
    return source


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            "Usage: install_ios_app_icon_girls.py "
            "<ios/Runner/Assets.xcassets/AppIcon.appiconset>"
        )

    iconset_dir = Path(sys.argv[1])
    contents_path = iconset_dir / "Contents.json"
    if not iconset_dir.is_dir():
        base.fail(f"AppIcon asset directory does not exist: {iconset_dir}")
    if not contents_path.is_file():
        base.fail(f"AppIcon Contents.json does not exist: {contents_path}")

    source_path = _girls_icon_source()
    source_props = base.sips_properties(source_path)
    try:
        source_width = int(source_props["pixelWidth"])
        source_height = int(source_props["pixelHeight"])
    except (KeyError, ValueError) as exc:
        raise RuntimeError(
            f"Could not read Girls brand icon dimensions from sips output: {source_props}"
        ) from exc

    if source_width <= 0 or source_height <= 0:
        base.fail(
            "Girls brand icon has invalid dimensions: "
            f"{source_width}x{source_height}"
        )
    if source_width != source_height:
        base.fail(
            "Girls brand icon must be square: "
            f"{source_width}x{source_height} ({source_path})"
        )
    base.validate_opaque_square(source_path, source_width)

    contents = json.loads(contents_path.read_text(encoding="utf-8"))
    images = contents.get("images")
    if not isinstance(images, list) or not images:
        base.fail(f"AppIcon Contents.json has no non-empty images list: {contents_path}")

    target_sizes: dict[str, int] = {}
    for index, item in enumerate(images):
        if not isinstance(item, dict):
            base.fail(f"AppIcon image entry {index} is not an object: {item!r}")

        filename = item.get("filename")
        pixel_size = base.parse_pixel_size(item, index)
        if not isinstance(filename, str) or not filename:
            base.fail(f"AppIcon image entry {index} has no valid filename: {item!r}")

        previous_size = target_sizes.get(filename)
        if previous_size is not None and previous_size != pixel_size:
            base.fail(
                "AppIcon Contents.json reuses filename "
                f"{filename!r} for conflicting sizes: {previous_size}px and {pixel_size}px"
            )
        target_sizes[filename] = pixel_size

    for filename, pixel_size in target_sizes.items():
        target = iconset_dir / filename
        subprocess.run(
            [
                "sips",
                "-z",
                str(pixel_size),
                str(pixel_size),
                str(source_path),
                "--out",
                str(target),
            ],
            check=True,
        )
        if not target.is_file():
            base.fail(f"sips completed without creating expected Girls icon: {target}")
        base.validate_opaque_square(target, pixel_size)

    shared.configure_runner_info_plist(iconset_dir)

    shared_references = len(images) - len(target_sizes)
    print(
        "Installed MinApp Girls flower icon from "
        f"{source_path} into {len(target_sizes)} unique AppIcon files referenced by "
        f"{len(images)} entries ({shared_references} shared filename references) "
        "and configured microphone usage"
    )


if __name__ == "__main__":
    main()
