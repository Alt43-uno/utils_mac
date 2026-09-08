#!/usr/bin/env python3
"""Check publishable Git history without echoing sensitive values.

Checks author/tagger email, Finder metadata, local paths, and common secrets.
This is a guard against recurring mistakes, not a complete secret detector.
"""
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args])


def main():
    patterns = {
        "local home path": re.compile(rb"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
        "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
        "access token": re.compile(
            rb"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}"
            rb"|sk-(?:proj-)?[A-Za-z0-9_-]{24,}|AKIA[0-9A-Z]{16}"
            rb"|xox[baprs]-[A-Za-z0-9-]{15,})"
        ),
        "credential in URL": re.compile(rb"https?://[^/\s:@]+:[^/\s@]+@"),
    }
    # Only refs intended for publication; exclude editor snapshots and reflogs.
    rows = git("rev-list", "--objects", "HEAD", "--branches", "--tags", "--remotes").splitlines()
    failures = []
    for row in rows:
        oid, _, path = row.partition(b" ")
        kind = git("cat-file", "-t", oid.decode()).strip()
        if kind not in (b"blob", b"commit", b"tag"):
            continue
        data = git("cat-file", "-p", oid.decode())
        label = oid[:12].decode()
        if path.split(b"/")[-1] == b".DS_Store":
            failures.append(f"{label}: Finder metadata in history")
        if kind in (b"commit", b"tag"):
            header = data.split(b"\n\n", 1)[0]
            for email in re.findall(rb"^(?:author|committer|tagger) .* <([^>]+)>", header, re.M):
                if not email.endswith(b"@users.noreply.github.com"):
                    failures.append(f"{label}: identity uses a non-noreply email")
        for name, pattern in patterns.items():
            if pattern.search(data):
                failures.append(f"{label}: {name}")
    if failures:
        print("Repository privacy check failed (values withheld):")
        print("\n".join(sorted(set(failures))))
        return 1
    print("Repository privacy check passed for publishable history.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
