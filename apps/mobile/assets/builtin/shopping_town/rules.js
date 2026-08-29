"use strict";

if (typeof state === "undefined" || typeof obstacles === "undefined" ||
    typeof player === "undefined" || typeof coinElements === "undefined" ||
    typeof rectanglesOverlap !== "function" || typeof registerHit !== "function" ||
    typeof duckButton === "undefined" || typeof jumpButton === "undefined" ||
    typeof resetGameState !== "function" || typeof updateJump !== "function") {
  throw new Error("Shopping town rules initialization failed: required game globals are missing.");
}

for (const obstacle of obstacles) {
  const kind = obstacle.dataset.kind;
  if (kind !== "ground" && kind !== "high") {
    throw new Error(`Unknown obstacle kind: ${kind}.`);
  }
}

const DUCK_BUTTON_LABEL = "↘ しゃがむ";
const STAND_BUTTON_LABEL = "↑ たつ";
const POINTER_CLICK_DEDUP_MS = 500;
const JUMP_DURATION_OVERRIDE_MS = 900;
let lastDuckPointerToggleAt = Number.NEGATIVE_INFINITY;

const duckStyle = document.createElement("style");
duckStyle.textContent = `
  .player.ducking {
    height: 79px !important;
    transform: translate3d(0, 18px, 0) scaleY(.62) !important;
  }
`;
document.head.appendChild(duckStyle);

function applyDuckState(ducking) {
  if (typeof ducking !== "boolean") {
    throw new TypeError(`ducking must be boolean; got ${typeof ducking}.`);
  }
  if (state.phase !== "running") {
    return;
  }
  if (ducking && state.jumping) {
    return;
  }

  state.ducking = ducking;
  player.classList.toggle("ducking", ducking);
  duckButton.classList.toggle("active", ducking);
  duckButton.textContent = ducking ? STAND_BUTTON_LABEL : DUCK_BUTTON_LABEL;

  if (ducking) {
    player.style.setProperty(
      "transform",
      "translate3d(0, 18px, 0) scaleY(.62)",
      "important"
    );
  } else {
    player.style.removeProperty("transform");
    if (!state.jumping) {
      player.style.transform = "translate3d(0, 0, 0)";
    }
  }

  hint.textContent = ducking
    ? "しゃがんで よけるよ！"
    : "しょうがいぶつを よけて スーパーへ！";
}

function toggleDuck() {
  if (state.phase !== "running") {
    return;
  }
  applyDuckState(!state.ducking);
}

function onDuckPointerDown(event) {
  event.preventDefault();
  event.stopImmediatePropagation();
  toggleDuck();
  lastDuckPointerToggleAt = performance.now();
}

function suppressOriginalDuckPointerHandler(event) {
  event.preventDefault();
  event.stopImmediatePropagation();
}

function onDuckClick(event) {
  event.preventDefault();
  event.stopImmediatePropagation();
  const elapsedSincePointerToggle = performance.now() - lastDuckPointerToggleAt;
  if (elapsedSincePointerToggle > POINTER_CLICK_DEDUP_MS) {
    toggleDuck();
  }
}

duckButton.addEventListener("pointerdown", onDuckPointerDown, true);
duckButton.addEventListener("pointerup", suppressOriginalDuckPointerHandler, true);
duckButton.addEventListener("pointercancel", suppressOriginalDuckPointerHandler, true);
duckButton.addEventListener("click", onDuckClick, true);

jumpButton.addEventListener("click", () => {
  if (state.ducking) {
    applyDuckState(false);
  }
}, true);

window.addEventListener("keydown", (event) => {
  if (event.code === "ArrowDown") {
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!event.repeat) {
      toggleDuck();
    }
    return;
  }
  if ((event.code === "Space" || event.code === "ArrowUp") && state.ducking) {
    applyDuckState(false);
  }
}, true);

window.addEventListener("keyup", (event) => {
  if (event.code === "ArrowDown") {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
}, true);

const originalResetGameState = resetGameState;
resetGameState = function resetGameStateWithDuckVisualReset() {
  originalResetGameState();
  duckButton.textContent = DUCK_BUTTON_LABEL;
  player.style.removeProperty("transform");
  player.style.transform = "translate3d(0, 0, 0)";
};

updateJump = function updateJumpWithLongerAirtime(now) {
  if (!state.jumping) {
    if (!state.ducking) {
      player.style.transform = "translate3d(0, 0, 0)";
    }
    return;
  }

  if (state.jumpStartedAt === null) {
    state.jumpStartedAt = now;
  }
  const elapsed = now - state.jumpStartedAt;
  const t = elapsed / JUMP_DURATION_OVERRIDE_MS;
  if (t >= 1) {
    state.jumping = false;
    state.jumpStartedAt = null;
    player.style.transform = "translate3d(0, 0, 0)";
    hint.textContent = "しょうがいぶつを よけて スーパーへ！";
    return;
  }

  if (t < 0) {
    throw new RangeError(`Jump elapsed time cannot be negative: ${elapsed}.`);
  }
  const y = 4 * JUMP_HEIGHT_PX * t * (1 - t);
  player.style.transform = `translate3d(0, ${-y}px, 0)`;
};

checkCollisions = function checkCollisionsWithActions(now) {
  if (state.phase !== "running") {
    return;
  }
  const playerRect = player.getBoundingClientRect();

  for (const obstacle of obstacles) {
    if (obstacle.dataset.hit === "true") {
      continue;
    }

    const kind = obstacle.dataset.kind;
    if ((kind === "ground" && state.jumping) ||
        (kind === "high" && state.ducking)) {
      continue;
    }

    const obstacleRect = obstacle.getBoundingClientRect();
    if (!rectanglesOverlap(playerRect, obstacleRect, OBSTACLE_HITBOX_INSET_PX)) {
      continue;
    }
    registerHit(now, obstacle);
    if (state.phase !== "running") {
      return;
    }
  }

  for (const coin of coinElements) {
    if (coin.dataset.collected === "true") {
      continue;
    }
    const coinRect = coin.getBoundingClientRect();
    if (!rectanglesOverlap(playerRect, coinRect)) {
      continue;
    }
    coin.dataset.collected = "true";
    coin.classList.add("collected");
    state.coins += 1;
    coinsLabel.textContent = String(state.coins);
    hint.textContent = "コイン みつけた！";
  }
};
