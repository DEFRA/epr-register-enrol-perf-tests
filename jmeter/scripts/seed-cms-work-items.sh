#!/usr/bin/env bash
# Seed re-accreditation work items into the case-management MongoDB and
# write the three JMeter CSV data files.
#
# Usage: ./jmeter/scripts/seed-cms-work-items.sh
#
# Item counts (default: 100 total, same ~3:2:2 ratio as the original 7-item set):
#   APPROVE_COUNT=43 REFUSE_COUNT=29 QUERY_COUNT=28 ./jmeter/scripts/seed-cms-work-items.sh
#
# Defaults:
#   MONGO_CONTAINER=epr-register-enrol-mongodb-1
#   MONGO_DB=epr-register-case-management
#   DATA_DIR=jmeter/data  (relative to repo root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$REPO_ROOT/jmeter/data"
MONGO_CONTAINER="${MONGO_CONTAINER:-epr-register-enrol-mongodb-1}"
MONGO_DB="${MONGO_DB:-epr-register-case-management}"

APPROVE_COUNT="${APPROVE_COUNT:-43}"
REFUSE_COUNT="${REFUSE_COUNT:-29}"
QUERY_COUNT="${QUERY_COUNT:-28}"
TOTAL_COUNT=$((APPROVE_COUNT + REFUSE_COUNT + QUERY_COUNT))

gen() { uuidgen | tr '[:upper:]' '[:lower:]'; }

NATIONS=(England Scotland Wales NorthernIreland)
MATERIALS=(plastic steel paper glass aluminium wood)
POSTCODES=("SW1A 1AA" "EH1 1YZ" "CF10 1AB" "BT1 1AA" "M1 1AE" "SA1 1AA" "G1 1AA" "BT48 6HH" "BS1 4DJ" "AB10 1AB")

mkdir -p "$DATA_DIR"

# build_group <prefix> <count> <csv_file> -> populates ITEMS_JS (mongo insertMany
# entries) and writes the matching CSV, cycling nation/material/postcode so a
# large count still gets realistic, varied data.
ITEMS_JS=""
build_group() {
  local prefix="$1" label="$2" count="$3" csv_file="$4"
  echo "workItemId,nation,material" > "$csv_file"

  local i nation material postcode id org reg
  for ((i = 1; i <= count; i++)); do
    id=$(gen)
    nation="${NATIONS[$(((i - 1) % ${#NATIONS[@]}))]}"
    material="${MATERIALS[$(((i - 1) % ${#MATERIALS[@]}))]}"
    postcode="${POSTCODES[$(((i - 1) % ${#POSTCODES[@]}))]}"
    org="Perf $label $nation Ltd $(printf '%03d' "$i")"
    reg="P${prefix}$(printf '%03d' "$i")"

    ITEMS_JS+="item('$id','$org','$material','$postcode','$nation','$reg'),"
    echo "$id,$nation,$material" >> "$csv_file"
  done
}

build_group A Approve "$APPROVE_COUNT" "$DATA_DIR/cms-approve.csv"
build_group R Refuse "$REFUSE_COUNT" "$DATA_DIR/cms-refuse.csv"
build_group Q Query "$QUERY_COUNT" "$DATA_DIR/cms-query.csv"

echo "Seeding $TOTAL_COUNT work items into $MONGO_CONTAINER/$MONGO_DB (approve=$APPROVE_COUNT refuse=$REFUSE_COUNT query=$QUERY_COUNT) …"

docker exec "$MONGO_CONTAINER" mongosh --quiet \
  "mongodb://localhost:27017/$MONGO_DB" \
  --eval "
var now = new Date();

// Remove any previous perf-test items before re-seeding
var deleted = db.workItems.deleteMany({'payload.perfTest': true});
print('Cleared ' + deleted.deletedCount + ' previous perf-test items.');

function item(id, org, material, postcode, nation, reg) {
  return {
    _id: id,
    typeId: 're-accreditation',
    stateId: 'submitted',
    submittedAt: now,
    lastModifiedAt: now,
    submittedBy: 'perf-test',
    assignedToId: null,
    assignedToName: null,
    assignedAt: null,
    assignedBy: null,
    slaClock: null,
    version: 0,
    completedTaskIdsByState: {},
    auditLog: [{
      action: 'work-item-submitted',
      actionDisplayName: 'Work item submitted',
      details: { typeId: 're-accreditation', source: 'perf-test' },
      createdAt: now,
      createdBy: 'perf-test',
      createdByName: null
    }],
    payload: {
      perfTest: true,
      organisationName: org,
      registrationNumber: reg,
      operatorRegistrationId: 'reg-' + reg,
      material: material,
      previousAccreditationYear: 2025,
      complianceIssuesReported: 0,
      operatorEmail: 'perf.test@example.com',
      siteAddressPostcode: postcode,
      nation: nation,
      applicationReference: 'RA-PERF-' + reg
    }
  };
}

db.workItems.insertMany([
  $ITEMS_JS
]);

print('Inserted $TOTAL_COUNT work items.');
"

echo ""
echo "CSVs written to $DATA_DIR/"
echo "  cms-approve.csv  → $APPROVE_COUNT rows"
echo "  cms-refuse.csv   → $REFUSE_COUNT rows"
echo "  cms-query.csv    → $QUERY_COUNT rows"
echo ""
echo "Run the JMeter test with: LOCAL=true ./entrypoint.sh case-management"
