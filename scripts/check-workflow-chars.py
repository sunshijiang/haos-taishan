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


def check_secrets_in_if(path):
    """The secrets context is not available in an `if` condition.

    GitHub rejects a workflow that compares a secret directly in an `if`,
    for example `if: ${{ secrets.NTFY_TOPIC != '' }}`. Expose the secret
    through the job environment first and test `env.NAME` instead.
    """
    problems = []
    with open(path, encoding="utf-8") as fh:
        for number, line in enumerate(fh, 1):
            stripped = line.strip()
            if not stripped.startswith("if:"):
                continue
            if "secrets." not in stripped:
                continue
            problems.append(
                f"{path}:{number}: the secrets context is not available in an "
                f"if condition ({stripped[:60]})"
            )
    return problems


def check_script_backticks(path):
    """A Markdown code fence breaks a github-script body.

    The body of `actions/github-script` is JavaScript. A code fence written
    as ``` inside a template literal terminates it early, and the step fails
    with "SyntaxError: Unexpected identifier". Every backtick in the body
    has to be escaped as \\`.

    A single backtick is what opens and closes a template literal, so it is
    fine on its own. A run of three or more is a code fence, and that is
    what breaks the step.
    """
    problems = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")

    inside = False
    for number, line in enumerate(lines, 1):
        if not inside:
            if "script: |" in line:
                inside = True
            continue
        # A block scalar ends at the first line that is not indented enough.
        if line.strip() and not line.startswith("            "):
            inside = False
            continue

        bare = line.replace("\\`", "")
        if "`" * 3 in bare:
            problems.append(
                f"{path}:{number}: a code fence breaks the github-script "
                f"body, escape the backticks as \\` ({line.strip()[:60]})"
            )
    return problems


def check_script_calls(path):
    """Do not run a shell script through ./script.sh.

    Git does not record the executable bit on Windows, so a script committed
    from Windows arrives without it and fails with "Permission denied".
    Call it through bash instead.

    Only the run steps count. A mention inside a github-script body is
    documentation for a human, not something that gets executed.
    """
    problems = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")

    inside_script = False
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("script: |"):
            inside_script = True
            continue
        if inside_script:
            if stripped and not line.startswith("            "):
                inside_script = False
            else:
                continue
        if stripped.startswith("#"):
            continue
        if stripped.startswith("./scripts/") or stripped.startswith("./script"):
            problems.append(
                f"{path}:{number}: run the script through bash, it has no "
                f"executable bit ({stripped[:60]})"
            )
    return problems


def main():
    failures = []
    for path in sorted(glob.glob(".github/workflows/*.yml") +
                       glob.glob(".github/workflows/*.yaml")):
        failures.extend(check_non_ascii(path))
        failures.extend(check_colons(path))
        failures.extend(check_secrets_in_if(path))
        failures.extend(check_script_backticks(path))
        failures.extend(check_script_calls(path))

    if failures:
        print("Workflow files contain constructs that GitHub rejects:")
        for failure in failures:
            print(f"  {failure}")
        print()
        print("Fix them like this:")
        print("  em dash (U+2014)          ->  -")
        print("  curly quotes              ->  ' or \"")
        print("  a colon in a name value   ->  drop it or quote the value")
        print("  secrets in an if          ->  set an env variable and test env.NAME")
        print("  a backtick in a script    ->  escape it as \\`")
        print("  ./script.sh               ->  bash script.sh")
        return 1

    print("All workflow files pass the GitHub compatibility checks.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
