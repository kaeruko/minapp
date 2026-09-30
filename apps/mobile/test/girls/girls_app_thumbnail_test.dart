import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_app_thumbnail.dart';

void main() {
  test('bundled defaults resolve by provenance instead of app title', () {
    expect(
      girlsBundledAppArtworkAsset(
        shopSourceAppId: 'ecb3cb6a08e05305668a952cbdae435b',
      ),
      'assets/girls/cutouts/minapp_cards_480/drawing_card.png',
    );
    expect(
      girlsBundledAppArtworkAsset(
        shopSourceAppId: '9571adacf55c47b4ac772cd48621a08b',
      ),
      'assets/girls/cutouts/minapp_cards_480/sing_along_card.png',
    );
    expect(
      girlsBundledAppArtworkAsset(builtinId: 'novel-editor'),
      'assets/girls/home/cards/novel_card.png',
    );
    expect(
      girlsBundledAppArtworkAsset(builtinId: 'memo'),
      'assets/girls/home/cards/memo_card.png',
    );
    expect(
      girlsBundledAppArtworkAsset(),
      isNull,
    );
  });

  test('shop provenance wins over builtin default when both are present', () {
    expect(
      girlsBundledAppArtworkAsset(
        shopSourceAppId: 'ecb3cb6a08e05305668a952cbdae435b',
        builtinId: 'novel-editor',
      ),
      'assets/girls/cutouts/minapp_cards_480/drawing_card.png',
    );
  });
}
