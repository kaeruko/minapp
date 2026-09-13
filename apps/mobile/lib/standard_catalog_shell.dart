import 'package:flutter/material.dart';

import 'api.dart';
import 'catalog_page.dart';
import 'shop_api.dart';
import 'shop_page.dart';
import 'ugc_safety.dart';

class StandardCatalogShell extends StatefulWidget {
  const StandardCatalogShell({
    required this.api,
    required this.apiBaseUri,
    required this.session,
    required this.classroomName,
    required this.creatorSafetyStore,
    required this.onChangeClassroom,
    required this.onLogout,
    this.creatorPortalBaseUri,
    super.key,
  });

  final MinAppApi api;
  final Uri apiBaseUri;
  final AuthenticatedSession session;
  final String classroomName;
  final Uri? creatorPortalBaseUri;
  final CreatorSafetyStore creatorSafetyStore;
  final Future<void> Function() onChangeClassroom;
  final VoidCallback onLogout;

  @override
  State<StandardCatalogShell> createState() => _StandardCatalogShellState();
}

class _StandardCatalogShellState extends State<StandardCatalogShell> {
  late final ShopApiClient _shopApi;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _shopApi = ShopApiClient(baseUri: widget.apiBaseUri);
  }

  @override
  void didUpdateWidget(covariant StandardCatalogShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUri != widget.apiBaseUri) {
      throw StateError(
        'StandardCatalogShell does not support replacing apiBaseUri at runtime.',
      );
    }
  }

  @override
  void dispose() {
    _shopApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: <Widget>[
          CatalogPage(
            api: widget.api,
            session: widget.session,
            classroomName: widget.classroomName,
            creatorPortalBaseUri: widget.creatorPortalBaseUri,
            creatorSafetyStore: widget.creatorSafetyStore,
            onChangeClassroom: widget.onChangeClassroom,
            onLogout: widget.onLogout,
          ),
          ShopPage(
            api: _shopApi,
            session: widget.session,
            creatorSafetyStore: widget.creatorSafetyStore,
            onLogout: widget.onLogout,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          if (index < 0 || index > 1) {
            throw RangeError.range(index, 0, 1, 'index');
          }
          setState(() => _selectedIndex = index);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'クラス',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'ショップ',
          ),
        ],
      ),
    );
  }
}
