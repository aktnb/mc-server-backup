#!/usr/bin/env bash
set -euo pipefail

source /opt/minecraft-backup/env

FORCE_ALL=false

if [ "${1:-}" = "--all" ]; then
  FORCE_ALL=true
fi

DATE="$(date +%F-%H%M%S)"
DAY_OF_WEEK="$(date +%u)"
DAY_OF_MONTH="$(date +%d)"

mkdir -p "$BACKUP_TMP_DIR"

BACKUP_FILE="$BACKUP_TMP_DIR/minecraft-worlds-${DATE}.tar.zst"

WORLDS_TO_BACKUP=()

for world in "${WORLD_NAMES[@]}"; do
  if [ -d "$SERVER_DIR/$world" ]; then
    WORLDS_TO_BACKUP+=("$world")
  else
    echo "[backup] skip missing world: $world"
  fi
done

mc_cmd() {
    tmux send-keys -t "$TMUX_SESSION" "$1" C-m
}

notify_discord() {
  local status="$1"
  local message="$2"

  if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
    return 0
  fi

  curl -sS -H "Content-Type: application/json" \
    -X POST \
    -d "{\"content\":\"${message}\"}" \
    "$DISCORD_WEBHOOK_URL" >/dev/null
}

echo "[backup] start: $DATE"

sleep 10
mc_cmd "save-off"

sleep 3

echo "[backup] archive worlds"

tar --use-compress-program="zstd -T0 -10" \
  -cf "$BACKUP_FILE" \
  -C "$SERVER_DIR" \
  "${WORLDS_TO_BACKUP[@]}"

sleep 1

mc_cmd "save-on"

echo "[backup] upload daily"
gcloud storage cp "$BACKUP_FILE" "$DAILY_BUCKET/"

if [ "$FORCE_ALL" = true ] || [ "$DAY_OF_WEEK" = "1" ]; then
  echo "[backup] upload weekly"
  gcloud storage cp "$BACKUP_FILE" "$WEEKLY_BUCKET/"
fi

if [ "$FORCE_ALL" = true ] || [ "$DAY_OF_MONTH" = "01" ]; then
  echo "[backup] upload monthly"
  gcloud storage cp "$BACKUP_FILE" "$MONTHLY_BUCKET/"
fi

rm -f "$BACKUP_FILE"

echo "[backup] done"

notify_discord "success" "✅ Minecraft backup completed: ${DATE}"


