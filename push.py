#!/usr/bin/env python3
"""
Publish the staged STD Hub repo to GitHub and verify the raw URL a loadstring
will actually hit.

One command, no gh CLI, no interactive auth:

    python push.py --token ghp_xxx

What it does, in order:

  1. GET /user                      proves the token works and names the owner
  2. POST /user/repos               creates the repo, or accepts 422 as "already
                                    there" so re-running after a fix is safe
  3. git init / commit / push       one commit, forced, because the repo is a
                                    build artifact and history adds nothing
  4. GET the raw URL                the only check that matters: does the URL a
                                    client will fetch return the bytes we pushed

Nothing here is destructive outside its own repo: it never deletes a repo, never
touches a branch it did not create, and refuses to run if the staged hub is
missing.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://api.github.com"


def die(msg):
    print("ERROR: " + msg)
    sys.exit(1)


def api(path, token, method="GET", payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "std-hub-publisher")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            body = json.loads(body)
        except Exception:
            pass
        return e.code, body


def http_get(url, token=None):
    req = urllib.request.Request(url)
    req.add_header("User-Agent", "std-hub-publisher")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def stamp(owner, repo):
    """
    Rewrite the placeholder owner and the build date into the two files that
    carry them, so the repo is self-consistent: STD_Loader.luau must fetch from
    the repo it is published in, and the autoexec bootstrap must fetch the loader
    from that same repo. Done here rather than by hand because a mismatch is
    invisible until a client is sitting on a dead URL.
    """
    today = __import__("datetime").date.today().isoformat()
    targets = [
        os.path.join(HERE, "STD_Loader.luau"),
        os.path.join(HERE, "autoexec", "STD_Hub.luau"),
    ]
    for path in targets:
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
        out = src.replace("OWNER/STD-Hub", f"{owner}/{repo}")
        # the build stamp is the push date. it separates the executor's own http
        # cache only - raw.githubusercontent's CDN keys on the path and ignores
        # the query string, so it still serves the old build for five minutes
        # after a push (max-age=300, measured)
        for line in src.splitlines():
            if line.startswith("local BUILD = "):
                old = line.split('"')[1]
                out = out.replace(f'local BUILD = "{old}"', f'local BUILD = "{today}"')
        if out != src:
            with open(path, "w", encoding="utf-8") as f:
                f.write(out)
            print(f"stamped {os.path.relpath(path, HERE)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"),
                    help="GitHub PAT with repo scope; falls back to $GITHUB_TOKEN "
                         "so the secret stays out of argv")
    ap.add_argument("--repo", default="STD-Hub")
    ap.add_argument("--owner", default=None, help="defaults to the token's user")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--private", action="store_true",
                    help="private repos cannot be fetched by raw URL without auth")
    args = ap.parse_args()
    if not args.token:
        die("no token: pass --token or set GITHUB_TOKEN")

    hub = os.path.join(HERE, "STD_Hub.luau")
    if not os.path.isfile(hub):
        die("STD_Hub.luau is not in " + HERE)
    size = os.path.getsize(hub)
    if size < 100_000:
        die(f"STD_Hub.luau is only {size} bytes - that is not the hub")

    print(f"staged hub: {size/1024:.0f} KB")

    status, me = api("/user", args.token)
    if status != 200:
        die(f"the token was rejected ({status}): {me}")
    owner = args.owner or me["login"]
    print(f"token belongs to: {me['login']}")

    status, body = api(f"/repos/{owner}/{args.repo}", args.token)
    if status == 200:
        print(f"repo exists: {body['full_name']} ({'private' if body['private'] else 'public'})")
    elif status == 404:
        status, body = api("/user/repos", args.token, "POST", {
            "name": args.repo,
            "description": "STD Hub - Sorcerer Tower Defense multi-box hub",
            "private": bool(args.private),
            "has_issues": False,
            "has_wiki": False,
        })
        if status not in (200, 201):
            die(f"could not create the repo ({status}): {body}")
        print(f"repo created: {body['full_name']}")
    else:
        die(f"could not look up the repo ({status}): {body}")

    print("pushing...")
    stamp(owner, args.repo)
    git = ["git", "-C", HERE]
    subprocess.run(git + ["init", "-b", args.branch], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # the machine's global config has core.autocrlf=true. left alone it rewrites
    # every LF in a 430KB file into CRLF on the way into the index, the raw bytes
    # stop matching the local bytes, and the md5 check below fails on a push that
    # actually worked. .gitattributes pins it too; this is belt and braces
    subprocess.run(git + ["config", "core.autocrlf", "false"], check=True)
    subprocess.run(git + ["config", "core.safecrlf", "false"], check=True)
    subprocess.run(git + ["add", "-A"], check=True)
    # identity is set per-command so the machine's global config is left alone
    subprocess.run(git + [
        "-c", "user.name=std-hub", "-c", "user.email=std-hub@users.noreply.github.com",
        "commit", "-m", "hub build", "--allow-empty", "-q",
    ], check=True)
    push_url = f"https://x-access-token:{args.token}@github.com/{owner}/{args.repo}.git"
    r = subprocess.run(git + ["push", "-f", push_url, f"HEAD:{args.branch}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        die("push failed:\n" + (r.stderr or r.stdout))
    # the token must not stay in .git/config
    subprocess.run(git + ["remote", "remove", "origin"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(git + ["remote", "add", "origin",
                          f"https://github.com/{owner}/{args.repo}.git"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    raw = f"https://raw.githubusercontent.com/{owner}/{args.repo}/{args.branch}/STD_Hub.luau"
    print("verifying the raw URL...")
    status, data = http_get(raw)
    if status != 200:
        die(f"the raw URL answered {status} - the repo is probably private, "
            f"and raw.githubusercontent does not serve private files to a loadstring")
    local_md5 = hashlib.md5(open(hub, "rb").read()).hexdigest()
    remote_md5 = hashlib.md5(data).hexdigest()
    print(f"  local  {local_md5}  {len(open(hub,'rb').read())/1024:.0f} KB")
    print(f"  remote {remote_md5}  {len(data)/1024:.0f} KB")
    if local_md5 != remote_md5:
        die("the bytes on GitHub are not the bytes on disk - a push raced a write")

    loader = f"https://raw.githubusercontent.com/{owner}/{args.repo}/{args.branch}/STD_Loader.luau"
    print()
    print("=" * 72)
    print("LOADSTRING (fetch the loader, which fetches the hub):")
    print(f'loadstring(game:HttpGet("{loader}"))()')
    print()
    print("AUTOEXEC (the only file that belongs in the executor's autoexec folder):")
    print(f'loadstring(game:HttpGet("{loader}"))()')
    print()
    print(f"raw hub: {raw}")
    print("=" * 72)


if __name__ == "__main__":
    main()
