from __future__ import annotations

from pathlib import Path

PATH = Path("apps/mobile/lib/girls/girls_groups_dashboard_page.dart")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    text = PATH.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "import 'girls_builtin_install_api.dart';\nimport 'girls_current_group_store.dart';\nimport 'girls_scaffold.dart';",
        "import 'girls_builtin_install_api.dart';\nimport 'girls_current_group_store.dart';\nimport 'girls_group_settings_page.dart';\nimport 'girls_scaffold.dart';",
        "group settings import",
    )

    text = replace_once(
        text,
        """  Future<void> _openGroup(HostedGroup group) async {\n    await Navigator.of(context).push<void>(\n      MaterialPageRoute<void>(\n        builder: (BuildContext context) => core.GirlsGroupHomePage(\n          api: widget.api,\n          session: widget.session,\n          group: group,\n        ),\n      ),\n    );\n    if (mounted) await _reload();\n  }\n\n  Future<void> _joinGroup() async {""",
        """  Future<void> _openGroup(HostedGroup group) async {\n    await Navigator.of(context).push<void>(\n      MaterialPageRoute<void>(\n        builder: (BuildContext context) => core.GirlsGroupHomePage(\n          api: widget.api,\n          session: widget.session,\n          group: group,\n        ),\n      ),\n    );\n    if (mounted) await _reload();\n  }\n\n  Future<void> _openGroupSettings(HostedGroup group) async {\n    final HostedGroup? updated = await Navigator.of(context).push<HostedGroup>(\n      MaterialPageRoute<HostedGroup>(\n        builder: (BuildContext context) => GirlsGroupSettingsPage(\n          api: widget.api,\n          session: widget.session,\n          group: group,\n        ),\n      ),\n    );\n    if (updated == null || !mounted) return;\n\n    final bool renamed = updated.name != group.name;\n    setState(() => _currentGroup = updated);\n    widget.onCurrentGroupChanged(updated);\n    await _reload();\n    if (!mounted || !renamed) return;\n    ScaffoldMessenger.of(context).showSnackBar(\n      SnackBar(content: Text('グループ名を「${updated.name}」に変更したよ。')),\n    );\n  }\n\n  Future<void> _joinGroup() async {""",
        "open group settings method",
    )

    text = replace_once(
        text,
        """                loading: _busy,\n                onOpen: () => _openGroup(current),\n              ),""",
        """                loading: _busy,\n                onOpen: () => _openGroup(current),\n                onSettings:\n                    current.isOwner ? () => _openGroupSettings(current) : null,\n              ),""",
        "current group settings callback",
    )

    text = replace_once(
        text,
        """    required this.latestApps,\n    required this.loading,\n    required this.onOpen,\n  });\n\n  final HostedGroup group;\n  final List<HostedMember>? members;\n  final List<HostedGroupApp>? latestApps;\n  final bool loading;\n  final VoidCallback onOpen;""",
        """    required this.latestApps,\n    required this.loading,\n    required this.onOpen,\n    this.onSettings,\n  });\n\n  final HostedGroup group;\n  final List<HostedMember>? members;\n  final List<HostedGroupApp>? latestApps;\n  final bool loading;\n  final VoidCallback onOpen;\n  final VoidCallback? onSettings;""",
        "current group card settings field",
    )

    text = replace_once(
        text,
        """          const SizedBox(height: 14),\n          SizedBox(\n            width: double.infinity,\n            child: FilledButton.icon(\n              key: const Key('girls-current-group-open'),""",
        """          const SizedBox(height: 14),\n          if (onSettings != null) ...<Widget>[\n            SizedBox(\n              width: double.infinity,\n              child: OutlinedButton.icon(\n                key: const Key('girls-current-group-settings'),\n                onPressed: loading ? null : onSettings,\n                style: OutlinedButton.styleFrom(\n                  backgroundColor: Colors.white.withValues(alpha: .56),\n                  foregroundColor: _ink,\n                  side: const BorderSide(color: Color(0xFFE8B9C7)),\n                  shape: RoundedRectangleBorder(\n                    borderRadius: BorderRadius.circular(20),\n                  ),\n                ),\n                icon: const Icon(Icons.settings_rounded),\n                label: const Text(\n                  'グループ設定',\n                  style: TextStyle(fontWeight: FontWeight.w900),\n                ),\n              ),\n            ),\n            const SizedBox(height: 10),\n          ],\n          SizedBox(\n            width: double.infinity,\n            child: FilledButton.icon(\n              key: const Key('girls-current-group-open'),""",
        "current group settings button",
    )

    PATH.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
