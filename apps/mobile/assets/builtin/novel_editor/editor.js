(function () {
  'use strict';

  const formatApi = window.MinAppNovelFormat;
  const core = window.MinAppNovelEditorCore;
  if (!formatApi || typeof formatApi.validateStory !== 'function') {
    throw new Error('MinAppNovelFormat validator is not loaded');
  }
  if (!core || typeof core.validateProject !== 'function') {
    throw new Error('MinAppNovelEditorCore is not loaded');
  }

  const els = {
    status: document.getElementById('status'),
    revision: document.getElementById('revision'),
    contentRevision: document.getElementById('content-revision'),
    title: document.getElementById('story-title'),
    startScene: document.getElementById('start-scene'),
    sceneList: document.getElementById('scene-list'),
    eventEditor: document.getElementById('event-editor'),
    assetList: document.getElementById('asset-list'),
    validation: document.getElementById('validation'),
    save: document.getElementById('save-button'),
    publish: document.getElementById('publish-button'),
  };

  let initialized = false;
  let project = null;
  let workingDocument = null;
  let selectedSceneId = null;
  let dirty = false;
  let busy = false;

  function authoringApi() {
    const minapp = window.minapp;
    if (!minapp || minapp.version !== 1 || !minapp.authoring) return null;
    const api = minapp.authoring;
    if (
      typeof api.load !== 'function' ||
      typeof api.save !== 'function' ||
      typeof api.publish !== 'function'
    ) {
      throw Object.assign(new Error('minapp.authoring.load/save/publish are required'), {
        code: 'authoring_bridge_incomplete',
      });
    }
    return api;
  }

  function setStatus(message, kind) {
    els.status.textContent = message;
    els.status.dataset.kind = kind || 'info';
  }

  function setBusy(value) {
    busy = value;
    els.save.disabled = value || !project || !dirty;
    els.publish.disabled = value || !project || dirty;
    els.title.disabled = value || !project;
    els.startScene.disabled = value || !project;
  }

  function markDirty() {
    if (!project || busy) return;
    dirty = true;
    setBusy(false);
    setStatus('未保存の変更があります', 'dirty');
    validateWorkingDocument();
  }

  function formatError(error) {
    const code = error && error.code ? error.code : 'editor_error';
    const message = error && error.message ? error.message : String(error);
    return `${code}: ${message}`;
  }

  function validateWorkingDocument() {
    try {
      formatApi.validateStory(workingDocument);
      els.validation.textContent = '✓ minapp/novel@1 として有効';
      els.validation.dataset.kind = 'ok';
      return true;
    } catch (error) {
      els.validation.textContent = formatError(error);
      els.validation.dataset.kind = 'error';
      return false;
    }
  }

  function renderProject() {
    els.revision.textContent = `Draft r${project.draftRevision}`;
    els.contentRevision.textContent = `Story r${workingDocument.content_revision}`;
    els.title.value = workingDocument.title;

    els.startScene.replaceChildren();
    for (const sceneId of Object.keys(workingDocument.scenes)) {
      const option = document.createElement('option');
      option.value = sceneId;
      option.textContent = sceneId;
      option.selected = sceneId === workingDocument.start_scene;
      els.startScene.appendChild(option);
    }

    if (!selectedSceneId || !workingDocument.scenes[selectedSceneId]) {
      selectedSceneId = workingDocument.start_scene;
    }
    renderSceneList();
    renderSelectedScene();
    renderAssets();
    validateWorkingDocument();
    setBusy(false);
  }

  function renderSceneList() {
    els.sceneList.replaceChildren();
    for (const sceneId of Object.keys(workingDocument.scenes)) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'scene-button';
      button.dataset.selected = String(sceneId === selectedSceneId);
      button.textContent = sceneId;
      button.addEventListener('click', () => {
        selectedSceneId = sceneId;
        renderSceneList();
        renderSelectedScene();
      });
      els.sceneList.appendChild(button);
    }
  }

  function readOnlyField(labelText, value) {
    const row = document.createElement('div');
    row.className = 'readonly-row';
    const label = document.createElement('span');
    label.textContent = labelText;
    const code = document.createElement('code');
    code.textContent = value;
    row.append(label, code);
    return row;
  }

  function eventCard(event) {
    const card = document.createElement('section');
    card.className = 'event-card';
    const heading = document.createElement('div');
    heading.className = 'event-heading';
    const type = document.createElement('strong');
    type.textContent = event.type;
    const id = document.createElement('code');
    id.textContent = event.id;
    heading.append(type, id);
    card.appendChild(heading);

    if (event.type === 'dialogue') {
      if (event.speaker) card.appendChild(readOnlyField('speaker', event.speaker));
      const textarea = document.createElement('textarea');
      textarea.rows = 4;
      textarea.value = event.text;
      textarea.setAttribute('aria-label', `${event.id} のセリフ`);
      textarea.addEventListener('input', () => {
        event.text = textarea.value;
        markDirty();
      });
      card.appendChild(textarea);
      return card;
    }

    if (event.type === 'choice') {
      for (const option of event.options) {
        const row = document.createElement('div');
        row.className = 'choice-row';
        const input = document.createElement('input');
        input.type = 'text';
        input.value = option.label;
        input.setAttribute('aria-label', `${option.id} の選択肢ラベル`);
        input.addEventListener('input', () => {
          option.label = input.value;
          markDirty();
        });
        const target = document.createElement('code');
        target.textContent = `${option.id} → ${option.goto}`;
        row.append(input, target);
        card.appendChild(row);
      }
      return card;
    }

    if (event.type === 'end') {
      const input = document.createElement('input');
      input.type = 'text';
      input.value = event.label || '';
      input.placeholder = 'END';
      input.setAttribute('aria-label', `${event.id} のENDラベル`);
      input.addEventListener('input', () => {
        if (input.value === '') delete event.label;
        else event.label = input.value;
        markDirty();
      });
      card.appendChild(input);
      return card;
    }

    for (const [key, value] of Object.entries(event)) {
      if (key === 'id' || key === 'type') continue;
      card.appendChild(
        readOnlyField(key, typeof value === 'string' ? value : JSON.stringify(value)),
      );
    }
    return card;
  }

  function renderSelectedScene() {
    els.eventEditor.replaceChildren();
    const scene = workingDocument.scenes[selectedSceneId];
    const heading = document.createElement('div');
    heading.className = 'scene-heading';
    const title = document.createElement('h2');
    title.textContent = selectedSceneId;
    const note = document.createElement('span');
    note.textContent = 'stable IDは編集しません';
    heading.append(title, note);
    els.eventEditor.appendChild(heading);
    for (const event of scene.events) {
      els.eventEditor.appendChild(eventCard(event));
    }
  }

  function renderAssets() {
    els.assetList.replaceChildren();
    if (project.assets.length === 0) {
      const empty = document.createElement('p');
      empty.textContent = 'Authoring Projectにassetはまだありません';
      els.assetList.appendChild(empty);
      return;
    }
    for (const asset of project.assets) {
      const row = document.createElement('code');
      row.textContent = typeof asset === 'string' ? asset : JSON.stringify(asset);
      els.assetList.appendChild(row);
    }
  }

  async function loadProject() {
    const api = authoringApi();
    if (!api) return false;
    setBusy(true);
    setStatus('作品を読み込んでいます…');
    const payload = await api.load();
    project = core.validateProject(payload, formatApi.validateStory);
    workingDocument = core.deepClone(project.document);
    selectedSceneId = workingDocument.start_scene;
    dirty = false;
    renderProject();
    setStatus('読み込みました', 'ok');
    return true;
  }

  async function saveProject() {
    if (!project || !workingDocument) {
      throw Object.assign(new Error('Authoring Project is not loaded'), {
        code: 'authoring_project_not_loaded',
      });
    }
    if (!dirty) return;
    const api = authoringApi();
    if (!api) {
      throw Object.assign(new Error('Authoring bridge is unavailable'), {
        code: 'authoring_unavailable',
      });
    }

    setBusy(true);
    setStatus('保存しています…');
    const expectedRevision = project.draftRevision;
    const documentToSave = core.prepareDocumentSave(
      workingDocument,
      formatApi.validateStory,
    );
    const response = await api.save(documentToSave, { expectedRevision });
    const nextRevision = core.validateSaveResponse(
      response,
      expectedRevision,
      project.contentId,
    );
    project.draftRevision = nextRevision;
    project.assets = core.deepClone(response.assets);
    workingDocument = core.deepClone(documentToSave);
    dirty = false;
    renderProject();
    setStatus(`Draft r${nextRevision} を保存しました`, 'ok');
  }

  async function publishProject() {
    if (!project || !workingDocument) {
      throw Object.assign(new Error('Authoring Project is not loaded'), {
        code: 'authoring_project_not_loaded',
      });
    }
    if (dirty) {
      throw Object.assign(new Error('公開前に変更を保存してください'), {
        code: 'unsaved_changes',
      });
    }
    formatApi.validateStory(workingDocument);
    const api = authoringApi();
    if (!api) {
      throw Object.assign(new Error('Authoring bridge is unavailable'), {
        code: 'authoring_unavailable',
      });
    }

    setBusy(true);
    setStatus('公開要求を送っています…');
    const expectedRevision = project.draftRevision;
    const response = await api.publish({ expectedRevision });
    const version = core.validatePublishResponse(
      response,
      expectedRevision,
      project.contentId,
    );
    setBusy(false);
    setStatus(`Published v${version} を作成しました`, 'ok');
  }

  async function initializeFromHost() {
    if (initialized) return;
    const api = authoringApi();
    if (!api) {
      setStatus('みんアプの編集画面から開いてください', 'waiting');
      return;
    }
    initialized = true;
    try {
      await loadProject();
    } catch (error) {
      initialized = false;
      setBusy(false);
      setStatus(formatError(error), 'error');
      console.error(error);
    }
  }

  els.title.addEventListener('input', () => {
    if (!workingDocument) return;
    workingDocument.title = els.title.value;
    markDirty();
  });
  els.startScene.addEventListener('change', () => {
    if (!workingDocument) return;
    workingDocument.start_scene = els.startScene.value;
    markDirty();
  });
  els.save.addEventListener('click', async () => {
    try {
      await saveProject();
    } catch (error) {
      setBusy(false);
      setStatus(formatError(error), 'error');
      console.error(error);
    }
  });
  els.publish.addEventListener('click', async () => {
    try {
      await publishProject();
    } catch (error) {
      setBusy(false);
      setStatus(formatError(error), 'error');
      console.error(error);
    }
  });

  window.addEventListener('minappready', initializeFromHost);
  setBusy(false);
  initializeFromHost();
})();
