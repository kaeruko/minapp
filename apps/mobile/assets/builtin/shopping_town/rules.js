"use strict";

if (typeof state === "undefined" || typeof obstacles === "undefined" ||
    typeof player === "undefined" || typeof coinElements === "undefined" ||
    typeof rectanglesOverlap !== "function" || typeof registerHit !== "function") {
  throw new Error("Shopping town rules initialization failed: required game globals are missing.");
}

for (const obstacle of obstacles) {
  const kind = obstacle.dataset.kind;
  if (kind !== "ground" && kind !== "high") {
    throw new Error(`Unknown obstacle kind: ${kind}.`);
  }
}

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
