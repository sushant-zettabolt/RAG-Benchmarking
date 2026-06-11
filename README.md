# RAG Pipeline Benchmark — ZenDNN vs baseline llama.cpp

End-to-end RAG benchmark that A/B-compares a **baseline** llama.cpp build
against a **ZenDNN**-enabled build on the *same* full pipeline:

```
harness.py ──► AnythingLLM ──► LiteLLM ──► llama-server (chat :8081 / embed :8082)
                  │ (LanceDB vector search)      │
                  └──────── Prometheus ◄─────────┘  (per-model latency + TTFT)
```

Each query is a real RAG round-trip: embed the query → vector search →
augment the prompt with retrieved chunks → stream the chat completion. The
report breaks end-to-end latency into embed / prefill / decode / residual,
with token counts, throughput, and retrieved-chunk stats per query.

## Quick start

```bash
git clone <this-repo> && cd rag_pipeline_bench
cp config.env.example config.env    # edit for your machine (see below)
./setup.sh                          # build, start stack, download + ingest corpus
./run_bench.sh                      # baseline job, zendnn job, then the report
```

The report lands in `results/REPORT_<STAMP>.md`.

## Requirements

- AMD EPYC (or any x86_64) Linux box; NUMA pinning optional but recommended
- `python3`, `docker` (daemon access), `cmake` + C++ toolchain, `git`,
  `curl`, `envsubst` (gettext), `numactl` (only if you use CPU binding)
- A llama.cpp checkout **containing the ZenDNN backend**
  (`ggml/src/ggml-zendnn/`) — this is a separate repo/fork, not part of
  this one. Point `LLAMA_SRC` at it (or set `LLAMA_REPO` to let
  `scripts/build_llama.sh` clone it).
- A ZenDNN install prefix (`ZENDNN_ROOT`) for the ZenDNN build
- Two GGUF models: a chat model and an embedding model
- python packages `requests`, `datasets`, `litellm[proxy]` —
  `setup.sh` installs any that are missing

## Configuration (`config.env`)

Everything machine-specific lives in `config.env` (gitignored). The
important knobs:

| Variable | What it is |
|---|---|
| `LLAMA_SRC`, `LLAMA_REPO`, `LLAMA_REF` | llama.cpp source path, or git URL+ref to clone |
| `ZENDNN_ROOT` | ZenDNN install prefix (`-DZENDNN_ROOT`); empty ⇒ baseline-only |
| `ZENDNN_ENV` | env applied to the zendnn job (default `ZENDNNL_MATMUL_ALGO=1`) |
| `CHAT_MODEL`, `EMBED_MODEL` | GGUF paths |
| `CHAT_CPUS`/`CHAT_MEMBIND`, `EMBED_CPUS`/`EMBED_MEMBIND` | numactl binding per server; empty ⇒ no numactl |
| `THREADS`, `CHAT_CTX`, `*_BATCH`, `*_UBATCH`, `EXTRA_LLAMA_FLAGS` | llama-server tuning |
| `CHAT_PORT`, `EMBED_PORT`, `LITELLM_PORT`, `PROM_PORT`, `ALLM_PORT` | ports |
| `CORPUS_N`, `QUERIES_N` | NQ corpus/query sizes (setup, once) |
| `WARMUP`, `BENCH_QUERIES`, `DROP_FIRST` | benchmark warmups, query cap, report Q1 drop |

On a 2-NUMA-node machine, pin chat and embed to different nodes (the
defaults pin chat to node 1, embed to node 0) so they never compete for
cores or memory bandwidth. On a non-NUMA machine just clear the `*_CPUS`
variables.

## Scripts

| Script | What it does |
|---|---|
| `./setup.sh` | One-shot: deps → build both llama-servers → start stack → init AnythingLLM (API key + provider settings in SQLite) → download NQ corpus → ingest → gate-check one RAG query. Idempotent. |
| `./run_bench.sh [ab\|baseline\|zendnn]` | The benchmark. For each job: swaps embed+chat servers to that build, gate-checks ZenDNN engagement/contamination, replays the queries through AnythingLLM, then generates the report. |
| `./start_services.sh <baseline\|zendnn>` | Bring up the whole stack for one build (embed, chat, LiteLLM, Prometheus, AnythingLLM) with health checks. |
| `./stop_all.sh` | Stop everything (keeps `allm_storage/` and `results/`). |
| `scripts/build_llama.sh` | Builds `build/` (baseline) and `build_zendnn/` from `LLAMA_SRC`; verifies the zendnn binary links `libzendnnl`. `FORCE_BUILD=1` to rebuild. |
| `scripts/start_{chat,embed,litellm,prometheus,anythingllm}.sh` | Individual service starters (all config-driven). |
| `scripts/init_anythingllm.sh` | First-time AnythingLLM DB seeding (idempotent). |

Python entry points (all configured via env vars, no hardcoded values):
`prepare_data.py` (NQ download), `ingest.py` (upload+embed corpus),
`harness.py` (query replay + Prometheus snapshots), `report.py` (the
report; `BASE=... STAMP=... DROP_FIRST=1 python3 report.py` regenerates
one any time).

## What gets measured

| Stage | Source |
|---|---|
| End-to-end wall + client TTFT | harness.py (`/stream-chat` SSE) |
| Retrieved chunks per query | SSE `sources` array |
| Prompt/generated token counts, prefill/decode time & t/s | llama-server log per request |
| Query embedding latency | LiteLLM Prometheus delta over the job |
| Vector search + prompt build (residual) | wall − embed − LLM |

## Repo hygiene

Generated artifacts are gitignored: `results/`, `data/`, `allm_storage/`
(AnythingLLM DB + LanceDB vectors), rendered `conf/*` (from the tracked
`conf/*.tpl`), logs/pids, and `config.env`. The llama.cpp tree (source and
builds) is also ignored — its ZenDNN modifications belong to the llama.cpp
fork and should be pushed there, not here.

## Troubleshooting

See [steps.md](steps.md) for the full manual walkthrough and a
symptom→fix table (unhealthy embed model, `--flash-attn` flag values,
ubatch vs chunk size, missing TTFT, negative residual, …).
