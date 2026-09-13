import 'package:flutter/material.dart';

import '../api.dart';
import 'girls_footer_nav.dart';
import 'girls_home_page.dart';
import 'girls_shop_page.dart';
import 'hosted_girls_api.dart';

class GirlsHomeShopShell extends StatelessWidget {
  const GirlsHomeShopShell({
    required this.api,
    required this.session,
    required this.onLogout,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return GirlsFooterNavigationScope(
      onOpenShop: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => GirlsShopPage(
              api: api,
              session: session,
            ),
          ),
        );
      },
      child: GirlsHomePage(
        api: api,
        session: session,
        onLogout: onLogout,
      ),
    );
  }
}
