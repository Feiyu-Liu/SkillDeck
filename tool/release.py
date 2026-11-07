#!/usr/bin/env python3
"""SkillDeck's stable entrypoint; mechanics live in macos-signed-release."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def option(args, name):
    for index, arg in enumerate(args):
        if arg == name and index + 1 < len(args):
            return args[index + 1]
        if arg.startswith(name + "="):
            return arg.split("=", 1)[1]
    return None


def git(*args, check=True):
    return subprocess.run(["git", "-C", str(root), *args], check=check,
                          capture_output=True, text=True)


def tag_release(run_dir):
    """Tags a published run's source commit as v<version> and pushes the tag.

    Every target of one version shares the tag. An existing tag on another
    commit is reported and left in place rather than moved.
    """
    state = json.loads((Path(run_dir) / "desktop-release-state.json").read_text())
    if state.get("status") != "published":
        sys.exit(f"Not tagging: {run_dir} is {state.get('status')!r}, not published")
    tag = f"v{state['version']}"
    commit = state["source_commit"]
    existing = git("rev-parse", "--verify", "--quiet", f"refs/tags/{tag}^{{commit}}", check=False)
    if existing.returncode != 0:
        git("tag", "-a", tag, commit, "-m", f"SkillDeck {state['version']} ({state['build_number']})")
    elif existing.stdout.strip() != commit:
        sys.exit(f"Tag {tag} already points at {existing.stdout.strip()[:12]}, "
                 f"not this run's {commit[:12]}; left unchanged")
    pushed = git("push", "origin", f"refs/tags/{tag}", check=False)
    if pushed.returncode != 0:
        sys.exit(f"Tagged {tag} locally but the push failed; retry with "
                 f"`python3 tool/release.py tag --run-dir {run_dir}`")
    print(f"tag={tag} commit={commit}", flush=True)


def published_run(args):
    """The run a successful publishing command just published, if any."""
    if run_dir := option(args, "--run-dir"):
        return Path(run_dir)
    runs = sorted(
        (root / "dist").glob(
            f"desktop-release-{option(args, '--version')}-{option(args, '--build-number')}"
            f"-{option(args, '--target')}-*"
        ),
        key=lambda path: path.stat().st_mtime,
    )
    return runs[-1] if runs else None


args = sys.argv[1:]
if args and args[0] == "tag":
    if not (run_dir := option(args, "--run-dir")):
        sys.exit("Usage: tool/release.py tag --run-dir <published run>")
    tag_release(run_dir)
    sys.exit(0)

# Resolve configuration before touching machine-local automation or private inputs.
# Help remains the backend's responsibility, including subcommand help.
if args and args[0] in ("plan", "prepare") and not any(
    arg in ("-h", "--help") for arg in args
):
    explicit_config = False
    for index, arg in enumerate(args):
        if arg == "--config":
            if index + 1 == len(args) or args[index + 1].startswith("-"):
                sys.exit("--config requires a file path")
            explicit_config = True
        elif arg.startswith("--config="):
            if not arg.split("=", 1)[1]:
                sys.exit("--config requires a file path")
            explicit_config = True
    if not explicit_config:
        args += ["--config", str(root / "keys/desktop-release.json")]
    if not Path(option(args, "--config")).is_file():
        sys.exit("Release configuration missing; configure keys/desktop-release.json "
                 "or pass --config <path>; see release/README.md")

local = root / "keys/release-tools.json"
settings = json.loads(local.read_text()) if local.exists() else {}
skill = os.environ.get("MACOS_RELEASE_SKILL") or settings.get("skill_root")
if not skill:
    sys.exit("Set MACOS_RELEASE_SKILL or keys/release-tools.json with skill_root once; see release/README.md")
entry = Path(skill).expanduser().resolve() / "scripts/release_desktop.py"
if not entry.is_file():
    sys.exit(f"Release automation missing: {entry}")
command = [sys.executable, str(entry), *args]
publishing = args and (args[0] in ("publish", "resume") or (args[0] == "prepare" and "--publish" in args))
if not publishing:
    os.execv(sys.executable, command)
code = subprocess.call(command)
if code != 0:
    sys.exit(code)
# Only a published run is tagged; resuming a prepare-only run stays untagged.
run = published_run(args)
if run is not None:
    state = json.loads((run / "desktop-release-state.json").read_text())
    if state.get("status") == "published":
        tag_release(run)
