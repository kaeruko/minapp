"use strict";

(function defineHostedAuthoringPortal(root, factory) {
  const api = factory(root);
  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  }
  if (root && typeof root === "object") {
    Object.defineProperty(root, "MinAppHostedAuthoringPortal", {
      configurable: true,
      value: Object.freeze(api),
    });
  }
})(typeof globalThis === "object" ? globalThis : null, function createHostedAuthoringPortal(root) {
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const CONTENT_FORMAT_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}\/[a-z0-9][a-z0-9._-]{0,63}@[1-9][0-9]{0,5}$/;
  const PROJECT_FIELDS = Object.freeze([
    "content_id",
    "group_id",
    "content_format",
    "status",
    "draft_revision",
    "assets",
    "created_at",
    "updated_at",
  ]);

  function requireAuthoringApi() {
    const api = root && root.MinAppWebAuthoring;
    if (!api ||
        typeof api.createWebAuthoringLaunch !== "function" ||
        typeof api.listAuthoringApps !== "function" ||
        typeof api.playersFor !== "function" ||
        typeof api.createAuthoringPreview !== "function" ||
        typeof api.WebAuthoringHostAdapter !== "function" ||
        typeof api.HostedWebApiError !== "function") {
      throw new Error("MinAppWebAuthoring foundation is required.");
    }
    return api;
  }

  function isPlainObject(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }

  function requirePlainObject(value, label) {
    if (!isPlainObject(value)) throw new Error(`${label} must be an object.`);
    return value;
  }

  function requireExactFields(value, expected, label) {
    const object = requirePlainObject(value, label);
    const actual = Object.keys(object).sort();
    const wanted = [...expected].sort();
    if (actual.length !== wanted.length || actual.some((name, index) => name !== wanted[index])) {
      throw new Error(`${label} fields are invalid.`);
    }
    return object;
  }

  function requireString(value, label) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`${label} must be a non-empty string.`);
    }
    return value;
  }

  function validateId(value, label) {
    if (typeof value !== "string" || !ID_PATTERN.test(value)) {
      throw new Error(`${label} must be a 32-character lowercase hexadecimal id.`);
    }
    return value;
  }

  function validateContentFormat(value, label) {
    if (typeof value !== "string" || !CONTENT_FORMAT_PATTERN.test(value)) {
      throw new Error(`${label} must be a namespaced versioned content format.`);
    }
    return value;
  }

  function requirePositiveInteger(value, label) {
    if (!Number.isInteger(value) || value < 1) {
      throw new Error(`${label} must be a positive integer.`);
    }
    return value;
  }

  function validateApiOrigin(value) {
    const api = requireAuthoringApi();
    return api.validateApiOrigin(value);
  }

  function validateAccessToken(value) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error("Hosted access token is unavailable.");
    }
    return value;
  }

  function parseTimestamp(value, label) {
    const text = requireString(value, label);
    const milliseconds = Date.parse(text);
    if (!Number.isFinite(milliseconds)) throw new Error(`${label} is invalid.`);
    return Object.freeze({ text, milliseconds });
  }

  function validateProjectSummary(rawProject, expectedGroupId, expectedContentFormat) {
    const project = requireExactFields(rawProject, PROJECT_FIELDS, "Authoring project summary");
    const contentId = validateId(project.content_id, "project content_id");
    const groupId = validateId(project.group_id, "project group_id");
    const contentFormat = validateContentFormat(project.content_format, "project content_format");
    if (groupId !== expectedGroupId || contentFormat !== expectedContentFormat) {
      throw new Error("Authoring project response changed the requested scope.");
    }
    if (project.status !== "draft") {
      throw new Error(`Authoring project status must be draft, received ${String(project.status)}.`);
    }
    if (!Array.isArray(project.assets)) throw new Error("Authoring project assets must be a list.");
    const created = parseTimestamp(project.created_at, "project created_at");
    const updated = parseTimestamp(project.updated_at, "project updated_at");
    return Object.freeze({
      contentId,
      groupId,
      contentFormat,
      status: "draft",
      draftRevision: requirePositiveInteger(project.draft_revision, "project draft_revision"),
      createdAt: created.text,
      createdAtMilliseconds: created.milliseconds,
      updatedAt: updated.text,
      updatedAtMilliseconds: updated.milliseconds,
    });
  }

  async function decodeJsonResponse(response, context) {
    if (!response || typeof response !== "object" || typeof response.status !== "number") {
      throw new Error(`${context} returned an invalid Response object.`);
    }
    const contentType = response.headers && typeof response.headers.get === "function"
      ? response.headers.get("content-type")
      : null;
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new (requireAuthoringApi().HostedWebApiError)(
        response.status,
        "invalid_api_response",
        `${context} returned a non-JSON response (HTTP ${response.status}).`,
      );
    }
    let payload;
    try {
      payload = await response.json();
    } catch (error) {
      throw new (requireAuthoringApi().HostedWebApiError)(
        response.status,
        "invalid_api_response",
        `${context} returned invalid JSON.`,
      );
    }
    if (!isPlainObject(payload)) {
      throw new (requireAuthoringApi().HostedWebApiError)(
        response.status,
        "invalid_api_response",
        `${context} returned a non-object JSON payload.`,
      );
    }
    if (!response.ok) {
      let errorPayload;
      try {
        errorPayload = requireExactFields(payload, ["error", "message"], `${context} error response`);
      } catch (error) {
        throw new (requireAuthoringApi().HostedWebApiError)(
          response.status,
          "invalid_api_response",
          `${context} error response fields are invalid.`,
        );
      }
      throw new (requireAuthoringApi().HostedWebApiError)(
        response.status,
        requireString(errorPayload.error, `${context} error code`),
        requireString(errorPayload.message, `${context} error message`),
      );
    }
    return payload;
  }

  async function authenticatedJsonRequest({
    apiOrigin,
    accessToken,
    path,
    method,
    body = null,
    fetchImpl = root.fetch,
    context,
  }) {
    const origin = validateApiOrigin(apiOrigin);
    validateAccessToken(accessToken);
    if (typeof fetchImpl !== "function") throw new TypeError("fetchImpl must be a function.");
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Hosted Authoring path must be origin-relative.");
    }
    if (method !== "GET" && method !== "POST") {
      throw new TypeError(`Unsupported Hosted Authoring method: ${String(method)}`);
    }
    if (method === "GET" && body !== null) {
      throw new TypeError("GET Hosted Authoring request must not contain a body.");
    }
    const url = new URL(path, `${origin}/`);
    if (url.origin !== origin) throw new Error("Hosted Authoring path escaped the configured origin.");
    const headers = {
      Accept: "application/json",
      Authorization: `Bearer ${accessToken}`,
    };
    const options = {
      method,
      headers,
      cache: "no-store",
      credentials: "omit",
    };
    if (body !== null) {
      if (!isPlainObject(body)) throw new TypeError("Hosted Authoring request body must be an object.");
      headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(body);
    }
    let response;
    try {
      response = await fetchImpl(url.toString(), options);
    } catch (error) {
      throw new (requireAuthoringApi().HostedWebApiError)(
        0,
        "host_adapter_request_failed",
        error instanceof Error ? error.message : String(error),
      );
    }
    return await decodeJsonResponse(response, context);
  }

  async function listProjects({
    apiOrigin,
    accessToken,
    groupId,
    contentFormat,
    fetchImpl = root.fetch,
  }) {
    const normalizedGroupId = validateId(groupId, "groupId");
    const normalizedFormat = validateContentFormat(contentFormat, "contentFormat");
    const query = new URLSearchParams({ content_format: normalizedFormat });
    const payload = await authenticatedJsonRequest({
      apiOrigin,
      accessToken,
      method: "GET",
      path: `/hosted/authoring/groups/${normalizedGroupId}/projects?${query.toString()}`,
      fetchImpl,
      context: "Authoring project list",
    });
    requireExactFields(payload, ["projects"], "Authoring project list response");
    if (!Array.isArray(payload.projects)) throw new Error("Authoring project list projects must be a list.");
    const contentIds = new Set();
    const projects = payload.projects.map((project) => {
      const validated = validateProjectSummary(project, normalizedGroupId, normalizedFormat);
      if (contentIds.has(validated.contentId)) {
        throw new Error("Authoring project list contains a duplicate content_id.");
      }
      contentIds.add(validated.contentId);
      return validated;
    });
    return Object.freeze(projects);
  }

  async function createProject({
    apiOrigin,
    accessToken,
    groupId,
    contentFormat,
    fetchImpl = root.fetch,
  }) {
    const normalizedGroupId = validateId(groupId, "groupId");
    const normalizedFormat = validateContentFormat(contentFormat, "contentFormat");
    const payload = await authenticatedJsonRequest({
      apiOrigin,
      accessToken,
      method: "POST",
      path: "/hosted/authoring/projects",
      body: {
        group_id: normalizedGroupId,
        content_format: normalizedFormat,
        document: {},
      },
      fetchImpl,
      context: "Authoring project create",
    });
    const project = validateProjectSummary(payload, normalizedGroupId, normalizedFormat);
    if (project.draftRevision !== 1) {
      throw new Error("New Authoring project must start at draft revision 1.");
    }
    return project;
  }

  function editorChoices(apps) {
    if (!Array.isArray(apps)) throw new TypeError("Authoring apps must be a list.");
    const seen = new Set();
    const choices = [];
    for (const app of apps) {
      if (!app || typeof app !== "object") throw new Error("Authoring app must be an object.");
      validateId(app.appId, "Authoring editor appId");
      requireString(app.title, "Authoring editor title");
      if (!Array.isArray(app.edits) || !Array.isArray(app.accepts)) {
        throw new Error("Authoring app edits/accepts must be lists.");
      }
      for (const contentFormat of app.edits) {
        validateContentFormat(contentFormat, "Authoring editor content format");
        const key = `${app.appId}\n${contentFormat}`;
        if (seen.has(key)) throw new Error("Authoring editor discovery contains a duplicate editor/format pair.");
        seen.add(key);
        choices.push(Object.freeze({
          appId: app.appId,
          title: app.title,
          contentFormat,
        }));
      }
    }
    choices.sort((left, right) =>
      left.title.localeCompare(right.title, "ja") || left.contentFormat.localeCompare(right.contentFormat)
    );
    return Object.freeze(choices);
  }

  function requireElement(value, constructorName, label) {
    if (!value || typeof value !== "object") throw new TypeError(`${label} is required.`);
    if (root && typeof root[constructorName] === "function" && !(value instanceof root[constructorName])) {
      throw new TypeError(`${label} must be a ${constructorName}.`);
    }
    return value;
  }

  function errorMessage(error) {
    if (error instanceof Error && error.message.length > 0) return error.message;
    return String(error);
  }

  class HostedAuthoringPortalController {
    constructor({
      sourceGroupSelect,
      groupSelect,
      editorSelect,
      refreshButton,
      createButton,
      statusElement,
      errorElement,
      projectList,
      editorDialog,
      editorTitle,
      editorFrame,
      editorCloseButton,
      playerDialog,
      playerOptions,
      playerCancelButton,
      previewDialog,
      previewTitle,
      previewFrame,
      previewCloseButton,
      getApiOrigin,
      getAccessToken,
      onUnauthorized = null,
      fetchImpl = root.fetch,
    }) {
      this.sourceGroupSelect = requireElement(sourceGroupSelect, "HTMLSelectElement", "sourceGroupSelect");
      this.groupSelect = requireElement(groupSelect, "HTMLSelectElement", "groupSelect");
      this.editorSelect = requireElement(editorSelect, "HTMLSelectElement", "editorSelect");
      this.refreshButton = requireElement(refreshButton, "HTMLButtonElement", "refreshButton");
      this.createButton = requireElement(createButton, "HTMLButtonElement", "createButton");
      this.statusElement = requireElement(statusElement, "HTMLElement", "statusElement");
      this.errorElement = requireElement(errorElement, "HTMLElement", "errorElement");
      this.projectList = requireElement(projectList, "HTMLElement", "projectList");
      this.editorDialog = requireElement(editorDialog, "HTMLDialogElement", "editorDialog");
      this.editorTitle = requireElement(editorTitle, "HTMLElement", "editorTitle");
      this.editorFrame = requireElement(editorFrame, "HTMLIFrameElement", "editorFrame");
      this.editorCloseButton = requireElement(editorCloseButton, "HTMLButtonElement", "editorCloseButton");
      this.playerDialog = requireElement(playerDialog, "HTMLDialogElement", "playerDialog");
      this.playerOptions = requireElement(playerOptions, "HTMLElement", "playerOptions");
      this.playerCancelButton = requireElement(playerCancelButton, "HTMLButtonElement", "playerCancelButton");
      this.previewDialog = requireElement(previewDialog, "HTMLDialogElement", "previewDialog");
      this.previewTitle = requireElement(previewTitle, "HTMLElement", "previewTitle");
      this.previewFrame = requireElement(previewFrame, "HTMLIFrameElement", "previewFrame");
      this.previewCloseButton = requireElement(previewCloseButton, "HTMLButtonElement", "previewCloseButton");
      if (typeof getApiOrigin !== "function") throw new TypeError("getApiOrigin must be a function.");
      if (typeof getAccessToken !== "function") throw new TypeError("getAccessToken must be a function.");
      if (onUnauthorized !== null && typeof onUnauthorized !== "function") {
        throw new TypeError("onUnauthorized must be null or a function.");
      }
      if (typeof fetchImpl !== "function") throw new TypeError("fetchImpl must be a function.");
      this.getApiOrigin = getApiOrigin;
      this.getAccessToken = getAccessToken;
      this.onUnauthorized = onUnauthorized;
      this.fetchImpl = fetchImpl;
      this.authoringApi = requireAuthoringApi();
      this.currentApps = Object.freeze([]);
      this.currentChoices = Object.freeze([]);
      this.currentSelection = null;
      this.currentAdapter = null;
      this.busy = false;
      this.activationGeneration = 0;
      this.playerResolver = null;
      this.previewResolver = null;
      this.bound = false;
    }

    bind() {
      if (this.bound) throw new Error("Hosted Authoring portal is already bound.");
      this.bound = true;
      this.refreshButton.addEventListener("click", () => { void this.activate(); });
      this.groupSelect.addEventListener("change", () => { void this.refreshEditorsAndProjects(); });
      this.editorSelect.addEventListener("change", () => { void this.refreshProjects(); });
      this.createButton.addEventListener("click", () => { void this.createAndOpenProject(); });
      this.editorCloseButton.addEventListener("click", () => { void this.closeEditor(); });
      this.playerCancelButton.addEventListener("click", () => this.cancelPlayerSelection());
      this.previewCloseButton.addEventListener("click", () => this.closePreview());
      this.playerDialog.addEventListener("cancel", (event) => {
        event.preventDefault();
        this.cancelPlayerSelection();
      });
      this.previewDialog.addEventListener("cancel", (event) => {
        event.preventDefault();
        this.closePreview();
      });
      this.editorDialog.addEventListener("cancel", (event) => {
        event.preventDefault();
        void this.closeEditor();
      });
    }

    setError(message) {
      if (message === null) {
        this.errorElement.textContent = "";
        this.errorElement.classList.add("hidden");
        return;
      }
      this.errorElement.textContent = message;
      this.errorElement.classList.remove("hidden");
    }

    setBusy(value) {
      this.busy = value;
      this.refreshButton.disabled = value;
      this.groupSelect.disabled = value;
      this.editorSelect.disabled = value || this.currentChoices.length === 0;
      this.createButton.disabled = value || this.currentSelection === null;
    }

    async environment() {
      const apiOrigin = validateApiOrigin(await this.getApiOrigin());
      const accessToken = validateAccessToken(this.getAccessToken());
      return Object.freeze({ apiOrigin, accessToken });
    }

    syncGroups() {
      const previous = this.groupSelect.value;
      this.groupSelect.replaceChildren();
      const options = [...this.sourceGroupSelect.options];
      for (const sourceOption of options) {
        const groupId = validateId(sourceOption.value, "Hosted group id");
        const label = sourceOption.textContent === null ? "" : sourceOption.textContent.trim();
        requireString(label, "Hosted group name");
        const option = root.document.createElement("option");
        option.value = groupId;
        option.textContent = label;
        this.groupSelect.appendChild(option);
      }
      if (options.length === 0) return;
      const sourceSelected = this.sourceGroupSelect.value;
      if (ID_PATTERN.test(previous) && [...this.groupSelect.options].some((item) => item.value === previous)) {
        this.groupSelect.value = previous;
      } else if (ID_PATTERN.test(sourceSelected) && [...this.groupSelect.options].some((item) => item.value === sourceSelected)) {
        this.groupSelect.value = sourceSelected;
      }
    }

    selectedChoice() {
      const index = Number(this.editorSelect.value);
      if (!Number.isInteger(index) || index < 0 || index >= this.currentChoices.length) return null;
      return this.currentChoices[index];
    }

    async activate() {
      const generation = ++this.activationGeneration;
      this.setError(null);
      this.statusElement.textContent = "編集できる作品を確認しています…";
      try {
        this.syncGroups();
        if (this.groupSelect.options.length === 0) {
          this.currentApps = Object.freeze([]);
          this.currentChoices = Object.freeze([]);
          this.currentSelection = null;
          this.editorSelect.replaceChildren();
          this.projectList.replaceChildren();
          this.statusElement.textContent = "参加中のグループがありません。";
          this.setBusy(false);
          return;
        }
        await this.refreshEditorsAndProjects(generation);
      } catch (error) {
        if (generation !== this.activationGeneration) return;
        this.handleError(error, "編集画面を読み込めませんでした。");
      }
    }

    async refreshEditorsAndProjects(existingGeneration = null) {
      const generation = existingGeneration === null ? ++this.activationGeneration : existingGeneration;
      this.setBusy(true);
      this.setError(null);
      this.projectList.replaceChildren();
      try {
        const { apiOrigin, accessToken } = await this.environment();
        const groupId = validateId(this.groupSelect.value, "selected group id");
        const apps = await this.authoringApi.listAuthoringApps({
          apiOrigin,
          accessToken,
          groupId,
          fetchImpl: this.fetchImpl,
        });
        if (generation !== this.activationGeneration) return;
        const choices = editorChoices(apps);
        this.currentApps = apps;
        this.currentChoices = choices;
        this.editorSelect.replaceChildren();
        choices.forEach((choice, index) => {
          const option = root.document.createElement("option");
          option.value = String(index);
          option.textContent = `${choice.title} — ${choice.contentFormat}`;
          this.editorSelect.appendChild(option);
        });
        this.currentSelection = choices.length === 0 ? null : choices[0];
        this.editorSelect.disabled = choices.length === 0;
        if (choices.length === 0) {
          this.statusElement.textContent = "このグループには利用できるEditorがありません。";
          this.projectList.replaceChildren();
          return;
        }
        await this.refreshProjects(generation);
      } catch (error) {
        if (generation !== this.activationGeneration) return;
        this.handleError(error, "Editor一覧を読み込めませんでした。");
      } finally {
        if (generation === this.activationGeneration) this.setBusy(false);
      }
    }

    async refreshProjects(existingGeneration = null) {
      const generation = existingGeneration === null ? ++this.activationGeneration : existingGeneration;
      this.setBusy(true);
      this.setError(null);
      try {
        const selection = this.selectedChoice();
        if (selection === null) {
          this.currentSelection = null;
          this.projectList.replaceChildren();
          this.statusElement.textContent = "Editorを選択してください。";
          return;
        }
        this.currentSelection = selection;
        const { apiOrigin, accessToken } = await this.environment();
        const groupId = validateId(this.groupSelect.value, "selected group id");
        const projects = await listProjects({
          apiOrigin,
          accessToken,
          groupId,
          contentFormat: selection.contentFormat,
          fetchImpl: this.fetchImpl,
        });
        if (generation !== this.activationGeneration) return;
        const sorted = [...projects].sort((left, right) => right.updatedAtMilliseconds - left.updatedAtMilliseconds);
        this.renderProjects(sorted);
        this.statusElement.textContent = sorted.length === 0
          ? "まだ作品がありません。新しい作品を作れます。"
          : `${sorted.length}件の作品があります。`;
      } catch (error) {
        if (generation !== this.activationGeneration) return;
        this.handleError(error, "作品一覧を読み込めませんでした。");
      } finally {
        if (generation === this.activationGeneration) this.setBusy(false);
      }
    }

    renderProjects(projects) {
      this.projectList.replaceChildren();
      for (const project of projects) {
        const card = root.document.createElement("article");
        card.className = "hosted-authoring-project";
        const copy = root.document.createElement("div");
        const title = root.document.createElement("strong");
        title.textContent = `作品 ${project.contentId.slice(0, 8)}`;
        const meta = root.document.createElement("span");
        const updated = new Date(project.updatedAtMilliseconds);
        meta.textContent = `Draft r${project.draftRevision} · ${updated.toLocaleString("ja-JP")}`;
        copy.append(title, meta);
        const button = root.document.createElement("button");
        button.type = "button";
        button.className = "girls-secondary";
        button.textContent = "編集する";
        button.addEventListener("click", () => { void this.openEditor(project.contentId); });
        card.append(copy, button);
        this.projectList.appendChild(card);
      }
    }

    async createAndOpenProject() {
      if (this.busy) return;
      this.setBusy(true);
      this.setError(null);
      try {
        const selection = this.selectedChoice();
        if (selection === null) throw new Error("Editorを選択してください。");
        this.currentSelection = selection;
        const { apiOrigin, accessToken } = await this.environment();
        const project = await createProject({
          apiOrigin,
          accessToken,
          groupId: validateId(this.groupSelect.value, "selected group id"),
          contentFormat: selection.contentFormat,
          fetchImpl: this.fetchImpl,
        });
        await this.openEditor(project.contentId, { keepBusy: true });
      } catch (error) {
        this.handleError(error, "作品を作成できませんでした。");
      } finally {
        if (!this.editorDialog.open) this.setBusy(false);
      }
    }

    async openEditor(contentId, options = {}) {
      if (this.busy && options.keepBusy !== true) return;
      this.setBusy(true);
      this.setError(null);
      try {
        if (this.currentAdapter !== null || this.editorDialog.open) {
          throw new Error("別のEditorがすでに開いています。");
        }
        const selection = this.selectedChoice();
        if (selection === null) throw new Error("Editorを選択してください。");
        this.currentSelection = selection;
        const { apiOrigin, accessToken } = await this.environment();
        const launch = await this.authoringApi.createWebAuthoringLaunch({
          apiOrigin,
          accessToken,
          contentId: validateId(contentId, "contentId"),
          editorAppId: selection.appId,
          fetchImpl: this.fetchImpl,
        });
        if (launch.contentFormat !== selection.contentFormat) {
          throw new Error("Editor launch returned a different content format.");
        }
        this.editorTitle.textContent = `${selection.title} — 編集`;
        this.editorFrame.removeAttribute("src");
        const adapter = new this.authoringApi.WebAuthoringHostAdapter({
          frame: this.editorFrame,
          apiOrigin,
          launch,
          previewHandler: async (expectedRevision) =>
            await this.previewFromEditor({
              apiOrigin,
              accessToken: validateAccessToken(this.getAccessToken()),
              groupId: launch.contentId === contentId
                ? validateId(this.groupSelect.value, "selected group id")
                : (() => { throw new Error("Editor launch content scope changed."); })(),
              contentId: launch.contentId,
              contentFormat: launch.contentFormat,
              expectedRevision,
            }),
          fetchImpl: this.fetchImpl,
        });
        adapter.attach();
        this.currentAdapter = adapter;
        this.editorDialog.showModal();
        this.editorFrame.src = launch.contentUrl;
        this.setBusy(false);
      } catch (error) {
        if (this.currentAdapter !== null) {
          this.currentAdapter.destroy();
          this.currentAdapter = null;
        }
        this.editorFrame.removeAttribute("src");
        if (this.editorDialog.open) this.editorDialog.close();
        this.handleError(error, "Editorを開けませんでした。");
      }
    }

    async previewFromEditor({
      apiOrigin,
      accessToken,
      groupId,
      contentId,
      contentFormat,
      expectedRevision,
    }) {
      const apps = await this.authoringApi.listAuthoringApps({
        apiOrigin,
        accessToken,
        groupId,
        fetchImpl: this.fetchImpl,
      });
      const players = this.authoringApi.playersFor(apps, contentFormat);
      const player = await this.choosePlayer(players, contentFormat);
      if (player === null) return null;
      const preview = await this.authoringApi.createAuthoringPreview({
        apiOrigin,
        accessToken: validateAccessToken(this.getAccessToken()),
        contentId,
        playerAppId: player.appId,
        expectedRevision,
        fetchImpl: this.fetchImpl,
      });
      if (preview.contentFormat !== contentFormat) {
        throw new Error("Preview returned a different content format.");
      }
      await this.showPreview(preview, player.title);
      return Object.freeze({
        content_format: preview.contentFormat,
        draft_revision: preview.draftRevision,
        player_app_id: preview.playerAppId,
      });
    }

    async choosePlayer(players, contentFormat) {
      if (!Array.isArray(players)) throw new TypeError("players must be a list.");
      if (players.length === 0) {
        throw new this.authoringApi.HostedWebApiError(
          409,
          "authoring_player_unavailable",
          `No installed Player accepts ${contentFormat}.`,
        );
      }
      if (players.length === 1) return players[0];
      if (this.playerResolver !== null) {
        throw new Error("Player selection is already open.");
      }
      this.playerOptions.replaceChildren();
      return await new Promise((resolve) => {
        this.playerResolver = resolve;
        for (const player of players) {
          const button = root.document.createElement("button");
          button.type = "button";
          button.className = "girls-secondary hosted-authoring-player-option";
          button.textContent = player.title;
          button.addEventListener("click", () => {
            const resolver = this.playerResolver;
            this.playerResolver = null;
            if (this.playerDialog.open) this.playerDialog.close();
            resolver(player);
          });
          this.playerOptions.appendChild(button);
        }
        this.playerDialog.showModal();
      });
    }

    cancelPlayerSelection() {
      if (this.playerDialog.open) this.playerDialog.close();
      if (this.playerResolver !== null) {
        const resolver = this.playerResolver;
        this.playerResolver = null;
        resolver(null);
      }
    }

    async showPreview(preview, playerTitle) {
      if (this.previewResolver !== null) throw new Error("Preview is already open.");
      this.previewTitle.textContent = `${playerTitle} — 下書きプレビュー`;
      this.previewFrame.removeAttribute("src");
      this.previewDialog.showModal();
      this.previewFrame.src = preview.contentUrl;
      await new Promise((resolve) => {
        this.previewResolver = resolve;
      });
    }

    closePreview() {
      this.previewFrame.removeAttribute("src");
      if (this.previewDialog.open) this.previewDialog.close();
      if (this.previewResolver !== null) {
        const resolver = this.previewResolver;
        this.previewResolver = null;
        resolver();
      }
    }

    async closeEditor() {
      this.cancelPlayerSelection();
      this.closePreview();
      if (this.currentAdapter !== null) {
        this.currentAdapter.destroy();
        this.currentAdapter = null;
      }
      this.editorFrame.removeAttribute("src");
      if (this.editorDialog.open) this.editorDialog.close();
      this.setBusy(false);
      await this.refreshProjects();
    }

    handleError(error, fallback) {
      const message = errorMessage(error);
      this.setError(message.length > 0 ? message : fallback);
      this.statusElement.textContent = fallback;
      this.setBusy(false);
      if (error instanceof this.authoringApi.HostedWebApiError && error.status === 401 && this.onUnauthorized !== null) {
        this.onUnauthorized(error);
      }
    }

    destroy() {
      this.activationGeneration += 1;
      this.cancelPlayerSelection();
      this.closePreview();
      if (this.currentAdapter !== null) {
        this.currentAdapter.destroy();
        this.currentAdapter = null;
      }
      this.editorFrame.removeAttribute("src");
      if (this.editorDialog.open) this.editorDialog.close();
      this.setBusy(false);
    }
  }

  return Object.freeze({
    HostedAuthoringPortalController,
    validateProjectSummary,
    listProjects,
    createProject,
    editorChoices,
  });
});
