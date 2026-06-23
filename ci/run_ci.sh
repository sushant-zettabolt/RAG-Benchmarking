#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ZenDNN regression CI — one self-contained run.
#
# This is the whole pipeline that Jenkins fires on a schedule (and that you can
# run by hand). It exists as a plain script on purpose: the Jenkins job is a thin
# wrapper around it, so the CI logic is testable without Jenkins.
#
# Steps:
#   1. (optional) FRESH PULL: rebuild the baseline + ZenDNN llama.cpp images
#      from scratch (--no-cache re-clones latest llama.cpp HEAD and re-fetches
#      public ZenDNN), so we track upstream as those open-source repos move.
#   2. Make sure documents are ingested (reuse the existing corpus — do NOT
#      re-ingest, so the corpus is identical across time and the only thing that
#      changed week-to-week is the rebuilt backend).
#   3. Run the A/B (baseline vs zendnn) over EVAL_LIMIT queries via run_ab.sh.
#   4. Compare THIS run's ZenDNN numbers against the previous ZenDNN run and emit
#      a degrade / neutral / speedup verdict (strictly zendnn→zendnn over time).
#
# It writes everything under ci/runs/ + ci/history/ and NEVER touches reports/
# (the user's hand-curated results) or data/results (left as run_ab.sh wrote it).
#
# Env knobs (all optional):
#   FRESH_BUILD=1|0          rebuild images no-cache first (default 1)
#   CI_EVAL_LIMIT=N          queries per backend (default 10)  ← "EVAL_N 10"
#   CI_CMP_THRESHOLD_PCT=5   % change that counts as speedup/degrade (default 5)
#   CI_FAIL_ON_DEGRADE=1|0   exit non-zero on DEGRADE (default 0 → Jenkins marks UNSTABLE)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."                      # repo root (rag_pipeline_bench)
ROOT="$(pwd)"

log() { echo "[ci $(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "[ci] ERROR: $*" >&2; exit 1; }

FRESH_BUILD="${FRESH_BUILD:-1}"
CI_EVAL_LIMIT="${CI_EVAL_LIMIT:-10}"
CI_CMP_THRESHOLD_PCT="${CI_CMP_THRESHOLD_PCT:-5}"
CI_FAIL_ON_DEGRADE="${CI_FAIL_ON_DEGRADE:-0}"
TS="$(date '+%Y%m%d_%H%M%S')"
RUN_DIR="$ROOT/ci/runs/$TS"
HIST_DIR="$ROOT/ci/history"
mkdir -p "$RUN_DIR" "$HIST_DIR"

env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*//' | xargs)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
ZENDNN_IMAGE="$(env_get LLAMA_ZENDNN_IMAGE nqrag-llama:zendnn)"

[ -f .env ] || die "no .env — run ./setup.sh first"
command -v docker >/dev/null || die "docker not found in PATH"

log "════════════ ZenDNN regression CI — run $TS ════════════"
log "FRESH_BUILD=$FRESH_BUILD  EVAL_LIMIT=$CI_EVAL_LIMIT  threshold=±${CI_CMP_THRESHOLD_PCT}%"

# ── 1. fresh pull + rebuild ──────────────────────────────────────────────────
if [ "$FRESH_BUILD" = "1" ] || [ "$FRESH_BUILD" = "true" ]; then
    log "fresh pull: rebuilding llama.cpp baseline + ZenDNN images (--no-cache, latest HEAD) ..."
    ./scripts/build_llama.sh --no-cache 2>&1 | tee "$RUN_DIR/build.log"
else
    log "FRESH_BUILD off — reusing existing images (no rebuild)."
fi

# Record which llama.cpp commit the ZenDNN image was actually built from.
BUILD_SHA="$(docker run --rm "$ZENDNN_IMAGE" cat /app/llama_cpp_built_sha.txt 2>/dev/null | tr -d '[:space:]' || true)"
log "zendnn image $ZENDNN_IMAGE built from llama.cpp commit: ${BUILD_SHA:-unknown}"

# ── 2. ensure ingest (reuse existing corpus; only ingest if truly absent) ────
if [ ! -f data/ingest_metadata.json ]; then
    log "no ingested corpus found — running ingest once (this is the slow path) ..."
    make ingest
else
    log "reusing existing ingested corpus (data/ingest_metadata.json present) — comparable across time."
fi

# ── 3. run the A/B over CI_EVAL_LIMIT queries ────────────────────────────────
# EVAL_LIMIT caps queries actually run against the existing corpus WITHOUT
# re-ingesting (EVAL_N would only matter if we re-ingested). Exporting these
# overrides the .env values via compose's shell-env precedence, for THIS run only
# — the user's .env on disk is left untouched.
log "running A/B (baseline vs zendnn), $CI_EVAL_LIMIT queries each ..."
export EVAL_LIMIT="$CI_EVAL_LIMIT"
export EVAL_N="$CI_EVAL_LIMIT"
AB_KEEP_RUNNING=0 bash run_ab.sh 2>&1 | tee "$RUN_DIR/run_ab.log"

[ -f data/results/report_ab.json ] || die "run_ab.sh produced no report_ab.json"

# Snapshot the report into the run dir (do NOT touch reports/ or overwrite anything).
cp -f data/results/report_ab.json "$RUN_DIR/report_ab.json"
cp -f data/results/report_ab.md   "$RUN_DIR/report_ab.md" 2>/dev/null || true

# ── 4. compare this ZenDNN run vs the previous ZenDNN run ────────────────────
log "comparing ZenDNN numbers against previous run ..."
FAIL_FLAG=""; [ "$CI_FAIL_ON_DEGRADE" = "1" ] && FAIL_FLAG="--fail-on-degrade"
CMP_RC=0
CI_RUN_TS="$TS" EVAL_N="$CI_EVAL_LIMIT" \
python3 ci/compare_zendnn.py \
    --report data/results/report_ab.json \
    --history "$HIST_DIR" \
    --out "$RUN_DIR" \
    --threshold "$CI_CMP_THRESHOLD_PCT" \
    --timestamp "$TS" \
    --build-sha "${BUILD_SHA:-}" \
    --eval-n "$CI_EVAL_LIMIT" \
    $FAIL_FLAG || CMP_RC=$?

# ── publish: refresh ci/runs/latest as a real dir (Jenkins archives this) ────
rm -rf "$ROOT/ci/runs/latest"
mkdir -p "$ROOT/ci/runs/latest"
cp -f "$RUN_DIR"/* "$ROOT/ci/runs/latest/" 2>/dev/null || true

# If we ran as root (Jenkins-over-Docker), hand the CI artifacts back to the host user.
if [ "$(id -u)" = "0" ]; then
    chown -R "${HOST_UID:-1002}:${HOST_GID:-1002}" "$ROOT/ci" 2>/dev/null || true
fi

echo
log "verdict: $(cat "$RUN_DIR/verdict.txt" 2>/dev/null || echo '?')"
log "artifacts: $RUN_DIR  (and ci/runs/latest)"
exit "$CMP_RC"
