#!/usr/bin/env python3
"""Per-question regression comparison for the ZenDNN CI run.

Where compare_zendnn.py compares the *aggregate* ZenDNN numbers of this run vs
the previous one (and gates the build verdict), THIS script drills down to the
per-question level and emits CSVs that put every question side-by-side:
performance (prefill/decode throughput + % delta + tag) and accuracy
(did the answer flip correct↔incorrect?).

Each CI run produces two per-question metrics files:
  * metrics_baseline_<TS>.jsonl  — the plain ggml (GGML_ZENDNN=OFF) backend
  * metrics_zendnn_<TS>.jsonl    — the ZenDNN (GGML_ZENDNN=ON) backend

Together with the *previous* run's two files (resolved from a persistent
pointer), that gives four datasets:
  ggml_prev, zendnn_prev   (previous run)
  ggml_curr, zendnn_curr   (this run)

We emit FOUR comparison CSVs, each named for exactly what it compares
(left → right):
  1. ggml_prev   → zendnn_prev    backend effect, frozen at the previous build
  2. ggml_prev   → ggml_curr      plain-backend drift across time
  3. zendnn_prev → zendnn_curr    ZenDNN drift across time (the regression watch)
  4. ggml_curr   → zendnn_curr    backend effect, this build (the live A/B)

Each file is laid out as three sections:
  * row 1  — a HEADING that states what the file compares + what delta% means
  * row 2  — the table header; value columns are SELF-DESCRIBING, suffixed with
             the dataset they came from (<time>_<backend>), e.g. file 4 has
             prefill_tps_curr_ggml vs prefill_tps_curr_zendnn, file 3 has
             decode_tps_prev_zendnn vs decode_tps_curr_zendnn — so a column never
             needs the filename to be understood. Shared columns (tags, delta %,
             prompt/decode token sizes) carry no suffix.
  * rows 3+ — one row per (model, question), grouped by model.

On the FIRST run after history is cleared there is no previous run, so the
prev_* columns are blank / "n/a" and across-time files are BASELINE — expected,
not a bug. The pointer written at the end makes the NEXT run resolve this run as
its "previous", at which point the prev_* columns populate.

"Previous run" is tracked by a persistent pointer file
(ci/history/prev_run.json) that we read at the start and OVERWRITE at the end to
point at the current run — so the next run sees this run as its "previous". This
is independent of compare_zendnn.py's history jsonl so the two never race.

Tags (per the user's vocabulary):
  perf_tag      SPEEDUP / NEUTRAL / DEGRADE   (throughput right vs left, %)
  accuracy_tag  IMPROVED / NEUTRAL / DEGRADED (correct↔incorrect flip)
                BASELINE when one side has no data for the question.
"""
import argparse
import csv
import json
import os
import sys

# Each comparison file is self-describing: the value columns are suffixed with
# WHICH dataset they came from (e.g. prefill_tps_curr_ggml vs prefill_tps_curr_zendnn)
# rather than a generic prev/curr, so a reader never has to consult the filename to
# know what a column means. A suffix is "<time>_<backend>": one of
#   prev_ggml  prev_zendnn  curr_ggml  curr_zendnn
# The shared columns (tags, delta %, prompt/decode token sizes) carry no suffix.
def header_for(left_suffix, right_suffix):
    """Build the table-header row for a comparison whose left/right datasets are
    identified by `left_suffix` / `right_suffix` (e.g. 'prev_ggml', 'curr_zendnn')."""
    return [
        "chat_model_name",
        "question",
        f"accuracy_{left_suffix}", f"accuracy_{right_suffix}", "accuracy_tag",
        "prompt_size",
        f"prefill_tps_{left_suffix}", f"prefill_tps_{right_suffix}",
        "prefill_tps_delta_percentage", "prefill_perf_tag",
        "decode_token_size",
        f"decode_tps_{left_suffix}", f"decode_tps_{right_suffix}",
        "decode_tps_delta_percentage", "decode_perf_tag",
    ]


def load_rows(path):
    """Load a metrics_*.jsonl into {(chat_model, id): row}. Missing/empty -> {}.

    The CI sweep merges every model's per-question metrics into one file, tagging
    each row with `chat_model`; keying on (model, id) keeps the comparison aligned
    per model. A file without `chat_model` (single-model run) keys on (None, id)."""
    if not path or not os.path.exists(path):
        return {}
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            out[(r.get("chat_model"), r.get("id"))] = r
    return out


def pct_delta(prev, curr):
    """Plain percent change of curr vs left/prev: (curr - prev) / prev * 100.

    No sign flipping — the number means exactly what it says (positive = curr is
    larger). Both metrics we report (prefill_tps, decode_tps) are throughput, so
    larger is better and a positive delta is a speed-up. Returns None when it
    can't be computed (missing value or prev == 0)."""
    if prev is None or curr is None:
        return None
    if prev == 0:
        return None
    return (curr - prev) / prev * 100.0


def perf_tag(delta_pct, threshold):
    """SPEEDUP/DEGRADE/NEUTRAL for a throughput metric (higher is better).

    delta_pct is the plain % change of curr vs prev, so a positive delta beyond
    +threshold is a speed-up and a negative delta beyond -threshold is a
    slow-down. BASELINE when there is nothing to compare against."""
    if delta_pct is None:
        return "BASELINE"
    if delta_pct >= threshold:
        return "SPEEDUP"
    if delta_pct <= -threshold:
        return "DEGRADE"
    return "NEUTRAL"


def accuracy_tag(prev_ok, curr_ok):
    """Did this question flip correctness from left (prev) to right (curr)?"""
    if prev_ok is None or curr_ok is None:
        return "BASELINE"
    if prev_ok and not curr_ok:
        return "DEGRADED"      # ← the regression we care about most
    if not prev_ok and curr_ok:
        return "IMPROVED"
    return "NEUTRAL"


def is_correct(row):
    """Correctness signal for a question. Prefer the LLM judge `match`; fall
    back to the model-independent lexical `contains_ref` when the judge is off
    (e.g. fixed-decode mode). None if the question errored / is absent."""
    if row is None:
        return None
    if not row.get("ok", True):
        return False
    if row.get("match") is not None:
        return bool(row.get("match"))
    if row.get("contains_ref") is not None:
        return bool(row.get("contains_ref"))
    return None


def acc_str(ok):
    if ok is None:
        return "n/a"
    return "correct" if ok else "incorrect"


def ftps(v):
    return "" if v is None else f"{float(v):.1f}"


def fpct(v):
    return "" if v is None else f"{v:+.1f}"


def fint(v):
    return "" if v is None else str(int(v))


def build_comparison(left, right, out_path, threshold,
                     left_suffix, right_suffix, heading):
    """Write one comparison CSV (left→right) and return per-tag counts +
    the (model, id) keys whose accuracy DEGRADED (correct→incorrect).

    The file is laid out as: a heading row that says what is being compared, then
    the table-header row (column names, suffixed with each side's dataset), then
    the data rows. Keys are (chat_model, id); rows are sorted by model then id so
    each model's questions are grouped together in the CSV."""
    keys = sorted(set(left) | set(right),
                  key=lambda k: ((k[0] is None, k[0]), (k[1] is None, k[1])))
    counts = {"prefill": {}, "decode": {}, "acc": {}}
    regressions = []
    rows_out = []

    for key in keys:
        model_name = key[0] or ""
        l = left.get(key)
        r = right.get(key)
        l_ok = is_correct(l)
        r_ok = is_correct(r)
        a_tag = accuracy_tag(l_ok, r_ok)
        if a_tag == "DEGRADED":
            regressions.append(key)

        # the question text + token sizes: prefer the right (curr) side, fall
        # back to the left so the row is still labelled when one side is absent.
        rr = r or l or {}
        question = (rr.get("question") or "").replace("\n", " ").strip()
        prompt_size = rr.get("prompt_tokens")
        if prompt_size is None:
            prompt_size = (l or {}).get("prompt_tokens")
        decode_size = rr.get("completion_tokens")
        if decode_size is None:
            decode_size = (l or {}).get("completion_tokens")

        pf_l = (l or {}).get("prefill_tps")
        pf_r = (r or {}).get("prefill_tps")
        pf_d = pct_delta(pf_l, pf_r)
        pf_tag = perf_tag(pf_d, threshold)

        dc_l = (l or {}).get("decode_tps")
        dc_r = (r or {}).get("decode_tps")
        dc_d = pct_delta(dc_l, dc_r)
        dc_tag = perf_tag(dc_d, threshold)

        counts["prefill"][pf_tag] = counts["prefill"].get(pf_tag, 0) + 1
        counts["decode"][dc_tag] = counts["decode"].get(dc_tag, 0) + 1
        counts["acc"][a_tag] = counts["acc"].get(a_tag, 0) + 1

        # one data row, in the exact order of header_for(left_suffix, right_suffix)
        rows_out.append([
            model_name,
            question,
            acc_str(l_ok), acc_str(r_ok), a_tag,
            fint(prompt_size),
            ftps(pf_l), ftps(pf_r), fpct(pf_d), pf_tag,
            fint(decode_size),
            ftps(dc_l), ftps(dc_r), fpct(dc_d), dc_tag,
        ])

    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([heading])                              # what this file compares
        w.writerow(header_for(left_suffix, right_suffix))  # table header
        w.writerows(rows_out)                              # data rows

    return counts, regressions, len(rows_out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--curr-baseline", required=True,
                    help="this run's metrics_baseline_<TS>.jsonl (ggml backend)")
    ap.add_argument("--curr-zendnn", required=True,
                    help="this run's metrics_zendnn_<TS>.jsonl (zendnn backend)")
    ap.add_argument("--pointer", required=True,
                    help="persistent prev-run pointer json (ci/history/prev_run.json)")
    ap.add_argument("--run-dir", required=True, help="this run's output dir")
    ap.add_argument("--timestamp", required=True, help="this run's timestamp label")
    ap.add_argument("--threshold", type=float,
                    default=float(os.environ.get("CI_CMP_THRESHOLD_PCT", "5.0")),
                    help="percent change that counts as SPEEDUP/DEGRADE")
    ap.add_argument("--build-sha", default="", help="llama.cpp commit of the zendnn image")
    args = ap.parse_args()

    ggml_curr = load_rows(args.curr_baseline)
    zendnn_curr = load_rows(args.curr_zendnn)
    if not zendnn_curr and not ggml_curr:
        sys.exit("ERROR: no current per-question metrics (baseline and zendnn both empty)")

    # ── resolve "previous run" from the persistent pointer ───────────────────
    prev_ptr = None
    if os.path.exists(args.pointer):
        try:
            prev_ptr = json.load(open(args.pointer))
        except (json.JSONDecodeError, OSError):
            prev_ptr = None
    prev_ptr = prev_ptr or {}
    ggml_prev = load_rows(prev_ptr.get("metrics_baseline"))
    zendnn_prev = load_rows(prev_ptr.get("metrics_zendnn"))
    prev_ts = prev_ptr.get("timestamp", "")

    TS = args.timestamp
    pv = prev_ts if prev_ts else "none"  # label for the previous run in headings
    # The delta % in every file is the RIGHT dataset relative to the LEFT
    # (positive = right is faster, since both metrics are throughput).
    # (label, left_rows, right_rows, filename, left_suffix, right_suffix, heading)
    plan = [
        ("ggml_prev → zendnn_prev",   ggml_prev,   zendnn_prev,
         f"cmp_ggml-prev_to_zendnn-prev_{TS}.csv", "prev_ggml", "prev_zendnn",
         f"Comparing: backend effect on the PREVIOUS run [prev={pv}] — GGML(prev) vs ZenDNN(prev). "
         f"delta% = ZenDNN relative to GGML; +ve = ZenDNN faster."),
        ("ggml_prev → ggml_curr",     ggml_prev,   ggml_curr,
         f"cmp_ggml-prev_to_ggml-curr_{TS}.csv", "prev_ggml", "curr_ggml",
         f"Comparing: GGML backend across time — prev={pv} vs curr={TS}. "
         f"delta% = current relative to previous; +ve = got faster."),
        ("zendnn_prev → zendnn_curr", zendnn_prev, zendnn_curr,
         f"cmp_zendnn-prev_to_zendnn-curr_{TS}.csv", "prev_zendnn", "curr_zendnn",
         f"Comparing: ZenDNN backend across time — prev={pv} vs curr={TS}. "
         f"delta% = current relative to previous; +ve = got faster."),
        ("ggml_curr → zendnn_curr",   ggml_curr,   zendnn_curr,
         f"cmp_ggml-curr_to_zendnn-curr_{TS}.csv", "curr_ggml", "curr_zendnn",
         f"Comparing: backend effect on THIS run [curr={TS}] — GGML(curr) vs ZenDNN(curr). "
         f"delta% = ZenDNN relative to GGML; +ve = ZenDNN faster."),
    ]

    models = sorted({k[0] for k in (set(ggml_curr) | set(zendnn_curr)) if k[0]})
    print("=" * 70)
    print(f"  Per-question comparisons — run {TS}")
    if prev_ts:
        print(f"  previous run on record: {prev_ts}")
    else:
        print("  no previous run on record — across-time comparisons are empty this run")
    print(f"  threshold: ±{args.threshold:g}%   models: {', '.join(models) or '(none tagged)'}")

    written = []
    for label, left, right, fname, lsuf, rsuf, heading in plan:
        out_path = os.path.join(args.run_dir, fname)
        counts, regressions, n = build_comparison(
            left, right, out_path, args.threshold, lsuf, rsuf, heading)
        written.append((fname, n))
        rgw = f"   ⚠️ accuracy DEGRADED on {regressions}" if regressions else ""
        print(f"  • {label:<26} {n:>3} rows -> {fname}")
        print(f"      prefill {counts['prefill']}  decode {counts['decode']}  acc {counts['acc']}{rgw}")

    # ── update the persistent prev-run pointer to THIS run ───────────────────
    new_ptr = {
        "timestamp": TS,
        "build_sha": args.build_sha,
        "run_dir": os.path.abspath(args.run_dir),
        "metrics_baseline": os.path.abspath(args.curr_baseline),
        "metrics_zendnn": os.path.abspath(args.curr_zendnn),
        "report_md": os.path.abspath(os.path.join(args.run_dir, f"report_ab_{TS}.md")),
        "report_json": os.path.abspath(os.path.join(args.run_dir, f"report_ab_{TS}.json")),
        "comparisons": [f for f, _ in written],
    }
    os.makedirs(os.path.dirname(args.pointer), exist_ok=True)
    with open(args.pointer, "w") as f:
        json.dump(new_ptr, f, indent=2)
    print(f"  prev-run pointer updated -> {args.pointer}")
    print("=" * 70)


if __name__ == "__main__":
    main()
