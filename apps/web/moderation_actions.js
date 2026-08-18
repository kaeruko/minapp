"use strict";

if (
  typeof phase2StatusLabel !== "function" ||
  typeof phase2AppCard !== "function" ||
  typeof phase4ValidateLifecycleApp !== "function" ||
  typeof phase4UploadVersion !== "function" ||
  typeof teacherPortalRenderPublishedApps !== "function" ||
  typeof teacherPortalOpenPreview !== "function" ||
  typeof teacherPortalClosePreview !== "function" ||
  typeof teacherPortalRefreshGroupData !== "function"
) {
  throw new Error("Moderation actions require the Phase 2, Phase 4, and teacher dashboard scripts.");
}
if (!(teacherPortalPreviewCancel instanceof HTMLButtonElement)) {
  throw new Error("Teacher preview reject button is missing.");
}

const moderationOriginalStatusLabel = phase2StatusLabel;
phase2StatusLabel = function moderationStatusLabel(status) {
  if (status === "unpublished") return "公開停止中";
  return moderationOriginalStatusLabel(status);
};

const moderationOriginalAppCard = phase2AppCard;
phase2AppCard = function moderationLifecycleAppCard(app, teacherReview) {
  const card = moderationOriginalAppCard(app, teacherReview);
  if (teacherReview) return card;

  phase4ValidateLifecycleApp(app);
  if (["rejected", "unpublished"].includes(app.status)) {
    const badge = card.querySelector(".phase4-version-badge");
    if (!(badge instanceof HTMLElement)) throw new Error("作品カードのバージョン表示が見つかりません。");
    badge.textContent = app.status === "rejected" ? "差し戻し" : "公開停止中";
  }

  if (!app.is_latest_version || !["rejected", "unpublished"].includes(app.status)) return card;
  const actions = card.querySelector(".phase2-actions");
  if (!(actions instanceof HTMLElement)) throw new Error("作品カードの操作欄が見つかりません。");

  const fileInput = document.createElement("input");
  fileInput.type = "file";
  fileInput.accept = ".zip,application/zip";
  fileInput.className = "phase4-hidden-file";
  fileInput.setAttribute("aria-label", `${app.title} の修正版ZIP`);

  const updateButton = document.createElement("button");
  updateButton.type = "button";
  updateButton.className = "button button-quiet button-small";
  updateButton.textContent = app.status === "rejected" ? "修正版をアップロード" : "更新版をアップロード";
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
  actions.prepend(updateButton);
  actions.append(fileInput);
  return card;
};

async function moderationRejectCurrent() {
  const app = teacherPortalState.previewApp;
  if (app === null || !teacherPortalState.previewCanApprove) {
    throw new Error("No pending app is selected for rejection.");
  }

  teacherPortalPreviewCancel.disabled = true;
  teacherPortalApproveButton.disabled = true;
  teacherPortalSetError(teacherPortalPreviewError, null);
  try {
    await apiRequest(`/apps/${app.app_id}/versions/${app.version_id}/reject`, {
      method: "POST",
      authenticated: true,
      body: {},
    });
    teacherPortalClosePreview();
    await teacherPortalRefreshGroupData();
  } catch (error) {
    teacherPortalHandleError(error, teacherPortalPreviewError);
  } finally {
    teacherPortalPreviewCancel.disabled = false;
    teacherPortalApproveButton.disabled = false;
  }
}

teacherPortalPreviewCancel.textContent = "↩ 差し戻す（公開しない）";
teacherPortalPreviewCancel.classList.add("teacher-reject-button");
teacherPortalPreviewCancel.addEventListener(
  "click",
  (event) => {
    event.preventDefault();
    event.stopImmediatePropagation();
    moderationRejectCurrent().catch((error) => teacherPortalHandleError(error, teacherPortalPreviewError));
  },
  true,
);

const moderationOriginalOpenPreview = teacherPortalOpenPreview;
teacherPortalOpenPreview = async function moderationOpenPreview(app, canApprove) {
  teacherPortalPreviewCancel.classList.toggle("hidden", !canApprove);
  return moderationOriginalOpenPreview(app, canApprove);
};

async function moderationUnpublishApp(app, button) {
  if (!window.confirm(`「${app.title}」の公開を停止しますか？\nクラスのアプリ一覧から非表示になります。`)) return;
  button.disabled = true;
  teacherPortalSetError(teacherPortalGlobalError, null);
  try {
    await apiRequest(`/apps/${app.app_id}/versions/${app.version_id}/unpublish`, {
      method: "POST",
      authenticated: true,
      body: {},
    });
    await teacherPortalRefreshGroupData();
  } catch (error) {
    teacherPortalHandleError(error);
  } finally {
    button.disabled = false;
  }
}

const moderationOriginalRenderPublishedApps = teacherPortalRenderPublishedApps;
teacherPortalRenderPublishedApps = function moderationRenderPublishedApps() {
  moderationOriginalRenderPublishedApps();
  if (teacherPortalState.publishedApps.length === 0) return;

  const rows = Array.from(teacherPortalPublishedList.querySelectorAll(".teacher-table-row:not(.teacher-table-header)"));
  if (rows.length !== teacherPortalState.publishedApps.length) {
    throw new Error("Published app table row count does not match app data.");
  }

  rows.forEach((row, index) => {
    if (!(row instanceof HTMLElement)) throw new Error("Published app row is not an HTMLElement.");
    const actionCell = row.lastElementChild;
    if (!(actionCell instanceof HTMLElement)) throw new Error("Published app action cell is missing.");
    const app = teacherPortalState.publishedApps[index];
    const stopButton = document.createElement("button");
    stopButton.type = "button";
    stopButton.className = "teacher-table-action teacher-unpublish-action";
    stopButton.textContent = "公開を停止する";
    stopButton.addEventListener("click", () => {
      moderationUnpublishApp(app, stopButton).catch((error) => teacherPortalHandleError(error));
    });
    actionCell.replaceChildren(stopButton);
  });
};
