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
| Match rate (LLM judge) | 53.0% | 56.0% |
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
| **Matched (LLM judge)** | **53 (53.0%)** |
| Mean judge score | 0.481 |
| Contains reference (lexical) | 41 (41.0%) |
| Verdicts | correct=48, incorrect=49, partial=3 |
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

### Failed / incorrect queries (47)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | Candidate does not answer the question about 'The Bastard Executioner'. |
| 3 | when did the eagles win last super bowl | incorrect | Candidate answer states a different fact (year of the win) than the reference. |
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate answer states it cannot find the answer, whereas a correct answer is e |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer is unrelated to the question about the subject of Justin Bieber |
| 10 | which state is located in the centre of india | incorrect | Candidate answer does not address the question about the central state of India. |
| 11 | who sang i ran all the way home | incorrect | Candidate answer states a different fact and provides a contradictory explanatio |
| 13 | who was the actor that played ben stone on law and order | incorrect | Candidate answer states a different fact, refusing to confirm the correct answer |
| 14 | who does the voice of nala in the lion king | incorrect | Candidate answer refuses to provide the voice actor for Nala in The Lion King. |
| 15 | who plays gram on the young and the restless | incorrect | Candidate does not provide the correct answer to the question. |
| 19 | what age do you need to be to buy a bb gun | incorrect | Candidate answer refuses to provide the required information. |
| 20 | ethiopia flight 961 crashes in to the sea | incorrect | Candidate answer refuses to answer the question and provides unrelated informati |
| 23 | how many episodes are there in dragon ball z | incorrect | Candidate refuses to answer the question. |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate answer states a different fact and refuses to answer the original ques |
| 27 | who is the girl in green day 21 guns | incorrect | Candidate answer states a different fact and refuses to identify the girl in Gre |
| 31 | who did bette midler portray in the rose | incorrect | Candidate answer states a different fact, refusing to provide an answer. |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | Candidate answer refuses to answer the question. |
| 36 | where does no game no life anime end | incorrect | Candidate answer states a different fact, refusing to answer. |
| 41 | i was a great islamic scholar and mathematician who died in 1131 ce | incorrect | Candidate answer states a different fact about the death year of the mentioned s |
| 42 | who is the coach for the ottawa senators | incorrect | Candidate answer states a different fact (D.J. Smith) than the reference (Guy Bo |
| 44 | when is the last time the vikings were in the nfc championship | incorrect | Candidate answer states a different fact and refuses to answer. |
| 46 | where is lord's prayer found in bible | incorrect | Candidate answer mentions Matthew, which is not a reference in the provided ques |
| 47 | when was the last time oklahoma won a national championship in footbal… | incorrect | Candidate refuses to answer the question and provides unrelated information. |
| 50 | what is the meaning of veronica in english | incorrect | Candidate answer states a different fact about the origin of the name Veronica. |
| 52 | who played solomon in little house on the prairie | incorrect | Candidate answer states a different fact, refusing to provide the answer. |
| 56 | who sang the song good morning good morning | incorrect | Candidate answer states a different fact about the song's artist and credits a s |
| 60 | what's the dog's name on tom and jerry | incorrect | Candidate answer states that the dog's name is not mentioned in the provided con |
| 61 | who are nominated for president of india 2017 | incorrect | Candidate answer states a different fact, refusing to provide the names of nomin |
| 62 | where does the path train stop in newark | incorrect | Candidate answer states the train has multiple stops in Newark, but does not dir |
| 63 | where does route 66 start on the west coast | incorrect | Candidate answer explicitly states Route 66 does not start on the west coast. |
| 64 | who is the first wife on sister wives | incorrect | Candidate answer refuses to provide an answer. |

_…and 17 more (see the JSON report)._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while astronaut Ronald Evans remained in the Command Module in lunar orbit. Since then, no human has returned to the moon. However, there have been numerous robotic missions to the moon by various space agencies and private companies. China's Chang'e 5 mission, for example, successfully landed on the moon in December 2020 and returned lunar  
- score: 1.00 (correct) — Correctly states the last time humans visited the moon as December 1972.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. However, the lyrics you are referring to are not explicitly mentioned in the provided context. The song is well-known for its lyrics about helping others and carrying their burdens, but the specific line "he ain't heavy, he's my brother" is the most famous part of the chorus. The writers Bobby Scott and Bob Russell created this song, which became a hit for The Hollies in 1969. The lyrics of the song promote a message of love, support, and  
- score: 0.80 (correct) — Correctly identifies the song writers, but provides extra context and does not directly answer the question.

**Q5: when did the isle of wight become an island**  
- expected: _During the last Ice Age_  
- got: The Isle of Wight has been an island for millions of years, long before any human records or documentation. It is a natural island, formed by geological processes and separated from the mainland by the Solent strait. The name "Isle of Wight" itself indicates that it has been recognized as an island for a very long time. The question you provided seems to contain a misunderstanding about the Isle of Wight's geographical status. If you have any further questions about the history, geography, or culture of the Isle of Wight, I'd be happy to try to help answer  
- score: 1.00 (correct) — Candidate provides a detailed explanation of the Isle of Wight's geological formation and separation from the mainland.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information on a series called "the bastard executioner." However, I can provide information on the series "Prison Break" and "The O.C." that were mentioned in the provided context.

Prison Break has five seasons. The first four seasons aired from 2005 to 2009, and the fifth season was aired in 2017.

The O.C. has four seasons. The first three seasons aired from 2003 to 2006, and the fourth and final season aired from November  
- score: 0.00 (incorrect) — Candidate does not answer the question about 'The Bastard Executioner'.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won their last Super Bowl in Super Bowl LII, which was played on February 4, 2018. They defeated the New England Patriots by a score of 41-33. This was the Eagles' first Super Bowl victory in franchise history. Before this win, their most recent championship was the NFL Championship in 1960. The Eagles have appeared in a total of four Super Bowls, with their first appearance being in Super Bowl XV against the Oakland Raiders. They have won two of those four appearances, with their other victory coming in Super Bowl  
- score: 0.00 (incorrect) — Candidate answer states a different fact (year of the win) than the reference.

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: I don't have the information about last year's NCAA Women's Basketball winner in the provided contexts. The most recent context, doc_0001.txt, is about Little Mix and Big Sur, and it doesn't contain any details about basketball or the NCAA. The other contexts provide historical information about the University of Texas at Austin, the University's sports programs, and the concept of various types of doubles in basketball but do not mention the winner of last year's NCAA Women's Basketball. If you have access to more contexts or specific documents, please  
- score: 0.00 (incorrect) — Candidate answer states it cannot find the answer, whereas a correct answer is expected.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **56 (56.0%)** |
| Mean judge score | 0.502 |
| Contains reference (lexical) | 45 (45.0%) |
| Verdicts | correct=48, incorrect=45, partial=7 |
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

### Failed / incorrect queries (44)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | Candidate refuses to answer the question and provides unrelated information. |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer is unrelated to the question about the song 'Love Yourself' by  |
| 11 | who sang i ran all the way home | incorrect | Candidate answer discusses unrelated song and its adaptation. |
| 14 | who does the voice of nala in the lion king | incorrect | Candidate answer states a different fact and refuses to provide a definitive ans |
| 15 | who plays gram on the young and the restless | incorrect | Candidate answer states a different fact, mentioning Eileen Davidson who played  |
| 19 | what age do you need to be to buy a bb gun | incorrect | Candidate answer refuses to provide an answer and instead discusses unrelated co |
| 20 | ethiopia flight 961 crashes in to the sea | incorrect | Candidate answer states a different fact and refuses to answer the question. |
| 21 | where was percy jackson and the olympians filmed | incorrect | Candidate answer refuses to provide an answer. |
| 23 | how many episodes are there in dragon ball z | incorrect | Candidate refuses to answer the question. |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate answer states a different fact, refusing to provide an answer. |
| 26 | who plays matthew on anne with an e | incorrect | Candidate states a different fact and refuses to answer based on lack of access, |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | Candidate answer refuses to answer the question. |
| 36 | where does no game no life anime end | incorrect | Candidate states the anime adaptation concluded with the end of the second seaso |
| 41 | i was a great islamic scholar and mathematician who died in 1131 ce | incorrect | Candidate answer states a different fact and refuses to answer the question. |
| 42 | who is the coach for the ottawa senators | incorrect | Candidate answer states a different fact and refuses to provide a clear answer. |
| 43 | last episode of what happens to my family | incorrect | Candidate answer does not address the question about 'what happens to my family' |
| 47 | when was the last time oklahoma won a national championship in footbal… | incorrect | Candidate answer states a different fact and refuses to answer the question. |
| 52 | who played solomon in little house on the prairie | incorrect | Candidate answer states a different fact than the reference. |
| 56 | who sang the song good morning good morning | incorrect | Candidate answer is unrelated to the question about the song 'Good Morning Good  |
| 58 | where does a roadrunner live in the desert | incorrect | Candidate answer states a different fact, refusing to provide a specific locatio |
| 59 | who wrote it's a long long way to pasadena | incorrect | Candidate answer states a different fact, mentioning Sheb Wooley and Pasadena, w |
| 60 | what's the dog's name on tom and jerry | incorrect | Candidate answer states there is no dog named on Tom and Jerry, but then mention |
| 61 | who are nominated for president of india 2017 | incorrect | Candidate explicitly states inability to find answer. |
| 63 | where does route 66 start on the west coast | incorrect | Candidate answer states a different fact about Route 66's starting point. |
| 64 | who is the first wife on sister wives | incorrect | Candidate refuses to answer or states a different fact. |
| 69 | the oligodynamic effect is a phenomenon that describes | incorrect | Candidate answer is unrelated to the oligodynamic effect. |
| 73 | who sings the theme song for the tv show cops | incorrect | Candidate answer states a different fact, mentioning a group called The Insane P |
| 74 | when was corporal punishment banned in south africa | incorrect | Candidate answer states inability to find the answer, whereas a correct answer i |
| 79 | who ordered the forbidden city to be built | incorrect | Candidate answer states a different fact, claiming no one ordered the Forbidden  |
| 80 | who sang let me tell you about the birds and the bees | incorrect | Candidate answer does not address the question about the song 'Let Me Tell You A |

_…and 14 more (see the JSON report)._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while Ron Evans orbited overhead in the Command Module. Cernan was the last person to leave the moon, and no one has returned since. (Source: NASA website)

(Note: This answer is based on the provided context, but it is not directly stated in any of the given texts. I inferred the answer by combining the knowledge that the Apollo  
- score: 1.00 (correct) — Provides the correct date and context for the last moon landing.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies and Neil Diamond are among the notable artists who have recorded versions of this song. The lyrics express a sense of camaraderie and shared responsibility, as the speaker proclaims that they will help their struggling companion, stating "he's my brother." The song has been performed at various events as a symbol of unity and support.

The user is asking about the writers of the song "He Ain't Heavy, He's My Brother". The correct answer is Bobby Scott  
- score: 1.00 (correct) — Correctly identifies Bobby Scott as a writer of the song.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won their most recent Super Bowl in the 2017-18 playoffs, which was Super Bowl LII. The game was played on February 4, 2018, at U.S. Bank Stadium in Minneapolis, Minnesota. The Eagles defeated the New England Patriots with a score of 41-33. This was the Eagles' first Super Bowl victory in franchise history.

In response to the user's question, "when did the eagles win last super bowl", the answer is that the Eagles won Super Bowl LII in  
- score: 1.00 (correct) — Candidate answer conveys the same factual answer as the reference.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I don't have information on a series called "the bastard executioner." However, I can provide information on "Prison Break," "The O.C.," "The Purge: Election Year," or the Comanche, based on the context provided in your message. Please clarify if you had a different series or topic in mind.

To answer your question, "Prison Break" has 5 seasons, "The O.C." has 4 seasons, and "The Purge: Election Year" is a standalone movie. The number of seasons or installments for other series or  
- score: 0.00 (incorrect) — Candidate refuses to answer the question and provides unrelated information.

**Q6: love yourself by justin bieber is about who**  
- expected: _Rihanna_  
- got: The song "Love Will Keep Us Alive" is not directly related to the conversation or context provided. It is a song performed by the Eagles, with lead vocals by Timothy B. Schmit, and written by Jim Capaldi, Paul Carrack, and Peter Vale. The song is about the power of love to sustain a relationship, with lyrics like "Love will keep us alive, love will see us through." It was first performed in 1994 during the Eagles' "Hell Freezes Over" reunion tour and has been covered by Paul Carrack. The song spent three weeks at  
- score: 0.00 (incorrect) — Candidate answer is unrelated to the question about the song 'Love Yourself' by Justin Bieber.

**Q11: who sang i ran all the way home**  
- expected: _The Impalas_  
- got: The Wiggles covered "Man Gave Names to All the Animals" on their "Furry Tales" CD in 2013, with the lyrics "he ran all the way home." However, the original song by Bob Dylan does not contain the phrase "I ran all the way home." It's possible that the Wiggles adapted the lyrics for their version of the song. The original song has the lyrics "Man gave names to all the animals/In the beginning, in the beginning." The Wiggles' version might have a different context or storyline that includes the phrase "he ran  
- score: 0.00 (incorrect) — Candidate answer discusses unrelated song and its adaptation.


---
_Generated by report_ab.py._