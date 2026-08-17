"use strict";

const statusElement = document.getElementById("api-status");

if (!(statusElement instanceof HTMLElement)) {
  throw new Error("Required element #api-status was not found.");
}

async function loadApiStatus() {
  const response = await fetch("/api/health", {
    method: "GET",
    headers: { Accept: "application/json" },
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`Health endpoint returned HTTP ${response.status}.`);
  }

  const payload = await response.json();

  if (
    typeof payload !== "object" ||
    payload === null ||
    payload.status !== "ok" ||
    payload.service !== "minapp-api"
  ) {
    throw new Error("Health endpoint returned an unexpected payload.");
  }

  statusElement.textContent = `接続OK · ${payload.version}`;
  statusElement.className = "status status-ok";
}

loadApiStatus().catch((error) => {
  console.error(error);
  statusElement.textContent = "API接続エラー";
  statusElement.className = "status status-error";
});
