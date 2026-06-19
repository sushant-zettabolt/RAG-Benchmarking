# Multi-stage build of llama.cpp's llama-server from public source.
#
# One Dockerfile, two images, selected by the GGML_ZENDNN build arg:
#   GGML_ZENDNN=OFF  -> nqrag-llama:baseline  (ggml CPU only)
#   GGML_ZENDNN=ON   -> nqrag-llama:zendnn    (ggml + ZenDNN backend)
#
# When GGML_ZENDNN=ON and no local ZenDNN path is provided, llama.cpp's CMake
# auto-fetches PUBLIC ZenDNN source and builds it — nothing internal/proprietary
# is shipped. Each host compiles from source with -march=native, auto-tuned to
# that CPU (so a built image is NOT portable to a different microarchitecture).
#
# A/B fairness: pass the SAME LLAMA_CPP_REF to both builds so baseline and zendnn
# are the identical commit (scripts/build_llama.sh resolves master's HEAD once and
# feeds it to both). Leave it empty for plain `up` to take whatever HEAD is at
# build time.

# ── builder ──────────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS builder

ARG GGML_ZENDNN=OFF
ARG LLAMA_CPP_REPO=https://github.com/ggml-org/llama.cpp
# Optional pin. Empty = build whatever HEAD the clone lands on (latest master).
ARG LLAMA_CPP_REF=

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        ca-certificates \
        libcurl4-openssl-dev \
        libgomp1 \
        python3 \
        python-is-python3 \
    && rm -rf /var/lib/apt/lists/*
# ^ python3 (+ `python` alias) is required by the ZenDNN backend's libxsmm
#   dependency, whose Makefile invokes a Python interpreter for code generation.

WORKDIR /src
# Shallow-clone latest; if a ref is pinned, fetch and check it out for a fair A/B.
RUN git clone "$LLAMA_CPP_REPO" llama.cpp \
    && cd llama.cpp \
    && if [ -n "$LLAMA_CPP_REF" ]; then \
           git fetch --depth 1 origin "$LLAMA_CPP_REF" && git checkout "$LLAMA_CPP_REF"; \
       fi \
    && git rev-parse HEAD > /src/llama_cpp_built_sha.txt

WORKDIR /src/llama.cpp
# GGML_NATIVE=ON => -march=native (tunes to this CPU). GGML_ZENDNN toggles the
# ZenDNN backend; ON triggers the public ZenDNN auto-fetch+build at configure.
RUN cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=ON \
        -DGGML_ZENDNN=${GGML_ZENDNN} \
        -DLLAMA_CURL=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
    && cmake --build build --config Release --target llama-server -j"$(nproc)" \
       || { echo "=== nested zendnn/libxsmm build+configure logs (on failure) ==="; \
            find build -path '*zendnn*' \( -name '*-build-*.log' -o -name '*-configure-*.log' \) \
                 -exec sh -c 'echo "---- $1 ----"; tail -50 "$1"' _ {} \; 2>/dev/null; \
            echo "=== end logs ==="; exit 1; }

# Collect the server binary + every shared lib it needs into one dir so the
# runtime stage can grab them with a single COPY (paths differ baseline vs zendnn).
# Match '*.so*' (not just '*.so') so VERSIONED libs (e.g. libllama-common.so.0,
# the SONAMEs the binary actually links against) are included — plain cp follows
# the symlinks so each needed name lands as a real file under /out.
RUN mkdir -p /out \
    && cp build/bin/llama-server /out/ \
    && find build -name '*.so*' -exec cp {} /out/ \; \
    && cp /src/llama_cpp_built_sha.txt /out/

# ── runtime ──────────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
# numactl is baked in so the compose command never has to apt-get it at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgomp1 \
        libcurl4 \
        libstdc++6 \
        ca-certificates \
        curl \
        numactl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /out/ /app/
ENV LD_LIBRARY_PATH=/app

# The compose `command:` is what actually launches the server (it builds the arg
# string from env). Default keeps the image runnable standalone.
ENTRYPOINT []
CMD ["/app/llama-server", "--help"]
