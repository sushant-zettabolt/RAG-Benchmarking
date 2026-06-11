#!/usr/bin/env bash
# Run the benchmark and generate the report — single entry point.
#   ./run_bench.sh            A/B: baseline job then zendnn job, then report
#   ./run_bench.sh baseline   one job only
#   ./run_bench.sh zendnn
# Knobs come from config.env (WARMUP, BENCH_QUERIES, DROP_FIRST, ...).
# STAMP can be preset in the environment to append to an existing run.
set -eo pipefail
. "$(dirname "$0")/scripts/lib.sh"

MODE="${1:-ab}"
case "$MODE" in
    ab)       JOBS="baseline zendnn" ;;
    baseline) JOBS="baseline" ;;
    zendnn)   JOBS="zendnn" ;;
    *) die "usage: run_bench.sh [ab|baseline|zendnn]" ;;
esac

STAMP="${STAMP:-$(date +%Y%m%d_%H%M%S)}"
export STAMP
log "STAMP=$STAMP  jobs: $JOBS"

[ -n "$ALLM_KEY" ] || die "ALLM_KEY empty — run ./setup.sh first"
[ -f "$BASE/data/queries.jsonl" ] || die "data/queries.jsonl missing — run ./setup.sh first"

# shared services (litellm needs live backends for its health check, so it is
# only started inside the per-job loop after embed+chat are up)
ensure_shared() {
    curl -s -m 5 "http://127.0.0.1:$LITELLM_PORT/health/liveliness" >/dev/null 2>&1 \
        || "$BASE/scripts/start_litellm.sh"
    curl -s -m 5 "http://127.0.0.1:$PROM_PORT/-/ready" >/dev/null 2>&1 \
        || "$BASE/scripts/start_prometheus.sh"
    curl -s -m 5 "$ALLM_URL/api/ping" >/dev/null 2>&1 \
        || die "anythingllm not running — run ./setup.sh (or ./start_services.sh) first"
}

for JOB in $JOBS; do
    echo
    log "=== job: $JOB ==="
    "$BASE/scripts/start_embed.sh" "$JOB" "$RESULTS_DIR/embed_${JOB}_${STAMP}.log"
    "$BASE/scripts/start_chat.sh"  "$JOB" "$RESULTS_DIR/chat_${JOB}_${STAMP}.log"
    ensure_shared

    # contamination / engagement gates
    if [ "$JOB" = "baseline" ]; then
        if grep -qi zendnn "$RESULTS_DIR/chat_${JOB}_${STAMP}.log"; then
            die "baseline chat log mentions zendnn — CONTAMINATED"
        fi
        log "baseline clean"
    else
        grep -qi zendnn "$RESULTS_DIR/chat_${JOB}_${STAMP}.log" || die "zendnn chat log has no zendnn marker — NOT ENGAGED"
        log "zendnn engaged"
    fi

    QN_ENV=()
    if [ -n "$BENCH_QUERIES" ]; then QN_ENV=(QUERIES_N="$BENCH_QUERIES"); fi
    env BASE="$BASE" ALLM_KEY="$ALLM_KEY" SLUG="$SLUG" ALLM_URL="$ALLM_URL" PROM_URL="$PROM_URL" \
        WARMUP="$WARMUP" STAMP="$STAMP" "${QN_ENV[@]}" \
        python3 "$BASE/harness.py" "$JOB"
done

echo
log "=== report ==="
env BASE="$BASE" STAMP="$STAMP" DROP_FIRST="$DROP_FIRST" python3 "$BASE/report.py"
echo
log "report: $RESULTS_DIR/REPORT_${STAMP}.md"
log "regenerate any time with:  BASE=$BASE STAMP=$STAMP DROP_FIRST=$DROP_FIRST python3 report.py"
