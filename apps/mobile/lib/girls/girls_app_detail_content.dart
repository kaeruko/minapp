import 'package:flutter/material.dart';

import 'girls_app_management_api.dart';

const _ink = Color(0xFF604943);
const _rose = Color(0xFFB98295);

/// Presentation only: all publication and deletion still use the detail page's
/// authenticated actions and confirmation dialog.
class GirlsAppDetailContent extends StatelessWidget {
  const GirlsAppDetailContent({
    required this.detail,
    required this.actions,
    required this.busy,
    required this.onVisibilityChanged,
    required this.onPublish,
    required this.onDownload,
    required this.onDelete,
    super.key,
  });

  final ManagedGirlsAppDetail detail;
  final Widget actions;
  final bool busy;
  final VoidCallback? onVisibilityChanged;
  final VoidCallback? onPublish;
  final VoidCallback? onDownload;
  final VoidCallback onDelete;

  static String _date(DateTime? value) {
    if (value == null) return '—';
    final date = value.toLocal();
    return '${date.year}年${date.month}月${date.day}日';
  }

  static Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 10),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _ink, fontSize: 21, fontWeight: FontWeight.w900)),
      );

  static Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE4C8D2), width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x16A66C83), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final app = detail.summary;
    final published = app.app.isPublished && !app.isHidden;
    int? publishedRevision;
    for (final version in detail.publishedHistory) {
      if (version.version == app.app.publishedVersion) {
        publishedRevision = version.sourceRevision;
      }
    }
    final hasUpdate = app.app.editable &&
        app.app.isPublished &&
        app.sourceRevision != null &&
        app.sourceRevision != publishedRevision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('アプリ名'),
        _card(Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: _rose, size: 22),
          const SizedBox(width: 10),
          Expanded(
              child: Text(app.app.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _ink, fontSize: 22, fontWeight: FontWeight.w900))),
          if (app.app.editable)
            IconButton(
              key: const Key('girls-app-download-source'),
              tooltip: 'ZIPをダウンロード',
              onPressed: busy ? null : onDownload,
              icon: const Text('📦', style: TextStyle(fontSize: 20)),
            ),
        ])),
        _heading('アプリ情報'),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
                child: Text('公開・非公開',
                    style: TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800))),
            DecoratedBox(
              decoration: BoxDecoration(
                color: published
                    ? const Color(0xFF76B986)
                    : const Color(0xFFE8DAE2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(published ? '公開中' : '非公開',
                    style: TextStyle(
                        color: published ? Colors.white : _ink,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
                label: 'アプリを公開',
                child: Switch(
                  key: const Key('girls-app-visibility'),
                  value: published,
                  activeTrackColor: _rose,
                  onChanged: busy || onVisibilityChanged == null
                      ? null
                      : (_) => onVisibilityChanged!(),
                )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Expanded(
                child: Text('遊ばれた回数',
                    style: TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800))),
            Flexible(
                child: Text('${app.stats.totalPlays}回',
                    style: const TextStyle(
                        color: _ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 5),
          Text(
              '遊んだ人数 ${app.stats.uniqueUsers}人　・　今月 ${app.stats.monthlyPlays}回',
              style: const TextStyle(color: _rose, fontSize: 12)),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: Color(0xFFF0DFE5))),
          Text('公開日：${_date(app.publishedAt)}',
              key: const Key('girls-app-published-date'),
              style: const TextStyle(color: _ink, fontSize: 13)),
          const SizedBox(height: 4),
          Text('最終更新日：${_date(app.sourceUpdatedAt)}',
              key: const Key('girls-app-updated-date'),
              style: const TextStyle(color: _ink, fontSize: 13)),
          if (hasUpdate) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('girls-app-publish-update'),
              onPressed: busy ? null : onPublish,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('変更を公開'),
            ),
          ],
        ])),
        _heading('プレビュー'),
        actions,
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('girls-app-delete'),
          onPressed: busy ? null : onDelete,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD94D49),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            textStyle:
                const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('このアプリを削除'),
        ),
      ],
    );
  }
}
