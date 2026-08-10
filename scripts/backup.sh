#!/usr/bin/env bash
set -euo pipefail

source /opt/minecraft-backup/env

AUTO_SAVE_DISABLED=false

mc_cmd() {
  tmux send-keys -t "$TMUX_SESSION" "$1" C-m
}

sync_worlds() {
  local world

  if [ "${#WORLDS_TO_BACKUP[@]}" -eq 0 ]; then
    echo "[backup] error: no worlds to backup" >&2
    return 1
  fi

  for world in "${WORLDS_TO_BACKUP[@]}"; do
    mkdir -p "$SNAPSHOT_DIR/$world"
    rsync -a --delete "$SERVER_DIR/$world/" "$SNAPSHOT_DIR/$world/"
  done
}

stop_auto_save() {
  mc_cmd "save-off"
  AUTO_SAVE_DISABLED=true
}

manually_save_all() {
  local timeout="${SAVE_ALL_TIMEOUT:-120}"
  local before_lines i line
  local -a pane_lines

  # 送信前のバッファ行数を記録し、それ以降に追加された行だけを検査する。
  # これにより前回実行や過去の "Saved the game" を拾う誤検知を防ぐ。
  before_lines="$(tmux capture-pane -p -S - -t "$TMUX_SESSION" | wc -l)"

  mc_cmd "save-all flush"

  for ((i = 0; i < timeout; i++)); do
    sleep 1
    mapfile -t pane_lines < <(tmux capture-pane -p -S - -t "$TMUX_SESSION")

    for line in "${pane_lines[@]:before_lines}"; do
      if [[ "$line" == *"Saved the game"* ]]; then
        return 0
      fi
    done
  done

  echo "[backup] error: save-all flush did not complete within ${timeout}s" >&2
  return 1
}

start_auto_save() {
  mc_cmd "save-on"
  AUTO_SAVE_DISABLED=false
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

# EXIT で必ず走る後始末。自動セーブを戻し、一時ファイルを掃除し、
# 異常終了時は失敗通知を送る。
cleanup() {
  local rc=$?

  if [ "$AUTO_SAVE_DISABLED" = true ]; then
    start_auto_save || true
  fi
  if [ "$rc" -eq 0 ] && [ -n "${BACKUP_FILE:-}" ]; then
    rm -f "$BACKUP_FILE" 2>/dev/null || true
  fi
  if [ "$rc" -ne 0 ]; then
    notify_discord "failure" "❌ Minecraft backup failed: ${DATE:-unknown}"
  fi
}

FORCE_ALL=false

if [ "${1:-}" = "--all" ]; then
  FORCE_ALL=true
fi

DATE="$(date +%F-%H%M%S)"
DAY_OF_WEEK="$(date +%u)"
DAY_OF_MONTH="$(date +%d)"

mkdir -p "$BACKUP_TMP_DIR"

BACKUP_FILE="$(mktemp "$BACKUP_TMP_DIR/minecraft-worlds.XXXXXX")"
SNAPSHOT_DIR="$BACKUP_TMP_DIR/snapshot"
mkdir -p "$SNAPSHOT_DIR"

WORLDS_TO_BACKUP=()

for world in "${WORLD_NAMES[@]}"; do
  if [ -d "$SERVER_DIR/$world" ]; then
    WORLDS_TO_BACKUP+=("$world")
  else
    echo "[backup] skip missing world: $world"
  fi
done

echo "[backup] start: $DATE"

trap cleanup EXIT

sleep 10

# 1パス目: サーバー稼働中に大部分を同期する（save-off 前・多少の不整合は許容）。
# 重いフルコピーを save-off の外に追い出すのが狙い。
echo "[backup] pre-sync (online)"
sync_worlds

echo "[backup] save-off"
stop_auto_save

sleep 3

echo "[backup] save-all flush"
manually_save_all

# 2パス目: save-off 中に差分だけ同期し、整合したスナップショットを得る。
# 変更分のみなので短時間で終わり、save-off 時間を最小化できる。
echo "[backup] sync (offline)"
sync_worlds

echo "[backup] save-on"
start_auto_save

echo "[backup] archive worlds"
tar --use-compress-program="zstd -T0 -10" \
  -cf "$BACKUP_FILE" \
  -C "$SNAPSHOT_DIR" \
  "${WORLDS_TO_BACKUP[@]}"

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
