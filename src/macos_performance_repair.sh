#!/bin/bash
set -u

RESTART_UI=false
APP_PATH=""
PID=""
FORCE=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: macos_performance_repair.sh [options]

  --restart-ui          Restart Dock, SystemUIServer and user preference services.
  --restart-app PATH    Gracefully quit and reopen one application bundle.
  --terminate-pid PID   Send TERM to one process owned by the logged-in user.
  --force               Use KILL if the selected process does not exit after TERM.
  --dry-run             Show actions without changing the Mac.
  --yes                 Skip confirmation prompts.
  --output DIR          Save logs and verification output in DIR.
  -h, --help            Show help.

At least one repair action is required. The script refuses to terminate system-owned processes.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart-ui) RESTART_UI=true; shift ;;
    --restart-app) APP_PATH="${2:-}"; shift 2 ;;
    --terminate-pid) PID="${2:-}"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 3; }
if ! $RESTART_UI && [ -z "$APP_PATH" ] && [ -z "$PID" ]; then echo "Choose at least one repair action." >&2; exit 2; fi

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ "$TARGET_USER" = "root" ]; then TARGET_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || echo root); fi
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null) || { echo "Target user not found." >&2; exit 3; }

if [ -n "$APP_PATH" ]; then
  APP_PATH=$(cd "$(dirname "$APP_PATH")" 2>/dev/null && pwd)/$(basename "$APP_PATH")
  case "$APP_PATH" in /Applications/*.app|/System/Applications/*.app|/Users/*/Applications/*.app) : ;; *) echo "Application path must reference a standard Applications folder." >&2; exit 2 ;; esac
  [ -d "$APP_PATH" ] || { echo "Application not found: $APP_PATH" >&2; exit 2; }
fi
if [ -n "$PID" ]; then
  case "$PID" in ''|*[!0-9]*) echo "PID must be numeric." >&2; exit 2 ;; esac
  [ "$PID" -gt 99 ] || { echo "Refusing low system PID." >&2; exit 2; }
  PROCESS_UID=$(ps -o uid= -p "$PID" 2>/dev/null | tr -d ' ')
  [ -n "$PROCESS_UID" ] || { echo "Process not found: $PID" >&2; exit 2; }
  [ "$PROCESS_UID" = "$TARGET_UID" ] || { echo "Process is not owned by $TARGET_USER." >&2; exit 2; }
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./performance-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_as_target() {
  description="$1"; shift
  if [ "$(id -u)" = "$TARGET_UID" ]; then run_action "$description" "$@"; else run_action "$description" /usr/bin/sudo -H -u "$TARGET_USER" "$@"; fi
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Target user: $TARGET_USER ($TARGET_UID)"
    echo
    echo "Load and memory:"
    /usr/bin/uptime
    /usr/bin/vm_stat
    /usr/bin/memory_pressure 2>/dev/null | head -n 80 || true
    echo
    echo "Top processes:"
    ps -Ao pid,user,%cpu,%mem,etime,comm | sort -k3 -nr | head -n 30
    if [ -n "$PID" ]; then
      echo
      echo "Selected PID state:"
      ps -p "$PID" -o pid,user,%cpu,%mem,etime,state,comm,args 2>&1 || true
    fi
  } > "$VERIFY" 2>&1
}

verify
if ! confirm "Apply the selected performance repair actions? Unsaved app work may be lost."; then log "Repair cancelled."; exit 10; fi

if $RESTART_UI; then
  for process_name in Dock SystemUIServer cfprefsd sharedfilelistd; do
    if pgrep -u "$TARGET_UID" -x "$process_name" >/dev/null 2>&1; then
      run_action "Restarting $process_name for $TARGET_USER" /usr/bin/killall -u "$TARGET_USER" "$process_name" || true
    fi
  done
fi

if [ -n "$APP_PATH" ]; then
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)
  APP_NAME=$(basename "$APP_PATH" .app)
  if [ -n "$BUNDLE_ID" ]; then
    run_as_target "Quitting $APP_NAME" /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
  else
    run_as_target "Quitting $APP_NAME" /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" || true
  fi
  if ! $DRY_RUN; then sleep 4; fi
  run_as_target "Reopening $APP_NAME" /usr/bin/open "$APP_PATH" || true
fi

if [ -n "$PID" ]; then
  run_action "Sending TERM to process $PID" /bin/kill -TERM "$PID" || true
  if ! $DRY_RUN; then
    waited=0
    while kill -0 "$PID" 2>/dev/null && [ "$waited" -lt 10 ]; do sleep 1; waited=$((waited + 1)); done
    if kill -0 "$PID" 2>/dev/null && $FORCE && confirm "Process $PID did not exit. Force it to stop?"; then
      run_action "Sending KILL to process $PID" /bin/kill -KILL "$PID" || true
    fi
  fi
fi

if ! $DRY_RUN; then sleep 4; fi
verify
if [ "$FAILURES" -gt 0 ]; then log "Repair completed with $FAILURES warning(s)."; exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
