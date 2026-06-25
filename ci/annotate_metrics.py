#!/usr/bin/env python3
"""Tag each per-question metrics row with the chat model that produced it, and
APPEND the tagged rows to a combined file.

The CI model-sweep runs the A/B once per model; evaluate.py writes
data/results/metrics_<job>.jsonl for whichever model is currently loaded. This
helper stamps every row with `chat_model` and appends it to the per-run combined
file, so compare_rows.py can build one CSV covering all (model, question) pairs.

  annotate_metrics.py --model <name> --in <metrics.jsonl> --out <combined.jsonl>
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="chat model name to stamp on each row")
    ap.add_argument("--in", dest="src", required=True, help="source metrics_<job>.jsonl")
    ap.add_argument("--out", required=True, help="combined file to APPEND tagged rows to")
    args = ap.parse_args()

    n = 0
    with open(args.src) as fin, open(args.out, "a") as fout:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            r["chat_model"] = args.model
            fout.write(json.dumps(r) + "\n")
            n += 1
    print(f"[annotate] {n} rows tagged chat_model={args.model} -> {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
