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
| Match rate (LLM judge) | 69.0% | 74.0% |
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
| **Matched (LLM judge)** | **69 (69.0%)** |
| Mean judge score | 0.602 |
| Contains reference (lexical) | 43 (43.0%) |
| Verdicts | correct=59, incorrect=31, partial=10 |
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

### Failed / incorrect queries (31)

| Q# | question | verdict | reason |
|---|---|---|---|
| 2 | how many seasons of the bastard executioner are there | incorrect | Candidate answer states 'likely we don't have info', which implies a lack of kno |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer states a different fact than the reference. |
| 11 | who sang i ran all the way home | incorrect | Candidate answer lists multiple possible songs, but does not confirm any of them |
| 13 | who was the actor that played ben stone on law and order | incorrect | Candidate answer incorrectly identifies the character and show. |
| 15 | who plays gram on the young and the restless | incorrect | Candidate does not provide the correct name of the actor who plays Gram. |
| 17 | who is under the mask of darth vader | incorrect | Candidate answer discusses multiple actors, whereas reference answer is a single |
| 18 | who had a baby at 100 in the bible | incorrect | CANDIDATE incorrectly identifies the biblical figure who gave birth at 100. |
| 19 | what age do you need to be to buy a bb gun | incorrect | Candidate answer states a different fact than the reference. |
| 21 | where was percy jackson and the olympians filmed | incorrect | Candidate answer states a different fact, mentioning the UK instead of Vancouver |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate answer does not mention the correct actor, Jacob Tremblay. |
| 26 | who plays matthew on anne with an e | incorrect | Candidate does not provide the name of the actor who plays Matthew. |
| 27 | who is the girl in green day 21 guns | incorrect | Candidate answer states a different fact, refusing to provide a clear answer. |
| 36 | where does no game no life anime end | incorrect | Candidate answer is unrelated to the question about No Game No Life anime ending |
| 41 | i was a great islamic scholar and mathematician who died in 1131 ce | incorrect | The candidate answer is a statement, not a response to a question. |
| 42 | who is the coach for the ottawa senators | incorrect | Candidate answer states a different coach than the reference. |
| 43 | last episode of what happens to my family | incorrect | Candidate does not provide a factual answer, instead it's a process of eliminati |
| 44 | when is the last time the vikings were in the nfc championship | incorrect | Candidate answer states the Vikings have never been to an NFC Championship game, |
| 52 | who played solomon in little house on the prairie | incorrect | Candidate does not provide the correct actor's name. |
| 55 | architectural elements forming rib vaults eg wells cathedral | incorrect | Candidate answer does not directly address the question about architectural elem |
| 56 | who sang the song good morning good morning | incorrect | Candidate incorrectly identifies the song as by The Beatles, when the correct an |
| 59 | who wrote it's a long long way to pasadena | incorrect | Candidate answer does not match any reference answer. |
| 61 | who are nominated for president of india 2017 | incorrect | Candidate lists a different fact than the reference answers. |
| 64 | who is the first wife on sister wives | incorrect | Candidate answer refers to a different show and person, Jim Jones, instead of th |
| 73 | who sings the theme song for the tv show cops | incorrect | Candidate incorrectly identifies the performer as The Who and The Cops Theme, wh |
| 79 | who ordered the forbidden city to be built | incorrect | Candidate answer refers to a different historical context and building. |
| 80 | who sang let me tell you about the birds and the bees | incorrect | Candidate answer states a different fact, mentioning a band 'The Mysterious' tha |
| 83 | who is the minister of local government in zimbabwe | incorrect | No information about current minister of local government in Zimbabwe. |
| 87 | who plays the saint of killers on preacher | incorrect | Candidate answer states a different fact, James Ransone instead of Graham McTavi |
| 88 | when did the royal proclamation of 1763 end | incorrect | Candidate answer does not address the question about when the Royal Proclamation |
| 89 | who is playing the halftime show at super bowl 2016 | incorrect | Candidate answer states a different fact than the reference answers. |

_…and 1 more (see the JSON report)._

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>We need answer: last time anyone was on the moon. That's Apollo 17 in December 1972. But perhaps mention last manned lunar landing. The last time humans visited the Moon was Apollo 17. They left on December 7 1972, landed December 11, 1972. So answer: December 1972. Provide details.</think>The last time humans walked on the Moon was during NASA’s **Apollo 17** mission, which launched on **December 7 1972**. The crew landed on the lunar surface on **December 11 1972  
- score: 1.00 (correct) — Candidate conveys the same factual answer as references.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics"

We need to answer: the song "He Ain't Heavy, He's My Brother" is written by Bobby Scott and Bob Russell. Actually the lyrics were written by Bob Russell, music by Bobby Scott. The question: "who wrote he ain't heavy he's my brother lyrics" So answer: Bob Russell wrote the lyrics, and Bobby Scott composed the music. Provide that info. Also maybe mention the song was originally recorded by The Hollies. Provide concise answer. No extraneous.</think>The lyrics to **“He Ain’t Heavy  
- score: 0.80 (correct) — correctly identifies Bob Russell as lyricist, but lacks clarity on music composition

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: <think>We need to answer: When did the Eagles win last Super Bowl? The Philadelphia Eagles have won one Super Bowl: Super Bowl LII (52) in 2018. They defeated the Patriots 41-33. So last win: February 4, 2018 (Super Bowl LII). Might mention year 2018. Provide answer.</think>The Philadelphia Eagles last won a Super Bowl on **February 4, 2018**—Super Bowl LII, when they defeated the New England Patriots 41–33. This remains the franchise’s sole  
- score: 0.80 (correct) — Mentions the correct year and outcome of the Eagles' last Super Bowl win.

#### Incorrect

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>We have to answer user question: "how many seasons of the bastard executioner are there". We need to find context: The user asks about "bastard executioner". That is presumably a show. We need to search context for "bastard executioner". None of the provided contexts mention that. We have contexts about Prison Break, The Vampire Diaries, The Purge, The O.C., etc. No mention of "bastard executioner". Possibly it's a show "The Bastard Executioner". I don't see it. We need to provide answer: likely we don't have info. We can say  
- score: 0.00 (incorrect) — Candidate answer states 'likely we don't have info', which implies a lack of knowledge rather than a factual answer.

**Q6: love yourself by justin bieber is about who**  
- expected: _Rihanna_  
- got: <think>We need to answer: "love yourself by justin bieber is about who". The user asks: "love yourself by justin bieber is about who". They likely want to know who the song is about. We have no context about that song. The provided contexts are about other songs like Pumped Up Kicks, The Chain, etc. There's no mention of Justin Bieber or "Love Yourself". We cannot answer based on provided contexts. Should we use external knowledge? The guidelines? We can answer with known info: The song is about a romantic relationship, about a former lover, telling them to love themselves.  
- score: 0.00 (incorrect) — Candidate answer states a different fact than the reference.

**Q11: who sang i ran all the way home**  
- expected: _The Impalas_  
- got: <think>The user asks: "who sang i ran all the way home". This is likely a song title: "I Ran (So Far Away)" is by A Flock of Seagulls, but the phrase "I Ran All the Way Home" might be a song by the band "The Killers"? Wait: There's a song "I Ran All the Way Home" by "The Mutton Birds"? Let's search memory: "I Ran All the Way Home" is a song by "The Goats" maybe? Actually there's a song "I Ran All the Way Home" by the band "The Dead" or  
- score: 0.00 (incorrect) — Candidate answer lists multiple possible songs, but does not confirm any of them as the correct answer.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **74 (74.0%)** |
| Mean judge score | 0.652 |
| Contains reference (lexical) | 41 (41.0%) |
| Verdicts | correct=67, incorrect=26, partial=7 |
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

### Failed / incorrect queries (26)

| Q# | question | verdict | reason |
|---|---|---|---|
| 1 | who wrote he ain't heavy he's my brother lyrics | incorrect | Candidate incorrectly states the song was written by The Hollies, when it was ac |
| 5 | when did the isle of wight become an island | incorrect | Candidate answer states a different fact than the reference. |
| 11 | who sang i ran all the way home | incorrect | Candidate answer states a different fact, referencing The Who instead of the cor |
| 14 | who does the voice of nala in the lion king | incorrect | Candidate answer states a different fact, mentioning Sally Jewell instead of the |
| 15 | who plays gram on the young and the restless | incorrect | Candidate does not provide the correct character name. |
| 24 | who plays auggie in the movie the wonder | incorrect | Candidate answer refers to a different movie and character description. |
| 26 | who plays matthew on anne with an e | incorrect | Candidate answer does not mention the correct actor's name, R. H. Thomson. |
| 41 | i was a great islamic scholar and mathematician who died in 1131 ce | incorrect | The candidate answer is a statement, not a response to a question. |
| 42 | who is the coach for the ottawa senators | incorrect | Candidate answer is based on outdated information and incorrect assumptions. |
| 43 | last episode of what happens to my family | incorrect | Candidate answer states a different fact, refusing to provide a clear answer. |
| 52 | who played solomon in little house on the prairie | incorrect | Candidate answer does not provide a specific actor's name. |
| 55 | architectural elements forming rib vaults eg wells cathedral | incorrect | Candidate answer is a lengthy explanation rather than a concise list of architec |
| 56 | who sang the song good morning good morning | incorrect | Candidate answer does not match any reference answer. |
| 59 | who wrote it's a long long way to pasadena | incorrect | Candidate states a different fact, The Flying Burrito Brothers are mentioned but |
| 61 | who are nominated for president of india 2017 | incorrect | CANDIDATE states a different fact than REFERENCE(S) |
| 64 | who is the first wife on sister wives | incorrect | Candidate answer does not specify a correct name, only possible interpretations. |
| 73 | who sings the theme song for the tv show cops | incorrect | Candidate provides incorrect information about the theme song's artist. |
| 77 | when did marathon change its name to snickers | incorrect | Candidate answer is unrelated to the actual question about the name change of a  |
| 80 | who sang let me tell you about the birds and the bees | incorrect | Candidate does not provide the correct artist. |
| 82 | how many seasons of the rugrats are there | incorrect | Candidate answer does not match any reference, as it does not provide a number o |
| 87 | who plays the saint of killers on preacher | incorrect | Candidate answer fails to provide the correct actor's name. |
| 88 | when did the royal proclamation of 1763 end | incorrect | Candidate answer states a different fact, 1773 instead of 1783. |
| 93 | when did amnesia the dark descent come out | incorrect | Candidate answer does not match any reference, and provides incomplete informati |
| 94 | what is the oldest street in the philippines | incorrect | Candidate answer does not match any reference answer. |
| 98 | types of skiing in the winter olympics 2018 | incorrect | Candidate answer includes unrelated categories and incorrect categorization of s |
| 99 | who plays noah newman on the young and the restless | incorrect | Candidate answer states a different fact than the reference. |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>User asks: "when was the last time anyone was on the moon". They want date. Last manned moon landing was Apollo 17, 1972. Specifically astronauts returned to Earth on December 7, 1972; they left the moon on December 7. They were on the moon until December 7, 1972. The last time anyone was on the moon is December 7, 1972. There's also mention of Lunar Reconnaissance Orbiter? But that's unmanned. So answer: December 7, 1972. Provide context.</think>The last  
- score: 1.00 (correct) — Candidate answer matches the reference date.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>The user asks: "how many seasons of the bastard executioner are there". We must identify the show "The Bastard Executioner". This seems a series. We need number of seasons. Let's recall: The Bastard Executioner (Spanish: El Bastardo Ejecutor). It's a Spanish TV series produced by RTVE. I think it had 3 seasons? Actually I recall that first season aired 2020. Then second season 2021? And third season 2023? Let’s check memory: The Bastard Executioner (El Bastardo Ejecutor) is a Spanish historical drama set in the  
- score: 0.80 (correct) — Candidate answer is close to the reference answer, but lacks precision on the exact years of the seasons.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: <think>We need to answer the user's question: "when did the eagles win last super bowl". This refers to Philadelphia Eagles. We need to provide the date of their most recent Super Bowl win. The Eagles won Super Bowl LII (52) in 2018? Actually Super Bowl LII was on February 4, 2018, where Eagles defeated Patriots 41-33. So answer: They won Super Bowl LII on February 4, 2018. Provide that answer. No extraneous commentary.</think>The Philadelphia Eagles last won a Super Bowl on February 4  
- score: 0.80 (correct) — Conveys the same factual answer as reference, but with extra context.

#### Incorrect

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics". That's a song by The Hollies. The lyrics were written by the band members? The song was written by the members of The Hollies: Tony Hicks, Graham Nash, and Noel Redding? Wait, "He Ain't Heavy, He's My Brother" was written by the members of The Hollies: Tony Hicks, Graham Nash, and Noel Redding? Let's recall: The Hollies wrote the song themselves: "He Ain't Heavy, He's My Brother" was written by the members of The Hollies: Tony Hicks, Graham Nash,  
- score: 0.00 (incorrect) — Candidate incorrectly states the song was written by The Hollies, when it was actually written by Bobby Scott and Bob Russell.

**Q5: when did the isle of wight become an island**  
- expected: _During the last Ice Age_  
- got: <think>The user asks: "when did the isle of wight become an island". They mention "isle of wight" not "Wake Island". This is a different location: Isle of Wight is in England, a real island. The question: "when did the isle of wight become an island". We need to answer: the Isle of Wight became an island when the sea level rose at the end of the last glacial period, around 6,000-7,000 years ago? Actually the Isle of Wight separated from the mainland during the Anglian glaciation, about 450  
- score: 0.00 (incorrect) — Candidate answer states a different fact than the reference.

**Q11: who sang i ran all the way home**  
- expected: _The Impalas_  
- got: <think>We need to answer: "who sang i ran all the way home". The user asks "who sang i ran all the way home". We need to identify the song "I Ran (So Far Away)" or "I Ran All the Way Home"? Possibly "I Ran All the Way Home" is a track by the band "The B-52's"? Wait, I recall a song called "I Ran All the Way Home" by The Who? Let's search memory. The phrase "I Ran All the Way Home" might be from "The B-52's" or "The Who"? Actually there is a  
- score: 0.00 (incorrect) — Candidate answer states a different fact, referencing The Who instead of the correct answer.


---
_Generated by report_ab.py._