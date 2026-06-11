import os, json
from datasets import load_dataset

BASE = os.environ["BASE"]
N = int(os.environ.get("CORPUS_N", "5000"))
Q = int(os.environ.get("QUERIES_N", "200"))

corpus = load_dataset("BeIR/nq", "corpus", split=f"corpus[:{N}]")
os.makedirs(f"{BASE}/data/docs", exist_ok=True)

buf = []; fi = 0
for i, row in enumerate(corpus):
    buf.append(f"# {row.get('title','')}\n{row.get('text','')}\n")
    if len(buf) >= 100:
        open(f"{BASE}/data/docs/passages_{fi:04d}.txt", "w").write("\n".join(buf))
        buf = []; fi += 1
if buf:
    open(f"{BASE}/data/docs/passages_{fi:04d}.txt", "w").write("\n".join(buf))
print(f"wrote {fi+1} doc files from {N} passages")

qs = load_dataset("BeIR/nq", "queries", split=f"queries[:{Q}]")
with open(f"{BASE}/data/queries.jsonl", "w") as f:
    for r in qs:
        f.write(json.dumps({"q": r["text"]}) + "\n")
print(f"wrote {Q} queries")
