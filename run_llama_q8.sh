#!/usr/bin/env bash
# A/B benchmark for llama31-8b-q8 only.
# Use this for judge testing, config validation, or quick iteration.
#   ./run_llama_q8.sh
set -euo pipefail
cd "$(dirname "$0")"

log() { echo "[batch $(date '+%H:%M:%S')] $*"; }

sed -i "s|^CHAT_MODEL_PATH=.*|CHAT_MODEL_PATH=/models/Q8_0_models/Llama-3.1-8B-Instruct-q8_0.gguf|" .env

log "══════════════ MODEL: llama31-8b-q8 ══════════════"
bash run_ab.sh
cp data/results/report_ab.md     reports/report_ab_llama31-8b-q8.md
cp data/results/report_ab.json   reports/report_ab_llama31-8b-q8.json
cp data/results/metrics_baseline.jsonl reports/metrics_llama31-8b-q8_baseline.jsonl
cp data/results/metrics_zendnn.jsonl   reports/metrics_llama31-8b-q8_zendnn.jsonl

log "🏁 Done. Report: reports/report_ab_llama31-8b-q8.md"
