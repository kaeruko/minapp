import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const String _girlsFooterAsset = 'assets/girls/girls_footer_base.svg';
const Color _footerInactive = Color(0xFFFCF5E9);
const Color _footerActive = Color(0xFFF9DDE8);
const Color _footerText = Color(0xFF6F514B);
const Color _footerSelectedText = Color(0xFF745B9E);

/// Footer destinations are kept separate from page implementation so each Girls
/// page can own its selected state without baking state into the SVG asset.
enum GirlsFooterTab {
  home('ホーム', 'assets/girls/cutouts/home_tab.png'),
  groups('グループ', 'assets/girls/cutouts/groups_tab.png'),
  diary('日記', 'assets/girls/cutouts/diary_tab.png'),
  games('ゲーム', 'assets/girls/cutouts/games_tab.png'),
  more('その他', 'assets/girls/cutouts/more_tab.png');

  const GirlsFooterTab(this.label, this.assetName);

  final String label;
  final String assetName;
}

/// Maps the five marker fills in girls_footer_base.svg to live Flutter colors.
///
/// The SVG owns the exact five-hill silhouette and outline. Flutter owns which
/// hill is active. This avoids drawing a translucent selection layer over a
/// fixed image and keeps the active fill as the actual SVG fill color.
class GirlsFooterColorMapper extends ColorMapper {
  const GirlsFooterColorMapper(this.selectedTab);

  final GirlsFooterTab selectedTab;

  static const List<Color> _markerColors = <Color>[
    Color(0xFF010101),
    Color(0xFF020202),
    Color(0xFF030303),
    Color(0xFF040404),
    Color(0xFF050505),
  ];

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (attributeName != 'fill') return color;

    final int index = _markerColors.indexOf(color);
    if (index == -1) return color;
    return index == selectedTab.index ? _footerActive : _footerInactive;
  }
}

class GirlsFooterNav extends StatelessWidget {
  const GirlsFooterNav({
    required this.selectedTab,
    this.onSelected,
    this.enabledTabs = const <GirlsFooterTab>{
      GirlsFooterTab.home,
      GirlsFooterTab.groups,
      GirlsFooterTab.diary,
      GirlsFooterTab.games,
      GirlsFooterTab.more,
    },
    super.key,
  });

  final GirlsFooterTab selectedTab;
  final ValueChanged<GirlsFooterTab>? onSelected;
  final Set<GirlsFooterTab> enabledTabs;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: 82,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SvgPicture(
              SvgAssetLoader(
                _girlsFooterAsset,
                colorMapper: GirlsFooterColorMapper(selectedTab),
              ),
              fit: BoxFit.fill,
              alignment: Alignment.bottomCenter,
              semanticsLabel: 'みんアプ Girls フッターメニュー',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 4, 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: GirlsFooterTab.values
                    .map(
                      (GirlsFooterTab tab) => Expanded(
                        child: _GirlsFooterItem(
                          tab: tab,
                          selected: tab == selectedTab,
                          enabled: enabledTabs.contains(tab),
                          onTap: onSelected == null
                              ? null
                              : () => onSelected!(tab),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GirlsFooterItem extends StatelessWidget {
  const _GirlsFooterItem({
    required this.tab,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final GirlsFooterTab tab;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? _footerSelectedText : _footerText;
    final VoidCallback? effectiveOnTap = enabled ? onTap : null;

    return Semantics(
      key: ValueKey<String>('girls-footer-${tab.name}'),
      button: true,
      selected: selected,
      enabled: enabled,
      label: tab.label,
      child: InkResponse(
        onTap: effectiveOnTap,
        radius: 30,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: AnimatedScale(
          scale: selected ? 1.04 : 1,
          duration: const Duration(milliseconds: 160),
          child: Opacity(
            opacity: enabled ? 1 : .68,
            child: Image.asset(
              tab.assetName,
              height: 69,
              fit: BoxFit.contain,
              semanticLabel: tab.label,
              color: enabled ? null : foreground.withValues(alpha: .72),
              colorBlendMode: enabled ? null : BlendMode.modulate,
            ),
          ),
        ),
      ),
    );
  }
}
