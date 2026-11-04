'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const html = fs.readFileSync(
  path.join(__dirname, '../assets/builtin/sing_along/index.html'), 'utf8'
);
const scripts = [...html.matchAll(/<script>([\\s\\S]*?)<\\/script>/g)];
assert.equal(scripts.length, 1, 'Karaoke must have exactly one inline script.');

function makeHarness() {
  class Element {
    constructor() {
      this.value = '';
      this.disabled = false;
      this.textContent = '';
      this.className = '';
      this.listeners = new Map();
    }
    addEventListener(name, callback) { this.listeners.set(name, callback); }
  }
  const elements = Object.fromEntries(
    [...html.matchAll(/\\bid="([^"]+)"/g)].map((match) => [match[1], new Element()])
  );
  elements.track.value = 'clair-de-lune';
  const intervals = new Map();
  const oscillators = [];
  const errors = [];
  let clock = 10000;
  let nextId = 0;
  const parameter = () => ({
    setValueAtTime() {},
    exponentialRampToValueAtTime() {},
  });
  const node = () => ({
    starts: [], stops: [], listeners: new Map(), disconnected: false,
    connect(destination) { return destination; },
    disconnect() { this.disconnected = true; },
    start(time) { this.starts.push(time); },
    stop(time) { this.stops.push(time); },
    addEventListener(name, handler) { this.listeners.set(name, handler); },
  });
  const context = {
    state: 'running',
    currentTime: 10,
    destination: {},
    async resume() { this.state = 'running'; },
    createOscillator() {
      const o = node();
      o.frequency = { setValueAtTime(value) { o.hz = value; } };
      oscillators.push(o);
      return o;
    },
    createGain() { return { ...node(), gain: parameter() }; },
    createDynamicsCompressor() {
      return {
        ...node(),
        threshold: parameter(), knee: parameter(), ratio: parameter(),
        attack: parameter(), release: parameter(),
      };
    },
  };
  const window = {
    AudioContext: function AudioContext() { return context; },
    MediaRecorder: function Recorder() {},
    addEventListener() {},
  };
  const sandbox = vm.createContext({
    window,
    navigator: { mediaDevices: { async getUserMedia() { throw Error('Unexpected microphone access'); } } },
    HTMLElement: Element,
    document: { getElementById(id) { return elements[id]; } },
    console: { error(error) { errors.push(error); } },
    performance: { now() { return clock; } },
    setInterval(callback) { const id = ++nextId; intervals.set(id, callback); return id; },
    clearInterval(id) { intervals.delete(id); },
  });
  vm.runInContext(scripts[0][1], sandbox, { filename: 'builtin/sing_along/index.html' });
  return {
    elements, context, oscillators, errors, intervals,
    run(expression) { return vm.runInContext(expression, sandbox); },
    tick(audioTime, wallTime = audioTime) {
      context.currentTime = audioTime;
      clock = wallTime * 1000;
      for (const callback of [...intervals.values()]) callback();
    },
  };
}

test('Android built-in score keeps scheduling new notes after 17 seconds', async () => {
  const app = makeHarness();
  await app.run('previewBgm()');
  const initiallyScheduled = app.oscillators.length;
  assert.ok(initiallyScheduled > 0 && initiallyScheduled < 20);
  for (let t = 10.25; t <= 28; t += 0.25) app.tick(t);
  assert.ok(app.oscillators.length > initiallyScheduled);
  assert.equal(app.errors.length, 0);
  assert.match(app.elements.status.textContent, /BGMを再生中/);

  app.run('stopByUser()');
  assert.equal(app.intervals.size, 0);
  app.elements.track.value = 'idol-step';
  app.run('updateTrackInfo()');
  await app.run('previewBgm()');
  assert.match(app.elements.status.textContent, /BGMを再生中/);
  assert.equal(app.errors.length, 0);
});

test('Android built-in fails fast when audio clock is stalled', async () => {
  const app = makeHarness();
  await app.run('previewBgm()');
  app.tick(10, 12);
  assert.equal(app.errors.length, 1);
  assert.match(app.elements.status.textContent, /BGM audio clock stopped advancing/);
  assert.equal(app.intervals.size, 0);
});
