import 'package:flutter/material.dart';

import 'kobo_home_page.dart';
import 'kobo_theme.dart';

class KoboApp extends StatelessWidget {
  const KoboApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ工房',
      debugShowCheckedModeBanner: false,
      theme: KoboTheme.light(),
      home: const KoboHomePage(),
    );
  }
}
