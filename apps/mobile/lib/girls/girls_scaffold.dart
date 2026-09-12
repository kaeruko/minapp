import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _girlsCream = Color(0xFFFCF4E9);
const String _headerBackground = 'assets/girls/backgrounds/girls_header_bg.jpg';
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
        body: Column(
          children: <Widget>[
            GirlsCommonHeader(
              title: title,
              leading: leading,
              actions: actions,
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const Positioned.fill(child: _GirlsBodyBackground()),
                  Column(
                    children: <Widget>[
                      Expanded(
                        child: ClipRect(
                          child: SafeArea(
                            top: false,
                            bottom: false,
                            child: body,
                          ),
                        ),
                      ),
                      SafeArea(top: false, child: bottomNavigationBar),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lace, logo, page name and actions share one header, including the inset.
class GirlsCommonHeader extends StatelessWidget {
  const GirlsCommonHeader({
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    super.key,
  });

  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final bool compact = media.size.height < 500;
    final double logoHeight = compact ? 40 : 50;
    final double controlsHeight = compact ? 42 : 46;
    final TextStyle titleStyle = TextStyle(
      fontSize: compact ? 23 : 27,
      height: 1.15,
      fontWeight: FontWeight.w800,
      letterSpacing: 1,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double contentWidth = math.max(
          1,
          constraints.maxWidth - media.padding.horizontal - 24,
        );
        final TextPainter titlePainter = TextPainter(
          text: TextSpan(text: title ?? '', style: titleStyle),
          textDirection: Directionality.of(context),
          textScaler: media.textScaler,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: contentWidth);
        final double titleHeight = title == null ? 0 : titlePainter.height;
        titlePainter.dispose();

        // Keep the controls in their own visible row instead of floating beside
        // the logo. The header art can grow when a notch or large text needs it.
        final double naturalHeight =
            math.min(constraints.maxWidth, 480) * 630 / 1200;
        final double top = media.padding.top + (compact ? 2 : 4);
        final double bottom = compact ? 16 : 20;
        final double contentHeight = controlsHeight +
            5 +
            logoHeight +
            (title == null ? 0 : 3 + titleHeight);
        final double height = math.max(
          naturalHeight,
          top + contentHeight + bottom,
        );
        final double logoWidth = math.min(
          132,
          math.max(72, contentWidth * .42),
        );

        return SizedBox(
          key: const Key('girls-common-header'),
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: height * 1200 / 630,
                  maxWidth: height * 1200 / 630,
                  child: Image.asset(
                    _headerBackground,
                    height: height,
                    width: height * 1200 / 630,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  media.padding.left + 12,
                  top,
                  media.padding.right + 12,
                  bottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: controlsHeight,
                      child: Row(
                        children: <Widget>[
                          if (leading != null)
                            _HeaderControlTray(
                              key: const Key('girls-header-leading-tray'),
                              child: leading!,
                            )
                          else
                            const SizedBox(width: 1),
                          const Spacer(),
                          if (actions.isNotEmpty)
                            _HeaderControlTray(
                              key: const Key('girls-header-actions-tray'),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: actions,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Image.asset(
                      _girlsLogo,
                      width: logoWidth,
                      height: logoHeight,
                      fit: BoxFit.contain,
                      semanticLabel: 'みんアプ Girls',
                    ),
                    if (title != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Semantics(
                        header: true,
                        label: title,
                        child: ExcludeSemantics(
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              Text(
                                title!,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle.copyWith(
                                  foreground: Paint()
                                    ..style = PaintingStyle.stroke
                                    ..strokeWidth = 5
                                    ..color =
                                        Colors.white.withValues(alpha: .96),
                                ),
                              ),
                              Text(
                                title!,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle.copyWith(
                                  color: const Color(0xFFB4A0BB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
