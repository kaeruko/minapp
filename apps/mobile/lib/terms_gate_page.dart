import 'package:flutter/material.dart';

import 'terms_of_use.dart';

class TermsGatePage extends StatefulWidget {
  const TermsGatePage({required this.childBuilder, super.key});

  final WidgetBuilder childBuilder;

  @override
  State<TermsGatePage> createState() => _TermsGatePageState();
}

class _TermsGatePageState extends State<TermsGatePage> {
  bool _accepted = false;
  bool _continueToLogin = false;

  @override
  Widget build(BuildContext context) {
    if (_continueToLogin) {
      return widget.childBuilder(context);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('みんアプ'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 48,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '利用規約への同意',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        minAppTermsSummary,
                        style: TextStyle(
                          color: Color(0xFF475569),
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const Key('terms-open'),
                        onPressed: () => showMinAppTermsOfUse(context),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('利用規約 / Terms of Use を読む'),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        key: const Key('terms-accept'),
                        value: _accepted,
                        onChanged: (bool? value) {
                          if (value == null) {
                            throw StateError('Terms checkbox returned a null value.');
                          }
                          setState(() => _accepted = value);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '利用規約に同意します',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          '不適切なコンテンツや迷惑行為を一切許容しない方針を含みます。',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          key: const Key('terms-continue'),
                          onPressed: _accepted
                              ? () => setState(() => _continueToLogin = true)
                              : null,
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('同意してログインへ'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '安全上の問題: $minAppSupportEmail',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
