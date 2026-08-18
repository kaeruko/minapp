"use strict";

if (typeof loadDashboard !== "function" || typeof clearAuthentication !== "function") {
  throw new Error("Student dashboard requires app.js to load first.");
}
if (
  typeof phase2Student === "undefined" ||
  typeof previewPanel === "undefined" ||
  typeof previewFrame === "undefined"
) {
  throw new Error("Student dashboard requires phase2.js to load first.");
}

const studentPortalSiteHeader = document.querySelector(".site-header");
const studentPortalPageShell = document.querySelector(".page-shell");
if (!(studentPortalSiteHeader instanceof HTMLElement)) throw new Error("Student portal site header was not found.");
if (!(studentPortalPageShell instanceof HTMLElement)) throw new Error("Student portal page shell was not found.");

const studentPortalRoot = document.createElement("div");
studentPortalRoot.id = "student-portal";
studentPortalRoot.className = "student-portal hidden";
studentPortalRoot.innerHTML = `
  <header class="student-topbar">
    <div class="student-brand">
      <div class="student-brand-mark" aria-hidden="true">✦</div>
      <div>
        <p class="student-brand-name">みんアプ</p>
        <p class="student-brand-subtitle">生徒用ポータル</p>
      </div>
    </div>
    <div class="student-topbar-actions">
      <div class="student-identity">
        <span id="student-classroom-name" class="student-classroom-name"></span>
        <strong id="student-account-name"></strong>
      </div>
      <button id="student-change-classroom" class="student-secondary-button" type="button">教室を変更</button>
      <button id="student-logout" class="student-secondary-button" type="button">ログアウト</button>
    </div>
  </header>

  <main class="student-main">
    <section class="student-hero" aria-labelledby="student-hero-title">
      <div>
        <p class="student-kicker">MY APPS</p>
        <h1 id="student-hero-title">作品を作って、先生に届けよう。</h1>
        <p>作ったWebアプリをZIPでアップロードして、プレビューを確認してから公開申請できます。</p>
      </div>
      <div class="student-flow" aria-label="公開までの流れ">
        <span><b>1</b> アップロード</span>
        <span aria-hidden="true">→</span>
        <span><b>2</b> プレビュー</span>
        <span aria-hidden="true">→</span>
        <span><b>3</b> 公開申請</span>
      </div>
    </section>

    <section class="student-workspace-card" aria-labelledby="student-workspace-title">
      <div class="student-section-heading">
        <div>
          <p class="student-kicker">作品管理</p>
          <h2 id="student-workspace-title">自分の作品</h2>
        </div>
        <p id="student-group-summary" class="student-group-summary"></p>
      </div>
      <div id="student-upload-slot"></div>
    </section>

    <div id="student-preview-slot"></div>
  </main>
`;
document.body.append(studentPortalRoot);

const studentPortalClassroomName = requiredElement("student-classroom-name");
const studentPortalAccountName = requiredElement("student-account-name");
const studentPortalGroupSummary = requiredElement("student-group-summary");
const studentPortalChangeClassroom = requiredElement("student-change-classroom");
const studentPortalLogout = requiredElement("student-logout");
const studentUploadSlot = requiredElement("student-upload-slot");
const studentPreviewSlot = requiredElement("student-preview-slot");

if (!(studentPortalChangeClassroom instanceof HTMLButtonElement)) throw new Error("#student-change-classroom must be a button.");
if (!(studentPortalLogout instanceof HTMLButtonElement)) throw new Error("#student-logout must be a button.");

studentUploadSlot.append(phase2Student);
studentPreviewSlot.append(previewPanel);
phase2Student.classList.add("student-phase2-workspace");
previewPanel.classList.add("student-preview-panel");

function studentPortalUpdateIdentity() {
  if (currentUser === null || currentUser.role !== "student") {
    throw new Error("Student portal requires an authenticated student.");
  }

  const displayName =
    typeof currentUser.display_name === "string" && currentUser.display_name.length > 0
      ? currentUser.display_name
      : currentUser.login_id;
  studentPortalAccountName.textContent = displayName;
  studentPortalClassroomName.textContent = currentTenant === null ? "みんアプ" : currentTenant.display_name;

  const groups = currentGroups.filter((group) => group.role === "student" && group.status === "active");
  studentPortalGroupSummary.textContent =
    groups.length === 0
      ? "参加中のクラスはありません"
      : groups.length === 1
        ? groups[0].name
        : `${groups.length}クラスに参加中`;
}

function studentPortalActivate() {
  if (currentUser === null || currentUser.role !== "student") {
    throw new Error("Cannot activate student portal for a non-student account.");
  }
  studentPortalUpdateIdentity();
  studentPortalSiteHeader.classList.add("student-source-hidden");
  studentPortalPageShell.classList.add("student-source-hidden");
  show(phase2Student);
  show(studentPortalRoot);
}

function studentPortalDeactivate() {
  previewFrame.removeAttribute("src");
  hide(previewPanel);
  hide(studentPortalRoot);
  studentPortalSiteHeader.classList.remove("student-source-hidden");
  studentPortalPageShell.classList.remove("student-source-hidden");
}

studentPortalChangeClassroom.addEventListener("click", () => classroomChangeButton.click());
studentPortalLogout.addEventListener("click", () => logoutButton.click());

const studentPortalOriginalClearAuthentication = clearAuthentication;
clearAuthentication = function clearAuthenticationWithStudentPortal() {
  studentPortalDeactivate();
  studentPortalOriginalClearAuthentication();
};

const studentPortalOriginalLoadDashboard = loadDashboard;
loadDashboard = async function loadDashboardWithStudentPortal() {
  await studentPortalOriginalLoadDashboard();
  if (currentUser !== null && currentUser.role === "student") {
    studentPortalActivate();
  } else {
    studentPortalDeactivate();
  }
};
