"use strict";

if (typeof phase2AppCard !== "function" || typeof phase2LoadMyApps !== "function") {
  throw new Error("Phase 4 requires phase2.js to load first.");
}

function phase4ValidateLifecycleApp(app) {
  phase2ValidateApp(app);
  if (!Number.isInteger(app.version_number) || app.version_number < 1 || !Number.isInteger(app.version_count) || app.version_count < app.version_number || typeof app.is_latest_version !== "boolean" || typeof app.is_published !== "boolean" || app.app_status !== "active") {
    throw new Error("作品管理APIのレスポンス形式が不正です。");
  }
}

async function phase4UploadVersion(app, file, button) {
  if (!(file instanceof File)) throw new TypeError("更新版はFileである必要があります。");
  if (!file.name.toLowerCase().endsWith(".zip")) throw new Error("拡張子 .zip のファイルを選んでください。");
  if (file.size <= 0 || file.size > PHASE2_MAX_ZIP_BYTES) throw new Error("ZIPファイルは0バイトより大きく、2MB以下にしてください。");
  button.disabled = true;
  try {
    const params = new URLSearchParams({ filename: file.name });
    const payload = await phase2BinaryUpload(`/apps/${app.app_id}/versions?${params.toString()}`, file);
    phase4ValidateLifecycleApp(payload);
    phase2SetMessage(uploadResult, `${app.title} の更新版をアップロードしました。プレビューして公開申請してください。`);
    await phase2LoadMyApps();
  } finally {
    button.disabled = false;
  }
}

async function phase4ArchiveApp(app, button) {
  const confirmed = window.confirm(`「${app.title}」を削除しますか？\nAndroidの一覧からも非公開になります。`);
  if (!confirmed) return;
  button.disabled = true;
  try {
    await apiRequest(`/apps/${app.app_id}`, { method: "DELETE", authenticated: true });
    previewFrame.removeAttribute("src");
    hide(previewPanel);
    phase2SetMessage(uploadResult, `${app.title} を削除しました。`);
    await phase2LoadMyApps();
  } finally {
    button.disabled = false;
  }
}

const phase4OriginalAppCard = phase2AppCard;
phase2AppCard = function phase4AppCard(app, teacherReview) {
  const card = phase4OriginalAppCard(app, teacherReview);
  if (teacherReview) return card;

  phase4ValidateLifecycleApp(app);
  const meta = card.querySelector(".member-meta");
  if (!(meta instanceof HTMLElement)) throw new Error("作品カードのメタ情報が見つかりません。");
  meta.textContent += ` · v${app.version_number}`;

  const badge = document.createElement("span");
  badge.className = "phase4-version-badge";
  if (app.is_published) {
    badge.textContent = "公開中";
    badge.classList.add("phase4-version-badge-live");
  } else if (app.status === "approved") {
    badge.textContent = "旧バージョン";
  } else if (app.is_latest_version) {
    badge.textContent = "最新版";
  } else {
    badge.textContent = "過去版";
  }
  meta.after(badge);

  if (!app.is_latest_version) return card;
  const actions = card.querySelector(".phase2-actions");
  if (!(actions instanceof HTMLElement)) throw new Error("作品カードの操作欄が見つかりません。");

  if (app.status === "approved") {
    const fileInput = document.createElement("input");
    fileInput.type = "file";
    fileInput.accept = ".zip,application/zip";
    fileInput.className = "phase4-hidden-file";
    fileInput.setAttribute("aria-label", `${app.title} の更新版ZIP`);
    const updateButton = document.createElement("button");
    updateButton.type = "button";
    updateButton.className = "button button-quiet button-small";
    updateButton.textContent = "更新版をアップロード";
    updateButton.addEventListener("click", () => fileInput.click());
    fileInput.addEventListener("change", async () => {
      phase2SetMessage(myAppError, null);
      try {
        if (fileInput.files === null || fileInput.files.length !== 1) return;
        await phase4UploadVersion(app, fileInput.files[0], updateButton);
      } catch (error) {
        phase2SetMessage(myAppError, apiErrorMessage(error));
      } finally {
        fileInput.value = "";
      }
    });
    actions.append(updateButton, fileInput);
  }

  if (app.status !== "pending_review") {
    const deleteButton = document.createElement("button");
    deleteButton.type = "button";
    deleteButton.className = "button button-small phase4-delete-button";
    deleteButton.textContent = "作品を削除";
    deleteButton.addEventListener("click", async () => {
      phase2SetMessage(myAppError, null);
      try {
        await phase4ArchiveApp(app, deleteButton);
      } catch (error) {
        phase2SetMessage(myAppError, apiErrorMessage(error));
      }
    });
    actions.append(deleteButton);
  }
  return card;
};

phase2LoadMyApps = async function phase4LoadMyApps() {
  phase2SetMessage(myAppError, null);
  myAppList.replaceChildren();
  const payload = await apiRequest("/lifecycle/apps", { authenticated: true });
  if (!Array.isArray(payload.apps)) throw new Error("作品管理APIにapps配列がありません。");
  if (payload.apps.length === 0) {
    show(myAppEmpty);
    return;
  }
  hide(myAppEmpty);
  for (const app of payload.apps) {
    phase4ValidateLifecycleApp(app);
    myAppList.append(phase2AppCard(app, false));
  }
};
