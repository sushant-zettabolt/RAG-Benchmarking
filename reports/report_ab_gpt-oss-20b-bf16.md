# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.002x |
| Retrieval + overhead | 0.190 | 0.189 | 1.01x |
| Prompt processing (prefill) | 5.966 | 4.722 | 1.26x |
| Generation (decode) | 3.627 | 3.652 | 1.01x |
| LLM total (prefill+decode) | 9.594 | 8.374 | 1.15x |
| Time to first token | 6.167 | 4.921 | 1.25x |
| End-to-end (total) | 9.716 | 8.494 | 1.14x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 607.0 | 767.2 | 1.26x |
| Decode (generation) t/s | 35.3 | 35.0 | 0.99x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3617.9 | 3617.9 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.190 | 0.189 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 40.0% | 50.0% |

### Speedup summary

- Prefill throughput: **1.26x**  (607.0 → 767.2 t/s)
- Decode throughput:  **0.99x**  (35.3 → 35.0 t/s)
- LLM inference latency: **1.15x**
- End-to-end latency: **1.14x**  (9.72s → 8.49s)

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
| Total tokens (sum) | 37459 |
| Tokens/query (prompt / completion) | 3617.9 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 9.716 | 9.855 | 11.093 | 8.879 | 11.093 |
| Time to first token | 6.167 | 6.304 | 7.509 | 5.364 | 7.509 |
| Query embedding | 0.011 | 0.011 | 0.012 | 0.010 | 0.012 |
| Retrieval + overhead | 0.190 | 0.194 | 0.203 | 0.155 | 0.203 |
| Prompt processing (prefill) | 5.966 | 6.138 | 7.296 | 5.167 | 7.296 |
| Generation (decode) | 3.627 | 3.630 | 3.663 | 3.594 | 3.663 |
| LLM total (prefill+decode) | 9.594 | 9.768 | 10.959 | 8.761 | 10.959 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3617.9 | 3676 | 4327 | 3141 | 4327 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3745.9 | 3804 | 4455 | 3269 | 4455 |

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
- got: <think>The user asks: "when was the last time anyone was on the moon". We need to answer. The context includes many documents, but none about moon landings directly. However we have knowledge: last time humans were on the Moon was Apollo 17, which landed on December 11, 1972, and the last exit from the lunar surface was December 19, 1972. So answer: December 1972. The user might want a date. Provide that. Ensure no extra.</think>The last time humans walked on the Moon was during NASA’s Apollo 17 mission,  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics". The song is "He Ain't Heavy, He's My Brother". The original lyric writer? The song was written by Bobby Scott and Bob Russell? Wait, "He Ain't Heavy, He's My Brother" is a song by The Hollies? Actually the song "He Ain't Heavy, He's My Brother" is a 1969 song written by Bobby Scott and Bob Russell. But the lyrics were written by someone? Let's recall: The original by The Hollies? The Hollies had a version. The original was by The Hollies? Actually  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>The user asks: "how many seasons of the bastard executioner are there". That is a question about a show or something titled "The Bastard Executioner". We need to see if any context mentions it. Let's search the context for "bastard executioner". None of the contexts mention that. We have contexts about Chicago Fire season 4, Vampire Diaries, This Is Us, etc. No mention of Bastard Executioner. So likely it's a show not included. We need to answer: number of seasons. We might need to research or guess? We should not hallucinate. We can say we don't  
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
| Total tokens (sum) | 37459 |
| Tokens/query (prompt / completion) | 3617.9 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 8.494 | 8.552 | 9.599 | 7.858 | 9.599 |
| Time to first token | 4.921 | 4.992 | 6.022 | 4.310 | 6.022 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.189 | 0.191 | 0.198 | 0.153 | 0.198 |
| Prompt processing (prefill) | 4.722 | 4.828 | 5.815 | 4.112 | 5.815 |
| Generation (decode) | 3.652 | 3.656 | 3.676 | 3.628 | 3.676 |
| LLM total (prefill+decode) | 8.374 | 8.468 | 9.471 | 7.740 | 9.471 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3617.9 | 3676 | 4327 | 3141 | 4327 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3745.9 | 3804 | 4455 | 3269 | 4455 |

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
- got: <think>We need to answer: "when was the last time anyone was on the moon". The last Apollo mission: Apollo 17 landed on December 11, 1972, and returned December 19, 1972. That was the last time humans visited the Moon. So answer: December 1972. Provide date: December 11, 1972 to December 19, 1972. Probably just mention December 1972. Let's respond.</think>The most recent human visit to the Moon was the Apollo 17 mission. Astronauts Eugene Cernan, Harrison  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics". They want the writer(s) of the lyrics for the song "He Ain't Heavy, He's My Brother". The song is a famous cover by The Hollies. The original was by The Hollies? Actually the original was written by Bob Mosley? Wait, "He Ain't Heavy, He's My Brother" was written by Bob Mosley and Bobby Scott? Let’s recall. The song "He Ain't Heavy, He's My Brother" was written by Bob Mosley and Bobby Scott. Actually check: The Hollies recorded it in 197  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>User asks: "how many seasons of the bastard executioner are there". This is likely a TV show or series. We need to search knowledge. "The Bastard Executioner" might be a show? I know "The Bastard Executioner" is a fictional title? There's a Netflix series "The Bastard Executioner" maybe? Actually there is a show "The Bastard Executioner" on Netflix? I recall a show "The Bastard Executioner" might be a Swedish series? Wait "The Bastard Executioner" is a 2024 series maybe? Let's think: There is "The Bast  
- score: n/a (None) — 


---
_Generated by report_ab.py._