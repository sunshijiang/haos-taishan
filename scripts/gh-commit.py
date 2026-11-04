#!/usr/bin/env python3
"""Commit a file to the repository through the GitHub API.

Used as a fallback when the git transport is unreliable, and as a probe for
whether GitHub can still parse a workflow file.
"""
import base64
import json
import subprocess
import sys
import urllib.request

REPO = "sunshijiang/haos-taishan"
API = f"https://api.github.com/repos/{REPO}"


def get_token():
    out = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n",
        capture_output=True, text=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    raise SystemExit("no token available")


TOKEN = get_token()


def api(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        API + path, data=data, method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "haos-taishan-tool",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def main():
    path = sys.argv[1]
    message = sys.argv[2]
    content = sys.stdin.buffer.read()

    existing = api("GET", f"/contents/{path}")
    payload = {
        "message": message,
        "content": base64.b64encode(content).decode(),
        "sha": existing["sha"],
        "branch": "main",
    }
    result = api("PUT", f"/contents/{path}", payload)
    print("committed:", result["commit"]["sha"][:12])


if __name__ == "__main__":
    main()
