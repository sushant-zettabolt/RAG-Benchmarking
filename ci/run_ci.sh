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
#   3. SWEEP every chat model in CHAT_MODELS_DIR: for each, run the full A/B
#      (baseline vs zendnn) over EVAL_LIMIT queries via run_ab.sh, merging the
#      per-question metrics (tagged with the model name) across all models.
#   4. Emit the four per-question comparison CSVs (ggml/zendnn × prev/curr), one
#      row per (model, question); plus a per-model aggregate verdict (no gate).
#
# Everything lives under CI_ARTIFACT_DIR (runs/, history/, reports/); it NEVER
# touches data/results (left as run_ab.sh wrote it). Point CI_ARTIFACT_DIR at a
# fresh dir to reset regression history.
#
# Env knobs:
#   CHAT_MODELS_DIR          REQUIRED — dir of chat GGUFs to sweep (no fallback)
#   CI_ARTIFACT_DIR          where all artifacts/history live (default <repo>/ci)
#   FRESH_BUILD=1|0          rebuild images no-cache first (default 1)
#   CI_EVAL_LIMIT=N          queries per backend per model (default 10)
#   CI_CMP_THRESHOLD_PCT=5   % change that counts as speedup/degrade (default 5)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."                      # repo root (rag_pipeline_bench)
ROOT="$(pwd)"

log() { echo "[ci $(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "[ci] ERROR: $*" >&2; exit 1; }

FRESH_BUILD="${FRESH_BUILD:-1}"
CI_EVAL_LIMIT="${CI_EVAL_LIMIT:-10}"
CI_CMP_THRESHOLD_PCT="${CI_CMP_THRESHOLD_PCT:-5}"
TS="$(date '+%Y%m%d_%H%M%S')"

[ -f .env ] || die "no .env — run ./setup.sh first"
command -v docker >/dev/null || die "docker not found in PATH"

env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*//' | xargs)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
ZENDNN_IMAGE="$(env_get LLAMA_ZENDNN_IMAGE nqrag-llama:zendnn)"

# ── artifact root ────────────────────────────────────────────────────────────
# ALL runs/, history/ and reports/ live under ONE configurable dir. Point
# CI_ARTIFACT_DIR at a fresh location to start regression history over — the
# next run finds no prev_run.json / zendnn_history there and begins from
# BASELINE, and (because this dir is bind-mounted into the Jenkins container)
# the Jenkins UI then reflects the new dir. Default: the in-repo ci/ tree.
ARTIFACT_DIR="$(env_get CI_ARTIFACT_DIR "$ROOT/ci")"
case "$ARTIFACT_DIR" in /*) ;; *) ARTIFACT_DIR="$ROOT/$ARTIFACT_DIR";; esac
RUN_DIR="$ARTIFACT_DIR/runs/$TS"
HIST_DIR="$ARTIFACT_DIR/history"
ARCHIVE="$ARTIFACT_DIR/reports"
LATEST="$ARTIFACT_DIR/runs/latest"
mkdir -p "$RUN_DIR" "$HIST_DIR" "$ARCHIVE"

# ── chat models to sweep (no fallbacks — error out if not supplied) ──────────
# CHAT_MODELS_DIR is a host directory of chat GGUFs (real files or symlinks);
# the CI evaluates EVERY *.gguf in it with the full baseline-vs-zendnn A/B.
MODELS_DIR="$(env_get MODELS_DIR '')"
CHAT_MODELS_DIR="$(env_get CHAT_MODELS_DIR '')"
[ -n "$MODELS_DIR" ]      || die "MODELS_DIR not set in .env"
[ -d "$MODELS_DIR" ]      || die "MODELS_DIR=$MODELS_DIR is not a directory (mount it into the Jenkins container)"
[ -n "$CHAT_MODELS_DIR" ] || die "CHAT_MODELS_DIR not set in .env — point it at the directory of chat GGUFs to sweep"
[ -d "$CHAT_MODELS_DIR" ] || die "CHAT_MODELS_DIR=$CHAT_MODELS_DIR is not a directory (mount it into the Jenkins container)"
shopt -s nullglob
MODEL_FILES=( "$CHAT_MODELS_DIR"/*.gguf )
shopt -u nullglob
[ ${#MODEL_FILES[@]} -gt 0 ] || die "no *.gguf found in CHAT_MODELS_DIR=$CHAT_MODELS_DIR"

# Map a host GGUF (dereferencing symlinks) to the in-container path llama-chat
# can open. llama-chat mounts MODELS_DIR at /models, so the resolved file must
# live under MODELS_DIR — otherwise the container could not see it. No guessing:
# anything outside MODELS_DIR is a hard error.
resolve_container_path() {  # host_path -> /models/<rel>
    local f="$1" real rel
    real="$(readlink -f "$f")" || die "cannot resolve symlink/path: $f"
    [ -f "$real" ] || die "model '$f' resolves to '$real', which does not exist"
    case "$real" in
        "$MODELS_DIR"/*) rel="${real#"$MODELS_DIR"/}"; printf '/models/%s\n' "$rel" ;;
        *) die "model '$f' resolves to '$real', OUTSIDE MODELS_DIR ($MODELS_DIR). llama-chat only mounts MODELS_DIR at /models — put the model (or its symlink target) under MODELS_DIR." ;;
    esac
}

# ── 0. prune orphan images left by previous (stale) container swaps ──────────
# Each fresh --no-cache rebuild and each baseline↔zendnn container swap can leave
# the OLD image untagged (dangling). `image prune` only removes *dangling*
# (untagged) images, so the live nqrag-llama:baseline/:zendnn/harness tags are
# never touched — this just reclaims the orphans so they don't accumulate run
# over run on a long-lived CI host.
log "pruning dangling (orphan) images left by previous runs ..."
docker image prune -f >/dev/null 2>&1 || log "WARN: image prune failed (non-fatal)"

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

# ── 3. multi-model A/B sweep ─────────────────────────────────────────────────
# For EACH chat model: swap llama-chat to it and run the full baseline-vs-zendnn
# A/B. The per-question metrics of every model are tagged with the model name and
# merged into ONE combined file per backend, so the four comparison CSVs below
# carry a row per (model, question). Containers stay up between models (only
# llama-chat is recreated per model) and are torn down after the last one.
# EVAL_LIMIT caps queries against the existing corpus WITHOUT re-ingesting; we
# export it for THIS run only (the .env on disk is untouched).
export EVAL_LIMIT="$CI_EVAL_LIMIT"
export EVAL_N="$CI_EVAL_LIMIT"

COMBINED_BASE="$RUN_DIR/metrics_baseline_${TS}.jsonl"
COMBINED_ZEN="$RUN_DIR/metrics_zendnn_${TS}.jsonl"
: > "$COMBINED_BASE"; : > "$COMBINED_ZEN"
VERDICT_MD="$RUN_DIR/verdict.md"
{ echo "# ZenDNN regression watch — per-model (run $TS)"; echo; } > "$VERDICT_MD"

MODEL_COUNT=${#MODEL_FILES[@]}
log "multi-model sweep: $MODEL_COUNT model(s) from $CHAT_MODELS_DIR, $CI_EVAL_LIMIT queries each ..."
IDX=0
for f in "${MODEL_FILES[@]}"; do
    IDX=$((IDX+1))
    MODEL_NAME="$(basename "${f%.gguf}")"
    CPATH="$(resolve_container_path "$f")"
    log "──────── model $IDX/$MODEL_COUNT: $MODEL_NAME  (→ $CPATH) ────────"

    # keep the stack up between models; tear down after the last one
    KEEP=1; [ "$IDX" = "$MODEL_COUNT" ] && KEEP=0
    CHAT_MODEL_PATH="$CPATH" AB_KEEP_RUNNING="$KEEP" \
        bash run_ab.sh 2>&1 | tee "$RUN_DIR/run_ab_${MODEL_NAME}.log"

    [ -f data/results/report_ab.json ] || die "run_ab.sh produced no report_ab.json for $MODEL_NAME"

    # per-model report snapshot (kept; never overwrites another model's)
    cp -f data/results/report_ab.json "$RUN_DIR/report_ab_${MODEL_NAME}_${TS}.json"
    cp -f data/results/report_ab.md   "$RUN_DIR/report_ab_${MODEL_NAME}_${TS}.md" 2>/dev/null || true

    # tag this model's per-question metrics and append to the combined files
    python3 ci/annotate_metrics.py --model "$MODEL_NAME" \
        --in data/results/metrics_baseline.jsonl --out "$COMBINED_BASE"
    python3 ci/annotate_metrics.py --model "$MODEL_NAME" \
        --in data/results/metrics_zendnn.jsonl   --out "$COMBINED_ZEN"

    # per-model aggregate watchdog (per-model history; informational — NO build gate)
    M_HIST="$HIST_DIR/per_model/$MODEL_NAME"; mkdir -p "$M_HIST"
    M_OUT="$RUN_DIR/.verdict_${MODEL_NAME}"; mkdir -p "$M_OUT"
    CI_RUN_TS="$TS" EVAL_N="$CI_EVAL_LIMIT" \
    python3 ci/compare_zendnn.py \
        --report data/results/report_ab.json \
        --history "$M_HIST" --out "$M_OUT" \
        --threshold "$CI_CMP_THRESHOLD_PCT" \
        --timestamp "$TS" --build-sha "${BUILD_SHA:-}" --eval-n "$CI_EVAL_LIMIT" \
        || log "WARN: aggregate watchdog failed for $MODEL_NAME (non-fatal)"
    cp -f "$M_OUT/verdict.md"  "$RUN_DIR/verdict_${MODEL_NAME}.md"  2>/dev/null || true
    cp -f "$M_OUT/verdict.txt" "$RUN_DIR/verdict_${MODEL_NAME}.txt" 2>/dev/null || true
    MV="$(cat "$M_OUT/verdict.txt" 2>/dev/null || echo '?')"
    { echo "## ${MODEL_NAME} — ${MV}"; echo; cat "$M_OUT/verdict.md" 2>/dev/null; echo; } >> "$VERDICT_MD"
    rm -rf "$M_OUT"
done

# combined one-line verdict.txt — informational only (per-model, NO build gate)
SUMMARY="${MODEL_COUNT} model(s):"
for f in "${MODEL_FILES[@]}"; do
    n="$(basename "${f%.gguf}")"
    v="$(awk '{print $1; exit}' "$RUN_DIR/verdict_${n}.txt" 2>/dev/null || echo '?')"
    SUMMARY="$SUMMARY ${n}=${v:-?}"
done
echo "$SUMMARY" > "$RUN_DIR/verdict.txt"

# ── 4. per-question comparison CSVs (4-way × all models) ─────────────────────
# Drills below the aggregate verdict: per (model, question) perf + accuracy,
# prev vs curr, with degrade/neutral/speedup tags. Reads the persistent prev-run
# pointer (which run is "previous"), then OVERWRITES it to point at THIS run.
log "building per-question comparison CSVs (4-way: ggml/zendnn × prev/curr, all models) ..."
PREV_PTR="$HIST_DIR/prev_run.json"
python3 ci/compare_rows.py \
    --curr-baseline "$COMBINED_BASE" \
    --curr-zendnn   "$COMBINED_ZEN" \
    --pointer "$PREV_PTR" \
    --run-dir "$RUN_DIR" \
    --timestamp "$TS" \
    --threshold "$CI_CMP_THRESHOLD_PCT" \
    --build-sha "${BUILD_SHA:-}" || log "WARN: per-question comparison failed (non-fatal)"

# ── 5. flat, timestamped archive of every run's artifacts + an index ─────────
# runs/<TS>/ already namespaces by time, but a flat archive with the timestamp IN
# the filename makes it trivial to collect/diff every run's reports and CSVs in
# one place without collisions.
VERDICT="$(cat "$RUN_DIR/verdict.txt" 2>/dev/null || echo '?')"
cp -f "$RUN_DIR"/report_ab_*_"${TS}".md   "$ARCHIVE/" 2>/dev/null || true
cp -f "$RUN_DIR"/report_ab_*_"${TS}".json "$ARCHIVE/" 2>/dev/null || true
cp -f "$RUN_DIR/verdict.md"               "$ARCHIVE/verdict_${TS}.md" 2>/dev/null || true
cp -f "$RUN_DIR"/cmp_*_"${TS}".csv        "$ARCHIVE/" 2>/dev/null || true
INDEX="$ARCHIVE/index.csv"
[ -f "$INDEX" ] || echo "timestamp,build_sha,n_models,verdict,comparison_glob" > "$INDEX"
echo "${TS},${BUILD_SHA:-},${MODEL_COUNT},\"${VERDICT}\",cmp_*_${TS}.csv" >> "$INDEX"
log "archived run $TS -> $ARCHIVE (4 comparison CSVs: cmp_*_${TS}.csv; index: $INDEX)"

# ── publish: refresh runs/latest as a real dir (Jenkins archives this) ───────
rm -rf "$LATEST"
mkdir -p "$LATEST"
cp -f "$RUN_DIR"/* "$LATEST/" 2>/dev/null || true

# If we ran as root (Jenkins-over-Docker), hand the artifacts back to the host
# user. Derive the owner from the repo dir itself (portable: no hard-coded uid)
# and fall back to HOST_UID/HOST_GID from the env if stat is unavailable.
# Scope the chown to the CI outputs we create (runs/, history/, reports/) — NOT
# the whole ARTIFACT_DIR, because Jenkins keeps its own home ($CI_ARTIFACT_DIR/
# jenkins_home) there as root-owned internal state; recursively chowning that on
# every run would churn it and fight the controller.
if [ "$(id -u)" = "0" ]; then
    OWNER="$(stat -c '%u:%g' "$ROOT" 2>/dev/null || echo "${HOST_UID:-}:${HOST_GID:-}")"
    if [ "$OWNER" != ":" ]; then
        for d in "$RUN_DIR" "$LATEST" "$HIST_DIR" "$ARCHIVE"; do
            [ -e "$d" ] && chown -R "$OWNER" "$d" 2>/dev/null || true
        done
    fi
fi

echo
log "verdict (per-model, no gate): $VERDICT"
log "artifacts: $RUN_DIR  (and $LATEST)"
