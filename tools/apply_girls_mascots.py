from __future__ import annotations

import base64
import hashlib
import io
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / ".github" / "girls-assets"
MOBILE = ROOT / "apps" / "mobile"

EXPECTED_ZIP_SHA256 = "defa024db1c5fd1208142f26a1fa11077222c07411fd854f13698d7cd5bebc91"
EXPECTED_ASSETS = {
    "mascot_pair.svg": "53b715abd3aacb21561c2ff20c33d7759bfebcabaed5a62f8248c574101b68bd",
    "mascot_white.svg": "d3ece705867d0b9eee8c3227699503616ca83f82efcabe41e66d4231c76e58e0",
    "mascot_black.svg": "0f0c6704faeca9132b505d38336e11ca4e64e17ca0ed6233b30c9b752565b6e8",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_required(path: Path) -> str:
    if not path.is_file():
        raise FileNotFoundError(f"Required staged payload file is missing: {path}")
    return path.read_text(encoding="ascii").strip()


def reconstruct_zip() -> bytes:
    prefix_b64 = "".join(
        read_required(STAGE / f"girls.zip.{index:02d}.b64")
        for index in range(3)
    )
    prefix = base64.b64decode(prefix_b64, validate=True)
    if len(prefix) != 18_000:
        raise RuntimeError(
            f"Unexpected decoded prefix length: {len(prefix)} bytes; expected 18000"
        )

    tail_hex = "".join(
        read_required(STAGE / f"girls.tail.{index:02d}.hex")
        for index in range(3)
    )
    tail = bytes.fromhex(tail_hex)
    if len(tail) != 8_942:
        raise RuntimeError(
            f"Unexpected decoded tail length: {len(tail)} bytes; expected 8942"
        )

    payload = prefix + tail
    actual = sha256(payload)
    if actual != EXPECTED_ZIP_SHA256:
        raise RuntimeError(
            "Mascot ZIP SHA256 mismatch: "
            f"actual={actual} expected={EXPECTED_ZIP_SHA256}"
        )
    return payload


def extract_assets(payload: bytes) -> None:
    output_dir = MOBILE / "assets" / "girls"
    output_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(io.BytesIO(payload), "r") as archive:
        names = archive.namelist()
        expected_names = list(EXPECTED_ASSETS)
        if names != expected_names:
            raise RuntimeError(
                f"Unexpected ZIP entries/order: {names!r}; expected {expected_names!r}"
            )
        for name, expected_hash in EXPECTED_ASSETS.items():
            data = archive.read(name)
            actual_hash = sha256(data)
            if actual_hash != expected_hash:
                raise RuntimeError(
                    f"{name} SHA256 mismatch: actual={actual_hash} expected={expected_hash}"
                )
            target = output_dir / name
            if target.exists():
                raise FileExistsError(f"Refusing to overwrite existing asset: {target}")
            target.write_bytes(data)


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{label}: expected exactly one source match in {path}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def patch_pubspec() -> None:
    path = MOBILE / "pubspec.yaml"
    replace_once(
        path,
        '  http: ">=1.2.0 <2.0.0"\n',
        '  http: ">=1.2.0 <2.0.0"\n  flutter_svg: 2.0.10+1\n',
        "add flutter_svg dependency",
    )
    replace_once(
        path,
        "    - assets/builtin/novel_starter/face.jpg\n",
        "    - assets/builtin/novel_starter/face.jpg\n"
        "    - assets/girls/mascot_pair.svg\n"
        "    - assets/girls/mascot_white.svg\n"
        "    - assets/girls/mascot_black.svg\n",
        "register Girls mascot assets",
    )


def patch_girls_app() -> None:
    path = MOBILE / "lib" / "girls_app.dart"
    replace_once(
        path,
        "import 'package:flutter/services.dart';\n",
        "import 'package:flutter/services.dart';\n"
        "import 'package:flutter_svg/flutter_svg.dart';\n",
        "import flutter_svg",
    )
    replace_once(
        path,
        "const Color _text = Color(0xFF5D4037);\n",
        "const Color _text = Color(0xFF5D4037);\n\n"
        "const String _mascotPairAsset = 'assets/girls/mascot_pair.svg';\n",
        "add mascot asset constants",
    )
    replace_once(
        path,
        "class _GirlsLogo extends StatelessWidget {\n",
        "class _GirlsMascot extends StatelessWidget {\n"
        "  const _GirlsMascot({\n"
        "    required this.assetName,\n"
        "    required this.width,\n"
        "    required this.height,\n"
        "    required this.semanticsLabel,\n"
        "  });\n\n"
        "  final String assetName;\n"
        "  final double width;\n"
        "  final double height;\n"
        "  final String semanticsLabel;\n\n"
        "  @override\n"
        "  Widget build(BuildContext context) {\n"
        "    return SvgPicture.asset(\n"
        "      assetName,\n"
        "      width: width,\n"
        "      height: height,\n"
        "      fit: BoxFit.contain,\n"
        "      semanticsLabel: semanticsLabel,\n"
        "    );\n"
        "  }\n"
        "}\n\n"
        "class _GirlsLogo extends StatelessWidget {\n",
        "add Girls mascot widget",
    )
    replace_once(
        path,
        "                  children: <Widget>[\n"
        "                    const _GirlsLogo(),\n"
        "                    const SizedBox(height: 8),\n",
        "                  children: <Widget>[\n"
        "                    const _GirlsMascot(\n"
        "                      assetName: _mascotPairAsset,\n"
        "                      width: 220,\n"
        "                      height: 112,\n"
        "                      semanticsLabel: 'みんアプ Girls のふたりのマスコット',\n"
        "                    ),\n"
        "                    const SizedBox(height: 8),\n"
        "                    const _GirlsLogo(),\n"
        "                    const SizedBox(height: 8),\n",
        "place mascot on Girls login",
    )
    replace_once(
        path,
        "                                const CircleAvatar(\n"
        "                                  radius: 28,\n"
        "                                  backgroundColor: _pink,\n"
        "                                  child: Icon(\n"
        "                                    Icons.groups_rounded,\n"
        "                                    color: Colors.white,\n"
        "                                    size: 31,\n"
        "                                  ),\n"
        "                                ),\n"
        "                                const SizedBox(width: 15),\n",
        "                                const _GirlsMascot(\n"
        "                                  assetName: _mascotPairAsset,\n"
        "                                  width: 92,\n"
        "                                  height: 76,\n"
        "                                  semanticsLabel: 'みんアプ Girls のふたりのマスコット',\n"
        "                                ),\n"
        "                                const SizedBox(width: 15),\n",
        "place mascot in Girls home greeting",
    )


def add_asset_test() -> None:
    path = MOBILE / "test" / "girls_mascot_assets_test.dart"
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite existing test: {path}")
    path.write_text(
        "import 'package:flutter/material.dart';\n"
        "import 'package:flutter_svg/flutter_svg.dart';\n"
        "import 'package:flutter_test/flutter_test.dart';\n\n"
        "void main() {\n"
        "  const List<String> assets = <String>[\n"
        "    'assets/girls/mascot_pair.svg',\n"
        "    'assets/girls/mascot_white.svg',\n"
        "    'assets/girls/mascot_black.svg',\n"
        "  ];\n\n"
        "  for (final String asset in assets) {\n"
        "    testWidgets('Girls mascot SVG loads: $asset', (WidgetTester tester) async {\n"
        "      await tester.pumpWidget(\n"
        "        MaterialApp(\n"
        "          home: Scaffold(body: SvgPicture.asset(asset)),\n"
        "        ),\n"
        "      );\n"
        "      await tester.pumpAndSettle();\n"
        "      expect(tester.takeException(), isNull);\n"
        "      expect(find.byType(SvgPicture), findsOneWidget);\n"
        "    });\n"
        "  }\n"
        "}\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    payload = reconstruct_zip()
    extract_assets(payload)
    patch_pubspec()
    patch_girls_app()
    add_asset_test()

    girls_app = (MOBILE / "lib" / "girls_app.dart").read_text(encoding="utf-8")
    if "_mascotPairAsset" not in girls_app:
        raise RuntimeError("Expected mascot pair constant missing after patch")


if __name__ == "__main__":
    main()
