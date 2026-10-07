#!/usr/bin/env bash
# Regenerate the CSV data file for scenarios/operator-accreditation-journey.jmx's
# PerfTest Records fixture pool.
#
# The /operator test-harness page lists 100 Reprocessor fixtures (org
# 60001-60100) and 100 Exporter fixtures (org 61001-61100), linked at year
# 2027. The landing page gets-or-creates an application keyed on
# (registrationId, materialType, year) and any year works, so each run gets a
# fresh block of synthetic years and every row is a brand-new application --
# see generate-accreditation-fixtures.sh for the verification and why years
# come from 8100-9999. Override ACCREDITATION_YEAR_BASE to pin the block.
#
# Usage: ./jmeter/scripts/generate-operator-accreditation-fixtures.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$REPO_ROOT/jmeter/data"
mkdir -p "$DATA_DIR"

python3 - "$DATA_DIR" "${ACCREDITATION_YEAR_BASE:-}" <<'PYEOF'
import sys, random, time

data_dir, year_base_override = sys.argv[1], sys.argv[2]
materials = ["Plastic", "Glass", "Steel", "Aluminium", "Paper", "Wood", "Fibre"]
YEARS_PER_RUN = 3

base_year = int(year_base_override) if year_base_override else 8100 + int(time.time()) % 1890
years = list(range(base_year, base_year + YEARS_PER_RUN))

def fixture_rows(org_base, fixture_type, count=100):
    rows = []
    for year in years:
        for i in range(1, count + 1):
            org_id = org_base + i
            registration_id = f"aaa{org_id:021d}"
            material = materials[(i - 1) % len(materials)]
            rows.append((org_id, registration_id, material, fixture_type, year))
    return rows

rows = fixture_rows(60000, "Reprocessor") + fixture_rows(61000, "Exporter")
random.shuffle(rows)

path = f"{data_dir}/operator-accreditation-fixtures.csv"
with open(path, "w") as f:
    f.write("orgId,registrationId,material,type,year\n")
    for org_id, registration_id, material, fixture_type, year in rows:
        f.write(f"{org_id},{registration_id},{material},{fixture_type},{year}\n")

reprocessor_count = sum(1 for r in rows if r[3] == "Reprocessor")
exporter_count = sum(1 for r in rows if r[3] == "Exporter")
print(f"operator-accreditation-fixtures.csv -> {len(rows)} rows "
      f"({reprocessor_count} Reprocessor, {exporter_count} Exporter), "
      f"years {years[0]}-{years[-1]}, shuffled")
PYEOF

echo ""
echo "Run with: USERS=100 ./entrypoint.sh operator-accreditation"
