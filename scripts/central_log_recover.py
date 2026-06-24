#!/usr/bin/env python3
"""
central_log_recover.py: Merge missing stats.log entries into central log.

Finds all stats.log files recursively from current directory, reads each JSONL line,
validates JSON, deduplicates against central log, appends missing entries.

Append-only -- never modifies existing entries. Run with --dry-run to preview.
"""

import os
import json
import sys
import argparse

SKIP_DIRS = {".git", "__pycache__", "node_modules", ".venv", "venv", ".tox", "build", "dist"}


def find_stats_files(root="."):
    found = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if f == "stats.log":
                found.append(os.path.join(dirpath, f))
    return sorted(found)


def load_central_set(path):
    s = set()
    count = 0
    try:
        with open(path, "r") as f:
            for raw in f:
                line = raw.rstrip("\n").rstrip("\r")
                if line:
                    s.add(line)
                    count += 1
    except FileNotFoundError:
        pass
    return s, count


def main():
    parser = argparse.ArgumentParser(
        description="Merge missing stats.log entries into central log."
    )
    parser.add_argument(
        "--central-log",
        default=None,
        help="Path to central stats log (default: $AICODER_CENTRAL_LOG or ~/.aicoder/central_stats.log)",
    )
    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="Preview what would be added without writing",
    )
    args = parser.parse_args()

    central_log = args.central_log or os.environ.get("AICODER_CENTRAL_LOG")
    if not central_log:
        home = os.environ.get("HOME", "/home/blah")
        central_log = os.path.join(home, ".aicoder", "central_stats.log")

    central_set, central_count = load_central_set(central_log)
    print(f"Central log: {central_log} ({central_count} entries)", file=sys.stderr)

    stats_files = find_stats_files(".")
    print(f"Found {len(stats_files)} stats.log files", file=sys.stderr)

    if not stats_files:
        print("No stats.log files found.", file=sys.stderr)
        sys.exit(0)

    added = 0
    skipped = 0
    errors = 0

    if args.dry_run:
        out_f = None
    else:
        try:
            log_dir = os.path.dirname(central_log)
            if log_dir:
                os.makedirs(log_dir, exist_ok=True)
            out_f = open(central_log, "a")
        except IOError as e:
            print(f"Error: cannot write to {central_log}: {e}", file=sys.stderr)
            sys.exit(1)

    try:
        for filepath in stats_files:
            try:
                with open(filepath, "r") as f:
                    for raw in f:
                        line = raw.rstrip("\n").rstrip("\r")
                        if not line:
                            continue

                        if line in central_set:
                            skipped += 1
                            continue

                        try:
                            json.loads(line)
                        except json.JSONDecodeError as e:
                            print(f"  [SKIP] Invalid JSON in {filepath}: {e}", file=sys.stderr)
                            print(f"    -> {line[:120]}", file=sys.stderr)
                            errors += 1
                            continue

                        if out_f:
                            out_f.write(line + "\n")
                            out_f.flush()
                        else:
                            print(f"  [DRY-RUN] would add: {line[:100]}...", file=sys.stderr)

                        central_set.add(line)
                        added += 1
            except IOError as e:
                print(f"  [ERROR] opening {filepath}: {e}", file=sys.stderr)
                errors += 1
    finally:
        if out_f:
            out_f.close()

    print(f"Done: {added} added, {skipped} skipped (already in central), {errors} errors", file=sys.stderr)
    if added > 0 and not args.dry_run:
        print(f"Recovered {added} entries to {central_log}")


if __name__ == "__main__":
    main()
