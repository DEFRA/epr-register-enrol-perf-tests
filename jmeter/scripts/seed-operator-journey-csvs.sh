#!/usr/bin/env bash
# Regenerate the CSV data files for scenarios/operator-journey-reprocessor-exporter.jmx.
#
# The landing page (GET /operator-accreditation/{org}/{registration}/{material}/{year})
# gets-or-creates an application keyed on (registrationId, materialType, year) --
# any year works, not just the ones listed on the /operator test-harness page --
# so each run picks a fresh year range (based on the current time) to guarantee
# every row is a brand-new application. Re-running against the SAME rows would
# hit already-Submitted/Withdrawn applications and fail (the app correctly
# rejects re-submitting or re-withdrawing).
#
# Usage: ./jmeter/scripts/seed-operator-journey-csvs.sh
#
# Row counts are generous (100 submit / 20 withdraw per operator type) so the
# same CSVs cover any --J*_users value up to that -- unused rows are simply
# never read (CSVDataSet recycle=false/stopThread=true).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$REPO_ROOT/jmeter/data"
mkdir -p "$DATA_DIR"

python3 - "$DATA_DIR" <<'PYEOF'
import sys, time

data_dir = sys.argv[1]
materials = ["Aluminium", "Fibre", "Glass", "Paper", "Plastic", "Steel", "Wood"]

# Fresh, collision-free base each run: a synthetic far-future year block seeded
# from the current time so back-to-back runs don't reuse the same applications.
base_year = 3000 + (int(time.time()) % 5000)
years = list(range(base_year, base_year + 20))  # 20 years * 7 materials = 140 combos

combos = [(m, y) for y in years for m in materials]

submit = combos[:100]
withdraw = combos[100:120]

def write_csv(name, rows):
    path = f"{data_dir}/{name}"
    with open(path, "w") as f:
        f.write("material,year\n")
        for m, y in rows:
            f.write(f"{m},{y}\n")
    print(f"  {name} -> {len(rows)} rows ({rows[0][0]} {rows[0][1]} .. {rows[-1][0]} {rows[-1][1]})")

print(f"Generating operator-journey CSVs (base_year={base_year}) ...")
write_csv("operator-journey-reprocessor-submit.csv", submit)
write_csv("operator-journey-exporter-submit.csv", submit)
write_csv("operator-journey-reprocessor-withdraw.csv", withdraw)
write_csv("operator-journey-exporter-withdraw.csv", withdraw)
PYEOF

echo ""
echo "Run with: ./entrypoint.sh operator-bulk"
echo "  (override REPROCESSOR_SUBMIT_USERS / EXPORTER_SUBMIT_USERS / REPROCESSOR_WITHDRAW_USERS /"
echo "   EXPORTER_WITHDRAW_USERS / RAMP_TIME env vars to change the load profile)"
