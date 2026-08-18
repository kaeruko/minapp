"use strict";

if (typeof phase2BinaryUpload !== "function") {
  throw new Error("phase2BinaryUpload must be defined before phase2_transport.js.");
}
if (typeof binaryApiRequest !== "function") {
  throw new Error("binaryApiRequest must be defined before phase2_transport.js.");
}

phase2BinaryUpload = async function phase2BinaryUploadThroughSelectedTenant(path, file) {
  return binaryApiRequest(path, file, "application/zip");
};
