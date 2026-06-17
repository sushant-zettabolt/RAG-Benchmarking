#!/usr/bin/env python3
"""Embedding throughput benchmark — called by run_embed_ab.sh.

Sends N requests to the embed endpoint and records per-request latency.
Results are written to /data/results/metrics_embed_{JOB}.jsonl
"""
import json, os, time, statistics, urllib.request, urllib.error

EMBED_URL  = os.environ.get("EMBED_URL",  "http://llama-embed:8080")
DATA_DIR   = os.environ.get("DATA_DIR",   "/data")
JOB        = os.environ.get("JOB",        "baseline")
N_WARMUP   = int(os.environ.get("WARMUP", "3"))
N_REQUESTS = int(os.environ.get("EMBED_N", "20"))

# Fixed sample texts — varied lengths to reflect real chunk diversity.
SAMPLES = [
    "What is the capital of France? Paris is the capital and largest city of France.",
    "The Apollo program was a series of space missions conducted by NASA between 1961 and 1972. "
    "It successfully landed twelve astronauts on the Moon. The program used the Saturn V rocket.",
    "Natural language processing (NLP) is a subfield of linguistics, computer science, and "
    "artificial intelligence concerned with the interactions between computers and human language.",
    "The Great Wall of China is a series of fortifications built across the historical northern "
    "borders of ancient Chinese states and Imperial China as protection against nomadic invasions.",
    "Photosynthesis is a process used by plants and other organisms to convert light energy into "
    "chemical energy that is stored in glucose. It occurs mainly in leaves through chloroplasts.",
    "The Internet is a global system of interconnected computer networks that uses the TCP/IP "
    "protocol suite to communicate between networks and devices worldwide.",
    "Shakespeare wrote 37 plays and 154 sonnets. His works have been translated into every major "
    "language and are performed more often than those of any other playwright.",
    "The human genome contains approximately 3 billion base pairs of DNA and about 20,000 genes. "
    "The Human Genome Project completed the full sequence in 2003.",
    "Supply and demand is a fundamental economic model describing price determination in a "
    "competitive market. When supply exceeds demand, prices tend to fall, and vice versa.",
    "The speed of light in a vacuum is approximately 299,792,458 meters per second. "
    "It is denoted by the letter c and is a universal physical constant in physics.",
]

def embed_one(text: str) -> float:
    payload = json.dumps({"input": text, "model": "embed-model"}).encode()
    req = urllib.request.Request(
        f"{EMBED_URL}/v1/embeddings",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=60) as r:
        r.read()
    return time.perf_counter() - t0

def main():
    out_path = f"{DATA_DIR}/results/metrics_embed_{JOB}.jsonl"
    os.makedirs(f"{DATA_DIR}/results", exist_ok=True)

    print(f"[bench_embed_{JOB}] warmup={N_WARMUP} requests={N_REQUESTS}")
    for i in range(N_WARMUP):
        t = embed_one(SAMPLES[i % len(SAMPLES)])
        print(f"[warmup {i+1}/{N_WARMUP}] {t*1000:.0f}ms")

    latencies = []
    with open(out_path, "w") as fh:
        for i in range(N_REQUESTS):
            text = SAMPLES[i % len(SAMPLES)]
            t = embed_one(text)
            latencies.append(t)
            rec = {"job": JOB, "i": i+1, "latency_s": round(t, 4), "text_len": len(text)}
            fh.write(json.dumps(rec) + "\n")
            print(f"[{JOB}] {i+1}/{N_REQUESTS}  {t*1000:.1f}ms")

    mean_ms = statistics.mean(latencies) * 1000
    p50_ms  = statistics.median(latencies) * 1000
    p95_ms  = sorted(latencies)[int(len(latencies)*0.95)] * 1000
    tps     = 1.0 / statistics.mean(latencies)
    print(f"\n[bench_embed_{JOB}] mean={mean_ms:.1f}ms  p50={p50_ms:.1f}ms  "
          f"p95={p95_ms:.1f}ms  throughput={tps:.1f} req/s")
    print(f"[bench_embed_{JOB}] results -> {out_path}")

if __name__ == "__main__":
    main()
