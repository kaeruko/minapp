import 'package:flutter/material.dart';

import 'directory.dart';
import 'tenant_store.dart';
import 'ui.dart';

class ClassroomSetupPage extends StatefulWidget {
  const ClassroomSetupPage({
    required this.directory,
    required this.tenantStore,
    required this.onConfigured,
    super.key,
  });

  final MinAppDirectory directory;
  final TenantStore tenantStore;
  final ValueChanged<ConfiguredTenant> onConfigured;

  @override
  State<ClassroomSetupPage> createState() => _ClassroomSetupPageState();
}

class _ClassroomSetupPageState extends State<ClassroomSetupPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _configure() async {
    final String classroomCode = _codeController.text;
    if (classroomCode.isEmpty) {
      setState(() => _error = '教室コードを入力してください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final TenantDescriptor descriptor = await widget.directory.resolveClassroom(
        classroomCode,
      );
      await widget.directory.verifyTenantEndpoint(descriptor);
      final ConfiguredTenant configured = ConfiguredTenant.fromVerifiedDescriptor(
        descriptor,
        verifiedAt: DateTime.now().toUtc(),
      );
      await widget.tenantStore.save(configured);
      if (mounted) widget.onConfigured(configured);
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: PhaseBadge()),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        Icons.school_outlined,
                        size: 44,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '教室を設定',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '先生からもらった教室コードを入力してください。教室を確認してからログイン画面を開きます。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        key: const Key('classroom-code'),
                        controller: _codeController,
                        enabled: !_busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 64,
                        decoration: const InputDecoration(
                          labelText: '教室コード',
                          hintText: 'XXXX-XXXX-XXXX',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          if (!_busy) _configure();
                        },
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        key: const Key('classroom-submit'),
                        onPressed: _busy ? null : _configure,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: const Text('この教室を使う'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
