import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _girlsCream = Color(0xFFFCF4E9);
const Color _headerCream = Color(0xFFFBF3E8);
const String _headerBackground =
    'assets/girls/backgrounds/girls_header_bg_top.png';
const String _bodyBackground = 'assets/girls/backgrounds/girls_body_bg.jpg';
const String _girlsLogo = 'assets/girls/generated/minapp_girls_logo.png';

/// Keeps the supplied artwork stationary while each page scrolls its content.
class GirlsScaffold extends StatelessWidget {
  const GirlsScaffold({
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    required this.body,
    required this.bottomNavigationBar,
    super.key,
  });

  final String? title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget body;
  final Widget bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _girlsCream,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _girlsCream,
        extendBody: true,
        bottomNavigationBar: SafeArea(top: false, child: bottomNavigationBar),
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final _HeaderLayout header = _HeaderLayout.forWidth(
              MediaQuery.of(context),
              constraints.maxWidth,
              hasLeading: leading != null,
              actionCount: actions.length,
            );
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Start behind the transparent scallops, so the body artwork
                // shows through the lace instead of a rectangular header fill.
                Positioned(
                  top: header.height - header.laceHeight,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: const _GirlsBodyBackground(),
                ),
                Column(
                  children: <Widget>[
                    GirlsCommonHeader(leading: leading, actions: actions),
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          if (title != null)
                            SafeArea(
                              top: false,
                              bottom: false,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      title!,
                                      key: const Key('girls-page-title'),
                                      style: const TextStyle(
                                        color: Color(0xFF745B9E),
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: ClipRect(
                              child: SafeArea(
                                top: false,
                                child: body,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The PNG is 1200 x 450; its bottom 100 pixels contain the scalloped lace.
class _HeaderLayout {
  const _HeaderLayout({
    required this.artHeight,
    required this.height,
    required this.laceHeight,
    required this.rowTop,
    required this.rowHeight,
    required this.logoWidth,
  });

  factory _HeaderLayout.forWidth(
    MediaQueryData media,
    double width, {
    required bool hasLeading,
    required int actionCount,
  }) {
    final double contentWidth =
        math.max(0, width - media.padding.horizontal - 24);
    final double sideWidth =
        math.max(hasLeading ? 48 : 0, actionCount * 48).toDouble();
    final double logoWidth =
        math.min(128, math.max(48, contentWidth - sideWidth * 2 - 16));
    final double rowHeight =
        math.max(48, math.min(64, logoWidth * 1504 / 2808));
    final double artHeight = width * 450 / 1200;
    final double laceHeight = width * 100 / 1200;
    final double safeTop = media.padding.top + 4;
    final double minimumHeight = safeTop + rowHeight + 4 + laceHeight;
    // Wide screens crop only the empty upper cream area. The lace always spans
    // the real screen width and keeps the PNG's proportions.
    final double preferredHeight =
        math.min(artHeight, media.size.height < 500 ? 144 : 180);
    final double height = math.max(preferredHeight, minimumHeight);
    final double rowTop =
        safeTop + (height - laceHeight - 4 - safeTop - rowHeight) / 2;
    return _HeaderLayout(
      artHeight: artHeight,
      height: height,
      laceHeight: laceHeight,
      rowTop: rowTop,
      rowHeight: rowHeight,
      logoWidth: logoWidth,
    );
  }

  final double artHeight;
  final double height;
  final double laceHeight;
  final double rowTop;
  final double rowHeight;
  final double logoWidth;
}

/// Places the logo and live controls in one row above the transparent lace.
class GirlsCommonHeader extends StatelessWidget {
  const GirlsCommonHeader({
    this.leading,
    this.actions = const <Widget>[],
    super.key,
  });

  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final _HeaderLayout layout = _HeaderLayout.forWidth(
          media,
          constraints.maxWidth,
          hasLeading: leading != null,
          actionCount: actions.length,
        );
        return SizedBox(
          key: const Key('girls-common-header'),
          height: layout.height,
          width: double.infinity,
          child: ClipRect(
            child: Stack(
              children: <Widget>[
                // Extra notch clearance is plain cream, not a scaled-up image.
                if (layout.height > layout.artHeight)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: layout.height - layout.artHeight + 1,
                    child: const ColoredBox(color: _headerCream),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Image.asset(
                    _headerBackground,
                    key: const Key('girls-header-background'),
                    width: constraints.maxWidth,
                    height: layout.artHeight,
                    fit: BoxFit.fitWidth,
                    excludeFromSemantics: true,
                  ),
                ),
                Positioned(
                  top: layout.rowTop,
                  left: media.padding.left + 12,
                  right: media.padding.right + 12,
                  height: layout.rowHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Center(
                        child: Image.asset(
                          _girlsLogo,
                          key: const Key('girls-header-logo'),
                          width: layout.logoWidth,
                          height: layout.rowHeight,
                          fit: BoxFit.contain,
                          semanticLabel: 'みんアプ Girls',
                        ),
                      ),
                      if (leading != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _HeaderControlTray(
                            key: const Key('girls-header-leading-tray'),
                            child: leading!,
                          ),
                        ),
                      if (actions.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: _HeaderControlTray(
                            key: const Key('girls-header-actions-tray'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderControlTray extends StatelessWidget {
  const _HeaderControlTray({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .74),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x99E8C9D5)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x16745B9E),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GirlsBodyBackground extends StatelessWidget {
  const _GirlsBodyBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double imageWidth = math.min(constraints.maxWidth, 600);
            final double imageHeight = imageWidth * 1984 / 1200;
            return ClipRect(
              child: Stack(
                alignment: Alignment.topCenter,
                children: <Widget>[
                  OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: imageHeight,
                    maxHeight: imageHeight,
                    child: Image.asset(
                      _bodyBackground,
                      key: const Key('girls-body-background'),
                      width: imageWidth,
                      height: imageHeight,
                      fit: BoxFit.contain,
                    ),
                  ),
                  // The source is not a seamless tile. Fade to cream instead of
                  // repeating clouds or exposing a hard edge on tall screens.
                  if (constraints.maxHeight > imageHeight)
                    Positioned(
                      top: math.max(0, imageHeight - 96),
                      width: imageWidth,
                      height: 96,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x00FCF4E9),
                              _girlsCream,
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
