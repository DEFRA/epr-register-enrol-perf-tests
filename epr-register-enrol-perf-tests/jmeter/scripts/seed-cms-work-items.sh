#!/usr/bin/env bash
# Seed 10 re-accreditation work items into the case-management MongoDB and
# write the four JMeter CSV data files.
#
# Usage: ./jmeter/scripts/seed-cms-work-items.sh [--mongo-container <name>]
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

# ---- generate 10 UUIDs (macOS uuidgen; lowercase) --------------------------
gen() { uuidgen | tr '[:upper:]' '[:lower:]'; }

A1=$(gen); A2=$(gen); A3=$(gen)    # approve: England, Scotland, Wales
R1=$(gen); R2=$(gen)               # refuse: NI, England
Q1=$(gen); Q2=$(gen)               # query: Wales, Scotland
W1=$(gen); W2=$(gen); W3=$(gen)   # withdraw: England(submitted), NI(duly-made), Scotland(assessment)

echo "Seeding 10 work items into $MONGO_CONTAINER/$MONGO_DB …"

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
  // Approve journey
  item('$A1', 'Perf Approve England Ltd',   'plastic',   'SW1A 1AA', 'England',         'PA001'),
  item('$A2', 'Perf Approve Scotland Ltd',  'steel',     'EH1 1YZ',  'Scotland',         'PA002'),
  item('$A3', 'Perf Approve Wales Ltd',     'paper',     'CF10 1AB', 'Wales',            'PA003'),
  // Refuse journey
  item('$R1', 'Perf Refuse NI Ltd',         'glass',     'BT1 1AA',  'NorthernIreland',  'PR001'),
  item('$R2', 'Perf Refuse England Ltd',    'aluminium', 'M1 1AE',   'England',          'PR002'),
  // Query journey
  item('$Q1', 'Perf Query Wales Ltd',       'wood',      'SA1 1AA',  'Wales',            'PQ001'),
  item('$Q2', 'Perf Query Scotland Ltd',    'plastic',   'G1 1AA',   'Scotland',         'PQ002'),
  // Withdraw journey
  item('$W1', 'Perf Withdraw England Ltd',  'steel',     'BS1 4DJ',  'England',          'PW001'),
  item('$W2', 'Perf Withdraw NI Ltd',       'paper',     'BT48 6HH', 'NorthernIreland',  'PW002'),
  item('$W3', 'Perf Withdraw Scotland Ltd', 'glass',     'AB10 1AB', 'Scotland',         'PW003'),
]);

print('Inserted 10 work items.');
"

# ---- write CSV data files ---------------------------------------------------
mkdir -p "$DATA_DIR"

cat > "$DATA_DIR/cms-approve.csv" <<EOF
workItemId,nation,material
$A1,England,plastic
$A2,Scotland,steel
$A3,Wales,paper
EOF

cat > "$DATA_DIR/cms-refuse.csv" <<EOF
workItemId,nation,material
$R1,NorthernIreland,glass
$R2,England,aluminium
EOF

cat > "$DATA_DIR/cms-query.csv" <<EOF
workItemId,nation,material
$Q1,Wales,wood
$Q2,Scotland,plastic
EOF

cat > "$DATA_DIR/cms-withdraw-submitted.csv" <<EOF
workItemId,nation,material
$W1,England,steel
EOF

cat > "$DATA_DIR/cms-withdraw-duly-made.csv" <<EOF
workItemId,nation,material
$W2,NorthernIreland,paper
EOF

cat > "$DATA_DIR/cms-withdraw-assessment.csv" <<EOF
workItemId,nation,material
$W3,Scotland,glass
EOF

echo ""
echo "CSVs written to $DATA_DIR/"
echo "  cms-approve.csv               → $A1 (England), $A2 (Scotland), $A3 (Wales)"
echo "  cms-refuse.csv                → $R1 (NI), $R2 (England)"
echo "  cms-query.csv                 → $Q1 (Wales), $Q2 (Scotland)"
echo "  cms-withdraw-submitted.csv    → $W1 (England/submitted)"
echo "  cms-withdraw-duly-made.csv    → $W2 (NI/duly-made)"
echo "  cms-withdraw-assessment.csv   → $W3 (Scotland/assessment)"
echo ""
echo "Run the JMeter test with: CM_PORT=5001 ./run-baseline.sh case-management"
