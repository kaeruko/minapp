# Shared Web portal shell design

## 1. Status

This document defines the target UI architecture for the MinApp Web portal.

Decision:

- MinApp has one Web product and one canonical portal URL.
- Teacher and student accounts do not use separately branded Web applications.
- After authentication, the same portal shell renders role-appropriate navigation and content.
- Teacher-only and student-only feature modules remain separate where their workflows differ.
- Phase 6E classroom routing, tenant isolation, authentication, and direct-browser API behavior are unchanged.
- The Android client remains a separate app-launcher experience for discovering and opening published classroom apps.

Canonical Web URL:

```text
https://minapp.cloxs.jp
```

## 2. Why change the current UI structure

The current Web implementation has evolved into two visually and structurally independent logged-in experiences:

- `teacher_dashboard.js` creates a full teacher portal shell with its own sidebar, top bar, account area, and content layout.
- `student_dashboard.js` creates a separate student portal shell with its own top bar, hero, account actions, and content layout.
- both modules hide the original shared dashboard after login and mount their own root element.

This works functionally, but it duplicates product-level UI responsibilities and makes future changes harder. Brand styling, account controls, classroom switching, logout behavior, responsive navigation, page layout, and accessibility patterns can drift between roles.

The teacher and student workflows are different enough to justify different pages, but not different Web products.

## 3. Goals

The shared shell must:

- present one consistent MinApp identity for teachers and students
- reuse one logged-in layout, navigation system, responsive behavior, account menu, classroom context, error surface, and logout/classroom-switch controls
- derive visible navigation from the authenticated role returned by `/me`
- keep role authorization enforced by the tenant API; hiding UI is not a security boundary
- preserve the existing teacher and student feature behavior during migration
- avoid backend/API/schema changes
- avoid changing Phase 6E tenant routing or browser credential boundaries
- remain usable on classroom PCs, tablets, and narrow mobile browsers
- keep implementation fail-closed: an unknown role or unsupported navigation definition must not silently fall back to another role

## 4. Non-goals

This design does not:

- merge teacher and student permissions
- allow a user to manually switch role in the UI
- change Cognito groups or `/me` response schemas
- change classroom-code resolution
- change tenant API endpoints
- redesign the Android published-app launcher
- require a frontend framework migration
- move tenant application data into the operator portal

## 5. Product model

Use one product name everywhere:

```text
みんアプ
```

Do not use separate product labels such as:

```text
先生用ポータル
生徒用ポータル
```

Role may be shown as secondary account context, for example:

```text
teacher-admin
先生
```

or:

```text
student-99993123
生徒
```

The role describes what the signed-in account can do. It does not create a separate application identity.

## 6. Target UI structure

```text
Browser
  |
  +-- classroom selection
  +-- login / initial password change
  |
  +-- authenticated portal shell
        |
        +-- brand: みんアプ
        +-- classroom context
        +-- role-aware navigation
        +-- page heading / page actions
        +-- page content slot
        +-- account controls
        +-- global error / loading surface
        |
        +-- teacher feature views
        |     +-- home
        |     +-- review requests
        |     +-- class/member management
        |     +-- settings
        |
        +-- student feature views
              +-- home / my apps
              +-- upload app
              +-- my apps / versions
              +-- settings
```

The shell is shared. Feature views are role-specific.

## 7. Shared shell responsibilities

Introduce a shared UI module, tentatively:

```text
apps/web/portal_shell.js
apps/web/portal_shell.css
```

The exact filenames are not API and may change during implementation, but there must be one owner for product-level authenticated layout.

The shell owns:

- MinApp logo / product name
- desktop sidebar or navigation rail
- mobile navigation drawer/menu
- top bar
- account identity and role label
- classroom display
- classroom change action
- logout action
- active navigation state
- page title
- page-level action slot
- common loading state
- common global error area
- responsive layout rules
- keyboard navigation and focus behavior for shell controls

Role modules must not create their own site header, sidebar, top-level account controls, or logout/classroom-switch implementation.

## 8. Role-aware navigation

Navigation is defined from an explicit role configuration after `/me` has been strictly validated.

Example logical definition:

```js
const PORTAL_NAVIGATION = {
  teacher: [
    { id: "home", label: "ホーム" },
    { id: "reviews", label: "申請の確認" },
    { id: "members", label: "クラス・生徒管理" },
    { id: "settings", label: "設定" },
  ],
  student: [
    { id: "home", label: "ホーム" },
    { id: "upload", label: "作品をアップロード" },
    { id: "apps", label: "自分の作品" },
    { id: "settings", label: "設定" },
  ],
};
```

Rules:

- role must be exactly `teacher` or `student`
- unknown roles throw and do not render an authenticated shell
- navigation IDs are fixed application identifiers, not user input
- navigation visibility is a UX concern only; API authorization remains authoritative
- teacher review count may be rendered as a badge in the shared navigation

## 9. Desktop layout

Use the current teacher dashboard as the general desktop layout direction because it already works well for management workflows:

```text
+-------------------+---------------------------------------------+
| みんアプ          | page title                     classroom   |
|                   +---------------------------------------------+
| navigation        |                                             |
|                   | page content                                |
|                   |                                             |
|                   |                                             |
| account           |                                             |
| logout            |                                             |
+-------------------+---------------------------------------------+
```

Teachers and students use the same dimensions, typography system, spacing scale, shell colors, and control styling.

Student pages may remain visually friendlier inside the content area, but they should not replace the entire shell with a second design system.

## 10. Mobile / narrow layout

On narrow screens:

- hide the permanent sidebar
- keep a common top bar with MinApp brand, page title, and menu button
- open the same role-aware navigation in a drawer/menu
- keep classroom change and logout inside the account/menu area
- feature content becomes single-column
- preview modals remain responsive and preserve sandbox behavior

Do not maintain a separate mobile-only role implementation.

## 11. Classroom context

Classroom routing remains a portal-level concern, not a teacher/student module concern.

Shared shell displays the verified tenant `display_name`.

Teacher class/group selection:

- retain the current selected teacher group behavior initially
- place the group selector in the shell page-action/top-bar slot for teacher pages where class context matters
- teacher feature modules own the selected teacher `group_id` state until a later explicit refactor

Student class/group selection:

- do not introduce a new global selected-group semantic as part of the first shell migration
- retain the current upload/group behavior so API semantics do not change silently
- when a student belongs to one active group, display that group as context
- when a student belongs to multiple active groups, the feature that requires a group continues to require an explicit choice

A later change may centralize selected-group state, but it must be designed separately because it changes interaction semantics.

## 12. Page ownership

### Teacher module owns

- pending review cards
- published app table
- safe preview / approval modal
- reject / unpublish actions
- class creation
- student account issuance
- member list and member actions
- teacher-specific data loading and validation

### Student module owns

- upload form
- group choice required for upload
- own app/version list
- preview before submission
- publish request
- rejected/unpublished update upload
- student display-name editing

### Shared shell owns

- all product-level chrome and account/navigation controls
- no teacher-only or student-only business API calls

This separation allows teacher and student workflows to evolve independently without duplicating the Web application frame.

## 13. Login and pre-authentication UI

Classroom selection, login, and initial password change remain one shared flow for all roles.

The portal must not ask the user whether they are a teacher or student before login.

Flow:

```text
classroom code
  -> verified tenant
  -> ID/password
  -> /me
  -> strict role validation
  -> shared shell configured for returned role
```

There is no role selector and no role-specific login URL.

The existing account IDs and passwords remain unchanged.

## 14. State and lifecycle

The current function-wrapping pattern, where role modules replace `loadDashboard` and `clearAuthentication`, should be removed gradually.

Target lifecycle:

```text
loadDashboard()
  -> GET /me
  -> validate user/groups
  -> portalShell.activate({ user, tenant, navigation })
  -> role controller activate()
```

Logout / classroom change:

```text
role controller deactivate()
  -> shared shell deactivate()
  -> clear authentication / tenant-specific transient state
  -> existing Phase 6E flow
```

Only one module should own the top-level authenticated lifecycle.

Role modules expose explicit methods rather than monkey-patching global functions.

Suggested interface:

```js
TeacherPortal.activate(context)
TeacherPortal.deactivate()
StudentPortal.activate(context)
StudentPortal.deactivate()
```

The concrete module form can remain plain JavaScript and does not require ESM migration in the same change.

## 15. Styling architecture

Target CSS ownership:

```text
styles.css                 pre-auth/common base
portal_shell.css           authenticated product shell
teacher_dashboard.css      teacher feature content only
student_dashboard.css      student feature content only
phase*.css                 phase-specific feature styles
```

After migration:

- teacher CSS must not own top-level site shell geometry
- student CSS must not own top-level site shell geometry
- common buttons, navigation items, account cards, layout breakpoints, page headings, errors, and loading states should move to shell/common CSS where semantics match
- do not force unrelated teacher/student feature cards into one class merely because they look similar

Prefer semantic reuse over visual-only abstraction.

## 16. Accessibility requirements

The shared shell must:

- expose navigation using appropriate `nav` semantics
- identify the active page with `aria-current` or equivalent
- support keyboard navigation for all navigation and account controls
- preserve visible focus styles
- give the mobile menu an accessible name and expanded state
- restore sensible focus when the mobile navigation closes
- avoid using clickable `div` elements when a button/link is appropriate
- preserve existing safe-preview iframe sandbox restrictions

## 17. Error handling

The shell provides one global error surface for portal-level failures.

Role modules keep local errors close to their forms/actions.

Examples:

- tenant/session mismatch -> portal-level handling and logout
- `/me` invalid role -> fail closed before role UI activation
- upload failure -> student feature-local error
- review approval failure -> teacher feature-local/modal error

No fallback from teacher UI to student UI or vice versa is allowed.

## 18. Security boundary

This UI refactor must not weaken the existing authorization model.

Required invariants:

- tenant API still validates every authenticated operation
- student APIs cannot become teacher-capable because a hidden menu item is manipulated
- access tokens remain tenant-bound as defined by Phase 6E
- classroom switching clears authentication and transient tenant state before selecting another classroom
- preview remains sandboxed
- no new user-supplied API endpoint is introduced
- no operator-side credential proxy is introduced

## 19. Android relationship

Android and Web have different primary jobs and should not be forced into one UI layout.

Web:

- create/upload/manage/review classroom applications
- account and class administration

Android:

- discover published classroom applications
- show app details
- open/run an approved application

They should share branding, terminology, app metadata, authentication identity, and classroom identity, but not necessarily navigation structure.

## 20. Migration plan

Implement in small, reviewable stages.

### Stage A: introduce shared shell without changing feature behavior

- add `portal_shell.js/css`
- shell owns brand, sidebar/top bar, account, classroom label, logout, classroom change, responsive menu, global error area
- preserve existing teacher and student feature DOM and API calls
- activate role-specific content inside a shell content slot

Acceptance requirement: all existing teacher/student E2E flows still work.

### Stage B: remove duplicated role chrome

- remove teacher-owned sidebar/top bar/account shell markup
- remove student-owned top bar/account shell markup
- move common styles to `portal_shell.css`
- keep role feature content unchanged

### Stage C: explicit controller lifecycle

- stop overriding/wrapping `loadDashboard` and `clearAuthentication`
- make `app.js` choose the controller after `/me`
- controller activation/deactivation becomes explicit
- unknown role fails closed

### Stage D: navigation/page cleanup

- map teacher feature views to shared navigation
- map student upload/apps/settings to shared navigation
- retain role-specific content components
- add/adjust responsive and keyboard tests

### Stage E: remove legacy authenticated dashboard

Only after both roles are fully served by the shared shell:

- remove obsolete authenticated markup from `index.html`
- remove legacy elements that are no longer required by `app.js`
- simplify production asset list if appropriate

Do not delete legacy elements before the new shell no longer depends on them.

## 21. Testing requirements

At minimum add/retain tests for:

### Role selection

- teacher `/me` activates teacher navigation and teacher controller
- student `/me` activates student navigation and student controller
- unsupported role fails closed

### Shared shell

- classroom name is displayed from the verified current tenant
- logout clears authenticated UI
- classroom change uses the existing Phase 6E clear/switch flow
- mobile menu exposes only current-role navigation

### Teacher regression

- pending review list
- preview and approve
- reject
- published preview
- unpublish
- class creation
- student issuance/member management

### Student regression

- upload ZIP
- own apps list
- preview
- publish request
- update rejected/unpublished version
- display-name change

### Isolation

- no role switch without a new authenticated `/me`
- stale role-specific DOM/state does not remain visible after logout or classroom change
- changing tenant clears role UI before new tenant login

## 22. Production publishing

The guarded static publishing process remains in use.

When `portal_shell.js/css` is introduced, `scripts/publish-portal.ps1` must include the new production assets in the explicit allow-list in the same PR that makes `index.html` depend on them.

This avoids publishing HTML that references assets absent from S3.

No Terraform change is required solely for the UI shell refactor.

## 23. Acceptance criteria for the completed refactor

The design is complete when all of the following are true:

1. `https://minapp.cloxs.jp` remains the single Web entry point.
2. Users do not select teacher/student before login.
3. `/me` determines the authenticated role.
4. One shared Web shell renders product branding, navigation, account controls, classroom context, and responsive behavior.
5. Teacher and student navigation differs only by explicit role configuration.
6. Teacher and student feature modules do not implement separate top-level site shells.
7. Teacher feature behavior is unchanged.
8. Student upload/publish behavior is unchanged.
9. Android remains the published-app launcher and is not coupled to the Web shell implementation.
10. Phase 6E routing, tenant isolation, token handling, and classroom-switch clearing semantics remain unchanged.
11. All CI suites pass.
12. Production publication includes every referenced shell asset.

## 24. Summary

MinApp should be treated as one product with role-aware capabilities, not two separately maintained teacher/student Web products.

The stable boundary is:

```text
shared portal shell
  + teacher feature module
  + student feature module
```

This keeps the UI consistent and lowers maintenance cost without flattening the real differences between teacher and student workflows or weakening tenant/API authorization boundaries.
