#!/usr/bin/env bash
# Regenerate the CSV data files for scenarios/accreditation-reprocessor-journey.jmx
# and scenarios/accreditation-exporter-journey.jmx's PerfTest Records fixture
# pools.
#
# The /operator test-harness page lists 100 Reprocessor fixtures (org
# 60001-60100) and 100 Exporter fixtures (org 61001-61100), linked at year
# 2027. But the landing page (GET /operator-accreditation/{org}/{registration}
# /{material}/{year}) gets-or-creates an application keyed on (registrationId,
# materialType, year), and any year works -- the same mechanism
# seed-operator-journey-csvs.sh relies on. Verified on perf-test 2026-10-07:
# org 60001 (already Submitted at 2027) and org 61003 ran the full reprocessor
# and exporter journeys at a synthetic year with 0 errors, overseas sites and
# BES evidence included.
#
# So each run gets a fresh block of synthetic years, and every row is a
# brand-new application: the pools no longer run out. Years come from
# 8100-9999, above the 3000-8019 range seed-operator-journey-csvs.sh uses
# (it also uses orgs 61001/61002), so the two schemes can never share an
# application. YEARS_PER_RUN years x 100 orgs gives the row count per pool,
# which caps the users a single run can drive.
#
# Override ACCREDITATION_YEAR_BASE to pin the block (e.g. to rerun against the
# applications a previous run created).
#
# Usage: ./jmeter/scripts/generate-accreditation-fixtures.sh
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

def fixture_rows(org_base, count=100):
    rows = []
    for year in years:
        for i in range(1, count + 1):
            org_id = org_base + i
            registration_id = f"aaa{org_id:021d}"
            material = materials[(i - 1) % len(materials)]
            rows.append((org_id, registration_id, material, year))
    return rows

def write_csv(name, rows):
    random.shuffle(rows)
    path = f"{data_dir}/{name}"
    with open(path, "w") as f:
        f.write("orgId,registrationId,material,year\n")
        for org_id, registration_id, material, year in rows:
            f.write(f"{org_id},{registration_id},{material},{year}\n")
    print(f"{name} -> {len(rows)} rows, years {years[0]}-{years[-1]}, shuffled")

write_csv("accreditation-reprocessor-fixtures.csv", fixture_rows(60000))
write_csv("accreditation-exporter-fixtures.csv", fixture_rows(61000))
PYEOF

echo ""
echo "Run with: ./entrypoint.sh accreditation-reprocessor"
echo "      or: ./entrypoint.sh accreditation-exporter"
