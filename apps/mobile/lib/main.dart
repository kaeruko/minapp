import 'package:flutter/material.dart';

void main() {
  runApp(const MinApp());
}

class MinApp extends StatelessWidget {
  const MinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3767C8)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const List<_DemoApp> _demoApps = <_DemoApp>[
    _DemoApp(
      title: '時間割',
      author: 'shiba-4821',
      icon: Icons.calendar_month_outlined,
    ),
    _DemoApp(
      title: '文化祭マップ',
      author: 'neko-7312',
      icon: Icons.map_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: _PhaseBadge()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Text(
              'みんなのアプリ',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '同じグループで承認されたアプリが、ここに並びます。',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            for (final _DemoApp app in _demoApps) ...<Widget>[
              _AppCard(app: app),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            const _SecurityNote(),
          ],
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app});

  final _DemoApp app;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: CircleAvatar(child: Icon(app.icon)),
        title: Text(app.title),
        subtitle: Text('作者: ${app.author}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: null,
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text('Phase 0'),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.shield_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Phase 0では画面の土台だけを作ります。認証やWebアプリ起動は、サーバ側の認可を実装してから有効にします。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoApp {
  const _DemoApp({
    required this.title,
    required this.author,
    required this.icon,
  });

  final String title;
  final String author;
  final IconData icon;
}
