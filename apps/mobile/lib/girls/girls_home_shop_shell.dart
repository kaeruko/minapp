import 'package:flutter/material.dart';

import '../api.dart';
import 'girls_home_page.dart';
import 'girls_shop_page.dart';
import 'hosted_girls_api.dart';

const Color _shopPink = Color(0xFFE987A8);

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
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GirlsHomePage(
            api: api,
            session: session,
            onLogout: onLogout,
          ),
        ),
        Positioned(
          right: 18,
          bottom: 88,
          child: SafeArea(
            top: false,
            left: false,
            child: FloatingActionButton.extended(
              heroTag: 'girls-shop-entry',
              key: const Key('girls-shop-entry'),
              backgroundColor: _shopPink,
              foregroundColor: Colors.white,
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => GirlsShopPage(
                      api: api,
                      session: session,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.storefront_rounded),
              label: const Text(
                'ショップ♡',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
