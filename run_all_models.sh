#!/usr/bin/env bash
# Run A/B benchmark sequentially for all models.
# Updates CHAT_MODEL_PATH in .env before each run, then copies reports to reports/.
#
#   ./run_all_models.sh           — run all 6 models
#   ./run_all_models.sh --test    — run only llama31-8b-q8 (quick smoke-test)
set -euo pipefail
cd "$(dirname "$0")"

log() { echo "[batch $(date '+%H:%M:%S')] $*"; }
die() { echo "[batch] ERROR: $*" >&2; exit 1; }

TEST_ONLY=0
[ "${1:-}" = "--test" ] && TEST_ONLY=1

patch_model() {  # path
    sed -i "s|^CHAT_MODEL_PATH=.*|CHAT_MODEL_PATH=$1|" .env
}

run_model() {  # slug container_model_path
    local slug="$1" path="$2"
    log "══════════════ MODEL: $slug ══════════════"
    patch_model "$path"
    bash run_ab.sh
    cp data/results/report_ab.md     "reports/report_ab_${slug}.md"
    cp data/results/report_ab.json   "reports/report_ab_${slug}.json"
    cp data/results/metrics_baseline.jsonl "reports/metrics_${slug}_baseline.jsonl"
    cp data/results/metrics_zendnn.jsonl   "reports/metrics_${slug}_zendnn.jsonl"
    log "✅ $slug done — report saved to reports/report_ab_${slug}.md"
}

if [ "$TEST_ONLY" = "1" ]; then
    log "── test mode: running llama31-8b-q8 only ──"
    run_model "llama31-8b-q8" "/models/Q8_0_models/Llama-3.1-8B-Instruct-q8_0.gguf"
    log "🏁 Test run complete. Report in reports/"
    exit 0
fi

run_model "llama31-8b-q8" "/models/Q8_0_models/Llama-3.1-8B-Instruct-q8_0.gguf"

log "🏁 All models complete. Reports in reports/"
