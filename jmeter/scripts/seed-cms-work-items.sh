#!/usr/bin/env bash
# Seed re-accreditation work items via the real /work-items/re-accreditation/new
# create-work-item form (a live authenticated HTTP POST against the
# case-management-frontend app), then write the three JMeter CSV data files
# consumed by case-management-journey.jmx.
#
# Replaces the old docker-exec-based direct-Mongo seeding, which only worked
# against a local docker-compose stack's mongo container -- useless against a
# real deployed environment like CDP Portal's perf-test, where there's no
# Docker socket and no local mongo container at all (that mismatch caused
# entrypoint.sh to crash before ever running jmeter or generating a report).
# This works against ANY reachable environment, local or remote, since it's
# just an authenticated HTTP client driving the app's own demo "create a work
# item" form (RA-127) -- the same form a caseworker would use by hand.
#
# Verified empirically against perf-test:
#   - the backend derives each item's `nation` from its postcode (see
#     nation_postcode() below -- each pins a postcode area prefix that
#     genuinely resolves to that nation, e.g. SW1A 1AA -> England)
#   - a freshly created item lands in state 'submitted', exactly the starting
#     point case-management-journey.jmx's "Duly Make — Record Payment" step
#     expects (the journey was already built to walk items through the full
#     realistic lifecycle from there, not a pre-advanced state)
#   - the live form currently has three fields not documented in this repo's
#     other notes (operatorOrganisationId, operatorApplicationId,
#     operatorRegistrationId) -- all left as their form-prefilled demo shape
#     below since the backend doesn't appear to validate their format
#
# Usage:
#   CM_BASE_URL=localhost CM_PORT=5001 CM_PROTOCOL=http ./jmeter/scripts/seed-cms-work-items.sh
#   CM_BASE_URL=epr-register-enrol-management-fe.perf-test.cdp-int.defra.cloud \
#     CM_PORT=443 CM_PROTOCOL=https ./jmeter/scripts/seed-cms-work-items.sh
#
# Item counts (default: 100 total, same ~3:2:2 ratio as before):
#   APPROVE_COUNT=43 REFUSE_COUNT=29 QUERY_COUNT=28 ./jmeter/scripts/seed-cms-work-items.sh
#
# This does ~2 live HTTP requests per item (GET the form for a fresh crumb,
# POST the creation) plus one login per nation -- for the default 100 items
# that's ~208 requests against the target environment, so expect this step
# to take real time (a couple of minutes), not be instant.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="${DATA_DIR:-$REPO_ROOT/jmeter/data}"

CM_BASE_URL="${CM_BASE_URL:-localhost}"
CM_PORT="${CM_PORT:-5001}"
CM_PROTOCOL="${CM_PROTOCOL:-http}"
BASE="$CM_PROTOCOL://$CM_BASE_URL:$CM_PORT"

APPROVE_COUNT="${APPROVE_COUNT:-43}"
REFUSE_COUNT="${REFUSE_COUNT:-29}"
QUERY_COUNT="${QUERY_COUNT:-28}"
TOTAL_COUNT=$((APPROVE_COUNT + REFUSE_COUNT + QUERY_COUNT))

MATERIALS=(plastic steel paper glass aluminium wood)
NATIONS=(England Scotland Wales NorthernIreland)

# One postcode per nation -- must genuinely resolve to that nation
# server-side (verified against perf-test: SW1A 1AA -> England). UK postcode
# area prefixes: SW -> England, EH -> Scotland, CF -> Wales, BT -> NI.
# (A case statement rather than an associative array -- macOS ships bash 3.2,
# which predates `declare -A` entirely, and this needs to run identically on
# a laptop and in whatever bash the container image provides.)
nation_postcode() {
  case "$1" in
    England) echo "SW1A 1AA" ;;
    Scotland) echo "EH1 1YZ" ;;
    Wales) echo "CF10 1AB" ;;
    NorthernIreland) echo "BT1 1AA" ;;
  esac
}

mkdir -p "$DATA_DIR"

JAR_DIR="$(mktemp -d)"
trap 'rm -rf "$JAR_DIR"' EXIT

extract_crumb() {
  grep -o 'name="crumb"[[:space:]]*value="[^"]*"' | head -1 | sed -E 's/.*value="([^"]*)".*/\1/'
}

# Logs in once per nation, as a caseworker scoped to that nation -- the
# resulting session cookie (jar per nation) is reused for every item created
# under that nation, rather than logging in again per item.
login_nation() {
  local nation="$1" jar="$JAR_DIR/$nation.txt"
  local login_page crumb
  login_page=$(curl -sS -c "$jar" -b "$jar" "$BASE/auth/stub/login")
  crumb=$(echo "$login_page" | extract_crumb)
  curl -sS -c "$jar" -b "$jar" -o /dev/null \
    -X POST "$BASE/auth/stub/login" \
    --data-urlencode "nation=$nation" \
    --data-urlencode "crumb=$crumb"
}

# Creates one work item as the given (already-logged-in) nation's caseworker.
# Echoes the created workItemId on success, nothing on failure.
create_item() {
  local nation="$1" material="$2" org="$3" jar="$JAR_DIR/$nation.txt"
  local form crumb location uid

  form=$(curl -sS -c "$jar" -b "$jar" "$BASE/work-items/re-accreditation/new")
  crumb=$(echo "$form" | extract_crumb)
  uid=$(uuidgen | tr '[:upper:]' '[:lower:]')

  location=$(curl -sS -c "$jar" -b "$jar" -o /dev/null -D - \
    -X POST "$BASE/work-items/re-accreditation/new" \
    --data-urlencode "crumb=$crumb" \
    --data-urlencode "operatorEmail=perf.test@example.com" \
    --data-urlencode "organisationName=$org" \
    --data-urlencode "operatorOrganisationId=500001" \
    --data-urlencode "operatorApplicationId=app-perf-$uid" \
    --data-urlencode "operatorRegistrationId=reg-perf-$uid" \
    --data-urlencode "siteAddressLine1=12 Industrial Way" \
    --data-urlencode "siteAddressTown=Perf Test Town" \
    --data-urlencode "siteAddressPostcode=$(nation_postcode "$nation")" \
    --data-urlencode "material=$material" \
    --data-urlencode "tonnageBand=500-5000" \
    | grep -i '^location:' | sed -E 's/^[Ll]ocation: *//; s/\r$//')

  echo "${location##*/}"
}

echo "Logging in per nation…"
for nation in "${NATIONS[@]}"; do
  login_nation "$nation"
done

# build_group <label> <count> <csv_file> -> creates <count> real work items via
# live HTTP, cycling nation/material so a large count still gets varied data,
# and writes the matching CSV (same workItemId,nation,material shape as
# before -- case-management-journey.jmx doesn't need to change).
build_group() {
  local label="$1" count="$2" csv_file="$3"
  echo "workItemId,nation,material" > "$csv_file"

  local i nation material org id
  for ((i = 1; i <= count; i++)); do
    nation="${NATIONS[$(((i - 1) % ${#NATIONS[@]}))]}"
    material="${MATERIALS[$(((i - 1) % ${#MATERIALS[@]}))]}"
    org="Perf $label $nation Ltd $(printf '%03d' "$i")"
    id=$(create_item "$nation" "$material" "$org")
    if [[ -z "$id" ]]; then
      echo "ERROR: failed to create item $i/$count for $label ($nation/$material)" >&2
      exit 1
    fi
    echo "$id,$nation,$material" >> "$csv_file"
    echo "  [$label $i/$count] $nation/$material -> $id"
  done
}

echo "Seeding $TOTAL_COUNT work items via $BASE (approve=$APPROVE_COUNT refuse=$REFUSE_COUNT query=$QUERY_COUNT) …"
build_group Approve "$APPROVE_COUNT" "$DATA_DIR/cms-approve.csv"
build_group Refuse "$REFUSE_COUNT" "$DATA_DIR/cms-refuse.csv"
build_group Query "$QUERY_COUNT" "$DATA_DIR/cms-query.csv"

echo ""
echo "CSVs written to $DATA_DIR/"
echo "  cms-approve.csv  → $APPROVE_COUNT rows"
echo "  cms-refuse.csv   → $REFUSE_COUNT rows"
echo "  cms-query.csv    → $QUERY_COUNT rows"
