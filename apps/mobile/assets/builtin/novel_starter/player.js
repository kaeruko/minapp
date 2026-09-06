(function () {
  'use strict';

  const SAVE_KEY = 'novel_progress_v1';
  const STORY_ELEMENT_ID = 'minapp-novel-story';
  const formatApi = window.MinAppNovelFormat;
  if (!formatApi || typeof formatApi.validateStory !== 'function') {
    throw new Error('MinAppNovelFormat validator is not loaded');
  }

  const els = {
    title: document.getElementById('title'),
    saveStatus: document.getElementById('save-status'),
    stage: document.getElementById('stage'),
    speaker: document.getElementById('speaker'),
    text: document.getElementById('text'),
    choices: document.getElementById('choices'),
    end: document.getElementById('end'),
    startOverlay: document.getElementById('start-overlay'),
    startButton: document.getElementById('start-button'),
    continueButton: document.getElementById('continue-button'),
    fatal: document.getElementById('fatal'),
    fatalMessage: document.getElementById('fatal-message'),
    resetButton: document.getElementById('reset-save-button'),
    slots: {
      left: document.querySelector('[data-character-slot="left"]'),
      center: document.querySelector('[data-character-slot="center"]'),
      right: document.querySelector('[data-character-slot="right"]'),
    },
  };

  let story;
  let savedProgress = null;
  let sceneId = null;
  let eventIndex = 0;
  let currentEventId = null;
  let ended = false;
  let runtimeMode = 'pending';
  let runtimeInitialized = false;
  let controlsBound = false;
  let bgmAudio = null;
  let seAudio = null;
  let displayState = emptyDisplayState();

  function emptyDisplayState() {
    return {
      background: null,
      characters: { left: null, center: null, right: null },
      bgm: null,
    };
  }

  function cloneDisplayState(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function setStatus(message) {
    els.saveStatus.textContent = message;
  }

  function fatal(error, allowSaveReset) {
    const code = error && error.code ? error.code : 'player_error';
    const message = error && error.message ? error.message : String(error);
    els.fatalMessage.textContent = `${code}: ${message}`;
    els.resetButton.hidden = allowSaveReset !== true;
    els.fatal.hidden = false;
    els.startOverlay.hidden = true;
    els.choices.replaceChildren();
    console.error(error);
  }

  function parseStory() {
    const element = document.getElementById(STORY_ELEMENT_ID);
    if (!element) throw Object.assign(new Error(`#${STORY_ELEMENT_ID} is required`), { code: 'story_not_embedded' });
    let parsed;
    try {
      parsed = JSON.parse(element.textContent);
    } catch (error) {
      throw Object.assign(new Error(`embedded story JSON is invalid: ${error.message}`), { code: 'invalid_story_json' });
    }
    return formatApi.validateStory(parsed);
  }

  function configureRuntime() {
    if (typeof window.minapp === 'undefined') {
      const channel = window.MinAppNativeBridge;
      if (channel && typeof channel.postMessage === 'function') {
        runtimeMode = 'waiting_for_host';
        setStatus('ホスト接続待ち');
        return;
      }
      runtimeMode = 'standalone';
      setStatus('単体プレビュー: セーブなし');
      return;
    }
    if (!window.minapp || window.minapp.version !== 1) {
      throw Object.assign(new Error('window.minapp.version === 1 is required'), { code: 'host_contract_error' });
    }
    const userState = window.minapp.userState;
    if (!userState || typeof userState.get !== 'function' || typeof userState.set !== 'function' || typeof userState.delete !== 'function') {
      throw Object.assign(new Error('minapp.userState.get/set/delete are required; shared minapp.state is not a valid fallback'), { code: 'user_state_unavailable' });
    }
    runtimeMode = 'hosted';
  }

  function asset(assetId, expectedKind) {
    const item = story.assets[assetId];
    if (!item) throw Object.assign(new Error(`asset ${assetId} does not exist`), { code: 'missing_asset' });
    if (item.kind !== expectedKind) throw Object.assign(new Error(`asset ${assetId} must be ${expectedKind}`), { code: 'asset_kind_mismatch' });
    return item;
  }

  function findEvent(targetSceneId, targetEventId) {
    const scene = story.scenes[targetSceneId];
    if (!scene) throw Object.assign(new Error(`scene ${targetSceneId} does not exist`), { code: 'missing_scene' });
    const index = scene.events.findIndex((event) => event.id === targetEventId);
    if (index < 0) throw Object.assign(new Error(`event ${targetEventId} does not exist in scene ${targetSceneId}`), { code: 'save_event_missing' });
    return index;
  }

  function validateSavedProgress(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      throw Object.assign(new Error('saved progress must be an object'), { code: 'invalid_save' });
    }
    if (raw.schema_version !== 1 || raw.content_format !== formatApi.FORMAT) {
      throw Object.assign(new Error('saved progress format is incompatible'), { code: 'incompatible_save' });
    }
    if (raw.content_revision !== story.content_revision) {
      throw Object.assign(
        new Error(`save revision ${raw.content_revision} does not match story revision ${story.content_revision}`),
        { code: 'incompatible_save' }
      );
    }
    if (typeof raw.scene_id !== 'string' || typeof raw.event_id !== 'string') {
      throw Object.assign(new Error('saved progress scene_id/event_id are required'), { code: 'invalid_save' });
    }
    findEvent(raw.scene_id, raw.event_id);
    validateSavedDisplayState(raw.state);
    return raw;
  }

  function validateSavedDisplayState(state) {
    if (!state || typeof state !== 'object' || Array.isArray(state)) {
      throw Object.assign(new Error('saved display state must be an object'), { code: 'invalid_save' });
    }
    const allowed = new Set(['background', 'characters', 'bgm']);
    for (const key of Object.keys(state)) {
      if (!allowed.has(key)) throw Object.assign(new Error(`unknown saved state field ${key}`), { code: 'invalid_save' });
    }
    if (state.background !== null) asset(state.background, 'image');
    if (state.bgm !== null) asset(state.bgm, 'audio');
    if (!state.characters || typeof state.characters !== 'object' || Array.isArray(state.characters)) {
      throw Object.assign(new Error('saved characters state is required'), { code: 'invalid_save' });
    }
    for (const slot of ['left', 'center', 'right']) {
      if (!Object.prototype.hasOwnProperty.call(state.characters, slot)) {
        throw Object.assign(new Error(`saved characters.${slot} is required`), { code: 'invalid_save' });
      }
      const item = state.characters[slot];
      if (item === null) continue;
      if (!item || typeof item !== 'object' || Array.isArray(item)) {
        throw Object.assign(new Error(`saved characters.${slot} is invalid`), { code: 'invalid_save' });
      }
      const character = story.characters[item.character_id];
      if (!character) throw Object.assign(new Error(`saved character ${item.character_id} does not exist`), { code: 'invalid_save' });
      const imageAssetId = character.expressions[item.expression];
      if (!imageAssetId) throw Object.assign(new Error(`saved expression ${item.expression} does not exist`), { code: 'invalid_save' });
      asset(imageAssetId, 'image');
    }
  }

  async function loadSavedProgress() {
    if (runtimeMode !== 'hosted') return null;
    try {
      const raw = await window.minapp.userState.get(SAVE_KEY);
      return validateSavedProgress(raw);
    } catch (error) {
      if (error && error.code === 'state_not_found') return null;
      throw error;
    }
  }

  async function persistProgress() {
    if (runtimeMode !== 'hosted') return;
    if (!sceneId || !currentEventId) throw Object.assign(new Error('cannot save without an active event'), { code: 'invalid_player_state' });
    const payload = {
      schema_version: 1,
      content_format: formatApi.FORMAT,
      content_revision: story.content_revision,
      scene_id: sceneId,
      event_id: currentEventId,
      state: cloneDisplayState(displayState),
    };
    await window.minapp.userState.set(SAVE_KEY, payload);
    setStatus('セーブしました');
  }

  async function deleteProgress() {
    if (runtimeMode !== 'hosted') return;
    try {
      await window.minapp.userState.delete(SAVE_KEY);
    } catch (error) {
      if (!(error && error.code === 'state_not_found')) throw error;
    }
    savedProgress = null;
    setStatus('はじめから');
  }

  function clearDialogue() {
    els.speaker.hidden = true;
    els.speaker.textContent = '';
    els.end.hidden = true;
    els.text.textContent = '';
    els.choices.replaceChildren();
  }

  function renderBackground(assetId) {
    const item = asset(assetId, 'image');
    els.stage.style.backgroundImage = `url(${JSON.stringify(item.src)})`;
    displayState.background = assetId;
  }

  function renderCharacter(slot, characterId, expression) {
    const character = story.characters[characterId];
    if (!character) throw Object.assign(new Error(`character ${characterId} does not exist`), { code: 'missing_character' });
    const imageAssetId = character.expressions[expression];
    if (!imageAssetId) throw Object.assign(new Error(`expression ${expression} does not exist on ${characterId}`), { code: 'missing_expression' });
    const item = asset(imageAssetId, 'image');
    const image = els.slots[slot];
    image.src = item.src;
    image.alt = item.alt || character.name;
    image.hidden = false;
    displayState.characters[slot] = { character_id: characterId, expression };
  }

  function hideCharacter(slot) {
    const image = els.slots[slot];
    image.hidden = true;
    image.removeAttribute('src');
    image.alt = '';
    displayState.characters[slot] = null;
  }

  async function playBgm(assetId, loop) {
    const item = asset(assetId, 'audio');
    if (bgmAudio) {
      bgmAudio.pause();
      bgmAudio = null;
    }
    bgmAudio = new Audio(item.src);
    bgmAudio.loop = loop !== false;
    await bgmAudio.play();
    displayState.bgm = assetId;
  }

  function stopBgm() {
    if (bgmAudio) {
      bgmAudio.pause();
      bgmAudio.currentTime = 0;
      bgmAudio = null;
    }
    displayState.bgm = null;
  }

  async function playSe(assetId) {
    const item = asset(assetId, 'audio');
    if (seAudio) {
      seAudio.pause();
      seAudio = null;
    }
    seAudio = new Audio(item.src);
    await seAudio.play();
  }

  async function restoreDisplayState(state) {
    displayState = emptyDisplayState();
    if (state.background !== null) renderBackground(state.background);
    for (const slot of ['left', 'center', 'right']) {
      const item = state.characters[slot];
      if (item === null) hideCharacter(slot);
      else renderCharacter(slot, item.character_id, item.expression);
    }
    if (state.bgm !== null) await playBgm(state.bgm, true);
  }

  function showDialogue(event) {
    if (event.speaker) {
      els.speaker.textContent = story.characters[event.speaker].name;
      els.speaker.hidden = false;
    } else {
      els.speaker.hidden = true;
      els.speaker.textContent = '';
    }
    els.text.textContent = event.text;
  }

  async function pauseAtEvent(event) {
    currentEventId = event.id;
    await persistProgress();
  }

  async function runUntilPause() {
    ended = false;
    while (true) {
      const scene = story.scenes[sceneId];
      if (!scene) throw Object.assign(new Error(`scene ${sceneId} does not exist`), { code: 'missing_scene' });
      if (eventIndex < 0 || eventIndex >= scene.events.length) {
        throw Object.assign(new Error(`scene ${sceneId} ran past its final event`), { code: 'unterminated_scene' });
      }
      const event = scene.events[eventIndex];
      clearDialogue();
      switch (event.type) {
        case 'background':
          renderBackground(event.asset);
          eventIndex += 1;
          break;
        case 'character':
          if (event.action === 'show') renderCharacter(event.slot, event.character, event.expression);
          else hideCharacter(event.slot);
          eventIndex += 1;
          break;
        case 'bgm':
          if (event.action === 'play') await playBgm(event.asset, event.loop);
          else stopBgm();
          eventIndex += 1;
          break;
        case 'se':
          await playSe(event.asset);
          eventIndex += 1;
          break;
        case 'dialogue':
          showDialogue(event);
          await pauseAtEvent(event);
          els.text.classList.add('clickable');
          els.text.onclick = async () => {
            els.text.onclick = null;
            els.text.classList.remove('clickable');
            eventIndex += 1;
            try {
              await runUntilPause();
            } catch (error) {
              fatal(error, false);
            }
          };
          return;
        case 'choice':
          els.text.textContent = 'どうする？';
          event.options.forEach((option) => {
            const button = document.createElement('button');
            button.className = 'choice';
            button.type = 'button';
            button.textContent = option.label;
            button.addEventListener('click', async () => {
              try {
                sceneId = option.goto;
                eventIndex = 0;
                await runUntilPause();
              } catch (error) {
                fatal(error, false);
              }
            });
            els.choices.appendChild(button);
          });
          await pauseAtEvent(event);
          return;
        case 'end': {
          ended = true;
          els.end.hidden = false;
          els.end.textContent = event.label || 'END';
          const button = document.createElement('button');
          button.className = 'restart';
          button.type = 'button';
          button.textContent = 'はじめから読む';
          button.addEventListener('click', async () => {
            try {
              await deleteProgress();
              await startNewGame();
            } catch (error) {
              fatal(error, false);
            }
          });
          els.choices.appendChild(button);
          await pauseAtEvent(event);
          return;
        }
        default:
          throw Object.assign(new Error(`unsupported event type ${event.type}`), { code: 'unknown_event_type' });
      }
    }
  }

  async function startNewGame() {
    stopBgm();
    displayState = emptyDisplayState();
    for (const slot of ['left', 'center', 'right']) hideCharacter(slot);
    els.stage.style.backgroundImage = '';
    sceneId = story.start_scene;
    eventIndex = 0;
    currentEventId = null;
    ended = false;
    els.startOverlay.hidden = true;
    await runUntilPause();
  }

  async function continueGame() {
    if (!savedProgress) throw Object.assign(new Error('no saved progress exists'), { code: 'state_not_found' });
    sceneId = savedProgress.scene_id;
    eventIndex = findEvent(savedProgress.scene_id, savedProgress.event_id);
    currentEventId = savedProgress.event_id;
    ended = false;
    els.startOverlay.hidden = true;
    await restoreDisplayState(savedProgress.state);
    await runUntilPause();
  }

  async function resetInvalidSaveAndStart() {
    try {
      await deleteProgress();
      els.fatal.hidden = true;
      await startNewGame();
    } catch (error) {
      fatal(error, false);
    }
  }

  function bindControls() {
    if (controlsBound) return;
    controlsBound = true;
    els.startButton.addEventListener('click', async () => {
      try {
        await deleteProgress();
        await startNewGame();
      } catch (error) {
        fatal(error, false);
      }
    });
    els.continueButton.addEventListener('click', async () => {
      try {
        await continueGame();
      } catch (error) {
        fatal(error, error && (error.code === 'incompatible_save' || error.code === 'invalid_save' || error.code === 'save_event_missing'));
      }
    });
    els.resetButton.addEventListener('click', resetInvalidSaveAndStart);
  }

  async function finishRuntimeInitialization() {
    if (runtimeInitialized) return;
    if (runtimeMode === 'waiting_for_host' || runtimeMode === 'pending') {
      throw Object.assign(new Error('Runtime initialization was attempted before the host bridge became ready'), { code: 'host_contract_error' });
    }
    runtimeInitialized = true;
    savedProgress = await loadSavedProgress();
    els.continueButton.hidden = savedProgress === null;
    els.startButton.disabled = false;
    els.continueButton.disabled = false;
    if (runtimeMode === 'hosted') setStatus(savedProgress ? 'セーブあり' : 'はじめから');
  }

  async function onMinAppReady() {
    if (runtimeInitialized) return;
    try {
      configureRuntime();
      if (runtimeMode !== 'hosted') {
        throw Object.assign(new Error('minappready fired without a valid hosted Runtime bridge'), { code: 'host_contract_error' });
      }
      await finishRuntimeInitialization();
    } catch (error) {
      const resettable = error && (error.code === 'incompatible_save' || error.code === 'invalid_save' || error.code === 'save_event_missing');
      fatal(error, resettable);
    }
  }

  async function initialize() {
    try {
      story = parseStory();
      els.title.textContent = story.title;
      bindControls();
      els.startButton.disabled = true;
      els.continueButton.disabled = true;
      window.addEventListener('minappready', onMinAppReady);
      configureRuntime();
      if (runtimeMode !== 'waiting_for_host') {
        await finishRuntimeInitialization();
      }
    } catch (error) {
      const resettable = error && (error.code === 'incompatible_save' || error.code === 'invalid_save' || error.code === 'save_event_missing');
      fatal(error, resettable);
    }
  }

  initialize();
})();
