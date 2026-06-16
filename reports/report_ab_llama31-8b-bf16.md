# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.00x slower |
| Retrieval + overhead | 0.199 | 0.195 | 1.02x faster |
| Prompt processing (prefill) | 7.760 | 6.373 | 1.22x faster |
| Generation (decode) | 6.534 | 6.528 | 1.00x faster |
| LLM total (prefill+decode) | 14.294 | 12.902 | 1.11x faster |
| Time to first token | 7.969 | 6.579 | 1.21x faster |
| End-to-end (total) | 14.499 | 13.102 | 1.11x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 461.2 | 562.5 | 1.22x |
| Decode (generation) t/s | 19.6 | 19.6 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3561.6 | 3561.6 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.199 | 0.195 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 50.0% | 60.0% |

### Speedup summary

- Prefill throughput: **1.22x**  (461.2 → 562.5 t/s)
- Decode throughput:  **1.00x**  (19.6 → 19.6 t/s)
- LLM inference latency: **1.11x faster**
- End-to-end latency: **1.11x faster**  (14.50s → 13.10s)

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
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 36896 |
| Tokens/query (prompt / completion) | 3561.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 14.499 | 14.413 | 16.850 | 12.892 | 16.850 |
| Time to first token | 7.969 | 7.846 | 10.268 | 6.396 | 10.268 |
| Query embedding | 0.011 | 0.011 | 0.012 | 0.010 | 0.012 |
| Retrieval + overhead | 0.199 | 0.215 | 0.242 | 0.060 | 0.242 |
| Prompt processing (prefill) | 7.760 | 7.774 | 10.043 | 6.187 | 10.043 |
| Generation (decode) | 6.534 | 6.538 | 6.588 | 6.484 | 6.588 |
| LLM total (prefill+decode) | 14.294 | 14.302 | 16.631 | 12.688 | 16.631 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3561.6 | 3635 | 4276 | 3071 | 4276 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3689.6 | 3763 | 4404 | 3199 | 4404 |

### Failed / incorrect queries (10)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | None |  |
| 1 | who wrote he ain't heavy he's my brother lyrics | None |  |
| 2 | how many seasons of the bastard executioner are there | None |  |
| 3 | when did the eagles win last super bowl | None |  |
| 4 | who won last year's ncaa women's basketball | None |  |
| 5 | when did the isle of wight become an island | None |  |
| 6 | love yourself by justin bieber is about who | None |  |
| 7 | who was the ruler of england in 1616 | None |  |
| 8 | what is the hot coffee mod in san andreas | None |  |
| 9 | what is the maximum data rate for the 802.11a standard select one | None |  |

### Example answers

#### Correct

_No correct examples._

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt. They launched on December 7, 1972, and landed on the moon's surface on December 11, 1972. The mission lasted for 12 days, and the astronauts spent three days on the moon's surface, conducting scientific experiments and collecting samples.

Eugene Cernan, the mission commander, was the last person to walk on the moon. He stepped off the lunar module Challenger and onto the moon's surface  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. However, the most well-known version of the song was recorded by The Hollies in 1969, but it was previously recorded by Kelly Gordon in 1969 and by the Welsh singer and actor, Andy Williams' friend, and also by Neil Sedaka, but it was Kelly Gordon's version that first charted in 1969,  before The Hollies. However, the song's most popular version was recorded by The Hollies in 1969. The song was also recorded by Kelly Gordon and Andy Williams,  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I am unable to verify how many seasons of the Bastard Executioner are in the Chicago Fire universe. However, I can tell you that The Bastard Executioner is an American historical drama television series that aired on FX, not as part of the Chicago Fire franchise. There is one season of the Bastard Executioner, which premiered on September 15, 2015, and the final episode aired on November 17, 2015. It was canceled after one season. The show is a historical drama series that explores the lives of a 14th-century Welsh knight who seeks revenge against the English king who killed his family.  
- score: n/a (None) — 


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **0 (0%)** |
| Mean judge score | n/a |
| Contains reference (lexical) | 6 (60.0%) |
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 36896 |
| Tokens/query (prompt / completion) | 3561.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 13.102 | 12.935 | 15.183 | 11.698 | 15.183 |
| Time to first token | 6.579 | 6.413 | 8.600 | 5.206 | 8.600 |
| Query embedding | 0.011 | 0.011 | 0.012 | 0.010 | 0.012 |
| Retrieval + overhead | 0.195 | 0.214 | 0.240 | 0.057 | 0.240 |
| Prompt processing (prefill) | 6.373 | 6.345 | 8.379 | 4.999 | 8.379 |
| Generation (decode) | 6.528 | 6.527 | 6.590 | 6.495 | 6.590 |
| LLM total (prefill+decode) | 12.902 | 12.841 | 14.969 | 11.496 | 14.969 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3561.6 | 3635 | 4276 | 3071 | 4276 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3689.6 | 3763 | 4404 | 3199 | 4404 |

### Failed / incorrect queries (10)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | None |  |
| 1 | who wrote he ain't heavy he's my brother lyrics | None |  |
| 2 | how many seasons of the bastard executioner are there | None |  |
| 3 | when did the eagles win last super bowl | None |  |
| 4 | who won last year's ncaa women's basketball | None |  |
| 5 | when did the isle of wight become an island | None |  |
| 6 | love yourself by justin bieber is about who | None |  |
| 7 | who was the ruler of england in 1616 | None |  |
| 8 | what is the hot coffee mod in san andreas | None |  |
| 9 | what is the maximum data rate for the 802.11a standard select one | None |  |

### Example answers

#### Correct

_No correct examples._

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: Unfortunately, there is no information provided in the given context about the last time anyone was on the moon. The context includes a variety of topics, including the Houston Astros, music, politics, and history, but it does not mention space exploration or the moon. If you would like to know the last time someone visited the moon, I can provide that information for you. The last time humans visited the moon was during the Apollo 17 mission in December 1972. Since then, there have been no manned missions to the moon. However, there are current plans to return humans to the moon in the near future, with NASA's Artem  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. However, the most well-known version of the song was recorded by The Hollies in 1969, and their version became a huge hit, reaching number one in several countries. The song was also recorded by The Beatles' friend, Neil Diamond, and many other artists, but the original version was written by Bobby Scott and Bob Russell. The song's lyrics were inspired by the motto of Boys Town, a home for homeless boys in Nebraska, USA. The motto was "He ain't heavy, he's my brother," and  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information about a TV show called "The Bastard Executioner". However, I found information about a TV series called "The Bastard Executioner" which is a historical drama television series that aired on FX from September 15, 2015, to November 17, 2015. It was a short-lived series with only 1 season. It had a total of 10 episodes. 

If you are referring to a different show with a similar name, please let me know and I will try to provide more information. 

However, I would like to note that Chicago Fire (which is mentioned in  
- score: n/a (None) — 


---
_Generated by report_ab.py._