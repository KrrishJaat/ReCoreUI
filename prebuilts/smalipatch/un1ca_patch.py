#!/usr/bin/env python3
"""ReCoreUI UN1CA unified/Git patch engine.

Applies stock UN1CA *.patch files to an Apktool/baksmali work directory.
The engine is deliberately conservative: it validates patch paths, checks
idempotency, prefers git apply, and uses bounded GNU patch fuzz only as a
compatibility fallback.
"""
from __future__ import annotations
import argparse, os, re, subprocess, sys
from pathlib import Path


def err(msg: str) -> None:
    print(f"un1ca_patch.py: ERROR: {msg}", file=sys.stderr)


def run(cmd, cwd=None, stdin=None):
    env = os.environ.copy()
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env.setdefault("LC_ALL", "C")
    return subprocess.run(cmd, cwd=cwd, input=stdin, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          env=env)


def validate_patch_file(p: Path) -> None:
    if not p.is_file():
        raise ValueError(f"Patch file not found: {p}")
    text = p.read_text(encoding="utf-8", errors="strict")
    if not re.search(r"(?m)^(diff --git |--- |From )", text):
        raise ValueError("not a supported unified/Git patch")

    paths = []
    for raw in text.splitlines():
        if raw.startswith("diff --git "):
            parts = raw[11:].split()
            paths.extend(parts[:2])
        elif raw.startswith("--- ") or raw.startswith("+++ "):
            paths.append(raw[4:].split("\t", 1)[0].strip())
    for path in paths:
        if path == "/dev/null":
            continue
        clean = path[2:] if path[:2] in ("a/", "b/") else path
        if clean.startswith("/") or any(x == ".." for x in clean.split("/")):
            raise ValueError(f"unsafe patch path: {path}")
        if "\x00" in clean:
            raise ValueError("NUL in patch path")


def has_real_deletions(p: Path) -> bool:
    for raw in p.read_text(encoding="utf-8").splitlines():
        if raw.startswith("--- ") or raw.startswith("+++ "):
            continue
        if raw.startswith("-") and not raw.startswith("---"):
            return True
    return False


def git_check(work: Path, patch: Path, reverse=False, strip=1):
    cmd = ["git", "-c", "core.safecrlf=false", 
           "apply", "--check", "--whitespace=nowarn", f"-p{strip}"]
    if reverse:
        cmd.append("--reverse")
    cmd.append(str(patch))
    return run(cmd, cwd=str(work))


def git_apply(work: Path, patch: Path, strip=1):
    cmd = ["git", "-c", "core.safecrlf=false", 
           "apply", "--whitespace=nowarn", f"-p{strip}", str(patch)]
    return run(cmd, cwd=str(work))


def patch_check(work: Path, patch: Path, reverse=False, fuzz=2, strip=1):
    cmd = ["patch", "--batch", "--forward" if not reverse else "--reverse",
           f"--fuzz={fuzz}", "--no-backup-if-mismatch", f"-p{strip}", "-l", "--dry-run"]
    return run(cmd, cwd=str(work), stdin=patch.read_text(encoding="utf-8"))


def patch_apply(work: Path, patch: Path, fuzz=2, strip=1):
    cmd = ["patch", "--batch", "--forward", f"--fuzz={fuzz}",
           "--no-backup-if-mismatch", f"-p{strip}", "-l"]
    return run(cmd, cwd=str(work), stdin=patch.read_text(encoding="utf-8"))


def clean_artifacts(work: Path) -> bool:
    bad = list(work.rglob("*.rej")) + list(work.rglob("*.orig"))
    return not bad


def strip_candidates(patch: Path):
    text = patch.read_text(encoding="utf-8", errors="strict")
    # UN1CA Git patches use a/ and b/. Plain unified patches normally need p0.
    return [1, 0] if re.search(r"(?m)^diff --git a/", text) else [0, 1]


def apply_un1ca_patch(work_dir: str, patch_file: str, *, dry_run=False,
                      quiet=False, verbose=False, fuzz=2, fallback=True,
                      subject=True) -> int:
    work = Path(work_dir).resolve()
    patch = Path(patch_file).resolve()
    if not work.is_dir():
        raise ValueError(f"work directory not found: {work}")
    validate_patch_file(patch)
    if subject and not quiet:
        print(f"[UN1CA] {patch.name}")

    candidates = strip_candidates(patch)

    # Reverse-check first. For GNU patch, only do this for patches containing
    # real deletions; insertion-only patches can produce false positives.
    for strip in candidates:
        r = git_check(work, patch, reverse=True, strip=strip)
        if r.returncode == 0:
            if not quiet: print(f"[UN1CA] Already applied: {patch.name}")
            return 0
    if has_real_deletions(patch):
        for strip in candidates:
            r = patch_check(work, patch, reverse=True, fuzz=min(fuzz, 2), strip=strip)
            if r.returncode == 0 and "Reversed" not in (r.stdout + r.stderr):
                if not quiet: print(f"[UN1CA] Already applied (compatibility state): {patch.name}")
                return 0

    for strip in candidates:
        r = git_check(work, patch, reverse=False, strip=strip)
        if r.returncode == 0:
            if dry_run:
                if not quiet: print(f"[UN1CA] Dry-run OK: {patch.name}")
                return 0
            a = git_apply(work, patch, strip=strip)
            if a.returncode == 0:
                if not quiet: print(f"[UN1CA] Applied: {patch.name}")
                return 0
            if verbose and not quiet:
                print(a.stderr, file=sys.stderr, end="")

    if fallback:
        for strip in candidates:
            r = patch_check(work, patch, reverse=False, fuzz=min(fuzz, 2), strip=strip)
            out = r.stdout + r.stderr
            bad = re.search(r"FAILED|saving rejects|Hunk #[0-9]+ FAILED|Reversed \(or previously applied\)|Skipping patch", out)
            if r.returncode == 0 and not bad:
                if dry_run:
                    if not quiet: print(f"[UN1CA] Dry-run OK (fallback): {patch.name}")
                    return 0
                a = patch_apply(work, patch, fuzz=min(fuzz, 2), strip=strip)
                if a.returncode == 0 and clean_artifacts(work):
                    if not quiet: print(f"[UN1CA] Applied with bounded fallback: {patch.name}")
                    return 0
                err(a.stderr or "GNU patch failed or left reject/original files")
                return 1

    err(f"patch context mismatch: {patch.name}")
    if verbose:
        print("git apply diagnostics:", file=sys.stderr)
        for strip in candidates:
            r = git_check(work, patch, reverse=False, strip=strip)
            print(r.stderr, file=sys.stderr, end="")
    return 1


def main():
    ap = argparse.ArgumentParser(description="Apply a stock UN1CA .patch")
    ap.add_argument("work_dir")
    ap.add_argument("patch_file")
    ap.add_argument("-n", "--dry-run", action="store_true")
    ap.add_argument("-q", "--quiet", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--fuzz", type=int, default=2)
    ap.add_argument("--no-fallback", action="store_true")
    ap.add_argument("--no-subject", action="store_true")
    args = ap.parse_args()
    if args.fuzz < 0:
        err("--fuzz must be >= 0")
        return 2
    try:
        return apply_un1ca_patch(args.work_dir, args.patch_file,
            dry_run=args.dry_run, quiet=args.quiet, verbose=args.verbose,
            fuzz=args.fuzz, fallback=not args.no_fallback,
            subject=not args.no_subject)
    except Exception as e:
        err(str(e))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
