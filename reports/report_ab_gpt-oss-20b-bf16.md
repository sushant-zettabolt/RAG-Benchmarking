# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.00x faster |
| Retrieval + overhead | 0.258 | 0.269 | 0.96x faster |
| Prompt processing (prefill) | 7.016 | 8.135 | 0.86x faster |
| Generation (decode) | 9.003 | 5.118 | 1.76x faster |
| LLM total (prefill+decode) | 16.019 | 13.253 | 1.21x faster |
| Time to first token | 7.285 | 8.414 | 0.87x faster |
| End-to-end (total) | 16.214 | 13.454 | 1.21x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 595.1 | 691.5 | 1.16x |
| Decode (generation) t/s | 35.0 | 34.7 | 0.99x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4152.2 | 5622.4 |
| Completion tokens (mean) | 314 | 177 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.258 | 0.269 |
| Match rate (LLM judge) | 40.0% | 50.0% |

### Speedup summary

- Prefill throughput: **1.16x**  (595.1 → 691.5 t/s)
- Decode throughput:  **0.99x**  (35.0 → 34.7 t/s)
- LLM inference latency: **1.21x faster**
- End-to-end latency: **1.21x faster**  (16.21s → 13.45s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **4 (40.0%)** |
| Mean judge score | 0.571 |
| Contains reference (lexical) | 4 (40.0%) |
| Verdicts | unparsed=3, correct=4, incorrect=3 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 44662 |
| Tokens/query (prompt / completion) | 4152.2 / 314 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 16.214 | 14.966 | 32.860 | 9.305 | 32.860 |
| Time to first token | 7.285 | 7.768 | 9.869 | 5.713 | 9.869 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.258 | 0.258 | 0.272 | 0.246 | 0.272 |
| Prompt processing (prefill) | 7.016 | 7.499 | 9.587 | 5.456 | 9.587 |
| Generation (decode) | 9.003 | 8.820 | 26.154 | 2.753 | 26.154 |
| LLM total (prefill+decode) | 16.019 | 14.784 | 32.654 | 9.122 | 32.654 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4152.2 | 4415 | 5455 | 3352 | 5455 |
| Completion tokens | 314 | 307 | 911 | 96 | 911 |
| Total tokens | 4466.2 | 4821 | 5578 | 3502 | 5578 |

### Failed / incorrect queries (6)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | unparsed |  |
| 3 | when did the eagles win last super bowl | incorrect | parsed from text |
| 4 | who won last year's ncaa women's basketball | unparsed |  |
| 5 | when did the isle of wight become an island | unparsed |  |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer does not match the reference answer. |
| 8 | what is the hot coffee mod in san andreas | incorrect | Candidate describes explicit content, not an inaccessible mini‑game. |

### Example answers

#### Correct

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>We need to answer the question: "who wrote he ain't heavy he's my brother lyrics". The user asks: "who wrote he ain't heavy he's my brother lyrics". We should provide correct answer. The song "He Ain't Heavy, He's My Brother" is a 1969 single by The Hollies. The lyrics were written by Bobby Scott and Bob Russell. Actually the original song was written by Bobby Scott (music) and Bob Russell (lyrics). The Hollies recorded it. So answer: the lyrics were written by Bob Russell, music by Bobby Scott. So answer accordingly. Also no apologies.</think>The lyrics were written by Bob Russell, with the music composed by Bobby Scott.  
- score: 1.00 (correct) — Matches the reference authorship.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>The user asks: "how many seasons of the bastard executioner are there". We must answer. "The Bastard Executioner" likely refers to a TV series? There's a show called "The Bastard Executioner" perhaps a historical drama about a medieval executioner. I need to find the number of seasons. Quick recall: "The Bastard Executioner" is a 2015 TV series? I'm not certain. Let's search memory: There is a series "The Bastard Executioner" (original title "El ejecutor")? Actually there is a Spanish series "El ejecutor" maybe. But "The Bastard Executioner" might be a 2015 series with 1 season. But we need to confirm. There is a British series? I recall a show called "The Bastard Executioner" starring? Wait, there is a 2015 British TV series "The Bastard Executioner" maybe about medieval times. It's a one season, 8 episodes? Let's check: It's a 2015 Spanish series "El ejecutor" is a Spanish TV series, but "The Bastard Executioner" might be the English title. According to sources, it's a 2015 TV series on Channel 4? Actually Channel 4 had a show "The Bastard Executioner" in 2015. It had 1 season, 8 episodes. So answer: 1 season.

Thus answer: There is only one season. Provide number. No apology.</think>There is only one season of *The Bastard Executioner*.  
- score: 1.00 (correct) — Matches the reference answer.

**Q7: who was the ruler of england in 1616**  
- expected: _James I_  
- got: <think>We need to answer the last question: "who was the ruler of England in 1616". The conversation has repeated earlier answer: James I. That is correct. The user asked earlier and we gave James I. So we can answer that. There's no new instruction. Just answer succinctly. No apologies.</think>James I (also known as James VI of Scotland) was the monarch of England in 1616.  
- score: 1.00 (correct) — Matches the reference answer.

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>The user repeats the same question. The instruction says: "Return only your response to the question given the above information following the users instructions as needed." The user didn't provide new instructions. We should answer: last time humans walked on the moon was Apollo 17, landed December 11, 1972, returned December 19, 1972. No apology. Just answer.</think>The last time humans walked on the Moon was during the Apollo 17 mission, which landed on December 11, 1972, and returned to Earth on December 19, 1972.  
- score: n/a (unparsed) — 

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: <think>The user asks: "when did the eagles win last super bowl". They refer to the Philadelphia Eagles NFL team. The Eagles won Super Bowl LII (52) on February 4, 2018, beating the New England Patriots. So answer: February 4, 2018. The user likely expects that. The conversation has many repeated Qs. No apology needed, just answer.</think>The Philadelphia Eagles won their most recent Super Bowl on **February 4, 2018** (Super Bowl LII).  
- score: 0.00 (incorrect) — parsed from text

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: <think>We need to answer: "who won last year's ncaa women's basketball". The last NCAA women's basketball champion. The conversation date: user says "last year's". We need to determine what year. As of current date, presumably 2026? But the assistant's knowledge cutoff is 2024-06. The user likely asks as of now (2026?). But knowledge cutoff 2024. But we should answer based on what we know up to 2024. "Last year's NCAA women's basketball" would be 2023? Or 2022? The conversation earlier the assistant incorrectly gave 2022. But that was a mistake. Now we need to give correct answer. As of 2024, the most recent champion is 2024: South Carolina? Actually the 2024 NCAA women's basketball tournament champion was South Carolina? Wait, let's recall: NCAA women's basketball champions:

- 2022: South Carolina
- 2023: LSU? Wait, 2023 champion was LSU? Actually 2023 NCAA women's champion was LSU? Let's check memory: 2023 women's champion was LSU (they beat UConn). Yes LSU won 2023. 2024 champion: South Carolina again? Wait, 2024 champion was South Carolina? Let's recall: The 2024 NCAA women's basketball champion was South Carolina? Actually 2024 final: South Carolina vs. UConn? I think South Carolina won. Wait, but we need to verify. Let's recall the 2024 NCAA women's champion: It was South Carolina (Caitlin Clark, etc). They beat UConn? Actually South Carolina beat UConn? Wait, but South Carolina played UConn in 2024? Let's check: The 2024 NCAA women's tournament champion was South Carolina, yes. They beat UConn? Actually the final was South Carolina vs. UConn? Let's recall: The 2024 women's final: South Carolina vs. UConn; South Carolina won 71-70. Yes that is correct. So the most recent champion is South Carolina. The question: "who won last year's ncaa women's basketball". If the conversation is current year 2026, last year's champion would be 2025? But we don't know that. But we have knowledge up to 2024. So we should answer with the most recent known champion. The question is ambiguous. But typical interpretation: "last year's" means the most recent completed tournament before current date. If current date is 2026, that would be 2025 champion, which we don't know. But we can answer with 2024 champion: South Carolina. But we could also say "South Carolina won the 2024 NCAA women's basketball championship". That is safe. We should also note that the 2023 champion was LSU. But the question: "who won last year's ncaa women's basketball". If the user is referencing "last year" as 2023, then answer LSU. But the assistant earlier incorrectly gave 2022. We should correct to 2023. But we need to decide. Let's interpret that "last year's" refers to the most recent tournament before the current year. If the current year is 2026, we don't know 2025 champion. But we can say "I don't have that information". But the instruction says: "Return only your response to the question given the above information following the users instructions as needed." There's no instruction about speculation. The user hasn't given a year. The safe approach: Provide the most recent known champion, which is 2024 South Carolina. But if the user expects 2023, we might be wrong. But earlier they incorrectly answered 2022. So we need to correct. I think the user might be referring to 2023 champion. Let's check context: The assistant earlier gave 2022 erroneously. The user likely is looking for 2023 champion. So we should answer: LSU won the 2023 NCAA women's basketball championship. That is the most recent champion before 2024. So answer that. The question: "who won last year's ncaa women's basketball". If it's 2024, last year is 2023. So LSU. So answer: LSU. Let's answer: LSU Tigers.</think>The 2023 NCAA Division I Women’s Basketball Championship was won by the **LSU Tigers**. They defeated UConn in the title game to capture the national title.  
- score: n/a (unparsed) — 


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **5 (50.0%)** |
| Mean judge score | 0.714 |
| Contains reference (lexical) | 3 (30.0%) |
| Verdicts | unparsed=3, correct=5, incorrect=2 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 57994 |
| Tokens/query (prompt / completion) | 5622.4 / 177 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 13.454 | 12.771 | 18.660 | 10.476 | 18.660 |
| Time to first token | 8.414 | 8.507 | 9.074 | 7.941 | 9.074 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.269 | 0.265 | 0.309 | 0.261 | 0.309 |
| Prompt processing (prefill) | 8.135 | 8.230 | 8.790 | 7.670 | 8.790 |
| Generation (decode) | 5.118 | 4.854 | 10.227 | 1.801 | 10.227 |
| LLM total (prefill+decode) | 13.253 | 12.575 | 18.457 | 10.287 | 18.457 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 5622.4 | 5691 | 6031 | 5334 | 6031 |
| Completion tokens | 177 | 168 | 352 | 63 | 352 |
| Total tokens | 5799.4 | 5836 | 6107 | 5442 | 6107 |

### Failed / incorrect queries (5)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | unparsed |  |
| 3 | when did the eagles win last super bowl | incorrect | parsed from text |
| 4 | who won last year's ncaa women's basketball | unparsed |  |
| 6 | love yourself by justin bieber is about who | incorrect | Candidate answer does not mention Rihanna, the reference answer. |
| 8 | what is the hot coffee mod in san andreas | unparsed |  |

### Example answers

#### Correct

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics". We need to answer correctly. The correct answer: The song "He Ain't Heavy, He's My Brother" was written by Bobby Scott (music) and Bob Russell (lyrics). The Hollies recorded it. So answer: Bob Russell wrote the lyrics; music by Bobby Scott. Provide that. No apology.</think>The lyrics were written by **Bob Russell**, while the music was composed by **Bobby Scott**.  
- score: 1.00 (correct) — Matches the reference information.

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>We have a repeated question about "how many seasons of the Bastard Executioner are there". We need to answer correctly. We need to verify the number of seasons. The user earlier asked, and the assistant gave 1 season. We need to confirm. The Bastard Executioner is a 2015 television series. I recall reading that it's a 2015 TV series starring? Actually there's a 2015 British TV series "The Bastard Executioner" produced by Channel 4, starring? I think it's a historical drama about a 14th-century executioner. It had 1 season, 8 episodes. Yes. So answer: 1 season. Provide concise answer. No apology.</think>There is only **one** season of *The Bastard Executioner*.  
- score: 1.00 (correct) — Matches reference answer.

**Q5: when did the isle of wight become an island**  
- expected: _During the last Ice Age_  
- got: <think>We need to answer the last question: "when did the isle of wight become an island". We need to provide a correct answer. The Isle of Wight is a geological island that has been separated from mainland for millions of years. But "when did it become an island" could refer to when sea level rose after the last glacial period, creating the Solent channel. That was about 6,000 to 7,000 years ago. The question might expect a more precise answer: about 4000 BCE? But it's not a specific date. We should explain that the Isle of Wight has been an island for millions of years, but the Solent channel formed around 6-7 thousand years ago. So answer accordingly. The previous assistant gave a similar answer. We can refine.

Let's answer: The Isle of Wight has been separated from mainland England for millions of years geologically, but it became a true island when the Solent channel opened due to rising sea levels at the end of the last Ice Age, around 6–7 thousand years ago (roughly 4–5 k BCE). No single date, but that period. Provide that.</think>The Isle of Wight has been a distinct landmass for millions of years, but it became a true island when the Solent channel opened. That happened as sea levels rose at the end of the last Ice Age, roughly 6 – 7 thousand years ago (about 4 – 5 k BCE). The exact moment can’t be pinpointed to a single date, but the post‑glacial sea‑level rise created the separation from the mainland.  
- score: 1.00 (correct) — Candidate answer correctly states the Isle of Wight became an island during the last Ice Age, matching the reference.

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>We have a repeated question. The user keeps asking "when was the last time anyone was on the moon". We have to answer. We should just answer: Apollo 17, December 11, 1972, return December 19, 1972. No apology, no repetition. So final answer.</think>The last time humans walked on the Moon was during the Apollo 17 mission, which landed on **December 11, 1972** and returned to Earth on **December 19, 1972**.  
- score: n/a (unparsed) — 

**Q3: when did the eagles win last super bowl**  
- expected: _2017_  
- got: <think>The user asks: "when did the eagles win last super bowl". They refer to Philadelphia Eagles. The last Super Bowl win was Super Bowl LII (52) on February 4, 2018. So answer that. The previous assistant gave that. No new instructions. So answer: February 4, 2018.</think>The Philadelphia Eagles won their most recent Super Bowl on **February 4, 2018** (Super Bowl LII).  
- score: 0.00 (incorrect) — parsed from text

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: <think>We need to answer: "who won last year's ncaa women's basketball". The user wants the champion of the most recent NCAA women's basketball tournament.

We need to consider what year the user is referring to. The user hasn't specified a year. "Last year" is relative to current date. The conversation currently is at time? The assistant has no knowledge of the current date beyond cutoff. But we can infer likely the user is asking about the most recent champion before the current year, which is 2024? But the assistant's cutoff is 2024-06, but the user might be in 2025 or 2026. But we don't know. The user likely wants the 2023 champion if current year is 2024. However, we need to decide. The conversation earlier: The assistant answered incorrectly with 2022. The user repeated "who won last year's ncaa women's basketball". The assistant should correct: it's LSU. So answer: LSU won the 2023 NCAA women's basketball championship. Provide that. That seems the best answer.

We should provide the champion and the year: LSU Tigers. We can mention that they beat UConn in the final.

We need to not apologize. Provide answer.

Thus final answer: LSU.</think>The 2023 NCAA Division I Women’s Basketball Championship was won by the **LSU Tigers**. They defeated UConn in the title game to capture the national title.  
- score: n/a (unparsed) — 


---
_Generated by report_ab.py._