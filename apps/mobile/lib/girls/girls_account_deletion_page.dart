import 'package:flutter/material.dart';

import '../hosted_group_management_api.dart';
import 'api.dart';
import 'girls_current_group_store.dart';
import 'girls_errors.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _danger = Color(0xFFB5465C);
const Color _cream = Color(0xFFFFFAF0);

class GirlsAccountDeletionPage extends StatefulWidget {
  const GirlsAccountDeletionPage({
    required this.api,
    required this.session,
    required this.currentGroupStore,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final GirlsCurrentGroupStore currentGroupStore;

  @override
  State<GirlsAccountDeletionPage> createState() =>
      _GirlsAccountDeletionPageState();
}

class _GirlsAccountDeletionPageState extends State<GirlsAccountDeletionPage> {
  bool _deleting = false;
  String? _error;

  Future<void> _confirmAndDelete() async {
    if (_deleting) return;

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            key: const Key('girls-account-delete-confirm-dialog'),
            title: const Text('アカウントを削除しますか？'),
            content: const Text(
              'この操作は取り消せません。\n\n'
              'ログイン情報とアカウントは削除されます。'
              'あなたがオーナーのグループと、そのグループ内のアプリも削除され、'
              '参加している人はそのグループを利用できなくなります。',
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('girls-account-delete-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                key: const Key('girls-account-delete-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: _danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('削除する'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });

    final HostedGroupManagementApi groupApi = HostedGroupManagementApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    try {
      final String accessToken = widget.session.accessToken;
      final List<HostedGroup> groups = await widget.api.listGroups(accessToken);

      // Clear the local group selection before any remote destructive action.
      // If local storage cannot be updated, fail before deleting server data.
      await widget.currentGroupStore.clear();

      for (final HostedGroup group in groups) {
        if (!group.isOwner) continue;
        await groupApi.deleteGroup(
          accessToken: accessToken,
          groupId: group.groupId,
        );
      }

      await widget.api.deleteAccount(accessToken);
      if (!mounted) return;
      Navigator.of(context).pop<bool>(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      groupApi.close();
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF4F7),
        foregroundColor: _ink,
        centerTitle: true,
        title: const Text(
          'アカウント削除',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              children: <Widget>[
                const Icon(
                  Icons.person_remove_rounded,
                  color: _danger,
                  size: 58,
                ),
                const SizedBox(height: 18),
                const Text(
                  'アカウントを完全に削除',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFF0D8DE)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '削除すると',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '・このアカウントではログインできなくなります\n'
                        '・アカウント情報は削除されます\n'
                        '・オーナーになっているグループと、そのグループ内のアプリも削除されます\n'
                        '・この操作は取り消せません',
                        style: TextStyle(
                          color: Color(0xFF75645F),
                          height: 1.65,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    key: const Key('girls-account-delete-error'),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE8EC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('girls-account-delete-start'),
                  onPressed: _deleting ? null : _confirmAndDelete,
                  style: FilledButton.styleFrom(
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: _deleting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.delete_forever_rounded),
                  label: Text(
                    _deleting ? '削除しています…' : 'アカウントを削除する',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _deleting ? null : () => Navigator.of(context).pop(),
                  child: const Text('削除せず戻る'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
