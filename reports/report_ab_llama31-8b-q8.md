# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

> ⚠️ **Latency comparison not valid:** baseline and zendnn processed different workloads (prompt tokens 4612 vs 4612, completion tokens 38.8 vs 47.2). Per-stage latency scales with token count, so the latency speedups below are apples-to-oranges. Compare the per-token throughput table instead, and check why the runs diverged (see Sanity / Evaluation detail — likely a broken job).

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.012 | 1.04x |
| Retrieval + overhead | 0.239 | 0.237 | 1.01x |
| Prompt processing (prefill) | 13.244 | 8.840 | 1.50x |
| Generation (decode) | 1.232 | 1.556 | 1.26x |
| LLM total (prefill+decode) | 14.476 | 10.397 | 1.39x |
| Time to first token | 13.494 | 9.089 | 1.48x |
| End-to-end (total) | 14.719 | 10.639 | 1.38x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 348.6 | 522.6 | 1.50x |
| Decode (generation) t/s | 31.8 | 30.8 | 0.97x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4611.8 | 4611.8 |
| Completion tokens (mean) | 38.8 | 47.2 |
| Query embedding (s) | 0.011 | 0.012 |
| Retrieval + overhead (s) | 0.239 | 0.237 |
| Match rate (LLM judge) | 40.0% | 40.0% |
| Contains reference (lexical) | 60.0% | 60.0% |

### Speedup summary

- Prefill throughput: **1.50x**  (348.6 → 522.6 t/s)
- Decode throughput:  **0.97x**  (31.8 → 30.8 t/s)
- LLM inference latency: **1.39x**
- End-to-end latency: **1.38x**  (14.72s → 10.64s)

_Note: throughput (t/s) is the only valid comparison here — the two runs processed different token counts, so latency speedups reflect workload size, not backend speed._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 5 |
| Succeeded | 5 |
| Errored | 0 |
| **Matched (LLM judge)** | **2 (40.0%)** |
| Mean judge score | 0.400 |
| Contains reference (lexical) | 3 (60.0%) |
| Verdicts | correct=2, incorrect=3 |
| Documents ingested | 500/500 |
| Answerable questions (corpus) | 85 |
| Total tokens (sum) | 23253 |
| Tokens/query (prompt / completion) | 4611.8 / 38.8 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 14.719 | 14.729 | 16.638 | 12.736 | 16.638 |
| Time to first token | 13.494 | 14.020 | 14.390 | 12.191 | 14.390 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.011 | 0.011 |
| Retrieval + overhead | 0.239 | 0.271 | 0.299 | 0.087 | 0.299 |
| Prompt processing (prefill) | 13.244 | 13.709 | 14.292 | 11.899 | 14.292 |
| Generation (decode) | 1.232 | 0.916 | 2.255 | 0.551 | 2.255 |
| LLM total (prefill+decode) | 14.476 | 14.426 | 16.547 | 12.450 | 16.547 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4611.8 | 4692 | 4937 | 4219 | 4937 |
| Completion tokens | 38.8 | 29 | 70 | 18 | 70 |
| Total tokens | 4650.6 | 4715 | 5007 | 4237 | 5007 |

### Failed / incorrect queries (3)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | The answer does not state the correct number of seasons (one) and instead claims |
| 3 | when did the eagles win last super bowl | incorrect | Candidate says the win was in 2018, but reference states 2017 |
| 4 | who won last year's ncaa women's basketball | incorrect | The candidate fails to answer and incorrectly claims lack of information, not ma |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt. They landed on the moon's surface on December 11, 1972, and spent three days conducting scientific experiments and exploring the lunar terrain.  
- score: 1.00 (correct) — Candidate correctly states the last moon visit was in December 1972, matching the reference.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell.  
- score: 1.00 (correct) — Provides the same authors (Bobby Scott and Bob Russell) as the reference.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is no information provided in the given contexts about "The Bastard Executioner".  
- score: 0.00 (incorrect) — The answer does not state the correct number of seasons (one) and instead claims no information is available.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Eagles won their last Super Bowl in Super Bowl LII (52), which took place on February 4, 2018. They defeated the New England Patriots with a score of 41-33. This was their first Super Bowl win in franchise history.  
- score: 0.00 (incorrect) — Candidate says the win was in 2018, but reference states 2017

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: Unfortunately, I don't have information on the 2025 NCAA women's basketball championship as my knowledge only goes up to 2023.  
- score: 0.00 (incorrect) — The candidate fails to answer and incorrectly claims lack of information, not matching the reference answer.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 5 |
| Succeeded | 5 |
| Errored | 0 |
| **Matched (LLM judge)** | **2 (40.0%)** |
| Mean judge score | 0.320 |
| Contains reference (lexical) | 3 (60.0%) |
| Verdicts | partial=1, correct=1, incorrect=3 |
| Documents ingested | 500/500 |
| Answerable questions (corpus) | 85 |
| Total tokens (sum) | 23295 |
| Tokens/query (prompt / completion) | 4611.8 / 47.2 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 10.639 | 10.307 | 12.839 | 8.704 | 12.839 |
| Time to first token | 9.089 | 9.581 | 9.656 | 8.213 | 9.656 |
| Query embedding | 0.012 | 0.011 | 0.013 | 0.011 | 0.013 |
| Retrieval + overhead | 0.237 | 0.266 | 0.297 | 0.083 | 0.297 |
| Prompt processing (prefill) | 8.840 | 9.272 | 9.559 | 7.925 | 9.559 |
| Generation (decode) | 1.556 | 1.256 | 3.190 | 0.497 | 3.190 |
| LLM total (prefill+decode) | 10.397 | 10.007 | 12.749 | 8.422 | 12.749 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4611.8 | 4692 | 4937 | 4219 | 4937 |
| Completion tokens | 47.2 | 38 | 95 | 16 | 95 |
| Total tokens | 4659 | 4715 | 5032 | 4235 | 5032 |

### Failed / incorrect queries (3)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | The candidate does not provide the answer and claims inability to identify the s |
| 3 | when did the eagles win last super bowl | incorrect | Candidate gives 2018 date, but reference answer is 2017 |
| 4 | who won last year's ncaa women's basketball | incorrect | The answer does not give South Carolina and gives unrelated information about 20 |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt. They spent three days on the moon's surface, conducting scientific experiments and exploring the lunar terrain. Eugene Cernan was the last person to walk on the moon, stepping off the lunar module Challenger onto the moon's surface on December 11, 1972.  
- score: 0.60 (partial) — Provides the correct month/year (December 1972) but gives an incorrect specific date (December 11) for the last moonwalk.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell.  
- score: 1.00 (correct) — Candidate correctly states Bobby Scott and Bob Russell wrote the song, matching the reference.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I am unable to identify the Bastard Executioner in the given text.  
- score: 0.00 (incorrect) — The candidate does not provide the answer and claims inability to identify the show.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won their last Super Bowl in Super Bowl LII (52) on February 4, 2018, when they defeated the New England Patriots 41-33.  
- score: 0.00 (incorrect) — Candidate gives 2018 date, but reference answer is 2017

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: The information provided does not explicitly state who won the NCAA women's basketball championship from the last year mentioned which would be 2015, 2016, 2017, 2018 however it does provide information about the team that won the championship in 2016 which was the UConn Huskies.  
- score: 0.00 (incorrect) — The answer does not give South Carolina and gives unrelated information about 2016 UConn.


---
_Generated by report_ab.py._