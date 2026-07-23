#!/usr/bin/env python3
"""Validate SUPERBROWKY's shared skill manifest and exact version lock."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
MANIFEST = REPO / "manifests" / "skills.tsv"
LOCK = REPO / "versions.lock"
EXPECTED_HEADER = [
    "name",
    "profiles",
    "source_type",
    "repo",
    "pin_key",
    "claude_upstream_folder",
    "codex_upstream_folder",
    "license",
    "required",
]
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
PROFILES = {"core", "web-launch", "growth", "full"}
FOLDER_SEGMENT_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def safe_source_folder(folder: str) -> bool:
    if folder == ".":
        return True
    if not folder or folder.startswith("/") or "\\" in folder:
        return False
    segments = folder.split("/")
    return all(
        segment not in {"", ".", ".."} and FOLDER_SEGMENT_RE.fullmatch(segment)
        for segment in segments
    )


def load_lock(errors: list[str]) -> dict[str, str]:
    pins: dict[str, str] = {}
    for number, raw in enumerate(LOCK.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            errors.append(f"{LOCK}:{number}: expected key=value")
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key in pins:
            errors.append(f"{LOCK}:{number}: duplicate key {key}")
        if not REPO_RE.fullmatch(key):
            errors.append(f"{LOCK}:{number}: invalid repository key {key!r}")
        if not SHA_RE.fullmatch(value):
            errors.append(f"{LOCK}:{number}: pin must be a lowercase 40-char SHA")
        pins[key] = value
    return pins


def main() -> int:
    errors: list[str] = []
    if not MANIFEST.is_file() or not LOCK.is_file():
        print("ERROR: manifest or versions.lock is missing", file=sys.stderr)
        return 2

    pins = load_lock(errors)
    used_pins: set[str] = set()
    names: set[str] = set()
    profile_counts = {profile: 0 for profile in PROFILES}

    with MANIFEST.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames != EXPECTED_HEADER:
            errors.append(
                f"{MANIFEST}: header must be exactly {EXPECTED_HEADER!r}"
            )
        for number, row in enumerate(reader, 2):
            if None in row:
                errors.append(f"{MANIFEST}:{number}: too many columns")
                continue
            name = (row.get("name") or "").strip()
            profile = (row.get("profiles") or "").strip()
            source_type = (row.get("source_type") or "").strip()
            repo = (row.get("repo") or "").strip()
            pin_key = (row.get("pin_key") or "").strip()
            license_name = (row.get("license") or "").strip()
            required = (row.get("required") or "").strip()
            claude_folder = (row.get("claude_upstream_folder") or "").strip()
            codex_folder = (row.get("codex_upstream_folder") or "").strip()

            if not NAME_RE.fullmatch(name):
                errors.append(f"{MANIFEST}:{number}: invalid skill name {name!r}")
            if name in names:
                errors.append(f"{MANIFEST}:{number}: duplicate skill {name!r}")
            names.add(name)
            if profile not in PROFILES:
                errors.append(f"{MANIFEST}:{number}: invalid profile {profile!r}")
            else:
                profile_counts[profile] += 1
            if required not in {"yes", "no"}:
                errors.append(f"{MANIFEST}:{number}: required must be yes or no")
            if not license_name or license_name == "NOASSERTION":
                errors.append(
                    f"{MANIFEST}:{number}: reviewed license is required for {name}"
                )
            if not claude_folder or not codex_folder:
                errors.append(
                    f"{MANIFEST}:{number}: both harness source folders are required"
                )
            for harness, folder in (
                ("claude", claude_folder),
                ("codex", codex_folder),
            ):
                if not safe_source_folder(folder):
                    errors.append(
                        f"{MANIFEST}:{number}: unsafe {harness} source folder {folder!r}"
                    )

            if source_type == "git":
                if not REPO_RE.fullmatch(repo):
                    errors.append(
                        f"{MANIFEST}:{number}: invalid repository {repo!r}"
                    )
                if pin_key != repo:
                    errors.append(
                        f"{MANIFEST}:{number}: pin_key must equal repository slug"
                    )
                if pin_key not in pins:
                    errors.append(
                        f"{MANIFEST}:{number}: missing lock pin for {pin_key}"
                    )
                used_pins.add(pin_key)
            elif source_type == "bundled":
                if repo != "." or pin_key != "-":
                    errors.append(
                        f"{MANIFEST}:{number}: bundled source must use repo='.' and pin_key='-'"
                    )
                for folder in {claude_folder, codex_folder}:
                    if not (REPO / folder / "SKILL.md").is_file():
                        errors.append(
                            f"{MANIFEST}:{number}: bundled folder lacks SKILL.md: {folder}"
                        )
            else:
                errors.append(
                    f"{MANIFEST}:{number}: source_type must be git or bundled"
                )

    stale = sorted(set(pins) - used_pins)
    if stale:
        errors.append(f"{LOCK}: unused pin(s): {', '.join(stale)}")
    if profile_counts["core"] == 0:
        errors.append(f"{MANIFEST}: core profile is empty")
    for overlay in ("third-party-safety.md", "impeccable-portable.md"):
        if not (REPO / "overlays" / overlay).is_file():
            errors.append(f"overlays/{overlay} is missing")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"FAILED: {len(errors)} manifest error(s)", file=sys.stderr)
        return 1

    print(
        f"OK: {len(names)} skills, {len(pins)} exact pins, "
        f"profiles={','.join(sorted(PROFILES))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
