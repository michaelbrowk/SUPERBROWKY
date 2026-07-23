#!/usr/bin/env python3
"""Validate the bundled Agent Skills packages using only the Python stdlib."""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit


NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
MARKDOWN_LINK_RE = re.compile(
    r"!?\[[^\]]*\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+['\"][^)]*['\"])?\s*\)"
)
HEADING_RE = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$")
ABSOLUTE_USER_PATH_RE = re.compile(r"(?<![A-Za-z0-9_])/Users/[^\s`'\")\]}>,]+")
TEXT_SUFFIXES = {
    ".md",
    ".markdown",
    ".mjs",
    ".js",
    ".cjs",
    ".ts",
    ".tsx",
    ".json",
    ".yaml",
    ".yml",
    ".txt",
}
FRONTMATTER_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def validate_scalar_syntax(
    path: Path, line_number: int, raw_value: str, errors: list[str]
) -> str:
    value = raw_value.strip()
    if not value:
        return "nested"
    if value.startswith(("|", ">")):
        errors.append(
            f"{path}:{line_number}: block scalars are outside the portable "
            "frontmatter subset; use one quoted line"
        )
        return "none"
    if value.startswith('"'):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            errors.append(
                f"{path}:{line_number}: malformed double-quoted scalar"
            )
            return "none"
        if not isinstance(parsed, str):
            errors.append(
                f"{path}:{line_number}: quoted scalar must decode to text"
            )
        return "none"
    if value.startswith("'"):
        if len(value) < 2 or not value.endswith("'"):
            errors.append(
                f"{path}:{line_number}: malformed single-quoted scalar"
            )
            return "none"
        inner = value[1:-1]
        if "'" in inner.replace("''", ""):
            errors.append(
                f"{path}:{line_number}: single quotes must be doubled"
            )
        return "none"
    if value.startswith(("[", "{")):
        errors.append(
            f"{path}:{line_number}: flow collections are outside the portable "
            "frontmatter subset; use an indented mapping/list"
        )
        return "none"
    if value.startswith(("]", "}")):
        errors.append(f"{path}:{line_number}: malformed flow collection")
    if value.startswith(("#", "&", "*", "!", "%", "@", "`")) or re.match(
        r"^(?:-\s|\?\s|:\s)", value
    ):
        errors.append(
            f"{path}:{line_number}: unsupported YAML indicator in plain scalar"
        )
    if re.search(r":(?:\s|$)", value):
        errors.append(
            f"{path}:{line_number}: plain scalars containing ': ' must be quoted"
        )
    if "\x00" in value or value.startswith(("@", "`")):
        errors.append(f"{path}:{line_number}: unsupported plain scalar")
    return "none"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repo",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root (defaults to the parent of scripts/)",
    )
    parser.add_argument(
        "--skills-dir",
        type=Path,
        help="validate this skill-directory root instead of <repo>/skills",
    )
    return parser.parse_args()


def read_text(path: Path, errors: list[str]) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        errors.append(f"{path}: file is not valid UTF-8")
    except OSError as exc:
        errors.append(f"{path}: cannot read file: {exc}")
    return None


def parse_frontmatter(path: Path, text: str, errors: list[str]) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        errors.append(f"{path}: missing opening YAML frontmatter delimiter")
        return {}

    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        errors.append(f"{path}: missing closing YAML frontmatter delimiter")
        return {}

    values: dict[str, str] = {}
    parent_mode = "none"
    i = 1
    while i < end:
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if "\t" in line[: len(line) - len(line.lstrip())]:
            errors.append(f"{path}:{i + 1}: tabs are not valid YAML indentation")
        # Agent Skills metadata may use nested mappings/lists. Support a strict
        # portable subset and validate their scalar syntax even though only
        # top-level name/description are consumed below.
        if line[:1].isspace():
            if parent_mode == "none":
                errors.append(
                    f"{path}:{i + 1}: unexpected indented frontmatter line"
                )
            elif parent_mode == "nested":
                indent = len(line) - len(line.lstrip(" "))
                if indent != 2:
                    errors.append(
                        f"{path}:{i + 1}: nested metadata must use exactly "
                        "two spaces in the portable subset"
                    )
                nested = line.strip()
                if nested.startswith("-"):
                    item = nested[1:].strip()
                    if not item:
                        errors.append(
                            f"{path}:{i + 1}: empty list item is unsupported"
                        )
                    elif ":" in item and FRONTMATTER_KEY_RE.fullmatch(
                        item.split(":", 1)[0].strip()
                    ):
                        validate_scalar_syntax(
                            path, i + 1, item.split(":", 1)[1], errors
                        )
                    else:
                        validate_scalar_syntax(path, i + 1, item, errors)
                elif ":" in nested:
                    nested_key, nested_value = nested.split(":", 1)
                    if not FRONTMATTER_KEY_RE.fullmatch(nested_key.strip()):
                        errors.append(
                            f"{path}:{i + 1}: unsupported nested key syntax"
                        )
                    validate_scalar_syntax(
                        path, i + 1, nested_value, errors
                    )
                else:
                    errors.append(
                        f"{path}:{i + 1}: unsupported nested frontmatter syntax"
                    )
            i += 1
            continue
        if ":" not in line:
            errors.append(f"{path}:{i + 1}: unsupported frontmatter syntax")
            i += 1
            continue

        key, raw_value = line.split(":", 1)
        key = key.strip()
        raw_value = raw_value.strip()
        if not FRONTMATTER_KEY_RE.fullmatch(key):
            errors.append(f"{path}:{i + 1}: unsupported frontmatter key {key!r}")
        if key in values:
            errors.append(f"{path}:{i + 1}: duplicate frontmatter key {key!r}")

        parent_mode = validate_scalar_syntax(path, i + 1, raw_value, errors)
        if (
            len(raw_value) >= 2
            and raw_value[0] == raw_value[-1]
            and raw_value[0] in {'"', "'"}
        ):
            raw_value = raw_value[1:-1]
        values[key] = raw_value.strip()
        i += 1

    return values


def validate_frontmatter(skill_md: Path, text: str, errors: list[str]) -> None:
    frontmatter = parse_frontmatter(skill_md, text, errors)
    name = frontmatter.get("name", "")
    description = frontmatter.get("description", "")
    directory_name = skill_md.parent.name

    if not name:
        errors.append(f"{skill_md}: frontmatter 'name' is required")
    else:
        if len(name) > 64 or not NAME_RE.fullmatch(name):
            errors.append(
                f"{skill_md}: name must be <=64 chars of lowercase letters, "
                "digits, and single hyphens"
            )
        if name != directory_name:
            errors.append(
                f"{skill_md}: frontmatter name {name!r} does not match "
                f"directory {directory_name!r}"
            )

    if not description:
        errors.append(f"{skill_md}: frontmatter 'description' is required")
    elif len(description) > 1024:
        errors.append(f"{skill_md}: description exceeds 1024 characters")


def github_anchor(text: str) -> str:
    text = html.unescape(text).strip().lower()
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"[`*_~]", "", text)
    text = "".join(
        char
        for char in text
        if char in {"-", "_", " "}
        or not unicodedata.category(char).startswith(("P", "S"))
    )
    return re.sub(r"\s+", "-", text).strip("-")


def markdown_anchors(path: Path, text: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    in_fence = False
    fence_marker = ""

    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith(("```", "~~~")):
            marker = stripped[:3]
            if not in_fence:
                in_fence = True
                fence_marker = marker
            elif marker == fence_marker:
                in_fence = False
                fence_marker = ""
            continue
        if in_fence:
            continue

        match = HEADING_RE.match(line)
        if not match:
            continue
        base = github_anchor(match.group(1))
        if not base:
            continue
        duplicate_index = counts.get(base, 0)
        counts[base] = duplicate_index + 1
        anchor = base if duplicate_index == 0 else f"{base}-{duplicate_index}"
        anchors.add(anchor)

    return anchors


def validate_markdown_links(
    path: Path,
    text: str,
    errors: list[str],
    text_cache: dict[Path, str],
    anchor_cache: dict[Path, set[str]],
) -> None:
    for match in MARKDOWN_LINK_RE.finditer(text):
        target = (match.group(1) or match.group(2) or "").strip()
        if not target:
            continue

        parsed = urlsplit(target)
        if parsed.scheme or target.startswith("//"):
            continue
        if parsed.path.startswith("/"):
            continue

        target_path = path if not parsed.path else path.parent / unquote(parsed.path)
        target_path = target_path.resolve()
        if not target_path.exists():
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"{path}:{line}: broken relative link {target!r}")
            continue

        if not parsed.fragment or not target_path.is_file():
            continue
        if target_path.suffix.lower() not in {".md", ".markdown"}:
            continue

        target_text = text_cache.get(target_path)
        if target_text is None:
            target_text = read_text(target_path, errors)
            if target_text is None:
                continue
            text_cache[target_path] = target_text

        anchors = anchor_cache.get(target_path)
        if anchors is None:
            anchors = markdown_anchors(target_path, target_text)
            anchor_cache[target_path] = anchors
        fragment = unquote(parsed.fragment)
        if fragment not in anchors:
            line = text.count("\n", 0, match.start()) + 1
            errors.append(
                f"{path}:{line}: missing Markdown anchor "
                f"{fragment!r} in {target_path}"
            )


def validate_absolute_user_paths(path: Path, text: str, errors: list[str]) -> None:
    for match in ABSOLUTE_USER_PATH_RE.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        errors.append(
            f"{path}:{line}: non-portable absolute user path {match.group(0)!r}"
        )


def main() -> int:
    args = parse_args()
    repo = args.repo.resolve()
    skills_dir = (
        args.skills_dir.resolve()
        if args.skills_dir is not None
        else repo / "skills"
    )
    errors: list[str] = []

    if not skills_dir.is_dir():
        print(f"ERROR: skills directory not found: {skills_dir}", file=sys.stderr)
        return 2

    skill_files = sorted(skills_dir.glob("*/SKILL.md"))
    if not skill_files:
        print(f"ERROR: no bundled skills found in {skills_dir}", file=sys.stderr)
        return 2

    text_cache: dict[Path, str] = {}
    anchor_cache: dict[Path, set[str]] = {}

    symlinks = sorted(path for path in skills_dir.rglob("*") if path.is_symlink())
    for path in symlinks:
        errors.append(
            f"{path}: symlinks are not allowed in portable skill packages"
        )

    for skill_md in skill_files:
        text = read_text(skill_md, errors)
        if text is None:
            continue
        text_cache[skill_md.resolve()] = text
        validate_frontmatter(skill_md, text, errors)

    text_files = sorted(
        path
        for path in skills_dir.rglob("*")
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES
    )
    for path in text_files:
        resolved = path.resolve()
        text = text_cache.get(resolved)
        if text is None:
            text = read_text(path, errors)
            if text is None:
                continue
            text_cache[resolved] = text
        validate_absolute_user_paths(path, text, errors)
        if path.suffix.lower() in {".md", ".markdown"}:
            validate_markdown_links(
                path, text, errors, text_cache, anchor_cache
            )

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(
            f"FAILED: {len(errors)} validation error(s) across "
            f"{len(skill_files)} skill package(s)",
            file=sys.stderr,
        )
        return 1

    print(
        f"OK: validated {len(skill_files)} skill package(s), "
        f"{len(text_files)} text file(s), and all relative Markdown links"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
