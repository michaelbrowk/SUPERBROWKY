#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "validate-skills.py"


def run_case(name: str, frontmatter: str, should_pass: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="superbrowky-yaml-fixture-") as tmp:
        skills = Path(tmp) / "skills"
        package = skills / name
        package.mkdir(parents=True)
        (package / "SKILL.md").write_text(
            f"---\n{frontmatter}\n---\n\n# Fixture\n",
            encoding="utf-8",
        )
        result = subprocess.run(
            [sys.executable, str(VALIDATOR), "--skills-dir", str(skills)],
            capture_output=True,
            text=True,
            check=False,
        )
        if (result.returncode == 0) != should_pass:
            raise AssertionError(
                f"{name}: expected pass={should_pass}, rc={result.returncode}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )


run_case(
    "valid-fixture",
    'name: valid-fixture\ndescription: "A valid fixture"\nmetadata:\n  owner: test',
    True,
)
run_case(
    "broken-quote",
    'name: broken-quote\ndescription: "unterminated',
    False,
)
run_case(
    "broken-flow",
    "name: broken-flow\ndescription: valid\nallowed-tools: [Read, Write",
    False,
)
run_case(
    "broken-indent",
    "name: broken-indent\n description: misplaced",
    False,
)
run_case(
    "inconsistent-nested-indent",
    "name: inconsistent-nested-indent\ndescription: valid\nmetadata:\n    a: x\n  b: y",
    False,
)
run_case(
    "unquoted-colon",
    "name: unquoted-colon\ndescription: Use when: a task needs help",
    False,
)
run_case(
    "comment-as-value",
    "name: comment-as-value\ndescription: # not a string",
    False,
)
run_case(
    "undefined-alias",
    "name: undefined-alias\ndescription: *missing",
    False,
)
run_case(
    "malformed-flow",
    "name: malformed-flow\ndescription: valid\nallowed-tools: [Read,,Write]",
    False,
)
run_case(
    "unsupported-flow",
    "name: unsupported-flow\ndescription: valid\nallowed-tools: [Read, Write]",
    False,
)
run_case(
    "unsupported-block",
    "name: unsupported-block\ndescription: |\n  multiline text",
    False,
)

print("PASS: strict frontmatter subset rejects malformed YAML")
