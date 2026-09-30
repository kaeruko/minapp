import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _girlsCream = Color(0xFFFCF4E9);
const Color _headerCream = Color(0xFFFBF3E8);
const String _headerBackground =
    'assets/girls/backgrounds/girls_header_bg_top.png';
const String _bodyBackground = 'assets/girls/backgrounds/girls_body_bg.jpg';
const String _girlsLogo = 'assets/girls/generated/minapp_girls_logo.png';

/// Lets a route match the transparent lace to the top of its own background.
class GirlsPageRouteSettings extends RouteSettings {
  const GirlsPageRouteSettings({
    super.name,
    super.arguments,
    this.headerLaceBackgroundColor,
  });

  final Color? headerLaceBackgroundColor;
}

/// Marks pages that are already hosted inside the authenticated Girls chrome.
///
/// Root and detail pages may keep using [GirlsScaffold] directly. When they are
/// pushed inside the authenticated shell, [GirlsScaffold] renders only their
/// page title and body so the shared header/footer are never duplicated.
class GirlsScaffoldChromeScope extends InheritedWidget {
  const GirlsScaffoldChromeScope({
    required super.child,
    this.onHome,
    this.onSharedFooterHiddenChanged,
    super.key,
  });

  final VoidCallback? onHome;
  final ValueChanged<bool>? onSharedFooterHiddenChanged;

  static GirlsScaffoldChromeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        GirlsScaffoldChromeScope>();
  }

  static bool isEmbedded(BuildContext context) => maybeOf(context) != null;

  static VoidCallback? homeAction(BuildContext context) =>
      maybeOf(context)?.onHome;

  static ValueChanged<bool>? sharedFooterHiddenAction(BuildContext context) =>
      maybeOf(context)?.onSharedFooterHiddenChanged;

  @override
  bool updateShouldNotify(GirlsScaffoldChromeScope oldWidget) =>
      oldWidget.onHome != onHome ||
      oldWidget.onSharedFooterHiddenChanged != onSharedFooterHiddenChanged;
}

/// Keeps the supplied artwork stationary while each page scrolls its content.
class GirlsScaffold extends StatelessWidget {
  const GirlsScaffold({
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    required this.body,
    required this.bottomNavigationBar,
    this.pageBackgroundDecoration,
    this.headerLaceBackgroundColor,
    super.key,
  });

  final String? title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget body;
  final Widget bottomNavigationBar;
  final Decoration? pageBackgroundDecoration;
  final Color? headerLaceBackgroundColor;

  @override
  Widget build(BuildContext context) {
    if (GirlsScaffoldChromeScope.isEmbedded(context)) {
      return _GirlsEmbeddedPage(
        title: title,
        body: body,
        pageBackgroundDecoration: pageBackgroundDecoration,
      );
    }

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
                // The page starts behind the lace, above the logo row.
                Positioned(
                  top: header.laceTop,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: const _GirlsBodyBackground(),
                ),
                // Continue custom page colors behind the scallops and logo.
                // Otherwise keep the shared artwork continuous below the lace.
                Positioned(
                  top: header.laceTop,
                  left: 0,
                  right: 0,
                  height: header.height - header.laceTop,
                  child: ColoredBox(
                    key: const Key('girls-header-lace-underlay'),
                    color: headerLaceBackgroundColor ?? Colors.transparent,
                  ),
                ),
                Column(
                  children: <Widget>[
                    GirlsCommonHeader(leading: leading, actions: actions),
                    Expanded(
                      child: _GirlsPageSurface(
                        title: title,
                        body: body,
                        decoration: pageBackgroundDecoration,
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

class _GirlsEmbeddedPage extends StatelessWidget {
  const _GirlsEmbeddedPage({
    required this.title,
    required this.body,
    required this.pageBackgroundDecoration,
  });

  final String? title;
  final Widget body;
  final Decoration? pageBackgroundDecoration;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _GirlsPageSurface(
        title: title,
        body: body,
        decoration: pageBackgroundDecoration,
      ),
    );
  }
}

class _GirlsPageSurface extends StatelessWidget {
  const _GirlsPageSurface({
    required this.title,
    required this.body,
    required this.decoration,
  });

  final String? title;
  final Widget body;
  final Decoration? decoration;

  @override
  Widget build(BuildContext context) {
    final Widget content = _GirlsPageContent(title: title, body: body);
    final Decoration? currentDecoration = decoration;
    if (currentDecoration == null) return content;
    return DecoratedBox(
      key: const Key('girls-page-background'),
      decoration: currentDecoration,
      child: content,
    );
  }
}

class _GirlsPageContent extends StatelessWidget {
  const _GirlsPageContent({required this.title, required this.body});

  final String? title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (title != null) GirlsPageTitle(title: title!),
        Expanded(
          child: ClipRect(
            child: SafeArea(
              top: false,
              child: body,
            ),
          ),
        ),
      ],
    );
  }
}

/// A page name centered immediately beneath the shared logo.
class GirlsPageTitle extends StatelessWidget {
  const GirlsPageTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Center(
          child: Semantics(
            header: true,
            child: Text(
              title,
              key: const Key('girls-page-title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF745B9E),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
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
    required this.laceTop,
    required this.laceBottom,
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
    // Let the decorative lace meet the status bar, while keeping controls
    // below both the safe inset and the scallops.
    final double laceTop = math.max(0, media.padding.top - 10);
    final double laceBottom = math.max(media.padding.top, laceTop + laceHeight);
    final double rowTop = laceBottom + 2;
    final double height = rowTop + rowHeight + 2;
    return _HeaderLayout(
      artHeight: artHeight,
      height: height,
      laceTop: laceTop,
      laceBottom: laceBottom,
      rowTop: rowTop,
      rowHeight: rowHeight,
      logoWidth: logoWidth,
    );
  }

  final double artHeight;
  final double height;
  final double laceTop;
  final double laceBottom;
  final double rowTop;
  final double rowHeight;
  final double logoWidth;
}

/// Places compact lace at the top, then the logo and live controls beneath it.
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
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: layout.laceBottom,
                  child: ClipRect(
                    key: const Key('girls-header-lace'),
                    child: Stack(
                      children: <Widget>[
                        if (layout.laceBottom > layout.artHeight)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: layout.laceBottom - layout.artHeight + 1,
                            child: const ColoredBox(color: _headerCream),
                          ),
                        // Only crop the unused cream above the original lace.
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
                      ],
                    ),
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
                fit: StackFit.expand,
                alignment: Alignment.topCenter,
                children: <Widget>[
                  Positioned(
                    top: 0,
                    left: (constraints.maxWidth - imageWidth) / 2,
                    width: imageWidth,
                    height: imageHeight,
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
