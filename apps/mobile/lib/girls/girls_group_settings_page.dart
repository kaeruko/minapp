import 'package:flutter/material.dart';

import '../hosted_group_management_api.dart';
import 'api.dart';
import 'girls_app_core.dart' as core;
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8062A7);
const Color _pink = Color(0xFFE79AAF);
const Color _cream = Color(0xFFFFFAF0);
const String _patternAsset = 'assets/girls/cutouts/home_pattern.png';

class GirlsGroupSettingsPage extends StatefulWidget {
  const GirlsGroupSettingsPage({
    required this.api,
    required this.session,
    required this.group,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroup group;

  @override
  State<GirlsGroupSettingsPage> createState() => _GirlsGroupSettingsPageState();
}

class _GirlsGroupSettingsPageState extends State<GirlsGroupSettingsPage> {
  late final TextEditingController _nameController;
  late final HostedGroupManagementApi _managementApi;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _managementApi = HostedGroupManagementApi(baseUri: widget.api.baseUri);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _managementApi.close();
    super.dispose();
  }

  String? _validateName(String? rawValue) {
    final String value = rawValue ?? '';
    if (value.isEmpty) return 'グループ名を入力してね。';
    if (value != value.trim()) return '前後の空白を消してね。';
    if (value.length > maxHostedGroupNameLength) {
      return 'グループ名は$maxHostedGroupNameLength文字までだよ。';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final String name = _nameController.text;
    if (name == widget.group.name) {
      Navigator.of(context).pop<HostedGroup>(widget.group);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final HostedGroup updated = await _managementApi.renameGroup(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        name: name,
      );
      if (!mounted) return;
      Navigator.of(context).pop<HostedGroup>(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
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
          'グループ設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_patternAsset),
            fit: BoxFit.cover,
            opacity: .1,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFF0DFE8)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x159B6A79),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              CircleAvatar(
                                backgroundColor: Color(0xFFFFEDF3),
                                foregroundColor: _pink,
                                child: Icon(Icons.edit_rounded),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'グループ名',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('girls-group-settings-name'),
                            controller: _nameController,
                            enabled: !_saving,
                            maxLength: maxHostedGroupNameLength,
                            validator: _validateName,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                            decoration: const InputDecoration(
                              labelText: 'グループ名',
                              hintText: '例：わんわん',
                              prefixIcon: Icon(Icons.groups_rounded),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            key: const Key('girls-group-settings-save'),
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: _lavender,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              _saving ? '保存中…' : '変更を保存',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Container(
                      key: const Key('girls-group-settings-error'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB45769).withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFB45769),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB45769),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.lock_outline_rounded,
                        color: _lavender,
                        size: 19,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'グループ設定を変更できるのはオーナーだけです。今はグループ名の変更に対応しています。',
                          style: TextStyle(
                            color: Color(0xFF75645F),
                            fontSize: 12,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
