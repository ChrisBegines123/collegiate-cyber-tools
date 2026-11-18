#!/usr/bin/env bash
set -euo pipefail

SITE_ROOT="/var/www/html/opencart"          # Path to your OpenCart install
BACKUP_ROOT="/var/backups/opencart_guard"
BASELINE_HASHES="${BACKUP_ROOT}/baseline.sha256"
LOG_FILE="/var/log/opencart_guard.log"
CHECK_INTERVAL=10                      # seconds

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" | tee -a "$LOG_FILE"
}

create_backup() {
  mkdir -p "$BACKUP_ROOT"
  log "Creating full backup in ${BACKUP_ROOT}"
  rsync -a --delete \
    --exclude 'system/storage/cache/' \
    --exclude 'system/storage/logs/' \
    --exclude 'system/storage/session/' \
    --exclude 'image/cache/' \
    "$SITE_ROOT"/ "$BACKUP_ROOT/site/"
}

generate_baseline_hashes() {
  log "Generating baseline checksums"
  (cd "$SITE_ROOT" && \
    find . -type f \
      ! -path "./system/storage/cache/*" \
      ! -path "./system/storage/logs/*" \
      ! -path "./system/storage/session/*" \
      ! -path "./image/cache/*" \
      -print0 | sort -z | xargs -0 sha256sum) > "$BASELINE_HASHES"
}

restore_file() {
  local rel_path="$1"
  local src="${BACKUP_ROOT}/site/${rel_path}"
  local dst="${SITE_ROOT}/${rel_path}"
  if [[ -f "$src" ]]; then
    install -D -m "$(stat -c '%a' "$src")" "$src" "$dst"
    log "Restored ${rel_path} from backup"
  else
    log "Backup missing for ${rel_path}; skipped restore"
  fi
}

verify_loop() {
  log "Starting integrity monitor (interval: ${CHECK_INTERVAL}s)"
  while true; do
    while read -r baseline_hash rel_path; do
      local_path="${SITE_ROOT}/${rel_path}"
      if [[ ! -f "$local_path" ]]; then
        restore_file "$rel_path"
        continue
      fi
      current_hash=$(sha256sum "$local_path" | awk '{print $1}')
      if [[ "$current_hash" != "$baseline_hash" ]]; then
        restore_file "$rel_path"
      fi
    done < "$BASELINE_HASHES"
    sleep "$CHECK_INTERVAL"
  done
}

main() {
  [[ -d "$SITE_ROOT" ]] || { echo "SITE_ROOT not found: $SITE_ROOT" >&2; exit 1; }
  mkdir -p "$(dirname "$LOG_FILE")"
  create_backup
  generate_baseline_hashes
  verify_loop
}

# Uncomment to run
main
