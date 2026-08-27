#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ENVIRONMENT=staging TEST_USERNAME=user TEST_PASSWORD=pass ./entrypoint.sh [plan]
#   LOCAL=true ./entrypoint.sh [plan]   # run against localhost (no auth required)
#
# Case management specific overrides:
#   In CI/CDP (LOCAL unset), CM_BASE_URL auto-derives from ENVIRONMENT just like
#   BASE_URL does, e.g. ENVIRONMENT=perf-test ->
#   epr-register-enrol-management-fe.perf-test.cdp-int.defra.cloud — no need to
#   pass CM_BASE_URL by hand unless targeting something non-standard:
#   ENVIRONMENT=perf-test CM_SKIP_SEED=true TEST_USERNAME=user TEST_PASSWORD=pass ./entrypoint.sh case-management
#   CM_BASE_URL=some-other-host.cdp-int.defra.cloud ./entrypoint.sh case-management   # explicit override
#   CM_PORT=443 CM_PROTOCOL=https ./entrypoint.sh case-management
#   CM_SKIP_SEED=true  # skip MongoDB seeding (use when targeting a remote env)
#
# Operator bulk journey overrides (Reprocessor/Exporter, Submit/Withdraw, users + ramp-up):
#   ./entrypoint.sh operator-bulk                                    # default: 100 users -> Submitted (50 reprocessor + 50 exporter), ramp 2->100 over 5s
#   REPROCESSOR_WITHDRAW_USERS=5 EXPORTER_WITHDRAW_USERS=5 \
#     REPROCESSOR_SUBMIT_USERS=45 EXPORTER_SUBMIT_USERS=45 \
#     ./entrypoint.sh operator-bulk                                  # 90 -> Submitted, 10 -> Withdrawn
#   RAMP_TIME=10 ./entrypoint.sh operator-bulk                       # slower ramp
#   OJ_SKIP_SEED=true ./entrypoint.sh operator-bulk                  # reuse existing CSV rows (they're one-shot; only safe if the previous run didn't consume them all)
#
# plan: operator | regulator | operator-accreditation | operator-bulk | case-management | all (default: all)
#   No plan argument needed for normal use — the Dockerfile's ENTRYPOINT runs
#   bare, so PLAN defaults to "all", which now just runs
#   operator-accreditation-journey. case-management is temporarily disabled
#   (see the commented-out "case-management" case arm and the "all" block
#   below) while diagnosing CDP Portal's "No report found" issue: every known-
#   working DEFRA perf-test repo runs exactly one scenario per container
#   invocation and writes its dashboard straight to $JM_REPORTS (report root),
#   not a subdirectory. Running two scenarios per invocation meant our root
#   index.html was a hand-rolled landing page instead of jmeter's own
#   dashboard output, which may be why CDP Portal didn't recognise it as a
#   report. Re-enable case-management by uncommenting its case arm and the
#   "all" block below once single-scenario runs are confirmed working — note
#   doing so again means restoring per-scenario subdirectories + a landing
#   page, since jmeter's -o refuses to write into a non-empty directory.

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
  # TEST_USERNAME/TEST_PASSWORD are NOT required to reach the app — every
  # journey in this suite authenticates via app-level stub login
  # (/auth/stub/login), not HTTP Basic Auth. Verified directly: hitting
  # epr-register-enrol-management-fe.perf-test.cdp-int.defra.cloud with no
  # credentials at all works fine. Only warn if they're unset, in case some
  # environment genuinely does sit behind Basic Auth at the edge and these
  # get wired into a header/auth manager later -- don't hard-fail a run that
  # doesn't need them.
  if [[ -z "$TEST_USERNAME" || -z "$TEST_PASSWORD" ]]; then
    echo "WARNING: TEST_USERNAME/TEST_PASSWORD not set — continuing, since stub login doesn't need them. Set LOCAL=true instead if you actually meant to target localhost."
  fi
  BASE_URL="epr-register-enrol-frontend.${ENVIRONMENT}.cdp-int.defra.cloud"
  PORT="443"
  PROTOCOL="https"
fi

# Case management frontend has a different hostname from the operator frontend.
# Mirrors the BASE_URL logic above: localhost:5001 for LOCAL=true, otherwise
# auto-derived from ENVIRONMENT (matching the real CDP service name,
# epr-register-enrol-management-fe) — so a CI/CDP run only needs
# ENVIRONMENT set, the same as every other plan, rather than requiring
# CM_BASE_URL to be remembered and passed separately every time.
# Override CM_BASE_URL explicitly if a run ever needs a different target.
if [[ "$LOCAL" == "true" ]]; then
  CM_BASE_URL="${CM_BASE_URL:-localhost}"
  CM_PORT="${CM_PORT:-5001}"
  CM_PROTOCOL="${CM_PROTOCOL:-http}"
else
  CM_BASE_URL="${CM_BASE_URL:-epr-register-enrol-management-fe.${ENVIRONMENT}.cdp-int.defra.cloud}"
  CM_PORT="${CM_PORT:-443}"
  CM_PROTOCOL="${CM_PROTOCOL:-https}"
fi

# Auto-detect env settings when a remote CM_BASE_URL is provided explicitly
# (covers LOCAL=true runs that still pass a real CM_BASE_URL by hand)
if [[ "$CM_BASE_URL" != "localhost" && "$CM_PROTOCOL" == "http" ]]; then
  CM_PORT="443"
  CM_PROTOCOL="https"
fi

# Skip MongoDB seeding when targeting a remote env (no direct DB access)
CM_SKIP_SEED="${CM_SKIP_SEED:-false}"
PLAN="${1:-all}"

# Some CDP perf-test runners expect the base image's standard
# SERVICE_ENDPOINT/SERVICE_PORT/SERVICE_URL_SCHEME variable names (defaulting
# to a literal "service-name.${ENVIRONMENT}..." placeholder when unset — the
# "UnknownHostException: service-name..." error). Export them here from the
# already-correct, dynamically-per-ENVIRONMENT values above, rather than
# hardcoding a specific environment's hostname anywhere: only the service
# *name* (epr-register-enrol-frontend / epr-register-enrol-management-fe) is
# fixed, same as BASE_URL/CM_BASE_URL. Case management targets its own
# service; everything else targets the operator frontend.
if [[ "$PLAN" == "case-management" ]]; then
  export SERVICE_ENDPOINT="$CM_BASE_URL"
  export SERVICE_PORT="$CM_PORT"
  export SERVICE_URL_SCHEME="$CM_PROTOCOL"
else
  export SERVICE_ENDPOINT="$BASE_URL"
  export SERVICE_PORT="$PORT"
  export SERVICE_URL_SCHEME="$PROTOCOL"
fi

# Matches the base image's own entrypoint.sh convention: JM_HOME defaults to
# /opt/perftest, the Dockerfile's WORKDIR, so paths resolve the same way
# whether the base image's stock script or this one runs. Falls back to the
# script's own directory when /opt/perftest doesn't exist (local runs outside
# the container).
JM_HOME="${JM_HOME:-/opt/perftest}"
if [[ ! -d "$JM_HOME" ]]; then
  JM_HOME="$(cd "$(dirname "$0")" && pwd)"
fi

JM_SCENARIOS="$JM_HOME/scenarios"
JM_LOGS="$JM_HOME/logs"
RESULTS_DIR="$JM_HOME/jmeter/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# HTML dashboard reports, matching the reference epr-re-ex-performance-tests
# entrypoint.sh convention (and this repo's own compose.yml, which already
# mounts ./reports:/opt/perftest/reports) -- CDP Portal's report page reads
# from here, not from jmeter/results/*.jtl.
JM_REPORTS="$JM_HOME/reports"
REPORT_NAMES=()

# Tracks the jmeter exit code across plans so it can be propagated as this
# script's own exit code at the very end, matching the reference entrypoint's
# `exit $test_exit_code` -- report publishing must still happen first (a
# non-zero jmeter exit is normal, sample failures, not a broken run), but the
# final exit code should reflect it so CDP Portal's pass/fail status is
# accurate rather than always green.
TEST_EXIT_CODE=0

mkdir -p "$RESULTS_DIR" "$JM_LOGS" "$JM_REPORTS"

run_plan() {
  local name="$1"
  local base="${2:-$BASE_URL}"
  local port="${3:-$PORT}"
  local proto="${4:-$PROTOCOL}"
  local jmx="$JM_SCENARIOS/${name}.jmx"
  local jtl="$RESULTS_DIR/${name}_${TIMESTAMP}.jtl"
  local log="$JM_LOGS/${name}_${TIMESTAMP}.log"

  echo "Running: $name → $proto://$base:$port"
  # -o "$JM_REPORTS" writes jmeter's own dashboard straight to the reports
  # root, matching the template/reference entrypoint.sh convention exactly
  # (see the plan-selection comment above) -- only one scenario runs per
  # invocation now, so there's no subdirectory nesting or synthetic landing
  # page needed; $JM_REPORTS/index.html is jmeter's real generated dashboard.
  #
  # A non-zero jmeter exit here (extremely common -- it means at least one
  # sample failed, not that the run itself broke) must NOT trip set -e and
  # kill the script before publish_reports() ever runs. The report's whole
  # purpose is to show which samples failed, so a script that dies here
  # produces exactly the "tests ran but no report" symptom this is fixing.
  jmeter -n \
    -t "$jmx" \
    -l "$jtl" \
    -j "$log" \
    -e -o "$JM_REPORTS" \
    -f \
    -Jbase_url="$base" \
    -Jport="$port" \
    -Jprotocol="$proto" \
    -Jdata_dir="jmeter/data" \
    -Jusername="${TEST_USERNAME:-}" \
    -Jpassword="${TEST_PASSWORD:-}" \
    -Japp_id="$APP_ID" \
    || { TEST_EXIT_CODE=$?; echo "jmeter exited non-zero ($TEST_EXIT_CODE) for $name (likely sample failures) — continuing to report generation"; }

  REPORT_NAMES+=("$name")
  echo "Done: $name — results at $jtl, report at $JM_REPORTS"
}

# Uploads the reports/ tree (jmeter's own dashboard, written straight to
# $JM_REPORTS by -o) to S3 for CDP Portal to display. Fails loudly (exit 1)
# on a missing RESULTS_OUTPUT_S3_PATH, a missing index.html, or a failed
# upload -- matching the base image's own reference entrypoint.sh, which
# treats all three as fatal. A silent "not uploaded, continuing" here would
# make a run look green in CDP Portal even though no report was ever
# published, which is exactly the "tests ran but no report" symptom this
# whole function exists to fix -- better to have CDP Portal show the run as
# failed so a missing/misconfigured RESULTS_OUTPUT_S3_PATH is immediately
# visible instead of silently swallowed.
publish_reports() {
  if [[ ${#REPORT_NAMES[@]} -eq 0 ]]; then
    echo "No reports were generated — nothing to publish."
    return
  fi

  if [[ -z "${RESULTS_OUTPUT_S3_PATH:-}" ]]; then
    echo "ERROR: RESULTS_OUTPUT_S3_PATH is not set — reports were generated at $JM_REPORTS but cannot be published for CDP Portal to display them."
    exit 1
  fi

  if [[ ! -f "$JM_REPORTS/index.html" ]]; then
    echo "ERROR: $JM_REPORTS/index.html not found — nothing to publish."
    exit 1
  fi

  echo "Publishing reports to $RESULTS_OUTPUT_S3_PATH …"
  if aws --endpoint-url="${S3_ENDPOINT:-}" s3 cp "$JM_REPORTS" "$RESULTS_OUTPUT_S3_PATH" --recursive; then
    echo "Reports published to $RESULTS_OUTPUT_S3_PATH"
  else
    echo "ERROR: failed to publish reports to $RESULTS_OUTPUT_S3_PATH — reports remain at $JM_REPORTS"
    exit 1
  fi
}

case "$PLAN" in
  operator)               run_plan "operator-journey" ;;
  regulator)              run_plan "regulator-journey" ;;
  operator-accreditation) run_plan "operator-accreditation-journey" ;;
  operator-bulk)
    OJ_SKIP_SEED="${OJ_SKIP_SEED:-false}"
    if [[ "$OJ_SKIP_SEED" != "true" ]]; then
      echo "Seeding fresh reprocessor/exporter application rows…"
      bash "$JM_HOME/jmeter/scripts/seed-operator-journey-csvs.sh"
    else
      echo "Skipping seed (OJ_SKIP_SEED=true) — reusing existing CSV rows"
    fi
    name="operator-journey-reprocessor-exporter"
    jtl="$RESULTS_DIR/${name}_${TIMESTAMP}.jtl"
    log="$JM_LOGS/${name}_${TIMESTAMP}.log"
    echo "Running: $name → $PROTOCOL://$BASE_URL:$PORT (ramp ${RAMP_TIME:-5}s)"
    jmeter -n \
      -t "$JM_SCENARIOS/${name}.jmx" \
      -l "$jtl" \
      -j "$log" \
      -e -o "$JM_REPORTS" \
      -f \
      -Jbase_url="$BASE_URL" \
      -Jport="$PORT" \
      -Jprotocol="$PROTOCOL" \
      -Jdata_dir="jmeter/data" \
      -Jreprocessor_submit_users="${REPROCESSOR_SUBMIT_USERS:-50}" \
      -Jexporter_submit_users="${EXPORTER_SUBMIT_USERS:-50}" \
      -Jreprocessor_withdraw_users="${REPROCESSOR_WITHDRAW_USERS:-0}" \
      -Jexporter_withdraw_users="${EXPORTER_WITHDRAW_USERS:-0}" \
      -Jramp_time="${RAMP_TIME:-5}" \
      || { TEST_EXIT_CODE=$?; echo "jmeter exited non-zero ($TEST_EXIT_CODE) for $name (likely sample failures) — continuing to report generation"; }
    REPORT_NAMES+=("$name")
    echo "Done: $name — results at $jtl, report at $JM_REPORTS"
    ;;
  # case-management)
  #   echo "Case management target: $CM_PROTOCOL://$CM_BASE_URL:$CM_PORT"
  #   if [[ "$CM_SKIP_SEED" != "true" ]]; then
  #     echo "Seeding work items into local MongoDB…"
  #     bash "$JM_HOME/jmeter/scripts/seed-cms-work-items.sh"
  #   else
  #     echo "Skipping seed (CM_SKIP_SEED=true) — using existing work item IDs from CSV files"
  #   fi
  #   run_plan "case-management-journey" "$CM_BASE_URL" "$CM_PORT" "$CM_PROTOCOL"
  #   ;;
  all)
    # Default entrypoint (no plan argument needed). Currently just an alias
    # for operator-accreditation-journey -- case-management is temporarily
    # disabled, see the plan-selection comment near the top of this file.
    echo "=== Operator accreditation (epr-register-enrol-frontend) ==="
    run_plan "operator-accreditation-journey"

    # echo "=== Case management (epr-register-enrol-management-fe) ==="
    # echo "Case management target: $CM_PROTOCOL://$CM_BASE_URL:$CM_PORT"
    # if [[ "$CM_SKIP_SEED" != "true" ]]; then
    #   echo "Seeding work items into local MongoDB…"
    #   bash "$JM_HOME/jmeter/scripts/seed-cms-work-items.sh"
    # else
    #   echo "Skipping seed (CM_SKIP_SEED=true) — using existing work item IDs from CSV files"
    # fi
    # run_plan "case-management-journey" "$CM_BASE_URL" "$CM_PORT" "$CM_PROTOCOL"
    ;;
  *)
    echo "Unknown plan: $PLAN. Use: operator | regulator | operator-accreditation | operator-bulk | all (case-management is currently disabled, see top of file)"
    exit 1
    ;;
esac

publish_reports

echo ""
echo "All done. Raw results in $RESULTS_DIR, HTML report(s) in $JM_REPORTS"

exit "$TEST_EXIT_CODE"
