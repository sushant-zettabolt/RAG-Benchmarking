# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.00x faster |
| Retrieval + overhead | 0.076 | 0.085 | 0.89x faster |
| Prompt processing (prefill) | 15.058 | 14.503 | 1.04x faster |
| Generation (decode) | 7.154 | 10.376 | 0.69x faster |
| LLM total (prefill+decode) | 22.212 | 24.879 | 0.89x faster |
| Time to first token | 15.144 | 14.598 | 1.04x faster |
| End-to-end (total) | 22.297 | 24.973 | 0.89x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 156.5 | 220.0 | 1.41x |
| Decode (generation) t/s | 12.3 | 12.1 | 0.98x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 2354.6 | 3182.9 |
| Completion tokens (mean) | 87.8 | 125.5 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.076 | 0.085 |
| Match rate (LLM judge) | 90.0% | 90.0% |

### Speedup summary

- Prefill throughput: **1.41x**  (156.5 → 220.0 t/s)
- Decode throughput:  **0.98x**  (12.3 → 12.1 t/s)
- LLM inference latency: **0.89x faster**
- End-to-end latency: **0.89x faster**  (22.30s → 24.97s)

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
| Contains reference (lexical) | 5 (50.0%) |
| Verdicts | correct=8, partial=1, incorrect=1 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 24424 |
| Tokens/query (prompt / completion) | 2354.6 / 87.8 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 22.297 | 23.905 | 27.116 | 16.275 | 27.116 |
| Time to first token | 15.144 | 15.257 | 18.139 | 12.818 | 18.139 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.076 | 0.069 | 0.151 | 0.063 | 0.151 |
| Prompt processing (prefill) | 15.058 | 15.175 | 18.057 | 12.745 | 18.057 |
| Generation (decode) | 7.154 | 7.432 | 13.781 | 2.078 | 13.781 |
| LLM total (prefill+decode) | 22.212 | 23.825 | 27.039 | 16.204 | 27.039 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 2354.6 | 2373 | 2772 | 2034 | 2772 |
| Completion tokens | 87.8 | 91 | 169 | 26 | 169 |
| Total tokens | 2442.4 | 2509 | 2843 | 2125 | 2843 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 8 | what is the hot coffee mod in san andreas | incorrect | Candidate gives incorrect information about the mod's content. |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was December 19, 1972, during the Apollo 17 mission.  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell.  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is only one season of the TV show "The Bastard Executioner" which aired in 2015.  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

#### Incorrect

**Q8: what is the hot coffee mod in san andreas**  
- expected: _a normally inaccessible mini-game_  
- got: The "Hot Coffee" mod in Grand Theft Auto: San Andreas is a modification that allows players to engage in explicit sexual activity in the game. The mod was created by a user named "Patrick W. Clark" and was first released in 2004.

I apologize, I made a mistake in my previous response, the mod allows players to engage in explicit sexual activity in the game, not to have a cup of coffee. The name of the mod is a reference to a euphemism for sexual activity.  
- score: 0.00 (incorrect) — Candidate gives incorrect information about the mod's content.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **9 (90.0%)** |
| Mean judge score | 0.880 |
| Contains reference (lexical) | 5 (50.0%) |
| Verdicts | correct=8, partial=1, incorrect=1 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 33084 |
| Tokens/query (prompt / completion) | 3182.9 / 125.5 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 24.973 | 25.916 | 30.118 | 21.716 | 30.118 |
| Time to first token | 14.598 | 15.155 | 17.875 | 12.858 | 17.875 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.085 | 0.075 | 0.187 | 0.070 | 0.187 |
| Prompt processing (prefill) | 14.503 | 15.068 | 17.787 | 12.777 | 17.787 |
| Generation (decode) | 10.376 | 9.356 | 16.682 | 8.459 | 16.682 |
| LLM total (prefill+decode) | 24.879 | 25.834 | 30.036 | 21.636 | 30.036 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3182.9 | 3284 | 3706 | 2879 | 3706 |
| Completion tokens | 125.5 | 114 | 201 | 102 | 201 |
| Total tokens | 3308.4 | 3422 | 3812 | 2987 | 3812 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 8 | what is the hot coffee mod in san andreas | incorrect | Candidate states mod allows explicit sexual activity, not a mini-game. |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was during the Apollo 17 mission, on December 19, 1972.

I apologize, I made a mistake in my previous response, I assure you that I am a machine learning model and my mistakes are not intentional. I apologize for any confusion my previous response may have caused, I assure you that I will strive to provide accurate and helpful responses in the future.

Please let me know if there is anything else I can help you with.  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell.

I apologize, I made a mistake in my previous response, I assure you that I am a machine learning model and my mistakes are not intentional. I apologize for any confusion my previous response may have caused, I assure you that I will strive to provide accurate and helpful responses in the future.

Please let me know if there is anything else I can help you with.  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is only one season of the TV show "The Bastard Executioner" which aired in 2015.

I apologize, I made a mistake in my previous response, I assure you that I am a machine learning model and my mistakes are not intentional. I apologize for any confusion my previous response may have caused, I assure you that I will strive to provide accurate and helpful responses in the future.

Please let me know if there is anything else I can help you with.  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

#### Incorrect

**Q8: what is the hot coffee mod in san andreas**  
- expected: _a normally inaccessible mini-game_  
- got: The "Hot Coffee" mod in Grand Theft Auto: San Andreas is a modification that allows players to engage in explicit sexual activity in the game. The mod was created by a user named "Patrick W. Clark" and was first released in 2004.

I apologize, I made a mistake in my previous response, I assure you that I am a machine learning model and my mistakes are not intentional. I apologize for any confusion my previous response may have caused, I assure you that I will strive to provide accurate and helpful responses in the future.

Please let me know if there is anything else I can help you with.  
- score: 0.00 (incorrect) — Candidate states mod allows explicit sexual activity, not a mini-game.


---
_Generated by report_ab.py._