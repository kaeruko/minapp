import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const String girlsDefaultGroupIconAsset = 'assets/girls/mascot_pair.svg';

class GirlsGroupIcon extends StatelessWidget {
  const GirlsGroupIcon({
    this.uri,
    this.accessToken,
    required this.size,
    required this.semanticLabel,
    this.radius,
    super.key,
  });

  final Uri? uri;
  final String? accessToken;
  final double size;
  final String semanticLabel;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => _DefaultGroupIcon(size: size);

    final Uri? imageUri = uri;
    if (imageUri == null) return fallback();
    final String? token = accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Authenticated group icon requires an access token.');
    }

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? size / 2),
        child: Image.network(
          imageUri.toString(),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
          },
          fit: BoxFit.cover,
          semanticLabel: semanticLabel,
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stackTrace,
          ) =>
              fallback(),
          frameBuilder: (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) =>
              wasSynchronouslyLoaded || frame != null ? child : fallback(),
        ),
      ),
    );
  }
}

class _DefaultGroupIcon extends StatelessWidget {
  const _DefaultGroupIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .09),
      color: const Color(0xFFF7EAF0),
      child: SvgPicture.asset(
        girlsDefaultGroupIconAsset,
        fit: BoxFit.contain,
        semanticsLabel: 'グループのデフォルト画像',
      ),
    );
  }
}
