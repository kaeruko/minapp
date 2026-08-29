"use strict";

(() => {
  if (window.__olHomeEffectsInstalled === true) {
    return;
  }

  const building = document.getElementById("building");
  const board = document.getElementById("board");
  const ol = document.getElementById("ol");
  const homeMarker = document.getElementById("homeMarker");
  const progress = document.getElementById("progress");

  if (!building || !board || !ol || !homeMarker || !progress) {
    throw new Error("OL home effects initialization failed: required DOM element is missing.");
  }

  const windows = Array.from(board.querySelectorAll(".window"));
  if (windows.length === 0) {
    throw new Error("OL home effects initialization failed: window cells are missing.");
  }

  const style = document.createElement("style");
  style.textContent = `
    .window.match-burst {
      z-index: 8 !important;
      animation: ol-home-match-burst .52s cubic-bezier(.2,.8,.2,1) !important;
    }

    .window.route-trail::before {
      content: "✦";
      position: absolute;
      z-index: 12;
      left: 50%;
      top: 50%;
      color: #fffbe6;
      font-size: clamp(13px, 4vw, 22px);
      line-height: 1;
      text-shadow: 0 0 8px #fff4a8, 0 0 14px #ffffff;
      pointer-events: none;
      animation: ol-home-trail-spark .48s ease-out forwards;
    }

    .ol-home-sparkle {
      position: absolute;
      z-index: 22;
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #fffbe6;
      box-shadow: 0 0 8px #fff4a8, 0 0 13px #ffffff;
      pointer-events: none;
      transform: translate(-50%, -50%);
      animation: ol-home-sparkle-fly .58s ease-out forwards;
    }

    .ol-home-match-toast {
      position: absolute;
      z-index: 25;
      left: 50%;
      top: 8%;
      transform: translate(-50%, 8px) scale(.94);
      padding: 7px 13px;
      border: 3px solid #fff;
      border-radius: 999px;
      background: #fff8dff2;
      box-shadow: 0 5px 0 #9a7458, 0 0 18px #fff5b888;
      color: #6d5145;
      font-size: clamp(13px, 4vw, 19px);
      font-weight: 1000;
      white-space: nowrap;
      opacity: 0;
      pointer-events: none;
      transition: opacity .16s ease, transform .16s ease;
    }

    .ol-home-match-toast.show {
      opacity: 1;
      transform: translate(-50%, 0) scale(1);
    }

    .home-marker.ol-home-arrived {
      animation: ol-home-arrive .75s ease-in-out infinite alternate !important;
      background: #fff0a8 !important;
      box-shadow: 0 4px 0 #a67f5e, 0 0 24px #fff2a8, 0 0 42px #ffffffaa !important;
    }

    @keyframes ol-home-match-burst {
      0% { transform: scale(1); filter: brightness(1); }
      36% { transform: scale(1.2); filter: brightness(1.45); }
      68% { transform: scale(.96); filter: brightness(1.18); }
      100% { transform: scale(1.06); filter: brightness(1.28); }
    }

    @keyframes ol-home-trail-spark {
      0% { opacity: 0; transform: translate(-50%, -50%) scale(.35) rotate(0deg); }
      35% { opacity: 1; transform: translate(-50%, -68%) scale(1.25) rotate(35deg); }
      100% { opacity: 0; transform: translate(-50%, -120%) scale(.55) rotate(80deg); }
    }

    @keyframes ol-home-sparkle-fly {
      from { opacity: 1; transform: translate(-50%, -50%) scale(1); }
      to { opacity: 0; transform: translate(calc(-50% + var(--spark-x)), calc(-50% + var(--spark-y))) scale(.25); }
    }

    @keyframes ol-home-arrive {
      from { transform: rotate(-3deg) scale(1); }
      to { transform: rotate(3deg) scale(1.12); }
    }
  `;
  document.head.appendChild(style);

  const toast = document.createElement("div");
  toast.className = "ol-home-match-toast";
  toast.setAttribute("aria-live", "polite");
  building.appendChild(toast);

  let toastTimer = null;
  let lastRouteSignature = null;
  let lastTrailIndex = null;
  let trailFramePending = false;
  let lastProgress = Number.parseInt(progress.textContent ?? "0", 10);
  if (!Number.isInteger(lastProgress)) {
    throw new Error(`OL home effects found invalid progress: ${progress.textContent}.`);
  }

  function showToast(text) {
    if (typeof text !== "string" || text.trim().length === 0) {
      throw new TypeError("OL home effect toast text must be a non-empty string.");
    }
    toast.textContent = text;
    toast.classList.remove("show");
    void toast.offsetWidth;
    toast.classList.add("show");
    if (toastTimer !== null) {
      window.clearTimeout(toastTimer);
    }
    toastTimer = window.setTimeout(() => {
      toast.classList.remove("show");
      toastTimer = null;
    }, 900);
  }

  function centerInsideBuilding(cell) {
    const buildingRect = building.getBoundingClientRect();
    const cellRect = cell.getBoundingClientRect();
    return {
      x: cellRect.left - buildingRect.left + cellRect.width / 2,
      y: cellRect.top - buildingRect.top + cellRect.height / 2,
    };
  }

  function spawnSparkles(cell) {
    if (!(cell instanceof HTMLElement) || !cell.classList.contains("window")) {
      throw new TypeError("OL home sparkle target must be a window element.");
    }
    const center = centerInsideBuilding(cell);
    const sparkleCount = 4;
    for (let i = 0; i < sparkleCount; i += 1) {
      const sparkle = document.createElement("span");
      sparkle.className = "ol-home-sparkle";
      sparkle.style.left = `${center.x}px`;
      sparkle.style.top = `${center.y}px`;
      const angle = (Math.PI * 2 * i) / sparkleCount + Math.PI / 8;
      const distance = 18 + i * 3;
      sparkle.style.setProperty("--spark-x", `${Math.cos(angle) * distance}px`);
      sparkle.style.setProperty("--spark-y", `${Math.sin(angle) * distance}px`);
      building.appendChild(sparkle);
      window.setTimeout(() => sparkle.remove(), 650);
    }
  }

  function celebrateRoute() {
    const routeCells = Array.from(board.querySelectorAll(".window.route"));
    if (routeCells.length === 0) {
      lastRouteSignature = null;
      lastTrailIndex = null;
      return;
    }
    if (routeCells.length < 4) {
      return;
    }

    const signature = routeCells
      .map((cell) => cell.dataset.index ?? "")
      .join(",");
    if (signature === lastRouteSignature) {
      return;
    }
    lastRouteSignature = signature;

    for (const cell of routeCells) {
      cell.classList.add("match-burst");
      spawnSparkles(cell);
      window.setTimeout(() => cell.classList.remove("match-burst"), 520);
    }
    showToast(`${routeCells.length}つ そろった！ ✨`);
  }

  function nearestRouteCellToOl() {
    const routeCells = Array.from(board.querySelectorAll(".window.route"));
    if (routeCells.length === 0) {
      return null;
    }
    const olRect = ol.getBoundingClientRect();
    const ox = olRect.left + olRect.width / 2;
    const oy = olRect.top + olRect.height / 2;
    let best = null;
    let bestDistance = Number.POSITIVE_INFINITY;

    for (const cell of routeCells) {
      const rect = cell.getBoundingClientRect();
      const dx = rect.left + rect.width / 2 - ox;
      const dy = rect.top + rect.height / 2 - oy;
      const distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = cell;
      }
    }
    return best;
  }

  function markOlTrail() {
    trailFramePending = false;
    const cell = nearestRouteCellToOl();
    if (!cell) {
      return;
    }
    const index = cell.dataset.index;
    if (index === undefined || index === lastTrailIndex) {
      return;
    }
    lastTrailIndex = index;
    cell.classList.remove("route-trail");
    void cell.offsetWidth;
    cell.classList.add("route-trail");
    spawnSparkles(cell);
    window.setTimeout(() => cell.classList.remove("route-trail"), 520);
  }

  function scheduleTrailCheck() {
    if (trailFramePending) {
      return;
    }
    trailFramePending = true;
    window.requestAnimationFrame(markOlTrail);
  }

  function updateGoalEffect() {
    const value = Number.parseInt(progress.textContent ?? "", 10);
    if (!Number.isInteger(value) || value < 0) {
      throw new Error(`OL home effects found invalid progress: ${progress.textContent}.`);
    }
    if (value === 0) {
      homeMarker.classList.remove("ol-home-arrived");
      lastTrailIndex = null;
    }
    if (value >= 6 && lastProgress < 6) {
      homeMarker.classList.add("ol-home-arrived");
      showToast("🏠 ただいま〜！");
    }
    lastProgress = value;
  }

  const boardObserver = new MutationObserver(() => {
    window.setTimeout(celebrateRoute, 0);
  });
  boardObserver.observe(board, {
    subtree: true,
    attributes: true,
    attributeFilter: ["class"],
  });

  const olObserver = new MutationObserver(scheduleTrailCheck);
  olObserver.observe(ol, {
    attributes: true,
    attributeFilter: ["style"],
  });

  const progressObserver = new MutationObserver(updateGoalEffect);
  progressObserver.observe(progress, {
    childList: true,
    characterData: true,
    subtree: true,
  });

  window.__olHomeEffectsInstalled = true;
})();
