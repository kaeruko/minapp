#!/usr/bin/env python3
"""Validate and normalize explicitly expected store PNGs (never resize images)."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

EXPECTED = {
    "feature": ((1024, 500), {"feature-graphic.png"}),
    "iphone": ((1206, 2622), {"01-home.png", "02-code-editor.png"}),
    "ipad": ((2064, 2752), {"01-home.png", "02-code-editor.png"}),
}


def validate(kind: str, directory: Path) -> None:
    size, expected_names = EXPECTED[kind]
    if not directory.is_dir():
        raise FileNotFoundError(f"Store image directory is missing: {directory}")
    actual_names = {path.name for path in directory.iterdir() if path.is_file()}
    if actual_names != expected_names:
        raise RuntimeError(
            f"{kind} file set mismatch; expected {sorted(expected_names)}, "
            f"got {sorted(actual_names)}"
        )
    for filename in sorted(expected_names):
        path = directory / filename
        with Image.open(path) as original:
            original.load()
            if original.format != "PNG":
                raise ValueError(f"{path}: expected PNG, got {original.format}")
            if original.size != size:
                raise ValueError(
                    f"{path}: wrong screenshot size {original.size}; expected {size}. "
                    "No scaling or alternate device will be attempted."
                )
            if original.mode == "RGBA":
                if original.getchannel("A").getextrema() != (255, 255):
                    raise ValueError(f"{path}: transparent pixels are not allowed")
                normalized = original.convert("RGB")
            elif original.mode == "RGB":
                normalized = original.copy()
            else:
                raise ValueError(f"{path}: unsupported PNG color mode {original.mode}")
        normalized.save(path, format="PNG", optimize=True)
        print(f"Validated {path} ({size[0]}x{size[1]}, RGB PNG)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=sorted(EXPECTED), required=True)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    validate(args.kind, args.directory)


if __name__ == "__main__":
    main()
