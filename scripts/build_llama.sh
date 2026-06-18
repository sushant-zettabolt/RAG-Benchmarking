#!/usr/bin/env bash
# Build the two A/B benchmark backends as Docker images, from fresh PUBLIC
# llama.cpp source — NO host build trees, NO machine-specific paths, nothing
# proprietary. Both images compile from the SAME llama.cpp commit so the A/B is
# fair (HEAD is resolved once and pinned into both builds via LLAMA_CPP_REF).
#
# Produces two images (see docker/llama/Dockerfile):
#   nqrag-llama:baseline   ggml-cpu only            (GGML_ZENDNN=OFF)
#   nqrag-llama:zendnn     ggml-cpu + ggml-zendnn    (GGML_ZENDNN=ON)
#
# ZenDNN is handled entirely by llama.cpp's own CMake: with GGML_ZENDNN=ON and no
# ZENDNN_ROOT, ggml/src/ggml-zendnn/CMakeLists.txt ExternalProject_Add's the
# public github.com/amd/ZenDNN at a pinned tag, builds it, and links it — so the
# build fetches everything it needs from public sources.
#
# Usage:
#   scripts/build_llama.sh             # build both images (cached layers reused)
#   scripts/build_llama.sh --no-cache  # force a from-scratch rebuild of both
#
# run_ab.sh then swaps the llama-chat IMAGE per job (baseline <-> zendnn); the
# base stack runs the baseline image for both chat and embed.
set -euo pipefail
cd "$(dirname "$0")/.."           # repo root (rag_pipeline_bench)

env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*//' | xargs)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
log()  { echo "[build] $*"; }
die()  { echo "[build] ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null || die "docker not found"
command -v git    >/dev/null || die "git not found"

NO_CACHE=""; [ "${1:-}" = "--no-cache" ] && NO_CACHE="--no-cache"

CTX="docker/llama"
REPO="$(env_get LLAMA_CPP_REPO https://github.com/ggml-org/llama.cpp)"
BASELINE_IMAGE="$(env_get LLAMA_BASELINE_IMAGE nqrag-llama:baseline)"
ZENDNN_IMAGE="$(env_get LLAMA_ZENDNN_IMAGE nqrag-llama:zendnn)"

# Resolve the repo's current HEAD once and pin BOTH builds to it, so baseline and
# zendnn are the identical commit even though it's "latest at build time". An
# explicit LLAMA_CPP_REF in .env wins. Empty + unreachable remote => unpinned
# (each build clones HEAD independently — fine for a single non-A/B build).
REF="$(env_get LLAMA_CPP_REF "")"
if [ -z "$REF" ]; then
    REF="$(git ls-remote "$REPO" HEAD 2>/dev/null | awk '{print $1}' | head -1 || true)"
    [ -n "$REF" ] && log "pinning both images to llama.cpp HEAD $REF (fair A/B)" \
                  || log "WARNING: could not resolve $REPO HEAD — builds are unpinned (may differ)"
fi

build() {  # tag GGML_ZENDNN
    local tag="$1" zen="$2"
    log "building $tag (GGML_ZENDNN=$zen) from $REPO ${REF:+@ $REF} ..."
    docker build $NO_CACHE \
        --build-arg "GGML_ZENDNN=$zen" \
        --build-arg "LLAMA_CPP_REPO=$REPO" \
        --build-arg "LLAMA_CPP_REF=$REF" \
        -t "$tag" "$CTX"
}

build "$BASELINE_IMAGE" OFF
build "$ZENDNN_IMAGE"   ON

log "done."
log "  baseline : $BASELINE_IMAGE"
log "  zendnn   : $ZENDNN_IMAGE"
log "  (run_ab.sh swaps the llama-chat image between these two per job)"
