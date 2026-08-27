#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ENVIRONMENT=staging TEST_USERNAME=user TEST_PASSWORD=pass ./run-baseline.sh [plan]
#   LOCAL=true ./run-baseline.sh [plan]   # run against localhost (no auth required)
#
# Case management specific overrides:
#   CM_BASE_URL=epr-register-enrol-management-fe.test.cdp-int.defra.cloud ./run-baseline.sh case-management
#   CM_BASE_URL=epr-register-enrol-management-fe.perf-test.cdp-int.defra.cloud CM_SKIP_SEED=true ./run-baseline.sh case-management
#   CM_PORT=443 CM_PROTOCOL=https ./run-baseline.sh case-management
#   CM_SKIP_SEED=true  # skip MongoDB seeding (use when targeting a remote env)
#
# Operator bulk journey overrides (Reprocessor/Exporter, Submit/Withdraw, users + ramp-up):
#   ./run-baseline.sh operator-bulk                                    # default: 100 users -> Submitted (50 reprocessor + 50 exporter), ramp 2->100 over 5s
#   REPROCESSOR_WITHDRAW_USERS=5 EXPORTER_WITHDRAW_USERS=5 \
#     REPROCESSOR_SUBMIT_USERS=45 EXPORTER_SUBMIT_USERS=45 \
#     ./run-baseline.sh operator-bulk                                  # 90 -> Submitted, 10 -> Withdrawn
#   RAMP_TIME=10 ./run-baseline.sh operator-bulk                       # slower ramp
#   OJ_SKIP_SEED=true ./run-baseline.sh operator-bulk                  # reuse existing CSV rows (they're one-shot; only safe if the previous run didn't consume them all)
#
# plan: operator | regulator | operator-accreditation | operator-bulk | case-management | all (default: all)

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

# Case management frontend has a different hostname from the operator frontend.
# Default to localhost:5001 locally; override CM_BASE_URL for remote envs.
# Example: CM_BASE_URL=epr-register-enrol-management-fe.test.cdp-int.defra.cloud
CM_BASE_URL="${CM_BASE_URL:-localhost}"
CM_PORT="${CM_PORT:-5001}"
CM_PROTOCOL="${CM_PROTOCOL:-http}"

# Auto-detect env settings when a remote CM_BASE_URL is provided explicitly
if [[ "$CM_BASE_URL" != "localhost" && "$CM_PROTOCOL" == "http" ]]; then
  CM_PORT="443"
  CM_PROTOCOL="https"
fi

# Skip MongoDB seeding when targeting a remote env (no direct DB access)
CM_SKIP_SEED="${CM_SKIP_SEED:-false}"
PLAN="${1:-all}"
PLANS_DIR="$(dirname "$0")/jmeter/plans"
RESULTS_DIR="$(dirname "$0")/jmeter/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "$RESULTS_DIR"

run_plan() {
  local name="$1"
  local base="${2:-$BASE_URL}"
  local port="${3:-$PORT}"
  local proto="${4:-$PROTOCOL}"
  local jmx="$PLANS_DIR/${name}.jmx"
  local jtl="$RESULTS_DIR/${name}_${TIMESTAMP}.jtl"
  local log="$RESULTS_DIR/${name}_${TIMESTAMP}.log"

  echo "Running: $name → $proto://$base:$port"
  jmeter -n \
    -t "$jmx" \
    -l "$jtl" \
    -j "$log" \
    -Jbase_url="$base" \
    -Jport="$port" \
    -Jprotocol="$proto" \
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
  operator-bulk)
    OJ_SKIP_SEED="${OJ_SKIP_SEED:-false}"
    if [[ "$OJ_SKIP_SEED" != "true" ]]; then
      echo "Seeding fresh reprocessor/exporter application rows…"
      bash "$(dirname "$0")/jmeter/scripts/seed-operator-journey-csvs.sh"
    else
      echo "Skipping seed (OJ_SKIP_SEED=true) — reusing existing CSV rows"
    fi
    name="operator-journey-reprocessor-exporter"
    jtl="$RESULTS_DIR/${name}_${TIMESTAMP}.jtl"
    log="$RESULTS_DIR/${name}_${TIMESTAMP}.log"
    echo "Running: $name → $PROTOCOL://$BASE_URL:$PORT (ramp ${RAMP_TIME:-5}s)"
    jmeter -n \
      -t "$PLANS_DIR/${name}.jmx" \
      -l "$jtl" \
      -j "$log" \
      -Jbase_url="$BASE_URL" \
      -Jport="$PORT" \
      -Jprotocol="$PROTOCOL" \
      -Jdata_dir="jmeter/data" \
      -Jreprocessor_submit_users="${REPROCESSOR_SUBMIT_USERS:-50}" \
      -Jexporter_submit_users="${EXPORTER_SUBMIT_USERS:-50}" \
      -Jreprocessor_withdraw_users="${REPROCESSOR_WITHDRAW_USERS:-0}" \
      -Jexporter_withdraw_users="${EXPORTER_WITHDRAW_USERS:-0}" \
      -Jramp_time="${RAMP_TIME:-5}"
    echo "Done: $name — results at $jtl"
    ;;
  case-management)
    echo "Case management target: $CM_PROTOCOL://$CM_BASE_URL:$CM_PORT"
    if [[ "$CM_SKIP_SEED" != "true" ]]; then
      echo "Seeding work items into local MongoDB…"
      bash "$(dirname "$0")/jmeter/scripts/seed-cms-work-items.sh"
    else
      echo "Skipping seed (CM_SKIP_SEED=true) — using existing work item IDs from CSV files"
    fi
    run_plan "case-management-journey" "$CM_BASE_URL" "$CM_PORT" "$CM_PROTOCOL"
    ;;
  all)
    run_plan "operator-journey"
    run_plan "regulator-journey"
    run_plan "operator-accreditation-journey"
    run_plan "case-management-journey" "$CM_BASE_URL" "$CM_PORT" "$CM_PROTOCOL"
    ;;
  *)
    echo "Unknown plan: $PLAN. Use: operator | regulator | operator-accreditation | operator-bulk | case-management | all"
    exit 1
    ;;
esac

echo ""
echo "All done. Results in $RESULTS_DIR"
echo "To generate HTML report: jmeter -g <jtl> -o <output-dir>"
