# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

> ⚠️ **Latency comparison not valid:** baseline and zendnn processed different workloads (prompt tokens 3018 vs 3018, completion tokens 71 vs 22). Per-stage latency scales with token count, so the latency speedups below are apples-to-oranges. Compare the per-token throughput table instead, and check why the runs diverged (see Sanity / Evaluation detail — likely a broken job).

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.060 | 0.054 | 1.12x |
| Retrieval + overhead | 0.056 | 0.053 | 1.05x |
| Prompt processing (prefill) | 7.559 | 4.553 | 1.66x |
| Generation (decode) | 2.210 | 0.667 | 3.31x |
| LLM total (prefill+decode) | 9.769 | 5.220 | 1.87x |
| Time to first token | 7.675 | 4.660 | 1.65x |
| End-to-end (total) | 9.881 | 5.322 | 1.86x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 399.3 | 662.9 | 1.66x |
| Decode (generation) t/s | 32.1 | 33.0 | 1.03x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3018 | 3018 |
| Completion tokens (mean) | 71 | 22 |
| Query embedding (s) | 0.060 | 0.054 |
| Retrieval + overhead (s) | 0.056 | 0.053 |
| Match rate (LLM judge) | 100.0% | 100.0% |
| Contains reference (lexical) | 100.0% | 100.0% |

### Speedup summary

- Prefill throughput: **1.66x**  (399.3 → 662.9 t/s)
- Decode throughput:  **1.03x**  (32.1 → 33.0 t/s)
- LLM inference latency: **1.87x**
- End-to-end latency: **1.86x**  (9.88s → 5.32s)

_Note: throughput (t/s) is the only valid comparison here — the two runs processed different token counts, so latency speedups reflect workload size, not backend speed._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 1 |
| Succeeded | 1 |
| Errored | 0 |
| **Matched (LLM judge)** | **1 (100.0%)** |
| Mean judge score | 0.800 |
| Contains reference (lexical) | 1 (100.0%) |
| Verdicts | correct=1 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 3089 |
| Tokens/query (prompt / completion) | 3018 / 71 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 9.881 | 9.881 | 9.881 | 9.881 | 9.881 |
| Time to first token | 7.675 | 7.675 | 7.675 | 7.675 | 7.675 |
| Query embedding | 0.060 | 0.060 | 0.060 | 0.060 | 0.060 |
| Retrieval + overhead | 0.056 | 0.056 | 0.056 | 0.056 | 0.056 |
| Prompt processing (prefill) | 7.559 | 7.559 | 7.559 | 7.559 | 7.559 |
| Generation (decode) | 2.210 | 2.210 | 2.210 | 2.210 | 2.210 |
| LLM total (prefill+decode) | 9.769 | 9.769 | 9.769 | 9.769 | 9.769 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3018 | 3018 | 3018 | 3018 | 3018 |
| Completion tokens | 71 | 71 | 71 | 71 | 71 |
| Total tokens | 3089 | 3089 | 3089 | 3089 | 3089 |

### Failed / incorrect queries (0)

_None — all queries matched._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: Unfortunately, the provided context does not contain any information about the last time anyone was on the moon. However, I can provide you with the information that the last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt.  
- score: 0.80 (correct) — Provides correct date and context, but lacks precision in the time.

#### Incorrect

_No incorrect examples._


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 1 |
| Succeeded | 1 |
| Errored | 0 |
| **Matched (LLM judge)** | **1 (100.0%)** |
| Mean judge score | 1.000 |
| Contains reference (lexical) | 1 (100.0%) |
| Verdicts | correct=1 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 3040 |
| Tokens/query (prompt / completion) | 3018 / 22 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 5.322 | 5.322 | 5.322 | 5.322 | 5.322 |
| Time to first token | 4.660 | 4.660 | 4.660 | 4.660 | 4.660 |
| Query embedding | 0.054 | 0.054 | 0.054 | 0.054 | 0.054 |
| Retrieval + overhead | 0.053 | 0.053 | 0.053 | 0.053 | 0.053 |
| Prompt processing (prefill) | 4.553 | 4.553 | 4.553 | 4.553 | 4.553 |
| Generation (decode) | 0.667 | 0.667 | 0.667 | 0.667 | 0.667 |
| LLM total (prefill+decode) | 5.220 | 5.220 | 5.220 | 5.220 | 5.220 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3018 | 3018 | 3018 | 3018 | 3018 |
| Completion tokens | 22 | 22 | 22 | 22 | 22 |
| Total tokens | 3040 | 3040 | 3040 | 3040 | 3040 |

### Failed / incorrect queries (0)

_None — all queries matched._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972.  
- score: 1.00 (correct) — Matches reference date and provides additional context.

#### Incorrect

_No incorrect examples._


---
_Generated by report_ab.py._