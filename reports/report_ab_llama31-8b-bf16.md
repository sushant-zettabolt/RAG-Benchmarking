# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.053 | 0.053 | 1.002x |
| Retrieval + overhead | 0.214 | 0.214 | 1.001x |
| Prompt processing (prefill) | 7.247 | 5.976 | 1.21x |
| Generation (decode) | 6.563 | 6.559 | 1.001x |
| LLM total (prefill+decode) | 13.811 | 12.534 | 1.10x |
| Time to first token | 7.514 | 6.243 | 1.20x |
| End-to-end (total) | 14.074 | 12.797 | 1.10x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 470.0 | 570.7 | 1.21x |
| Decode (generation) t/s | 19.5 | 19.5 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3396.2 | 3396.2 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.053 | 0.053 |
| Retrieval + overhead (s) | 0.214 | 0.214 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 52.0% | 57.0% |

### Speedup summary

- Prefill throughput: **1.21x**  (470.0 → 570.7 t/s)
- Decode throughput:  **1.00x**  (19.5 → 19.5 t/s)
- LLM inference latency: **1.10x**
- End-to-end latency: **1.10x**  (14.07s → 12.80s)

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
| Contains reference (lexical) | 52 (52.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 352425 |
| Tokens/query (prompt / completion) | 3396.2 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 14.074 | 14.009 | 15.543 | 12.468 | 15.770 |
| Time to first token | 7.514 | 7.463 | 8.952 | 5.968 | 9.163 |
| Query embedding | 0.053 | 0.053 | 0.055 | 0.050 | 0.055 |
| Retrieval + overhead | 0.214 | 0.214 | 0.238 | 0.178 | 0.271 |
| Prompt processing (prefill) | 7.247 | 7.178 | 8.679 | 5.708 | 8.867 |
| Generation (decode) | 6.563 | 6.562 | 6.612 | 6.490 | 6.633 |
| LLM total (prefill+decode) | 13.811 | 13.730 | 15.275 | 12.211 | 15.480 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3396.2 | 3369 | 3901 | 2781 | 4064 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3524.2 | 3497 | 4029 | 2909 | 4192 |

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
- got: The last time humans were on the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt. Eugene Cernan and Harrison Schmitt spent three days on the lunar surface, while Ronald Evans remained in orbit around the moon. The mission concluded on December 19, 1972, when the astronauts returned to Earth. 

Since then, there have been several unmanned missions to the moon, but no human has visited the moon. However, NASA is currently planning to return humans to the moon by 2025 as part of the  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The phrase "He ain't heavy, he's my brother" is a famous saying that was popularized by a song of the same name. The song was written by Bobby Scott and Bob Russell, and it was first recorded by Kelly Gordon in 1969. However, it was the 1970 version by Neil Sedaka that became a hit single and made the phrase a well-known catchphrase. The song's lyrics were written by Bobby Scott and Bob Russell, and they are based on a phrase that was coined by a social worker, John E. McCarthy, in the 1950s. McCarthy used the phrase as a way  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information about a TV show called "The Bastard Executioner". However, there was a TV series called "The Bastard Executioner" that aired on FX in 2015. It was a historical drama series created by Kurt Sutter, and it only had one season, which consisted of 10 episodes. It premiered on September 15, 2015, and the final episode aired on November 17, 2015. The show was canceled after one season. If you have any further questions, please let me know! 

However, if you are asking about The Bastard Executioner a movie  
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
| Contains reference (lexical) | 57 (57.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 352425 |
| Tokens/query (prompt / completion) | 3396.2 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 12.797 | 12.753 | 14.121 | 11.395 | 14.245 |
| Time to first token | 6.243 | 6.188 | 7.519 | 4.894 | 7.659 |
| Query embedding | 0.053 | 0.053 | 0.055 | 0.046 | 0.056 |
| Retrieval + overhead | 0.214 | 0.212 | 0.241 | 0.179 | 0.265 |
| Prompt processing (prefill) | 5.976 | 5.904 | 7.239 | 4.637 | 7.376 |
| Generation (decode) | 6.559 | 6.558 | 6.604 | 6.492 | 6.630 |
| LLM total (prefill+decode) | 12.534 | 12.473 | 13.841 | 11.141 | 13.954 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3396.2 | 3369 | 3901 | 2781 | 4064 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3524.2 | 3497 | 4029 | 2909 | 4192 |

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
- got: I don't see any information in the given context about anyone being on the moon recently. However, according to NASA, the last time humans visited the moon was during the Apollo 17 mission in December 1972. Since then, there have been several unmanned spacecraft that have visited the moon, but no human has returned to the lunar surface. 

If you're looking for more up-to-date information, I'd be happy to help you find it. Alternatively, I can provide you with information on the Apollo 17 mission or other NASA-related topics if you're interested. 

Contexts provided don't seem to contain any information about space  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. However, the song's original title was "Jimmy Mack" and was written by Scott. Russell then rewrote the lyrics as "He Ain't Heavy, He's My Brother," and it was recorded by the Hollies in 1969, becoming a hit single. The song was later adopted as the anthem for the Boys Town organization in the United States, a home for troubled youth. It has since become a popular song around the world, known for its uplifting message and memorable chorus. The song's most famous line, "  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information on a TV show called "The Bastard Executioner." However, I did find a TV series called "The Bastard Executioner" that aired on FX from 2015 to 2015. It was a historical drama series that aired for one season, which consisted of 10 episodes. The series premiered on September 15, 2015, and the final episode aired on November 10, 2015. There is no information on subsequent seasons being produced. If this is the series you are referring to, then the answer is 1 season. If you are referring to a different series  
- score: n/a (None) — 


---
_Generated by report_ab.py._