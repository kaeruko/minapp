"use strict";

(function installGirlsAppSourceEditor() {
  if (typeof document === "undefined") return;

  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
  const CONFIG_PATH = "/girls-config.json";
  const MAX_UPLOAD_BYTES = 2 * 1024 * 1024;
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const TEXT_SUFFIXES = new Set([".html", ".css", ".js", ".mjs", ".json", ".txt"]);
  const ALLOWED_SUFFIXES = new Set([
    ".html", ".css", ".js", ".mjs", ".json", ".txt",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico",
    ".mp3", ".m4a", ".ogg", ".wav",
  ]);

  function requiredElement(id, ctor = HTMLElement) {
    const element = document.getElementById(id);
    if (!(element instanceof ctor)) throw new Error(`#${id} has an unexpected type.`);
    return element;
  }

  function errorMessage(error) {
    return error instanceof Error && error.message.length > 0 ? error.message : String(error);
  }

  function suffixOf(path) {
    const slash = path.lastIndexOf("/");
    const dot = path.lastIndexOf(".");
    return dot > slash ? path.slice(dot).toLowerCase() : "";
  }

  function validatePath(path) {
    if (typeof path !== "string" || path.length === 0 || path !== path.trim()) {
      throw new Error("ファイル名が不正です。");
    }
    if (path.includes("\\") || path.startsWith("/") || path.includes("\0")) {
      throw new Error(`ファイル名が不正です: ${path}`);
    }
    const parts = path.split("/");
    if (parts.some((part) => part === "" || part === "." || part === "..")) {
      throw new Error(`ファイル名が不正です: ${path}`);
    }
    if (!ALLOWED_SUFFIXES.has(suffixOf(path))) {
      throw new Error(`この種類のファイルは使えません: ${path}`);
    }
    return path;
  }

  function crc32(bytes) {
    if (!(bytes instanceof Uint8Array)) throw new TypeError("crc32 input must be Uint8Array.");
    let crc = 0xffffffff;
    for (const byte of bytes) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit += 1) {
        const mask = -(crc & 1);
        crc = (crc >>> 1) ^ (0xedb88320 & mask);
      }
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  function readUint16(view, offset) {
    return view.getUint16(offset, true);
  }

  function readUint32(view, offset) {
    return view.getUint32(offset, true);
  }

  function writeUint16(view, offset, value) {
    view.setUint16(offset, value, true);
  }

  function writeUint32(view, offset, value) {
    view.setUint32(offset, value >>> 0, true);
  }

  async function inflateRaw(bytes) {
    if (typeof DecompressionStream !== "function") {
      throw new Error("このブラウザは圧縮ZIPの編集に対応していません。ZIPを保存して外部で編集してください。");
    }
    let stream;
    try {
      stream = new DecompressionStream("deflate-raw");
    } catch (error) {
      throw new Error("このブラウザは圧縮ZIPの編集に対応していません。", { cause: error });
    }
    const response = new Response(new Blob([bytes]).stream().pipeThrough(stream));
    return new Uint8Array(await response.arrayBuffer());
  }

  async function readZip(zipBytes) {
    if (!(zipBytes instanceof Uint8Array) || zipBytes.length < 22) {
      throw new Error("正しいZIPファイルではありません。");
    }
    const view = new DataView(zipBytes.buffer, zipBytes.byteOffset, zipBytes.byteLength);
    const minEocd = Math.max(0, zipBytes.length - 22 - 0xffff);
    let eocd = -1;
    for (let offset = zipBytes.length - 22; offset >= minEocd; offset -= 1) {
      if (readUint32(view, offset) === 0x06054b50) {
        eocd = offset;
        break;
      }
    }
    if (eocd < 0) throw new Error("ZIPの終端情報が見つかりません。");
    const diskNumber = readUint16(view, eocd + 4);
    const centralDisk = readUint16(view, eocd + 6);
    const entriesOnDisk = readUint16(view, eocd + 8);
    const entryCount = readUint16(view, eocd + 10);
    const centralSize = readUint32(view, eocd + 12);
    const centralOffset = readUint32(view, eocd + 16);
    const commentLength = readUint16(view, eocd + 20);
    if (diskNumber !== 0 || centralDisk !== 0 || entriesOnDisk !== entryCount) {
      throw new Error("分割ZIPには対応していません。");
    }
    if (eocd + 22 + commentLength !== zipBytes.length) {
      throw new Error("ZIP終端の長さが不正です。");
    }
    if (centralOffset + centralSize > eocd) {
      throw new Error("ZIP中央ディレクトリの位置が不正です。");
    }

    const decoder = new TextDecoder("utf-8", { fatal: true });
    const entries = new Map();
    let offset = centralOffset;
    for (let index = 0; index < entryCount; index += 1) {
      if (offset + 46 > zipBytes.length || readUint32(view, offset) !== 0x02014b50) {
        throw new Error("ZIP中央ディレクトリが壊れています。");
      }
      const flags = readUint16(view, offset + 8);
      const method = readUint16(view, offset + 10);
      const expectedCrc = readUint32(view, offset + 16);
      const compressedSize = readUint32(view, offset + 20);
      const uncompressedSize = readUint32(view, offset + 24);
      const nameLength = readUint16(view, offset + 28);
      const extraLength = readUint16(view, offset + 30);
      const commentLen = readUint16(view, offset + 32);
      const localOffset = readUint32(view, offset + 42);
      if ((flags & 0x1) !== 0) throw new Error("暗号化ZIPは編集できません。");
      const nameStart = offset + 46;
      const nameEnd = nameStart + nameLength;
      if (nameEnd + extraLength + commentLen > zipBytes.length) {
        throw new Error("ZIP内のファイル名情報が壊れています。");
      }
      let path;
      try {
        path = decoder.decode(zipBytes.subarray(nameStart, nameEnd));
      } catch (error) {
        throw new Error("ZIP内のファイル名はUTF-8である必要があります。", { cause: error });
      }
      offset = nameEnd + extraLength + commentLen;
      if (path.endsWith("/")) continue;
      validatePath(path);
      if (entries.has(path)) throw new Error(`ZIP内に同名ファイルがあります: ${path}`);
      if (localOffset + 30 > zipBytes.length || readUint32(view, localOffset) !== 0x04034b50) {
        throw new Error(`ZIP内のローカルヘッダーが壊れています: ${path}`);
      }
      const localNameLength = readUint16(view, localOffset + 26);
      const localExtraLength = readUint16(view, localOffset + 28);
      const dataStart = localOffset + 30 + localNameLength + localExtraLength;
      const dataEnd = dataStart + compressedSize;
      if (dataEnd > zipBytes.length) throw new Error(`ZIP内のデータが途切れています: ${path}`);
      const compressed = zipBytes.subarray(dataStart, dataEnd);
      let data;
      if (method === 0) {
        data = Uint8Array.from(compressed);
      } else if (method === 8) {
        data = await inflateRaw(compressed);
      } else {
        throw new Error(`未対応のZIP圧縮方式です: ${path} (method=${method})`);
      }
      if (data.length !== uncompressedSize) {
        throw new Error(`ZIP展開後サイズが一致しません: ${path}`);
      }
      if (crc32(data) !== expectedCrc) {
        throw new Error(`ZIP内のファイルが破損しています: ${path}`);
      }
      entries.set(path, data);
    }
    if (offset !== centralOffset + centralSize) {
      throw new Error("ZIP中央ディレクトリの長さが一致しません。");
    }
    if (!entries.has("index.html")) throw new Error("ZIP直下に index.html が必要です。");
    return entries;
  }

  function buildZip(entries) {
    if (!(entries instanceof Map) || entries.size === 0) throw new Error("ZIPに入れるファイルがありません。");
    if (!entries.has("index.html")) throw new Error("index.html は削除できません。");
    if (entries.size > 100) throw new Error("ファイル数は100個以下にしてください。");

    const encoder = new TextEncoder();
    const records = [];
    let totalUncompressed = 0;
    let localLength = 0;
    for (const [rawPath, rawBytes] of [...entries.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      const path = validatePath(rawPath);
      if (!(rawBytes instanceof Uint8Array)) throw new TypeError(`File bytes must be Uint8Array: ${path}`);
      totalUncompressed += rawBytes.length;
      if (totalUncompressed > 8 * 1024 * 1024) throw new Error("ファイルの合計サイズは8MB以下にしてください。");
      const name = encoder.encode(path);
      const crc = crc32(rawBytes);
      records.push({ path, name, bytes: rawBytes, crc, localOffset: localLength });
      localLength += 30 + name.length + rawBytes.length;
    }

    let centralLength = 0;
    for (const record of records) centralLength += 46 + record.name.length;
    const totalLength = localLength + centralLength + 22;
    if (totalLength > MAX_UPLOAD_BYTES) {
      throw new Error("編集後のZIPが2MBを超えます。素材を小さくしてから保存してください。");
    }

    const output = new Uint8Array(totalLength);
    const view = new DataView(output.buffer);
    let offset = 0;
    for (const record of records) {
      writeUint32(view, offset, 0x04034b50); offset += 4;
      writeUint16(view, offset, 20); offset += 2;
      writeUint16(view, offset, 0x0800); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint16(view, offset, 0x0021); offset += 2;
      writeUint32(view, offset, record.crc); offset += 4;
      writeUint32(view, offset, record.bytes.length); offset += 4;
      writeUint32(view, offset, record.bytes.length); offset += 4;
      writeUint16(view, offset, record.name.length); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      output.set(record.name, offset); offset += record.name.length;
      output.set(record.bytes, offset); offset += record.bytes.length;
    }
    const centralOffset = offset;
    for (const record of records) {
      writeUint32(view, offset, 0x02014b50); offset += 4;
      writeUint16(view, offset, 20); offset += 2;
      writeUint16(view, offset, 20); offset += 2;
      writeUint16(view, offset, 0x0800); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint16(view, offset, 0x0021); offset += 2;
      writeUint32(view, offset, record.crc); offset += 4;
      writeUint32(view, offset, record.bytes.length); offset += 4;
      writeUint32(view, offset, record.bytes.length); offset += 4;
      writeUint16(view, offset, record.name.length); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint16(view, offset, 0); offset += 2;
      writeUint32(view, offset, 0); offset += 4;
      writeUint32(view, offset, record.localOffset); offset += 4;
      output.set(record.name, offset); offset += record.name.length;
    }
    const centralSize = offset - centralOffset;
    writeUint32(view, offset, 0x06054b50); offset += 4;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, records.length); offset += 2;
    writeUint16(view, offset, records.length); offset += 2;
    writeUint32(view, offset, centralSize); offset += 4;
    writeUint32(view, offset, centralOffset); offset += 4;
    writeUint16(view, offset, 0); offset += 2;
    if (offset !== output.length) throw new Error("ZIP構築サイズが一致しません。");
    return output;
  }

  function decodeText(bytes, path) {
    if (!TEXT_SUFFIXES.has(suffixOf(path))) throw new Error(`テキスト編集できないファイルです: ${path}`);
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch (error) {
      throw new Error(`${path} はUTF-8テキストではありません。`, { cause: error });
    }
  }

  let apiOrigin = null;
  async function getApiOrigin() {
    if (apiOrigin !== null) return apiOrigin;
    const response = await fetch(CONFIG_PATH, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    if (!response.ok) throw new Error(`Girls config request failed: HTTP ${response.status}`);
    const payload = await response.json();
    if (typeof payload !== "object" || payload === null || Array.isArray(payload) || payload.schema_version !== 1) {
      throw new Error("Girls config response is invalid.");
    }
    const value = payload.hosted_api_base_url;
    if (typeof value !== "string" || value.length === 0 || value !== value.trim()) {
      throw new Error("Girls API origin is invalid.");
    }
    const url = new URL(value);
    if (url.protocol !== "https:" || url.pathname !== "/" || url.search !== "" || url.hash !== "" || url.username !== "" || url.password !== "") {
      throw new Error("Girls API origin must be an HTTPS origin.");
    }
    apiOrigin = url.origin;
    return apiOrigin;
  }

  function getToken() {
    const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    if (token === null || token.length === 0) throw new Error("ログイン情報がありません。もう一度ログインしてください。");
    return token;
  }

  async function authenticatedFetch(path, options = {}) {
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Girls source editor path must be origin-relative.");
    }
    const origin = await getApiOrigin();
    const url = new URL(path, `${origin}/`);
    if (url.origin !== origin) throw new Error("Girls source editor path escaped API origin.");
    const headers = new Headers(options.headers ?? {});
    headers.set("Authorization", `Bearer ${getToken()}`);
    return await fetch(url.toString(), {
      method: options.method ?? "GET",
      headers,
      body: options.body,
      cache: "no-store",
      credentials: "omit",
    });
  }

  async function responseError(response) {
    const contentType = response.headers.get("content-type") ?? "";
    if (contentType.toLowerCase().startsWith("application/json")) {
      const payload = await response.json();
      if (typeof payload === "object" && payload !== null && !Array.isArray(payload) && typeof payload.message === "string" && payload.message.length > 0) {
        return payload.message;
      }
    }
    return `HTTP ${response.status}`;
  }

  async function loadManagedApps() {
    const response = await authenticatedFetch("/hosted/my/apps", { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error(await responseError(response));
    const payload = await response.json();
    if (typeof payload !== "object" || payload === null || Array.isArray(payload) || !Array.isArray(payload.apps)) {
      throw new Error("自分のアプリ一覧の形式が不正です。");
    }
    const result = new Map();
    for (const raw of payload.apps) {
      if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error("アプリ情報の形式が不正です。");
      if (!ID_PATTERN.test(raw.app_id) || !ID_PATTERN.test(raw.group_id) || typeof raw.editable !== "boolean") {
        throw new Error("アプリ情報のIDまたは編集可否が不正です。");
      }
      result.set(raw.app_id, raw);
    }
    return result;
  }

  const style = document.createElement("style");
  style.textContent = `
    .girls-source-secondary { margin-top: 12px; border: 1px dashed #d8b9df; border-radius: 16px; padding: 10px 12px; background: #fffafd; }
    .girls-source-secondary summary { cursor: pointer; color: #765a8e; font-weight: 800; }
    .girls-app-edit-button { min-width: 74px; }
    .girls-source-editor-dialog { width: min(1080px, calc(100vw - 24px)); height: min(820px, calc(100vh - 24px)); border: 0; border-radius: 24px; padding: 0; background: #fffafc; color: #604943; box-shadow: 0 22px 80px rgba(76, 48, 70, .28); }
    .girls-source-editor-dialog::backdrop { background: rgba(74, 55, 71, .36); }
    .girls-source-editor-shell { display: grid; grid-template-rows: auto 1fr auto; height: 100%; min-height: 0; }
    .girls-source-editor-header, .girls-source-editor-footer { display: flex; align-items: center; gap: 10px; padding: 14px 16px; border-bottom: 1px solid #eddde7; }
    .girls-source-editor-footer { border-top: 1px solid #eddde7; border-bottom: 0; justify-content: space-between; flex-wrap: wrap; }
    .girls-source-editor-header h2 { margin: 0; flex: 1; font-size: 1.05rem; }
    .girls-source-editor-main { display: grid; grid-template-columns: 220px minmax(0, 1fr); min-height: 0; }
    .girls-source-editor-files { overflow: auto; padding: 12px; border-right: 1px solid #eddde7; background: #fff7fb; }
    .girls-source-editor-file { width: 100%; margin: 0 0 6px; padding: 8px 10px; border: 0; border-radius: 10px; background: transparent; color: inherit; text-align: left; font: inherit; font-size: .82rem; cursor: pointer; overflow-wrap: anywhere; }
    .girls-source-editor-file[data-active="true"] { background: #f0e5f7; color: #674b84; font-weight: 800; }
    .girls-source-editor-file:disabled { cursor: default; opacity: .55; }
    .girls-source-editor-workspace { display: grid; grid-template-rows: auto 1fr auto; min-width: 0; min-height: 0; padding: 12px; gap: 8px; }
    .girls-source-editor-path { font-weight: 800; color: #765a8e; }
    .girls-source-editor-code { width: 100%; height: 100%; min-height: 260px; resize: none; border: 1px solid #dbc9d6; border-radius: 14px; padding: 12px; background: #fff; color: #3f3439; font: 13px/1.55 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; tab-size: 2; }
    .girls-source-editor-status { min-height: 1.4em; margin: 0; font-size: .8rem; color: #876f7c; }
    .girls-source-editor-status[data-state="error"] { color: #a04455; font-weight: 700; }
    .girls-source-editor-actions { display: flex; gap: 8px; flex-wrap: wrap; }
    .girls-source-editor-add-input, .girls-source-editor-import-input { position: absolute; width: 1px; height: 1px; clip-path: inset(50%); overflow: hidden; }
    @media (max-width: 700px) {
      .girls-source-editor-main { grid-template-columns: 1fr; grid-template-rows: auto 1fr; }
      .girls-source-editor-files { display: flex; gap: 6px; overflow-x: auto; border-right: 0; border-bottom: 1px solid #eddde7; }
      .girls-source-editor-file { width: auto; min-width: max-content; margin: 0; }
    }
  `;
  document.head.append(style);

  const sourceFile = requiredElement("girls-source-file", HTMLInputElement);
  const sourceCode = requiredElement("girls-source-code", HTMLTextAreaElement);
  const uploadSubmit = requiredElement("girls-upload-submit", HTMLButtonElement);
  const uploadTitle = requiredElement("girls-upload-title");
  const sourceBlock = sourceCode.closest(".girls-source-block");
  if (!(sourceBlock instanceof HTMLElement)) throw new Error("Girls source block was not found.");
  const fileLabel = sourceFile.closest("label");
  const codeLabel = sourceCode.closest("label");
  if (!(fileLabel instanceof HTMLLabelElement) || !(codeLabel instanceof HTMLLabelElement)) {
    throw new Error("Girls source labels were not found.");
  }

  uploadTitle.textContent = "アプリをつくる";
  uploadSubmit.textContent = "作って公開 ♡";
  sourceCode.placeholder = "<!doctype html>\n<html lang=\"ja\">\n  <meta charset=\"utf-8\">\n  <title>わたしのアプリ</title>\n  <h1>こんにちは！</h1>\n</html>";
  const codeTextNode = [...codeLabel.childNodes].find((node) => node.nodeType === Node.TEXT_NODE);
  if (codeTextNode) codeTextNode.textContent = "\n                    index.html を編集\n                    ";
  const fileTextNode = [...fileLabel.childNodes].find((node) => node.nodeType === Node.TEXT_NODE);
  if (fileTextNode) fileTextNode.textContent = "\n                    ZIP / HTMLファイルを選ぶ\n                    ";

  const orElement = sourceBlock.querySelector(".girls-or");
  orElement?.remove();
  sourceBlock.insertBefore(codeLabel, sourceBlock.firstChild);
  const advanced = document.createElement("details");
  advanced.className = "girls-source-secondary";
  const advancedSummary = document.createElement("summary");
  advancedSummary.textContent = "別の方法：ZIP / HTMLファイルを読み込む";
  advanced.append(advancedSummary, fileLabel);
  sourceBlock.append(advanced);

  sourceFile.addEventListener("change", () => {
    if (sourceFile.files.length > 0) sourceCode.value = "";
  });
  sourceCode.addEventListener("input", () => {
    if (sourceCode.value.length > 0 && sourceFile.files.length > 0) sourceFile.value = "";
  });

  for (const button of document.querySelectorAll('[data-girls-view="add"]')) {
    const label = button.querySelector("span:last-child");
    if (label instanceof HTMLElement) label.textContent = "アプリをつくる";
  }
  for (const button of document.querySelectorAll('[data-girls-open-view="add"]')) {
    const strong = button.querySelector("strong");
    const small = button.querySelector("small");
    if (strong instanceof HTMLElement) strong.textContent = "アプリをつくる";
    if (small instanceof HTMLElement) small.textContent = "エディタですぐ作る";
  }

  const dialog = document.createElement("dialog");
  dialog.className = "girls-source-editor-dialog";
  dialog.innerHTML = `
    <div class="girls-source-editor-shell">
      <header class="girls-source-editor-header">
        <h2 id="girls-source-editor-title">アプリを編集</h2>
        <button id="girls-source-editor-close" class="girls-secondary" type="button">閉じる</button>
      </header>
      <div class="girls-source-editor-main">
        <aside class="girls-source-editor-files" id="girls-source-editor-files"></aside>
        <section class="girls-source-editor-workspace">
          <div class="girls-source-editor-path" id="girls-source-editor-path">index.html</div>
          <textarea id="girls-source-editor-code" class="girls-source-editor-code" spellcheck="false"></textarea>
          <p id="girls-source-editor-status" class="girls-source-editor-status" role="status"></p>
        </section>
      </div>
      <footer class="girls-source-editor-footer">
        <div class="girls-source-editor-actions">
          <label class="girls-secondary" tabindex="0">＋ ファイルを追加<input id="girls-source-editor-add" class="girls-source-editor-add-input" type="file" multiple /></label>
          <button id="girls-source-editor-delete" class="girls-secondary" type="button">このファイルを削除</button>
          <button id="girls-source-editor-download" class="girls-secondary" type="button">ZIPを書き出す</button>
          <label class="girls-secondary" tabindex="0">ZIPで置き換え<input id="girls-source-editor-import" class="girls-source-editor-import-input" type="file" accept=".zip,application/zip" /></label>
        </div>
        <button id="girls-source-editor-save" class="girls-primary" type="button">保存して公開 ♡</button>
      </footer>
    </div>`;
  document.body.append(dialog);

  const editorTitle = requiredElement("girls-source-editor-title");
  const closeButton = requiredElement("girls-source-editor-close", HTMLButtonElement);
  const filesElement = requiredElement("girls-source-editor-files");
  const pathElement = requiredElement("girls-source-editor-path");
  const codeElement = requiredElement("girls-source-editor-code", HTMLTextAreaElement);
  const statusElement = requiredElement("girls-source-editor-status");
  const addInput = requiredElement("girls-source-editor-add", HTMLInputElement);
  const deleteButton = requiredElement("girls-source-editor-delete", HTMLButtonElement);
  const downloadButton = requiredElement("girls-source-editor-download", HTMLButtonElement);
  const importInput = requiredElement("girls-source-editor-import", HTMLInputElement);
  const saveButton = requiredElement("girls-source-editor-save", HTMLButtonElement);

  let currentApp = null;
  let currentRevision = null;
  let entries = null;
  let activePath = null;
  let busy = false;

  function setStatus(message, state = "idle") {
    statusElement.textContent = message;
    statusElement.dataset.state = state;
  }

  function setBusy(value) {
    busy = value;
    closeButton.disabled = value;
    addInput.disabled = value;
    deleteButton.disabled = value || activePath === "index.html";
    downloadButton.disabled = value;
    importInput.disabled = value;
    saveButton.disabled = value;
    codeElement.disabled = value || activePath === null || !TEXT_SUFFIXES.has(suffixOf(activePath));
  }

  function commitActiveText() {
    if (!(entries instanceof Map) || activePath === null) return;
    if (!TEXT_SUFFIXES.has(suffixOf(activePath))) return;
    entries.set(activePath, new TextEncoder().encode(codeElement.value));
  }

  function renderFiles() {
    if (!(entries instanceof Map)) throw new Error("Editor source is not loaded.");
    filesElement.replaceChildren();
    for (const path of [...entries.keys()].sort()) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "girls-source-editor-file";
      button.dataset.active = String(path === activePath);
      button.textContent = `${TEXT_SUFFIXES.has(suffixOf(path)) ? "📄" : "◻"} ${path}`;
      button.disabled = busy;
      button.addEventListener("click", () => {
        if (busy) return;
        commitActiveText();
        activePath = path;
        renderFiles();
        renderActiveFile();
      });
      filesElement.append(button);
    }
  }

  function renderActiveFile() {
    if (!(entries instanceof Map) || activePath === null) throw new Error("Editor source is not loaded.");
    pathElement.textContent = activePath;
    const editable = TEXT_SUFFIXES.has(suffixOf(activePath));
    if (editable) {
      codeElement.value = decodeText(entries.get(activePath), activePath);
      codeElement.placeholder = "";
    } else {
      codeElement.value = "";
      codeElement.placeholder = "このファイルは素材として保持されます。テキスト編集はできません。";
    }
    codeElement.disabled = busy || !editable;
    deleteButton.disabled = busy || activePath === "index.html";
  }

  async function fetchSource(app) {
    const response = await authenticatedFetch(`/hosted/groups/${app.group_id}/apps/${app.app_id}/source`, {
      headers: { Accept: "application/zip" },
    });
    if (!response.ok) throw new Error(await responseError(response));
    const revision = Number(response.headers.get("x-minapp-source-revision"));
    if (!Number.isInteger(revision) || revision < 1) throw new Error("現在版を確認できませんでした。");
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0 || bytes.length > MAX_UPLOAD_BYTES) throw new Error("取得したZIPのサイズが不正です。");
    return { revision, bytes };
  }

  async function openEditor(app) {
    currentApp = app;
    currentRevision = null;
    entries = null;
    activePath = null;
    editorTitle.textContent = `${app.title} を編集`;
    setStatus("ソースを読み込んでいます…");
    if (!dialog.open) dialog.showModal();
    setBusy(true);
    try {
      const source = await fetchSource(app);
      entries = await readZip(source.bytes);
      currentRevision = source.revision;
      activePath = "index.html";
      renderFiles();
      renderActiveFile();
      setStatus("現在版を編集中");
    } catch (error) {
      setStatus(errorMessage(error), "error");
      throw error;
    } finally {
      setBusy(false);
    }
  }

  closeButton.addEventListener("click", () => {
    if (busy) return;
    dialog.close();
  });

  dialog.addEventListener("close", () => {
    currentApp = null;
    currentRevision = null;
    entries = null;
    activePath = null;
    filesElement.replaceChildren();
    codeElement.value = "";
    setStatus("");
  });

  addInput.addEventListener("change", async () => {
    if (!(entries instanceof Map) || addInput.files.length === 0) return;
    try {
      commitActiveText();
      for (const file of addInput.files) {
        const path = validatePath(file.name);
        if (entries.has(path)) throw new Error(`同名ファイルがすでにあります: ${path}`);
        entries.set(path, new Uint8Array(await file.arrayBuffer()));
      }
      renderFiles();
      setStatus("ファイルを追加しました。保存するまで公開版は変わりません。");
    } catch (error) {
      setStatus(errorMessage(error), "error");
    } finally {
      addInput.value = "";
    }
  });

  deleteButton.addEventListener("click", () => {
    if (!(entries instanceof Map) || activePath === null || activePath === "index.html") return;
    const deleting = activePath;
    entries.delete(deleting);
    activePath = "index.html";
    renderFiles();
    renderActiveFile();
    setStatus(`${deleting} を削除しました。保存するまで公開版は変わりません。`);
  });

  downloadButton.addEventListener("click", () => {
    if (!(entries instanceof Map) || currentApp === null) return;
    try {
      commitActiveText();
      const bytes = buildZip(entries);
      const blob = new Blob([bytes], { type: "application/zip" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `minapp-${currentApp.app_id}.zip`;
      document.body.append(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
      setStatus("ZIPを書き出しました。");
    } catch (error) {
      setStatus(errorMessage(error), "error");
    }
  });

  importInput.addEventListener("change", async () => {
    const file = importInput.files.length === 1 ? importInput.files[0] : null;
    if (file === null) return;
    try {
      if (!file.name.toLowerCase().endsWith(".zip")) throw new Error(".zip ファイルを選んでください。");
      if (file.size <= 0 || file.size > MAX_UPLOAD_BYTES) throw new Error("ZIPは1byte以上2MB以下にしてください。");
      const imported = await readZip(new Uint8Array(await file.arrayBuffer()));
      entries = imported;
      activePath = "index.html";
      renderFiles();
      renderActiveFile();
      setStatus("ZIPを読み込みました。保存するまで公開版は変わりません。");
    } catch (error) {
      setStatus(errorMessage(error), "error");
    } finally {
      importInput.value = "";
    }
  });

  saveButton.addEventListener("click", async () => {
    if (currentApp === null || currentRevision === null || !(entries instanceof Map)) return;
    setBusy(true);
    setStatus("保存しています…");
    try {
      commitActiveText();
      const zipBytes = buildZip(entries);
      const update = await authenticatedFetch(
        `/hosted/groups/${currentApp.group_id}/apps/${currentApp.app_id}/source?revision=${currentRevision}`,
        {
          method: "POST",
          headers: { Accept: "application/json", "Content-Type": "application/zip" },
          body: zipBytes,
        },
      );
      if (!update.ok) throw new Error(await responseError(update));
      const updatePayload = await update.json();
      if (!Number.isInteger(updatePayload.revision) || updatePayload.revision !== currentRevision + 1) {
        throw new Error("現在版の更新情報が不正です。");
      }
      const nextRevision = updatePayload.revision;
      const publish = await authenticatedFetch(
        `/hosted/groups/${currentApp.group_id}/apps/${currentApp.app_id}/publish`,
        {
          method: "POST",
          headers: { Accept: "application/json", "Content-Type": "application/json" },
          body: JSON.stringify({ revision: nextRevision }),
        },
      );
      if (!publish.ok) {
        currentRevision = nextRevision;
        throw new Error(`現在版は保存されましたが、公開版の更新に失敗しました: ${await responseError(publish)}`);
      }
      const publishPayload = await publish.json();
      if (publishPayload.source_revision !== nextRevision || !Number.isInteger(publishPayload.published_version)) {
        throw new Error("公開結果の版情報が不正です。");
      }
      currentRevision = nextRevision;
      setStatus("現在版を保存して公開版を更新しました。");
      const refresh = document.getElementById("girls-apps-refresh");
      if (refresh instanceof HTMLButtonElement) refresh.click();
    } catch (error) {
      setStatus(errorMessage(error), "error");
    } finally {
      setBusy(false);
    }
  });

  const appList = requiredElement("girls-app-list");
  let decorateScheduled = false;
  let managedApps = null;
  let managedAppsPromise = null;

  async function getManagedApps() {
    if (managedApps !== null) return managedApps;
    if (managedAppsPromise === null) {
      managedAppsPromise = loadManagedApps().then((value) => {
        managedApps = value;
        return value;
      }).finally(() => {
        managedAppsPromise = null;
      });
    }
    return await managedAppsPromise;
  }

  async function decorateCards() {
    const managed = await getManagedApps();
    for (const card of appList.children) {
      if (!(card instanceof HTMLElement) || !card.classList.contains("girls-app-card")) continue;
      const appId = card.dataset.girlsAppId ?? "";
      if (!ID_PATTERN.test(appId) || card.querySelector(".girls-app-edit-button") !== null) continue;
      const app = managed.get(appId);
      if (app === undefined || app.editable !== true) continue;
      const actions = card.querySelector(".girls-app-card-actions");
      if (!(actions instanceof HTMLElement)) continue;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "girls-secondary girls-app-edit-button";
      button.textContent = "編集";
      button.addEventListener("click", () => {
        void openEditor(app).catch((error) => {
          console.error("Girls app source editor failed", error);
        });
      });
      actions.prepend(button);
    }
  }

  function scheduleDecorate() {
    if (decorateScheduled) return;
    decorateScheduled = true;
    queueMicrotask(() => {
      decorateScheduled = false;
      void decorateCards().catch((error) => console.error("Girls source editor card decoration failed", error));
    });
  }

  new MutationObserver(scheduleDecorate).observe(appList, { childList: true, subtree: true, attributes: true, attributeFilter: ["data-girls-app-id"] });
  const refreshButton = requiredElement("girls-apps-refresh", HTMLButtonElement);
  refreshButton.addEventListener("click", () => {
    managedApps = null;
  });
  scheduleDecorate();

  globalThis.MinAppGirlsAppSourceEditor = Object.freeze({ readZip, buildZip });
})();
