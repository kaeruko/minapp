#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys

import install_ios_app_icon as base
import install_ios_app_icon_shared_files as shared


LAUNCH_IMAGE_POINTS = 96


def _girls_icon_source() -> Path:
    mobile_dir = Path(__file__).resolve().parent.parent
    source = mobile_dir.parent / "web" / "girls-assets" / "brand_icon.png"
    if not source.is_file():
        base.fail(f"Girls brand icon does not exist: {source}")
    return source


def _install_girls_launch_image(iconset_dir: Path, source_path: Path) -> None:
    assets_dir = iconset_dir.parent
    launchset_dir = assets_dir / "LaunchImage.imageset"
    launch_contents_path = launchset_dir / "Contents.json"
    storyboard_path = assets_dir.parent / "Base.lproj" / "LaunchScreen.storyboard"

    if not launchset_dir.is_dir():
        base.fail(f"LaunchImage asset directory does not exist: {launchset_dir}")
    if not launch_contents_path.is_file():
        base.fail(f"LaunchImage Contents.json does not exist: {launch_contents_path}")
    if not storyboard_path.is_file():
        base.fail(f"LaunchScreen storyboard does not exist: {storyboard_path}")

    storyboard = storyboard_path.read_text(encoding="utf-8")
    if 'image="LaunchImage"' not in storyboard:
        base.fail(
            "Generated LaunchScreen storyboard does not reference LaunchImage: "
            f"{storyboard_path}"
        )

    launch_contents = json.loads(launch_contents_path.read_text(encoding="utf-8"))
    launch_images = launch_contents.get("images")
    if not isinstance(launch_images, list) or not launch_images:
        base.fail(
            f"LaunchImage Contents.json has no non-empty images list: {launch_contents_path}"
        )

    expected_scales = {"1x": 1, "2x": 2, "3x": 3}
    generated_scales: set[str] = set()

    for index, item in enumerate(launch_images):
        if not isinstance(item, dict):
            base.fail(f"LaunchImage entry {index} is not an object: {item!r}")

        filename = item.get("filename")
        scale = item.get("scale")
        if filename is None:
            continue
        if not isinstance(filename, str) or not filename:
            base.fail(f"LaunchImage entry {index} has invalid filename: {item!r}")
        if scale not in expected_scales:
            base.fail(
                f"LaunchImage entry {index} has unsupported scale {scale!r}: {item!r}"
            )
        if scale in generated_scales:
            base.fail(f"LaunchImage Contents.json repeats scale {scale}: {launch_contents_path}")

        pixel_size = LAUNCH_IMAGE_POINTS * expected_scales[scale]
        target = launchset_dir / filename
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
            base.fail(f"sips completed without creating Girls launch image: {target}")
        base.validate_opaque_square(target, pixel_size)
        generated_scales.add(scale)

    missing_scales = set(expected_scales) - generated_scales
    if missing_scales:
        base.fail(
            "LaunchImage Contents.json does not provide all expected scales; missing "
            f"{sorted(missing_scales)}: {launch_contents_path}"
        )


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

    _install_girls_launch_image(iconset_dir, source_path)
    shared.configure_runner_info_plist(iconset_dir)

    shared_references = len(images) - len(target_sizes)
    print(
        "Installed MinApp Girls flower icon from "
        f"{source_path} into {len(target_sizes)} unique AppIcon files referenced by "
        f"{len(images)} entries ({shared_references} shared filename references), "
        f"installed {LAUNCH_IMAGE_POINTS}pt flower LaunchImage assets, "
        "and configured microphone usage"
    )


if __name__ == "__main__":
    main()
