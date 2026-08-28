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

# One real, nation-correct postcode OUTWARD code per nation (verified against
# perf-test: SW1A -> England). UK postcode area prefixes: SW -> England,
# EH -> Scotland, CF -> Wales, BT -> NI.
#
# The INWARD code (the "1AA" half) is synthesised per-item from its index
# rather than reused fixed -- verified empirically that reusing the exact
# same full postcode across many creates eventually makes the backend's
# applicationReference generator fail with "Failed to generate a unique
# applicationReference after 5 attempts" for THAT postcode specifically, even
# though the backend itself is healthy and a fresh postcode succeeds
# immediately. A small hand-picked pool of real postcodes (tried first) still
# ran out around item #13-20 per nation; a synthetic inward code (also
# verified working, e.g. "SW1A 9ZZ") gives 10*26*26 = 6,760 combinations per
# outward code, comfortably covering any realistic seed run size.
#
# (Plain functions/case rather than an associative array -- macOS ships bash
# 3.2, which predates `declare -A` entirely, and this needs to run
# identically on a laptop and in whatever bash the container image provides.)
ALPHA="ABCDEFGHIJKLMNOPQRSTUVWXYZ"

nation_outward() {
  case "$1" in
    England) echo "SW1A" ;;
    Scotland) echo "EH1" ;;
    Wales) echo "CF10" ;;
    NorthernIreland) echo "BT1" ;;
  esac
}

nation_postcode() {
  local nation="$1" index="$2" outward digit letter_index l1 l2
  outward="$(nation_outward "$nation")"
  digit=$((index % 10))
  letter_index=$(((index / 10) % 676))
  l1=$((letter_index / 26))
  l2=$((letter_index % 26))
  echo "$outward $digit${ALPHA:$l1:1}${ALPHA:$l2:1}"
}

# Unique-enough string for operatorApplicationId/operatorRegistrationId --
# deliberately not `uuidgen`: it's not guaranteed present in every container
# image (the base perf-test image's actual contents aren't something this
# repo controls or can easily inspect), whereas $$ / $RANDOM / an incrementing
# counter are plain bash builtins with no external dependency.
UID_COUNTER=0
next_uid() {
  UID_COUNTER=$((UID_COUNTER + 1))
  echo "$$-${UID_COUNTER}-${RANDOM}"
}

mkdir -p "$DATA_DIR"

JAR_DIR="$(mktemp -d)"
trap 'rm -rf "$JAR_DIR"' EXIT

# Deliberately avoids `sed -E`/capture groups: this container's base image is
# Alpine (verified via its public manifest -- ADD alpine-minirootfs...), whose
# default sed/grep are BusyBox applets, and BusyBox sed's -E (extended
# regexp) support is a build-time option that isn't guaranteed enabled. grep
# -o's plain [[:space:]]/[^"]* classes and `cut` are POSIX-basic and don't
# depend on that.
extract_crumb() {
  grep -o 'name="crumb"[[:space:]]*value="[^"]*"' | head -1 | cut -d'"' -f4
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
# Echoes the created workItemId on success, empty string if every retry
# failed (build_group's own -z check turns that into a clean error+exit,
# same as before -- this function's own exit status always stays 0 so a
# retried-but-ultimately-failed create doesn't trip set -e here first).
#
# Retries up to 5 times, rotating to a different postcode from the nation's
# pool each attempt (see nation_postcode above): verified empirically against
# perf-test that a REPEATED postcode is what exhausts the backend's
# applicationReference generator ("Failed to generate a unique
# applicationReference after 5 attempts"), not backend health or rate --
# identical requests with only the postcode changed succeed immediately. A
# large seed run reusing one fixed postcode per nation would eventually hit
# this and, without a retry here, kill the whole script under set -e before
# jmeter or publish_reports() ever run -- the actual cause of "no report" for
# case-management.
create_item() {
  local nation="$1" material="$2" org="$3" index="$4" jar="$JAR_DIR/$nation.txt"
  local form crumb location uid attempt

  location=""
  for attempt in 1 2 3 4 5; do
    form=$(curl -sS -c "$jar" -b "$jar" "$BASE/work-items/re-accreditation/new")
    crumb=$(echo "$form" | extract_crumb)
    uid=$(next_uid)

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
      --data-urlencode "siteAddressPostcode=$(nation_postcode "$nation" "$((index + attempt))")" \
      --data-urlencode "material=$material" \
      --data-urlencode "tonnageBand=500-5000" \
      | grep -i '^location:' | head -1 | sed 's/^[Ll]ocation: *//' | tr -d '\r\n')

    if [[ -n "$location" ]]; then
      break
    fi

    echo "  retrying $org (attempt $attempt failed — postcode likely exhausted, rotating) …" >&2
    sleep 1
  done

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
    id=$(create_item "$nation" "$material" "$org" "$i")
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
