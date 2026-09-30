import 'package:flutter/material.dart';

const String _drawingShopAppId = 'ecb3cb6a08e05305668a952cbdae435b';
const String _singAlongShopAppId = '9571adacf55c47b4ac772cd48621a08b';

const String _drawingAsset =
    'assets/girls/cutouts/minapp_cards_480/drawing_card.png';
const String _singAlongAsset =
    'assets/girls/cutouts/minapp_cards_480/sing_along_card.png';
const String _memoAsset = 'assets/girls/home/cards/memo_card.png';
const String _minappchiAsset = 'assets/girls/home/cards/minappchi_card.png';
const String _novelAsset = 'assets/girls/home/cards/novel_card.png';

String? girlsBundledAppArtworkAsset({
  String? shopSourceAppId,
  String? builtinId,
}) {
  final String? shopAsset = switch (shopSourceAppId) {
    _drawingShopAppId => _drawingAsset,
    _singAlongShopAppId => _singAlongAsset,
    _ => null,
  };
  if (shopAsset != null) return shopAsset;

  return switch (builtinId) {
    'memo' => _memoAsset,
    'minappchi' => _minappchiAsset,
    'novel-editor' || 'novel-starter' => _novelAsset,
    _ => null,
  };
}

class GirlsAppThumbnail extends StatelessWidget {
  const GirlsAppThumbnail({
    required this.uri,
    required this.accessToken,
    required this.size,
    required this.radius,
    required this.semanticLabel,
    required this.fallback,
    this.shopSourceAppId,
    this.builtinId,
    super.key,
  });

  final Uri uri;
  final String accessToken;
  final double size;
  final double radius;
  final String semanticLabel;
  final Widget fallback;
  final String? shopSourceAppId;
  final String? builtinId;

  @override
  Widget build(BuildContext context) {
    final String? bundledAsset = girlsBundledAppArtworkAsset(
      shopSourceAppId: shopSourceAppId,
      builtinId: builtinId,
    );

    Widget defaultArtwork() {
      final String? asset = bundledAsset;
      if (asset == null) {
        return SizedBox.square(
          dimension: size,
          child: fallback,
        );
      }
      return SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            semanticLabel: semanticLabel,
          ),
        ),
      );
    }

    // A user-saved thumbnail always wins. Bundled shop/builtin artwork is only
    // the default when the app has no saved thumbnail (404) or it cannot load.
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          uri.toString(),
          headers: <String, String>{
            'Authorization': 'Bearer $accessToken',
          },
          fit: BoxFit.contain,
          semanticLabel: semanticLabel,
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stackTrace,
          ) =>
              defaultArtwork(),
          frameBuilder: (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) =>
              wasSynchronouslyLoaded || frame != null
                  ? child
                  : defaultArtwork(),
        ),
      ),
    );
  }
}
