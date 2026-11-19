#!/usr/bin/env python3
"""
Run the loader fetch simulations.

Each scenario is built the same way: stubs, then STD_Loader.luau verbatim, then
assertions. Concatenating instead of importing keeps what runs identical to what
ships - there is no copy of the loader to drift out of date.

    python sim/run.py
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LUAU = os.environ.get(
    "LUAU_BIN",
    r"C:/Users/0/Desktop/Deobfuscator-Luraph-V15-master/bin/luau.exe",
)

SCENARIOS = {
    1: "first source works",
    2: "first source rate-limited, mirror carries it",
    3: "every source dead, cache on disk",
    4: "every source dead, nothing on disk",
    5: "captive portal HTML",
    6: "every source serves the old 56KB ancestor",
}


def build(n):
    head = open(os.path.join(HERE, "sim_loader_head.luau"), encoding="utf-8").read()
    body = open(os.path.join(REPO, "STD_Loader.luau"), encoding="utf-8").read()
    tail = open(os.path.join(HERE, "sim_loader_tail.luau"), encoding="utf-8").read()
    out = os.path.join(HERE, f"_run_{n}.luau")
    with open(out, "w", encoding="utf-8") as f:
        f.write(head.replace("__SCENARIO__", str(n)))
        f.write("\n" + body + "\n")
        f.write(tail)
    return out


def main():
    if not os.path.isfile(LUAU):
        sys.exit(f"no luau binary at {LUAU} - set LUAU_BIN")
    total_p = total_f = 0
    bad = []
    for n, label in SCENARIOS.items():
        path = build(n)
        r = subprocess.run([LUAU, path], capture_output=True, text=True)
        out = (r.stdout or "") + (r.stderr or "")
        m = re.search(r"(\d+) passed, (\d+) failed", out)
        p, f = (int(m.group(1)), int(m.group(2))) if m else (0, 1)
        total_p += p
        total_f += f
        if f:
            bad.append(n)
            print(f"scenario {n}  {label}: {p} passed, {f} FAILED")
            for line in out.splitlines():
                if "FAIL" in line:
                    print("    " + line.strip())
        else:
            print(f"scenario {n}  {label}: {p} passed")
    print(f"\n{total_p} assertions, {total_f} failures")
    if bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
