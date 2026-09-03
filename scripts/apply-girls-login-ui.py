from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
girls_app_path = ROOT / "apps" / "mobile" / "lib" / "girls_app.dart"
pubspec_path = ROOT / "apps" / "mobile" / "pubspec.yaml"
test_path = ROOT / "apps" / "mobile" / "test" / "girls_login_art_assets_test.dart"

girls = girls_app_path.read_text(encoding="utf-8")
pubspec = pubspec_path.read_text(encoding="utf-8")

constants_old = '''const String _mascotPairAsset = 'assets/girls/mascot_pair.svg';

const Set<String> _girlsBuiltinIds'''
constants_new = '''const String _mascotPairAsset = 'assets/girls/mascot_pair.svg';
const String _girlsLoginHeroBackgroundAsset =
    'assets/girls/generated/login_hero_bg.png';

const Set<String> _girlsBuiltinIds'''
if constants_old not in girls:
    raise RuntimeError("Expected Girls mascot constant block was not found.")
girls = girls.replace(constants_old, constants_new, 1)

insert_anchor = '''class _GirlsLogo extends StatelessWidget {
'''
hero_class = r'''class _GirlsLoginHero extends StatelessWidget {
  const _GirlsLoginHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        height: 300,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              _girlsLoginHeroBackgroundAsset,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            const Positioned(
              left: 20,
              right: 20,
              bottom: 34,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _GirlsMascot(
                  assetName: _mascotPairAsset,
                  width: 215,
                  height: 118,
                  semanticsLabel: 'みんアプ Girls のふたりのマスコット',
                ),
              ),
            ),
            Positioned(
              right: 22,
              bottom: 104,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 125),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE7B5C8),
                    width: 1.3,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x22A36B8A),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  'おかえりなさい ♡',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _lavenderDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''
if insert_anchor not in girls:
    raise RuntimeError("Expected _GirlsLogo class anchor was not found.")
girls = girls.replace(insert_anchor, hero_class + insert_anchor, 1)

auth_old = '''                    const _GirlsMascot(
                      assetName: _mascotPairAsset,
                      width: 220,
                      height: 112,
                      semanticsLabel: 'みんアプ Girls のふたりのマスコット',
                    ),
                    const SizedBox(height: 8),
                    const _GirlsLogo(),
                    const SizedBox(height: 8),
                    const Text(
                      'かわいいアプリを、友達といっしょに。',
                      style: TextStyle(
                        color: Color(0xFF8C7893),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PastelPanel(
'''
auth_new = '''                    const _GirlsLoginHero(),
                    const SizedBox(height: 16),
                    const Text(
                      'かわいいアプリを、友達といっしょに。',
                      style: TextStyle(
                        color: Color(0xFF8C7893),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PastelPanel(
'''
if auth_old not in girls:
    raise RuntimeError("Expected Girls auth header block was not found.")
girls = girls.replace(auth_old, auth_new, 1)

asset_line = "    - assets/girls/generated/login_hero_bg.png\n"
anchor = "    - assets/girls/mascot_black.svg\n"
if asset_line not in pubspec:
    if anchor not in pubspec:
        raise RuntimeError("Expected Girls asset anchor was not found in pubspec.yaml.")
    pubspec = pubspec.replace(anchor, anchor + asset_line, 1)

girls_app_path.write_text(girls, encoding="utf-8", newline="\n")
pubspec_path.write_text(pubspec, encoding="utf-8", newline="\n")

test_path.write_text(
    '''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Girls login hero background asset renders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Image.asset(
            'assets/girls/generated/login_hero_bg.png',
            width: 360,
            height: 220,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
''',
    encoding="utf-8",
    newline="\n",
)
