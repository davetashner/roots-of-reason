#!/usr/bin/env python3
"""Check that PR bodies contain explicit 'Closes roots-of-reason-*' lines.

Runs as a CI check on pull requests. Warns (does not fail) if no bead
references are found, since some PRs (dependency bumps, CI changes) are
legitimately bead-free.
"""

import json
import os
import re
import sys


def main() -> int:
    pr_body = os.environ.get("PR_BODY", "")
    pr_title = os.environ.get("PR_TITLE", "")

    # Skip for non-feature PRs (deps, CI, docs-only)
    skip_prefixes = ("chore(deps):", "chore:", "ci:", "docs:")
    if any(pr_title.lower().startswith(p) for p in skip_prefixes):
        print("Skipping bead check for non-feature PR")
        return 0

    # Find explicit Closes lines
    closes = re.findall(
        r"^Closes\s+(roots-of-reason-[\w.-]+)", pr_body, re.MULTILINE | re.IGNORECASE
    )
    # Find informal bead mentions (not in a Closes line)
    all_mentions = re.findall(r"roots-of-reason-[\w.-]+", pr_body)
    informal = [m for m in set(all_mentions) if m not in closes]

    # Also check for short-form mentions like [fk5.3] or fk5.3 in isolation
    short_mentions = re.findall(r"\b([a-z0-9]{2,4}\.\d+(?:\.\d+)?)\b", pr_body)

    if not closes and not all_mentions:
        print("::warning::No bead references found in PR body. If this PR "
              "completes a bead, add 'Closes roots-of-reason-XXX' lines.")
        return 0

    if informal:
        print("::warning::Found informal bead mentions without 'Closes' keyword:")
        for m in informal:
            print(f"  - {m}")
        print("If these beads are completed by this PR, change to:")
        for m in informal:
            print(f"  Closes {m}")
        return 1

    print(f"Found {len(closes)} bead closure(s):")
    for c in closes:
        print(f"  Closes {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
