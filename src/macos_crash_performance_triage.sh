#!/bin/bash
set -u

HOURS=24
TOP_N=25
OUTPUT_DIR=""
usage() { echo "Usage: macos_crash_performance_triage.sh [--hours N] [--top N] [--output DIR]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --top) TOP_N="${2:-25}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
case "$HOURS:$TOP_N" in *[!0-9:]*) echo "--hours and --top must be numeric" >&2; exit 2 ;; esac
[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./macos-performance-triage-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/performance-triage.txt"
CSV="$OUTPUT_DIR/diagnostic-reports.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"
echo 'path,type,size_bytes,modified_epoch' > "$CSV"

section() { title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; uname -a; uptime'
section "Memory pressure" /usr/bin/memory_pressure
section "Virtual memory" /usr/bin/vm_stat
section "Swap usage" /usr/sbin/sysctl vm.swapusage
section "Top CPU processes" /bin/bash -c "ps -Ao pid,user,%cpu,%mem,rss,vsz,etime,state,comm -r | head -n $((TOP_N + 1))"
section "Top memory processes" /bin/bash -c "ps -Ao pid,user,%cpu,%mem,rss,vsz,etime,state,comm -m | head -n $((TOP_N + 1))"
section "Thermal and power state" /bin/bash -c 'pmset -g therm; pmset -g batt; sysctl -n machdep.xcpm.cpu_thermal_level 2>/dev/null || true'
section "Recent performance events" /bin/bash -c "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(eventMessage CONTAINS[c] \"crash\") OR (eventMessage CONTAINS[c] \"hang\") OR (eventMessage CONTAINS[c] \"watchdog\") OR (eventMessage CONTAINS[c] \"memory pressure\") OR (eventMessage CONTAINS[c] \"jetsam\") OR (eventMessage CONTAINS[c] \"thermal\")' 2>/dev/null | tail -n 4000"

TOTAL_REPORTS=0
RECENT_REPORTS=0
NOW=$(date +%s)
CUTOFF=$((NOW - HOURS * 3600))
for dir in /Library/Logs/DiagnosticReports /Users/*/Library/Logs/DiagnosticReports; do
  [ -d "$dir" ] || continue
  for file in "$dir"/*; do
    [ -f "$file" ] || continue
    TOTAL_REPORTS=$((TOTAL_REPORTS + 1))
    modified=$(stat -f '%m' "$file" 2>/dev/null || echo 0)
    [ "$modified" -ge "$CUTOFF" ] && RECENT_REPORTS=$((RECENT_REPORTS + 1))
    size=$(stat -f '%z' "$file" 2>/dev/null || echo 0)
    type=$(basename "$file" | awk -F. '{print $NF}')
    safe=$(printf '%s' "$file" | sed 's/"/""/g')
    printf '"%s","%s",%s,%s\n' "$safe" "$type" "$size" "$modified" >> "$CSV"
  done
done

LOAD1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || echo 0)
MEM_FREE_PAGES=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub("\\.","",$3); print $3}' || echo 0)
OVERALL="Healthy"
[ "$RECENT_REPORTS" -gt 10 ] && OVERALL="Attention required"
cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "hours_reviewed": $HOURS,
  "diagnostic_reports_total": $TOTAL_REPORTS,
  "recent_diagnostic_reports": $RECENT_REPORTS,
  "load_average_1m": $LOAD1,
  "free_memory_pages": ${MEM_FREE_PAGES:-0},
  "overall_status": "$OVERALL"
}
EOF
printf '\nmacOS crash and performance triage completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
