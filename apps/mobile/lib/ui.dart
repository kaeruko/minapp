import 'package:flutter/material.dart';

import 'api.dart';

class PhaseBadge extends StatelessWidget {
  const PhaseBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('Phase 3'),
        ),
      ),
    );
  }
}

String messageFor(Object error) {
  if (error is ApiException) {
    return error.message;
  }
  if (error is FormatException) {
    return 'サーバーの応答形式が不正です。';
  }
  return '通信に失敗しました: $error';
}
