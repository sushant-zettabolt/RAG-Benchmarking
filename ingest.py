import os, glob, json, requests, time

BASE = os.environ["BASE"]
KEY = os.environ["ALLM_KEY"]
U = os.environ.get("ALLM_URL", "http://127.0.0.1:3001")
H = {"Authorization": f"Bearer {KEY}"}

WS_NAME = os.environ.get("SLUG", "nq-bench")
ws = requests.post(f"{U}/api/v1/workspace/new",
                   headers={**H, "Content-Type": "application/json"},
                   json={"name": WS_NAME}).json()
slug = ws.get("workspace", {}).get("slug") or WS_NAME
print("workspace:", slug)

locs = []
for fp in sorted(glob.glob(f"{BASE}/data/docs/*.txt")):
    r = requests.post(f"{U}/api/v1/document/upload", headers=H,
                      files={"file": open(fp, "rb")})
    j = r.json()
    for d in j.get("documents", []):
        if d.get("location"):
            locs.append(d["location"])
    print(f"uploaded {os.path.basename(fp)} -> {len(locs)} docs", end="\r")

print(f"\nembedding {len(locs)} docs into workspace...")
for i in range(0, len(locs), 50):
    requests.post(f"{U}/api/v1/workspace/{slug}/update-embeddings",
                  headers={**H, "Content-Type": "application/json"},
                  json={"adds": locs[i:i+50]})
    print(f"  embedded {min(i+50, len(locs))}/{len(locs)}", end="\r")

open(f"{BASE}/results/workspace_slug.txt", "w").write(slug)
print(f"\ndone; workspace slug saved: {slug}")
