"use strict";

const PHASE2_MAX_ZIP_BYTES = 2 * 1024 * 1024;

const phase2Panel = document.createElement("section");
phase2Panel.id = "phase2-panel";
phase2Panel.className = "panel";
phase2Panel.innerHTML = `
  <div class="section-heading">
    <div>
      <p class="eyebrow">作品</p>
      <h2>Webアプリを共有</h2>
      <p class="muted">ZIP直下に index.html を入れてください。MVPではZIPは2MBまでです。</p>
    </div>
  </div>

  <section id="phase2-student" class="phase2-section hidden">
    <form id="app-upload-form" class="subpanel form-stack">
      <h3>作品をアップロード</h3>
      <label>グループ<select id="app-upload-group" required></select></label>
      <label>作品名<input id="app-title" maxlength="80" placeholder="例: ねんね組の時間割" required /></label>
      <label>ZIPファイル<input id="app-zip" type="file" accept=".zip,application/zip" required /></label>
      <button class="button" type="submit">ZIPをアップロード</button>
      <p id="app-upload-error" class="form-error hidden" role="alert"></p>
      <p id="app-upload-result" class="phase2-success hidden" role="status"></p>
    </form>

    <section class="phase2-list-section">
      <div><p class="eyebrow">自分の作品</p><h3>アップロードした作品</h3></div>
      <div id="my-app-list" class="phase2-list"></div>
      <p id="my-app-empty" class="muted hidden">まだ作品がありません。</p>
      <p id="my-app-error" class="form-error hidden" role="alert"></p>
    </section>
  </section>

  <section id="phase2-teacher" class="phase2-section hidden">
    <div class="section-heading">
      <div><p class="eyebrow">公開申請</p><h3>先生の確認待ち</h3></div>
      <select id="review-group" aria-label="公開申請を確認するグループ"></select>
    </div>
    <div id="review-list" class="phase2-list"></div>
    <p id="review-empty" class="muted hidden">このグループには確認待ちの作品がありません。</p>
    <p id="review-error" class="form-error hidden" role="alert"></p>
  </section>

  <section id="preview-panel" class="preview-panel hidden" aria-labelledby="preview-title">
    <div class="section-heading">
      <div><p class="eyebrow">安全プレビュー</p><h3 id="preview-title">作品を確認</h3></div>
      <button id="preview-close" class="button button-quiet button-small" type="button">閉じる</button>
    </div>
    <p class="muted">外部通信を禁止した短時間URLを、sandbox付きiframeで表示しています。</p>
    <iframe id="preview-frame" title="作品プレビュー" sandbox="allow-scripts" referrerpolicy="no-referrer"></iframe>
  </section>
`;
dashboard.append(phase2Panel);

const phase2Student = requiredElement("phase2-student");
const phase2Teacher = requiredElement("phase2-teacher");
const uploadForm = requiredElement("app-upload-form");
const uploadGroup = requiredElement("app-upload-group");
const appTitleInput = requiredElement("app-title");
const appZipInput = requiredElement("app-zip");
const uploadError = requiredElement("app-upload-error");
const uploadResult = requiredElement("app-upload-result");
const myAppList = requiredElement("my-app-list");
const myAppEmpty = requiredElement("my-app-empty");
const myAppError = requiredElement("my-app-error");
const reviewGroup = requiredElement("review-group");
const reviewList = requiredElement("review-list");
const reviewEmpty = requiredElement("review-empty");
const reviewError = requiredElement("review-error");
const previewPanel = requiredElement("preview-panel");
const previewTitle = requiredElement("preview-title");
const previewClose = requiredElement("preview-close");
const previewFrame = requiredElement("preview-frame");

if (!(uploadForm instanceof HTMLFormElement)) throw new Error("#app-upload-form must be a form.");
if (!(uploadGroup instanceof HTMLSelectElement)) throw new Error("#app-upload-group must be a select.");
if (!(appTitleInput instanceof HTMLInputElement)) throw new Error("#app-title must be an input.");
if (!(appZipInput instanceof HTMLInputElement)) throw new Error("#app-zip must be an input.");
if (!(reviewGroup instanceof HTMLSelectElement)) throw new Error("#review-group must be a select.");
if (!(previewFrame instanceof HTMLIFrameElement)) throw new Error("#preview-frame must be an iframe.");

function phase2SetMessage(element, message) {
  if (message === null) {
    element.textContent = "";
    hide(element);
    return;
  }
  element.textContent = message;
  show(element);
}

function phase2Groups(role) {
  return currentGroups.filter((group) => group.role === role && group.status === "active");
}

function phase2SetSelect(select, groups) {
  const previous = select.value;
  select.replaceChildren();
  for (const group of groups) {
    const option = document.createElement("option");
    option.value = group.group_id;
    option.textContent = group.name;
    select.append(option);
  }
  if (groups.some((group) => group.group_id === previous)) select.value = previous;
  select.disabled = groups.length === 0;
}

function phase2StatusLabel(status) {
  const labels = {
    draft: "下書き",
    pending_review: "先生の確認待ち",
    approved: "承認済み",
    rejected: "差し戻し",
  };
  if (!(status in labels)) throw new Error(`Unsupported app status: ${status}`);
  return labels[status];
}

function phase2ValidateApp(item) {
  if (
    typeof item !== "object" ||
    item === null ||
    typeof item.app_id !== "string" ||
    typeof item.version_id !== "string" ||
    typeof item.group_id !== "string" ||
    typeof item.group_name !== "string" ||
    typeof item.owner_login_id !== "string" ||
    typeof item.title !== "string" ||
    typeof item.filename !== "string" ||
    typeof item.status !== "string" ||
    typeof item.created_at !== "string"
  ) {
    throw new Error("作品APIのレスポンス形式が不正です。");
  }
  phase2StatusLabel(item.status);
}

async function phase2BinaryUpload(path, file) {
  const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
  if (token === null || token.length === 0) {
    throw new ApiError(401, "unauthorized", "ログインが必要です。");
  }
  const response = await fetch(`/api${path}`, {
    method: "POST",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/zip",
    },
    body: file,
    cache: "no-store",
  });
  const contentType = response.headers.get("content-type");
  if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
    throw new Error(`API returned non-JSON response (HTTP ${response.status}).`);
  }
  const payload = await response.json();
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    throw new Error("API returned an unexpected JSON payload.");
  }
  if (!response.ok) {
    throw new ApiError(
      response.status,
      typeof payload.error === "string" ? payload.error : "api_error",
      typeof payload.message === "string" ? payload.message : `HTTP ${response.status}`,
    );
  }
  return payload;
}

async function phase2OpenPreview(app) {
  phase2SetMessage(myAppError, null);
  phase2SetMessage(reviewError, null);
  const payload = await apiRequest(`/apps/${app.app_id}/versions/${app.version_id}/preview`, {
    method: "POST",
    authenticated: true,
    body: {},
  });
  if (typeof payload.url !== "string" || typeof payload.expires_in !== "number") {
    throw new Error("プレビューAPIのレスポンス形式が不正です。");
  }
  const url = new URL(payload.url);
  if (url.protocol !== "https:") throw new Error("プレビューURLはHTTPSである必要があります。");
  previewTitle.textContent = `${app.title} を確認`;
  previewFrame.src = url.toString();
  show(previewPanel);
  previewPanel.scrollIntoView({ behavior: "smooth", block: "start" });
}

previewClose.addEventListener("click", () => {
  previewFrame.removeAttribute("src");
  hide(previewPanel);
});

uploadForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  phase2SetMessage(uploadError, null);
  phase2SetMessage(uploadResult, null);

  const groupId = uploadGroup.value;
  if (groupId.length === 0) {
    phase2SetMessage(uploadError, "アップロード先のグループを選んでください。");
    return;
  }
  const title = appTitleInput.value;
  if (title !== title.trim() || title.length < 1 || title.length > 80) {
    phase2SetMessage(uploadError, "作品名は前後に空白を入れず、1〜80文字で入力してください。");
    return;
  }
  if (appZipInput.files === null || appZipInput.files.length !== 1) {
    phase2SetMessage(uploadError, "ZIPファイルを1つ選んでください。");
    return;
  }
  const file = appZipInput.files[0];
  if (!file.name.toLowerCase().endsWith(".zip")) {
    phase2SetMessage(uploadError, "拡張子 .zip のファイルを選んでください。");
    return;
  }
  if (file.size <= 0 || file.size > PHASE2_MAX_ZIP_BYTES) {
    phase2SetMessage(uploadError, "ZIPファイルは0バイトより大きく、2MB以下にしてください。");
    return;
  }

  const submitButton = uploadForm.querySelector("button[type='submit']");
  if (!(submitButton instanceof HTMLButtonElement)) throw new Error("Upload submit button was not found.");
  submitButton.disabled = true;
  try {
    const params = new URLSearchParams({ title, filename: file.name });
    const payload = await phase2BinaryUpload(`/groups/${groupId}/apps?${params.toString()}`, file);
    phase2ValidateApp(payload);
    appTitleInput.value = "";
    appZipInput.value = "";
    phase2SetMessage(uploadResult, "アップロードできました。内容を確認して「公開申請」を押してください。");
    await phase2LoadMyApps();
  } catch (error) {
    phase2SetMessage(uploadError, apiErrorMessage(error));
  } finally {
    submitButton.disabled = false;
  }
});

async function phase2LoadMyApps() {
  phase2SetMessage(myAppError, null);
  myAppList.replaceChildren();
  const payload = await apiRequest("/apps", { authenticated: true });
  if (!Array.isArray(payload.apps)) throw new Error("作品一覧APIにapps配列がありません。");
  if (payload.apps.length === 0) {
    show(myAppEmpty);
    return;
  }
  hide(myAppEmpty);
  for (const app of payload.apps) {
    phase2ValidateApp(app);
    myAppList.append(phase2AppCard(app, false));
  }
}

function phase2AppCard(app, teacherReview) {
  const card = document.createElement("article");
  card.className = "phase2-app-card";

  const main = document.createElement("div");
  const title = document.createElement("h4");
  title.textContent = app.title;
  const meta = document.createElement("p");
  meta.className = "member-meta";
  meta.textContent = `${app.group_name} · ${app.owner_login_id} · ${phase2StatusLabel(app.status)}`;
  const filename = document.createElement("p");
  filename.className = "phase2-filename";
  filename.textContent = app.filename;
  main.append(title, meta, filename);

  const actions = document.createElement("div");
  actions.className = "phase2-actions";
  const previewButton = document.createElement("button");
  previewButton.type = "button";
  previewButton.className = "button button-quiet button-small";
  previewButton.textContent = "プレビュー";
  previewButton.addEventListener("click", async () => {
    previewButton.disabled = true;
    try {
      await phase2OpenPreview(app);
    } catch (error) {
      phase2SetMessage(teacherReview ? reviewError : myAppError, apiErrorMessage(error));
    } finally {
      previewButton.disabled = false;
    }
  });
  actions.append(previewButton);

  if (!teacherReview && app.status === "draft") {
    const submitButton = document.createElement("button");
    submitButton.type = "button";
    submitButton.className = "button button-small";
    submitButton.textContent = "公開申請";
    submitButton.addEventListener("click", async () => {
      submitButton.disabled = true;
      phase2SetMessage(myAppError, null);
      try {
        await apiRequest(`/apps/${app.app_id}/versions/${app.version_id}/submit`, {
          method: "POST",
          authenticated: true,
          body: {},
        });
        await phase2LoadMyApps();
      } catch (error) {
        phase2SetMessage(myAppError, apiErrorMessage(error));
      } finally {
        submitButton.disabled = false;
      }
    });
    actions.append(submitButton);
  }

  if (teacherReview) {
    const approveButton = document.createElement("button");
    approveButton.type = "button";
    approveButton.className = "button button-small";
    approveButton.textContent = "承認して公開";
    approveButton.addEventListener("click", async () => {
      approveButton.disabled = true;
      phase2SetMessage(reviewError, null);
      try {
        await apiRequest(`/apps/${app.app_id}/versions/${app.version_id}/approve`, {
          method: "POST",
          authenticated: true,
          body: {},
        });
        previewFrame.removeAttribute("src");
        hide(previewPanel);
        await phase2LoadReviewQueue();
      } catch (error) {
        phase2SetMessage(reviewError, apiErrorMessage(error));
      } finally {
        approveButton.disabled = false;
      }
    });
    actions.append(approveButton);
  }

  card.append(main, actions);
  return card;
}

reviewGroup.addEventListener("change", () => {
  phase2LoadReviewQueue().catch((error) => phase2SetMessage(reviewError, apiErrorMessage(error)));
});

async function phase2LoadReviewQueue() {
  phase2SetMessage(reviewError, null);
  reviewList.replaceChildren();
  const groupId = reviewGroup.value;
  if (groupId.length === 0) {
    show(reviewEmpty);
    return;
  }
  const payload = await apiRequest(`/groups/${groupId}/review-queue`, { authenticated: true });
  if (!Array.isArray(payload.apps)) throw new Error("公開申請APIにapps配列がありません。");
  if (payload.apps.length === 0) {
    show(reviewEmpty);
    return;
  }
  hide(reviewEmpty);
  for (const app of payload.apps) {
    phase2ValidateApp(app);
    if (app.status !== "pending_review") throw new Error("公開申請一覧に確認待ち以外の作品があります。");
    reviewList.append(phase2AppCard(app, true));
  }
}

async function phase2Refresh() {
  if (currentUser === null || dashboard.classList.contains("hidden")) return;
  previewFrame.removeAttribute("src");
  hide(previewPanel);

  if (currentUser.role === "student") {
    show(phase2Student);
    hide(phase2Teacher);
    phase2SetSelect(uploadGroup, phase2Groups("student"));
    await phase2LoadMyApps();
    return;
  }

  if (currentUser.role === "teacher") {
    hide(phase2Student);
    show(phase2Teacher);
    phase2SetSelect(reviewGroup, phase2Groups("teacher"));
    await phase2LoadReviewQueue();
    return;
  }

  throw new Error(`Unsupported user role: ${currentUser.role}`);
}

const phase2OriginalLoadDashboard = loadDashboard;
loadDashboard = async function loadDashboardWithPhase2() {
  await phase2OriginalLoadDashboard();
  await phase2Refresh();
};

const phase2DashboardObserver = new MutationObserver(() => {
  if (!dashboard.classList.contains("hidden") && currentUser !== null) {
    phase2Refresh().catch((error) => {
      console.error(error);
      if (currentUser?.role === "teacher") phase2SetMessage(reviewError, apiErrorMessage(error));
      if (currentUser?.role === "student") phase2SetMessage(myAppError, apiErrorMessage(error));
    });
  }
});
phase2DashboardObserver.observe(dashboard, { attributes: true, attributeFilter: ["class"] });

logoutButton.addEventListener("click", () => {
  previewFrame.removeAttribute("src");
  hide(previewPanel);
});
