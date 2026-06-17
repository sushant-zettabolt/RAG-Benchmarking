#!/usr/bin/env bash
# Run A/B benchmark sequentially for all 6 models.
# Updates CHAT_MODEL_PATH in .env before each run, then copies reports to reports/.
set -euo pipefail
cd "$(dirname "$0")"

log() { echo "[batch $(date '+%H:%M:%S')] $*"; }
die() { echo "[batch] ERROR: $*" >&2; exit 1; }
mkdir -p reports

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

# All 6 models.
run_model "llama31-8b-bf16"    "/models/Llama-3.1-8B-Instruct-BF16.gguf"
run_model "gemma4-4b-bf16"     "/models/Gemma-4-E2B-It-4.6B-BF16.gguf"
run_model "mixtral-8x7b-bf16"  "/models/Mixtral-8x7B-Instruct-v0.1-BF16.gguf"
run_model "gpt-oss-20b-bf16"   "/models/gpt-oss-20B-BF16.gguf"
run_model "mixtral-8x7b-q8"    "/models/Q8_0_models/Mixtral-8x7B-Instruct-v0.1-Q8_0.gguf"
run_model "llama31-8b-q8"      "/models/Q8_0_models/Llama-3.1-8B-Instruct-q8_0.gguf"

log "🏁 All models complete. Reports in reports/"
