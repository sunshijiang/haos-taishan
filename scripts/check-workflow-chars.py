#!/usr/bin/env python3
"""Check the workflow files for constructs that GitHub refuses to parse.

Two constructs are rejected by GitHub's workflow parser while a plain YAML
parser accepts them:

1. Non-ASCII characters, an em dash (U+2014) in particular.

2. A colon followed by a space inside an unquoted `name:` value, for example
   `- name: Restore cache: object files`. The colon is read as a key
   separator, which makes the document ambiguous.

Both failures are silent in the usual sense: the workflow keeps an entry in
the API but its name falls back to the file path, and a run created for it
has zero jobs and fails immediately.

Usage:
    scripts/check-workflow-chars.py
"""
import glob
import sys

# Characters that are known to work, but only in comments and in strings.
# To be safe the workflows are kept ASCII only.
ALLOWED_EXTRA = set()


def check_non_ascii(path):
    problems = []
    with open(path, encoding="utf-8") as fh:
        for number, line in enumerate(fh, 1):
            for char in line:
                if ord(char) < 128 or char in ALLOWED_EXTRA:
                    continue
                problems.append(
                    f"{path}:{number}: non-ASCII character "
                    f"U+{ord(char):04X} ({char!r})"
                )
    return problems


def check_colons(path):
    problems = []
    with open(path, encoding="utf-8") as fh:
        for number, line in enumerate(fh, 1):
            stripped = line.strip()
            if not (stripped.startswith("name:") or stripped.startswith("- name:")):
                continue
            value = stripped.split("name:", 1)[1].strip()
            if value.startswith(('"', "'")):
                continue
            if ": " in value:
                problems.append(
                    f"{path}:{number}: a colon in an unquoted name value "
                    f"({stripped[:60]})"
                )
    return problems


def main():
    failures = []
    for path in sorted(glob.glob(".github/workflows/*.yml") +
                       glob.glob(".github/workflows/*.yaml")):
        failures.extend(check_non_ascii(path))
        failures.extend(check_colons(path))

    if failures:
        print("Workflow files contain constructs that GitHub rejects:")
        for failure in failures:
            print(f"  {failure}")
        print()
        print("Fix them like this:")
        print("  em dash (U+2014)          ->  -")
        print("  curly quotes              ->  ' or \"")
        print("  a colon in a name value   ->  drop it or quote the value")
        return 1

    print("All workflow files are ASCII only and free of colons in names.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
