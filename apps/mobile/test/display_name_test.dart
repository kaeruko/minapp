import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';

void main() {
  Map<String, Object?> appJson({String? displayName}) => <String, Object?>{
        'app_id': 'a' * 32,
        'version_id': 'b' * 32,
        'group_id': 'c' * 32,
        'group_name': '火曜クラス',
        'owner_login_id': 'student-demo',
        if (displayName != null) 'owner_display_name': displayName,
        'title': '時間割',
        'status': 'approved',
        'reviewed_at': '2026-08-18T00:00:00Z',
      };

  test('PublishedApp prefers owner display name when present', () {
    final PublishedApp app = PublishedApp.fromJson(appJson(displayName: '山田 太郎'));
    expect(app.ownerLoginId, '山田 太郎');
  });

  test('PublishedApp falls back to login id without display name', () {
    final PublishedApp app = PublishedApp.fromJson(appJson());
    expect(app.ownerLoginId, 'student-demo');
  });

  test('PublishedApp rejects malformed owner display name', () {
    expect(
      () => PublishedApp.fromJson(appJson(displayName: ' 山田')),
      throwsFormatException,
    );
  });
}
