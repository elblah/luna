#!/usr/bin/env python3
"""
Backfill empty URLs in central_stats.log by inferring from:
1. Known entries with same model that have URLs
2. Hardcoded rules for models with zero URL references

Usage: python3 scripts/fix_stats_urls.py [path/to/central_stats.log]
       Default: ../.aicoder/central_stats.log relative to script
"""
import json
import os
import sys
from collections import Counter

if len(sys.argv) > 1:
    CENTRAL_LOG = sys.argv[1]
else:
    CENTRAL_LOG = os.path.join(os.path.dirname(__file__), "..", ".aicoder", "central_stats.log")
    CENTRAL_LOG = os.path.abspath(CENTRAL_LOG)

# Hardcoded rules for models with no URL entries anywhere in the log
MODEL_URL_RULES = {
    "mistral-medium-latest": "https://api.mistral.ai/v1",
    "ministral-3b-2512": "https://api.mistral.ai/v1",
    "devstral-2512": "https://api.mistral.ai/v1",
    "qwen/qwen3.6-27b": "https://api.groq.com/openai/v1",
    "qwen/qwen3-next-80b-a3b-instruct": "https://integrate.api.nvidia.com/v1",
    "gpt-oss-120b": "https://api.cerebras.ai/v1",
}


def main():
    # Pass 1: read all entries, build model->URL map
    entries = []
    model_urls = {}
    fixed = 0
    total = 0

    with open(CENTRAL_LOG) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            total += 1
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue

            m = e.get("model", "")
            u = e.get("url", "")

            if u:
                model_urls.setdefault(m, Counter())
                model_urls[m][u] += 1

            entries.append(e)

    # Pass 2: fix empty URLs
    for e in entries:
        if e.get("url", "") != "":
            continue

        m = e.get("model", "")

        # Try infer from same-model entries first
        if m in model_urls:
            best_url, _ = model_urls[m].most_common(1)[0]
            e["url"] = best_url
            fixed += 1
            continue

        # Try hardcoded rule
        if m in MODEL_URL_RULES:
            e["url"] = MODEL_URL_RULES[m]
            fixed += 1
            continue

        # If no rule exists, check if model name has known patterns
        m_lower = m.lower()
        if "free" in m_lower and "kilo" not in m_lower:
            e["url"] = "https://opencode.ai/zen/v1"
            fixed += 1
        elif "mistral" in m_lower or "ministral" in m_lower or "devstral" in m_lower:
            e["url"] = "https://api.mistral.ai/v1"
            fixed += 1
        elif "minimax" in m_lower:
            e["url"] = "https://api.minimax.io/anthropic/v1/messages"
            fixed += 1
        elif "qwen" in m_lower or "deepseek" in m_lower or "mimo" in m_lower or "north" in m_lower or "nemotron" in m_lower:
            e["url"] = "https://opencode.ai/zen/go/v1"
            fixed += 1
        else:
            print(f"  WARN: no rule for model '{m}', leaving as empty")

    # Pass 3: write back
    tmp = CENTRAL_LOG + ".tmp"
    with open(tmp, "w") as f:
        for e in entries:
            f.write(json.dumps(e, separators=(",", ":")) + "\n")

    os.replace(tmp, CENTRAL_LOG)
    print(f"Done. {fixed}/{total} entries fixed (empty URL).")


if __name__ == "__main__":
    main()
