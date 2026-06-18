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
| Match rate (LLM judge) | 54.0% | 51.0% |
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
| **Matched (LLM judge)** | **54 (54.0%)** |
| Mean judge score | 0.479 |
| Contains reference (lexical) | 52 (52.0%) |
| Verdicts | correct=49, incorrect=46, partial=5 |
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

### Failed / incorrect queries (46)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | Candidate states a different fact, mentioning a movie instead of a TV show. |
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate states a different fact and refuses to answer the question. |
| 5 | when did the isle of wight become an island | incorrect | Candidate provides a detailed but incorrect answer, stating a different time fra |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer does not mention the correct song or artist. |
| 11 | who sang i ran all the way home | incorrect | Candidate answer states it cannot find the answer, but provides alternative song |
| 15 | who plays gram on the young and the restless | incorrect | Candidate answer does not provide the correct information about who plays Gram o |
| 17 | who is under the mask of darth vader | incorrect | Candidate answer states a different fact, refusing to answer the question. |
| 21 | where was percy jackson and the olympians filmed | incorrect | Candidate answer states it cannot find the answer, but provides information abou |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate answer refuses to provide the answer. |
| 26 | who plays matthew on anne with an e | incorrect | Candidate answer states a different fact and refuses to answer the question. |
| 27 | who is the girl in green day 21 guns | incorrect | Candidate answer states a different fact and cannot provide a definitive answer. |
| 30 | when was the first hunger games book published | incorrect | Candidate answer states the information is not present, but then provides the co |
| 32 | who is the lead singer of depeche mode | incorrect | Candidate answer provides incorrect information about the lead singer of Depeche |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | Candidate answer does not address the question about the butchers' residence. |
| 36 | where does no game no life anime end | incorrect | Candidate answer does not mention the ending of No Game No Life anime. |
| 41 | i was a great islamic scholar and mathematician who died in 1131 ce | incorrect | Candidate answer states different facts and refuses to identify the correct figu |
| 42 | who is the coach for the ottawa senators | incorrect | Candidate answer states a different fact and provides outdated information. |
| 43 | last episode of what happens to my family | incorrect | Candidate refuses to answer and asks for more context instead of providing a fac |
| 47 | when was the last time oklahoma won a national championship in footbal… | incorrect | Candidate answer does not provide the requested information about a national cha |
| 50 | what is the meaning of veronica in english | incorrect | Candidate answer provides a different meaning than the reference. |
| 52 | who played solomon in little house on the prairie | incorrect | Candidate answer states a different fact, Willie Aames instead of Todd Bridges. |
| 54 | an object that moves around an external axis is said to be | incorrect | Candidate answer states a different fact, 'rotating', whereas the correct answer |
| 56 | who sang the song good morning good morning | incorrect | Candidate answer states a different fact and refuses to answer the original ques |
| 58 | where does a roadrunner live in the desert | incorrect | Candidate answer provides general information but does not directly answer the q |
| 59 | who wrote it's a long long way to pasadena | incorrect | Candidate answer states different facts and refuses to answer the original quest |
| 62 | where does the path train stop in newark | incorrect | Candidate answer refuses to provide a direct answer and instead recommends exter |
| 63 | where does route 66 start on the west coast | incorrect | Candidate answer states a different fact about the origin of Route 66. |
| 66 | when did they stop cigarette advertising on television | incorrect | Candidate does not provide a specific date or fact about when cigarette advertis |
| 70 | where does the white witch live in narnia | incorrect | Candidate answer does not provide the location of the White Witch's residence. |
| 71 | how many games in a row have the uconn women's basketball team won | incorrect | Candidate answer states a different fact and refuses to provide the answer. |

_…and 16 more (see the JSON report)._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time humans were on the moon was during the Apollo 17 mission in December 1972. The mission was crewed by astronauts Eugene Cernan, Ronald Evans, and Harrison Schmitt. Eugene Cernan and Harrison Schmitt spent three days on the lunar surface, while Ronald Evans remained in orbit around the moon. The mission concluded on December 19, 1972, when the astronauts returned to Earth. 

Since then, there have been several unmanned missions to the moon, but no human has visited the moon. However, NASA is currently planning to return humans to the moon by 2025 as part of the  
- score: 1.00 (correct) — Correctly states the last time humans were on the moon as December 1972.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The phrase "He ain't heavy, he's my brother" is a famous saying that was popularized by a song of the same name. The song was written by Bobby Scott and Bob Russell, and it was first recorded by Kelly Gordon in 1969. However, it was the 1970 version by Neil Sedaka that became a hit single and made the phrase a well-known catchphrase. The song's lyrics were written by Bobby Scott and Bob Russell, and they are based on a phrase that was coined by a social worker, John E. McCarthy, in the 1950s. McCarthy used the phrase as a way  
- score: 0.80 (correct) — Correctly identifies Bobby Scott and Bob Russell as the songwriters.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won Super Bowl LII (52) on February 4, 2018. They defeated the New England Patriots by a score of 41-33. This was the Eagles' first Super Bowl victory in franchise history. The game was played at U.S. Bank Stadium in Minneapolis, Minnesota. The Eagles were led by quarterback Nick Foles, who was the Super Bowl MVP. The Eagles' victory marked the end of the Patriots' bid for a 19-0 season, as they had finished the 2017 regular season with a 13-3 record. The Eagles' win also marked the first time in  
- score: 1.00 (correct) — Correctly states the Eagles won Super Bowl LII in 2018.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information about a TV show called "The Bastard Executioner". However, there was a TV series called "The Bastard Executioner" that aired on FX in 2015. It was a historical drama series created by Kurt Sutter, and it only had one season, which consisted of 10 episodes. It premiered on September 15, 2015, and the final episode aired on November 17, 2015. The show was canceled after one season. If you have any further questions, please let me know! 

However, if you are asking about The Bastard Executioner a movie  
- score: 0.00 (incorrect) — Candidate states a different fact, mentioning a movie instead of a TV show.

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: I don't see any information about last year's NCAA women's basketball champion in the provided contexts. The information provided is mostly about men's basketball and the University of Texas at Austin, as well as other unrelated topics. If you're looking for information on the most recent NCAA women's basketball champion, I recommend checking the official NCAA website or a reliable sports news source for the most up-to-date information. 

However, I can tell you that the University of Connecticut has a rich history of winning NCAA women's basketball championships. They have won 11 national titles in the NCAA tournament. 

If you would like information about the 2025  
- score: 0.00 (incorrect) — Candidate states a different fact and refuses to answer the question.

**Q5: when did the isle of wight become an island**  
- expected: _During the last Ice Age_  
- got: The Isle of Wight is not mentioned in the provided contexts. However, it is a real island located off the coast of southern England. The Isle of Wight is thought to have been an island since the end of the last Ice Age, which was around 10,000 years ago. It was once connected to the mainland by a land bridge, but as the sea levels rose due to the melting of the ice, the island became isolated. The exact date when the Isle of Wight became an island is not certain, but it is believed to be around 8,000 to 10,000 years ago. 

If you  
- score: 0.00 (incorrect) — Candidate provides a detailed but incorrect answer, stating a different time frame than the reference.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **51 (51.0%)** |
| Mean judge score | 0.448 |
| Contains reference (lexical) | 57 (57.0%) |
| Verdicts | incorrect=49, correct=42, partial=9 |
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

### Failed / incorrect queries (49)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | incorrect | Candidate states a different fact, mentioning unmanned spacecraft and offering t |
| 3 | when did the eagles win last super bowl | incorrect | Candidate answer states a different year than the reference. |
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate answer refuses to provide the answer and provides unrelated informatio |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer states a different fact about the song's meaning. |
| 9 | what is the maximum data rate for the 802.11a standard select one | incorrect | Candidate answer states a different fact about the maximum data rate. |
| 11 | who sang i ran all the way home | incorrect | Candidate answer states a different fact and refuses to answer the original ques |
| 13 | who was the actor that played ben stone on law and order | incorrect | Candidate answer states a different fact, refusing to answer the question. |
| 15 | who plays gram on the young and the restless | incorrect | Candidate answer explicitly states it does not mention the character Gram. |
| 16 | what is the oath that new citizens take | incorrect | Candidate answer contains outdated and incorrect clauses of the oath. |
| 19 | what age do you need to be to buy a bb gun | incorrect | Candidate answer states different facts and refuses to provide the answer. |
| 21 | where was percy jackson and the olympians filmed | incorrect | Candidate answer states it cannot find the answer, but then provides specific in |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate refuses to answer and instead asks for more context. |
| 25 | when was the first australian prime minister elected | incorrect | Candidate answer states a different fact and refuses to provide the answer. |
| 26 | who plays matthew on anne with an e | incorrect | Candidate refuses to answer the question. |
| 27 | who is the girl in green day 21 guns | incorrect | Candidate answer states a different fact, refusing to acknowledge a girl is asso |
| 28 | who plays joker in batman the dark knight | incorrect | Candidate answer is about a different context and person. |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | Candidate answer states a different fact and refuses to answer the question. |
| 36 | where does no game no life anime end | incorrect | Candidate answer refuses to provide the information. |
| 37 | when did taylor swift's first album release | incorrect | Candidate answer states it cannot find the answer, but then provides the correct |
| 40 | what are the ranks in the us navy | incorrect | Candidate answer does not address the question about officer ranks. |
| 41 | i was a great islamic scholar and mathematician who died in 1131 ce | incorrect | Candidate answer does not identify the correct scholar, instead providing unrela |
| 42 | who is the coach for the ottawa senators | incorrect | Candidate answer states a different fact, the coach is D.J. Smith, not mentioned |
| 43 | last episode of what happens to my family | incorrect | Candidate answer refuses to provide a factual answer and instead tries to guess  |
| 44 | when is the last time the vikings were in the nfc championship | incorrect | Candidate provides incorrect information about the Vikings' last NFC Championshi |
| 46 | where is lord's prayer found in bible | incorrect | Candidate answer does not answer the question about where the Lord's Prayer is f |
| 47 | when was the last time oklahoma won a national championship in footbal… | incorrect | Candidate answer states a different fact and refuses to answer the question dire |
| 50 | what is the meaning of veronica in english | incorrect | Candidate answer provides a different meaning than the reference. |
| 52 | who played solomon in little house on the prairie | incorrect | Candidate answer states it cannot find the answer, whereas a correct answer is p |
| 54 | an object that moves around an external axis is said to be | incorrect | Candidate answer states a different fact, 'rotating' is not among the reference  |
| 56 | who sang the song good morning good morning | incorrect | Candidate answer states a different fact and refuses to answer the original ques |

_…and 19 more (see the JSON report)._

### Example answers

#### Correct

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. However, the song's original title was "Jimmy Mack" and was written by Scott. Russell then rewrote the lyrics as "He Ain't Heavy, He's My Brother," and it was recorded by the Hollies in 1969, becoming a hit single. The song was later adopted as the anthem for the Boys Town organization in the United States, a home for troubled youth. It has since become a popular song around the world, known for its uplifting message and memorable chorus. The song's most famous line, "  
- score: 0.80 (correct) — Candidate conveys the same factual answer as the reference, with additional context.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find any information on a TV show called "The Bastard Executioner." However, I did find a TV series called "The Bastard Executioner" that aired on FX from 2015 to 2015. It was a historical drama series that aired for one season, which consisted of 10 episodes. The series premiered on September 15, 2015, and the final episode aired on November 10, 2015. There is no information on subsequent seasons being produced. If this is the series you are referring to, then the answer is 1 season. If you are referring to a different series  
- score: 1.00 (correct) — Correctly states the number of seasons as 1.

**Q5: when did the isle of wight become an island**  
- expected: _During the last Ice Age_  
- got: There is no information in the provided context about the Isle of Wight becoming an island. The context provided discusses Wake Island, which is a small island in the Pacific Ocean. If you're looking for information on the Isle of Wight, I'd be happy to try and help you find it elsewhere. The Isle of Wight is actually a small island located off the coast of southern England in the United Kingdom. It became an island due to rising sea levels, likely following the last ice age. However, the exact time it became an island is not well-documented and would require further research. The earliest known human habitation on the  
- score: 0.80 (partial) — Candidate provides correct information but lacks specificity and accuracy in the timeline.

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: I don't see any information in the given context about anyone being on the moon recently. However, according to NASA, the last time humans visited the moon was during the Apollo 17 mission in December 1972. Since then, there have been several unmanned spacecraft that have visited the moon, but no human has returned to the lunar surface. 

If you're looking for more up-to-date information, I'd be happy to help you find it. Alternatively, I can provide you with information on the Apollo 17 mission or other NASA-related topics if you're interested. 

Contexts provided don't seem to contain any information about space  
- score: 0.00 (incorrect) — Candidate states a different fact, mentioning unmanned spacecraft and offering to find more up-to-date information.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won their last Super Bowl in 2018. They defeated the New England Patriots in Super Bowl LII (52) on February 4, 2018, at U.S. Bank Stadium in Minneapolis, Minnesota, by a score of 41-33. This was the Eagles' first Super Bowl victory in franchise history. The quarterback who led the Eagles to victory was Nick Foles. He was the Super Bowl MVP for that game. The Eagles' win in Super Bowl LII was also the first time a team from the NFC had won the Super Bowl in the 21st century without Tom Brady or Peyton Manning  
- score: 0.00 (incorrect) — Candidate answer states a different year than the reference.

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: I am unable to verify the winner of last year's NCAA women's basketball.  I don't have any information about the winner of that event. I can tell you that the University of Texas at Austin has won several NCAA Division I National Men's and Women's sports championships, but I do not know the winner of the 2025 NCAA women's basketball championship. If you want to know the 2025 NCAA women's basketball championship winner, I would suggest looking it up on a search engine or the official NCAA website. I can tell you, however, that the 2021 NCAA women's basketball championship was won by the Stanford  
- score: 0.00 (incorrect) — Candidate answer refuses to provide the answer and provides unrelated information.


---
_Generated by report_ab.py._