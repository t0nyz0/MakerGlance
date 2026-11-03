#!/usr/bin/env python3
"""Small, dependency-free source/history guard. Not a complete secret detector."""
import argparse
import collections
from pathlib import Path
import re
import subprocess
import sys

PATTERNS = {
    "private-key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "github-token": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})",
    "jwt-shaped-credential": rb"eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{10,}",
    "aws-access-id": rb"(?:AKIA|ASIA)[A-Z0-9]{16}",
    "machine-home-path": rb"/(?:Users|home)/[A-Za-z0-9_.-]+/",
}
EXCLUDED = {".git", ".build", ".swiftpm", "dist", "__pycache__", ".local", "private"}
SENSITIVE_NAMES = {"accesstoken.json", "connection-status.json", "audit.json", "audit-error.txt"}
SENSITIVE_SUFFIXES = {".sqlite", ".sqlite-wal", ".sqlite-shm", ".db", ".pem", ".key", ".p12", ".pfx", ".mobileprovision", ".dmg"}

def findings(data, secrets_only=False):
    if b"\0" in data[:8000]:
        return []
    output = []
    for rule, pattern in PATTERNS.items():
        if secrets_only and rule == "machine-home-path":
            continue
        for match in re.finditer(pattern, data):
            # Recognize one exact historical verifier assertion, which contains
            # only a header literal. Real key headers elsewhere still flag.
            start = data.rfind(b"\n", 0, match.start()) + 1
            end = data.find(b"\n", match.end())
            line = data[start:end if end >= 0 else len(data)].strip()
            guard_literals = {b"assert b" + quote + b"-----BEGIN " + b"PRIVATE KEY-----" + quote + b" not in data" for quote in (b"'", b'"')}
            if rule == "private-key" and line in guard_literals:
                continue
            output.append((rule, data[:match.start()].count(b"\n") + 1))
    return output

def prohibited_name(path):
    p = Path(path)
    return p.name.lower() in SENSITIVE_NAMES or p.suffix.lower() in SENSITIVE_SUFFIXES or p.name.startswith(".env") or any(x.endswith(".app") for x in p.parts)

def files(root):
    if (root / ".git").exists():
        names = subprocess.check_output(["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]).decode().split("\0")
        return [Path(x) for x in names if x]
    return [p.relative_to(root) for p in root.rglob("*") if p.is_file() and not any(x in EXCLUDED or x.startswith(".venv") for x in p.relative_to(root).parts)]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true", help="Scan every reachable historical blob, without printing matching values")
    parser.add_argument("--secrets-only", action="store_true", help="Omit historical machine-path findings; this does not clear the publication privacy gate")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    issues = []; scanned = 0
    if args.history:
        lines = subprocess.check_output(["git", "-C", str(root), "rev-list", "--objects", "--all"]).decode().splitlines()
        for line in lines:
            sha, _, name = line.partition(" ")
            if not name or subprocess.check_output(["git", "-C", str(root), "cat-file", "-t", sha]).strip() != b"blob":
                continue
            data = subprocess.check_output(["git", "-C", str(root), "cat-file", "blob", sha]); scanned += 1
            issues.extend((f"{sha[:12]}:{name}", rule, number) for rule, number in findings(data, args.secrets_only))
    else:
        for name in files(root):
            path = root / name
            if not path.exists():
                issues.append((str(name), "missing-tracked-file", 0)); continue
            scanned += 1
            if prohibited_name(name):
                issues.append((str(name), "sensitive-artifact-name", 0))
            issues.extend((str(name), rule, number) for rule, number in findings(path.read_bytes()))
    for name, rule, number in issues:
        print(f"{name}:{number}: {rule}; matching value withheld")
    print(f"Checked {scanned} files/blobs; {len(issues)} findings. Pattern checks are not a security guarantee.")
    return bool(issues)

if __name__ == "__main__":
    sys.exit(main())
