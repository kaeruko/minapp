import 'package:flutter/material.dart';

class GirlsAppThumbnail extends StatelessWidget {
  const GirlsAppThumbnail({
    required this.uri,
    required this.accessToken,
    required this.size,
    required this.radius,
    required this.semanticLabel,
    required this.fallback,
    super.key,
  });

  final Uri uri;
  final String accessToken;
  final double size;
  final double radius;
  final String semanticLabel;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    Widget fallbackBox() => SizedBox.square(
          dimension: size,
          child: fallback,
        );

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
              fallbackBox(),
          frameBuilder: (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) =>
              wasSynchronouslyLoaded || frame != null
                  ? child
                  : fallbackBox(),
        ),
      ),
    );
  }
}
