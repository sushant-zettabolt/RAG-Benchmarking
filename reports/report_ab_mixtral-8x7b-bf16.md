# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.003x |
| Retrieval + overhead | 0.228 | 0.225 | 1.01x |
| Prompt processing (prefill) | 29.145 | 13.767 | 2.12x |
| Generation (decode) | 10.654 | 10.633 | 1.002x |
| LLM total (prefill+decode) | 39.799 | 24.400 | 1.63x |
| Time to first token | 29.384 | 14.003 | 2.10x |
| End-to-end (total) | 40.032 | 24.631 | 1.63x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 149.4 | 316.6 | 2.12x |
| Decode (generation) t/s | 12.0 | 12.0 | 1.00x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4350.5 | 4350.5 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.228 | 0.225 |
| Match rate (LLM judge) | 0% | 0% |
| Contains reference (lexical) | 40.0% | 30.0% |

### Speedup summary

- Prefill throughput: **2.12x**  (149.4 → 316.6 t/s)
- Decode throughput:  **1.00x**  (12.0 → 12.0 t/s)
- LLM inference latency: **1.63x**
- End-to-end latency: **1.63x**  (40.03s → 24.63s)

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
| End-to-end (total) | 40.032 | 40.636 | 46.089 | 35.851 | 46.089 |
| Time to first token | 29.384 | 29.941 | 35.372 | 25.282 | 35.372 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.228 | 0.251 | 0.278 | 0.061 | 0.278 |
| Prompt processing (prefill) | 29.145 | 29.789 | 35.117 | 25.044 | 35.117 |
| Generation (decode) | 10.654 | 10.672 | 10.723 | 10.574 | 10.723 |
| LLM total (prefill+decode) | 39.799 | 40.452 | 45.840 | 35.618 | 45.840 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about three days on the lunar surface, while Ron Evans orbited overhead in the Command Module. Cernan was the last person to leave the moon, and no humans have returned since then. The Apollo program, which included six manned missions to the moon, was the only spaceflight mission to land humans on the moon. It was active from 1961 to 1972 and was part  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies, a British rock group, had a hit with the song in 1969. The song has also been covered by other artists, including Neil Diamond and The Band. The lyrics include the lines "He ain't heavy, he's my brother" and "His welfare is of my concern, no burden is he to bear, we'll get there." The song is about supporting and caring for others, and has been a popular choice for funerals and memorial services.  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information on a television series called "the bastard executioner." However, I can provide information on "Chicago Fire" which was mentioned in several of the contexts provided. There are currently 10 seasons of "Chicago Fire" with the latest season, season 10, currently airing. Each season typically contains 22-24 episodes. The series follows the lives of the firefighters and paramedics working at the Chicago Fire Department at the firehouse of Engine 51, Truck 81, Squad 3, Ambulance 61 and  
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
| Contains reference (lexical) | 3 (30.0%) |
| Verdicts | none=10 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 44785 |
| Tokens/query (prompt / completion) | 4350.5 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 24.631 | 24.792 | 27.780 | 22.587 | 27.780 |
| Time to first token | 14.003 | 14.169 | 17.095 | 11.999 | 17.095 |
| Query embedding | 0.011 | 0.011 | 0.012 | 0.010 | 0.012 |
| Retrieval + overhead | 0.225 | 0.245 | 0.273 | 0.061 | 0.273 |
| Prompt processing (prefill) | 13.767 | 14.006 | 16.845 | 11.763 | 16.845 |
| Generation (decode) | 10.633 | 10.633 | 10.691 | 10.593 | 10.691 |
| LLM total (prefill+decode) | 24.400 | 24.635 | 27.536 | 22.356 | 27.536 |

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
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about three days on the lunar surface, while Ron Evans orbited above in the Command Module. Since then, no human has returned to the moon. The Apollo program, which was responsible for these lunar missions, was officially terminated in 1975. Currently, various space agencies and private companies are working on plans to return humans to the moon in the coming years, such as NASA's Artemis  
- score: n/a (None) — 

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies recorded a popular version of the song in 1969. The song's title and lyrics express the idea that helping and supporting others is a shared responsibility and not a burden. The phrase "he ain't heavy, he's my brother" is often used to describe a situation where one person is assisting or carrying the load of another person, emphasizing the idea that the person being helped is a sibling or equal, not a burden. The song has been covered by  
- score: n/a (None) — 

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information on a series called "the bastard executioner." However, I can provide information on "Chicago Fire" that was part of the context provided to me. Chicago Fire has 10 seasons as of my knowledge up to 2026. If you have any questions about any of the contexts provided or another specific topic, please let me know!

For the document_metadata:
sourceDocument: doc_0022.txt
published: 6/12/2026, 10:09:50 AM

The fourth  
- score: n/a (None) — 


---
_Generated by report_ab.py._