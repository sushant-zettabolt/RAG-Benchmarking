# RAG Pipeline Bench — Reference Info

Quick reference for the prompts, NUMA/CPU pinning, and containers in this stack.
Values pulled from the live config (`.env`, compose files, `src/`, `scripts/`).

---

## 1. AnythingLLM system prompt

AnythingLLM is the RAG layer. The seed script (`scripts/seed_anythingllm.py`) does
**not** override the workspace system prompt, so each workspace uses AnythingLLM's
**default** `openAiPrompt`:

```
Given the following conversation, relevant context, and a follow up question,
reply with an answer to the current question the user is asking. Return only your
response to the question given the above information following the users
instructions as needed.
```

How the RAG query is sent (`src/common.py` → `allm_stream_chat`):

```
POST {ALLM_URL}/api/v1/workspace/{SLUG}/stream-chat
body: {"message": <question>, "mode": "query", "sessionId": <unique-per-query>}
```

- `SLUG` = **`squad-bench`** (`.env`)
- `QUERY_MODE` = **`query`** (RAG-only; the model answers strictly from retrieved
  context, not its own knowledge)
- A **unique `sessionId` per query** prevents prior answers being carried forward as
  chat history (which would inflate prompt_tokens / prefill across A/B jobs).

### Retrieval / chunking that shapes the prompt
Applied to the workspace by `src/ingest.py` via `POST /workspace/{slug}/update`:

| setting | value | source |
|---|---|---|
| `topN` (chunks stuffed into context) | **15** | `.env RETRIEVAL_TOPN` |
| `similarityThreshold` | **0.0** | `.env RETRIEVAL_SIM_THRESHOLD` |
| chunk size | **512 words** (~3072 chars, ~6 chars/word) | `.env EMBED_CHUNK_WORDS` |
| chunk overlap | **100 words** (~600 chars) | `.env EMBED_CHUNK_OVERLAP_WORDS` |
| chat context window | **16384** tokens | `.env CHAT_CTX` |

> Note: the splitter is langchain's `RecursiveCharacterTextSplitter` measuring
> **characters**, not tokens — the word knobs are converted to chars in the seed
> script. `topN × chunk_size` sets the prompt size (≈ multi-thousand-token prefill).

---

## 2. Judge prompt (LLM-as-judge)

Defined in `src/common.py` (`_JUDGE_SYS` + `judge_answer`). Grading instructions are
folded into a **single user turn** (some chat templates, e.g. Gemma, ignore a system
role and return empty content).

**System/grading instruction (`_JUDGE_SYS`):**
```
You are a strict grader for a question-answering system. You are given a QUESTION,
one or more REFERENCE answers considered correct, and a CANDIDATE answer produced by
the system. Decide whether the CANDIDATE is correct: it is correct if it conveys the
same factual answer as any REFERENCE, even if phrased differently or with extra
context. It is incorrect if it states a different fact, refuses, or says it cannot
find the answer. Respond with ONLY a compact JSON object: {"score": <0.0-1.0>,
"verdict": "correct"|"incorrect"|"partial", "reason": "<one short sentence>"}.
```

**User turn actually sent:**
```
{_JUDGE_SYS}

QUESTION: {question}
REFERENCE(S): {ref1 | ref2 | ...}
CANDIDATE: {candidate or "(empty)"}

Grade now.
```

**Judge call parameters:**

| param | value | source |
|---|---|---|
| endpoint | `https://openrouter.ai/api/v1/chat/completions` | `.env JUDGE_BASE_URL` |
| model | **`deepseek/deepseek-chat`** | `.env JUDGE_MODEL` |
| `temperature` | **0** | `common.py` |
| `max_completion_tokens` | **2048** | `common.py` |
| match threshold | `score >= ` **0.5** → `match=True` | `.env JUDGE_THRESHOLD` |
| auth | `Authorization: Bearer $JUDGE_API_KEY` | `.env` (secret, not committed) |

- The judge runs **after** the metrics snapshot, so grading never pollutes the
  measured prompt/decode counters.
- Parsing is best-effort (regex-extracts the JSON object, tolerates code fences /
  reasoning preambles, falls back to `reasoning_content`); on parse failure the raw
  text is kept under `judge_raw` for debugging instead of a silent 0%.
- Alternative judge (commented in `.env`): DeepSeek direct
  `https://api.deepseek.com/v1`, model `deepseek-chat`. If no external judge is
  configured it routes through the local LiteLLM proxy.

---

## 3. NUMA / CPU pinning per service

All pinning is **optional** and set per-host in `.env`, sized to your CPU topology
(run `lscpu` to see your NUMA nodes and core ranges); leave the variables empty for
the portable, no-pinning default.

Mechanism:
- `*_CPUSET` → Docker `cpuset` (cgroup: which CPUs the container may run on).
- `*_MEMBIND` → NUMA memory node, applied **in-process** via `numactl --membind`
  inside the llama containers (compose has no cgroup `cpuset-mems` field).
- `OMP_PROC_BIND=close` + `OMP_PLACES=cores` exported for the llama servers so OpenMP
  threads stay pinned to cores.

**Example layout** for a 2-socket box (node 0 = CPUs `0–95`, node 1 = `96–191`) —
substitute your own ranges:

| service | CPUSET | MEMBIND (NUMA node) | threads | source |
|---|---|---|---|---|
| **llama-chat** | `96-191` | node **1** | `CHAT_THREADS` | `.env` |
| **llama-embed** | `0-15` | node **0** | `EMBED_THREADS` | `.env` |
| **litellm** | `16-23` | — | — | `.env` |
| **anythingllm** | `24-39` | — | — | `.env` |
| **prometheus** + **pushgateway** | `40-43` (`PROM_CPUSET`) | — | — | `.env` |
| **harness** | `44-51` | — | — | `.env` |
| **grafana** | `52-55` | — | — | `.env` |
| **jenkins** | `88-95` (`JENKINS_CPUSET`) | — | — | `.env` |

Design intent: give the chat server **one whole socket exclusively** (with its memory
node-local) so generation is isolated; put the embed server and all support services on
the other socket.

### Parallel ingest pinning (separate path — `run_ingest.sh`, not the live servers)
Data-parallel embedding launches many short-lived embed instances, configured in `.env`:

| knob | meaning |
|---|---|
| `EMBED_INGEST_INSTANCES` | number of parallel embed instances |
| `EMBED_INGEST_THREADS_PER` | threads per instance |
| `EMBED_INGEST_BATCH` | embedding batch size |
| `EMBED_INGEST_PHYSICAL_ONLY` | restrict to physical cores (skip SMT siblings) |

Each instance is pinned to `THREADS_PER` consecutive logical CPUs, split evenly across
the NUMA nodes and kept node-local. Constraint: `(INSTANCES/nodes) * THREADS_PER ≤
logical CPUs/node`.

### A/B overlay (`docker-compose.ab.yml`)
Both **llama-chat** and **llama-embed** keep the same CPUSET/MEMBIND and OMP pinning;
the only per-job change is the ZenDNN runtime env:
- baseline job: `ZENDNNL_MATMUL_ALGO` **unset** (no ZenDNN env at all)
- zendnn job: `ZENDNNL_MATMUL_ALGO=$AB_ZENDNN_ALGO`

---

## 4. Containers / services

### Main stack — `docker-compose.yml`

| service | container_name | role | image | port (host) |
|---|---|---|---|---|
| `llama-chat` | `nqrag-llama-chat` | chat/generation llama-server (alias `chat-model`) | built from source | 8080 |
| `llama-embed` | `nqrag-llama-embed` | embedding llama-server (`--embedding`, alias `embed-model`) | built from source | 8080 |
| `litellm` | `nqrag-litellm` | OpenAI-compatible proxy / router | public | 4000 |
| `pushgateway` | `nqrag-pushgateway` | Prometheus pushgateway (harness metrics) | public | 9091 |
| `prometheus` | `nqrag-prometheus` | metrics scrape + storage | public | 9090 |
| `grafana` | `nqrag-grafana` | dashboards | public | 3000 |
| `anythingllm` | `nqrag-anythingllm` | RAG layer + LanceDB vector store | public | 3001 |
| `seed` | `nqrag-seed` | one-shot: seeds AnythingLLM DB (API key + provider/chunk settings), then exits | `nqrag-harness:local` | — |
| `harness` | `nqrag-harness` | Python bench harness (ingest / evaluate / report) | `build ./harness` | — |

**Named volumes:** `anythingllm-storage` (SQLite + LanceDB files), `prom-data`,
`grafana-data`.

### A/B overlay — `docker-compose.ab.yml`
Overrides only `llama-chat` and `llama-embed` (swaps image baseline↔zendnn + ZenDNN
env per job). No new containers.

### CI — `docker-compose.jenkins.yml`

| service | container_name | role | port |
|---|---|---|---|
| `jenkins` | `nqrag-jenkins` | CI controller (Docker-out-of-Docker, host networking) | 8088 |

---

_Secrets (`JUDGE_API_KEY`, `ALLM_KEY`, `LITELLM_MASTER_KEY`) live in the gitignored
`.env` and are never committed._
