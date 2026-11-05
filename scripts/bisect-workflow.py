#!/usr/bin/env python3
"""Bisect a workflow file to find the construct GitHub rejects.

Commits a candidate version of a workflow through the API, waits for GitHub
to re-index it, and reports whether GitHub could parse it (the workflow name
appears in the API) or not (the name falls back to the file path).
"""
import base64
import json
import subprocess
import sys
import time
import urllib.request

REPO = "sunshijiang/haos-taishan"
API = f"https://api.github.com/repos/{REPO}"


def token():
    out = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n",
        capture_output=True, text=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    raise SystemExit("no token")


TOKEN = token()


def api(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        API + path, data=data, method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "bisect",
        },
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode())
        except Exception:
            if attempt == 3:
                raise
            time.sleep(8)


def parsed(path):
    """Return True when GitHub parsed the workflow (name != path)."""
    for _ in range(8):
        wfs = api("GET", "/actions/workflows")["workflows"]
        for w in wfs:
            if w["path"] == path:
                return w["name"] != path
        time.sleep(6)
    return None


def commit(path, content, message):
    existing = api("GET", f"/contents/{path}")
    api("PUT", f"/contents/{path}", {
        "message": message,
        "content": base64.b64encode(content).decode(),
        "sha": existing["sha"],
        "branch": "main",
    })


def main():
    wf_path = sys.argv[1]
    candidate_path = sys.argv[2]

    with open(candidate_path, encoding="utf-8") as fh:
        candidate = fh.read()

    commit(wf_path, candidate.encode(), f"bisect: {wf_path}")
    ok = parsed(wf_path)
    print(f"{wf_path}: {'PARSED' if ok else 'REJECTED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
