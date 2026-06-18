# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.053 | 0.053 | 1.001x |
| Retrieval + overhead | 0.154 | 0.153 | 1.01x |
| Prompt processing (prefill) | 4.934 | 4.351 | 1.13x |
| Generation (decode) | 3.458 | 3.487 | 1.01x |
| LLM total (prefill+decode) | 8.393 | 7.838 | 1.07x |
| Time to first token | 5.142 | 4.557 | 1.13x |
| End-to-end (total) | 8.526 | 7.971 | 1.07x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 732.4 | 831.6 | 1.14x |
| Decode (generation) t/s | 37.0 | 36.7 | 0.99x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3598.3 | 3598.3 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.053 | 0.053 |
| Retrieval + overhead (s) | 0.154 | 0.153 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 10.0% | 9.0% |

### Speedup summary

- Prefill throughput: **1.14x**  (732.4 → 831.6 t/s)
- Decode throughput:  **0.99x**  (37.0 → 36.7 t/s)
- LLM inference latency: **1.07x**
- End-to-end latency: **1.07x**  (8.53s → 7.97s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **0 (0%)** |
| Mean judge score | n/a |
| Contains reference (lexical) | 10 (10.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 372634 |
| Tokens/query (prompt / completion) | 3598.3 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 8.526 | 8.323 | 9.721 | 7.264 | 9.970 |
| Time to first token | 5.142 | 4.947 | 6.333 | 3.890 | 6.573 |
| Query embedding | 0.053 | 0.053 | 0.056 | 0.048 | 0.057 |
| Retrieval + overhead | 0.154 | 0.153 | 0.160 | 0.141 | 0.182 |
| Prompt processing (prefill) | 4.934 | 4.738 | 6.129 | 3.693 | 6.364 |
| Generation (decode) | 3.458 | 3.455 | 3.494 | 3.409 | 3.509 |
| LLM total (prefill+decode) | 8.393 | 8.187 | 9.588 | 7.139 | 9.831 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3598.3 | 3589 | 4180 | 2924 | 4297 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3726.3 | 3717 | 4308 | 3052 | 4425 |

### Failed / incorrect queries (100)

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
| 10 | which state is located in the centre of india | None |  |
| 11 | who sang i ran all the way home | None |  |
| 12 | where did the last name wallace come from | None |  |
| 13 | who was the actor that played ben stone on law and order | None |  |
| 14 | who does the voice of nala in the lion king | None |  |
| 15 | who plays gram on the young and the restless | None |  |
| 16 | what is the oath that new citizens take | None |  |
| 17 | who is under the mask of darth vader | None |  |
| 18 | who had a baby at 100 in the bible | None |  |
| 19 | what age do you need to be to buy a bb gun | None |  |
| 20 | ethiopia flight 961 crashes in to the sea | None |  |
| 21 | where was percy jackson and the olympians filmed | None |  |
| 22 | how many seasons of vampire diaries r there | None |  |
| 23 | how many episodes are there in dragon ball z | None |  |
| 24 | who plays auggie in the movie the wonder | None |  |
| 25 | when was the first australian prime minister elected | None |  |
| 26 | who plays matthew on anne with an e | None |  |
| 27 | who is the girl in green day 21 guns | None |  |
| 28 | who plays joker in batman the dark knight | None |  |
| 29 | when was the south asian association for regional co-operation (saarc)… | None |  |

_…and 70 more (see the JSON report)._

### Example answers

#### Correct

_No correct examples._

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>Thinking Process:

1.  **Analyze the Request:** The user is asking, "when was the last time anyone was on the moon".
2.  **Scan Context for Keywords:** I need to search the provided context (Context 0 through Context 7) for terms like "moon," "astronaut," "space," "mission," or specific dates related to lunar activities.
3.  **Review Contexts:**
    *   Context 0 (Chinese New Year): Deals with Chinese calendar, zodiac, and customs. (Irrelevant)
    *   Context 1 (Wake Island): Deals  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>1.  **Analyze the Request:** The user is asking who wrote the lyrics to the song "he ain't heavy he's my brother".

2.  **Scan the Context:** I need to search all provided context documents (Context 0 through Context 7) for the specific song title or lyrics.

    *   Context 0: Mentions "Don't Let Me Down (The Chainsmokers song)", Walter Frederick Morrison.
    *   Context 1: Mentions "Can't Help Falling in Love" (Elvis Presley, Hugo Peretti, Luigi Creatore, George  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>1.  **Analyze the Request:** The user is asking "how many seasons of the bastard executioner are there".

2.  **Scan the Contexts:** I need to search the provided texts (Context 0 through Context 7) for any mention of "The Bastard Executioner" or any show/series that matches that title.

    *   Context 0 (Prison Break): Mentions Prison Break seasons and episodes.
    *   Context 1 (Prison Break): Mentions Prison Break seasons.
    *   Context 2 (The Vampire Diaries): Mentions seasons four and five  
- score: n/a (None) — 


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **0 (0%)** |
| Mean judge score | n/a |
| Contains reference (lexical) | 9 (9.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 372634 |
| Tokens/query (prompt / completion) | 3598.3 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 7.971 | 7.788 | 9.062 | 6.792 | 9.324 |
| Time to first token | 4.557 | 4.362 | 5.661 | 3.402 | 5.907 |
| Query embedding | 0.053 | 0.053 | 0.055 | 0.046 | 0.057 |
| Retrieval + overhead | 0.153 | 0.153 | 0.158 | 0.140 | 0.165 |
| Prompt processing (prefill) | 4.351 | 4.151 | 5.455 | 3.202 | 5.699 |
| Generation (decode) | 3.487 | 3.490 | 3.521 | 3.434 | 3.530 |
| LLM total (prefill+decode) | 7.838 | 7.660 | 8.926 | 6.664 | 9.187 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3598.3 | 3589 | 4180 | 2924 | 4297 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3726.3 | 3717 | 4308 | 3052 | 4425 |

### Failed / incorrect queries (100)

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
| 10 | which state is located in the centre of india | None |  |
| 11 | who sang i ran all the way home | None |  |
| 12 | where did the last name wallace come from | None |  |
| 13 | who was the actor that played ben stone on law and order | None |  |
| 14 | who does the voice of nala in the lion king | None |  |
| 15 | who plays gram on the young and the restless | None |  |
| 16 | what is the oath that new citizens take | None |  |
| 17 | who is under the mask of darth vader | None |  |
| 18 | who had a baby at 100 in the bible | None |  |
| 19 | what age do you need to be to buy a bb gun | None |  |
| 20 | ethiopia flight 961 crashes in to the sea | None |  |
| 21 | where was percy jackson and the olympians filmed | None |  |
| 22 | how many seasons of vampire diaries r there | None |  |
| 23 | how many episodes are there in dragon ball z | None |  |
| 24 | who plays auggie in the movie the wonder | None |  |
| 25 | when was the first australian prime minister elected | None |  |
| 26 | who plays matthew on anne with an e | None |  |
| 27 | who is the girl in green day 21 guns | None |  |
| 28 | who plays joker in batman the dark knight | None |  |
| 29 | when was the south asian association for regional co-operation (saarc)… | None |  |

_…and 70 more (see the JSON report)._

### Example answers

#### Correct

_No correct examples._

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>1.  **Analyze the Request:** The user is asking "when was the last time anyone was on the moon".

2.  **Scan the Contexts:** I need to search the provided text (Context 0 through Context 7) for any information regarding moon landings, space travel, or astronaut history.

    *   Context 0 (Chinese New Year): Discusses the Chinese calendar, zodiac, and astrology. (Irrelevant)
    *   Context 1 (Wake Island): Discusses U.S. military use of Wake Island for Chinese immigrants. (Irrelevant)
    *  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>1.  **Analyze the Request:** The user is asking who wrote the lyrics to the song "He Ain't Heavy, He's My Brother".

2.  **Scan the Contexts:** I need to search all provided contexts (0 through 7) for mentions of "He Ain't Heavy, He's My Brother" or any related song/lyric information.

    *   Context 0 (Don't Let Me Down, Walter Frederick Morrison): Irrelevant.
    *   Context 1 (Can't Help Falling in Love): Irrelevant.
    *  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>1.  **Analyze the Request:** The user is asking "how many seasons of the bastard executioner are there".

2.  **Scan the Contexts:** I need to search the provided text (Context 0 through Context 7) for any mention of "The Bastard Executioner" or related content.

    *   Context 0: Mentions *Prison Break* episodes and seasons.
    *   Context 1: Mentions *Prison Break* series details.
    *   Context 2: Mentions *The Vampire Diaries* characters and seasons.
    *   Context  
- score: n/a (None) — 


---
_Generated by report_ab.py._