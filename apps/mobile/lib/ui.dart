import 'package:flutter/material.dart';

import 'api.dart';
import 'classroom_join.dart';
import 'directory.dart';

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
          child: Text('Phase 6'),
        ),
      ),
    );
  }
}

String messageFor(Object error) {
  if (error is InvalidClassroomJoinInput) {
    return error.message;
  }
  if (error is AppUpdateRequiredException) {
    return 'この教室の環境には新しいみんアプが必要です。アプリを更新してください。';
  }
  if (error is DirectoryConnectionException) {
    return '教室案内サービスに接続できません。通信環境を確認して、もう一度お試しください。';
  }
  if (error is TenantConnectionException) {
    return '教室のサーバーを確認できません。しばらくしてから、もう一度お試しください。';
  }
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_classroom_code':
      case 'classroom_not_found':
        return '教室コードが見つかりません。先生からもらったコードを確認してください。';
      case 'classroom_inactive':
        return 'この教室は現在利用できません。先生または管理者に確認してください。';
      case 'incompatible_tenant_config':
        return 'この教室の環境には新しいみんアプが必要です。アプリを更新してください。';
      case 'directory_unavailable':
        return '教室案内サービスに接続できません。しばらくしてから、もう一度お試しください。';
      case 'rate_limited':
        return '確認回数が多すぎます。少し待ってから、もう一度お試しください。';
      default:
        return error.message;
    }
  }
  if (error is FormatException || error is ArgumentError) {
    return '教室またはサーバーの設定形式が不正です。';
  }
  return '通信または端末保存に失敗しました: $error';
}
