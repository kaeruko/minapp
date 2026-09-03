from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
girls_path = ROOT / "apps" / "mobile" / "lib" / "girls_app.dart"
pubspec_path = ROOT / "apps" / "mobile" / "pubspec.yaml"
test_path = ROOT / "apps" / "mobile" / "test" / "girls_login_art_assets_test.dart"

girls = girls_path.read_text(encoding="utf-8")
pubspec = pubspec_path.read_text(encoding="utf-8")
test = test_path.read_text(encoding="utf-8")

old_asset = "assets/girls/generated/login_hero_bg.png"
new_asset = "assets/girls/generated/login_hero_bg.svg"

if old_asset not in girls:
    raise RuntimeError("Girls login hero PNG reference not found in girls_app.dart")
girls = girls.replace(old_asset, new_asset, 1)

old_picture = """            Image.asset(\n              _girlsLoginHeroBackgroundAsset,\n              fit: BoxFit.cover,\n              alignment: Alignment.topCenter,\n            ),\n            const Positioned(\n              left: 20,\n"""
new_picture = """            SvgPicture.asset(\n              _girlsLoginHeroBackgroundAsset,\n              fit: BoxFit.cover,\n              alignment: Alignment.topCenter,\n            ),\n            const Positioned(\n              top: 52,\n              left: 20,\n              right: 20,\n              child: Center(child: _GirlsLogo()),\n            ),\n            const Positioned(\n              left: 20,\n"""
if old_picture not in girls:
    raise RuntimeError("Girls login hero Image.asset block not found")
girls = girls.replace(old_picture, new_picture, 1)

old_pubspec = "    - assets/girls/generated/login_hero_bg.png\n"
new_pubspec = "    - assets/girls/generated/login_hero_bg.svg\n"
if old_pubspec not in pubspec:
    raise RuntimeError("Girls login hero PNG asset line not found in pubspec.yaml")
pubspec = pubspec.replace(old_pubspec, new_pubspec, 1)

if "package:flutter_svg/flutter_svg.dart" not in test:
    test = test.replace(
        "import 'package:flutter_test/flutter_test.dart';\n",
        "import 'package:flutter_test/flutter_test.dart';\nimport 'package:flutter_svg/flutter_svg.dart';\n",
        1,
    )
if old_asset not in test:
    raise RuntimeError("Girls login hero PNG reference not found in asset test")
test = test.replace(old_asset, new_asset, 1)
old_test_widget = """          body: Image.asset(\n            'assets/girls/generated/login_hero_bg.svg',\n"""
new_test_widget = """          body: SvgPicture.asset(\n            'assets/girls/generated/login_hero_bg.svg',\n"""
if old_test_widget not in test:
    raise RuntimeError("Girls login hero Image.asset test block not found")
test = test.replace(old_test_widget, new_test_widget, 1)

girls_path.write_text(girls, encoding="utf-8", newline="\n")
pubspec_path.write_text(pubspec, encoding="utf-8", newline="\n")
test_path.write_text(test, encoding="utf-8", newline="\n")
