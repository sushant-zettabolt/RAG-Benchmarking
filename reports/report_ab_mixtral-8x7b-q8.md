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
| Match rate (LLM judge) | 53.0% | 60.0% |
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
| **Matched (LLM judge)** | **53 (53.0%)** |
| Mean judge score | 0.483 |
| Contains reference (lexical) | 43 (43.0%) |
| Verdicts | correct=49, incorrect=47, partial=4 |
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

### Failed / incorrect queries (47)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | Candidate states it cannot find the answer, whereas reference answers provide a  |
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate refuses to answer the question and provides unrelated information. |
| 5 | when did the isle of wight become an island | incorrect | Candidate answer states the Isle of Wight has always been an island, contradicti |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer is unrelated to the question about 'love yourself' by Justin Bi |
| 11 | who sang i ran all the way home | incorrect | Candidate answer states a different fact and provides incorrect information abou |
| 13 | who was the actor that played ben stone on law and order | incorrect | Candidate answer states a different fact, referring to a different work. |
| 14 | who does the voice of nala in the lion king | incorrect | Candidate answer states a different fact and provides additional context not pre |
| 15 | who plays gram on the young and the restless | incorrect | Candidate answer states a different fact, mentioning Christopher Lloyd instead o |
| 19 | what age do you need to be to buy a bb gun | incorrect | Candidate answer refuses to provide the minimum age for buying a BB gun. |
| 20 | ethiopia flight 961 crashes in to the sea | incorrect | Candidate answer refuses to answer the question and provides unrelated informati |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate answer states a different fact and refuses to answer the question. |
| 25 | when was the first australian prime minister elected | incorrect | Candidate answer states a different fact, refusing to answer due to lack of cont |
| 27 | who is the girl in green day 21 guns | incorrect | Candidate answer states a different fact than the reference. |
| 28 | who plays joker in batman the dark knight | incorrect | Candidate answer provides unrelated information about Gotham season 4. |
| 29 | when was the south asian association for regional co-operation (saarc)… | incorrect | Candidate answer states it cannot find the answer, but then provides the correct |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | Candidate answer states a different fact, refusing to answer the question. |
| 36 | where does no game no life anime end | incorrect | Candidate does not answer the question about the ending location, but rather the |
| 42 | who is the coach for the ottawa senators | incorrect | Candidate answer states a different fact and refuses to provide the answer. |
| 43 | last episode of what happens to my family | incorrect | Candidate answer states a different fact, refusing to provide information withou |
| 44 | when is the last time the vikings were in the nfc championship | incorrect | Candidate answer refuses to provide an answer and suggests consulting other sour |
| 47 | when was the last time oklahoma won a national championship in footbal… | incorrect | Candidate states a different fact, refusing to provide the exact year when Oklah |
| 49 | where did the allies go after north africa | incorrect | Candidate answer provides unrelated information and refuses to answer the questi |
| 50 | what is the meaning of veronica in english | incorrect | Candidate answer provides incorrect information about the origin and meaning of  |
| 54 | an object that moves around an external axis is said to be | incorrect | Candidate answer discusses audio panning, whereas question is about an object mo |
| 56 | who sang the song good morning good morning | incorrect | Candidate answer is unrelated to the question and mentions a different song. |
| 59 | who wrote it's a long long way to pasadena | incorrect | Candidate states a different fact. |
| 60 | what's the dog's name on tom and jerry | incorrect | Candidate answer states a different fact by mentioning Spots, which is not relev |
| 61 | who are nominated for president of india 2017 | incorrect | Candidate answer states a different fact and refuses to answer the question. |
| 63 | where does route 66 start on the west coast | incorrect | Candidate answer states a different fact, claiming Route 66 does not start on th |
| 70 | where does the white witch live in narnia | incorrect | Candidate answer states a different fact, mentioning multiple locations and unce |

_…and 17 more (see the JSON report)._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while Ronald Evans orbited overhead in the Command Module. No human has returned to the moon since then. However, there are plans for future lunar missions by various space agencies and private companies. For example, NASA's Artemis program aims to land "the first woman and the next man" on the moon by 2024, and China's Chang  
- score: 1.00 (correct) — Correctly states the last time humans visited the moon as December 1972.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies, a British rock group, had a hit version of the song in 1969. The lyrics describe the bond between two brothers and the idea that even though one might be a burden, he is still loved and cared for. The title is a reference to a famous phrase spoken by English children's charity leader Sir William Booth, who said, "A man who is good enough to carry his brother's burdens is good enough to carry a nation." The song has  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won their last Super Bowl in Super Bowl LII on February 4, 2018. They defeated the New England Patriots with a score of 41-33. This was their first Super Bowl victory in franchise history. The game was notable as the first Super Bowl to go into overtime. The Eagles' quarterback, Nick Foles, was named the Super Bowl MVP. He completed 28 out of 43 passes for 373 yards, 3 touchdowns, and 1 interception. The Eagles' defense also made key plays, including  
- score: 0.80 (correct) — Candidate conveys the same factual answer as the reference, although with extra context.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I couldn't find specific information about the number of seasons of "The Bastard Executioner" within the provided contexts. "The Bastard Executioner" is a different television series from "Prison Break", "The O.C.", "The Purge: Election Year", and "Comanche" which are mentioned in the given contexts. To get the information you need, you might want to look up the details of "The Bastard Executioner" separately. In general, you can check the show's official website or trusted entertainment databases such as IMDb for accurate information regarding the  
- score: 0.00 (incorrect) — Candidate states it cannot find the answer, whereas reference answers provide a specific fact.

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: I don't have information about last year's NCAA women's basketball winner in the provided context. However, the University of Texas at Austin has a strong athletics program, and its women's basketball team has gained prominence in recent years. They advanced to the NCAA Tournament Sweet Sixteen in 2002 and 2004, the Elite Eight in 2006 and 2008, and the Final Four in 2003. For the most accurate and up-to-date information, I recommend checking the official NCAA website or reput  
- score: 0.00 (incorrect) — Candidate refuses to answer the question and provides unrelated information.

**Q5: when did the isle of wight become an island**  
- expected: _During the last Ice Age_  
- got: The Isle of Wight has always been an island. It is located in the English Channel, off the south coast of England. It is separated from the mainland by the Solent strait. The island has been inhabited since the Paleolithic era, and it has a rich history as a site of cultural and economic importance. The name "Isle of Wight" first appears in written records in the 7th century, but the island has been known by various names throughout its history. Despite its name, it has always been an island and has never been connected to the mainland. The Solent  
- score: 0.00 (incorrect) — Candidate answer states the Isle of Wight has always been an island, contradicting the reference that it became an island during the last Ice Age.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **60 (60.0%)** |
| Mean judge score | 0.535 |
| Contains reference (lexical) | 47 (47.0%) |
| Verdicts | correct=50, incorrect=40, partial=10 |
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

### Failed / incorrect queries (40)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | Candidate answer states a different fact and refuses to answer the original ques |
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate does not provide the correct winner of the NCAA Women's Basketball cha |
| 5 | when did the isle of wight become an island | incorrect | Candidate answer states a different fact, claiming the Isle of Wight has always  |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer is unrelated to the question about Justin Bieber's song 'Love Y |
| 11 | who sang i ran all the way home | incorrect | Candidate answer does not identify the original singer of the song. |
| 13 | who was the actor that played ben stone on law and order | incorrect | Candidate answer states a different fact. |
| 14 | who does the voice of nala in the lion king | incorrect | Candidate answer refuses to answer the question. |
| 15 | who plays gram on the young and the restless | incorrect | Candidate answer states a different fact than the reference. |
| 19 | what age do you need to be to buy a bb gun | incorrect | Candidate answer refuses to provide an answer and does not state the minimum age |
| 21 | where was percy jackson and the olympians filmed | incorrect | Candidate answer states a different fact, mentioning New Orleans which is not in |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate answer states a different fact, refusing to provide information about  |
| 31 | who did bette midler portray in the rose | incorrect | Candidate answer states a different fact, refusing to answer. |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | Candidate answer refuses to answer the question. |
| 35 | who wrote cant get you out of my head lyrics | incorrect | Candidate answer is unrelated to the question about 'Can't Get You Out of My Hea |
| 36 | where does no game no life anime end | incorrect | Candidate answer states a different fact, refusing to answer the question. |
| 43 | last episode of what happens to my family | incorrect | Candidate answer refuses to provide factual information about the final episode  |
| 47 | when was the last time oklahoma won a national championship in footbal… | incorrect | Candidate states a different fact, claiming the most recent championship was in  |
| 49 | where did the allies go after north africa | incorrect | The candidate answer describes the Allies' actions in the Pacific, but does not  |
| 50 | what is the meaning of veronica in english | incorrect | Candidate answer states a different fact about the origin and meaning of the nam |
| 55 | architectural elements forming rib vaults eg wells cathedral | incorrect | Candidate answer discusses ribs and their patterns, but does not mention the arc |
| 56 | who sang the song good morning good morning | incorrect | Candidate answer is unrelated to the question about the song 'Good Morning Good  |
| 59 | who wrote it's a long long way to pasadena | incorrect | Candidate answer is unrelated to the question and does not provide information a |
| 60 | what's the dog's name on tom and jerry | incorrect | Candidate answer states there is no dog named on Tom and Jerry, which contradict |
| 61 | who are nominated for president of india 2017 | incorrect | Candidate refuses to provide the list of nominees. |
| 63 | where does route 66 start on the west coast | incorrect | Candidate answer states a different fact and provides unrelated information. |
| 74 | when was corporal punishment banned in south africa | incorrect | Candidate answer refuses to provide information on the topic. |
| 78 | who captained the first european ship to sail around the tip of africa | incorrect | Candidate answer provides incorrect information and extra context. |
| 79 | who ordered the forbidden city to be built | incorrect | Candidate answer states a different fact, claiming no single person ordered the  |
| 80 | who sang let me tell you about the birds and the bees | incorrect | Candidate answer does not mention the song 'Let Me Tell You About the Birds and  |
| 83 | who is the minister of local government in zimbabwe | incorrect | Candidate refuses to provide the answer. |

_…and 10 more (see the JSON report)._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: The last time anyone was on the moon was during the Apollo 17 mission in December 1972. Astronauts Eugene Cernan and Harrison Schmitt spent about 75 hours on the lunar surface, while astronaut Ronald Evans orbited overhead in the Command Module. Since then, no human has returned to the moon. However, there have been numerous robotic missions to the moon by various countries and organizations, with plans for future manned missions in development. For example, NASA's Artemis program aims to return humans to the moon by 2024.  
- score: 1.00 (correct) — Correctly states the last time humans visited the moon as December 1972.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott and Bob Russell. The Hollies, a British rock group, had a hit version of the song in 1969. The lyrics describe the bond between two brothers, with the chorus repeating the phrase "he ain't heavy, he's my brother." The song has been covered by various artists and has been used in films and television shows. The title and lyrics of the song have also been used in various contexts to convey a message of support and unity. Bobby Scott and Bob Russell wrote the lyrics  
- score: 1.00 (correct) — Candidate conveys the same factual information as the references.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: The Philadelphia Eagles won their last Super Bowl in Super Bowl LII on February 4, 2018. They defeated the New England Patriots with a score of 41-33. This victory marked the first Super Bowl championship for the Eagles in franchise history. The game was played at U.S. Bank Stadium in Minneapolis, Minnesota. Nick Foles, the Eagles' quarterback, was named the Super Bowl MVP. This win also ended the Patriots' chance of tying the Pittsburgh Steelers for the most Super Bowl wins, as the Eagles prevented them from winning their  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: I cannot provide an answer as there is no context or document provided that discusses "the bastard executioner" and its number of seasons. However, I can look up information about "the bastard executioner" if you provide more context or details.

If you meant "The O.C." instead of "the bastard executioner," then there are four seasons of The O.C. according to context 4 and 5. The O.C. was an American teen drama television series that aired in the United States from November 2, 2006 to February 22,  
- score: 0.00 (incorrect) — Candidate answer states a different fact and refuses to answer the original question.

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: The University of Texas at Austin has a strong athletics program, but the provided context does not include specific information about who won the most recent NCAA Women's Basketball championship. You may need to look up the latest news or sports records for this information. However, it is worth noting that the University of Texas has won a total of 50 national championships, including 42 NCAA national championships as of 2015. The women's basketball team has had some success in recent years, advancing to the NCAA Tournament Sweet Sixteen in 2002 and 20  
- score: 0.00 (incorrect) — Candidate does not provide the correct winner of the NCAA Women's Basketball championship.

**Q5: when did the isle of wight become an island**  
- expected: _During the last Ice Age_  
- got: The Isle of Wight has been an island for millions of years, long before any human records or documentation. It is a natural island located in the English Channel, off the south coast of England. It has never been a part of the mainland and has always been separated by water. Therefore, it is not accurate to say that the Isle of Wight "became" an island at any specific point in time. It has always been an island.

It is possible that you may be confusing the Isle of Wight with another place or that you may have some other question in mind. If you have any  
- score: 0.00 (incorrect) — Candidate answer states a different fact, claiming the Isle of Wight has always been an island.


---
_Generated by report_ab.py._