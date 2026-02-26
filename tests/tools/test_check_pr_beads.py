"""Tests for tools/check_pr_beads.py."""

import os
import subprocess
import sys


SCRIPT = os.path.join(os.path.dirname(__file__), "..", "..", "tools", "check_pr_beads.py")


def run(title: str, body: str) -> subprocess.CompletedProcess:
    env = {**os.environ, "PR_TITLE": title, "PR_BODY": body}
    return subprocess.run(
        [sys.executable, SCRIPT], capture_output=True, text=True, env=env
    )


def test_no_mentions_warns():
    result = run("feat: add feature", "Just some description")
    assert result.returncode == 0
    assert "warning" in result.stdout.lower()


def test_explicit_closes_passes():
    result = run(
        "feat: add armor",
        "## Summary\nArmor stuff\n\nCloses roots-of-reason-fk5.3\n",
    )
    assert result.returncode == 0
    assert "1 bead closure" in result.stdout


def test_multiple_closes():
    body = "Closes roots-of-reason-fk5.3\nCloses roots-of-reason-fk5.4\n"
    result = run("feat: armor and siege", body)
    assert result.returncode == 0
    assert "2 bead closure" in result.stdout


def test_informal_mention_fails():
    body = "Implemented roots-of-reason-fk5.3 armor matrix"
    result = run("feat: armor", body)
    assert result.returncode == 1
    assert "informal" in result.stdout.lower()


def test_chore_pr_skipped():
    result = run("chore(deps): bump actions/checkout", "")
    assert result.returncode == 0
    assert "Skipping" in result.stdout


def test_ci_pr_skipped():
    result = run("ci: fix workflow", "")
    assert result.returncode == 0
    assert "Skipping" in result.stdout


def test_case_insensitive_closes():
    result = run("feat: thing", "closes roots-of-reason-abc.1\n")
    assert result.returncode == 0
    assert "1 bead closure" in result.stdout
