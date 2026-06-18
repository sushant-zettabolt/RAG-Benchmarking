# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench-97555499`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.053 | 0.053 | 1.001x |
| Retrieval + overhead | 0.154 | 0.153 | 1.01x |
| Prompt processing (prefill) | 4.934 | 4.351 | 1.13x |
| Generation (decode) | 3.458 | 3.487 | 1.01x |
| LLM total (prefill+decode) | 8.393 | 7.838 | 1.07x |
| Time to first token | 5.142 | 4.557 | 1.13x |
| End-to-end (total) | 8.526 | 7.971 | 1.07x |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 732.4 | 831.6 | 1.14x |
| Decode (generation) t/s | 37.0 | 36.7 | 0.99x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 3598.3 | 3598.3 |
| Completion tokens (mean) | 128 | 128 |
| Query embedding (s) | 0.053 | 0.053 |
| Retrieval + overhead (s) | 0.154 | 0.153 |
| Match rate (LLM judge) | 20.0% | 25.0% |
| Contains reference (lexical) | 10.0% | 9.0% |

### Speedup summary

- Prefill throughput: **1.14x**  (732.4 → 831.6 t/s)
- Decode throughput:  **0.99x**  (37.0 → 36.7 t/s)
- LLM inference latency: **1.07x**
- End-to-end latency: **1.07x**  (8.53s → 7.97s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **20 (20.0%)** |
| Mean judge score | 0.181 |
| Contains reference (lexical) | 10 (10.0%) |
| Verdicts | incorrect=80, correct=17, partial=3 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 372634 |
| Tokens/query (prompt / completion) | 3598.3 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 8.526 | 8.323 | 9.721 | 7.264 | 9.970 |
| Time to first token | 5.142 | 4.947 | 6.333 | 3.890 | 6.573 |
| Query embedding | 0.053 | 0.053 | 0.056 | 0.048 | 0.057 |
| Retrieval + overhead | 0.154 | 0.153 | 0.160 | 0.141 | 0.182 |
| Prompt processing (prefill) | 4.934 | 4.738 | 6.129 | 3.693 | 6.364 |
| Generation (decode) | 3.458 | 3.455 | 3.494 | 3.409 | 3.509 |
| LLM total (prefill+decode) | 8.393 | 8.187 | 9.588 | 7.139 | 9.831 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3598.3 | 3589 | 4180 | 2924 | 4297 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3726.3 | 3717 | 4308 | 3052 | 4425 |

### Failed / incorrect queries (80)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | incorrect | Candidate does not provide a date or any information related to the last time so |
| 1 | who wrote he ain't heavy he's my brother lyrics | incorrect | Candidate answer does not mention the song title or its writers. |
| 3 | when did the eagles win last super bowl | incorrect | Candidate answer does not match any reference answer. |
| 4 | who won last year's ncaa women's basketball | incorrect | No information about last year's NCAA women's basketball championship. |
| 5 | when did the isle of wight become an island | incorrect | Candidate answer does not address the question of when the Isle of Wight became  |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer does not address the question about the theme of Justin Bieber' |
| 8 | what is the hot coffee mod in san andreas | incorrect | Candidate answer is unrelated to the question about a mod in San Andreas. |
| 9 | what is the maximum data rate for the 802.11a standard select one | incorrect | Candidate answer does not attempt to answer the question. |
| 10 | which state is located in the centre of india | incorrect | Candidate answer does not mention any state in the centre of India, and context  |
| 11 | who sang i ran all the way home | incorrect | Candidate answer does not match any reference answer. |
| 12 | where did the last name wallace come from | incorrect | Candidate answer does not address the origin of the surname Wallace. |
| 13 | who was the actor that played ben stone on law and order | incorrect | CANDIDATE does not mention the correct actor, Michael Moriarty. |
| 14 | who does the voice of nala in the lion king | incorrect | Candidate answer is unrelated to the question. |
| 15 | who plays gram on the young and the restless | incorrect | Candidate answer does not mention the character Gram or the actor's name. |
| 16 | what is the oath that new citizens take | incorrect | Candidate answer does not mention the oath, let alone its content. |
| 17 | who is under the mask of darth vader | incorrect | Candidate does not mention Darth Vader or Anakin Skywalker. |
| 18 | who had a baby at 100 in the bible | incorrect | No mention of a baby at age 100 in the provided texts. |
| 19 | what age do you need to be to buy a bb gun | incorrect | Candidate answer does not address the question about BB gun purchase age. |
| 20 | ethiopia flight 961 crashes in to the sea | incorrect | Candidate answer does not provide a date, whereas the reference answer is a spec |
| 21 | where was percy jackson and the olympians filmed | incorrect | Candidate answer does not mention the location of the filming of Percy Jackson a |
| 23 | how many episodes are there in dragon ball z | incorrect | Candidate does not mention the number of episodes in Dragon Ball Z. |
| 25 | when was the first australian prime minister elected | incorrect | Candidate answer is unrelated to the question about Australian Prime Minister. |
| 26 | who plays matthew on anne with an e | incorrect | Candidate answer does not mention the character's name, 'Matthew'. |
| 27 | who is the girl in green day 21 guns | incorrect | No mention of Green Day or 21 Guns in the provided contexts. |
| 28 | who plays joker in batman the dark knight | incorrect | Candidate answer does not mention the Joker. |
| 30 | when was the first hunger games book published | incorrect | No mention of Hunger Games in any context. |
| 31 | who did bette midler portray in the rose | incorrect | No mention of Bette Midler or the Rose in the provided context. |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | Candidate answer does not mention a location related to the butchers in the slau |
| 34 | who developed the concept of total quality management | incorrect | Candidate answer does not mention the actual developer of TQM. |
| 35 | who wrote cant get you out of my head lyrics | incorrect | Candidate answer does not mention the song 'Can't Get You Out of My Head'. |

_…and 50 more (see the JSON report)._

### Example answers

#### Correct

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>1.  **Analyze the Request:** The user is asking "how many seasons of the bastard executioner are there".

2.  **Scan the Contexts:** I need to search the provided texts (Context 0 through Context 7) for any mention of "The Bastard Executioner" or any show/series that matches that title.

    *   Context 0 (Prison Break): Mentions Prison Break seasons and episodes.
    *   Context 1 (Prison Break): Mentions Prison Break seasons.
    *   Context 2 (The Vampire Diaries): Mentions seasons four and five  
- score: 1.00 (correct) — Candidate answer matches the number of seasons in the reference.

**Q7: who was the ruler of england in 1616**  
- expected: _James I_  
- got: <think>1.  **Analyze the Request:** The user is asking for the ruler of England in 1616.

2.  **Scan Context for Keywords:** I need to look for terms related to "England," "ruler," "1616," or specific historical figures associated with England during that period.

3.  **Review Contexts:**
    *   Context 0 (Two-party system): Discusses British political history (Glorious Revolution to 1715).
    *   Context 1 (Habsburg Monarchy): Discusses Habsburg territories.  
- score: 1.00 (correct) — Candidate answer matches the reference answer.

**Q22: how many seasons of vampire diaries r there**  
- expected: _eight | 8_  
- got: <think>1.  **Analyze the Request:** The user is asking "how many seasons of vampire diaries r there".

2.  **Scan the Context for Season Information:** I need to look through all the provided contexts (0 through 7) for any mention of the total number of seasons in *The Vampire Diaries*.

3.  **Review Contexts:**
    *   Context 0: Mentions events, characters, and timelines, but not the total season count.
    *   Context 1: Mentions Season 7 and Season 8.
    *   Context 2: Mentions  
- score: 0.80 (partial) — Candidate answer is close but does not exactly match any reference.

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>Thinking Process:

1.  **Analyze the Request:** The user is asking, "when was the last time anyone was on the moon".
2.  **Scan Context for Keywords:** I need to search the provided context (Context 0 through Context 7) for terms like "moon," "astronaut," "space," "mission," or specific dates related to lunar activities.
3.  **Review Contexts:**
    *   Context 0 (Chinese New Year): Deals with Chinese calendar, zodiac, and customs. (Irrelevant)
    *   Context 1 (Wake Island): Deals  
- score: 0.00 (incorrect) — Candidate does not provide a date or any information related to the last time someone was on the moon.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>1.  **Analyze the Request:** The user is asking who wrote the lyrics to the song "he ain't heavy he's my brother".

2.  **Scan the Context:** I need to search all provided context documents (Context 0 through Context 7) for the specific song title or lyrics.

    *   Context 0: Mentions "Don't Let Me Down (The Chainsmokers song)", Walter Frederick Morrison.
    *   Context 1: Mentions "Can't Help Falling in Love" (Elvis Presley, Hugo Peretti, Luigi Creatore, George  
- score: 0.00 (incorrect) — Candidate answer does not mention the song title or its writers.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: <think>1.  **Analyze the Request:** The user is asking "when did the eagles win last super bowl".

2.  **Scan the Context for "Eagles" and "Super Bowl":** I need to look through the provided context documents for mentions of the Philadelphia Eagles winning a Super Bowl.

    *   *Context 1:* Mentions Patriots winning Super Bowl XLIX (2015) against the Seattle Seahawks. Mentions Patriots losing to the Philadelphia Eagles in Super Bowl LII (2018).
    *   *Context 2:* No mention of Eagles winning a Super Bowl  
- score: 0.00 (incorrect) — Candidate answer does not match any reference answer.


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 100 |
| Succeeded | 100 |
| Errored | 0 |
| **Matched (LLM judge)** | **25 (25.0%)** |
| Mean judge score | 0.227 |
| Contains reference (lexical) | 9 (9.0%) |
| Verdicts | incorrect=75, correct=21, partial=4 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 372634 |
| Tokens/query (prompt / completion) | 3598.3 / 128 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 7.971 | 7.788 | 9.062 | 6.792 | 9.324 |
| Time to first token | 4.557 | 4.362 | 5.661 | 3.402 | 5.907 |
| Query embedding | 0.053 | 0.053 | 0.055 | 0.046 | 0.057 |
| Retrieval + overhead | 0.153 | 0.153 | 0.158 | 0.140 | 0.165 |
| Prompt processing (prefill) | 4.351 | 4.151 | 5.455 | 3.202 | 5.699 |
| Generation (decode) | 3.487 | 3.490 | 3.521 | 3.434 | 3.530 |
| LLM total (prefill+decode) | 7.838 | 7.660 | 8.926 | 6.664 | 9.187 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 3598.3 | 3589 | 4180 | 2924 | 4297 |
| Completion tokens | 128 | 128 | 128 | 128 | 128 |
| Total tokens | 3726.3 | 3717 | 4308 | 3052 | 4425 |

### Failed / incorrect queries (75)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | incorrect | Candidate answer is not provided, cannot assess its correctness. |
| 1 | who wrote he ain't heavy he's my brother lyrics | incorrect | Candidate answer does not mention the song title or its writers. |
| 3 | when did the eagles win last super bowl | incorrect | Candidate answer does not mention the Eagles winning a Super Bowl. |
| 5 | when did the isle of wight become an island | incorrect | Candidate answer does not address the question about when the Isle of Wight beca |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer does not address the question about the song 'Love Yourself' by |
| 8 | what is the hot coffee mod in san andreas | incorrect | Candidate answer is unrelated to the question about a mod in San Andreas. |
| 9 | what is the maximum data rate for the 802.11a standard select one | incorrect | Candidate answer does not directly state the maximum data rate for 802.11a. |
| 10 | which state is located in the centre of india | incorrect | Candidate answer is unrelated to the question about the central state of India. |
| 11 | who sang i ran all the way home | incorrect | Candidate answer does not match any reference |
| 12 | where did the last name wallace come from | incorrect | Candidate answer does not address the origin of the surname Wallace. |
| 13 | who was the actor that played ben stone on law and order | incorrect | No mention of Law & Order or Ben Stone in the provided contexts. |
| 14 | who does the voice of nala in the lion king | incorrect | Candidate answer does not mention The Lion King or Nala. |
| 16 | what is the oath that new citizens take | incorrect | Candidate answer does not mention the oath, let alone its content. |
| 18 | who had a baby at 100 in the bible | incorrect | No mention of a baby at 100 in the provided context. |
| 20 | ethiopia flight 961 crashes in to the sea | incorrect | Candidate answer does not provide a date, whereas the reference answer does. |
| 21 | where was percy jackson and the olympians filmed | incorrect | Candidate answer does not mention any filming locations of Percy Jackson and the |
| 22 | how many seasons of vampire diaries r there | incorrect | Candidate answer does not match any reference answer. |
| 23 | how many episodes are there in dragon ball z | incorrect | Candidate does not mention Dragon Ball Z or its episode count. |
| 24 | who plays auggie in the movie the wonder | incorrect | No mention of The Wonder or Auggie in the provided context. |
| 25 | when was the first australian prime minister elected | incorrect | Candidate answer does not mention Australia or the election of a Prime Minister. |
| 26 | who plays matthew on anne with an e | incorrect | Candidate answer does not mention the character or show. |
| 28 | who plays joker in batman the dark knight | incorrect | Candidate answer does not mention the Joker or the movie's title. |
| 29 | when was the south asian association for regional co-operation (saarc)… | incorrect | Candidate answer is missing, cannot assess its correctness. |
| 31 | who did bette midler portray in the rose | incorrect | Candidate answer does not mention the character portrayed by Betty Midler in 'Th |
| 32 | who is the lead singer of depeche mode | incorrect | Candidate answer does not mention Depeche Mode or its lead singer. |
| 33 | where did the butchers in the slaughterhouse cases live | incorrect | No mention of butchers or slaughterhouses in the provided contexts. |
| 36 | where does no game no life anime end | incorrect | Candidate answer is unrelated to the question. |
| 38 | what are the three fifty shades of grey books | incorrect | No mention of Fifty Shades of Grey or related titles in the provided contexts. |
| 40 | what are the ranks in the us navy | incorrect | Candidate answer does not mention any ranks in the US Navy. |
| 41 | i was a great islamic scholar and mathematician who died in 1131 ce | incorrect | No matching information found in the context. |

_…and 45 more (see the JSON report)._

### Example answers

#### Correct

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>1.  **Analyze the Request:** The user is asking "how many seasons of the bastard executioner are there".

2.  **Scan the Contexts:** I need to search the provided text (Context 0 through Context 7) for any mention of "The Bastard Executioner" or related content.

    *   Context 0: Mentions *Prison Break* episodes and seasons.
    *   Context 1: Mentions *Prison Break* series details.
    *   Context 2: Mentions *The Vampire Diaries* characters and seasons.
    *   Context  
- score: 1.00 (correct) — Candidate answer matches the number of seasons in the reference.

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: <think>1.  **Analyze the Request:** The user is asking "who won last year's ncaa women's basketball".

2.  **Scan Context for Keywords:** I need to look for terms like "NCAA," "women's basketball," "championship," "winner," and dates/years.

3.  **Review Contexts:**
    *   Context 0 (Double (basketball)): Mentions Ann Meyers (first American female player to record a quadruple-double in 1978) and Veronica Pettry (first Division I women's player to record a quadruple-  
- score: 1.00 (correct) — Candidate answer matches the reference answer.

**Q7: who was the ruler of england in 1616**  
- expected: _James I_  
- got: <think>1.  **Analyze the Request:** The user is asking for the ruler of England in 1616.

2.  **Scan Contexts for Keywords:** I need to look for terms like "England," "ruler," "monarchy," and dates around 1616.

    *   **Context 0 (Two-party system):** Discusses the Glorious Revolution, Stuart dynasty, George I, and Robert Walpole. (Mentions the period up to 1715).
    *   **Context 1 (Habsburg Monarchy):** Discusses  
- score: 1.00 (correct) — Candidate answer matches the reference answer in terms of factual content.

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>1.  **Analyze the Request:** The user is asking "when was the last time anyone was on the moon".

2.  **Scan the Contexts:** I need to search the provided text (Context 0 through Context 7) for any information regarding moon landings, space travel, or astronaut history.

    *   Context 0 (Chinese New Year): Discusses the Chinese calendar, zodiac, and astrology. (Irrelevant)
    *   Context 1 (Wake Island): Discusses U.S. military use of Wake Island for Chinese immigrants. (Irrelevant)
    *  
- score: 0.00 (incorrect) — Candidate answer is not provided, cannot assess its correctness.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>1.  **Analyze the Request:** The user is asking who wrote the lyrics to the song "He Ain't Heavy, He's My Brother".

2.  **Scan the Contexts:** I need to search all provided contexts (0 through 7) for mentions of "He Ain't Heavy, He's My Brother" or any related song/lyric information.

    *   Context 0 (Don't Let Me Down, Walter Frederick Morrison): Irrelevant.
    *   Context 1 (Can't Help Falling in Love): Irrelevant.
    *  
- score: 0.00 (incorrect) — Candidate answer does not mention the song title or its writers.

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: <think>1.  **Analyze the Request:** The user is asking "when did the eagles win last super bowl".

2.  **Scan the Context for "Eagles" and "Super Bowl":** I need to look through the provided context documents for mentions of the Philadelphia Eagles winning a Super Bowl.

3.  **Review Context 1:**
    *   "...In 2015, they won Super Bowl XLIX, defeating the Seattle Seahawks by a score of 28–24." (No Eagles)
    *   "...faced the Atlanta Falcons in Super Bowl LI, which ended  
- score: 0.00 (incorrect) — Candidate answer does not mention the Eagles winning a Super Bowl.


---
_Generated by report_ab.py._