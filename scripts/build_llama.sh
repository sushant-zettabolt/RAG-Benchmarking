#!/usr/bin/env bash
# Build baseline and ZenDNN llama-server binaries from $LLAMA_SRC.
# usage: scripts/build_llama.sh            (skips builds whose binary exists)
#        FORCE_BUILD=1 scripts/build_llama.sh   (rebuild both)
set -eo pipefail
. "$(dirname "$0")/lib.sh"

if [ ! -d "$LLAMA_SRC" ]; then
    [ -n "$LLAMA_REPO" ] || die "LLAMA_SRC ($LLAMA_SRC) not found and LLAMA_REPO is empty.
Point LLAMA_SRC in config.env at your ZenDNN-enabled llama.cpp checkout,
or set LLAMA_REPO (+ optional LLAMA_REF) so it can be cloned."
    log "cloning $LLAMA_REPO -> $LLAMA_SRC"
    git clone "$LLAMA_REPO" "$LLAMA_SRC"
    if [ -n "$LLAMA_REF" ]; then git -C "$LLAMA_SRC" checkout "$LLAMA_REF"; fi
fi

CCACHE_ARG=""
command -v ccache >/dev/null && CCACHE_ARG="-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"

# ── baseline ────────────────────────────────────────────────────────────────
if [ -x "$LLAMA_BUILD_BASELINE/bin/llama-server" ] && [ "${FORCE_BUILD:-0}" != "1" ]; then
    log "baseline binary exists — skipping (FORCE_BUILD=1 to rebuild)"
else
    log "building baseline -> $LLAMA_BUILD_BASELINE"
    cmake -S "$LLAMA_SRC" -B "$LLAMA_BUILD_BASELINE" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=ON \
        -DLLAMA_CURL=OFF \
        $CCACHE_ARG
    cmake --build "$LLAMA_BUILD_BASELINE" --target llama-server -j"$(nproc)"
fi

# ── zendnn ──────────────────────────────────────────────────────────────────
if [ -z "$ZENDNN_ROOT" ]; then
    log "ZENDNN_ROOT empty — skipping ZenDNN build (baseline-only)"
    exit 0
fi
[ -d "$ZENDNN_ROOT" ] || die "ZENDNN_ROOT ($ZENDNN_ROOT) does not exist"

if [ -x "$LLAMA_BUILD_ZENDNN/bin/llama-server" ] && [ "${FORCE_BUILD:-0}" != "1" ]; then
    log "zendnn binary exists — skipping (FORCE_BUILD=1 to rebuild)"
else
    log "building zendnn -> $LLAMA_BUILD_ZENDNN"
    cmake -S "$LLAMA_SRC" -B "$LLAMA_BUILD_ZENDNN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=ON \
        -DLLAMA_CURL=OFF \
        -DGGML_ZENDNN=ON \
        -DZENDNN_ROOT="$ZENDNN_ROOT" \
        $CCACHE_ARG
    cmake --build "$LLAMA_BUILD_ZENDNN" --target llama-server -j"$(nproc)"
fi

# verify the zendnn binary actually links libzendnnl from ZENDNN_ROOT
if LD_LIBRARY_PATH="$ZENDNN_LIB" ldd "$LLAMA_BUILD_ZENDNN/bin/llama-server" | grep -q zendnn; then
    log "zendnn link OK: $(LD_LIBRARY_PATH="$ZENDNN_LIB" ldd "$LLAMA_BUILD_ZENDNN/bin/llama-server" | grep zendnn | head -1 | xargs)"
else
    die "zendnn binary does NOT link libzendnnl — check ZENDNN_ROOT"
fi
