#!/usr/bin/env bash
# Backuper (Unified Launcher) + Uptime Kuma Add-on + Installer
# MIT

set -euo pipefail

###############################################
# ========== User-configurable section ==========
###############################################

VERSION="${VERSION:-v1.2.1}"

# Upstream Backuper (original menu by erfjab)
UPSTREAM_BACKUPER_URL="${UPSTREAM_BACKUPER_URL:-https://github.com/erfjab/Backuper/raw/master/backuper.sh}"
UPSTREAM_CACHE_PATH="${UPSTREAM_CACHE_PATH:-/tmp/backuper_upstream.sh}"
UPSTREAM_CACHE_TTL_HOURS="${UPSTREAM_CACHE_TTL_HOURS:-12}"

# Install/uninstall
INSTALL_BIN_NAME="${INSTALL_BIN_NAME:-lornaNET}"
INSTALL_BIN_PATH="/usr/local/bin/${INSTALL_BIN_NAME}"

# Uptime Kuma backup settings
BACKUP_DIR="${BACKUP_DIR:-/var/backups/uptime-kuma}"
RETENTION="${RETENTION:-7}"

# Auto-detect by default (می‌توانی دستی override کنی)
KUMA_CONTAINER_NAME="${KUMA_CONTAINER_NAME:-}"
KUMA_VOLUME_NAME="${KUMA_VOLUME_NAME:-}"

# Image names to try (بدون تگ و با تگ v2)
KUMA_IMAGE_CANDIDATES="${KUMA_IMAGE_CANDIDATES:-louislam/uptime-kuma:2 louislam/uptime-kuma}"

# For SQLite consistency
STOP_DURING_BACKUP="${STOP_DURING_BACKUP:-true}"

# Telegram (اختیاری)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_MENTION="${TELEGRAM_MENTION:-@lorna_support}"

###############################################
# ================= Utilities ==================
###############################################
timestamp() { date +"%Y%m%d-%H%M%S"; }
now_human() { date +'%F %T'; }
log() { echo "[$(date +'%F %T')] $*"; }
ensure_dir() { mkdir -p "$BACKUP_DIR"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found."; exit 127; }; }

# ANSI for menu
RESET='\033[0m'; FG_CYAN='\033[36m'; FG_GREEN='\033[32m'; FG_YELLOW='\033[33m'; FG_WHITE='\033[37m'

###############################################
# ======== Auto-detect Kuma container/volume ===
###############################################
detect_kuma() {
  require_cmd docker

  # 1) کانتینر
  if [ -z "${KUMA_CONTAINER_NAME:-}" ]; then
    # تلاش با ancestor (اول ایمیج‌های کاندید، بعد بدون فیلتر و بر اساس اسم)
    for img in ${KUMA_IMAGE_CANDIDATES}; do
      KUMA_CONTAINER_NAME="$(docker ps --filter "ancestor=${img}" --format '{{.Names}}' | head -n1 || true)"
      [ -n "${KUMA_CONTAINER_NAME}" ] && break
    done
    if [ -z "${KUMA_CONTAINER_NAME:-}" ]; then
      for img in ${KUMA_IMAGE_CANDIDATES}; do
        KUMA_CONTAINER_NAME="$(docker ps -a --filter "ancestor=${img}" --format '{{.Names}}' | head -n1 || true)"
        [ -n "${KUMA_CONTAINER_NAME}" ] && break
      done
    fi
    # اگر هنوز پیدا نشد، بر اساس اسم‌هایی که شامل uptime-kuma هستند
    if [ -z "${KUMA_CONTAINER_NAME:-}" ]; then
      KUMA_CONTAINER_NAME="$(docker ps -a --format '{{.Names}}' | grep -E -m1 '(^|[-_])uptime-kuma([-_]|$)' || true)"
    fi
  fi

  if [ -z "${KUMA_CONTAINER_NAME:-}" ]; then
    echo "ERROR: No Uptime Kuma container found (image candidates: ${KUMA_IMAGE_CANDIDATES})."
    echo "Hint: run 'docker ps -a' and ensure Uptime Kuma is installed."
    exit 1
  fi

  # 2) ولیومِ /app/data (اگه bind باشه Name خالی می‌مونه که اشکال نداره)
  if [ -z "${KUMA_VOLUME_NAME:-}" ]; then
    KUMA_VOLUME_NAME="$(docker inspect "$KUMA_CONTAINER_NAME" \
      -f '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Name}}{{end}}{{end}}' 2>/dev/null || true)"
  fi
}

###############################################
# ======= Docker helpers (post-detect) =========
###############################################
docker_container_exists() { docker ps -a --format '{{.Names}}' | grep -qx "${KUMA_CONTAINER_NAME}"; }
docker_container_running() { docker ps --format '{{.Names}}' | grep -qx "${KUMA_CONTAINER_NAME}"; }
docker_volume_exists() { [ -n "${KUMA_VOLUME_NAME:-}" ] && docker volume ls --format '{{.Name}}' | grep -qx "${KUMA_VOLUME_NAME}"; }

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
# ===== helper: smart archive resolver ========
###############################################
# ورودی: رشتهٔ کاربر (می‌تونه خالی، اسم فایل، بخشی از اسم یا مسیر کامل باشه)
# خروجی: مسیر آرشیو انتخاب‌شده یا رشتهٔ خالی
select_archive() {
  local in="${1:-}"
  local out=""

  # اگر خالی بود، آخرین بکاپ را انتخاب کن
  if [ -z "$in" ]; then
    out="$(ls -1t "$BACKUP_DIR"/uptime-kuma-*.tar.gz 2>/dev/null | head -n1 || true)"
    echo "$out"; return 0
  fi

  # اگر مسیر کاملِ موجود است
  if [ -f "$in" ]; then
    echo "$in"; return 0
  fi

  # اگر فقط نام فایل در BACKUP_DIR موجود است
  if [ -f "$BACKUP_DIR/$in" ]; then
    echo "$BACKUP_DIR/$in"; return 0
  fi

  # اگر بخشی از نام داده شده: در BACKUP_DIR بگرد و جدیدترینِ منطبق را بردار
  out="$(ls -1t "$BACKUP_DIR"/uptime-kuma-*.tar.gz 2>/dev/null | grep -F "$in" | head -n1 || true)"
  if [ -n "$out" ]; then
    echo "$out"; return 0
  fi

  # تلاش نهایی: هر tar.gz در BACKUP_DIR که شامل in باشد
  out="$(ls -1t "$BACKUP_DIR"/*"$in"*.tar.gz 2>/dev/null | head -n1 || true)"
  echo "$out"
}

###############################################
# ============ Uptime Kuma Add-on =============
###############################################
kuma_backup() {
  detect_kuma
  ensure_dir

  local OUT="$BACKUP_DIR/uptime-kuma-$(timestamp).tar.gz"

  stop_container_if_requested
  trap start_container_if_stopped EXIT

  if docker_volume_exists; then
    log "Detected volume '${KUMA_VOLUME_NAME}'. Backing up -> ${OUT}"
    docker run --rm -v "${KUMA_VOLUME_NAME}:/data:ro" -v "${BACKUP_DIR}:/backup" \
      alpine sh -c "cd /data && tar -czf /backup/$(basename "$OUT") ."
  elif docker_container_exists; then
    log "No named volume detected; using --volumes-from '${KUMA_CONTAINER_NAME}' (/app/data) -> ${OUT}"
    docker run --rm --volumes-from "${KUMA_CONTAINER_NAME}" -v "${BACKUP_DIR}:/backup" \
      alpine sh -c "cd /app/data && tar -czf /backup/$(basename "$OUT") ."
  else
    log "ERROR: After detection, neither volume nor container is usable."
    exit 1
  fi

  trap - EXIT
  start_container_if_stopped

  log "Backup saved: ${OUT}"
  apply_retention "${RETENTION}"
  send_telegram_document "${OUT}" "✅ Uptime Kuma backup @ $(now_human) — ${TELEGRAM_MENTION}"
  log "Done."
}

kuma_restore() {
  # 1) انتخاب فایل بکاپ (هوشمند)
  local ARCHIVE_IN="${1:-}"
  local ARCHIVE
  ARCHIVE="$(select_archive "$ARCHIVE_IN")"

  if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
    echo "Cannot find backup archive (input: '${ARCHIVE_IN}')."
    echo "Tip: ls -1t $BACKUP_DIR/*.tar.gz | head -n5"
    exit 2
  fi
  log "Using backup archive: $ARCHIVE"

  # 2) تشخیص مقصد
  detect_kuma
  require_cmd docker

  # 3) Stop/restore/start
  if docker_container_exists && docker_container_running; then
    log "Stopping container ${KUMA_CONTAINER_NAME} for restore ..."
    docker stop "${KUMA_CONTAINER_NAME}" >/dev/null || true
    STOPPED=1
  else
    STOPPED=0
  fi
  trap start_container_if_stopped EXIT

  if docker_volume_exists; then
    log "Restoring into volume '${KUMA_VOLUME_NAME}' from ${ARCHIVE}"
    docker run --rm -v "${KUMA_VOLUME_NAME}:/data" -v "$(dirname "$ARCHIVE"):/backup:ro" \
      alpine sh -c "rm -rf /data/* && tar -xzf /backup/$(basename "$ARCHIVE") -C /data"
  elif docker_container_exists; then
    log "No named volume; restoring via --volumes-from ${KUMA_CONTAINER_NAME} to /app/data"
    docker run --rm --volumes-from "${KUMA_CONTAINER_NAME}" -v "$(dirname "$ARCHIVE"):/backup:ro" \
      alpine sh -c "rm -rf /app/data/* && tar -xzf /backup/$(basename "$ARCHIVE") -C /app/data"
  else
    log "ERROR: Target not found for restore."
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
  bash "$UPSTREAM_CACHE_PATH"
}

###############################################
# ================== UI (Erfan-style) =========
###############################################
print_header() {
  clear
  echo -e "\033[36m=======  Backuper Menu [${VERSION}]  =======\033[0m"
  echo
  echo -e "  \033[32m1)\033[0m \033[37mRun ORIGINAL Backuper (erfjab)\033[0m"
  echo -e "  \033[32m2)\033[0m \033[37mUptime Kuma Backup\033[0m"
  echo -e "  \033[32m3)\033[0m \033[37mUptime Kuma Restore\033[0m"
  echo -e "  \033[32m0)\033[0m \033[37mExit\033[0m"
  echo
  echo -en "\033[33m► Choose an option: \033[0m"
}

main_menu() {
  while true; do
    print_header
    read -r opt
    case "${opt:-}" in
      1) run_upstream_menu; pause ;;
      2) kuma_backup; pause ;;
      3)
         echo -n "Enter backup archive path (empty = latest / name or partial is OK): "
         read -r arch
         kuma_restore "${arch:-}"; pause
         ;;
      0) echo "Bye."; exit 0 ;;
      *) echo "Invalid option."; pause ;;
    esac
  done
}

###############################################
# ============== Install / Uninstall ==========
###############################################
install_self() {
  require_cmd install
  local src
  src="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
  sudo install -m 0755 "$src" "$INSTALL_BIN_PATH"
  echo "✅ Installed: $INSTALL_BIN_PATH"
  echo "Run: sudo $INSTALL_BIN_NAME"
}

uninstall_self() {
  if [ -e "$INSTALL_BIN_PATH" ]; then
    sudo rm -f "$INSTALL_BIN_PATH"
    echo "🗑️  Removed: $INSTALL_BIN_PATH"
  else
    echo "Nothing to remove at $INSTALL_BIN_PATH"
  fi
}

###############################################
# ============== Direct CLI mode ==============
###############################################
usage() {
cat <<EOF
Usage:
  $0                 # interactive menu
  $0 upstream
  $0 kuma-backup
  # ری‌استور هوشمند:
  #   بدون آرگومان = آخرین بکاپ
  #   اسم فایل یا بخشی از اسم = از BACKUP_DIR پیدا می‌کند
  #   مسیر کامل = همان
  $0 kuma-restore [archive-or-partial-or-full-path]
  $0 install         # copy to /usr/local/bin/${INSTALL_BIN_NAME}
  $0 uninstall       # remove installed launcher

Env:
  BACKUP_DIR  RETENTION  KUMA_CONTAINER_NAME  KUMA_VOLUME_NAME
  STOP_DURING_BACKUP  TELEGRAM_BOT_TOKEN  TELEGRAM_CHAT_ID  TELEGRAM_MENTION
  INSTALL_BIN_NAME  VERSION  KUMA_IMAGE_CANDIDATES
EOF
}

main() {
  case "${1:-menu}" in
    menu) main_menu ;;
    upstream) run_upstream_menu ;;
    kuma-backup) kuma_backup ;;
    kuma-restore) kuma_restore "${2:-}" ;;
    install) install_self ;;
    uninstall) uninstall_self ;;
    -h|--help|help) usage ;;
    *) main_menu ;;
  esac
}

main "$@"
