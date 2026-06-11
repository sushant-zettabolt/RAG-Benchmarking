# RAG Pipeline Benchmark — Setup & Run Guide

> **Scripted flow (recommended):** everything below is automated —
> `cp config.env.example config.env`, then `./setup.sh` once and
> `./run_bench.sh` per benchmark. See [README.md](README.md).
> This document is the manual, step-by-step walkthrough of what those
> scripts do, plus the troubleshooting table.
> Machine-specific values (paths, NUMA binding, ports, batch sizes) now
> live in `config.env`; the start scripts moved to `scripts/` and read it.

## Index

1. [Components](#components)
2. [Pipeline Structure](#pipeline-structure)
3. [Setup Steps](#setup-steps)
   - [S1. Build llama-server binaries](#s1-build-llama-server-binaries)
   - [S2. Start the embedding server](#s2-start-the-embedding-server)
   - [S3. Start the chat server](#s3-start-the-chat-server)
   - [S4. Start LiteLLM proxy](#s4-start-litellm-proxy)
   - [S5. Start Prometheus](#s5-start-prometheus)
   - [S6. Start AnythingLLM (headless)](#s6-start-anythingllm-headless)
   - [S7. Prepare data and ingest corpus](#s7-prepare-data-and-ingest-corpus)
4. [Running the Benchmark](#running-the-benchmark)
   - [R1. Job A — baseline](#r1-job-a--baseline)
   - [R2. Job B — ZenDNN](#r2-job-b--zendnn)
   - [R3. Generate the report](#r3-generate-the-report)
5. [Teardown](#teardown)
6. [Troubleshooting](#troubleshooting)

---

## Components

| Component | What it does | Port |
|---|---|---|
| `llama-server` (chat) | Serves Llama-3.1-8B-Instruct-BF16 for inference | 8081 |
| `llama-server` (embed) | Serves nomic-embed-text-v1.5 for embeddings | 8082 |
| LiteLLM proxy | Routes `chat-model` → 8081, `embed-model` → 8082; emits Prometheus metrics | 4000 |
| Prometheus | Scrapes LiteLLM + both llama-servers every 5s | 9090 |
| AnythingLLM | RAG orchestrator — chunks docs, embeds, vector search, augments prompt, calls chat | 3001 |
| `harness.py` | Replays NQ queries via AnythingLLM streaming; records wall-clock + TTFT; snapshots Prometheus | — |

**Both embed and chat servers swap between Job A (baseline) and Job B (ZenDNN). Everything else stays up.**

---

## Pipeline Structure

```
harness.py  (wall-clock + client TTFT, via /stream-chat SSE)
    │
    ▼
AnythingLLM :3001
    │  1. embeds query  → LiteLLM :4000 → llama-server :8082
    │  2. vector search in LanceDB  (no external API; absorbed into residual)
    │  3. builds augmented prompt (~2300 tokens)
    │  4. streaming chat  → LiteLLM :4000 → llama-server :8081
    ▼
LiteLLM :4000  ──► Prometheus :9090  (per-model latency + TTFT)
    ├─ embed-model ──► :8082  (Job A: build/  |  Job B: build_zendnn/)
    └─ chat-model  ──► :8081  (Job A: build/  |  Job B: build_zendnn/)
```

| Stage | How it is measured |
|---|---|
| Query embedding | LiteLLM Prometheus `litellm_request_total_latency_metric` (embed-model), delta over job |
| Vector search + augment | Derived: wall − embed − llm (includes LanceDB, prompt build, HTTP overhead) |
| LLM inference | llama-server log `prompt eval time` + `eval time` per request |
| TTFT — client | harness.py: time from request to first SSE chunk |
| TTFT — LiteLLM | Prometheus `litellm_llm_api_time_to_first_token_metric`, delta over job |
| End-to-end | harness.py wall-clock to SSE close event |

---

## Setup Steps

### S1. Build llama-server binaries

> Scripted: `scripts/build_llama.sh` runs exactly this (paths from `config.env`) and verifies the zendnn link.

```bash
cd /home/zettabolt/mkumar/sushant/RAG_testing/llama.cpp

# Baseline — output: build/bin/llama-server
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=ON \
  -DLLAMA_CURL=OFF \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
cmake --build build --target llama-server -j$(nproc)

# ZenDNN — output: build_zendnn/bin/llama-server
cmake -B build_zendnn \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=ON \
  -DLLAMA_CURL=OFF \
  -DGGML_ZENDNN=ON \
  -DZENDNN_ROOT=/home/zettabolt/internal_zendnn/ZenDNN/build/install \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
cmake --build build_zendnn --target llama-server -j$(nproc)
```

Verify ZenDNN binary links the right lib:
```bash
ldd /home/zettabolt/mkumar/sushant/RAG_testing/llama.cpp/build_zendnn/bin/llama-server | grep zendnn
# expect: libzendnnl.so => /home/zettabolt/internal_zendnn/ZenDNN/build/install/zendnnl/lib/libzendnnl.so
```

---

### S2. Start the embedding server

> **Critical:** `-b 2048 -ub 2048 -c 2048` are required. Default ubatch=512 is too small for AnythingLLM chunks (1400–2000 tokens) and causes silent 500 errors.

For the **initial ingest and Job A**, start the baseline embed server:
```bash
/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/scripts/start_embed.sh \
  baseline \
  /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/embed_baseline.log
```

What that script runs (for reference):
```bash
LD_LIBRARY_PATH="/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/llama.cpp/build/bin" \
numactl --physcpubind=0-95 --membind=0 \
/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/llama.cpp/build/bin/llama-server \
    --model /scratch/zettabolt/data/models/gguf/nomic-embed-text-v1.5.f32.gguf \
    --embedding \
    --port 8082 --host 127.0.0.1 \
    -t 96 -b 2048 -ub 2048 -c 2048 \
    --flash-attn on \
    --cache-type-k bf16 \
    --cache-type-v bf16 \
    --no-mmap \
    --metrics
```

Verify:
```bash
curl -s http://127.0.0.1:8082/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"input":"hello","model":"local-embed"}' \
  | python3 -c "import sys,json; print('dims=', len(json.load(sys.stdin)['data'][0]['embedding']))"
# expect: dims= 768
```

---

### S3. Start the chat server

For Job A, start the baseline chat server:
```bash
/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/scripts/start_chat.sh \
  baseline \
  /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/chat_baseline.log
```

What that script runs (for reference):
```bash
# baseline
LD_LIBRARY_PATH="/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/llama.cpp/build/bin" \
numactl --physcpubind=96-191 --membind=1 \
/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/llama.cpp/build/bin/llama-server \
    --model /scratch/zettabolt/data/models/gguf/Llama-3.1-8B-Instruct-BF16.gguf \
    --port 8081 --host 127.0.0.1 \
    -t 96 -c 8192 -b 2048 \
    --flash-attn on \
    --cache-type-k bf16 \
    --cache-type-v bf16 \
    --no-mmap \
    --metrics

# zendnn
ZENDNNL_MATMUL_ALGO=1 \
LD_LIBRARY_PATH="/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/llama.cpp/build_zendnn/bin:/home/zettabolt/internal_zendnn/ZenDNN/build/install/zendnnl/lib" \
numactl --physcpubind=96-191 --membind=1 \
/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/llama.cpp/build_zendnn/bin/llama-server \
    --model /scratch/zettabolt/data/models/gguf/Llama-3.1-8B-Instruct-BF16.gguf \
    --port 8081 --host 127.0.0.1 \
    -t 96 -c 8192 -b 2048 \
    --flash-attn on \
    --cache-type-k bf16 \
    --cache-type-v bf16 \
    --no-mmap \
    --metrics
```

To change numactl binding, context size, batch size, ports, or env vars: edit `config.env` — both start scripts read every value from it (nothing is hardcoded).

---

### S4. Start LiteLLM proxy

> **Critical:** the `embed-model` entry in `conf/litellm.yaml` **must** carry `model_info: {mode: embedding}`. Without it, LiteLLM health-checks the embedding server with a *chat completion* probe, the embed server rejects it (`the current context does not logits computation. skipping`), and the model is permanently flagged unhealthy — which surfaces downstream as `textResponse=None` / empty answers from AnythingLLM. The committed config already has this set:
> ```yaml
>   - model_name: embed-model
>     litellm_params:
>       model: openai/local-embed
>       api_base: http://127.0.0.1:8082/v1
>       api_key: "sk-noauth"
>     model_info:
>       mode: embedding
> ```

```bash
/home/zettabolt/.local/bin/litellm \
  --config /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/conf/litellm.yaml \
  --port 4000 \
  > /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/litellm.log 2>&1 &
echo $! > /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/litellm.pid

sleep 15
```

Verify **both** models are healthy (not just that the proxy is up):
```bash
curl -s http://127.0.0.1:4000/health -H "Authorization: Bearer sk-bench-master" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('healthy:', [e['model'] for e in d['healthy_endpoints']]); print('unhealthy:', [e['model'] for e in d['unhealthy_endpoints']])"
# expect: healthy: ['openai/local-chat', 'openai/local-embed']   unhealthy: []
```

---

### S5. Start Prometheus

```bash
docker rm -f prom-bench 2>/dev/null
docker run -d --name prom-bench --network host \
  -v /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/conf/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus

sleep 10
curl -s 'http://127.0.0.1:9090/api/v1/targets' \
  | python3 -c "
import sys,json
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(t['labels']['job'], '->', t['health'])
"
# expect: litellm -> up, llamacpp_chat -> up, llamacpp_embed -> up
```

---

### S6. Start AnythingLLM (headless)

**First time only** — if allm_storage already exists with data, skip to the docker run.

```bash
# Fix storage permissions
docker run --rm --privileged \
  -v /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/allm_storage:/fix \
  alpine sh -c "chmod -R 777 /fix && chown -R 1000:1000 /fix"
```

```bash
docker rm -f anythingllm-bench 2>/dev/null
docker run -d --name anythingllm-bench --network host \
  --cap-add SYS_ADMIN \
  --env-file /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/conf/anythingllm.env \
  -v /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/allm_storage:/app/server/storage \
  mintplexlabs/anythingllm

sleep 30
curl -s http://127.0.0.1:3001/api/ping && echo "AnythingLLM up"
```

**First time only — write API key and provider settings to SQLite:**
```bash
docker exec anythingllm-bench python3 -c "
import sqlite3
conn = sqlite3.connect('/app/server/storage/anythingllm.db')
cur = conn.cursor()
cur.execute('''
  INSERT INTO api_keys (secret, name, createdAt, lastUpdatedAt)
  VALUES ('nua-bench-4ee96facb8074640bb8fc9ceffd56870', 'bench-key',
          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
''')
settings = [
    ('LLMProvider',                  'generic-openai'),
    ('EmbeddingEngine',              'generic-openai'),
    ('LLMPreference',                'chat-model'),
    ('EmbeddingModel',               'embed-model'),
    ('GenericOpenAiBasePath',        'http://127.0.0.1:4000/v1'),
    ('GenericOpenAiKey',             'sk-bench-master'),
    ('GenericOpenAiModelPref',       'chat-model'),
    ('GenericOpenAiTokenLimit',      '8192'),
    ('EmbeddingBasePath',            'http://127.0.0.1:4000/v1'),
    ('EmbeddingModelMaxChunkLength', '8192'),
    ('GenericOpenAiEmbeddingApiKey', 'sk-bench-master'),
]
for label, value in settings:
    cur.execute('''INSERT INTO system_settings (label, value) VALUES (?, ?)
                   ON CONFLICT(label) DO UPDATE SET value=excluded.value''', (label, value))
conn.commit(); conn.close(); print('done')
"
docker restart anythingllm-bench && sleep 30
```

---

### S7. Prepare data and ingest corpus

**Runs once. Do not re-run between Job A and Job B.**

```bash
cd /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench

# Download NQ corpus and write doc files + query file
CORPUS_N=5000 QUERIES_N=200 python3 prepare_data.py

# Upload and embed all docs into AnythingLLM workspace "nq-bench"
BASE=/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench \
ALLM_KEY=nua-bench-4ee96facb8074640bb8fc9ceffd56870 \
python3 ingest.py
```

Gate check:
```bash
curl -s -X POST "http://127.0.0.1:3001/api/v1/workspace/nq-bench/chat" \
  -H "Authorization: Bearer nua-bench-4ee96facb8074640bb8fc9ceffd56870" \
  -H "Content-Type: application/json" \
  -d '{"message":"What is the largest planet?","mode":"query"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('sources:', len(d.get('sources',[])), '| answer:', d.get('textResponse','')[:80])"
# sources must be > 0
```

---

## Running the Benchmark

> Run Job A to full completion before starting Job B. Never run both simultaneously.

### R1. Job A — baseline (embed + chat both baseline)

```bash
export STAMP=$(date +%Y%m%d_%H%M%S)

/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/scripts/start_embed.sh \
  baseline \
  /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/embed_baseline_${STAMP}.log

/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/scripts/start_chat.sh \
  baseline \
  /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/chat_baseline_${STAMP}.log

# Gate checks
grep -i zendnn /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/chat_baseline_${STAMP}.log \
  && echo "CONTAMINATED — STOP" || echo "chat baseline clean"
grep -i zendnn /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/embed_baseline_${STAMP}.log \
  && echo "CONTAMINATED — STOP" || echo "embed baseline clean"

BASE=/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench \
ALLM_KEY=nua-bench-4ee96facb8074640bb8fc9ceffd56870 \
SLUG=nq-bench \
WARMUP=1 \
STAMP=$STAMP \
python3 /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/harness.py baseline
```

> `SLUG=nq-bench` and `ALLM_KEY` are **required** env vars — `harness.py` raises `KeyError` without them.
> `WARMUP=N` runs N leading warmup queries (default 0) that are executed **before** the Prometheus snapshot and excluded from all stats — absorbs model-load/cache-fill cost. With the 5 queries in `queries.jsonl`, `WARMUP=1` gives 1 warmup + 5 measured = 6 sends per job. `report.py` aligns the chat-log timing to the *last* N entries, so the warmup request in the log is dropped automatically.
> `QUERIES_N` is optional (caps the measured query count; used for smoke tests).

**Smoke test before the full run** — confirm one query flows end-to-end (returns `ok=True` with a non-`n/a` TTFT) before committing to all 200:
```bash
BASE=/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench \
ALLM_KEY=nua-bench-4ee96facb8074640bb8fc9ceffd56870 \
SLUG=nq-bench \
QUERIES_N=1 \
python3 /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/harness.py baseline
# expect: [baseline] 1/1  wall=~40s  ttft=~19s  ok=True
# if you see "ALLM error: ..." or ttft=n/a, fix the pipeline before the real run (see Troubleshooting)
```

---

### R2. Job B — ZenDNN (embed + chat both ZenDNN)

> Do not restart AnythingLLM, LiteLLM, or Prometheus.

```bash
sleep 10

/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/scripts/start_embed.sh \
  zendnn \
  /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/embed_zendnn_${STAMP}.log

grep -i zendnn /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/embed_zendnn_${STAMP}.log \
  && echo "embed zendnn engaged" || echo "EMBED ZENDNN NOT ENGAGED — STOP"

/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/scripts/start_chat.sh \
  zendnn \
  /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/chat_zendnn_${STAMP}.log

grep -i zendnn /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/chat_zendnn_${STAMP}.log \
  && echo "chat zendnn engaged" || echo "CHAT ZENDNN NOT ENGAGED — STOP"

BASE=/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench \
ALLM_KEY=nua-bench-4ee96facb8074640bb8fc9ceffd56870 \
SLUG=nq-bench \
WARMUP=1 \
STAMP=$STAMP \
python3 /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/harness.py zendnn
```

---

### R3. Generate the report

```bash
BASE=/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench \
STAMP=$STAMP \
python3 /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/report.py
```

---

## Manual query (no harness)

```bash
curl -s -X POST "http://127.0.0.1:3001/api/v1/workspace/nq-bench/chat" \
  -H "Authorization: Bearer nua-bench-4ee96facb8074640bb8fc9ceffd56870" \
  -H "Content-Type: application/json" \
  -d '{"message":"who invented the telephone?","mode":"query"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('Answer:', d.get('textResponse','')); print('Sources:', len(d.get('sources',[])))"
```

---

## Teardown

```bash
kill $(cat /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/chat.pid)   2>/dev/null
kill $(cat /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/embed.pid)  2>/dev/null
kill $(cat /home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench/results/litellm.pid) 2>/dev/null
docker rm -f prom-bench anythingllm-bench 2>/dev/null
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `harness.py` → `KeyError: 'SLUG'` (or `'ALLM_KEY'`) | Required env var not passed | Prefix the run with `SLUG=nq-bench ALLM_KEY=nua-bench-... BASE=...` |
| `textResponse=None` / empty answer / `ttft=n/a` with `ok=True` | embed-model unhealthy in LiteLLM | Ensure `model_info: {mode: embedding}` is set for embed-model in litellm.yaml, restart LiteLLM, confirm `/health` shows it under `healthy_endpoints` (see S4) |
| LiteLLM `/health` lists embed under `unhealthy_endpoints` with `"does not logits computation"` | Chat-completion health probe hitting embeddings-only server | Add `model_info: {mode: embedding}` to embed-model and restart LiteLLM |
| `EMBED/CHAT SERVER DOWN` → `unknown value for --flash-attn` | This llama.cpp build needs an explicit value | Use `--flash-attn on` (already fixed in both start scripts) |
| `sources: 0` but answer present | Query embedded but vector store empty | Re-run ingest (S7); confirm embed-model healthy first |
| Embedding 500: "input too large" | Embed server started without `-ub 2048` | Restart embed server — start_embed.sh already has the right flags |
| `sources: 0` on test query | Embedding failed during ingest | Delete workspace, clear lancedb + sqlite, re-run ingest.py |
| TTFT `n/a` in report | harness.py used `/chat` instead of `/stream-chat` | Current harness.py uses stream-chat — check you have the latest version |
| Negative residual | Log parser matched wrong log file (old run mixed in) | Set STAMP correctly so report.py reads the right log |
| LiteLLM `/metrics` empty | curl doesn't follow 307 redirect | Use `curl -sL`; prometheus.yml already uses `metrics_path: /metrics/` |
| AnythingLLM provider `<not set>` | DB overrides env vars | Re-run the SQLite insert block in S6, then `docker restart anythingllm-bench` |
| `zendnn engaged` missing | Wrong ZENDNN_ROOT at cmake time | Check `ldd build_zendnn/bin/llama-server \| grep zendnn` — must show internal_zendnn path |
| scipy/numpy import error | System scipy + user numpy version mismatch | `python3 -m pip install --upgrade scipy` |
