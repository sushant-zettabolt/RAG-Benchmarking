# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.014 | 1.30x |
| Retrieval + overhead | 0.152 | 0.148 | 1.03x |
| Prompt processing (prefill) | 5.627 | 5.006 | 1.12x |
| Generation (decode) | 3.451 | 3.467 | 1.005x |
| LLM total (prefill+decode) | 9.078 | 8.473 | 1.07x |
| Time to first token | 5.790 | 5.168 | 1.12x |
| End-to-end (total) | 9.169 | 8.563 | 1.07x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 718.1 | 808.0 | 1.13x |
| Decode (generation) t/s | 37.1 | 36.9 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4022.7 | 4022.7 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.011 | 0.014 |
| Retrieval + overhead (s) | 0.152 | 0.148 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 10.0% | 10.0% |

### Speedup summary

- Prefill throughput: **1.13x**  (718.1 → 808.0 t/s)
- Decode throughput:  **1.00x**  (37.1 → 36.9 t/s)
- LLM inference latency: **1.07x**
- End-to-end latency: **1.07x**  (9.17s → 8.56s)

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
| Contains reference (lexical) | 1 (10.0%) |
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 41507 |
| Tokens/query (prompt / completion) | 4022.7 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 9.169 | 9.108 | 10.694 | 8.139 | 10.694 |
| Time to first token | 5.790 | 5.719 | 7.321 | 4.760 | 7.321 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.152 | 0.154 | 0.159 | 0.135 | 0.159 |
| Prompt processing (prefill) | 5.627 | 5.573 | 7.151 | 4.601 | 7.151 |
| Generation (decode) | 3.451 | 3.452 | 3.477 | 3.418 | 3.477 |
| LLM total (prefill+decode) | 9.078 | 9.017 | 10.595 | 8.053 | 10.595 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4022.7 | 4107 | 4726 | 3529 | 4726 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 4150.7 | 4235 | 4854 | 3657 | 4854 |

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
- got: <think>1.  **Analyze the Request:** The user is asking "when was the last time anyone was on the moon".

2.  **Scan the Context for Keywords:** I need to look for terms like "moon," "astronaut," "space," "mission," or specific dates related to lunar landings.

3.  **Review Contexts:**
    *   Context 0 (Houston Astros): Mentions NASA, Space City. (Relevant to space, but not a specific lunar mission date).
    *   Context 1 (Fishin' in the Dark): Fishing, constellations. (Irrelevant).  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>1.  **Analyze the Request:** The user is asking for the writer of the lyrics "he ain't heavy he's my brother".

2.  **Scan Context for Keywords:** I need to search the provided context for the lyrics "he ain't heavy he's my brother" or any information related to a song with those lyrics and its writer.

3.  **Review Context Snippets:**
    *   Context 0 (Don't Let Me Down): Mentions The Chainsmokers, Taggart, Emily Warren, Scott Harris, Daya. (Irrelevant)  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>1.  **Analyze the Request:** The user is asking "how many seasons of the bastard executioner are there".

2.  **Scan the Context:** I need to search the provided text snippets for any mention of "The Bastard Executioner" or any television show/series that matches this title.

    *   Context 0: Mentions *Chicago Fire* (season 4).
    *   Context 1: Mentions *The Vampire Diaries*.
    *   Context 2: Mentions *This Is Us*.
    *   Context 3: Mentions Atomic bombings of  
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
| Contains reference (lexical) | 1 (10.0%) |
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 41507 |
| Tokens/query (prompt / completion) | 4022.7 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 8.563 | 8.497 | 10.019 | 7.572 | 10.019 |
| Time to first token | 5.168 | 5.099 | 6.635 | 4.189 | 6.635 |
| Query embedding | 0.014 | 0.011 | 0.032 | 0.010 | 0.032 |
| Retrieval + overhead | 0.148 | 0.149 | 0.156 | 0.134 | 0.156 |
| Prompt processing (prefill) | 5.006 | 4.937 | 6.447 | 4.033 | 6.447 |
| Generation (decode) | 3.467 | 3.469 | 3.493 | 3.444 | 3.493 |
| LLM total (prefill+decode) | 8.473 | 8.409 | 9.902 | 7.490 | 9.902 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4022.7 | 4107 | 4726 | 3529 | 4726 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 4150.7 | 4235 | 4854 | 3657 | 4854 |

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
- got: <think>1.  **Analyze the Request:** The user is asking, "when was the last time anyone was on the moon".

2.  **Scan the Context for Keywords:** I need to look for terms like "moon," "astronaut," "space," "mission," or specific dates related to lunar landings.

3.  **Review Contexts:**
    *   Context 0 (Houston Astros): Mentions NASA, Space City.
    *   Context 1 (Fishin' in the Dark): Fishing.
    *   Context 2 (Wake Island): Typhoon.
    *   Context  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>1.  **Analyze the Request:** The user is asking for the writer of the lyrics "he ain't heavy he's my brother".

2.  **Scan the Context for Keywords:** I need to search the provided context for the lyrics "he ain't heavy he's my brother" or any information related to song lyrics authorship.

3.  **Review Contexts:**
    *   Context 0 (Don't Let Me Down): Mentions Taggart, Emily Warren, Scott Harris, Daya. (Irrelevant)
    *   Context 1 (Love Will Keep  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>1.  **Analyze the Request:** The user is asking "how many seasons of the bastard executioner are there".

2.  **Scan the Context:** I need to search the provided text snippets for any mention of "The Bastard Executioner" or a similar title.

    *   Context 0: Mentions "Chicago Fire (season 4)".
    *   Context 1: Mentions "The Vampire Diaries".
    *   Context 2: Mentions "This Is Us".
    *   Context 3: Mentions "Atomic bombings of Hiroshima and Nagasaki".  
- score: n/a (None) — 


---
_Generated by report_ab.py._