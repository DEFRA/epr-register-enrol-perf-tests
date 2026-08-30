#!/usr/bin/env bash
# Regenerate the CSV data files for scenarios/accreditation-reprocessor-journey.jmx
# and scenarios/accreditation-exporter-journey.jmx's PerfTest Records fixture
# pools.
#
# The /operator test-harness page lists 100 Reprocessor fixtures (org
# 60001-60100) and 100 Exporter fixtures (org 61001-61100), each with a fixed
# material and year (2027) already baked into its URL -- a static,
# pre-existing pool, unlike operator-journey-reprocessor-exporter.jmx's own
# CSVs (seed-operator-journey-csvs.sh), which generate brand-new applications
# each run via a synthetic year. These fixtures can each only be submitted
# ONCE ever (the app correctly rejects re-submitting an already-Submitted
# application) -- there is no "generate fresh ones" option here, since the
# org/registration/material/year combination IS the fixture, fixed by the
# harness page itself. Re-running this suite against the same fixtures a
# second time will start failing once they're all consumed; that's expected,
# not a bug, and outside what this script can work around.
#
# This script only shuffles the row order within each pool (so which fixture
# each thread number lands on varies run to run) and writes the two CSVs --
# no live HTTP calls needed, since org IDs/registrationIds/materials are
# deterministic from the harness page's own listing (verified against
# http://localhost:3000/operator).
#
# Usage: ./jmeter/scripts/generate-accreditation-fixtures.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$REPO_ROOT/jmeter/data"
mkdir -p "$DATA_DIR"

python3 - "$DATA_DIR" <<'PYEOF'
import sys, random

data_dir = sys.argv[1]
materials = ["Plastic", "Glass", "Steel", "Aluminium", "Paper", "Wood", "Fibre"]

def fixture_rows(org_base, count=100):
    rows = []
    for i in range(1, count + 1):
        org_id = org_base + i
        registration_id = f"aaa{org_id:021d}"
        material = materials[(i - 1) % len(materials)]
        rows.append((org_id, registration_id, material))
    return rows

def write_csv(name, rows):
    random.shuffle(rows)
    path = f"{data_dir}/{name}"
    with open(path, "w") as f:
        f.write("orgId,registrationId,material\n")
        for org_id, registration_id, material in rows:
            f.write(f"{org_id},{registration_id},{material}\n")
    print(f"{name} -> {len(rows)} rows, shuffled")

write_csv("accreditation-reprocessor-fixtures.csv", fixture_rows(60000))
write_csv("accreditation-exporter-fixtures.csv", fixture_rows(61000))
PYEOF

echo ""
echo "Run with: ./entrypoint.sh accreditation-reprocessor"
echo "      or: ./entrypoint.sh accreditation-exporter"
echo "  (each pool's 100 fixtures are one-shot -- once consumed by a run, re-running"
echo "   against the same fixtures will fail; regenerate only gives a fresh SHUFFLE"
echo "   of the same 100 per pool, not new fixtures)"
