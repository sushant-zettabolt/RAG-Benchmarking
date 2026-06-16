# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.00x faster |
| Retrieval + overhead | 0.099 | 0.100 | 1.00x faster |
| Prompt processing (prefill) | 2.454 | 2.135 | 1.15x faster |
| Generation (decode) | 1.195 | 1.194 | 1.00x faster |
| LLM total (prefill+decode) | 3.650 | 3.328 | 1.10x faster |
| Time to first token | 2.564 | 2.245 | 1.14x faster |
| End-to-end (total) | 3.757 | 3.436 | 1.09x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 866.9 | 998.9 | 1.15x |
| Decode (generation) t/s | 38.7 | 38.8 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 2116.8 | 2118 |
| Completion tokens (mean) | 46.1 | 46.1 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.099 | 0.100 |
| Match rate (LLM judge) | 0% | 0% |

### Speedup summary

- Prefill throughput: **1.15x**  (866.9 → 998.9 t/s)
- Decode throughput:  **1.00x**  (38.7 → 38.8 t/s)
- LLM inference latency: **1.10x faster**
- End-to-end latency: **1.09x faster**  (3.76s → 3.44s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **0 (0%)** |
| Mean judge score | n/a |
| Contains reference (lexical) | 5 (50.0%) |
| Verdicts | unparsed=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 21629 |
| Tokens/query (prompt / completion) | 2116.8 / 46.1 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 3.757 | 3.811 | 4.638 | 2.890 | 4.638 |
| Time to first token | 2.564 | 2.700 | 2.940 | 2.173 | 2.940 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.099 | 0.098 | 0.107 | 0.096 | 0.107 |
| Prompt processing (prefill) | 2.454 | 2.583 | 2.827 | 2.066 | 2.827 |
| Generation (decode) | 1.195 | 1.264 | 2.466 | 0.548 | 2.466 |
| LLM total (prefill+decode) | 3.650 | 3.705 | 4.532 | 2.785 | 4.532 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 2116.8 | 2130 | 2384 | 1860 | 2384 |
| Completion tokens | 46.1 | 49 | 94 | 22 | 94 |
| Total tokens | 2162.9 | 2159 | 2418 | 1954 | 2418 |

### Failed / incorrect queries (10)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | unparsed |  |
| 1 | who wrote he ain't heavy he's my brother lyrics | unparsed |  |
| 2 | how many seasons of the bastard executioner are there | unparsed |  |
| 3 | when did the eagles win last super bowl | unparsed |  |
| 4 | who won last year's ncaa women's basketball | unparsed |  |
| 5 | when did the isle of wight become an island | unparsed |  |
| 6 | love yourself by justin bieber is about who | unparsed |  |
| 7 | who was the ruler of england in 1616 | unparsed |  |
| 8 | what is the hot coffee mod in san andreas | unparsed |  |
| 9 | what is the maximum data rate for the 802.11a standard select one | unparsed |  |

### Example answers

#### Correct

_No correct examples._

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was December 19, 1972, during the Apollo 17 mission.  
- score: n/a (unparsed) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: Bobby Scott and Bob Russell wrote the song "He Ain't Heavy, He's My Brother".  
- score: n/a (unparsed) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is no TV show called "The Bastard Executioner". However, there was a TV series called "The Bastard Executioner" that aired on FX in 2015, but it only lasted for 1 season.  
- score: n/a (unparsed) — 


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **0 (0%)** |
| Mean judge score | n/a |
| Contains reference (lexical) | 5 (50.0%) |
| Verdicts | unparsed=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 21641 |
| Tokens/query (prompt / completion) | 2118 / 46.1 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 3.436 | 3.435 | 4.346 | 2.588 | 4.346 |
| Time to first token | 2.245 | 2.382 | 2.580 | 1.888 | 2.580 |
| Query embedding | 0.011 | 0.010 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.100 | 0.099 | 0.107 | 0.096 | 0.107 |
| Prompt processing (prefill) | 2.135 | 2.264 | 2.468 | 1.781 | 2.468 |
| Generation (decode) | 1.194 | 1.301 | 2.460 | 0.547 | 2.460 |
| LLM total (prefill+decode) | 3.328 | 3.326 | 4.241 | 2.483 | 4.241 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 2118 | 2130 | 2384 | 1859 | 2384 |
| Completion tokens | 46.1 | 49 | 94 | 22 | 94 |
| Total tokens | 2164.1 | 2159 | 2418 | 1953 | 2418 |

### Failed / incorrect queries (10)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | unparsed |  |
| 1 | who wrote he ain't heavy he's my brother lyrics | unparsed |  |
| 2 | how many seasons of the bastard executioner are there | unparsed |  |
| 3 | when did the eagles win last super bowl | unparsed |  |
| 4 | who won last year's ncaa women's basketball | unparsed |  |
| 5 | when did the isle of wight become an island | unparsed |  |
| 6 | love yourself by justin bieber is about who | unparsed |  |
| 7 | who was the ruler of england in 1616 | unparsed |  |
| 8 | what is the hot coffee mod in san andreas | unparsed |  |
| 9 | what is the maximum data rate for the 802.11a standard select one | unparsed |  |

### Example answers

#### Correct

_No correct examples._

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was December 19, 1972, during the Apollo 17 mission.  
- score: n/a (unparsed) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: Bobby Scott and Bob Russell wrote the song "He Ain't Heavy, He's My Brother".  
- score: n/a (unparsed) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is no TV show called "The Bastard Executioner". However, there was a TV series called "The Bastard Executioner" that aired on FX in 2015, but it only lasted for 1 season.  
- score: n/a (unparsed) — 


---
_Generated by report_ab.py._