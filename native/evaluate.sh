#!/usr/bin/env bash
# Run the eval queries through AnythingLLM + LLM judge. Writes results/metrics to
# native/data/results/ (JOB env tags the output, e.g. JOB=baseline -> metrics_baseline).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$NATIVE/services.sh"
is_running anythingllm || die "stack not up — run: native/up.sh"
[ -f "$DATA/eval.jsonl" ] || die "no eval set — run: native/ingest.sh first"
export JOB="${JOB:-}"
log "evaluating (JOB='${JOB:-<none>}') ..."
run_harness evaluate.py
