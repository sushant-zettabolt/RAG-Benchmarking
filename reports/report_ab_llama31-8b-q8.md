# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.01x faster |
| Retrieval + overhead | 0.200 | 0.196 | 1.02x faster |
| Prompt processing (prefill) | 9.406 | 6.003 | 1.57x faster |
| Generation (decode) | 4.027 | 4.048 | 1.01x slower |
| LLM total (prefill+decode) | 13.433 | 10.051 | 1.34x faster |
| Time to first token | 9.617 | 6.209 | 1.55x faster |
| End-to-end (total) | 13.639 | 10.252 | 1.33x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 380.0 | 597.6 | 1.57x |
| Decode (generation) t/s | 31.8 | 31.6 | 0.99x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3561.6 | 3561.6 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.200 | 0.196 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 40.0% | 50.0% |

### Speedup summary

- Prefill throughput: **1.57x**  (380.0 → 597.6 t/s)
- Decode throughput:  **0.99x**  (31.8 → 31.6 t/s)
- LLM inference latency: **1.34x faster**
- End-to-end latency: **1.33x faster**  (13.64s → 10.25s)

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
| Contains reference (lexical) | 4 (40.0%) |
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 36896 |
| Tokens/query (prompt / completion) | 3561.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 13.639 | 13.542 | 16.289 | 11.843 | 16.289 |
| Time to first token | 9.617 | 9.527 | 12.229 | 7.838 | 12.229 |
| Query embedding | 0.011 | 0.011 | 0.012 | 0.010 | 0.012 |
| Retrieval + overhead | 0.200 | 0.218 | 0.241 | 0.062 | 0.241 |
| Prompt processing (prefill) | 9.406 | 9.448 | 12.002 | 7.629 | 12.002 |
| Generation (decode) | 4.027 | 4.024 | 4.067 | 4.005 | 4.067 |
| LLM total (prefill+decode) | 13.433 | 13.470 | 16.069 | 11.638 | 16.069 |

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
- got: Unfortunately, I don't see any information in the provided contexts about the last time anyone was on the moon. The contexts appear to cover a wide range of topics, including sports, music, politics, history, and more, but none of them specifically address space exploration or the moon. If you're looking for information on when the last time someone was on the moon, I'd be happy to try and help you find it elsewhere. 

However, I can tell you that the last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. It was originally recorded by Kelly Gordon in 1969, but it was made famous by The Hollies, who released a version in 1969 that became a worldwide hit. The song has since been covered by many other artists, including Neil Diamond, who had a hit version in 1970. However, the original lyrics were written by Bobby Scott and Bob Russell. Bob Russell was an American lyricist who wrote many popular songs, including "He Ain't Heavy, He's My Brother", and Bobby Scott was an American  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I am unable to verify how many seasons of The Bastard Executioner are there. I do not have access to a search engine to find this information. The Bastard Executioner is a series that aired on FX from 2015. It ran for 1 season and 10 episodes. It was cancelled after the first season. It is a historical drama television series that premiered on September 15, 2015. It is based on a medieval story and was created by Kurt Sutter. The series follows the story of a knight who is tasked with serving as the executioner for a local lord. The show was well-received  
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
| Contains reference (lexical) | 5 (50.0%) |
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 36896 |
| Tokens/query (prompt / completion) | 3561.6 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 10.252 | 10.107 | 12.227 | 8.863 | 12.227 |
| Time to first token | 6.209 | 6.062 | 8.143 | 4.863 | 8.143 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.196 | 0.213 | 0.238 | 0.058 | 0.238 |
| Prompt processing (prefill) | 6.003 | 5.989 | 7.923 | 4.658 | 7.923 |
| Generation (decode) | 4.048 | 4.049 | 4.092 | 4.003 | 4.092 |
| LLM total (prefill+decode) | 10.051 | 10.038 | 12.015 | 8.661 | 12.015 |

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
- got: The last time humans were on the moon was during the Apollo 17 mission in December 1972. NASA astronauts Eugene Cernan and Harrison Schmitt spent three days on the lunar surface, conducting scientific experiments and exploring the Taurus-Littrow valley. They returned to Earth on December 19, 1972.

Since then, there have been no manned missions to the moon. However, there are plans to return humans to the moon in the near future. NASA's Artemis program aims to send the first woman and the next man to the moon by 2025, and to establish a sustainable presence on the lunar surface by  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The song was originally recorded by Kelly Gordon in 1969, but the most famous version was recorded by The Hollies in 1969, and later by Neil Diamond in 1970. The song was written for Kelly Gordon, but he was not able to secure the rights to the song, which ultimately led to The Hollies and Neil Diamond recording the song. The lyrics are based on a phrase that was first spoken by a young boy named Joey Dwyer, who was a patient at a hospital where Bob Russell's  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I am unable to identify any information regarding the number of seasons for The Bastard Executioner. If you could provide more details or context about the series, I'll do my best to provide a more accurate answer. However, I can suggest some options to find the information you're looking for.

The Bastard Executioner is a short-lived TV series that aired from September 15, 2015, to November 17, 2015. It had a total of 10 episodes in its first and only season. I was unable to find any information on further seasons of the show. 

If you're looking for more information on  
- score: n/a (None) — 


---
_Generated by report_ab.py._