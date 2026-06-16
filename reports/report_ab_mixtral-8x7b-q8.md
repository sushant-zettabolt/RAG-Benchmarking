# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.00x slower |
| Retrieval + overhead | 0.227 | 0.224 | 1.01x faster |
| Prompt processing (prefill) | 32.231 | 12.963 | 2.49x faster |
| Generation (decode) | 6.371 | 6.301 | 1.01x faster |
| LLM total (prefill+decode) | 38.602 | 19.264 | 2.00x faster |
| Time to first token | 32.468 | 13.198 | 2.46x faster |
| End-to-end (total) | 38.834 | 19.494 | 1.99x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 135.1 | 336.2 | 2.49x |
| Decode (generation) t/s | 20.1 | 20.3 | 1.01x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4350.5 | 4350.5 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.227 | 0.224 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 40.0% | 40.0% |

### Speedup summary

- Prefill throughput: **2.49x**  (135.1 → 336.2 t/s)
- Decode throughput:  **1.01x**  (20.1 → 20.3 t/s)
- LLM inference latency: **2.00x faster**
- End-to-end latency: **1.99x faster**  (38.83s → 19.49s)

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
| Total tokens (sum) | 44785 |
| Tokens/query (prompt / completion) | 4350.5 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 38.834 | 39.532 | 45.344 | 34.240 | 45.344 |
| Time to first token | 32.468 | 33.156 | 38.933 | 27.943 | 38.933 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.227 | 0.248 | 0.278 | 0.063 | 0.278 |
| Prompt processing (prefill) | 32.231 | 32.983 | 38.678 | 27.707 | 38.678 |
| Generation (decode) | 6.371 | 6.374 | 6.418 | 6.302 | 6.418 |
| LLM total (prefill+decode) | 38.602 | 39.333 | 45.096 | 34.009 | 45.096 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4350.5 | 4449 | 5139 | 3770 | 5139 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 4478.5 | 4577 | 5267 | 3898 | 5267 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972, when astronauts Eugene Cernan and Harrison Schmitt spent about three days on the lunar surface. No human has returned to the moon since then.

(Information gathered from context documents 0, 5, and 11 does not directly provide information about the last time anyone was on the moon, but it does provide context about the song "Can't Help Falling in Love," which Elvis Presley performed as the last song in his final live concert in  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies and Neil Diamond are among the artists who have recorded this song. It's also known as a motivational slogan and has been used in various campaigns. The title and central theme of the song are derived from a phrase made famous by a young boy who was asked to carry a much smaller, disabled boy on his back during a 1966 charity walk in England. When asked if he was tired, the boy replied, "No, he's not heavy; he's  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information about a series called "the bastard executioner." However, I can provide information about the series "Chicago Fire" that was mentioned in several of the contexts you provided. There are currently 10 seasons of "Chicago Fire" as of the information published in 2026. Therefore, I would not be able to provide an accurate number of seasons for "the bastard executioner" based on the information given. It would be best to check a reliable source for information on that specific series. If you have any more questions about "Chicago Fire" or any of the  
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
| Contains reference (lexical) | 4 (40.0%) |
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 44785 |
| Tokens/query (prompt / completion) | 4350.5 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 19.494 | 19.672 | 22.441 | 17.547 | 22.441 |
| Time to first token | 13.198 | 13.366 | 16.102 | 11.276 | 16.102 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.224 | 0.246 | 0.272 | 0.059 | 0.272 |
| Prompt processing (prefill) | 12.963 | 13.235 | 15.851 | 11.041 | 15.851 |
| Generation (decode) | 6.301 | 6.311 | 6.345 | 6.264 | 6.345 |
| LLM total (prefill+decode) | 19.264 | 19.534 | 22.196 | 17.316 | 22.196 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4350.5 | 4449 | 5139 | 3770 | 5139 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 4478.5 | 4577 | 5267 | 3898 | 5267 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972, when astronauts Eugene Cernan and Harrison Schmitt spent about three days on the lunar surface. No human has returned to the moon since then. However, various space agencies and private companies have plans to send astronauts or space tourists to the moon in the future. For example, NASA's Artemis program aims to land "the first woman and the next man" on the moon by 2024, and SpaceX's Starship spacecraft is  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies recorded a popular version of the song in 1969. The song's lyrics include the line "He's my brother, he's my friend." The title and lyrics of the song convey a message of support and camaraderie. The song has been covered by various artists and has been used in films and television shows. The song's message remains relevant and inspiring to this day. It is a powerful anthem of support and solidarity, reminding  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information about a television series called "the bastard executioner." I can provide information about the shows that were mentioned in the given contexts. If you have a specific document or context regarding "the bastard executioner," please provide it and I'll do my best to help with your question.

However, based on the contexts you provided, here is some information about the number of seasons for those shows:

1. Chicago Fire - There are 10 seasons of Chicago Fire, and the fourth season is the focus of the provided context.
2. The Vampire Di  
- score: n/a (None) — 


---
_Generated by report_ab.py._