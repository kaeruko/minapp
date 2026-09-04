"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { INDEX_FILENAME, buildSingleHtmlZip } = require("./single_html_zip.js");

function uint16(bytes, offset) {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint16(offset, true);
}

function uint32(bytes, offset) {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(offset, true);
}

test("buildSingleHtmlZip creates one stored index.html entry", () => {
  const html = "<!doctype html><html><body>こんにちは♡</body></html>";
  const bytes = buildSingleHtmlZip(html);
  const decoder = new TextDecoder();

  assert.equal(uint32(bytes, 0), 0x04034b50);
  assert.equal(uint16(bytes, 8), 0);
  const compressedSize = uint32(bytes, 18);
  const uncompressedSize = uint32(bytes, 22);
  const filenameLength = uint16(bytes, 26);
  const extraLength = uint16(bytes, 28);
  assert.equal(compressedSize, uncompressedSize);
  assert.equal(extraLength, 0);

  const filenameStart = 30;
  const filename = decoder.decode(bytes.slice(filenameStart, filenameStart + filenameLength));
  assert.equal(filename, INDEX_FILENAME);

  const contentStart = filenameStart + filenameLength;
  const content = decoder.decode(bytes.slice(contentStart, contentStart + uncompressedSize));
  assert.equal(content, html);

  const centralDirectoryOffset = contentStart + uncompressedSize;
  assert.equal(uint32(bytes, centralDirectoryOffset), 0x02014b50);
  assert.equal(uint32(bytes, bytes.length - 22), 0x06054b50);
  assert.equal(uint16(bytes, bytes.length - 14), 1);
  assert.equal(uint16(bytes, bytes.length - 12), 1);
});

test("buildSingleHtmlZip rejects empty or non-string input", () => {
  assert.throws(() => buildSingleHtmlZip(""), /must not be empty/);
  assert.throws(() => buildSingleHtmlZip(null), /must be a string/);
});
