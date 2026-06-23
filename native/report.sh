#!/usr/bin/env bash
# Generate the single-run report (native/data/results/report.md + report.json).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$NATIVE/services.sh"
log "generating report ..."
run_harness report.py
log "report → ${DATA#$BASE/}/results/report.md"
