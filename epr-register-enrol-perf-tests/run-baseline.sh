#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ENVIRONMENT=staging TEST_USERNAME=user TEST_PASSWORD=pass ./run-baseline.sh [plan]
#   LOCAL=true ./run-baseline.sh [plan]   # run against localhost:3000 (no auth required)
#
# plan: operator | regulator | operator-accreditation | all (default: all)

ENVIRONMENT="${ENVIRONMENT:-staging}"
TEST_USERNAME="${TEST_USERNAME:-}"
TEST_PASSWORD="${TEST_PASSWORD:-}"
APP_ID="${APP_ID:-app001}"
LOCAL="${LOCAL:-false}"

if [[ "$LOCAL" == "true" ]]; then
  BASE_URL="localhost"
  PORT="3000"
  PROTOCOL="http"
else
  if [[ -z "$TEST_USERNAME" || -z "$TEST_PASSWORD" ]]; then
    echo "ERROR: TEST_USERNAME and TEST_PASSWORD must be set (or use LOCAL=true for localhost)"
    exit 1
  fi
  BASE_URL="epr-register-enrol-frontend.${ENVIRONMENT}.cdp-int.defra.cloud"
  PORT="443"
  PROTOCOL="https"
fi
PLAN="${1:-all}"
PLANS_DIR="$(dirname "$0")/jmeter/plans"
RESULTS_DIR="$(dirname "$0")/jmeter/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "$RESULTS_DIR"

run_plan() {
  local name="$1"
  local port_override="${2:-$PORT}"
  local jmx="$PLANS_DIR/${name}.jmx"
  local jtl="$RESULTS_DIR/${name}_${TIMESTAMP}.jtl"
  local log="$RESULTS_DIR/${name}_${TIMESTAMP}.log"

  echo "Running: $name → $jtl"
  jmeter -n \
    -t "$jmx" \
    -l "$jtl" \
    -j "$log" \
    -Jbase_url="$BASE_URL" \
    -Jport="$port_override" \
    -Jprotocol="$PROTOCOL" \
    -Jdata_dir="jmeter/data" \
    -Jusername="${TEST_USERNAME:-}" \
    -Jpassword="${TEST_PASSWORD:-}" \
    -Japp_id="$APP_ID"

  echo "Done: $name — results at $jtl"
}

case "$PLAN" in
  operator)               run_plan "operator-journey" ;;
  regulator)              run_plan "regulator-journey" ;;
  operator-accreditation) run_plan "operator-accreditation-journey" ;;
  case-management)
    CM_PORT="${CM_PORT:-5001}"
    echo "Seeding work items…"
    bash "$(dirname "$0")/jmeter/scripts/seed-cms-work-items.sh"
    run_plan "case-management-journey" "$CM_PORT"
    ;;
  all)
    run_plan "operator-journey"
    run_plan "regulator-journey"
    run_plan "operator-accreditation-journey"
    run_plan "case-management-journey"
    ;;
  *)
    echo "Unknown plan: $PLAN. Use: operator | regulator | operator-accreditation | case-management | all"
    exit 1
    ;;
esac

echo ""
echo "All done. Results in $RESULTS_DIR"
echo "To generate HTML report: jmeter -g <jtl> -o <output-dir>"
