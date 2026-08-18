"use strict";

if (typeof apiRequest !== "function" || typeof loadDashboard !== "function" || typeof teacherGroups !== "function") {
  throw new Error("Teacher dashboard requires app.js to load first.");
}
if (typeof phase2ValidateApp !== "function") {
  throw new Error("Teacher dashboard requires phase2.js to load first.");
}

const teacherPortalSiteHeader = document.querySelector(".site-header");
const teacherPortalPageShell = document.querySelector(".page-shell");
if (!(teacherPortalSiteHeader instanceof HTMLElement)) throw new Error("Teacher portal site header was not found.");
if (!(teacherPortalPageShell instanceof HTMLElement)) throw new Error("Teacher portal page shell was not found.");

const teacherPortalRoot = document.createElement("div");
teacherPortalRoot.id = "teacher-portal";
teacherPortalRoot.className = "teacher-portal hidden";
teacherPortalRoot.innerHTML = `
  <aside class="teacher-sidebar" aria-label="先生用メニュー">
    <div class="teacher-brand">
      <div class="teacher-brand-mark" aria-hidden="true">👥</div>
      <div>
        <p class="teacher-brand-name">みんアプ</p>
        <p class="teacher-brand-subtitle">先生用ポータル</p>
      </div>
    </div>
    <nav class="teacher-nav">
      <button class="teacher-nav-item teacher-nav-item-active" type="button" data-teacher-view="home"><span aria-hidden="true">⌂</span><span>ホーム</span></button>
      <button class="teacher-nav-item" type="button" data-teacher-view="reviews"><span aria-hidden="true">◉</span><span>申請の確認</span><span id="teacher-nav-review-count" class="teacher-nav-badge hidden"></span></button>
      <button class="teacher-nav-item" type="button" data-teacher-view="members"><span aria-hidden="true">♟</span><span>クラス・生徒管理</span></button>
      <button class="teacher-nav-item" type="button" data-teacher-view="settings"><span aria-hidden="true">⚙</span><span>設定</span></button>
    </nav>
    <div class="teacher-account">
      <div class="teacher-account-card">
        <div id="teacher-account-avatar" class="teacher-account-avatar">先</div>
        <div class="teacher-account-copy">
          <strong id="teacher-account-name"></strong>
          <span id="teacher-account-classroom"></span>
        </div>
      </div>
      <button id="teacher-logout" class="teacher-logout" type="button">↪ ログアウト</button>
    </div>
  </aside>

  <div class="teacher-main">
    <header class="teacher-topbar">
      <div class="teacher-topbar-title-wrap">
        <button id="teacher-mobile-menu" class="teacher-mobile-menu" type="button" aria-label="メニューを開く">☰</button>
        <h1 id="teacher-class-title">クラスの管理</h1>
      </div>
      <label class="teacher-class-picker">
        <span>現在のクラス:</span>
        <select id="teacher-class-select" aria-label="管理するクラス"></select>
      </label>
    </header>

    <main class="teacher-content">
      <p id="teacher-global-error" class="teacher-error hidden" role="alert"></p>

      <section id="teacher-view-home" class="teacher-view">
        <div class="teacher-welcome">
          <h2 id="teacher-welcome-title"></h2>
          <p>生徒さんから <strong id="teacher-welcome-review-count">0件</strong> のアプリ公開申請が届いています。</p>
        </div>

        <section class="teacher-pending-panel" aria-labelledby="teacher-pending-title">
          <div class="teacher-section-heading teacher-section-heading-pending">
            <span class="teacher-heading-icon teacher-heading-icon-warning" aria-hidden="true">!</span>
            <h3 id="teacher-pending-title">先生の確認待ち</h3>
            <span id="teacher-pending-count" class="teacher-count-badge">0件</span>
          </div>
          <div id="teacher-pending-list" class="teacher-pending-grid"></div>
          <p id="teacher-pending-empty" class="teacher-empty hidden">このクラスには確認待ちのアプリがありません。</p>
        </section>

        <section class="teacher-published-section" aria-labelledby="teacher-published-title">
          <div class="teacher-section-heading">
            <span class="teacher-heading-icon teacher-heading-icon-success" aria-hidden="true">✓</span>
            <h3 id="teacher-published-title">現在クラスに公開されているアプリ</h3>
          </div>
          <div id="teacher-published-list" class="teacher-table"></div>
          <p id="teacher-published-empty" class="teacher-empty hidden">このクラスには公開中のアプリがありません。</p>
        </section>
      </section>

      <section id="teacher-view-reviews" class="teacher-view hidden">
        <div class="teacher-page-heading">
          <p class="teacher-kicker">公開申請</p>
          <h2>申請の確認</h2>
          <p>生徒さんのアプリを安全なプレビューで確認してから公開できます。</p>
        </div>
        <div id="teacher-review-page-list" class="teacher-review-page-list"></div>
        <p id="teacher-review-page-empty" class="teacher-empty hidden">このクラスには確認待ちのアプリがありません。</p>
      </section>

      <section id="teacher-view-members" class="teacher-view hidden">
        <div class="teacher-page-heading">
          <p class="teacher-kicker">クラス管理</p>
          <h2>クラス・生徒管理</h2>
          <p>クラスの作成、生徒IDの発行、所属メンバーの管理ができます。</p>
        </div>
        <div class="teacher-management-grid">
          <form id="teacher-create-group-form" class="teacher-management-card">
            <h3>クラスを作る</h3>
            <label>クラス名<input id="teacher-group-name" maxlength="60" placeholder="例: 火曜・午前クラス" required /></label>
            <button class="teacher-primary-button" type="submit">クラスを作成</button>
            <p id="teacher-create-group-error" class="teacher-inline-error hidden" role="alert"></p>
          </form>
          <form id="teacher-create-student-form" class="teacher-management-card">
            <h3>生徒IDを発行</h3>
            <p class="teacher-management-note">現在選択しているクラスに、生徒IDと仮パスワードを1人分発行します。</p>
            <button class="teacher-primary-button" type="submit">生徒IDを1人分発行</button>
            <p id="teacher-create-student-error" class="teacher-inline-error hidden" role="alert"></p>
          </form>
        </div>
        <section id="teacher-issued-credentials" class="teacher-credentials hidden" aria-live="polite">
          <p class="teacher-kicker">生徒に渡すもの</p>
          <div><strong>ID</strong><code id="teacher-issued-login"></code></div>
          <div><strong>仮パスワード</strong><code id="teacher-issued-password"></code></div>
          <p>仮パスワードはこの画面で一度だけ表示します。必要な場所へ安全に控えてください。</p>
        </section>
        <section class="teacher-members-section">
          <div class="teacher-section-heading">
            <span class="teacher-heading-icon" aria-hidden="true">♟</span>
            <h3>現在のクラスのメンバー</h3>
          </div>
          <div id="teacher-members-list" class="teacher-members-list"></div>
          <p id="teacher-members-empty" class="teacher-empty hidden">メンバーがいません。</p>
        </section>
      </section>

      <section id="teacher-view-settings" class="teacher-view hidden">
        <div class="teacher-page-heading">
          <p class="teacher-kicker">設定</p>
          <h2>教室とアカウント</h2>
          <p>現在接続している教室とログイン中のアカウントを確認できます。</p>
        </div>
        <div class="teacher-settings-card">
          <dl>
            <div><dt>ログインID</dt><dd id="teacher-settings-login"></dd></div>
            <div><dt>教室</dt><dd id="teacher-settings-classroom"></dd></div>
            <div><dt>選択中のクラス</dt><dd id="teacher-settings-group"></dd></div>
          </dl>
          <button id="teacher-change-classroom" class="teacher-secondary-button" type="button">教室を変更する</button>
        </div>
      </section>
    </main>
  </div>

  <div id="teacher-preview-modal" class="teacher-modal hidden" role="dialog" aria-modal="true" aria-labelledby="teacher-preview-title">
    <div class="teacher-modal-card">
      <div class="teacher-preview-area">
        <button id="teacher-preview-mobile-close" class="teacher-modal-close teacher-modal-close-mobile" type="button" aria-label="閉じる">×</button>
        <div class="teacher-phone-frame">
          <iframe id="teacher-preview-frame" title="アプリの安全プレビュー" sandbox="allow-scripts" referrerpolicy="no-referrer"></iframe>
          <div id="teacher-preview-loading" class="teacher-preview-loading">プレビューを読み込み中…</div>
        </div>
      </div>
      <div class="teacher-preview-details">
        <div class="teacher-preview-header">
          <div>
            <span id="teacher-preview-status" class="teacher-preview-status">確認待ち</span>
            <h2 id="teacher-preview-title"></h2>
          </div>
          <button id="teacher-preview-close" class="teacher-modal-close" type="button" aria-label="閉じる">×</button>
        </div>
        <div class="teacher-message-card">
          <p>作成者からのメッセージ</p>
          <strong id="teacher-preview-description"></strong>
          <div class="teacher-preview-meta">
            <span id="teacher-preview-owner"></span>
            <span id="teacher-preview-filename"></span>
          </div>
        </div>
        <div class="teacher-safety">
          <h3><span aria-hidden="true">✓</span> 安全なプレビュー環境</h3>
          <ul>
            <li>✓ sandbox 内で実行</li>
            <li>✓ 外部通信を遮断</li>
            <li>✓ ZIPファイルは規定サイズ内</li>
          </ul>
        </div>
        <div id="teacher-preview-error" class="teacher-inline-error hidden" role="alert"></div>
        <div class="teacher-preview-actions">
          <p id="teacher-preview-help">動作を確認し、問題がなければ承認してください。</p>
          <button id="teacher-approve-button" class="teacher-approve-button" type="button">✓ 承認して、クラス全員に公開する</button>
          <button id="teacher-preview-cancel" class="teacher-secondary-button teacher-preview-cancel" type="button">← 閉じる（公開しない）</button>
        </div>
      </div>
    </div>
  </div>
`;
document.body.append(teacherPortalRoot);

const teacherPortalClassTitle = requiredElement("teacher-class-title");
const teacherPortalClassSelect = requiredElement("teacher-class-select");
const teacherPortalGlobalError = requiredElement("teacher-global-error");
const teacherPortalWelcomeTitle = requiredElement("teacher-welcome-title");
const teacherPortalWelcomeReviewCount = requiredElement("teacher-welcome-review-count");
const teacherPortalPendingCount = requiredElement("teacher-pending-count");
const teacherPortalPendingList = requiredElement("teacher-pending-list");
const teacherPortalPendingEmpty = requiredElement("teacher-pending-empty");
const teacherPortalPublishedList = requiredElement("teacher-published-list");
const teacherPortalPublishedEmpty = requiredElement("teacher-published-empty");
const teacherPortalReviewPageList = requiredElement("teacher-review-page-list");
const teacherPortalReviewPageEmpty = requiredElement("teacher-review-page-empty");
const teacherPortalMembersList = requiredElement("teacher-members-list");
const teacherPortalMembersEmpty = requiredElement("teacher-members-empty");
const teacherPortalNavReviewCount = requiredElement("teacher-nav-review-count");
const teacherPortalAccountName = requiredElement("teacher-account-name");
const teacherPortalAccountClassroom = requiredElement("teacher-account-classroom");
const teacherPortalAccountAvatar = requiredElement("teacher-account-avatar");
const teacherPortalLogout = requiredElement("teacher-logout");
const teacherPortalMobileMenu = requiredElement("teacher-mobile-menu");
const teacherPortalCreateGroupForm = requiredElement("teacher-create-group-form");
const teacherPortalGroupName = requiredElement("teacher-group-name");
const teacherPortalCreateGroupError = requiredElement("teacher-create-group-error");
const teacherPortalCreateStudentForm = requiredElement("teacher-create-student-form");
const teacherPortalCreateStudentError = requiredElement("teacher-create-student-error");
const teacherPortalIssuedCredentials = requiredElement("teacher-issued-credentials");
const teacherPortalIssuedLogin = requiredElement("teacher-issued-login");
const teacherPortalIssuedPassword = requiredElement("teacher-issued-password");
const teacherPortalSettingsLogin = requiredElement("teacher-settings-login");
const teacherPortalSettingsClassroom = requiredElement("teacher-settings-classroom");
const teacherPortalSettingsGroup = requiredElement("teacher-settings-group");
const teacherPortalChangeClassroom = requiredElement("teacher-change-classroom");
const teacherPortalPreviewModal = requiredElement("teacher-preview-modal");
const teacherPortalPreviewFrame = requiredElement("teacher-preview-frame");
const teacherPortalPreviewLoading = requiredElement("teacher-preview-loading");
const teacherPortalPreviewTitle = requiredElement("teacher-preview-title");
const teacherPortalPreviewStatus = requiredElement("teacher-preview-status");
const teacherPortalPreviewDescription = requiredElement("teacher-preview-description");
const teacherPortalPreviewOwner = requiredElement("teacher-preview-owner");
const teacherPortalPreviewFilename = requiredElement("teacher-preview-filename");
const teacherPortalPreviewError = requiredElement("teacher-preview-error");
const teacherPortalPreviewHelp = requiredElement("teacher-preview-help");
const teacherPortalApproveButton = requiredElement("teacher-approve-button");
const teacherPortalPreviewClose = requiredElement("teacher-preview-close");
const teacherPortalPreviewMobileClose = requiredElement("teacher-preview-mobile-close");
const teacherPortalPreviewCancel = requiredElement("teacher-preview-cancel");

if (!(teacherPortalClassSelect instanceof HTMLSelectElement)) throw new Error("#teacher-class-select must be a select.");
if (!(teacherPortalCreateGroupForm instanceof HTMLFormElement)) throw new Error("#teacher-create-group-form must be a form.");
if (!(teacherPortalGroupName instanceof HTMLInputElement)) throw new Error("#teacher-group-name must be an input.");
if (!(teacherPortalCreateStudentForm instanceof HTMLFormElement)) throw new Error("#teacher-create-student-form must be a form.");
if (!(teacherPortalPreviewFrame instanceof HTMLIFrameElement)) throw new Error("#teacher-preview-frame must be an iframe.");
if (!(teacherPortalApproveButton instanceof HTMLButtonElement)) throw new Error("#teacher-approve-button must be a button.");

const teacherPortalState = {
  selectedGroupId: null,
  reviewApps: [],
  publishedApps: [],
  members: [],
  previewApp: null,
  previewCanApprove: false,
};

function teacherPortalSetError(element, message) {
  if (message === null) {
    element.textContent = "";
    hide(element);
    return;
  }
  element.textContent = message;
  show(element);
}

function teacherPortalHandleError(error, element = teacherPortalGlobalError) {
  console.error(error);
  if (error instanceof ApiError && error.status === 401) {
    clearAuthentication();
    setError(loginError, "ログインの有効期限が切れました。もう一度ログインしてください。");
    return;
  }
  teacherPortalSetError(element, apiErrorMessage(error));
}

function teacherPortalActiveGroup() {
  if (teacherPortalState.selectedGroupId === null) return null;
  const group = teacherGroups().find((item) => item.group_id === teacherPortalState.selectedGroupId);
  if (group === undefined) throw new Error("Selected teacher group is no longer available.");
  return group;
}

function teacherPortalFormatDate(value, includeTime = false) {
  if (typeof value !== "string" || value.length === 0) throw new TypeError("Date value must be a non-empty string.");
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid date value: ${value}`);
  const options = includeTime
    ? { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }
    : { year: "numeric", month: "2-digit", day: "2-digit" };
  return new Intl.DateTimeFormat("ja-JP", options).format(date);
}

function teacherPortalAppVisual(app) {
  const text = `${app.title} ${app.app_id}`.toLowerCase();
  if (text.includes("時間") || text.includes("予定") || text.includes("calendar")) return { symbol: "▣", tone: "blue" };
  if (text.includes("血圧") || text.includes("健康") || text.includes("heart")) return { symbol: "♥", tone: "green" };
  if (text.includes("クイズ") || text.includes("quiz") || text.includes("問題")) return { symbol: "♟", tone: "orange" };
  if (text.includes("計算") || text.includes("calculator")) return { symbol: "▦", tone: "gray" };
  return { symbol: "◆", tone: "purple" };
}

function teacherPortalValidateReviewApp(app) {
  phase2ValidateApp(app);
  if (app.status !== "pending_review") throw new Error("Review queue contained an app that is not pending review.");
}

function teacherPortalValidatePublishedApp(app) {
  phase2ValidateApp(app);
  if (app.status !== "approved" || typeof app.reviewed_at !== "string") {
    throw new Error("Published app response is invalid.");
  }
}

function teacherPortalValidateMember(member) {
  if (
    typeof member !== "object" || member === null || Array.isArray(member) ||
    typeof member.user_id !== "string" || member.user_id.length === 0 ||
    typeof member.login_id !== "string" || member.login_id.length === 0 ||
    !["teacher", "student"].includes(member.role)
  ) {
    throw new Error("Members response contains an invalid member.");
  }
}

function teacherPortalSetGroups() {
  const groups = teacherGroups();
  const previous = teacherPortalState.selectedGroupId;
  teacherPortalClassSelect.replaceChildren();
  for (const group of groups) {
    const option = document.createElement("option");
    option.value = group.group_id;
    option.textContent = group.name;
    teacherPortalClassSelect.append(option);
  }
  teacherPortalClassSelect.disabled = groups.length === 0;
  if (groups.length === 0) {
    teacherPortalState.selectedGroupId = null;
    return;
  }
  const selected = groups.some((group) => group.group_id === previous) ? previous : groups[0].group_id;
  teacherPortalState.selectedGroupId = selected;
  teacherPortalClassSelect.value = selected;
}

function teacherPortalUpdateIdentity() {
  if (currentUser === null || currentUser.role !== "teacher") throw new Error("Teacher portal requires an authenticated teacher.");
  const displayName = `${currentUser.login_id}先生`;
  const classroom = currentTenant === null ? "みんアプ" : currentTenant.display_name;
  teacherPortalWelcomeTitle.textContent = `${displayName}、こんにちは！`;
  teacherPortalAccountName.textContent = displayName;
  teacherPortalAccountClassroom.textContent = classroom;
  teacherPortalAccountAvatar.textContent = currentUser.login_id.slice(0, 1).toUpperCase() || "先";
  teacherPortalSettingsLogin.textContent = currentUser.login_id;
  teacherPortalSettingsClassroom.textContent = classroom;
}

function teacherPortalUpdateGroupLabels() {
  const group = teacherPortalActiveGroup();
  const name = group === null ? "クラス未設定" : group.name;
  teacherPortalClassTitle.textContent = `${name} の管理`;
  teacherPortalSettingsGroup.textContent = name;
}

function teacherPortalReviewCard(app, compact) {
  const visual = teacherPortalAppVisual(app);
  const card = document.createElement("article");
  card.className = compact ? "teacher-review-card teacher-review-card-compact" : "teacher-review-card";

  const icon = document.createElement("div");
  icon.className = `teacher-app-icon teacher-app-icon-${visual.tone}`;
  icon.textContent = visual.symbol;

  const body = document.createElement("div");
  body.className = "teacher-review-body";
  const title = document.createElement("h4");
  title.textContent = app.title;
  const meta = document.createElement("div");
  meta.className = "teacher-review-meta";
  const submittedAt = typeof app.submitted_at === "string" ? app.submitted_at : app.created_at;
  const owner = document.createElement("span");
  owner.textContent = `◉ ${app.owner_login_id} さん`;
  const time = document.createElement("span");
  time.textContent = `◷ ${teacherPortalFormatDate(submittedAt, true)} 申請`;
  meta.append(owner, time);
  const description = document.createElement("p");
  description.className = "teacher-review-description";
  description.textContent = typeof app.description === "string" ? app.description : "アプリの説明はありません。";
  body.append(title, meta, description);

  const button = document.createElement("button");
  button.type = "button";
  button.className = "teacher-review-button";
  button.textContent = "⌕ 確認する";
  button.addEventListener("click", () => {
    teacherPortalOpenPreview(app, true).catch((error) => teacherPortalHandleError(error));
  });

  card.append(icon, body, button);
  return card;
}

function teacherPortalRenderReviewApps() {
  teacherPortalPendingList.replaceChildren();
  teacherPortalReviewPageList.replaceChildren();
  const count = teacherPortalState.reviewApps.length;
  teacherPortalPendingCount.textContent = `${count}件`;
  teacherPortalWelcomeReviewCount.textContent = `${count}件`;
  teacherPortalNavReviewCount.textContent = String(count);
  if (count === 0) {
    show(teacherPortalPendingEmpty);
    show(teacherPortalReviewPageEmpty);
    hide(teacherPortalNavReviewCount);
    return;
  }
  hide(teacherPortalPendingEmpty);
  hide(teacherPortalReviewPageEmpty);
  show(teacherPortalNavReviewCount);
  for (const app of teacherPortalState.reviewApps) {
    teacherPortalPendingList.append(teacherPortalReviewCard(app, true));
    teacherPortalReviewPageList.append(teacherPortalReviewCard(app, false));
  }
}

function teacherPortalRenderPublishedApps() {
  teacherPortalPublishedList.replaceChildren();
  if (teacherPortalState.publishedApps.length === 0) {
    show(teacherPortalPublishedEmpty);
    return;
  }
  hide(teacherPortalPublishedEmpty);

  const header = document.createElement("div");
  header.className = "teacher-table-row teacher-table-header";
  for (const label of ["アプリ名", "作成者", "公開日", "ステータス", "操作"]) {
    const cell = document.createElement("span");
    cell.textContent = label;
    header.append(cell);
  }
  teacherPortalPublishedList.append(header);

  for (const app of teacherPortalState.publishedApps) {
    const visual = teacherPortalAppVisual(app);
    const row = document.createElement("div");
    row.className = "teacher-table-row";

    const titleCell = document.createElement("div");
    titleCell.className = "teacher-table-app";
    const icon = document.createElement("span");
    icon.className = `teacher-table-icon teacher-app-icon-${visual.tone}`;
    icon.textContent = visual.symbol;
    const title = document.createElement("strong");
    title.textContent = app.title;
    titleCell.append(icon, title);

    const owner = document.createElement("span");
    owner.textContent = app.owner_login_id;
    const date = document.createElement("span");
    date.textContent = teacherPortalFormatDate(app.reviewed_at);
    const status = document.createElement("span");
    const badge = document.createElement("span");
    badge.className = "teacher-live-badge";
    badge.textContent = "公開中";
    status.append(badge);
    const action = document.createElement("span");
    const previewButton = document.createElement("button");
    previewButton.type = "button";
    previewButton.className = "teacher-table-action";
    previewButton.textContent = "プレビュー";
    previewButton.addEventListener("click", () => {
      teacherPortalOpenPreview(app, false).catch((error) => teacherPortalHandleError(error));
    });
    action.append(previewButton);

    row.append(titleCell, owner, date, status, action);
    teacherPortalPublishedList.append(row);
  }
}

function teacherPortalRenderMembers() {
  teacherPortalMembersList.replaceChildren();
  if (teacherPortalState.members.length === 0) {
    show(teacherPortalMembersEmpty);
    return;
  }
  hide(teacherPortalMembersEmpty);
  for (const member of teacherPortalState.members) {
    const row = document.createElement("article");
    row.className = "teacher-member-row";
    const identity = document.createElement("div");
    const name = document.createElement("strong");
    name.textContent = member.login_id;
    const role = document.createElement("span");
    role.textContent = member.role === "teacher" ? "先生" : "生徒";
    identity.append(name, role);
    row.append(identity);

    if (member.role === "student") {
      const actions = document.createElement("div");
      actions.className = "teacher-member-actions";
      const reset = document.createElement("button");
      reset.type = "button";
      reset.className = "teacher-secondary-button teacher-small-button";
      reset.textContent = "仮パスワード再発行";
      reset.addEventListener("click", async () => {
        teacherPortalSetError(teacherPortalGlobalError, null);
        reset.disabled = true;
        try {
          const payload = await apiRequest(`/users/${member.user_id}/reset-password`, { method: "POST", authenticated: true, body: {} });
          teacherPortalShowCredentials(payload.login_id, payload.temporary_password);
        } catch (error) {
          teacherPortalHandleError(error);
        } finally {
          reset.disabled = false;
        }
      });
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "teacher-danger-button teacher-small-button";
      remove.textContent = "所属解除";
      remove.addEventListener("click", async () => {
        const group = teacherPortalActiveGroup();
        if (group === null) throw new Error("Cannot remove member without a selected group.");
        if (!window.confirm(`${member.login_id} を ${group.name} から外しますか？`)) return;
        remove.disabled = true;
        try {
          await apiRequest(`/groups/${group.group_id}/members/${member.user_id}`, { method: "DELETE", authenticated: true });
          await teacherPortalRefreshGroupData();
        } catch (error) {
          teacherPortalHandleError(error);
        } finally {
          remove.disabled = false;
        }
      });
      actions.append(reset, remove);
      row.append(actions);
    }
    teacherPortalMembersList.append(row);
  }
}

function teacherPortalShowCredentials(loginId, temporaryPassword) {
  if (typeof loginId !== "string" || loginId.length === 0 || typeof temporaryPassword !== "string" || temporaryPassword.length === 0) {
    throw new Error("Credential response is missing ID or temporary password.");
  }
  teacherPortalIssuedLogin.textContent = loginId;
  teacherPortalIssuedPassword.textContent = temporaryPassword;
  show(teacherPortalIssuedCredentials);
}

async function teacherPortalRefreshGroupData() {
  teacherPortalSetError(teacherPortalGlobalError, null);
  const group = teacherPortalActiveGroup();
  teacherPortalUpdateGroupLabels();
  if (group === null) {
    teacherPortalState.reviewApps = [];
    teacherPortalState.publishedApps = [];
    teacherPortalState.members = [];
    teacherPortalRenderReviewApps();
    teacherPortalRenderPublishedApps();
    teacherPortalRenderMembers();
    return;
  }

  const [reviewPayload, publishedPayload, membersPayload] = await Promise.all([
    apiRequest(`/groups/${group.group_id}/review-queue`, { authenticated: true }),
    apiRequest("/mobile/apps", { authenticated: true }),
    apiRequest(`/groups/${group.group_id}/members`, { authenticated: true }),
  ]);
  if (!Array.isArray(reviewPayload.apps)) throw new Error("Review queue response has no apps array.");
  if (!Array.isArray(publishedPayload.apps)) throw new Error("Published apps response has no apps array.");
  if (!Array.isArray(membersPayload.members)) throw new Error("Members response has no members array.");

  for (const app of reviewPayload.apps) teacherPortalValidateReviewApp(app);
  const published = publishedPayload.apps.filter((app) => app.group_id === group.group_id);
  for (const app of published) teacherPortalValidatePublishedApp(app);
  for (const member of membersPayload.members) teacherPortalValidateMember(member);

  teacherPortalState.reviewApps = reviewPayload.apps;
  teacherPortalState.publishedApps = published;
  teacherPortalState.members = membersPayload.members;
  teacherPortalRenderReviewApps();
  teacherPortalRenderPublishedApps();
  teacherPortalRenderMembers();
}

async function teacherPortalReloadIdentity() {
  const payload = await apiRequest("/me", { authenticated: true });
  validateMe(payload);
  if (payload.user.role !== "teacher") throw new Error("Teacher account changed to a non-teacher role.");
  currentUser = payload.user;
  currentGroups = payload.groups;
  teacherPortalSetGroups();
  teacherPortalUpdateIdentity();
  await teacherPortalRefreshGroupData();
}

function teacherPortalSetView(view) {
  const allowed = new Set(["home", "reviews", "members", "settings"]);
  if (!allowed.has(view)) throw new Error(`Unsupported teacher view: ${view}`);
  for (const element of teacherPortalRoot.querySelectorAll(".teacher-view")) {
    if (!(element instanceof HTMLElement)) throw new Error("Teacher view node is not an HTMLElement.");
    element.classList.toggle("hidden", element.id !== `teacher-view-${view}`);
  }
  for (const item of teacherPortalRoot.querySelectorAll("[data-teacher-view]")) {
    if (!(item instanceof HTMLButtonElement)) throw new Error("Teacher navigation item is not a button.");
    item.classList.toggle("teacher-nav-item-active", item.dataset.teacherView === view);
  }
  teacherPortalRoot.classList.remove("teacher-sidebar-open");
}

async function teacherPortalOpenPreview(app, canApprove) {
  phase2ValidateApp(app);
  teacherPortalState.previewApp = app;
  teacherPortalState.previewCanApprove = canApprove;
  teacherPortalPreviewTitle.textContent = app.title;
  teacherPortalPreviewDescription.textContent = typeof app.description === "string" ? app.description : "アプリの説明はありません。";
  teacherPortalPreviewOwner.textContent = `◉ ${app.owner_login_id}`;
  teacherPortalPreviewFilename.textContent = `▣ ${app.filename}`;
  teacherPortalPreviewStatus.textContent = canApprove ? "確認待ち" : "公開中";
  teacherPortalPreviewStatus.classList.toggle("teacher-preview-status-live", !canApprove);
  teacherPortalApproveButton.classList.toggle("hidden", !canApprove);
  teacherPortalPreviewHelp.textContent = canApprove
    ? "左の画面で動作を確認し、問題がなければ承認してください。"
    : "公開中のアプリを安全なプレビュー環境で確認しています。";
  teacherPortalSetError(teacherPortalPreviewError, null);
  teacherPortalPreviewFrame.removeAttribute("src");
  show(teacherPortalPreviewLoading);
  show(teacherPortalPreviewModal);
  document.body.classList.add("teacher-modal-open");

  const payload = await apiRequest(`/apps/${app.app_id}/versions/${app.version_id}/preview`, {
    method: "POST",
    authenticated: true,
    body: {},
  });
  if (typeof payload.url !== "string" || typeof payload.expires_in !== "number") {
    throw new Error("Preview API response is invalid.");
  }
  const url = new URL(payload.url);
  if (url.protocol !== "https:") throw new Error("Preview URL must use HTTPS.");
  teacherPortalPreviewFrame.src = url.toString();
  hide(teacherPortalPreviewLoading);
}

function teacherPortalClosePreview() {
  teacherPortalPreviewFrame.removeAttribute("src");
  hide(teacherPortalPreviewModal);
  hide(teacherPortalPreviewLoading);
  document.body.classList.remove("teacher-modal-open");
  teacherPortalState.previewApp = null;
  teacherPortalState.previewCanApprove = false;
}

async function teacherPortalApproveCurrent() {
  const app = teacherPortalState.previewApp;
  if (app === null || !teacherPortalState.previewCanApprove) throw new Error("No pending app is selected for approval.");
  teacherPortalApproveButton.disabled = true;
  teacherPortalSetError(teacherPortalPreviewError, null);
  try {
    await apiRequest(`/apps/${app.app_id}/versions/${app.version_id}/approve`, {
      method: "POST",
      authenticated: true,
      body: {},
    });
    teacherPortalClosePreview();
    await teacherPortalRefreshGroupData();
  } catch (error) {
    teacherPortalHandleError(error, teacherPortalPreviewError);
  } finally {
    teacherPortalApproveButton.disabled = false;
  }
}

function teacherPortalActivate() {
  if (currentUser === null || currentUser.role !== "teacher") throw new Error("Cannot activate teacher portal for a non-teacher account.");
  teacherPortalSiteHeader.classList.add("teacher-source-hidden");
  teacherPortalPageShell.classList.add("teacher-source-hidden");
  show(teacherPortalRoot);
  teacherPortalSetGroups();
  teacherPortalUpdateIdentity();
  teacherPortalSetView("home");
}

function teacherPortalDeactivate() {
  teacherPortalClosePreview();
  hide(teacherPortalRoot);
  teacherPortalSiteHeader.classList.remove("teacher-source-hidden");
  teacherPortalPageShell.classList.remove("teacher-source-hidden");
  teacherPortalRoot.classList.remove("teacher-sidebar-open");
}

for (const navItem of teacherPortalRoot.querySelectorAll("[data-teacher-view]")) {
  if (!(navItem instanceof HTMLButtonElement)) throw new Error("Teacher navigation item is not a button.");
  navItem.addEventListener("click", () => teacherPortalSetView(navItem.dataset.teacherView));
}

teacherPortalClassSelect.addEventListener("change", async () => {
  teacherPortalState.selectedGroupId = teacherPortalClassSelect.value;
  hide(teacherPortalIssuedCredentials);
  try {
    await teacherPortalRefreshGroupData();
  } catch (error) {
    teacherPortalHandleError(error);
  }
});

teacherPortalLogout.addEventListener("click", () => {
  clearAuthentication();
  loginIdInput.focus();
});

teacherPortalMobileMenu.addEventListener("click", () => {
  teacherPortalRoot.classList.toggle("teacher-sidebar-open");
});

teacherPortalCreateGroupForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  teacherPortalSetError(teacherPortalCreateGroupError, null);
  const name = teacherPortalGroupName.value;
  if (name !== name.trim() || name.length < 1 || name.length > 60) {
    teacherPortalSetError(teacherPortalCreateGroupError, "クラス名は前後に空白を入れず、1〜60文字で入力してください。");
    return;
  }
  const button = teacherPortalCreateGroupForm.querySelector("button[type='submit']");
  if (!(button instanceof HTMLButtonElement)) throw new Error("Create group submit button was not found.");
  button.disabled = true;
  try {
    await apiRequest("/groups", { method: "POST", authenticated: true, body: { name } });
    teacherPortalGroupName.value = "";
    await teacherPortalReloadIdentity();
  } catch (error) {
    teacherPortalHandleError(error, teacherPortalCreateGroupError);
  } finally {
    button.disabled = false;
  }
});

teacherPortalCreateStudentForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  teacherPortalSetError(teacherPortalCreateStudentError, null);
  const group = teacherPortalActiveGroup();
  if (group === null) {
    teacherPortalSetError(teacherPortalCreateStudentError, "生徒を追加するクラスを選んでください。");
    return;
  }
  const button = teacherPortalCreateStudentForm.querySelector("button[type='submit']");
  if (!(button instanceof HTMLButtonElement)) throw new Error("Create student submit button was not found.");
  button.disabled = true;
  try {
    const payload = await apiRequest(`/groups/${group.group_id}/students`, { method: "POST", authenticated: true, body: {} });
    teacherPortalShowCredentials(payload.login_id, payload.temporary_password);
    await teacherPortalRefreshGroupData();
  } catch (error) {
    teacherPortalHandleError(error, teacherPortalCreateStudentError);
  } finally {
    button.disabled = false;
  }
});

teacherPortalChangeClassroom.addEventListener("click", () => classroomChangeButton.click());
teacherPortalPreviewClose.addEventListener("click", teacherPortalClosePreview);
teacherPortalPreviewMobileClose.addEventListener("click", teacherPortalClosePreview);
teacherPortalPreviewCancel.addEventListener("click", teacherPortalClosePreview);
teacherPortalApproveButton.addEventListener("click", () => teacherPortalApproveCurrent());
teacherPortalPreviewModal.addEventListener("click", (event) => {
  if (event.target === teacherPortalPreviewModal) teacherPortalClosePreview();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !teacherPortalPreviewModal.classList.contains("hidden")) teacherPortalClosePreview();
});

const teacherPortalOriginalClearAuthentication = clearAuthentication;
clearAuthentication = function clearAuthenticationWithTeacherPortal() {
  teacherPortalDeactivate();
  teacherPortalOriginalClearAuthentication();
};

const teacherPortalOriginalLoadDashboard = loadDashboard;
loadDashboard = async function loadDashboardWithTeacherPortal() {
  await teacherPortalOriginalLoadDashboard();
  if (currentUser !== null && currentUser.role === "teacher") {
    teacherPortalActivate();
    try {
      await teacherPortalRefreshGroupData();
    } catch (error) {
      teacherPortalHandleError(error);
    }
  } else {
    teacherPortalDeactivate();
  }
};
