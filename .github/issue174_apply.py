from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_count = text.count(start)
    end_count = text.count(end)
    if start_count != 1 or end_count != 1:
        raise RuntimeError(
            f"{label}: expected one start/end marker, found {start_count}/{end_count}"
        )
    left, tail = text.split(start, 1)
    _, right = tail.split(end, 1)
    return left + replacement + end + right


# Web upload portal: every listed Hosted group is already an active membership.
path = "apps/web/girls_portal.js"
text = read(path)
text = replace_once(text, "async function loadOwnerGroups() {", "async function loadActiveGroups() {", "web active group loader name")
text = replace_once(text, "    const owners = [];\n", "    const groups = [];\n", "web owner array")
text = replace_once(text, '      if (group.role === "owner") owners.push(group);\n', '      groups.push(group);\n', "web owner filter")
text = replace_once(text, "    for (const group of owners) {\n", "    for (const group of groups) {\n", "web group select population")
text = replace_once(text, "    uploadGroup.disabled = owners.length === 0;\n    uploadSubmit.disabled = owners.length === 0;\n    if (owners.length === 0) {\n      setMessage(uploadError, \"アプリを追加するには、自分がオーナーのグループが必要です。Girlsアプリで先にグループを作ってください。\");\n", "    uploadGroup.disabled = groups.length === 0;\n    uploadSubmit.disabled = groups.length === 0;\n    if (groups.length === 0) {\n      setMessage(uploadError, \"アプリを追加するには、参加中のグループが必要です。Girlsアプリでグループを作るか参加してください。\");\n", "web active group empty state")
text = replace_once(text, "      await loadOwnerGroups();\n", "      await loadActiveGroups();\n", "web active group loader call")
write(path, text)


# Web shell: uploadGroup is the active-group selector; My Apps comes only from /hosted/my/apps.
path = "apps/web/girls_portal_shell.js"
text = read(path)
text = text.replace("ownerGroups", "activeGroups")
text = text.replace("owner group", "active group")
text = text.replace("オーナーのグループ", "参加中のグループ")

new_validator = '''  function validateManagedAppsPayload(payload) {
    const keys = Object.keys(payload);
    if (keys.length !== 1 || keys[0] !== "apps") {
      throw new Error("Managed Girls apps response has invalid fields.");
    }
    if (!Array.isArray(payload.apps)) {
      throw new Error("Managed Girls apps response has no apps list.");
    }
    const allowedFields = new Set([
      "app_id", "group_id", "owner_user_id", "title", "source_kind", "created_at",
      "builtin_id", "builtin_asset_path", "parent_app_id", "source_sha256",
      "source_updated_at", "published_sha256", "published_at", "deletion_state",
      "builtin_version", "source_revision", "published_version", "editable",
      "visibility", "stats", "group_name",
    ]);
    return payload.apps.map((rawApp) => {
      const app = requirePlainObject(rawApp, "Managed Girls app");
      const actual = Object.keys(app);
      for (const field of [
        "app_id", "group_id", "owner_user_id", "title", "source_kind", "created_at",
        "editable", "visibility", "stats", "group_name",
      ]) {
        if (!actual.includes(field)) throw new Error(`Managed Girls app is missing field: ${field}`);
      }
      for (const field of actual) {
        if (!allowedFields.has(field)) throw new Error(`Managed Girls app contained unexpected field: ${field}`);
      }
      if (!ID_PATTERN.test(app.app_id)) throw new Error("Managed Girls app has an invalid app_id.");
      if (!ID_PATTERN.test(app.group_id)) throw new Error("Managed Girls app has an invalid group_id.");
      if (!ID_PATTERN.test(app.owner_user_id)) throw new Error("Managed Girls app has an invalid owner_user_id.");
      const title = requireString(app.title, "Managed Girls app title");
      const groupName = requireString(app.group_name, "Managed Girls app group_name");
      const createdAt = requireString(app.created_at, "Managed Girls app created_at");
      if (Number.isNaN(Date.parse(createdAt))) throw new Error("Managed Girls app created_at is invalid.");
      if (typeof app.editable !== "boolean") throw new Error("Managed Girls app editable is invalid.");
      if (app.visibility !== "visible" && app.visibility !== "hidden") {
        throw new Error("Managed Girls app visibility is invalid.");
      }
      const stats = requirePlainObject(app.stats, "Managed Girls app stats");
      requireExactFields(stats, ["total_plays", "unique_users", "monthly_plays"], "Managed Girls app stats");
      for (const field of ["total_plays", "unique_users", "monthly_plays"]) {
        if (!Number.isInteger(stats[field]) || stats[field] < 0) {
          throw new Error(`Managed Girls app stats ${field} is invalid.`);
        }
      }
      const publishedVersion = app.published_version;
      if (publishedVersion !== undefined && (!Number.isInteger(publishedVersion) || publishedVersion < 1)) {
        throw new Error("Managed Girls app published_version is invalid.");
      }
      return {
        appId: app.app_id,
        groupId: app.group_id,
        ownerUserId: app.owner_user_id,
        title,
        groupName,
        createdAt,
        published: Number.isInteger(publishedVersion),
      };
    });
  }

'''
text = replace_between(
    text,
    "  function validateGroupAppsPayload(payload, group) {\n",
    "  async function openPreview(app, triggerButton) {\n",
    new_validator,
    "web managed app validator",
)
text = replace_once(
    text,
    '        ["app_id", "group_id", "source_revision", "content_path", "expires_in"],\n',
    '        ["app_id", "group_id", "source_revision", "content_path", "expires_in", "runtime_token", "runtime_expires_in"],\n',
    "web preview exact schema",
)
text = replace_once(
    text,
    '      requirePositiveInteger(payload.expires_in, "preview expires_in");\n      const contentPath = requireString(payload.content_path, "preview content_path");\n',
    '      requirePositiveInteger(payload.expires_in, "preview expires_in");\n      requireString(payload.runtime_token, "preview runtime_token");\n      requirePositiveInteger(payload.runtime_expires_in, "preview runtime_expires_in");\n      const contentPath = requireString(payload.content_path, "preview content_path");\n',
    "web preview runtime validation",
)
new_load = '''  async function loadMyApps() {
    const generation = ++appsLoadGeneration;
    closePreview();
    setMessage(appsError, null);
    appsRefresh.disabled = true;
    appsStatus.textContent = "アプリを読み込み中…";
    appList.replaceChildren();

    try {
      const payload = await hostedGet("/hosted/my/apps");
      if (generation !== appsLoadGeneration) return;
      const apps = validateManagedAppsPayload(payload);
      apps.sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt));
      renderApps(apps);
      appsStatus.textContent = apps.length === 0
        ? "まだ自分で作ったアプリはありません。"
        : `${apps.length}個の自分のアプリがあります。`;
    } catch (error) {
      if (generation !== appsLoadGeneration) return;
      setMessage(appsError, errorMessage(error));
      appsStatus.textContent = "アプリを読み込めませんでした。";
      if (error instanceof Error && error.status === 401) {
        logoutButton.click();
      }
    } finally {
      if (generation === appsLoadGeneration) appsRefresh.disabled = false;
    }
  }

'''
text = replace_between(
    text,
    "  async function loadMyApps() {\n",
    "  for (const button of nav.querySelectorAll(\"[data-girls-view]\")) {\n",
    new_load,
    "web my apps loader",
)
write(path, text)


# Web app action decorator: use the author-only managed list as the single source.
path = "apps/web/girls_footer.js"
text = read(path)
text = replace_once(text, '  const uploadGroup = document.getElementById("girls-upload-group");\n', "", "footer upload group lookup")
text = replace_once(text, '    [uploadGroup, "#girls-upload-group", HTMLSelectElement],\n', "", "footer upload group type check")
new_metadata = '''  async function loadAppMetadata() {
    const managedPayload = await apiRequest("/hosted/my/apps");
    const keys = Object.keys(managedPayload);
    if (keys.length !== 1 || keys[0] !== "apps" || !Array.isArray(managedPayload.apps)) {
      throw new Error("Managed Girls apps response has invalid fields.");
    }
    const allowedFields = new Set([
      "app_id", "group_id", "owner_user_id", "title", "source_kind", "created_at",
      "builtin_id", "builtin_asset_path", "parent_app_id", "source_sha256",
      "source_updated_at", "published_sha256", "published_at", "deletion_state",
      "builtin_version", "source_revision", "published_version", "editable",
      "visibility", "stats", "group_name",
    ]);
    const apps = [];
    const managedById = new Map();
    for (const rawManaged of managedPayload.apps) {
      const managed = requirePlainObject(rawManaged, "Managed Girls app");
      const actual = Object.keys(managed);
      for (const field of [
        "app_id", "group_id", "owner_user_id", "title", "source_kind", "created_at",
        "editable", "visibility", "stats", "group_name",
      ]) {
        if (!actual.includes(field)) throw new Error(`Managed Girls app is missing field: ${field}`);
      }
      for (const field of actual) {
        if (!allowedFields.has(field)) throw new Error(`Managed Girls app contained unexpected field: ${field}`);
      }
      if (!ID_PATTERN.test(managed.app_id)) throw new Error("Managed Girls app has an invalid app_id.");
      if (!ID_PATTERN.test(managed.group_id)) throw new Error("Managed Girls app has an invalid group_id.");
      if (!ID_PATTERN.test(managed.owner_user_id)) throw new Error("Managed Girls app has an invalid owner_user_id.");
      if (managed.visibility !== "visible" && managed.visibility !== "hidden") {
        throw new Error("Managed Girls app has an invalid visibility state.");
      }
      if (typeof managed.editable !== "boolean") throw new Error("Managed Girls app has invalid editable.");
      const title = requireString(managed.title, "Managed Girls app title");
      const groupName = requireString(managed.group_name, "Managed Girls app group_name");
      const createdAt = requireString(managed.created_at, "Managed Girls app created_at");
      const parsedDate = new Date(createdAt);
      if (Number.isNaN(parsedDate.getTime())) throw new Error("Managed Girls app created_at is invalid.");
      requirePlainObject(managed.stats, "Managed Girls app stats");
      const app = {
        appId: managed.app_id,
        groupId: managed.group_id,
        ownerUserId: managed.owner_user_id,
        groupName,
        title,
        dateLabel: parsedDate.toLocaleDateString("ja-JP"),
        thumbnailUrl: optionalThumbnailUrl(managed.thumbnail_url, "Managed Girls app thumbnail_url"),
      };
      apps.push(app);
      managedById.set(managed.app_id, {
        appId: managed.app_id,
        visibility: managed.visibility,
        thumbnailUrl: app.thumbnailUrl,
      });
    }
    return { apps, managedById };
  }

'''
text = replace_between(
    text,
    "  function ownerGroups() {\n",
    "  function cardIdentity(card) {\n",
    new_metadata,
    "footer managed metadata",
)
write(path, text)


# Web copy: My Apps is author identity, not group ownership.
path = "apps/web/girls.html"
text = read(path)
text = replace_once(
    text,
    "自分がオーナーのグループに追加したアプリをまとめて表示します。",
    "自分で作ったアプリをまとめて表示します。",
    "web My Apps copy",
)
write(path, text)


# Flutter Hosted app schema: owner_user_id is mandatory in the new contract.
path = "apps/mobile/lib/hosted_api.dart"
text = read(path)
text = replace_once(text, "    this.ownerUserId,\n", "    required this.ownerUserId,\n", "HostedGroupApp owner constructor")
text = replace_once(text, "  final String? ownerUserId;\n", "  final String ownerUserId;\n", "HostedGroupApp owner field")
text = replace_once(
    text,
    "      'created_at',\n    ]) {\n",
    "      'created_at',\n      'owner_user_id',\n    ]) {\n",
    "HostedGroupApp required owner field",
)
text = replace_once(
    text,
    "    final String? ownerUserId = _optionalString(json, 'owner_user_id');\n    if (ownerUserId != null && !_hostedHexIdPattern.hasMatch(ownerUserId)) {\n      throw const FormatException('Hosted group app has invalid owner_user_id.');\n    }\n",
    "",
    "HostedGroupApp optional owner compatibility",
)
text = replace_once(text, "      ownerUserId: ownerUserId,\n", "      ownerUserId: _requireHexId(json, 'owner_user_id'),\n", "HostedGroupApp strict owner parse")
write(path, text)


# Flutter My Apps: all listed groups are active memberships; author apps still come from /my/apps.
path = "apps/mobile/lib/girls/girls_apps_page.dart"
text = read(path)
text = text.replace("_ownerGroups", "_activeGroups")
text = text.replace("ownerGroups", "activeGroups")
text = text.replace("_chooseOwnerGroup", "_chooseActiveGroup")
text = replace_once(
    text,
    "        _activeGroups = groups\n            .where((HostedGroup group) => group.isOwner)\n            .toList(growable: false);\n",
    "        _activeGroups = groups;\n",
    "Flutter active groups load",
)
text = text.replace("自分がオーナーのグループ", "参加中のグループ")
write(path, text)


# Flutter Groups page: any active membership can open the app-add flow.
path = "apps/mobile/lib/girls/girls_groups_page.dart"
text = read(path)
text = replace_once(
    text,
    "    final bool hasOwnedGroup = groups.any((HostedGroup group) => group.isOwner);\n    if (!hasOwnedGroup) {\n      setState(() => _error = 'アプリを追加するには、自分がオーナーのグループが必要です。');\n      return;\n    }\n",
    "    if (groups.isEmpty) {\n      setState(() => _error = 'アプリを追加するには、参加中のグループが必要です。');\n      return;\n    }\n",
    "Flutter group page active membership",
)
write(path, text)


# Flutter ZIP page contract is activeGroups, not ownerGroups.
path = "apps/mobile/lib/girls/girls_zip_upload_page.dart"
text = read(path)
text = text.replace("ownerGroups", "activeGroups")
text = text.replace("owner group", "active group")
write(path, text)


# Ensure obsolete Girls ownership names/copy are gone from the target UI files.
for path in (
    "apps/web/girls_portal.js",
    "apps/web/girls_portal_shell.js",
    "apps/web/girls_footer.js",
    "apps/mobile/lib/girls/girls_apps_page.dart",
    "apps/mobile/lib/girls/girls_groups_page.dart",
    "apps/mobile/lib/girls/girls_zip_upload_page.dart",
):
    text = read(path)
    for legacy in ("loadOwnerGroups", "ownerGroups", "_ownerGroups", "自分がオーナーのグループが必要"):
        if legacy in text:
            raise RuntimeError(f"{path}: legacy owner-only UI token remains: {legacy}")

print("#174 active-member UI migration applied")
