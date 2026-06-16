# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.013 | 0.011 | 1.24x faster |
| Retrieval + overhead | 0.180 | 0.087 | 2.07x faster |
| Prompt processing (prefill) | 55.957 | 4.290 | 13.04x faster |
| Generation (decode) | 0.762 | 0.654 | 1.17x faster |
| LLM total (prefill+decode) | 56.719 | 4.944 | 11.47x faster |
| Time to first token | 56.150 | 4.387 | 12.80x faster |
| End-to-end (total) | 56.889 | 5.036 | 11.30x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 228.7 | 684.9 | 2.99x |
| Decode (generation) t/s | 29.0 | 35.0 | 1.21x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 12535.4 | 2654.6 |
| Completion tokens (mean) | 21.3 | 22.1 |
| Query embedding (s) | 0.013 | 0.011 |
| Retrieval + overhead (s) | 0.180 | 0.087 |
| Match rate (LLM judge) | 80.0% | 90.0% |

### Speedup summary

- Prefill throughput: **2.99x**  (228.7 → 684.9 t/s)
- Decode throughput:  **1.21x**  (29.0 → 35.0 t/s)
- LLM inference latency: **11.47x faster**
- End-to-end latency: **11.30x faster**  (56.89s → 5.04s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **8 (80.0%)** |
| Mean judge score | 0.780 |
| Contains reference (lexical) | 4 (40.0%) |
| Verdicts | correct=8, incorrect=2 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 125567 |
| Tokens/query (prompt / completion) | 12535.4 / 21.3 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 56.889 | 67.444 | 68.570 | 33.503 | 68.570 |
| Time to first token | 56.150 | 66.115 | 67.843 | 33.417 | 67.843 |
| Query embedding | 0.013 | 0.011 | 0.034 | 0.010 | 0.034 |
| Retrieval + overhead | 0.180 | 0.129 | 0.710 | 0.100 | 0.710 |
| Prompt processing (prefill) | 55.957 | 65.975 | 67.700 | 33.301 | 67.700 |
| Generation (decode) | 0.762 | 0.764 | 1.355 | 0.104 | 1.355 |
| LLM total (prefill+decode) | 56.719 | 67.305 | 68.452 | 33.405 | 68.452 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 12535.4 | 13938 | 14342 | 8992 | 14342 |
| Completion tokens | 21.3 | 21 | 36 | 4 | 36 |
| Total tokens | 12556.7 | 13974 | 14362 | 8996 | 14362 |

### Failed / incorrect queries (2)

| Q# | question | verdict | reason |
|---|---|---|---|
| 4 | who won last year's ncaa women's basketball | incorrect | CANDIDATE states a different team won. |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate mentions Selena Gomez, while reference is Rihanna. |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972.  
- score: 1.00 (correct) — Matches reference date and provides additional context.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell.  
- score: 1.00 (correct) — Exact match with reference answers.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is only 1 season of the TV series "The Bastard Executioner".  
- score: 1.00 (correct) — matches reference in content and phrasing

#### Incorrect

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: The UConn Huskies won the 2022 NCAA Women's Division I Basketball Championship.  
- score: 0.00 (incorrect) — CANDIDATE states a different team won.

**Q6: love yourself by justin bieber is about who**  
- expected: _Rihanna_  
- got: "Love Yourself" by Justin Bieber is about his ex-girlfriend Selena Gomez.  
- score: 0.00 (incorrect) — Candidate mentions Selena Gomez, while reference is Rihanna.


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
| Total tokens (sum) | 26767 |
| Tokens/query (prompt / completion) | 2654.6 / 22.1 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 5.036 | 4.046 | 11.769 | 2.367 | 11.769 |
| Time to first token | 4.387 | 2.701 | 11.618 | 1.851 | 11.618 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.087 | 0.053 | 0.354 | 0.048 | 0.354 |
| Prompt processing (prefill) | 4.290 | 2.637 | 11.253 | 1.793 | 11.253 |
| Generation (decode) | 0.654 | 0.665 | 1.347 | 0.092 | 1.347 |
| LLM total (prefill+decode) | 4.944 | 3.984 | 11.417 | 2.311 | 11.417 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 2654.6 | 1977 | 5636 | 1436 | 5636 |
| Completion tokens | 22.1 | 21 | 45 | 4 | 45 |
| Total tokens | 2676.7 | 2022 | 5642 | 1454 | 5642 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate states a different fact than the reference. |

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
- got: The information I have is from 2022, and the UConn Huskies won the 2022 NCAA Women's Division I Basketball Championship. I do not have information on the winner from the most recent year.  
- score: 0.00 (incorrect) — Candidate states a different fact than the reference.


---
_Generated by report_ab.py._