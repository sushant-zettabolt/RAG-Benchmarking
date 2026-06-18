# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.054 | 0.053 | 1.004x |
| Retrieval + overhead | 0.189 | 0.188 | 1.01x |
| Prompt processing (prefill) | 5.200 | 4.608 | 1.13x |
| Generation (decode) | 3.667 | 3.672 | 1.002x |
| LLM total (prefill+decode) | 8.867 | 8.281 | 1.07x |
| Time to first token | 5.443 | 4.849 | 1.12x |
| End-to-end (total) | 9.029 | 8.441 | 1.07x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 657.1 | 741.8 | 1.13x |
| Decode (generation) t/s | 34.9 | 34.9 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3414.0 | 3414.0 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.054 | 0.053 |
| Retrieval + overhead (s) | 0.189 | 0.188 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 43.0% | 41.0% |

### Speedup summary

- Prefill throughput: **1.13x**  (657.1 → 741.8 t/s)
- Decode throughput:  **1.00x**  (34.9 → 34.9 t/s)
- LLM inference latency: **1.07x**
- End-to-end latency: **1.07x**  (9.03s → 8.44s)

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
| Contains reference (lexical) | 43 (43.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 354197 |
| Tokens/query (prompt / completion) | 3414.0 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 9.029 | 8.962 | 9.854 | 8.038 | 10.025 |
| Time to first token | 5.443 | 5.379 | 6.248 | 4.453 | 6.439 |
| Query embedding | 0.054 | 0.054 | 0.056 | 0.051 | 0.058 |
| Retrieval + overhead | 0.189 | 0.188 | 0.199 | 0.180 | 0.213 |
| Prompt processing (prefill) | 5.200 | 5.134 | 6.003 | 4.220 | 6.189 |
| Generation (decode) | 3.667 | 3.669 | 3.686 | 3.635 | 3.692 |
| LLM total (prefill+decode) | 8.867 | 8.798 | 9.689 | 7.886 | 9.855 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3414.0 | 3385 | 3907 | 2814 | 4012 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3542.0 | 3513 | 4035 | 2942 | 4140 |

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
- got: <think>We need answer: last time anyone was on the moon. That's Apollo 17 in December 1972. But perhaps mention last manned lunar landing. The last time humans visited the Moon was Apollo 17. They left on December 7 1972, landed December 11, 1972. So answer: December 1972. Provide details.</think>The last time humans walked on the Moon was during NASA’s **Apollo 17** mission, which launched on **December 7 1972**. The crew landed on the lunar surface on **December 11 1972  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics"

We need to answer: the song "He Ain't Heavy, He's My Brother" is written by Bobby Scott and Bob Russell. Actually the lyrics were written by Bob Russell, music by Bobby Scott. The question: "who wrote he ain't heavy he's my brother lyrics" So answer: Bob Russell wrote the lyrics, and Bobby Scott composed the music. Provide that info. Also maybe mention the song was originally recorded by The Hollies. Provide concise answer. No extraneous.</think>The lyrics to **“He Ain’t Heavy  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>We have to answer user question: "how many seasons of the bastard executioner are there". We need to find context: The user asks about "bastard executioner". That is presumably a show. We need to search context for "bastard executioner". None of the provided contexts mention that. We have contexts about Prison Break, The Vampire Diaries, The Purge, The O.C., etc. No mention of "bastard executioner". Possibly it's a show "The Bastard Executioner". I don't see it. We need to provide answer: likely we don't have info. We can say  
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
| Contains reference (lexical) | 41 (41.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 354197 |
| Tokens/query (prompt / completion) | 3414.0 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 8.441 | 8.393 | 9.194 | 7.569 | 9.336 |
| Time to first token | 4.849 | 4.796 | 5.599 | 4.011 | 5.743 |
| Query embedding | 0.053 | 0.053 | 0.056 | 0.050 | 0.057 |
| Retrieval + overhead | 0.188 | 0.187 | 0.195 | 0.179 | 0.212 |
| Prompt processing (prefill) | 4.608 | 4.559 | 5.354 | 3.774 | 5.498 |
| Generation (decode) | 3.672 | 3.669 | 3.711 | 3.630 | 3.716 |
| LLM total (prefill+decode) | 8.281 | 8.230 | 9.029 | 7.413 | 9.171 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3414.0 | 3385 | 3907 | 2814 | 4012 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3542.0 | 3513 | 4035 | 2942 | 4140 |

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
- got: <think>User asks: "when was the last time anyone was on the moon". They want date. Last manned moon landing was Apollo 17, 1972. Specifically astronauts returned to Earth on December 7, 1972; they left the moon on December 7. They were on the moon until December 7, 1972. The last time anyone was on the moon is December 7, 1972. There's also mention of Lunar Reconnaissance Orbiter? But that's unmanned. So answer: December 7, 1972. Provide context.</think>The last  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics". That's a song by The Hollies. The lyrics were written by the band members? The song was written by the members of The Hollies: Tony Hicks, Graham Nash, and Noel Redding? Wait, "He Ain't Heavy, He's My Brother" was written by the members of The Hollies: Tony Hicks, Graham Nash, and Noel Redding? Let's recall: The Hollies wrote the song themselves: "He Ain't Heavy, He's My Brother" was written by the members of The Hollies: Tony Hicks, Graham Nash,  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>The user asks: "how many seasons of the bastard executioner are there". We must identify the show "The Bastard Executioner". This seems a series. We need number of seasons. Let's recall: The Bastard Executioner (Spanish: El Bastardo Ejecutor). It's a Spanish TV series produced by RTVE. I think it had 3 seasons? Actually I recall that first season aired 2020. Then second season 2021? And third season 2023? Let’s check memory: The Bastard Executioner (El Bastardo Ejecutor) is a Spanish historical drama set in the  
- score: n/a (None) — 


---
_Generated by report_ab.py._