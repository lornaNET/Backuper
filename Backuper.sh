#!/usr/bin/env bash
# Unified Backuper Launcher + Uptime Kuma Add-on (single file)
# - Shows a top-level menu:
#     1) Run ORIGINAL Backuper menu (from erfjab/Backuper)
#     2) Uptime Kuma Backup (built-in here)
#     3) Uptime Kuma Restore (built-in here)
# - No need to modify upstream files; we just fetch & run them.
# - MIT License

set -euo pipefail

###############################################
# ========== User-configurable section ==========
###############################################

# Upstream Backuper (original menu) - leave as is unless you fork it
UPSTREAM_BACKUPER_URL="${UPSTREAM_BACKUPER_URL:-https://github.com/erfjab/Backuper/raw/master/backuper.sh}"
UPSTREAM_CACHE_PATH="${UPSTREAM_CACHE_PATH:-/tmp/backuper_upstream.sh}"
UPSTREAM_CACHE_TTL_HOURS="${UPSTREAM_CACHE_TTL_HOURS:-12}"

# Uptime Kuma backup settings (defaults)
BACKUP_DIR="${BACKUP_DIR:-/var/backups/uptime-kuma}"
RETENTION="${RETENTION:-7}"

# Docker names (change if your compose/docker run names differ)
KUMA_CONTAINER_NAME="${KUMA_CONTAINER_NAME:-uptime-kuma}"
KUMA_VOLUME_NAME="${KUMA_VOLUME_NAME:-uptime-kuma}"

# For SQLite consistency, stop the container briefly during backup/restore
STOP_DURING_BACKUP="${STOP_DURING_BACKUP:-true}"

# Telegram notifications (optional). If both TOKEN and CHAT_ID are set,
# backup archives will be sent with a caption mentioning TELEGRAM_MENTION.
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_MENTION="${TELEGRAM_MENTION:-@lorna_support}"

###############################################
# =============== Utilities ====================
###############################################
timestamp() { date +"%Y%m%d-%H%M%S"; }
now_human() { date +'%F %T'; }
log() { echo "[$(date +'%F %T')] $*"; }
ensure_dir() { mkdir -p "$BACKUP_DIR"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found."; exit 127; }; }

docker_container_exists() { docker ps -a --format '{{.Names}}' | grep -qx "${KUMA_CONTAINER_NAME}"; }
docker_container_running() { docker ps --format '{{.Names}}' | grep -qx "${KUMA_CONTAINER_NAME}"; }
docker_volume_exists() { docker volume ls --format '{{.Name}}' | grep -qx "${KUMA_VOLUME_NAME}"; }

stop_container_if_requested() {
  STOPPED=0
  if [ "${STOP_DURING_BACKUP}" = "true" ] && docker_container_running; then
    log "Stopping container ${KUMA_CONTAINER_NAME} ..."
    docker stop "${KUMA_CONTAINER_NAME}" >/dev/null
    STOPPED=1
  fi
}
start_container_if_stopped() {
  if [ "${STOPPED:-0}" -eq 1 ]; then
    log "Starting container ${KUMA_CONTAINER_NAME} ..."
    docker start "${KUMA_CONTAINER_NAME}" >/dev/null
  fi
}

send_telegram_document() {
  # $1=file path, $2=caption
  local FILE="$1" CAPTION="$2"
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    require_cmd curl
    log "Sending archive to Telegram chat_id=${TELEGRAM_CHAT_ID} ..."
    curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
      -F "chat_id=${TELEGRAM_CHAT_ID}" \
      -F "document=@${FILE}" \
      -F "caption=${CAPTION}" >/dev/null || log "WARN: Telegram send failed."
  else
    log "Telegram not configured; skipping send."
  fi
}

apply_retention() {
  local keep="$1" pattern="$BACKUP_DIR/uptime-kuma-*.tar.gz"
  local count; count=$(ls -1t $pattern 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt "$keep" ]; then
    local to_delete=$((count - keep))
    log "Applying retention (keep $keep): deleting $to_delete older archive(s)."
    ls -1t $pattern 2>/dev/null | tail -n "$to_delete" | xargs -r rm -f
  else
    log "Retention: nothing to delete (count=$count, keep=$keep)."
  fi
}

pause() { read -rp "ادامه با Enter..." _ || true; }

###############################################
# ============ Uptime Kuma Add-on =============
###############################################
kuma_backup() {
  require_cmd docker
  ensure_dir
  local OUT="$BACKUP_DIR/uptime-kuma-$(timestamp).tar.gz"

  stop_container_if_requested
  trap start_container_if_stopped EXIT

  if docker_volume_exists; then
    log "Backing up from named volume '${KUMA_VOLUME_NAME}' -> ${OUT}"
    docker run --rm -v "${KUMA_VOLUME_NAME}:/data:ro" -v "${BACKUP_DIR}:/backup" \
      alpine sh -c "cd /data && tar -czf /backup/$(basename "$OUT") ."
  elif docker_container_exists; then
    log "Named volume not found; backing up via --volumes-from ${KUMA_CONTAINER_NAME} -> ${OUT}"
    docker run --rm --volumes-from "${KUMA_CONTAINER_NAME}" -v "${BACKUP_DIR}:/backup" \
      alpine sh -c "cd /app/data && tar -czf /backup/$(basename "$OUT") ."
  else
    log "ERROR: Neither volume '${KUMA_VOLUME_NAME}' nor container '${KUMA_CONTAINER_NAME}' exists."
    exit 1
  fi

  trap - EXIT
  start_container_if_stopped

  log "Backup saved: ${OUT}"
  apply_retention "${RETENTION}"
  send_telegram_document "${OUT}" "✅ Uptime Kuma backup created at $(now_human). ${TELEGRAM_MENTION}"
  log "Done."
}

kuma_restore() {
  require_cmd docker
  local ARCHIVE="${1:-}"
  if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
    echo "Usage: $0 kuma-restore /path/to/uptime-kuma-YYYYMMDD-HHMMSS.tar.gz"
    exit 2
  fi

  if docker_container_exists && docker_container_running; then
    log "Stopping container ${KUMA_CONTAINER_NAME} for restore ..."
    docker stop "${KUMA_CONTAINER_NAME}" >/dev/null || true
    STOPPED=1
  else
    STOPPED=0
  fi
  trap start_container_if_stopped EXIT

  if docker_volume_exists; then
    log "Restoring into named volume '${KUMA_VOLUME_NAME}' from ${ARCHIVE}"
    docker run --rm -v "${KUMA_VOLUME_NAME}:/data" -v "$(dirname "$ARCHIVE"):/backup:ro" \
      alpine sh -c "rm -rf /data/* && tar -xzf /backup/$(basename "$ARCHIVE") -C /data"
  elif docker_container_exists; then
    log "Volume not found; restoring via --volumes-from ${KUMA_CONTAINER_NAME} from ${ARCHIVE}"
    docker run --rm --volumes-from "${KUMA_CONTAINER_NAME}" -v "$(dirname "$ARCHIVE"):/backup:ro" \
      alpine sh -c "rm -rf /app/data/* && tar -xzf /backup/$(basename "$ARCHIVE") -C /app/data"
  else
    log "ERROR: No target volume/container found."
    exit 1
  fi

  trap - EXIT
  start_container_if_stopped

  log "Restore finished."
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=♻️ Uptime Kuma restore completed: $(basename "$ARCHIVE") — ${TELEGRAM_MENTION}" \
      >/dev/null || true
  fi
}

###############################################
# ======= Upstream Backuper integration ========
###############################################
file_age_hours() {
  local f="$1"
  [ -f "$f" ] || { echo 999999; return; }
  local mtime epoch_now diff_sec
  mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
  epoch_now=$(date +%s)
  diff_sec=$((epoch_now - mtime))
  echo $((diff_sec / 3600))
}

fetch_upstream_if_needed() {
  local ttl="${UPSTREAM_CACHE_TTL_HOURS}"
  local age
  age=$(file_age_hours "$UPSTREAM_CACHE_PATH" || echo 999999)
  if [ "$age" -ge "$ttl" ]; then
    require_cmd curl
    log "Fetching upstream Backuper from: $UPSTREAM_BACKUPER_URL"
    curl -fsSL "$UPSTREAM_BACKUPER_URL" -o "$UPSTREAM_CACHE_PATH"
    chmod +x "$UPSTREAM_CACHE_PATH"
  fi
}

run_upstream_menu() {
  fetch_upstream_if_needed
  if [ ! -x "$UPSTREAM_CACHE_PATH" ]; then
    echo "ERROR: Could not retrieve upstream backuper from $UPSTREAM_BACKUPER_URL"
    return 1
  fi
  # hand over to original menu (it has its own prompts for Marzban/Marzneshin/etc.)
  bash "$UPSTREAM_CACHE_PATH"
}

###############################################
# ================== UI =======================
###############################################
print_header() {
  clear
  cat <<'HDR'
=========================================
         Backuper (Unified Launcher)
=========================================
1) اجرای منوی اصلی Backuper (از گیت‌هاب erfjab)
2) بکاپ Uptime Kuma
3) ری‌استور Uptime Kuma
0) خروج
HDR
}

main_menu() {
  while true; do
    print_header
    echo -n "انتخاب: "
    read -r opt
    case "${opt:-}" in
      1) run_upstream_menu; pause ;;
      2) kuma_backup; pause ;;
      3) 
         echo -n "مسیر فایل آرشیو بکاپ را وارد کنید: "
         read -r arch
         [ -z "$arch" ] && { echo "لغو شد."; pause; continue; }
         kuma_restore "$arch"; pause
         ;;
      0) echo "خروج."; exit 0 ;;
      *) echo "انتخاب نامعتبر."; pause ;;
    escase
  done
}

###############################################
# ============== Direct CLI mode ==============
###############################################
usage() {
cat <<EOF
Usage:
  # Interactive menu (recommended)
  $0

  # Direct commands (non-interactive):
  $0 upstream         # fetch & run original Backuper menu
  $0 kuma-backup      # run Uptime Kuma backup
  $0 kuma-restore /path/to/uptime-kuma-YYYYMMDD-HHMMSS.tar.gz

Env (override defaults as needed):
  BACKUP_DIR=/var/backups/uptime-kuma  RETENTION=7
  KUMA_CONTAINER_NAME=uptime-kuma      KUMA_VOLUME_NAME=uptime-kuma
  STOP_DURING_BACKUP=true
  TELEGRAM_BOT_TOKEN=   TELEGRAM_CHAT_ID=   TELEGRAM_MENTION=${TELEGRAM_MENTION}
EOF
}

main() {
  case "${1:-menu}" in
    menu) main_menu ;;
    upstream) run_upstream_menu ;;
    kuma-backup) kuma_backup ;;
    kuma-restore) kuma_restore "${2:-}" ;;
    -h|--help|help) usage ;;
    *) main_menu ;;
  esac
}

main "$@"
