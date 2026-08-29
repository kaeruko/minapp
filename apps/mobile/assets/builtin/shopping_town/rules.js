"use strict";

if (typeof state === "undefined" || typeof obstacles === "undefined" ||
    typeof player === "undefined" || typeof coinElements === "undefined" ||
    typeof rectanglesOverlap !== "function" || typeof registerHit !== "function" ||
    typeof duckButton === "undefined" || typeof jumpButton === "undefined") {
  throw new Error("Shopping town rules initialization failed: required game globals are missing.");
}

for (const obstacle of obstacles) {
  const kind = obstacle.dataset.kind;
  if (kind !== "ground" && kind !== "high") {
    throw new Error(`Unknown obstacle kind: ${kind}.`);
  }
}

const duckStyle = document.createElement("style");
duckStyle.textContent = `
  .player.ducking {
    height: 79px !important;
    transform: translate3d(0, 4px, 0) scaleY(.78) !important;
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
  hint.textContent = ducking
    ? "しゃがんで よけるよ！"
    : "しょうがいぶつを よけて スーパーへ！";
}

function toggleDuckFromButton(event) {
  event.preventDefault();
  event.stopImmediatePropagation();
  if (state.phase !== "running") {
    return;
  }
  applyDuckState(!state.ducking);
}

function suppressOriginalDuckPointerHandler(event) {
  event.preventDefault();
  event.stopImmediatePropagation();
}

duckButton.addEventListener("pointerdown", toggleDuckFromButton, true);
duckButton.addEventListener("pointerup", suppressOriginalDuckPointerHandler, true);
duckButton.addEventListener("pointercancel", suppressOriginalDuckPointerHandler, true);
duckButton.addEventListener("click", suppressOriginalDuckPointerHandler, true);

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
      applyDuckState(!state.ducking);
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
