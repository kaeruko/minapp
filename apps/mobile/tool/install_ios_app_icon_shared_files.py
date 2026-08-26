#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile

import install_ios_app_icon as base


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            "Usage: install_ios_app_icon_shared_files.py "
            "<ios/Runner/Assets.xcassets/AppIcon.appiconset>"
        )

    iconset_dir = Path(sys.argv[1])
    contents_path = iconset_dir / "Contents.json"
    if not iconset_dir.is_dir():
        base.fail(f"AppIcon asset directory does not exist: {iconset_dir}")
    if not contents_path.is_file():
        base.fail(f"AppIcon Contents.json does not exist: {contents_path}")

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
        assert isinstance(filename, str)

        previous_size = target_sizes.get(filename)
        if previous_size is not None and previous_size != pixel_size:
            base.fail(
                "AppIcon Contents.json reuses filename "
                f"{filename!r} for conflicting sizes: {previous_size}px and {pixel_size}px"
            )
        target_sizes[filename] = pixel_size

    with tempfile.TemporaryDirectory(prefix="minapp-ios-icon-") as temp_dir:
        source_path = Path(temp_dir) / "minapp-icon-512.png"
        base.write_source_png(source_path)
        base.validate_opaque_square(source_path, base.SOURCE_WIDTH)

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
                base.fail(f"sips completed without creating expected icon: {target}")
            base.validate_opaque_square(target, pixel_size)

    shared_references = len(images) - len(target_sizes)
    print(
        "Installed MinApp icon into "
        f"{len(target_sizes)} unique AppIcon files referenced by {len(images)} entries "
        f"({shared_references} shared filename references)"
    )


if __name__ == "__main__":
    main()
