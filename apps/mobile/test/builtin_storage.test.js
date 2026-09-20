'use strict';

// Execute the shipped inline scripts with a controllable native bridge. These
// tests exercise persistence across WebView instances and delayed native writes.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const MEMO_KEY = 'minapp_memo_pad_v1';
const PET_KEY = 'minappchi_pet_v1';
const NOW = 1900000000000;

class Element {
  constructor() {
    this.value = '';
    this.textContent = '';
    this.disabled = false;
    this.readOnly = false;
    this.hidden = false;
    this.children = [];
    this.listeners = new Map();
    const classes = new Set();
    this.classList = {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name),
      toggle: (name, on) => on ? classes.add(name) : classes.delete(name),
    };
  }
  addEventListener(name, callback) { this.listeners.set(name, callback); }
  emit(name) { return this.listeners.get(name)?.(); }
  replaceChildren(...children) { this.children = children; }
  appendChild(child) { this.children.push(child); }
  focus() {}
}
class TextArea extends Element {}
class Button extends Element {}

function launch(app, options = {}) {
  const nativeStore = options.nativeStore ?? new Map();
  const legacyStore = options.legacyStore ?? new Map();
  const requests = [];
  const localReads = [];
  const localWrites = [];
  const elements = new Map();
  const timers = new Map();
  const intervals = [];
  const events = new Map();
  let nextTimer = 0;
  let now = NOW;
  let closed = false;
  const html = readFileSync(path.join(__dirname, '../assets/builtin', app, 'index.html'), 'utf8');
  for (const match of html.matchAll(/<(button|textarea|[a-z]+)\b([^>]*\bid="([^"]+)"[^>]*)>/g)) {
    const element = match[1] === 'textarea' ? new TextArea() : match[1] === 'button' ? new Button() : new Element();
    element.disabled = /\bdisabled\b/.test(match[2]);
    element.readOnly = /\breadonly\b/.test(match[2]);
    element.hidden = /\bhidden\b/.test(match[2]);
    elements.set(match[3], element);
  }
  const window = {
    location: { protocol: options.protocol ?? 'file:' },
    localStorage: {
      getItem(key) {
        localReads.push(key);
        if (options.localReadError) throw new Error('legacy read failed');
        return legacyStore.has(key) ? legacyStore.get(key) : null;
      },
      setItem(key, value) {
        if (options.localWriteError) throw new Error('legacy write failed');
        localWrites.push({ key, value });
        legacyStore.set(key, value);
      },
    },
    setTimeout(callback, ms) { const id = ++nextTimer; timers.set(id, { callback, ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
    setInterval(callback) { intervals.push(callback); return intervals.length; },
    addEventListener(name, callback) { events.set(name, callback); },
    confirm: () => true,
  };
  function reply(request, response) {
    if (!request) throw new Error('No pending request');
    let payload = response;
    if (!payload) {
      if (request.method === 'set') {
        nativeStore.set(request.key, structuredClone(request.value));
        payload = {};
      } else {
        payload = nativeStore.has(request.key)
          ? { found: true, value: structuredClone(nativeStore.get(request.key)) }
          : { found: false };
      }
    }
    if (!closed) window.__minappBuiltinStateResolve({ version: 1, id: request.id, ok: true, ...payload });
  }
  if (options.native !== false) {
    window.MinAppBuiltinState = {
      postMessage(raw) {
        const request = JSON.parse(raw);
        requests.push(request);
        if (options.automatic !== false) queueMicrotask(() => reply(request));
      },
    };
  }
  if (options.hosted) window.minapp = options.hosted;
  const context = vm.createContext({
    window,
    document: { getElementById: (id) => elements.get(id), createElement: () => new Element() },
    HTMLElement: Element,
    HTMLTextAreaElement: TextArea,
    HTMLButtonElement: Button,
    Date: class extends Date { static now() { return now; } },
  });
  const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  vm.runInContext(script, context, { filename: `${app}/index.html` });
  return {
    nativeStore, legacyStore, requests, localReads, localWrites, window,
    element: (id) => elements.get(id),
    reply,
    close() { closed = true; },
    event: (name) => events.get(name)?.(),
    tick() { for (const callback of intervals) callback(); },
    now(value) { now = value; },
    state: () => JSON.parse(vm.runInContext('JSON.stringify(state)', context)),
    timeout(ms) {
      for (const [id, timer] of [...timers]) {
        if (timer.ms === ms) { timers.delete(id); timer.callback(); }
      }
    },
  };
}

const settled = () => new Promise(setImmediate);
const writes = (page) => page.requests.filter((request) => request.method === 'set');
const egg = (generation = 3) => ({
  version: 1, generation, phase: 'egg', eggAt: NOW, hatchAt: NOW + 15000,
  bornAt: null, diedAt: null, deathCause: null, fullness: 3, health: 3,
  poop: 0, nextHungerAt: null, nextPoopAt: null,
});
const alive = () => ({
  ...egg(), phase: 'alive', eggAt: NOW - 20000, hatchAt: NOW - 5000,
  bornAt: NOW - 5000, nextHungerAt: NOW + 1000, nextPoopAt: NOW + 2000,
});

test('memo waits for load, immediately hands off snapshots and only marks the latest acknowledged input saved', async () => {
  const page = launch('memo_pad', { automatic: false });
  const memo = page.element('memo');
  assert.equal(memo.readOnly, true);
  assert.equal(page.element('clear-button').disabled, true);
  memo.emit('input');
  assert.equal(writes(page).length, 0);
  page.reply(page.requests[0]);
  await settled();
  assert.equal(memo.readOnly, false);

  memo.value = 'first';
  memo.emit('input');
  memo.value = 'latest';
  memo.emit('input');
  assert.equal(writes(page).length, 2);
  await settled();
  assert.equal(writes(page)[0].value, 'first');
  assert.equal(page.element('status').textContent, '保存中…');
  page.reply(writes(page)[0]);
  await settled();
  assert.equal(writes(page).length, 2);
  assert.equal(writes(page)[1].value, 'latest');
  assert.equal(memo.value, 'latest');
  assert.equal(page.element('status').textContent, '保存中…');
  page.reply(writes(page)[1]);
  await settled();
  assert.equal(page.element('status').textContent, '保存しました');
  assert.equal(page.localWrites.length, 0);

  const reopened = launch('memo_pad', { nativeStore: page.nativeStore });
  await settled();
  assert.equal(reopened.element('memo').value, 'latest');
});

test('memo input immediately followed by closing leaves all snapshots with native storage', async () => {
  const page = launch('memo_pad', { automatic: false });
  page.reply(page.requests[0]);
  await settled();
  page.element('memo').value = 'earlier';
  page.element('memo').emit('input');
  page.element('memo').value = 'last input before closing';
  page.element('memo').emit('input');
  page.close();
  // Native FIFO completes accepted writes even though the old page can no
  // longer receive an acknowledgement or send another queued snapshot.
  assert.equal(writes(page).length, 2);
  for (const request of writes(page)) page.reply(request);
  const reopened = launch('memo_pad', { nativeStore: page.nativeStore });
  await settled();
  assert.equal(reopened.element('memo').value, 'last input before closing');
});

test('memo imports legacy once and preserves an explicitly empty native memo', async () => {
  const legacyStore = new Map([[MEMO_KEY, 'legacy memo']]);
  const migrated = launch('memo_pad', { legacyStore });
  await settled();
  assert.equal(migrated.nativeStore.get(MEMO_KEY), 'legacy memo');
  assert.equal(legacyStore.get(MEMO_KEY), 'legacy memo');
  migrated.element('clear-button').emit('click');
  await settled();
  assert.equal(migrated.nativeStore.get(MEMO_KEY), '');
  const reopened = launch('memo_pad', { nativeStore: migrated.nativeStore, legacyStore, localReadError: true });
  await settled();
  assert.equal(reopened.element('memo').value, '');
  assert.equal(reopened.element('memo').readOnly, false);
  assert.deepEqual(reopened.localReads, []);
  assert.equal(writes(reopened).length, 0);
});

test('memo native read failure or invalid state never overwrites or falls back', async () => {
  for (const response of [
    { ok: false, error: 'native read failed' },
    { found: true, value: { text: 'invalid type' } },
    { found: 'invalid' },
  ]) {
    const page = launch('memo_pad', { automatic: false, legacyStore: new Map([[MEMO_KEY, 'legacy']]) });
    page.reply(page.requests[0], response);
    await settled();
    assert.equal(page.element('memo').readOnly, true);
    assert.equal(page.element('status').classList.contains('error'), true);
    assert.equal(writes(page).length, 0);
    assert.deepEqual(page.localReads, []);
  }
});

test('memo migration failure retains legacy and visible text while blocking edits', async () => {
  const page = launch('memo_pad', { automatic: false, legacyStore: new Map([[MEMO_KEY, 'keep me']]) });
  page.reply(page.requests[0]);
  await settled();
  assert.equal(page.element('memo').readOnly, true);
  page.reply(writes(page)[0], { ok: false, error: 'disk full' });
  await settled();
  assert.equal(page.element('memo').value, 'keep me');
  assert.equal(page.legacyStore.get(MEMO_KEY), 'keep me');
  assert.equal(page.nativeStore.has(MEMO_KEY), false);
  assert.equal(page.element('memo').readOnly, true);
});

test('memo failed write preserves newest input and late acknowledgements do not clear the error', async () => {
  const page = launch('memo_pad', { automatic: false });
  page.reply(page.requests[0]);
  await settled();
  page.element('memo').value = 'older';
  page.element('memo').emit('input');
  page.element('memo').value = 'copy this latest text';
  page.element('memo').emit('input');
  await settled();
  page.reply(writes(page)[0], { ok: false, error: 'disk full' });
  await settled();
  assert.equal(writes(page).length, 2);
  page.reply(writes(page)[1]);
  await settled();
  page.element('memo').emit('input');
  assert.equal(writes(page).length, 2);
  assert.equal(page.element('memo').value, 'copy this latest text');
  assert.equal(page.element('memo').readOnly, true);
  assert.match(page.element('status').textContent, /保存できませんでした/);
  assert.equal(page.localWrites.length, 0);
});

test('legacy read errors do not create new native data', async () => {
  for (const app of ['memo_pad', 'minappchi']) {
    const page = launch(app, { localReadError: true });
    await settled();
    assert.equal(writes(page).length, 0);
    assert.equal(page.nativeStore.size, 0);
  }
});

test('minappchi migrates validated legacy state and keeps native authoritative on reopen', async () => {
  const legacyStore = new Map([[PET_KEY, JSON.stringify(egg(7))]]);
  const migrated = launch('minappchi', { legacyStore });
  await settled();
  assert.equal(migrated.state().generation, 7);
  assert.deepEqual(migrated.nativeStore.get(PET_KEY), egg(7));
  assert.equal(legacyStore.get(PET_KEY), JSON.stringify(egg(7)));
  legacyStore.set(PET_KEY, '{corrupt old save');
  const reopened = launch('minappchi', { nativeStore: migrated.nativeStore, legacyStore, localReadError: true });
  await settled();
  assert.deepEqual(reopened.state(), egg(7));
  assert.deepEqual(reopened.localReads, []);
  assert.equal(writes(reopened).length, 0);
});

test('minappchi corrupt legacy data never creates a fresh egg', async () => {
  for (const legacy of ['not JSON', JSON.stringify({ generation: 8 }), 'null']) {
    const page = launch('minappchi', { legacyStore: new Map([[PET_KEY, legacy]]) });
    await settled();
    page.now(NOW + 60000);
    page.tick();
    page.element('snack').emit('click');
    await settled();
    assert.equal(writes(page).length, 0);
    assert.equal(page.state(), null);
    assert.equal(page.element('message').classList.contains('error'), true);
    assert.equal(page.legacyStore.get(PET_KEY), legacy);
  }
});

test('minappchi failed legacy import leaves the original save and cannot restart the timer', async () => {
  const legacy = JSON.stringify(alive());
  const page = launch('minappchi', { automatic: false, legacyStore: new Map([[PET_KEY, legacy]]) });
  page.reply(page.requests[0]);
  await settled();
  assert.deepEqual(writes(page)[0].value, alive());
  page.reply(writes(page)[0], { ok: false, error: 'import failed' });
  await settled();
  page.now(NOW + 20000);
  page.tick();
  page.element('snack').emit('click');
  await settled();
  assert.deepEqual(page.state(), alive());
  assert.equal(page.legacyStore.get(PET_KEY), legacy);
  assert.equal(page.nativeStore.has(PET_KEY), false);
  assert.equal(writes(page).length, 1);
  assert.equal(page.element('message').classList.contains('error'), true);
});

test('minappchi native read errors and invalid state do not fall back or overwrite', async () => {
  for (const response of [{ ok: false, error: 'read failed' }, { found: true, value: {} }]) {
    const page = launch('minappchi', { automatic: false, legacyStore: new Map([[PET_KEY, JSON.stringify(egg())]]) });
    page.reply(page.requests[0], response);
    await settled();
    page.tick();
    assert.equal(writes(page).length, 0);
    assert.deepEqual(page.localReads, []);
    assert.equal(page.element('snack').disabled, true);
  }
});

test('minappchi pending initial save blocks ticks/actions and failure permanently stops them', async () => {
  const page = launch('minappchi', { automatic: false });
  page.reply(page.requests[0]);
  await settled();
  const original = page.state();
  page.now(NOW + 60000);
  page.tick();
  page.element('snack').emit('click');
  assert.deepEqual(page.state(), original);
  assert.equal(writes(page).length, 1);
  page.reply(writes(page)[0], { ok: false, error: 'save failed' });
  await settled();
  const failureMessage = page.element('message').textContent;
  page.tick();
  page.element('next-egg').emit('click');
  page.event('minappready');
  await settled();
  assert.deepEqual(page.state(), original);
  assert.equal(writes(page).length, 1);
  assert.equal(page.element('message').textContent, failureMessage);
  assert.equal(page.element('next-egg').disabled, true);
});

test('minappchi timer and action writes share a lock until native acknowledgement', async () => {
  const page = launch('minappchi', { automatic: false, nativeStore: new Map([[PET_KEY, alive()]]) });
  page.reply(page.requests[0]);
  await settled();
  page.now(NOW + 1500);
  page.tick();
  await settled();
  assert.equal(writes(page).length, 1);
  assert.equal(writes(page)[0].value.fullness, 2);
  page.now(NOW + 3000);
  page.tick();
  page.element('snack').emit('click');
  await settled();
  assert.equal(writes(page).length, 1);
  assert.equal(page.state().poop, 0);
  assert.equal(page.element('snack').disabled, true);
  page.reply(writes(page)[0]);
  await settled();
  page.element('snack').emit('click');
  await settled();
  assert.equal(writes(page).length, 2);
  assert.equal(writes(page)[1].value.fullness, 3);
  assert.equal(writes(page)[1].value.poop, 1);
  page.reply(writes(page)[1]);
  await settled();
  assert.equal(page.element('snack').disabled, false);
  const reopened = launch('minappchi', { nativeStore: page.nativeStore });
  await settled();
  assert.deepEqual(reopened.state(), page.state());
});

test('minappchi action/timer write failure stays stopped and preserves error text', async () => {
  for (const trigger of ['action', 'timer']) {
    const page = launch('minappchi', { automatic: false, nativeStore: new Map([[PET_KEY, alive()]]) });
    page.reply(page.requests[0]);
    await settled();
    if (trigger === 'action') page.element('snack').emit('click');
    else { page.now(NOW + 1500); page.tick(); }
    await settled();
    page.reply(writes(page)[0], { ok: false, error: 'storage offline' });
    await settled();
    const stoppedState = page.state();
    const errorText = page.element('message').textContent;
    page.now(NOW + 30000000);
    page.tick();
    page.element('snack').emit('click');
    page.element('flush').emit('click');
    await settled();
    assert.equal(writes(page).length, 1);
    assert.deepEqual(page.state(), stoppedState);
    assert.equal(page.element('snack').disabled, true);
    assert.equal(page.element('message').textContent, errorText);
    assert.match(errorText, /停止しました/);
  }
});

test('native initialization cannot be replaced by a late hosted-ready event', async () => {
  let hostedReads = 0;
  const page = launch('minappchi', {
    automatic: false,
    hosted: { version: 1, state: { get() { hostedReads += 1; return Promise.resolve(egg(99)); }, set: async () => {} } },
  });
  page.event('minappready');
  page.event('minappready');
  page.reply(page.requests[0], { found: true, value: egg(4) });
  await settled();
  assert.equal(hostedReads, 0);
  assert.equal(page.state().generation, 4);
});

test('unanswered native requests fail visibly, and late responses cannot resume a stopped app', async () => {
  for (const app of ['memo_pad', 'minappchi']) {
    const page = launch(app, { automatic: false });
    page.timeout(10000);
    await settled();
    page.reply(page.requests[0]);
    await settled();
    assert.equal(writes(page).length, 0);
    if (app === 'memo_pad') {
      assert.equal(page.element('memo').readOnly, true);
      assert.equal(page.element('status').classList.contains('error'), true);
    } else {
      page.tick();
      assert.equal(page.state(), null);
      assert.equal(page.element('message').classList.contains('error'), true);
    }
  }
});

test('standalone local-file usage still persists without the native bridge', async () => {
  const memo = launch('memo_pad', { native: false });
  await settled();
  memo.element('memo').value = 'browser memo';
  memo.element('memo').emit('input');
  await settled();
  assert.equal(memo.legacyStore.get(MEMO_KEY), 'browser memo');
  const pet = launch('minappchi', { native: false, legacyStore: new Map([[PET_KEY, JSON.stringify(egg(12))]]) });
  await settled();
  assert.equal(pet.state().generation, 12);
  pet.now(NOW + 20000);
  pet.tick();
  await settled();
  assert.equal(JSON.parse(pet.legacyStore.get(PET_KEY)).phase, 'alive');
});
