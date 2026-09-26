#!/usr/bin/env python3
"""ReCoreUI UN1CA patch executor.

Apply stock UN1CA unified/Git patches to decoded Apktool trees.
The decoded tree normally lives inside the outer ReCoreUI Git repository,
so Git must be isolated with a temporary GIT_DIR/GIT_WORK_TREE pair; otherwise
`git apply` can resolve paths against the outer repository, return success for
untracked decoded files, and change nothing.
"""
from __future__ import annotations
import argparse, os, re, subprocess, sys, tempfile
from pathlib import Path


def err(msg: str) -> None:
    print(f"un1ca_patch.py: ERROR: {msg}", file=sys.stderr)


def run(cmd, cwd=None, stdin=None, env_extra=None):
    env = os.environ.copy()
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env.setdefault("LC_ALL", "C")
    if env_extra:
        env.update(env_extra)
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
    work_real = os.path.realpath(str(work))
    for rel in rel_paths:
        target_real = os.path.realpath(str(work / rel))
        if target_real != work_real and not target_real.startswith(work_real + os.sep):
            raise ValueError(f"patch target escapes work dir via symlink: {rel}")


def new_file_targets(p: Path) -> list[str]:
    lines = p.read_text(encoding="utf-8", errors="strict").splitlines()
    out = []
    for i, line in enumerate(lines[:-1]):
        if line == "--- /dev/null" and lines[i + 1].startswith("+++ b/"):
            out.append(lines[i + 1][6:].split("\t", 1)[0].strip())
    return sorted(set(out))


def git_check(work: Path, patch: Path, git_dir: Path, reverse=False, strip=1):
    cmd = ["git", "-c", "core.safecrlf=false",
           "apply", "--check", "--whitespace=nowarn", f"-p{strip}"]
    if reverse:
        cmd.append("--reverse")
    cmd.append(str(patch))
    return run(cmd, cwd=str(work), env_extra={
        "GIT_DIR": str(git_dir),
        "GIT_WORK_TREE": str(work),
    })


def git_apply(work: Path, patch: Path, git_dir: Path, strip=1):
    cmd = ["git", "-c", "core.safecrlf=false",
           "apply", "--whitespace=nowarn", f"-p{strip}", str(patch)]
    return run(cmd, cwd=str(work), env_extra={
        "GIT_DIR": str(git_dir),
        "GIT_WORK_TREE": str(work),
    })


def patch_check(work: Path, patch: Path, reverse=False, fuzz=2, strip=1):
    cmd = ["patch", "--batch"]
    if reverse:
        # Prevent GNU patch from auto-flipping an unapplied patch.
        cmd += ["--reverse", "--forward"]
    else:
        cmd += ["--forward"]
    cmd += [f"--fuzz={fuzz}", "--no-backup-if-mismatch", f"-p{strip}", "-l", "--dry-run"]
    return run(cmd, cwd=str(work), stdin=patch.read_text(encoding="utf-8"))


def patch_apply(work: Path, patch: Path, fuzz=2, strip=1):
    cmd = ["patch", "--batch", "--forward", f"--fuzz={fuzz}",
           "--no-backup-if-mismatch", f"-p{strip}", "-l"]
    return run(cmd, cwd=str(work), stdin=patch.read_text(encoding="utf-8"))


def clean_artifacts(work: Path) -> bool:
    return not (list(work.rglob("*.rej")) + list(work.rglob("*.orig")))


def strip_candidates(patch: Path):
    text = patch.read_text(encoding="utf-8", errors="strict")
    return [1, 0] if re.search(r"(?m)^diff --git a/", text) else [0, 1]


def _backup_targets(work: Path, rel_paths: list[str]) -> dict:
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
    expected_new = new_file_targets(patch)
    if subject and not quiet:
        print(f"[UN1CA] {patch.name}")
    candidates = strip_candidates(patch)

    # Git must be isolated from any parent repository. ReCoreUI's decoded
    # trees are untracked directories nested under the checkout, and plain
    # `git apply` in them can return 0 while changing nothing.
    with tempfile.TemporaryDirectory(prefix="un1ca_git_") as git_tmp:
        git_dir = Path(git_tmp) / "repo"
        init = run(["git", "init", "-q", str(git_dir)])
        if init.returncode != 0:
            raise RuntimeError(init.stderr.strip() or "failed to initialize temporary Git directory")

        # Exact reverse check = already applied. Because this Git context is
        # private to the decoded tree, it actually tests the files on disk.
        for strip in candidates:
            r = git_check(work, patch, git_dir, reverse=True, strip=strip)
            if r.returncode == 0:
                missing = [rel for rel in expected_new if not (work / rel).is_file()]
                if not missing:
                    if not quiet:
                        print(f"[UN1CA] Already applied: {patch.name}")
                    return 0

        # Some UN1CA patches are accepted through bounded GNU fuzz because the
        # ROM baseline differs slightly. Recognize that already-applied state
        # with GNU's explicit --reverse --forward probe, which cannot silently
        # flip an unapplied patch. This is intentionally SECONDARY: plain Git
        # reverse-check must not be used against the outer ReCoreUI repository.
        for strip in candidates:
            r = patch_check(work, patch, reverse=True, fuzz=min(fuzz, 2), strip=strip)
            if r.returncode == 0:
                missing = [rel for rel in expected_new if not (work / rel).is_file()]
                if not missing:
                    if not quiet:
                        print(f"[UN1CA] Already applied (compatibility state): {patch.name}")
                    return 0

        for strip in candidates:
            r = git_check(work, patch, git_dir, reverse=False, strip=strip)
            if r.returncode == 0:
                if dry_run:
                    if not quiet:
                        print(f"[UN1CA] Dry-run OK: {patch.name}")
                    return 0
                a = git_apply(work, patch, git_dir, strip=strip)
                if a.returncode == 0:
                    missing = [rel for rel in expected_new if not (work / rel).is_file()]
                    if missing:
                        err(f"patch reported success but did not create expected file(s): {', '.join(missing)}")
                        return 1
                    if not quiet:
                        print(f"[UN1CA] Applied: {patch.name}")
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
                        if not quiet:
                            print(f"[UN1CA] Dry-run OK (fallback): {patch.name}")
                        return 0
                    backups = _backup_targets(work, rel_targets)
                    a = patch_apply(work, patch, fuzz=min(fuzz, 2), strip=strip)
                    if a.returncode == 0 and clean_artifacts(work):
                        missing = [rel for rel in expected_new if not (work / rel).is_file()]
                        if missing:
                            _restore_targets(work, backups)
                            err(f"patch reported success but did not create expected file(s): {', '.join(missing)}")
                            return 1
                        if not quiet:
                            print(f"[UN1CA] Applied with bounded fallback: {patch.name}")
                        return 0
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
                r = git_check(work, patch, git_dir, reverse=False, strip=strip)
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
                                 dry_run=args.dry_run, quiet=args.quiet,
                                 verbose=args.verbose, fuzz=args.fuzz,
                                 fallback=not args.no_fallback,
                                 subject=not args.no_subject)
    except Exception as e:
        err(str(e))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
