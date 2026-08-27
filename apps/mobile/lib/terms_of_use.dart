import 'package:flutter/material.dart';

const String minAppSupportEmail = 'mail@cloxs.jp';

const String minAppTermsSummary =
    'みんアプでは、不適切なコンテンツや嫌がらせ・いじめなどの迷惑行為を一切許容しません。';

const String minAppTermsBody = '''
みんアプ 利用規約 / Terms of Use

1. 不適切なコンテンツ・迷惑行為の禁止
みんアプでは、わいせつ・暴力・差別・脅迫・いじめ・嫌がらせ・個人情報の侵害その他の不適切なコンテンツ、および他の利用者への abusive behavior を一切許容しません（zero tolerance）。

2. 公開前の確認
クラスの作品は、先生の確認・承認を受けたものだけが公開されます。

3. 報告と対応
利用者は、不適切な作品をアプリ内から運営へ報告できます。運営は報告を24時間以内に確認し、規約に違反するコンテンツを削除または公開停止し、違反した利用者を利用停止またはクラスから除外します。

4. ユーザーのブロック
利用者は、迷惑行為を行う利用者をブロックできます。ブロックした利用者の作品は、その端末の一覧に表示されなくなります。

5. 連絡先
安全上の問題や規約に関するお問い合わせ: $minAppSupportEmail

ログインすることで、この利用規約に同意したものとします。
''';

Future<void> showMinAppTermsOfUse(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('利用規約 / Terms of Use'),
      content: const SingleChildScrollView(
        child: SelectableText(
          minAppTermsBody,
          style: TextStyle(height: 1.55),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          key: const Key('terms-close'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}
