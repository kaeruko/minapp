import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String girlsHowToUrl = 'https://cloxs.jp/minapp/girls/howto.html';
const String girlsTechnicalGuideUrl = 'https://cloxs.jp/minapp/ai/index.html';

Future<void> showGirlsCodeHelpDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      key: const Key('girls-source-editor-help-dialog'),
      title: const Text('コード編集で迷ったら？'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'わからないところは、AIに相談しながら進めよう。',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 12),
          Text(
            '「背景をピンクにしたい」「ボタンを増やしたい」みたいに、'
            'やりたいことをそのまま伝えてみよう。',
          ),
          SizedBox(height: 12),
          Text(
            'みんアプGirlsの使い方ガイドには、AIにアレンジをお願いする流れも載っているよ。',
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('girls-source-editor-help-close'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('閉じる'),
        ),
        FilledButton.icon(
          key: const Key('girls-source-editor-howto'),
          onPressed: () async {
            final Uri uri = Uri.parse(girlsHowToUrl);
            final bool opened = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (!opened) {
              throw StateError('使い方ガイドを開けませんでした: $uri');
            }
          },
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('使い方ガイドを見る'),
        ),
      ],
    ),
  );
}
