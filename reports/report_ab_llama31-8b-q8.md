# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.020 | 0.011 | n/a (same binary) |
| Retrieval + overhead | 0.072 | 0.064 | 1.12x |
| Prompt processing (prefill) | 1.778 | 1.029 | 1.73x |
| Generation (decode) | 3.913 | 3.925 | 0.997x |
| LLM total (prefill+decode) | 5.691 | 4.954 | 1.15x |
| Time to first token | 1.870 | 1.104 | 1.69x |
| End-to-end (total) | 5.782 | 5.029 | 1.15x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 465.2 | 802.3 | 1.72x |
| Decode (generation) t/s | 32.7 | 32.6 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 824.6 | 824.6 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.020 | 0.011 |
| Retrieval + overhead (s) | 0.072 | 0.064 |
| Match rate (LLM judge) | 80.0% | 100.0% |
| Contains reference (lexical) | 100.0% | 80.0% |

### Speedup summary

- Prefill throughput: **1.72x**  (465.2 → 802.3 t/s)
- Decode throughput:  **1.00x**  (32.7 → 32.6 t/s)
- LLM inference latency: **1.15x**
- End-to-end latency: **1.15x**  (5.78s → 5.03s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 5 |
| Succeeded | 5 |
| Errored | 0 |
| **Matched (LLM judge)** | **4 (80.0%)** |
| Mean judge score | 0.700 |
| Contains reference (lexical) | 5 (100.0%) |
| Verdicts | correct=3, incorrect=1, partial=1 |
| Documents ingested | 500/500 |
| Answerable questions (corpus) | 85 |
| Total tokens (sum) | 4763 |
| Tokens/query (prompt / completion) | 824.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 5.782 | 5.650 | 6.712 | 5.326 | 6.712 |
| Time to first token | 1.870 | 1.736 | 2.796 | 1.433 | 2.796 |
| Query embedding | 0.020 | 0.012 | 0.038 | 0.011 | 0.038 |
| Retrieval + overhead | 0.072 | 0.076 | 0.095 | 0.036 | 0.095 |
| Prompt processing (prefill) | 1.778 | 1.629 | 2.696 | 1.317 | 2.696 |
| Generation (decode) | 3.913 | 3.917 | 3.922 | 3.892 | 3.922 |
| LLM total (prefill+decode) | 5.691 | 5.543 | 6.613 | 5.209 | 6.613 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 824.6 | 770 | 1213 | 600 | 1213 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 952.6 | 898 | 1341 | 728 | 1341 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 3 | when did the eagles win last super bowl | incorrect | Candidate states the win occurred in 2018, conflicting with reference answer of  |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt, and they spent three days on the moon's surface from December 11 to 14, 1972. 

Eugene Cernan was the last person to walk on the moon, and he stepped off the lunar module Challenger and onto the moon's surface on December 11, 1972. 

Since then, there have been no manned missions to the moon, although several unmanned spacecraft have visited the moon as part of various  
- score: 1.00 (correct) — Provides the same date (December 1972) for the last human presence on the Moon, matching the reference.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. However, the song was inspired by a poem by Russell. The original title of the poem was "He Ain't Heavy" but a phrase was added to it later by Scott. The song was originally recorded by Kelly Gordon in 1969, but the most well-known version was recorded by The Hollies in 1969. 

The lyrics are also often attributed to a phrase which is said to have been spoken by a boy carrying his disabled brother across a bridge. The phrase supposedly went like this, "He ain't heavy  
- score: 1.00 (correct) — Correctly states the song was written by Bobby Scott and Bob Russell, matching the reference.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information about a TV series called "The Bastard Executioner". However, I did find information about a TV series called "The Bastard Executioner" was a short-lived American period drama television series that aired on FX for one season from September 15, 2015 to November 18, 2015. 

Therefore, there is only one season of "The Bastard Executioner". However, since it only had one season and the question does not specify if it should be answered with the number of seasons, or the number of seasons with episodes, I answered the former. If you're asking for  
- score: 1.00 (correct) — The candidate correctly states there is only one season, matching the reference answer.

#### Incorrect

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Eagles won Super Bowl LII (52) on February 4, 2018. They defeated the New England Patriots 41-33. This was their first Super Bowl championship in franchise history. It is also mentioned in context 0 that this season was considered the franchise's most successful until their Super Bowl LII-winning 2017 season, but the game took place in 2018, not in 2017. The 2017 season is what led to the Eagles winning their first Super Bowl in 2018. The 2004 season was the Eagles' most successful season before the 2017 season, and  
- score: 0.00 (incorrect) — Candidate states the win occurred in 2018, conflicting with reference answer of 2017


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 5 |
| Succeeded | 5 |
| Errored | 0 |
| **Matched (LLM judge)** | **5 (100.0%)** |
| Mean judge score | 1.000 |
| Contains reference (lexical) | 4 (80.0%) |
| Verdicts | correct=5 |
| Documents ingested | 500/500 |
| Answerable questions (corpus) | 85 |
| Total tokens (sum) | 4763 |
| Tokens/query (prompt / completion) | 824.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 5.029 | 4.956 | 5.556 | 4.798 | 5.556 |
| Time to first token | 1.104 | 1.030 | 1.627 | 0.880 | 1.627 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.011 | 0.011 |
| Retrieval + overhead | 0.064 | 0.069 | 0.088 | 0.030 | 0.088 |
| Prompt processing (prefill) | 1.029 | 0.937 | 1.552 | 0.801 | 1.552 |
| Generation (decode) | 3.925 | 3.929 | 3.930 | 3.916 | 3.930 |
| LLM total (prefill+decode) | 4.954 | 4.856 | 5.481 | 4.717 | 5.481 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 824.6 | 770 | 1213 | 600 | 1213 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 952.6 | 898 | 1341 | 728 | 1341 |

### Failed / incorrect queries (0)

_None — all queries matched._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt. Eugene Cernan and Harrison Schmitt spent three days on the lunar surface, while Ronald Evans remained in orbit around the moon in the command module. The mission landed on the moon on December 11, 1972, and the astronauts returned to Earth on December 19, 1972. Since then, there have been no manned missions to the moon, although several unmanned spacecraft have visited the lunar surface. NASA plans to return humans  
- score: 1.00 (correct) — Provides the same month and year (December 1972) as the reference, matching the factual answer.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The lyrics were actually inspired by a 19th-century song called "Pauper's Lament" and were rewritten by Russell in 1969. However, the most well-known version of the song, which was recorded by The Hollies in 1969, was written by Bobby Scott and Bob Russell, with Russell getting credit for the lyrics. The song became an anthem of the 1970s, and its message of supporting one another has endured as a popular phrase. 

The song was first recorded by Kelly Gordon in  
- score: 1.00 (correct) — Correctly states that Bobby Scott and Bob Russell wrote the lyrics

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information on a TV series titled "The Bastard Executioner." However, there is a TV series titled "The Bastard Executioner" that aired on FX from September 15, 2015, to November 18, 2015, for one season of 10 episodes. It was cancelled after the first season. 

If you are referring to this series, the answer is 1. If you are referring to a different series, please provide more information. I will be happy to try and help.  If you are referring to a different series, please provide more information. I will be happy  
- score: 1.00 (correct) — The candidate states there is one season, matching the reference answer.

#### Incorrect

_No incorrect examples._


---
_Generated by report_ab.py._