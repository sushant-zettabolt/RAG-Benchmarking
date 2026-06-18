# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.012 | 0.92x |
| Retrieval + overhead | 0.073 | 0.065 | 1.13x |
| Prompt processing (prefill) | 1.804 | 1.035 | 1.74x |
| Generation (decode) | 3.924 | 3.925 | 1.000x |
| LLM total (prefill+decode) | 5.728 | 4.961 | 1.15x |
| Time to first token | 1.888 | 1.112 | 1.70x |
| End-to-end (total) | 5.812 | 5.038 | 1.15x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 457.9 | 796.8 | 1.74x |
| Decode (generation) t/s | 32.6 | 32.6 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 824.6 | 824.6 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.011 | 0.012 |
| Retrieval + overhead (s) | 0.073 | 0.065 |
| Match rate (LLM judge) | 40.0% | 80.0% |
| Contains reference (lexical) | 80.0% | 100.0% |

### Speedup summary

- Prefill throughput: **1.74x**  (457.9 → 796.8 t/s)
- Decode throughput:  **1.00x**  (32.6 → 32.6 t/s)
- LLM inference latency: **1.15x**
- End-to-end latency: **1.15x**  (5.81s → 5.04s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 5 |
| Succeeded | 5 |
| Errored | 0 |
| **Matched (LLM judge)** | **2 (40.0%)** |
| Mean judge score | 0.400 |
| Contains reference (lexical) | 4 (80.0%) |
| Verdicts | incorrect=3, correct=2 |
| Documents ingested | 500/500 |
| Answerable questions (corpus) | 85 |
| Total tokens (sum) | 4763 |
| Tokens/query (prompt / completion) | 824.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 5.812 | 5.657 | 6.713 | 5.308 | 6.713 |
| Time to first token | 1.888 | 1.769 | 2.775 | 1.395 | 2.775 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.073 | 0.077 | 0.098 | 0.039 | 0.098 |
| Prompt processing (prefill) | 1.804 | 1.661 | 2.691 | 1.307 | 2.691 |
| Generation (decode) | 3.924 | 3.936 | 3.945 | 3.887 | 3.945 |
| LLM total (prefill+decode) | 5.728 | 5.583 | 6.630 | 5.219 | 6.630 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 824.6 | 770 | 1213 | 600 | 1213 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 952.6 | 898 | 1341 | 728 | 1341 |

### Failed / incorrect queries (3)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | incorrect | Provides the wrong specific date (December 19, 1972) instead of the correct date |
| 1 | who wrote he ain't heavy he's my brother lyrics | incorrect | The answer gives wrong songwriters (Bob Russell and Carl Sigman) instead of the  |
| 3 | when did the eagles win last super bowl | incorrect | Candidate says the Eagles won in 2018, but reference states 2017. |

### Example answers

#### Correct

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: There is no information given about the show "The Bastard Executioner" within the given context. However, according to external knowledge, The Bastard Executioner is a historical drama television series created by Kurt Sutter. The show aired on FX from September 15, 2015, to November 17, 2015. There is only one season of the show. It was cancelled after one season due to low ratings.  9 episodes were released.  There was initially a second season planned but the show was cancelled before it was produced.  Therefore there is only 1 season of the show.  If you need  
- score: 1.00 (correct) — The candidate correctly states there is only one season, matching the reference answer.

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: I don't have information about last year's NCAA women's basketball championship. However, I can tell you that in 2023, the South Carolina Gamecocks won the women's NCAA basketball championship. They defeated the UConn Huskies 86-75 in the championship game. But information before 2023 is not available. I recommend checking the latest news for last year's championship. 

If you are looking for a different year, I can try to help you with that. Please let me know the year you are looking for. 

If you are looking for information from 2022, the South Carolina Gamecocks  
- score: 1.00 (correct) — Candidate states South Carolina won, matching the reference answer.

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt, and it marked the sixth and final manned mission to the moon as part of the United States' Apollo program. Eugene Cernan was the last person to walk on the moon, and he stepped off the lunar surface for the final time on December 19, 1972. Since then, there have been no manned missions to the moon, although there are currently plans to return humans to the moon in the near future as part of NASA  
- score: 0.00 (incorrect) — Provides the wrong specific date (December 19, 1972) instead of the correct date (December 14, 1972).

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: I can't verify who wrote "He Ain't Heavy, He's My Brother" lyrics. The information isn't available in the given contexts. However, I can provide you with relevant information. 

"He Ain't Heavy, He's My Brother" is a popular song written by Bob Russell and Carl Sigman, and recorded by several artists including the Hollies and Neil Diamond. The song was originally written in 1969 for the film "The Christmas Tree" but was not used. It was later recorded by the Hollies in 1969 and became a big hit. The song's lyrics are based on a phrase coined by a  
- score: 0.00 (incorrect) — The answer gives wrong songwriters (Bob Russell and Carl Sigman) instead of the correct Bobby Scott and Bob Russell.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won their last Super Bowl in 2018, which was Super Bowl LII (52), defeating the New England Patriots 41-33 on February 4, 2018, at U.S. Bank Stadium in Minneapolis, Minnesota. This was their first Super Bowl win in franchise history. 

However, the question you initially asked was about the 2004 season. The Eagles did not win the Super Bowl in 2004, but they did make it to Super Bowl XXXIX, where they lost to the New England Patriots 24-21 on February 6, 2005. 

If you are asking  
- score: 0.00 (incorrect) — Candidate says the Eagles won in 2018, but reference states 2017.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 5 |
| Succeeded | 5 |
| Errored | 0 |
| **Matched (LLM judge)** | **4 (80.0%)** |
| Mean judge score | 0.680 |
| Contains reference (lexical) | 5 (100.0%) |
| Verdicts | correct=2, partial=2, incorrect=1 |
| Documents ingested | 500/500 |
| Answerable questions (corpus) | 85 |
| Total tokens (sum) | 4763 |
| Tokens/query (prompt / completion) | 824.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 5.038 | 4.938 | 5.595 | 4.809 | 5.595 |
| Time to first token | 1.112 | 1.035 | 1.629 | 0.902 | 1.629 |
| Query embedding | 0.012 | 0.011 | 0.014 | 0.010 | 0.014 |
| Retrieval + overhead | 0.065 | 0.069 | 0.087 | 0.031 | 0.087 |
| Prompt processing (prefill) | 1.035 | 0.939 | 1.553 | 0.821 | 1.553 |
| Generation (decode) | 3.925 | 3.913 | 3.966 | 3.900 | 3.966 |
| LLM total (prefill+decode) | 4.961 | 4.855 | 5.519 | 4.726 | 5.519 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 824.6 | 770 | 1213 | 600 | 1213 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 952.6 | 898 | 1341 | 728 | 1341 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 4 | who won last year's ncaa women's basketball | incorrect | The candidate does not state South Carolina as the winner and fails to give a cl |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt. They landed on the moon's surface on December 11, 1972, and spent about 75 hours there, conducting scientific experiments and exploring the lunar terrain. Eugene Cernan was the last person to walk on the moon, leaving the surface on December 14, 1972. Since then, there has been no manned mission to the moon. However, several unmanned spacecraft have visited the moon, including NASA's Lunar Reconnaissance  
- score: 1.00 (correct) — Provides the same date (December 1972, specifically Dec 14) as the reference, with additional accurate context.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bob Russell and Bobby Scott. However, it was made famous by the 1969 version by the Welsh-English rock band The Hollies, and later by The Beatles, who were also inspired by the song. 

The song is based on a poem by Albert E. Brumley titled "He's My Brother" from 1913 and was later modified to "He Ain't Heavy, He's My Brother" by Bob Russell in 1962. 

The song was inspired by a poem from 1913 by Albert E. Brumley  
- score: 0.70 (partial) — Correctly names Bob Russell and Bobby Scott as writers, but adds inaccurate extra details.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information on the number of seasons of "The Bastard Executioner". It's possible that it may be a lesser-known or older series. However, I do know that there was a television series called "The Bastard Executioner" that aired on FX in 2015. It was a historical drama series that lasted for one season with 10 episodes. It premiered on September 15, 2015, and the final episode aired on November 17, 2015. If you have any more information about the series you are referring to, I may be able to help further. However, based on  
- score: 1.00 (correct) — The answer states the series had one season, matching the reference.

#### Incorrect

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: Since the information provided is from 2014 and earlier, I'll need a bit more context to give a precise answer. However, considering the information from [CONTEXT 2] and [CONTEXT 4], the last information provided is from 2014, and it mentions UConn winning the championship that year with a record 40-0. 

To find the winner of last year's NCAA women's basketball championship, I would need more recent information. However, based on my general knowledge, here are some recent winners:

- 2021: Stanford Cardinal
- 2022: South Carolina Gamecocks
- 202  
- score: 0.00 (incorrect) — The candidate does not state South Carolina as the winner and fails to give a clear answer to the question.


---
_Generated by report_ab.py._