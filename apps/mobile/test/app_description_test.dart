import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/app_detail_page.dart';

class _UnusedApi implements MinAppApi {
  @override
  Future<AuthResult> login(String loginId, String password) {
    throw UnimplementedError();
  }

  @override
  Future<AuthenticatedSession> completeNewPassword({
    required String loginId,
    required String newPassword,
    required String session,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<PublishedApp>> listPublishedApps(String accessToken) {
    throw UnimplementedError();
  }

  @override
  Future<LaunchGrant> createLaunch(String accessToken, PublishedApp app) {
    throw UnimplementedError();
  }

  @override
  Future<void> reportApp(
    String accessToken,
    PublishedApp app,
    String reason,
  ) {
    throw UnimplementedError();
  }
}

Map<String, Object?> _publishedJson({Object? description}) => <String, Object?>{
      'app_id': 'a' * 32,
      'version_id': 'b' * 32,
      'group_id': 'c' * 32,
      'group_name': 'ねんね組',
      'owner_user_id': 'd' * 32,
      'owner_login_id': 'student-demo',
      'title': '時間割アプリ',
      'status': 'approved',
      'reviewed_at': '2026-08-18T00:00:00Z',
      if (description != null) 'description': description,
    };

void main() {
  test('PublishedApp parses an optional description', () {
    final PublishedApp app = PublishedApp.fromJson(
      _publishedJson(description: '今日の時間割を確認できます。'),
    );
    expect(app.description, '今日の時間割を確認できます。');
  });

  test('PublishedApp keeps legacy apps compatible when description is absent', () {
    final PublishedApp app = PublishedApp.fromJson(_publishedJson());
    expect(app.description, isNull);
  });

  test('PublishedApp rejects an empty description when the field is present', () {
    expect(
      () => PublishedApp.fromJson(_publishedJson(description: '')),
      throwsFormatException,
    );
  });

  testWidgets('detail page shows the author description and safety actions', (
    WidgetTester tester,
  ) async {
    final PublishedApp app = PublishedApp.fromJson(
      _publishedJson(description: '毎日の予定をすぐ確認できるアプリです。'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppDetailPage(
          api: _UnusedApi(),
          session: const AuthenticatedSession(
            accessToken: 'token',
            expiresIn: 3600,
          ),
          app: app,
          onHideCreator: (_) async {},
          onLogout: () {},
        ),
      ),
    );

    expect(find.text('アプリの説明'), findsOneWidget);
    expect(find.text('毎日の予定をすぐ確認できるアプリです。'), findsOneWidget);
    expect(find.byKey(const Key('app-detail-report')), findsOneWidget);
    expect(find.byKey(const Key('app-detail-hide-creator')), findsOneWidget);
    expect(find.text('このユーザーをブロック'), findsOneWidget);
  });
}
