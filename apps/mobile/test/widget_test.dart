import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/session_app.dart';

class FakeApi implements MinAppApi {
  @override
  Future<AuthResult> login(String loginId, String password) async {
    expect(loginId, 'student-demo');
    expect(password, 'Password123');
    return const AuthenticatedSession(accessToken: 'token', expiresIn: 3600);
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
  Future<List<PublishedApp>> listPublishedApps(String accessToken) async {
    expect(accessToken, 'token');
    return <PublishedApp>[
      PublishedApp(
        appId: 'a' * 32,
        versionId: 'b' * 32,
        groupId: 'c' * 32,
        groupName: 'ねんね組',
        ownerLoginId: 'student-demo',
        title: 'ねんねぐみのじかんわり',
        reviewedAt: DateTime.utc(2026, 8, 17),
      ),
    ];
  }

  @override
  Future<LaunchGrant> createLaunch(String accessToken, PublishedApp app) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('student can login and see approved app catalog', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MinApp(api: FakeApi()));

    expect(find.text('みんアプ'), findsOneWidget);
    expect(find.text('先生からもらったIDでログイン'), findsOneWidget);
    expect(find.text('Phase 3'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-id')), 'student-demo');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Password123',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('みんなのアプリ'), findsOneWidget);
    expect(find.text('ねんねぐみのじかんわり'), findsOneWidget);
    expect(find.textContaining('ねんね組'), findsOneWidget);
  });
}
