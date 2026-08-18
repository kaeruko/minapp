"use strict";

if (
  typeof loadDashboard !== "function" ||
  typeof clearAuthentication !== "function" ||
  typeof classroomChangeButton === "undefined" ||
  typeof logoutButton === "undefined" ||
  typeof teacherPortalRoot === "undefined" ||
  typeof studentPortalRoot === "undefined"
) {
  throw new Error("Shared portal shell requires the authenticated Web portal modules.");
}

const PORTAL_NAVIGATION = {
  teacher: [
    { id: "home", label: "ホーム", icon: "⌂" },
    { id: "reviews", label: "申請の確認", icon: "◉", badge: "reviews" },
    { id: "members", label: "クラス・生徒管理", icon: "♟" },
    { id: "settings", label: "設定", icon: "⚙" },
  ],
  student: [
    { id: "home", label: "ホーム", icon: "⌂" },
    { id: "upload", label: "作品をアップロード", icon: "＋" },
    { id: "apps", label: "自分の作品", icon: "◆" },
    { id: "settings", label: "設定", icon: "⚙" },
  ],
};

const PORTAL_PAGE_TITLES = {
  teacher: {
    home: "ホーム",
    reviews: "申請の確認",
    members: "クラス・生徒管理",
    settings: "設定",
  },
  student: {
    home: "ホーム",
    upload: "作品をアップロード",
    apps: "自分の作品",
    settings: "設定",
  },
};

const portalShellRoot = document.createElement("div");
portalShellRoot.id = "portal-shell";
portalShellRoot.className = "portal-shell hidden";
portalShellRoot.innerHTML = `
  <aside class="portal-shell-sidebar" aria-label="みんアプ メニュー">
    <div class="portal-shell-brand">
      <div class="portal-shell-brand-mark" aria-hidden="true">👥</div>
      <div>
        <p class="portal-shell-brand-name">みんアプ</p>
        <p class="portal-shell-brand-context" id="portal-shell-brand-context"></p>
      </div>
    </div>
    <nav id="portal-shell-nav" class="portal-shell-nav" aria-label="メインメニュー"></nav>
    <div class="portal-shell-account">
      <div class="portal-shell-account-card">
        <div id="portal-shell-avatar" class="portal-shell-avatar" aria-hidden="true"></div>
        <div class="portal-shell-account-copy">
          <strong id="portal-shell-account-name"></strong>
          <span id="portal-shell-role-label"></span>
          <span id="portal-shell-classroom-name"></span>
        </div>
      </div>
      <button id="portal-shell-change-classroom" class="portal-shell-secondary-action" type="button">教室を変更</button>
      <button id="portal-shell-logout" class="portal-shell-logout" type="button">↪ ログアウト</button>
    </div>
  </aside>

  <div id="portal-shell-scrim" class="portal-shell-scrim" aria-hidden="true"></div>

  <div class="portal-shell-main">
    <header class="portal-shell-topbar">
      <div class="portal-shell-title-wrap">
        <button id="portal-shell-menu" class="portal-shell-menu" type="button" aria-label="メニューを開く" aria-expanded="false">☰</button>
        <div>
          <p id="portal-shell-role-context" class="portal-shell-role-context"></p>
          <h1 id="portal-shell-title">ホーム</h1>
        </div>
      </div>
      <div id="portal-shell-topbar-actions" class="portal-shell-topbar-actions"></div>
    </header>
    <main id="portal-shell-content" class="portal-shell-content"></main>
  </div>
`;
document.body.append(portalShellRoot);

const portalShellNav = requiredElement("portal-shell-nav");
const portalShellBrandContext = requiredElement("portal-shell-brand-context");
const portalShellAvatar = requiredElement("portal-shell-avatar");
const portalShellAccountName = requiredElement("portal-shell-account-name");
const portalShellRoleLabel = requiredElement("portal-shell-role-label");
const portalShellClassroomName = requiredElement("portal-shell-classroom-name");
const portalShellChangeClassroom = requiredElement("portal-shell-change-classroom");
const portalShellLogout = requiredElement("portal-shell-logout");
const portalShellMenu = requiredElement("portal-shell-menu");
const portalShellScrim = requiredElement("portal-shell-scrim");
const portalShellRoleContext = requiredElement("portal-shell-role-context");
const portalShellTitle = requiredElement("portal-shell-title");
const portalShellTopbarActions = requiredElement("portal-shell-topbar-actions");
const portalShellContent = requiredElement("portal-shell-content");

if (!(portalShellNav instanceof HTMLElement)) throw new Error("#portal-shell-nav must be an element.");
if (!(portalShellChangeClassroom instanceof HTMLButtonElement)) throw new Error("#portal-shell-change-classroom must be a button.");
if (!(portalShellLogout instanceof HTMLButtonElement)) throw new Error("#portal-shell-logout must be a button.");
if (!(portalShellMenu instanceof HTMLButtonElement)) throw new Error("#portal-shell-menu must be a button.");

const portalShellState = {
  role: null,
  view: null,
  mountedRoot: null,
};

const teacherClassPicker = teacherPortalClassSelect.closest("label");
if (!(teacherClassPicker instanceof HTMLElement)) {
  throw new Error("Teacher class picker was not found.");
}
teacherClassPicker.classList.add("portal-shell-class-picker");

const studentHero = studentPortalRoot.querySelector(".student-hero");
const studentWorkspace = studentPortalRoot.querySelector(".student-workspace-card");
const studentProfile = studentPortalRoot.querySelector(".student-profile-card");
const studentListSection = phase2Student.querySelector(".phase2-list-section");
const studentWorkspaceTitle = studentPortalRoot.querySelector("#student-workspace-title");
if (!(studentHero instanceof HTMLElement)) throw new Error("Student hero was not found.");
if (!(studentWorkspace instanceof HTMLElement)) throw new Error("Student workspace was not found.");
if (!(studentProfile instanceof HTMLElement)) throw new Error("Student profile was not found.");
if (!(studentListSection instanceof HTMLElement)) throw new Error("Student app list was not found.");
if (!(studentWorkspaceTitle instanceof HTMLElement)) throw new Error("Student workspace title was not found.");

function portalShellDisplayName() {
  if (currentUser === null) throw new Error("Portal shell requires an authenticated user.");
  if (typeof displayNameState !== "undefined" && displayNameState.selfName !== null) {
    return displayNameState.selfName;
  }
  return currentUser.login_id;
}

function portalShellCloseNavigation() {
  portalShellRoot.classList.remove("portal-shell-nav-open");
  portalShellMenu.setAttribute("aria-expanded", "false");
}

function portalShellToggleNavigation() {
  const open = !portalShellRoot.classList.contains("portal-shell-nav-open");
  portalShellRoot.classList.toggle("portal-shell-nav-open", open);
  portalShellMenu.setAttribute("aria-expanded", String(open));
}

function portalShellSyncIdentity() {
  if (currentUser === null || !["teacher", "student"].includes(currentUser.role)) {
    throw new Error("Portal shell received an unsupported authenticated role.");
  }
  const name = portalShellDisplayName();
  const roleLabel = currentUser.role === "teacher" ? "先生" : "生徒";
  const classroom = currentTenant === null ? "みんアプ" : currentTenant.display_name;
  portalShellAccountName.textContent = name;
  portalShellRoleLabel.textContent = roleLabel;
  portalShellClassroomName.textContent = classroom;
  portalShellBrandContext.textContent = classroom;
  portalShellRoleContext.textContent = roleLabel;
  portalShellAvatar.textContent = name.slice(0, 1).toUpperCase() || (currentUser.role === "teacher" ? "先" : "生");
}

function portalShellReviewBadgeValue() {
  const raw = teacherPortalNavReviewCount.textContent.trim();
  if (raw.length === 0 || teacherPortalNavReviewCount.classList.contains("hidden")) return null;
  return raw;
}

function portalShellSyncReviewBadge() {
  const badge = portalShellNav.querySelector("[data-portal-badge='reviews']");
  if (!(badge instanceof HTMLElement)) return;
  const value = portalShellReviewBadgeValue();
  badge.textContent = value ?? "";
  badge.classList.toggle("hidden", value === null);
}

function portalShellRenderNavigation(role) {
  const navigation = PORTAL_NAVIGATION[role];
  if (!Array.isArray(navigation)) throw new Error(`Unsupported portal role: ${role}`);
  portalShellNav.replaceChildren();
  for (const item of navigation) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "portal-shell-nav-item";
    button.dataset.portalView = item.id;

    const icon = document.createElement("span");
    icon.className = "portal-shell-nav-icon";
    icon.setAttribute("aria-hidden", "true");
    icon.textContent = item.icon;
    const label = document.createElement("span");
    label.textContent = item.label;
    button.append(icon, label);

    if (item.badge !== undefined) {
      const badge = document.createElement("span");
      badge.className = "portal-shell-nav-badge hidden";
      badge.dataset.portalBadge = item.badge;
      button.append(badge);
    }

    button.addEventListener("click", () => portalShellSetView(item.id));
    portalShellNav.append(button);
  }
  if (role === "teacher") portalShellSyncReviewBadge();
}

function portalShellSetActiveNavigation(view) {
  for (const button of portalShellNav.querySelectorAll("[data-portal-view]")) {
    if (!(button instanceof HTMLButtonElement)) throw new Error("Portal navigation item must be a button.");
    const active = button.dataset.portalView === view;
    button.classList.toggle("portal-shell-nav-item-active", active);
    if (active) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  }
}

function portalShellSetStudentView(view) {
  const allowed = new Set(["home", "upload", "apps", "settings"]);
  if (!allowed.has(view)) throw new Error(`Unsupported student view: ${view}`);

  const isHome = view === "home";
  const isUpload = view === "upload";
  const isApps = view === "apps";
  const isSettings = view === "settings";

  studentHero.classList.toggle("hidden", !isHome);
  studentWorkspace.classList.toggle("hidden", isSettings);
  studentProfile.classList.toggle("hidden", !isSettings);
  uploadForm.classList.toggle("hidden", !(isUpload));
  studentListSection.classList.toggle("hidden", !(isHome || isApps));
  studentWorkspaceTitle.textContent = isUpload ? "作品をアップロード" : "自分の作品";

  if (isSettings) {
    previewFrame.removeAttribute("src");
    hide(previewPanel);
  }
}

function portalShellSetView(view) {
  const role = portalShellState.role;
  if (role === null) throw new Error("Cannot change portal view without an active role.");
  const title = PORTAL_PAGE_TITLES[role]?.[view];
  if (typeof title !== "string") throw new Error(`Unsupported ${role} portal view: ${view}`);

  if (role === "teacher") {
    teacherPortalSetView(view);
  } else if (role === "student") {
    portalShellSetStudentView(view);
  } else {
    throw new Error(`Unsupported portal role: ${role}`);
  }

  portalShellState.view = view;
  portalShellTitle.textContent = title;
  portalShellSetActiveNavigation(view);
  portalShellCloseNavigation();
  portalShellContent.scrollTo({ top: 0, behavior: "auto" });
}

function portalShellMountRole(role) {
  if (role === "teacher") {
    portalShellContent.append(teacherPortalRoot);
    portalShellTopbarActions.replaceChildren(teacherClassPicker);
    portalShellState.mountedRoot = teacherPortalRoot;
    return;
  }
  if (role === "student") {
    portalShellContent.append(studentPortalRoot);
    portalShellTopbarActions.replaceChildren();
    portalShellState.mountedRoot = studentPortalRoot;
    return;
  }
  throw new Error(`Unsupported portal role: ${role}`);
}

function portalShellActivate() {
  if (currentUser === null || !["teacher", "student"].includes(currentUser.role)) {
    throw new Error("Cannot activate shared portal shell without a supported authenticated role.");
  }
  portalShellState.role = currentUser.role;
  portalShellRoot.dataset.role = currentUser.role;
  portalShellRenderNavigation(currentUser.role);
  portalShellMountRole(currentUser.role);
  portalShellSyncIdentity();
  document.body.classList.add("portal-shell-active");
  show(portalShellRoot);
  portalShellSetView("home");
}

function portalShellDeactivate() {
  portalShellCloseNavigation();
  if (portalShellState.mountedRoot instanceof HTMLElement) {
    document.body.append(portalShellState.mountedRoot);
  }
  portalShellTopbarActions.replaceChildren();
  hide(portalShellRoot);
  document.body.classList.remove("portal-shell-active");
  delete portalShellRoot.dataset.role;
  portalShellState.role = null;
  portalShellState.view = null;
  portalShellState.mountedRoot = null;
}

portalShellMenu.addEventListener("click", portalShellToggleNavigation);
portalShellScrim.addEventListener("click", portalShellCloseNavigation);
portalShellChangeClassroom.addEventListener("click", () => classroomChangeButton.click());
portalShellLogout.addEventListener("click", () => logoutButton.click());
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") portalShellCloseNavigation();
});

const portalShellReviewObserver = new MutationObserver(() => portalShellSyncReviewBadge());
portalShellReviewObserver.observe(teacherPortalNavReviewCount, {
  childList: true,
  characterData: true,
  subtree: true,
  attributes: true,
  attributeFilter: ["class"],
});

const portalShellOriginalClearAuthentication = clearAuthentication;
clearAuthentication = function clearAuthenticationWithSharedPortalShell() {
  portalShellDeactivate();
  portalShellOriginalClearAuthentication();
};

const portalShellOriginalLoadDashboard = loadDashboard;
loadDashboard = async function loadDashboardWithSharedPortalShell() {
  await portalShellOriginalLoadDashboard();
  if (currentUser === null) {
    portalShellDeactivate();
    return;
  }
  portalShellActivate();
};
