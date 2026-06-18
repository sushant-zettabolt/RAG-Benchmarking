# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.054 | 0.053 | 1.01x |
| Retrieval + overhead | 0.243 | 0.241 | 1.01x |
| Prompt processing (prefill) | 26.897 | 12.643 | 2.13x |
| Generation (decode) | 10.632 | 10.627 | 1.000x |
| LLM total (prefill+decode) | 37.530 | 23.271 | 1.61x |
| Time to first token | 27.194 | 12.938 | 2.10x |
| End-to-end (total) | 37.822 | 23.561 | 1.61x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 149.7 | 319.0 | 2.13x |
| Decode (generation) t/s | 12.0 | 12.0 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4022.4 | 4022.4 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.054 | 0.053 |
| Retrieval + overhead (s) | 0.243 | 0.241 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 41.0% | 45.0% |

### Speedup summary

- Prefill throughput: **2.13x**  (149.7 → 319.0 t/s)
- Decode throughput:  **1.00x**  (12.0 → 12.0 t/s)
- LLM inference latency: **1.61x**
- End-to-end latency: **1.61x**  (37.82s → 23.56s)

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
| Contains reference (lexical) | 41 (41.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 415036 |
| Tokens/query (prompt / completion) | 4022.4 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 37.822 | 37.393 | 42.249 | 32.555 | 43.993 |
| Time to first token | 27.194 | 26.766 | 31.571 | 21.953 | 33.278 |
| Query embedding | 0.054 | 0.054 | 0.055 | 0.051 | 0.056 |
| Retrieval + overhead | 0.243 | 0.241 | 0.269 | 0.202 | 0.308 |
| Prompt processing (prefill) | 26.897 | 26.460 | 31.280 | 21.670 | 32.963 |
| Generation (decode) | 10.632 | 10.631 | 10.698 | 10.542 | 10.721 |
| LLM total (prefill+decode) | 37.530 | 37.087 | 41.961 | 32.262 | 43.683 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while astronaut Ronald Evans remained in the Command Module in lunar orbit. Since then, no human has returned to the moon. However, there have been numerous robotic missions to the moon by various space agencies and private companies. China's Chang'e 5 mission, for example, successfully landed on the moon in December 2020 and returned lunar  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. However, the lyrics you are referring to are not explicitly mentioned in the provided context. The song is well-known for its lyrics about helping others and carrying their burdens, but the specific line "he ain't heavy, he's my brother" is the most famous part of the chorus. The writers Bobby Scott and Bob Russell created this song, which became a hit for The Hollies in 1969. The lyrics of the song promote a message of love, support, and  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information on a series called "the bastard executioner." However, I can provide information on the series "Prison Break" and "The O.C." that were mentioned in the provided context.

Prison Break has five seasons. The first four seasons aired from 2005 to 2009, and the fifth season was aired in 2017.

The O.C. has four seasons. The first three seasons aired from 2003 to 2006, and the fourth and final season aired from November  
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
| Contains reference (lexical) | 45 (45.0%) |
| Verdicts | none=100 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 415036 |
| Tokens/query (prompt / completion) | 4022.4 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 23.561 | 23.200 | 25.743 | 20.814 | 26.958 |
| Time to first token | 12.938 | 12.552 | 15.098 | 10.222 | 16.252 |
| Query embedding | 0.053 | 0.053 | 0.055 | 0.050 | 0.057 |
| Retrieval + overhead | 0.241 | 0.241 | 0.270 | 0.202 | 0.304 |
| Prompt processing (prefill) | 12.643 | 12.268 | 14.813 | 9.936 | 15.937 |
| Generation (decode) | 10.627 | 10.627 | 10.697 | 10.517 | 10.714 |
| LLM total (prefill+decode) | 23.271 | 22.900 | 25.456 | 20.530 | 26.651 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while Ron Evans orbited overhead in the Command Module. Cernan was the last person to leave the moon, and no one has returned since. (Source: NASA website)

(Note: This answer is based on the provided context, but it is not directly stated in any of the given texts. I inferred the answer by combining the knowledge that the Apollo  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies and Neil Diamond are among the notable artists who have recorded versions of this song. The lyrics express a sense of camaraderie and shared responsibility, as the speaker proclaims that they will help their struggling companion, stating "he's my brother." The song has been performed at various events as a symbol of unity and support.

The user is asking about the writers of the song "He Ain't Heavy, He's My Brother". The correct answer is Bobby Scott  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information on a series called "the bastard executioner." However, I can provide information on "Prison Break," "The O.C.," "The Purge: Election Year," or the Comanche, based on the context provided in your message. Please clarify if you had a different series or topic in mind.

To answer your question, "Prison Break" has 5 seasons, "The O.C." has 4 seasons, and "The Purge: Election Year" is a standalone movie. The number of seasons or installments for other series or  
- score: n/a (None) — 


---
_Generated by report_ab.py._