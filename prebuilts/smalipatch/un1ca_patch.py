#!/usr/bin/env python3
"""ReCoreUI UN1CA unified/Git patch engine.

Applies stock UN1CA *.patch files to an Apktool/baksmali work directory.
The engine is deliberately conservative: it validates patch paths (including
symlink escape, not just textual .. / absolute paths), checks idempotency via
exact reverse-apply rather than assuming a failed forward-apply means
"already applied", prefers git apply, and only falls back to bounded GNU
patch fuzz as a last resort - rolling back cleanly if that fallback fails
partway instead of leaving a partially-patched file behind.
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


def _extract_raw_paths(text: str):
    paths = []
    for raw in text.splitlines():
        if raw.startswith("diff --git "):
            parts = raw[11:].split()
            paths.extend(parts[:2])
        elif raw.startswith("--- ") or raw.startswith("+++ "):
            paths.append(raw[4:].split("\t", 1)[0].strip())
    return paths


def _clean_path(path: str):
    if path == "/dev/null":
        return None
    return path[2:] if path[:2] in ("a/", "b/") else path


def validate_patch_file(p: Path) -> list[str]:
    """Validates the patch is well-formed and every touched path is safe
    (no absolute path, no .. traversal). Returns the cleaned relative target
    paths for later use (backup/rollback, symlink-escape check)."""
    if not p.is_file():
        raise ValueError(f"Patch file not found: {p}")
    text = p.read_text(encoding="utf-8", errors="strict")
    if not re.search(r"(?m)^(diff --git |--- |From )", text):
        raise ValueError("not a supported unified/Git patch")

    cleaned_paths = []
    for path in _extract_raw_paths(text):
        clean = _clean_path(path)
        if clean is None:
            continue
        if clean.startswith("/") or any(x == ".." for x in clean.split("/")):
            raise ValueError(f"unsafe patch path: {path}")
        if "\x00" in clean:
            raise ValueError("NUL in patch path")
        cleaned_paths.append(clean)
    return sorted(set(cleaned_paths))


def validate_no_symlink_escape(work: Path, rel_paths: list[str]) -> None:
    """A patch's own path text can look perfectly safe (no absolute path, no
    ..) and still escape the work directory if some component of the real
    filesystem path is a symlink pointing elsewhere. realpath() resolves
    every symlink that actually exists along the way; a not-yet-created leaf
    file is fine since the traversal-escape risk is only in the *existing*
    directory structure."""
    work_real = os.path.realpath(str(work))
    for rel in rel_paths:
        target_real = os.path.realpath(str(work / rel))
        if target_real != work_real and not target_real.startswith(work_real + os.sep):
            raise ValueError(f"patch target escapes work dir via symlink: {rel}")


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


def _backup_targets(work: Path, rel_paths: list[str]) -> dict:
    """Snapshots every file the fallback is about to touch, recording None
    for files that don't exist yet, so a failed fallback can be undone
    exactly instead of leaving a partially-applied hunk in place."""
    backups = {}
    for rel in rel_paths:
        full = work / rel
        backups[rel] = full.read_bytes() if full.is_file() else None
    return backups


def _restore_targets(work: Path, backups: dict) -> None:
    for rel, content in backups.items():
        full = work / rel
        if content is None:
            try:
                full.unlink()
            except FileNotFoundError:
                pass
        else:
            full.parent.mkdir(parents=True, exist_ok=True)
            full.write_bytes(content)


def apply_un1ca_patch(work_dir: str, patch_file: str, *, dry_run=False,
                      quiet=False, verbose=False, fuzz=2, fallback=True,
                      subject=True) -> int:
    work = Path(work_dir).resolve()
    patch = Path(patch_file).resolve()
    if not work.is_dir():
        raise ValueError(f"work directory not found: {work}")
    rel_targets = validate_patch_file(patch)
    validate_no_symlink_escape(work, rel_targets)
    if subject and not quiet:
        print(f"[UN1CA] {patch.name}")

    candidates = strip_candidates(patch)

    # Reverse-check first, via git's own exact (non-fuzzy) matching. For GNU
    # patch, only attempt a reverse check when the patch contains real
    # deletions - an insertion-only patch has nothing for a reverse-apply to
    # remove, so a naive reverse dry-run can misreport "already applied" on
    # a patch that was never applied at all.
    for strip in candidates:
        r = git_check(work, patch, reverse=True, strip=strip)
        if r.returncode == 0:
            if not quiet: print(f"[UN1CA] Already applied: {patch.name}")
            return 0
    if has_real_deletions(patch):
        for strip in candidates:
            r = patch_check(work, patch, reverse=True, fuzz=min(fuzz, 2), strip=strip)
            out = r.stdout + r.stderr
            # GNU patch second-guesses the direction it's given: asked to
            # reverse-apply a patch that ISN'T applied yet, it prints
            # "Unreversed patch detected!  Ignoring -R." and quietly applies
            # it FORWARD instead, still exiting 0 - which is indistinguishable
            # from a real successful reverse-check by return code alone, and
            # was silently reporting "already applied" on a patch that had
            # genuinely never been touched. A true reverse success prints
            # nothing but "checking file ..."; both of patch's own
            # self-correction messages ("Reversed (or previously applied)
            # patch detected" and "Unreversed patch detected") end in
            # "patch detected", so reject on that rather than one specific
            # wording.
            if r.returncode == 0 and "patch detected" not in out:
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
                backups = _backup_targets(work, rel_targets)
                a = patch_apply(work, patch, fuzz=min(fuzz, 2), strip=strip)
                if a.returncode == 0 and clean_artifacts(work):
                    if not quiet: print(f"[UN1CA] Applied with bounded fallback: {patch.name}")
                    return 0
                # Fallback failed partway (or left .rej/.orig) - undo any
                # partial write rather than leaving a half-patched file.
                _restore_targets(work, backups)
                for stray in list(work.rglob("*.rej")) + list(work.rglob("*.orig")):
                    try:
                        stray.unlink()
                    except OSError:
                        pass
                err(a.stderr or "GNU patch failed or left reject/original files; rolled back")
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
