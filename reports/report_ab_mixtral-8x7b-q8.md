# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.053 | 0.053 | 1.002x |
| Retrieval + overhead | 0.246 | 0.245 | 1.003x |
| Prompt processing (prefill) | 29.014 | 11.952 | 2.43x |
| Generation (decode) | 6.356 | 6.362 | 1.001x |
| LLM total (prefill+decode) | 35.371 | 18.313 | 1.93x |
| Time to first token | 29.314 | 12.250 | 2.39x |
| End-to-end (total) | 35.666 | 18.608 | 1.92x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 138.8 | 337.5 | 2.43x |
| Decode (generation) t/s | 20.1 | 20.1 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4022.4 | 4022.4 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.053 | 0.053 |
| Retrieval + overhead (s) | 0.246 | 0.245 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 43.0% | 47.0% |

### Speedup summary

- Prefill throughput: **2.43x**  (138.8 → 337.5 t/s)
- Decode throughput:  **1.00x**  (20.1 → 20.1 t/s)
- LLM inference latency: **1.93x**
- End-to-end latency: **1.92x**  (35.67s → 18.61s)

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
| Total tokens (sum) | 415036 |
| Tokens/query (prompt / completion) | 4022.4 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 35.666 | 35.235 | 40.367 | 30.010 | 42.132 |
| Time to first token | 29.314 | 28.914 | 33.938 | 23.718 | 35.746 |
| Query embedding | 0.053 | 0.053 | 0.056 | 0.047 | 0.057 |
| Retrieval + overhead | 0.246 | 0.248 | 0.281 | 0.202 | 0.312 |
| Prompt processing (prefill) | 29.014 | 28.610 | 33.660 | 23.430 | 35.431 |
| Generation (decode) | 6.356 | 6.357 | 6.414 | 6.280 | 6.434 |
| LLM total (prefill+decode) | 35.371 | 34.935 | 40.094 | 29.726 | 41.823 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4022.4 | 3995 | 4631 | 3305 | 4787 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 4150.4 | 4123 | 4759 | 3433 | 4915 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while Ronald Evans orbited overhead in the Command Module. No human has returned to the moon since then. However, there are plans for future lunar missions by various space agencies and private companies. For example, NASA's Artemis program aims to land "the first woman and the next man" on the moon by 2024, and China's Chang  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies, a British rock group, had a hit version of the song in 1969. The lyrics describe the bond between two brothers and the idea that even though one might be a burden, he is still loved and cared for. The title is a reference to a famous phrase spoken by English children's charity leader Sir William Booth, who said, "A man who is good enough to carry his brother's burdens is good enough to carry a nation." The song has  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find specific information about the number of seasons of "The Bastard Executioner" within the provided contexts. "The Bastard Executioner" is a different television series from "Prison Break", "The O.C.", "The Purge: Election Year", and "Comanche" which are mentioned in the given contexts. To get the information you need, you might want to look up the details of "The Bastard Executioner" separately. In general, you can check the show's official website or trusted entertainment databases such as IMDb for accurate information regarding the  
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
| Contains reference (lexical) | 47 (47.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 415036 |
| Tokens/query (prompt / completion) | 4022.4 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 18.608 | 18.223 | 20.613 | 16.024 | 21.811 |
| Time to first token | 12.250 | 11.896 | 14.229 | 9.652 | 15.404 |
| Query embedding | 0.053 | 0.053 | 0.055 | 0.050 | 0.057 |
| Retrieval + overhead | 0.245 | 0.247 | 0.273 | 0.203 | 0.306 |
| Prompt processing (prefill) | 11.952 | 11.590 | 13.938 | 9.359 | 15.086 |
| Generation (decode) | 6.362 | 6.365 | 6.414 | 6.295 | 6.437 |
| LLM total (prefill+decode) | 18.313 | 17.919 | 20.326 | 15.734 | 21.500 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4022.4 | 3995 | 4631 | 3305 | 4787 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 4150.4 | 4123 | 4759 | 3433 | 4915 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while astronaut Ronald Evans orbited overhead in the Command Module. Since then, no human has returned to the moon. However, there have been numerous robotic missions to the moon by various countries and organizations, with plans for future manned missions in development. For example, NASA's Artemis program aims to return humans to the moon by 2024.  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies, a British rock group, had a hit version of the song in 1969. The lyrics describe the bond between two brothers, with the chorus repeating the phrase "he ain't heavy, he's my brother." The song has been covered by various artists and has been used in films and television shows. The title and lyrics of the song have also been used in various contexts to convey a message of support and unity. Bobby Scott and Bob Russell wrote the lyrics  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I cannot provide an answer as there is no context or document provided that discusses "the bastard executioner" and its number of seasons. However, I can look up information about "the bastard executioner" if you provide more context or details.

If you meant "The O.C." instead of "the bastard executioner," then there are four seasons of The O.C. according to context 4 and 5. The O.C. was an American teen drama television series that aired in the United States from November 2, 2006 to February 22,  
- score: n/a (None) — 


---
_Generated by report_ab.py._