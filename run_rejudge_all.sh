#!/usr/bin/env bash
# Re-run LLM-as-a-judge on all existing model reports.
# Copies each model's metrics into data/results/, runs the judge inside the
# harness container, then copies the updated files back to reports/.
set -euo pipefail
cd "$(dirname "$0")"

DC="docker compose"
log() { echo "[rejudge $(date '+%H:%M:%S')] $*"; }

MODELS=(
    llama31-8b-bf16
    gemma4-4b-bf16
    mixtral-8x7b-bf16
    gpt-oss-20b-bf16
    mixtral-8x7b-q8
    llama31-8b-q8
)

mkdir -p reports

for slug in "${MODELS[@]}"; do
    bl="reports/metrics_${slug}_baseline.jsonl"
    zn="reports/metrics_${slug}_zendnn.jsonl"
    if [ ! -f "$bl" ] || [ ! -f "$zn" ]; then
        log "SKIP $slug (metrics files not found)"
        continue
    fi
    log "══════════════ $slug ══════════════"
    cp "$bl" data/results/metrics_baseline.jsonl
    cp "$zn" data/results/metrics_zendnn.jsonl

    $DC run --rm harness python rejudge.py

    cp data/results/metrics_baseline.jsonl "$bl"
    cp data/results/metrics_zendnn.jsonl   "$zn"
    cp data/results/report_ab.md           "reports/report_ab_${slug}.md"
    cp data/results/report_ab.json         "reports/report_ab_${slug}.json"
    log "✅ $slug done"
done

log "🏁 All models re-judged. Reports in reports/"
