#!/usr/bin/env bash
# export-dashboards.sh
#
# Exports Grafana dashboards to the dashboards/ directory via the Grafana HTTP API.
#
# Usage:
#   export-dashboards.sh [--include-provisioned] [--output-dir <path>]
#
# Environment variables (required):
#   GRAFANA_URL      Base URL of Grafana, e.g. https://grafana.homelab.properties
#   GRAFANA_USER     Admin username (default: admin)
#   GRAFANA_PASSWORD Admin password
#
# By default, dashboards managed by Helm/ConfigMap provisioners are skipped.
# Pass --include-provisioned to export those too.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
INCLUDE_PROVISIONED=false
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/dashboards"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-provisioned)
      INCLUDE_PROVISIONED=true
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '3,16p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------
: "${GRAFANA_URL:?GRAFANA_URL is required}"
: "${GRAFANA_PASSWORD:?GRAFANA_PASSWORD is required}"
GRAFANA_USER="${GRAFANA_USER:-admin}"

GRAFANA_URL="${GRAFANA_URL%/}"  # strip trailing slash

if ! command -v curl &>/dev/null; then
  echo "ERROR: curl is required but not found in PATH" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required but not found in PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
grafana_get() {
  # $1 = path (e.g. /api/search?type=dash-db)
  curl --silent --fail \
    --user "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}${1}"
}

slugify() {
  # Convert a dashboard title to a filesystem-safe slug
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/-\{2,\}/-/g' \
    | sed 's/^-\|-$//g'
}

# ---------------------------------------------------------------------------
# Strip fields that must not be committed to git
# ---------------------------------------------------------------------------
strip_dashboard() {
  # Reads JSON from stdin, strips id / __inputs / gnetId, writes to stdout.
  python3 - <<'PYEOF'
import sys, json

data = json.load(sys.stdin)

# The export endpoint returns {dashboard: {...}, meta: {...}}
# We only want the inner dashboard object.
db = data.get("dashboard", data)

for key in ("id", "__inputs", "gnetId"):
    db.pop(key, None)

print(json.dumps(db, indent=2, ensure_ascii=False))
PYEOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "Fetching dashboard list from ${GRAFANA_URL} …"

SEARCH_JSON=$(grafana_get "/api/search?type=dash-db&limit=5000")

TOTAL=$(echo "$SEARCH_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
echo "Found ${TOTAL} dashboard(s) total."

EXPORTED=0
SKIPPED=0

while IFS= read -r row; do
  DASH_UID=$(echo "$row"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uid',''))")
  TITLE=$(echo "$row" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))")

  # Fetch full dashboard (includes meta.provisioned)
  FULL_JSON=$(grafana_get "/api/dashboards/uid/${DASH_UID}")

  PROVISIONED=$(echo "$FULL_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(str(d.get('meta',{}).get('provisioned',False)).lower())")

  if [[ "$PROVISIONED" == "true" && "$INCLUDE_PROVISIONED" == "false" ]]; then
    echo "  SKIP  [provisioned] ${TITLE} (${DASH_UID})"
    (( SKIPPED++ )) || true
    continue
  fi

  SLUG=$(slugify "$TITLE")
  OUT_FILE="${OUTPUT_DIR}/${SLUG}.json"

  echo "$FULL_JSON" | strip_dashboard > "$OUT_FILE"

  echo "  OK    ${TITLE} → dashboards/${SLUG}.json"
  (( EXPORTED++ )) || true

done < <(echo "$SEARCH_JSON" | python3 -c "
import sys, json
for item in json.load(sys.stdin):
    print(json.dumps(item))
")

echo ""
echo "Done. Exported: ${EXPORTED}  Skipped (provisioned): ${SKIPPED}"
if [[ $SKIPPED -gt 0 && "$INCLUDE_PROVISIONED" == "false" ]]; then
  echo "Tip: re-run with --include-provisioned to export Helm-managed dashboards too."
fi
