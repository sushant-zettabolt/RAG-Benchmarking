# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.053 | 0.053 | 1.002x |
| Retrieval + overhead | 0.216 | 0.212 | 1.02x |
| Prompt processing (prefill) | 8.937 | 5.620 | 1.59x |
| Generation (decode) | 4.079 | 4.102 | 1.01x |
| LLM total (prefill+decode) | 13.016 | 9.722 | 1.34x |
| Time to first token | 9.206 | 5.885 | 1.56x |
| End-to-end (total) | 13.281 | 9.983 | 1.33x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 380.9 | 607.2 | 1.59x |
| Decode (generation) t/s | 31.4 | 31.2 | 0.99x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3396.2 | 3396.2 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.053 | 0.053 |
| Retrieval + overhead (s) | 0.216 | 0.212 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 51.0% | 52.0% |

### Speedup summary

- Prefill throughput: **1.59x**  (380.9 → 607.2 t/s)
- Decode throughput:  **0.99x**  (31.4 → 31.2 t/s)
- LLM inference latency: **1.34x**
- End-to-end latency: **1.33x**  (13.28s → 9.98s)

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
| Contains reference (lexical) | 51 (51.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 352425 |
| Tokens/query (prompt / completion) | 3396.2 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 13.281 | 13.214 | 15.014 | 11.330 | 15.307 |
| Time to first token | 9.206 | 9.120 | 10.918 | 7.310 | 11.159 |
| Query embedding | 0.053 | 0.053 | 0.055 | 0.050 | 0.057 |
| Retrieval + overhead | 0.216 | 0.214 | 0.242 | 0.178 | 0.272 |
| Prompt processing (prefill) | 8.937 | 8.843 | 10.638 | 7.057 | 10.878 |
| Generation (decode) | 4.079 | 4.076 | 4.136 | 4.013 | 4.165 |
| LLM total (prefill+decode) | 13.016 | 12.933 | 14.739 | 11.070 | 15.018 |

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
- got: The last time humans were on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent three days on the lunar surface, conducting scientific experiments and collecting samples. They returned to Earth on December 19, 1972. Since then, no human has visited the moon. 

However, in 2020, NASA's Artemis program was announced, with the goal of returning humans to the moon by 2024 and establishing a sustainable presence on the lunar surface. The program includes plans for a new lunar lander, the Space Launch System (SLS)  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The phrase "He ain't heavy, he's my brother" was written by Albert E. Brumley. It was originally titled "He's My Brother" and was written in 1949. The song became famous after Peter, Paul and Mary recorded a version in 1969, with the title changed to "He Ain't Heavy, He's My Brother." The song is often associated with the story of a person helping another person carry a heavy load, and has become a popular phrase to express solidarity and support for others. The song was also famously recorded by The Hollies in 1969, and has since been covered  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I am unable to locate information about a television show called "The Bastard Executioner". If you could provide more context or details about the show you are referring to, I may be able to help you find the information you are looking for. If the information is not available, I will let you know. 

However, I do see information on a television show called "The Bastard Executioner" is a television series that aired on FX from 2015. The series only lasted for one season. It is a historical drama set in 14th century Wales. 

If you are looking for more information about "The Bastard  
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
| Contains reference (lexical) | 52 (52.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 352425 |
| Tokens/query (prompt / completion) | 3396.2 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 9.983 | 9.902 | 11.224 | 8.687 | 11.331 |
| Time to first token | 5.885 | 5.819 | 7.101 | 4.607 | 7.192 |
| Query embedding | 0.053 | 0.054 | 0.055 | 0.050 | 0.056 |
| Retrieval + overhead | 0.212 | 0.211 | 0.236 | 0.176 | 0.269 |
| Prompt processing (prefill) | 5.620 | 5.550 | 6.823 | 4.347 | 6.914 |
| Generation (decode) | 4.102 | 4.099 | 4.159 | 4.036 | 4.171 |
| LLM total (prefill+decode) | 9.722 | 9.655 | 10.951 | 8.430 | 11.060 |

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
- got: The last time humans visited the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt, and they spent three days on the lunar surface. The last time anyone was on the moon was when Eugene Cernan and Harrison Schmitt returned to the lunar module Challenger and lifted off from the moon on December 19, 1972. Since then, there have been no manned missions to the moon, although several robotic missions have been sent to the moon for scientific research and exploration. 

However, NASA plans to return humans to the  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bob Russell and Karl Sigman. The song was originally written for a 1969 film called "The Proud and the Profane" and was performed by Neil Diamond. However, it gained more popularity when it was recorded by The Hollies in 1969. The song's lyrics were inspired by a 19th-century hymn called "He's My Brother", which was written by Albert E. Brumley. But the modern version with the famous lyrics we know today was written by Bob Russell and Karl Sigman. The song's title is a  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information in the given contexts about "The Bastard Executioner." However, I can tell you that it is a short-lived American television drama series that aired on FX from September 15, 2015 to November 10, 2015. The show only had one season with 10 episodes. It was created by Kurt Sutter, who is also known for his work on the television series "Sons of Anarchy." If you are looking for more information about "The Bastard Executioner," I'd be happy to try and help you find it. However, it is not mentioned in the given  
- score: n/a (None) — 


---
_Generated by report_ab.py._