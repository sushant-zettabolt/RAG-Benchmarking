# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.013 | 0.010 | 1.24x faster |
| Retrieval + overhead | 0.056 | 0.056 | 1.00x faster |
| Prompt processing (prefill) | 2.855 | 2.332 | 1.22x faster |
| Generation (decode) | 1.039 | 1.127 | 0.92x faster |
| LLM total (prefill+decode) | 3.894 | 3.459 | 1.13x faster |
| Time to first token | 2.925 | 2.399 | 1.22x faster |
| End-to-end (total) | 3.960 | 3.523 | 1.12x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 564.5 | 706.0 | 1.25x |
| Decode (generation) t/s | 21.7 | 21.4 | 0.98x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 1607.9 | 1639.6 |
| Completion tokens (mean) | 21.7 | 23.4 |
| Query embedding (s) | 0.013 | 0.010 |
| Retrieval + overhead (s) | 0.056 | 0.056 |
| Match rate (LLM judge) | 90.0% | 90.0% |

### Speedup summary

- Prefill throughput: **1.25x**  (564.5 → 706.0 t/s)
- Decode throughput:  **0.98x**  (21.7 → 21.4 t/s)
- LLM inference latency: **1.13x faster**
- End-to-end latency: **1.12x faster**  (3.96s → 3.52s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **9 (90.0%)** |
| Mean judge score | 0.880 |
| Contains reference (lexical) | 4 (40.0%) |
| Verdicts | correct=9, incorrect=1 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 16296 |
| Tokens/query (prompt / completion) | 1607.9 / 21.7 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 3.960 | 3.828 | 5.621 | 3.118 | 5.621 |
| Time to first token | 2.925 | 2.869 | 3.608 | 2.504 | 3.608 |
| Query embedding | 0.013 | 0.010 | 0.036 | 0.010 | 0.036 |
| Retrieval + overhead | 0.056 | 0.058 | 0.063 | 0.048 | 0.063 |
| Prompt processing (prefill) | 2.855 | 2.810 | 3.535 | 2.436 | 3.535 |
| Generation (decode) | 1.039 | 1.004 | 2.016 | 0.150 | 2.016 |
| LLM total (prefill+decode) | 3.894 | 3.764 | 5.551 | 3.061 | 5.551 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 1607.9 | 1600 | 1934 | 1383 | 1934 |
| Completion tokens | 21.7 | 21 | 41 | 4 | 41 |
| Total tokens | 1629.6 | 1615 | 1975 | 1401 | 1975 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate answer states a different fact, refusing to answer. |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: December 1972.  
- score: 1.00 (correct) — Candidate answer matches reference answer in content.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: Bobby Scott and Bob Russell wrote the song "He Ain't Heavy, He's My Brother".  
- score: 1.00 (correct) — exact match with reference

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is only 1 season of the TV series "The Bastard Executioner".  
- score: 1.00 (correct) — matches reference in content and phrasing

#### Incorrect

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: I don't have information on the winner of last year's NCAA Women's Basketball Championship, as my knowledge cutoff is 2023 and I may not have information on events that occurred after that date.  
- score: 0.00 (incorrect) — Candidate answer states a different fact, refusing to answer.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **9 (90.0%)** |
| Mean judge score | 0.880 |
| Contains reference (lexical) | 4 (40.0%) |
| Verdicts | correct=9, incorrect=1 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 16630 |
| Tokens/query (prompt / completion) | 1639.6 / 23.4 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 3.523 | 3.382 | 4.905 | 2.801 | 4.905 |
| Time to first token | 2.399 | 2.282 | 2.900 | 2.021 | 2.900 |
| Query embedding | 0.010 | 0.010 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.056 | 0.059 | 0.062 | 0.048 | 0.062 |
| Prompt processing (prefill) | 2.332 | 2.224 | 2.828 | 1.952 | 2.828 |
| Generation (decode) | 1.127 | 1.103 | 2.007 | 0.150 | 2.007 |
| LLM total (prefill+decode) | 3.459 | 3.327 | 4.835 | 2.732 | 4.835 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 1639.6 | 1605 | 1947 | 1432 | 1947 |
| Completion tokens | 23.4 | 23 | 41 | 4 | 41 |
| Total tokens | 1663 | 1628 | 1988 | 1450 | 1988 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate answer states a different fact, refusing to provide the answer. |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: December 1972, specifically the Apollo 17 mission which landed on December 11, 1972.  
- score: 1.00 (correct) — Candidate provides specific mission details matching reference dates.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: Bobby Scott and Bob Russell wrote the song "He Ain't Heavy, He's My Brother".  
- score: 1.00 (correct) — exact match with reference

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is only 1 season of the TV series "The Bastard Executioner".  
- score: 1.00 (correct) — matches reference in content and phrasing

#### Incorrect

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: I don't have information on the winner of last year's NCAA Women's Basketball Championship, as my knowledge cutoff is 2023 and I may not have information on events that occurred after that date.  
- score: 0.00 (incorrect) — Candidate answer states a different fact, refusing to provide the answer.


---
_Generated by report_ab.py._