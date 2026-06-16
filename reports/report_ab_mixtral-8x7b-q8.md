# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions

_Dataset: **nq_open** (questions) + **BeIR/nq** (documents) · workspace `nq-bench`_

_Comparison: **baseline** vs **zendnn** — same pipeline, model and queries; only the llama.cpp chat backend differs. Jobs run sequentially._

## ZenDNN A/B comparison (baseline vs zendnn)

### Per-stage mean latency

| Stage | baseline (s) | zendnn (s) | speedup |
|---|---|---|---|
| Query embedding | 0.011 | 0.011 | 1.00x faster |
| Retrieval + overhead | 0.104 | 0.316 | 0.33x faster |
| Prompt processing (prefill) | 35.345 | 36.184 | 0.98x faster |
| Generation (decode) | 3.798 | 54.139 | 0.07x faster |
| LLM total (prefill+decode) | 39.143 | 90.322 | 0.43x faster |
| Time to first token | 35.459 | 36.510 | 0.97x faster |
| End-to-end (total) | 39.253 | 90.646 | 0.43x faster |

### Inference throughput (tokens/sec, mean)

| Metric | baseline | zendnn | speedup |
|---|---|---|---|
| Prefill (prompt) t/s | 133.2 | 267.2 | 2.01x |
| Decode (generation) t/s | 20.4 | 18.9 | 0.93x |

### Sanity — should be ~equal across jobs (else contamination/contention)

| Metric | baseline | zendnn |
|---|---|---|
| Prompt tokens (mean) | 4701 | 9399 |
| Completion tokens (mean) | 77.3 | 1021.1 |
| Query embedding (s) | 0.011 | 0.011 |
| Retrieval + overhead (s) | 0.104 | 0.316 |
| Match rate (LLM judge) | 90.0% | 0% |

### Speedup summary

- Prefill throughput: **2.01x**  (133.2 → 267.2 t/s)
- Decode throughput:  **0.93x**  (20.4 → 18.9 t/s)
- LLM inference latency: **0.43x faster**
- End-to-end latency: **0.43x faster**  (39.25s → 90.65s)

_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._

## Evaluation detail — baseline

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 10 |
| Errored | 0 |
| **Matched (LLM judge)** | **9 (90.0%)** |
| Mean judge score | 0.880 |
| Contains reference (lexical) | 3 (30.0%) |
| Verdicts | correct=8, incorrect=1, partial=1 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 47783 |
| Tokens/query (prompt / completion) | 4701 / 77.3 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 39.253 | 38.080 | 49.849 | 34.438 | 49.849 |
| Time to first token | 35.459 | 34.165 | 43.087 | 30.423 | 43.087 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.104 | 0.081 | 0.319 | 0.076 | 0.319 |
| Prompt processing (prefill) | 35.345 | 34.074 | 42.757 | 30.336 | 42.757 |
| Generation (decode) | 3.798 | 3.784 | 6.767 | 2.538 | 6.767 |
| LLM total (prefill+decode) | 39.143 | 37.994 | 49.524 | 34.353 | 49.524 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 4701 | 4592 | 5618 | 4130 | 5618 |
| Completion tokens | 77.3 | 78 | 135 | 52 | 135 |
| Total tokens | 4778.3 | 4672 | 5753 | 4225 | 5753 |

### Failed / incorrect queries (1)

| Q# | question | verdict | reason |
|---|---|---|---|
| 4 | who won last year's ncaa women's basketball | incorrect | Candidate answer gives an incorrect team name for the winner of last year's NCAA |

### Example answers

#### Correct

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: <think>The user repeats the question: "when was the last time anyone was on the moon". We need to answer: Apollo 17, December 11, 1972 (landing), returned December 19, 1972. Provide that. No apology.</think>The last time humans walked on the Moon was during the Apollo 17 mission, which landed on **December 11, 1972** and returned to Earth on **December 19, 1972**.  
- score: 1.00 (correct) — Candidate provides the same factual answer as the reference.

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: <think>The user asks: "who wrote he ain't heavy he's my brother lyrics". We need to answer: Bob Russell. Provide that.</think>The lyrics were written by **Bob Russell**.  
- score: 1.00 (correct) — Candidate answer correctly identifies Bob Russell as one of the writers of 'He Ain't Heavy, He's My Brother' lyrics

**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: <think>The user asks: "how many seasons of the bastard executioner are there". We need to answer: 1. Provide that.</think>There is only **one** season of *The Bastard Executioner*.  
- score: 1.00 (correct) — Candidate conveys the same factual answer as the reference.

#### Incorrect

**Q4: who won last year's ncaa women's basketball**  
- expected: _South Carolina_  
- got: <think>The user asks: "who won last year's ncaa women's basketball". We need to answer: LSU. Provide that.</think>The 2023 NCAA Division I Women’s Basketball Championship was won by the **LSU Tigers**.  
- score: 0.00 (incorrect) — Candidate answer gives an incorrect team name for the winner of last year's NCAA women's basketball


## Evaluation detail — zendnn

### Aggregate

| Metric | Value |
|---|---|
| Queries | 10 |
| Succeeded | 7 |
| Errored | 3 |
| **Matched (LLM judge)** | **0 (0%)** |
| Mean judge score | n/a |
| Contains reference (lexical) | 1 (10.0%) |
| Verdicts | unparsed=7, skipped=3 |
| Documents ingested | 100/100 |
| Answerable questions (corpus) | 55 |
| Total tokens (sum) | 72941 |
| Tokens/query (prompt / completion) | 9399 / 1021.1 |

### Latency by stage (successful queries)

| Stage | mean (s) | p50 (s) | p95 (s) | min | max |
|---|---|---|---|---|---|
| End-to-end (total) | 90.646 | 87.338 | 110.581 | 73.756 | 110.581 |
| Time to first token | 36.510 | 33.407 | 54.992 | 21.568 | 54.992 |
| Query embedding | 0.011 | 0.011 | 0.011 | 0.010 | 0.011 |
| Retrieval + overhead | 0.316 | 0.188 | 0.644 | 0.150 | 0.644 |
| Prompt processing (prefill) | 36.184 | 33.237 | 54.794 | 21.195 | 54.794 |
| Generation (decode) | 54.139 | 53.933 | 56.076 | 52.184 | 56.076 |
| LLM total (prefill+decode) | 90.322 | 87.170 | 110.393 | 73.379 | 110.393 |

### Token usage (successful queries)

| | mean | p50 | p95 | min | max |
|---|---|---|---|---|---|
| Prompt tokens | 9399 | 8930 | 12749 | 6528 | 12749 |
| Completion tokens | 1021.1 | 1024 | 1024 | 1004 | 1024 |
| Total tokens | 10420.1 | 9954 | 13753 | 7552 | 13753 |

### Failed / incorrect queries (10)

| Q# | question | verdict | reason |
|---|---|---|---|
| 0 | when was the last time anyone was on the moon | unparsed | 

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

``` |
| 1 | who wrote he ain't heavy he's my brother lyrics | unparsed | 

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

 |
| 2 | how many seasons of the bastard executioner are there | unparsed |  Cross-posted from *The Guardian*.

> The US has been accused of “hypocrisy” aft |
| 3 | when did the eagles win last super bowl | unparsed |  chr(10) + "    " + "    " + "    " + "    " + "    " + "    " + "    " + "    " |
| 4 | who won last year's ncaa women's basketball | skipped | litellm.MidStreamFallbackError: litellm.APIConnectionError: APIConnectionError:  |
| 5 | when did the isle of wight become an island | unparsed | 

###### Small Business

Small business owners have a lot on their plate, and ma |
| 6 | love yourself by justin bieber is about who | skipped | litellm.MidStreamFallbackError: litellm.APIConnectionError: APIConnectionError:  |
| 7 | who was the ruler of england in 1616 | unparsed |  /******/printStackTrace/    in functionniej acknowlodgment
* { Unidos nos torna |
| 8 | what is the hot coffee mod in san andreas | unparsed | 

\begin{table}
\begin{tabular}{\|l\|l\|l\|l\|l\|}
\hline
\textbf{Nombre} & \textbf{Pa |
| 9 | what is the maximum data rate for the 802.11a standard select one | skipped | litellm.MidStreamFallbackError: litellm.APIConnectionError: APIConnectionError:  |

### Example answers

#### Correct

_No correct examples._

#### Incorrect

**Q0: when was the last time anyone was on the moon**  
- expected: _14 December 1972 UTC | December 1972_  
- got: with numbers,? […] behav.ha […] […]haARGETdma […] ?. […] […]-. […]- […]. shit- […] […] slo- gross neuro […] weap- […] […] i. Why […] […] […] /******/ […] […]hang Soundha ??ARGET?? […]..… […] […] Why and/ […] […] […] /******/ […] […] /******/ i.? […] weapons weapil thousia. […] […] […] /******/…ARGET??.ha- etc? […]. Why. meant […]. Starous […] weap- vsnetct […] /******/. […] or. […]. i. gross- […]ARGET, which could […] as. […]. Why […] […] /******/ weap- “ […] weap- “ […] […] weap- which […].ha […] vs-sect to […] i. meant […] […]zhonsonsish- theories […] Adultish etc. gross […] /******/ “ roots, etc. gross /******/ […]. Problem-Kang […]. gross-? […] classified- […] weap. gross […]ARGET […] “ […]’nia […] weap-week weeks […] puzzons […] brain ring cluster of “ suddil […] Ursen. Groß […] […]. C. […]. gross […] weap […]-ha etc […] weap- […] weapons […] […] /******/… […]- gross […]ha. I. […] […] […] weapak which […] […].. […]. like […]. […]? […] fucked- […]. gross blocks/ illness? i. […]  […] […] /******/ […] […] /******// […] […] […]        . gross […] weap etc. gross shitty […] ~. i. etcoughnia, which […]. This […] […] weap- “ […]ARGET/ “ho: […] […]HERE are […]? “sect to […]ha. gross fucked- […] weap- […] […]. i. i. […]-ha. meant- grossons […] /******/.ha. i. i. topics etc […]taient’s possibly […] weap- atm […]ARGET behav-ARGET […]ware- puzz. I. […] […]. “ puzz […] logged- […]. […] i. brain […] […]. why […]/… […]- etc. dangerha- meant […]. ?- Theory chamberke. ? […] Why’ […]. Scientonic […]. i. panels of blocks of yet- […] […] /******/ and vs- […] […]-… sessions like- vs. […] weapons of […] […] […] […] i. Herr PO Why […] […] […] […] are i. How- certain […]? which etc. “dozes of etc […] SND […]. […] […]. “ puzzono/ “lin weekly-ARGET […] Adultil […]. maps- […] […]- and […].  […]- i. i. […] […] /******/ […] […] Ukrous and- i. […]. dangerha […] weap- […]. i. +. gross-like […]ARGETish […]. i. “ha. […]~s. i. buzzed- grosswhe […] weapons,?ha weap- tent cluster i. meant […] […] […] are […]heim,?ha weap […]. […]lich weaphent etc […] […]. […] and i. i. proceedes- problemkeepha […] […]aneous […]heimishy. meant- vsellARGET? etc- […] Sara i.? “ […] […]nia ~ […]. gross […] […]plaatstheim’y.nia. gross […]. I. etc. […]- i. i. puzzons/ha […]ARGET. i. Scient consolidonic “Hello […]. i. Det […]ARGET […] of yet vs. i. […] SND. gross- gross- crime and etc […]?  […]. gross- vs-Triggerons. crime-ha […] thousons of etc Shan’ […] […]han. “NIARGET origins, NY-? […] AU-ecoin Why weap […]/sland- […]. […] […]- i. gross fucking brainha SND. i.? […] […] Why, including/ triggered mostly […]. […] […]ARGETons […]. brain PO yet […] […] […] /******/. i. topics: […]ha. i.🤔. versus- health/ vs. emptago. […]onic […] […] […] […] […] […] […]- i. “? […].?? […].nic […]ha. mechanisms of […].haansons […] […] weapons. i. i. classes i. […] […] ¿ […] […] which are lost “Markogen SND […] to i. etc- i. H. […] /******/ — […] possibly? i. […] usually […] of “? FLUG POlandes […] […] /******/ […] […] […]    […]onic }hrans. […] […]/ vs. “ology/rootelli. grosshandans which… […] […]. gross […].nia. i. gross- tent- […]. “ […] i. I […]/ “/ contents/ “… and why. Why. I could- […] […]onic W. “landARGET etc. i. IMENT Death and- […] […] […] […]il […] […]-landes- based […]. i. […] […] are […] i. “dec. […] […] Why00. […] Ladyani to  
- score: n/a (unparsed) — 

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

```

**Q1: who wrote he ain't heavy he's my brother lyrics**  
- expected: _Bobby Scott | Bob Russell_  
- got: vs brainons weap /******/ […] i. […] primarily weap […] […] weap […] […]- /******/ […], Irish fucking- why […] thousons […] […]? […]. […] i.?.ha […] weap /******/ […]ARGET to etc […] weap […] […]ARGET weap POARGETonic “ […]/ […]- […] […]. […] weap- […] […]      SND SND. “GA […] […]/ Scientonic “ […] weap […] weap weap as i. […] […]. Why […]. […]. Either […] weap […] SND, i.ARGET […]. meant […]… […] […]. meant […]. certain […]. either- […]. […] […]ARGETonic […]. Lady. […]ARGET […]. i. […] weap […] Ukransonsessonic “ wherein […]? i.night- […]. Why i.. etc.. opinions […]shirelandhan’ […] /******/ etc […]ARGETons […] […] […]- vs […] weaphetish […] […] […]plaatst […] etc […] […] Why, i. […], […]. etc. […]? […]- Problem […] […] /******// […] weap […] weap […]. gross- problem/ […]. i. atmARGET —ARGET, […] SND. Scient /******/ […] […] /******/ which “n. certain […] suddhan Adult Adultnutogen […] […] […] called- […] […]- […]      […]- […] […] possibly? […] […] […] […]ARGET […]ARGETs SND. […] […] behav […] […] /******/ |- […] […] ?ono- […] […] […]?? […]   ARGET […] weapons […] etc […]ARGET SND […]ere […] […] behav. Why-? […]…ly… behav […]zer […] weap […] /******/ […]ARGET weap[/ […] […]. meant- […] i. […]. gross- […]. the week- […] […]?.?? behav […] […] /******/ which are possibly — […]plaatst […] […] […]- […]. either […] The […]ARGET to- […] […]ARGET roots,? […] /******/ /******/ i. possibly […]    […]plaatst […] […] weap- panels both […] […]? i. gross […] […] […]ARGET behavonic/ […]. ENC. Master shit, […] […] […]plaatst SND- certain- i.loyd-root […] /******/. […]ARGET […] /******/ […] […]?? […] weap- “2 […] […]plaatst ? […] […] […] weap- plus […]ARGET […]plaatst […] and seemingly […] […] […] […] whichunächst […]-  […] […] […] […]- […]. i.te […]ARGET, i. […]/ […] […] i.ha Why-? […] /******/. danger- […]. etc […]. “ARGET […] […] […]heim […]plaatstane febrs? […]ARGET […] […] weap […]      Sound SMAons and “ brain? i. […]- i. basically […]. i. […]- i. […]? i.ha weap- […] […] possibly […] ? […]ARGETons weap […] weap […]plaatst/ symptoms/Trigger […]. gross fucking […]0 blind Death and etc. i. i. […]ARGETons dun […]- […].« […] […]plaatstonic […] […] […]ARGET […].ha. […] […] […]s […]- i.ni.te […] “ […] certain […]? […] […] such- […]. “ARGEToga. certain […] […] […] […] […]plaatst… puzzhanthplaatst and etc-ha. gross […] […]. Problem and etcough […]?? vsnia- i. i. possibly […]. grossons, in which could […] […]. i. ?? […] ? […] […] classified […] i.ha. i. i. […] vs’ […]ARGET buzz […]. in question […] and. neuroono? i. […] […]plaatst i. etc- problemha […] of blocks? “sect […] […] […]2 […] […] as […] […] citizonsland- […]plaatst […]ARGET SNDARGET,/ […] […] of etc. i. gross POGA. […] weap which […]. gross- […]ARGET vs. […] /******/ of mostly i.teARGET […]zh.ha? […] […] ?? […]. i. i. i. i. Problem […] etc […] of either i. namely-haons […]plaatst.s. meant […]. gross […] of unknown […]. etc […] […] […]… […]ARGET manifestons PO […] i. “home […] i. i.? […] […] SND […] […] Emerangish mostly, “ crap- […]- […]. I reject […] […]-- of […]. i.?? vs. vs. […] […] […]. danger […] are […]      land […] […] […] … […]/H Why […] which […]? “ARGETons […]. i. 3 […] ? […] or […]. gross […] i. Lady Palace i. “ brain- […].haana […] […]plaatst […] ? […] […] which are/ […] […] and? […] weap- i.ha […]ARGET b. […] […] […] […] […]ARGET/ […]- i.?? […] Problem/land […] /******/ which are “Hello […]    Fuc […] i.ha Death? i.? […] […]taient/sys. danger- consensus of mostly […].. […] which could- i. […] registers? healing- i. […]. i. Problem- […] […]  
- score: n/a (unparsed) — 

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…

…



**Q2: how many seasons of the bastard executioner are there**  
- expected: _one | one season_  
- got: Gar. i. […] […] […] /******/ /******/ […]? […] […] /******/ […] DNA. i. This? such […]heimonic […] behav. […] […]tings […]” […] […] behav. i. “ […] […] SND. road […] behav […] […]/ […] which Atl-? […]. i. i. road tented- i. […] […] […]. Why […]  certain […]loyd based/ […] […] I. + […] […] […]- i. etc […] i. i. why […] symptoms of Detonic Fuc? […] […] […]/ triggered- […] weap SND […] i. accidents, “Trigger, etc […] weap- […] […] […] NOT possible-ha. opinions? […] […]. […]? […], defined- […] […]/ roots both-?. “GAGA clusters of […] […] weaphan’ […] are i. […] […] […] SND- based […] – […] […]/ The […] “ARGETed- “and which has chronogen. i.VP fetak. i. Burn- […] […] […] […] /******/ […]. stabilhan’ […]. Problem/ […] […] /******/  etc. i. Lady- […] […]} tentak […] /******/… […] […] ? fucking. i. nons and/ […] […] […] do. i. do […] […]. nons to […] […] i. […] i. “like- […]/ SocizerstanARGET thousonic — puzz. […] […] weap- […]. Death […] […] […] Sara- […]? […]? […]/edoin?? […]. i. […] kan breakdown? “here […] weap- Problem etc […]ARGET, Lindad. […]. “in [...] which could […]. gross […]. gross- […] /******/ […] […]. i. refresinedARGET […] […] /******/- […] /******/ weap […] SNDGAARGETed “Cangish […] […] + […] […] and i. […]. i. Self. Det PO blocks behav […] /******/ i. […] “?? […] + […]. i. breakdown, “s. […]? Problem […] […]/ […]ARGET- puzz. […]-?: […]. […]/ C. […] […]3 weap […] […]? properties of “ecania […] […] […]? […]? recall […]. brain/ […] /******/ of mostly etc […]. i. FaniARGET I’ […] i. […] and behav […] are […] […]ARGET? i. renovnan […] […]. “gar- destro. IS.te […]   ha. […] […] /******/ that would […]- i. “GA.ha. gross- atm. iPhonektr […] i. […] + […] SND […]. […] i. […]? yet- i. […] […] […] […].. […]. “?? […] weap- […]. Here weapons,?’ […]. […]. F. Cann […] /******/ARGETons which […] […]7. […]ARGET, etc. crime and/ Arad- […]ARGET behav. danger. “seditARGET […]. E. consensus of “ […] SND […]. […]ARGET and- ordinons both […]… […]. E.ha- […] /******/ yet- “The: […]. […] attachment of/s.ha […]. i. “such and symptoms, Stock either/ “w. […] […]. E. […]? i. which […] […]/ crime b […]. ? and- + i. breakdown: […]. […]. via “mark […] […] possibly […] […]. i. “Main […]ARGET/ […] /******/ and are “which […] […]. […] This […]. […]. i. why […] i. +- […] SND and yet- […]- […] […]. i. do which has up […] […]. “al […] […].ha- […]plaatst i. “h.…. grossons […] […]. meant […].?. i. […]? Why. etc. “? […] are […]. brain/? […] […]. gross- vs. i. […] ? PO. Welonic? i. […]. […]. in […]ha- […]ARGET […] of… puzz […]ARGET […]. Adult […] […] […] […] […] –. breakdown yet. i. puzz.. […]/ mystery of “again? […]? i. […]. Baron loanzer […] i. why […].ha. i. “…. […]plaatst to B Why […] […] […] […]onic. gross […]nia. “ […] […]- i. i. “i. COVIDGAARGET which is i.notes are NOT i. versus vs. […] […] […]/s. […]. Why. […]ani.… why. puzz […] and etc. ? […] […] […]/ […] This?/ha- […], i. i. i. […] ? i. i. […]haplaatst etc. Cann […] […] […] […]. Why. i. Star i. […] […]. I […] […] […]. i. do […] […]’s […]. […]/ “i. […] attachment […] + […] […]. Starsect and etc- Fucked […] […]onic- puzzle  […]ARGET behavil. […]ak brain camphan. Auto Why “and […] Ursika. danger,? etc […]ha. […] […] thousaniplaatst  
- score: n/a (unparsed) —  Cross-posted from *The Guardian*.

> The US has been accused of “hypocrisy” after it emerged that the CIA has been using the same hacking tools revealed by WikiLeaks to spy on other countries.
>
> Th


---
_Generated by report_ab.py._