"use strict";

(function attachSingleHtmlZip(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.MinAppSingleHtmlZip = api;
})(typeof globalThis === "object" ? globalThis : this, function buildSingleHtmlZipApi() {
  const INDEX_FILENAME = "index.html";
  const ZIP_UTF8_FLAG = 0x0800;
  const ZIP_STORE_METHOD = 0;
  const DOS_TIME_MIDNIGHT = 0x0000;
  const DOS_DATE_1980_01_01 = 0x0021;

  function requireTextEncoder() {
    if (typeof TextEncoder !== "function") {
      throw new Error("TextEncoder is required to build a ZIP archive.");
    }
    return new TextEncoder();
  }

  function writeUint16(view, offset, value) {
    view.setUint16(offset, value, true);
  }

  function writeUint32(view, offset, value) {
    view.setUint32(offset, value >>> 0, true);
  }

  function crc32(bytes) {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("crc32 input must be a Uint8Array.");
    }
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

  function buildSingleHtmlZip(htmlText) {
    if (typeof htmlText !== "string") {
      throw new TypeError("htmlText must be a string.");
    }
    if (htmlText.length === 0) {
      throw new Error("htmlText must not be empty.");
    }

    const encoder = requireTextEncoder();
    const filenameBytes = encoder.encode(INDEX_FILENAME);
    const htmlBytes = encoder.encode(htmlText);
    if (htmlBytes.length === 0) {
      throw new Error("Encoded HTML must not be empty.");
    }
    if (htmlBytes.length > 0xffffffff) {
      throw new RangeError("HTML is too large for the supported ZIP format.");
    }

    const checksum = crc32(htmlBytes);
    const localHeaderLength = 30 + filenameBytes.length;
    const centralHeaderLength = 46 + filenameBytes.length;
    const centralDirectoryOffset = localHeaderLength + htmlBytes.length;
    const centralDirectorySize = centralHeaderLength;
    const totalLength = centralDirectoryOffset + centralDirectorySize + 22;
    if (!Number.isSafeInteger(totalLength) || totalLength > 0xffffffff) {
      throw new RangeError("ZIP output is too large for the supported ZIP format.");
    }

    const output = new Uint8Array(totalLength);
    const view = new DataView(output.buffer);

    let offset = 0;
    writeUint32(view, offset, 0x04034b50); offset += 4;
    writeUint16(view, offset, 20); offset += 2;
    writeUint16(view, offset, ZIP_UTF8_FLAG); offset += 2;
    writeUint16(view, offset, ZIP_STORE_METHOD); offset += 2;
    writeUint16(view, offset, DOS_TIME_MIDNIGHT); offset += 2;
    writeUint16(view, offset, DOS_DATE_1980_01_01); offset += 2;
    writeUint32(view, offset, checksum); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint16(view, offset, filenameBytes.length); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    output.set(filenameBytes, offset); offset += filenameBytes.length;
    output.set(htmlBytes, offset); offset += htmlBytes.length;

    if (offset !== centralDirectoryOffset) {
      throw new Error("ZIP local record length mismatch.");
    }

    writeUint32(view, offset, 0x02014b50); offset += 4;
    writeUint16(view, offset, 20); offset += 2;
    writeUint16(view, offset, 20); offset += 2;
    writeUint16(view, offset, ZIP_UTF8_FLAG); offset += 2;
    writeUint16(view, offset, ZIP_STORE_METHOD); offset += 2;
    writeUint16(view, offset, DOS_TIME_MIDNIGHT); offset += 2;
    writeUint16(view, offset, DOS_DATE_1980_01_01); offset += 2;
    writeUint32(view, offset, checksum); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint16(view, offset, filenameBytes.length); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint32(view, offset, 0); offset += 4;
    writeUint32(view, offset, 0); offset += 4;
    output.set(filenameBytes, offset); offset += filenameBytes.length;

    writeUint32(view, offset, 0x06054b50); offset += 4;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 1); offset += 2;
    writeUint16(view, offset, 1); offset += 2;
    writeUint32(view, offset, centralDirectorySize); offset += 4;
    writeUint32(view, offset, centralDirectoryOffset); offset += 4;
    writeUint16(view, offset, 0); offset += 2;

    if (offset !== output.length) {
      throw new Error("ZIP output length mismatch.");
    }
    return output;
  }

  return Object.freeze({
    INDEX_FILENAME,
    buildSingleHtmlZip,
  });
});
