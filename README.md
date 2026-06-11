# Local RAG Evaluation Stack — AnythingLLM + llama.cpp + Google NQ

A fully containerized, reproducible RAG evaluation pipeline. Everything runs in
Docker — including the LLM and embedding servers — so the only host requirement
is **Docker + Docker Compose**. One `docker compose up` starts the stack; three
commands ingest Google Natural Questions, evaluate, and produce a report.

```
        ┌─────────────┐   embed   ┌──────────────┐
        │ llama-embed │◀──────────│              │
        │ (llama.cpp) │           │   LiteLLM    │   OpenAI-compatible proxy
        └─────────────┘           │   (proxy +   │   (token usage + TTFT metrics)
        ┌─────────────┐   chat    │  Prometheus  │
        │ llama-chat  │◀──────────│   metrics)   │
        │ (llama.cpp) │           └──────┬───────┘
        └─────────────┘                  │ /v1
                                  ┌───────▼───────┐        ┌────────────┐
                                  │  AnythingLLM  │◀───────│  harness   │
                                  │ (RAG app +    │ HTTP   │ ingest /   │
                                  │  LanceDB)     │        │ evaluate / │
                                  └───────────────┘        │ report     │
                                                           └────────────┘
```

## Prerequisites

- Docker Engine + Docker Compose v2 (`docker compose version`)
- ~6 GB disk for images + the default small models
- Internet access on first run (pulls images, models, and the NQ dataset).
  For air-gapped machines see **Shipping images via git-lfs** below.

## Quick start

```bash
cp .env.example .env        # optional: edit models/ports/sizes
./setup.sh                  # start stack + seed AnythingLLM (first run downloads models)
make ingest                 # download Google NQ + ingest 100 documents
make evaluate               # run queries against AnythingLLM + LLM-as-judge
make report                 # write results/report.md + results/report.json
```

`make all` runs ingest → evaluate → report in sequence. Outputs land in
`./data/` (bind-mounted into the harness container):

```
data/
  docs/                 ingested document files
  eval.jsonl            questions + reference answers
  ingest_metadata.json  ingestion status / failures
  results/
    metrics.jsonl       one structured record per query
    results.json        raw results + run summary
    report.md           human-readable report
    report.json         machine-readable report
```

A pre-generated example lives in [`reports/`](reports/).

## Configuration (`.env`)

Everything is configurable through `.env` — nothing is hardcoded.

| Variable | Default | Meaning |
|---|---|---|
| `CHAT_HF_REPO` / `CHAT_HF_FILE` | `unsloth/Llama-3.2-1B-Instruct-GGUF` / `…BF16.gguf` | Chat model (auto-downloaded) |
| `EMBED_HF_REPO` / `EMBED_HF_FILE` | `nomic-ai/nomic-embed-text-v1.5-GGUF` / `…f16.gguf` | Embedding model |
| `CHAT_MODEL_PATH` / `EMBED_MODEL_PATH` | _empty_ | Use a LOCAL GGUF (mounted from `MODELS_DIR`) instead of HF download |
| `MODELS_DIR` | `./models` | Host dir mounted read-only at `/models` |
| `CHAT_CTX` / `CHAT_BATCH` / `CHAT_UBATCH` | `8192` / `512` / `512` | Chat context & batch sizes |
| `EMBED_CTX` / `EMBED_BATCH` / `EMBED_UBATCH` | `2048` | Embed context & batch (keep batch ≥ ctx) |
| `CHAT_NGL` / `EMBED_NGL` | `0` | GPU layers to offload (0 = CPU). See **GPU** below |
| `CHAT_THREADS` / `EMBED_THREADS` | _empty_ | CPU threads (empty = auto) |
| `CHAT_EXTRA_FLAGS` | _empty_ | Extra llama-server flags, e.g. `--flash-attn on` |
| `*_PORT` | 8081/8082/4000/9090/3001 | Host ports for chat/embed/litellm/prometheus/anythingllm |
| `DOC_N` | `100` | Documents to ingest |
| `EVAL_N` | `100` | Eval questions to draw |
| `EVAL_LIMIT` | _empty_ | Cap measured queries (smoke tests) |
| `CORPUS_SCAN` | `20000` | Passages scanned to find answer-bearing documents |
| `JUDGE_MODEL` | `chat-model` | Model used as LLM judge |
| `JUDGE_THRESHOLD` | `0.5` | Judge score ≥ threshold counts as a match |
| `WARMUP` | `1` | Leading warmup queries excluded from the report |

### Models

By default llama.cpp auto-downloads small GGUFs from Hugging Face on first boot
(cached in the `llama-cache` volume). To use your own local models:

```dotenv
MODELS_DIR=/scratch/models/gguf
CHAT_MODEL_PATH=/models/Llama-3.1-8B-Instruct-BF16.gguf
EMBED_MODEL_PATH=/models/nomic-embed-text-v1.5.f32.gguf
```

### GPU

The default image is CPU-only. For NVIDIA GPUs set
`LLAMA_IMAGE=ghcr.io/ggml-org/llama.cpp:server-cuda`, set `CHAT_NGL`/`EMBED_NGL`
> 0, and add a `deploy.resources.reservations.devices` GPU reservation to the
`llama-chat`/`llama-embed` services (requires nvidia-container-toolkit).

## What gets measured

Per query we snapshot the llama.cpp `/metrics` counters on the chat and embed
servers before/after the AnythingLLM call (queries run serially, so deltas are
clean), and grade the answer with an LLM judge afterwards.

| Metric | Source |
|---|---|
| Match score / verdict | LLM-as-judge (LiteLLM) comparing answer vs reference |
| End-to-end latency | Harness wall-clock (request → SSE `close`) |
| TTFT | Harness: time to first `textResponse` chunk |
| Query embedding time | `llamacpp:prompt_seconds_total` delta on llama-embed |
| Prompt processing (prefill) | `llamacpp:prompt_seconds_total` delta on llama-chat |
| Generation (decode) | `llamacpp:tokens_predicted_seconds_total` delta on llama-chat |
| Retrieval + overhead | derived: `ttft − embed − prefill` (vector search + prompt build) |
| Token usage | `llamacpp:prompt_tokens_total` / `tokens_predicted_total` deltas |
| Total runtime | Harness job wall-clock |

LiteLLM + Prometheus also expose aggregate token-usage and TTFT metrics at
`http://localhost:9090` (Prometheus) for dashboards.

## ZenDNN A/B benchmark (optional)

Compare a **baseline** vs a **ZenDNN** llama.cpp chat backend on the *same* RAG
pipeline (identical model, documents, and queries) and get a baseline-vs-zendnn
report with per-stage latency, inference throughput (prefill/decode t/s), and
speedup ratios.

```bash
./setup.sh && make ingest      # stack up + documents ingested
make ab                        # baseline job, then zendnn job, then report_ab
```

`run_ab.sh` swaps only the `llama-chat` backend between jobs and runs them
**strictly sequentially** — one chat server at a time — so they never compete
for CPU and the numbers stay clean. It writes `data/results/report_ab.{md,json}`.

How the two backends are provided (configurable in `.env`):

| Variable | Default | Meaning |
|---|---|---|
| `AB_BASELINE_BINDIR` | `./llama.cpp/build/bin` | Host dir with a baseline `llama-server` (no ZenDNN) |
| `AB_ZENDNN_BINDIR` | `./llama.cpp/build_zendnn/bin` | Host dir with a ZenDNN-enabled `llama-server` |
| `AB_ZENDNN_LIBDIR` | _(ZenDNN install lib)_ | Dir with `libzendnnl.so`, added to `LD_LIBRARY_PATH` for the zendnn job |
| `AB_ZENDNN_ALGO` | `1` | `ZENDNNL_MATMUL_ALGO` value for the zendnn job |

Each job mounts its build tree into the runtime image
(`docker-compose.ab.yml`) and runs that binary — so baseline and zendnn differ
only in the llama.cpp backend. `CHAT_MODEL_PATH` must point at a local GGUF (the
A/B uses your real model, since ZenDNN targets matmul-bound prefill). A sample
A/B report is in [`reports/`](reports/).

## Dataset notes

- **Documents** come from `BeIR/nq` (Google NQ Wikipedia passages).
- **Questions + reference answers** come from `nq_open` (Google NQ open Q&A).
- To keep retrieval meaningful, ingestion prefers passages that actually contain
  a reference answer (`CORPUS_SCAN`), then tops up to `DOC_N`. The number of
  answerable questions is recorded in `ingest_metadata.json` and the report.
- Both datasets are configurable via `EVAL_DATASET` / `CORPUS_DATASET`.

## Shipping images via git-lfs (air-gapped install)

```bash
make save-images            # docker save -> images/*.tar (tracked by git-lfs)
git lfs track "images/*.tar"   # already in .gitattributes
git add .gitattributes images/*.tar && git commit -m "ship images"
```

On the target machine:

```bash
git lfs pull
make load-images            # docker load all tarballs
./setup.sh                  # no registry pulls needed
```

## Lifecycle

```bash
make up        # start serving containers
make ps        # status
make logs      # follow logs
make down      # stop containers (keeps volumes)
make clean     # remove generated data/results
make clean-all # also drop volumes (models cache, vector DB)
```

## Troubleshooting

- **`make ingest` says ALLM_KEY is empty** — run `./setup.sh` first; it generates
  the key and writes it to `.env`.
- **llama-chat slow to become healthy on first run** — it's downloading the GGUF;
  watch with `make logs`. Subsequent boots use the cached model.
- **All answers empty / unhealthy embed model** — confirm `conf/litellm.yaml`
  keeps `model_info: {mode: embedding}` on `embed-model`; without it LiteLLM
  health-probes the embed endpoint with a chat completion and flags it unhealthy.
- **Port already in use** — change the `*_PORT` values in `.env`.
```
