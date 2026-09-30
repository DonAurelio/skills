#!/usr/bin/env python3
"""Analyze a RecordFunction/LTTng trace into the granularity metrics this project
reports. Input is a babeltrace2 TEXT dump (a traces/*.txt file) OR a raw CTF trace
dir (auto-converted via `babeltrace2` if it's a directory).

    analyze.py <trace.txt | trace-dir> [--json]
    analyze.py --compare <global.txt> <local.txt>   # thread-reach coverage gap

What it computes (the numbers that go into a stage README):
  * total events, entry/exit balance (per vtid + overall)  -- correctness
  * distinct vtids, per-vtid entry count + max nesting depth -- thread granularity
  * scope mix (FUNCTION vs BACKWARD_FUNCTION ...)            -- scope granularity
  * backward-thread detection: which vtid(s) carry *Backward0 / autograd::engine
  * top ops by frequency                                     -- op identity
  * device args: counts of @<device> seen in rendered inputs -- device granularity
  * --compare: events(global) vs events(local) and the % a thread-local run misses

Pure stdlib + one optional `babeltrace2` call. No torch, runs anywhere.
"""
import os
import re
import sys
import json
import subprocess
from collections import Counter, defaultdict

# babeltrace2 line: ... op_entry: {..}, { vpid = N, vtid = M }, { name = "..",
#                    scope = "..", depth = D, args = ".." }
RE_EVENT = re.compile(r'lttng_ust_pytorch:(op_entry|op_exit)')
RE_VTID  = re.compile(r'vtid = (\d+)')
RE_NAME  = re.compile(r'name = "([^"]*)"')
RE_SCOPE = re.compile(r'scope = "([^"]*)"')
RE_DEPTH = re.compile(r'depth = (\d+)')
RE_ARGS  = re.compile(r'args = "([^"]*)"')
RE_DEV   = re.compile(r'@([a-zA-Z]+(?::\d+)?)')
# backward markers: autograd nodes end in "Backward0", plus engine/accumulate.
RE_BWD   = re.compile(r'Backward\d*$|autograd::engine|AccumulateGrad')


def load_lines(path):
    """Return the babeltrace2 text lines for a .txt dump or a CTF trace dir."""
    if os.path.isdir(path):
        out = subprocess.run(["babeltrace2", path], capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit(f"babeltrace2 failed on {path}:\n{out.stderr}")
        return out.stdout.splitlines()
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read().splitlines()


def analyze(path):
    lines = load_lines(path)
    per_vtid = defaultdict(lambda: {"entry": 0, "exit": 0, "maxdepth": 0,
                                    "bwd": 0})
    names = Counter()
    scopes = Counter()
    devices = Counter()
    bwd_vtids = set()
    total_entry = total_exit = 0

    for ln in lines:
        m = RE_EVENT.search(ln)
        if not m:
            continue
        kind = m.group(1)
        vt = RE_VTID.search(ln)
        vtid = vt.group(1) if vt else "?"
        rec = per_vtid[vtid]
        if kind == "op_entry":
            rec["entry"] += 1
            total_entry += 1
            nm = RE_NAME.search(ln)
            name = nm.group(1) if nm else "?"
            names[name] += 1
            sc = RE_SCOPE.search(ln)
            if sc:
                scopes[sc.group(1)] += 1
            dp = RE_DEPTH.search(ln)
            if dp:
                rec["maxdepth"] = max(rec["maxdepth"], int(dp.group(1)))
            ar = RE_ARGS.search(ln)
            if ar:
                for dev in RE_DEV.findall(ar.group(1)):
                    devices[dev] += 1
            if RE_BWD.search(name):
                rec["bwd"] += 1
                bwd_vtids.add(vtid)
        else:
            rec["exit"] += 1
            total_exit += 1

    return {
        "path": path,
        "total_events": total_entry + total_exit,
        "total_entry": total_entry,
        "total_exit": total_exit,
        "balanced": total_entry == total_exit,
        "vtids": {v: r for v, r in sorted(per_vtid.items())},
        "vtid_count": len(per_vtid),
        "scopes": dict(scopes.most_common()),
        "top_ops": names.most_common(15),
        "devices": dict(devices.most_common()),
        "backward_vtids": sorted(bwd_vtids),
    }


def print_report(a):
    print(f"=== trace analysis: {a['path']} ===")
    print(f"events: {a['total_events']}  ({a['total_entry']} entry / "
          f"{a['total_exit']} exit)  balanced={a['balanced']}")
    print(f"vtids: {a['vtid_count']}")
    for v, r in a["vtids"].items():
        bal = "OK" if r["entry"] == r["exit"] else "!! UNBALANCED"
        tag = f"  bwd={r['bwd']}" if r["bwd"] else ""
        print(f"  vtid {v}: entry={r['entry']} exit={r['exit']} "
              f"maxdepth={r['maxdepth']}{tag}  [{bal}]")
    if a["backward_vtids"]:
        print(f"backward runs on vtid(s): {', '.join(a['backward_vtids'])}"
              + ("  <- dedicated autograd thread (not inline)"
                 if len(a["vtids"]) > 1 else "  <- inline on the only thread"))
    print(f"scopes: {a['scopes']}")
    if a["devices"]:
        print(f"devices in args: {a['devices']}")
    print("top ops:")
    for name, c in a["top_ops"]:
        print(f"  {c:6d}  {name}")


def compare(gpath, lpath):
    g = analyze(gpath)
    l = analyze(lpath)
    gt, lt = g["total_events"], l["total_events"]
    pct = (lt / gt * 100) if gt else 0.0
    print("=== thread-reach comparison (global vs thread-local) ===")
    print(f"global ({gpath}): {gt} events, {g['vtid_count']} vtids")
    print(f"local  ({lpath}): {lt} events, {l['vtid_count']} vtids")
    print(f"thread-local captured {lt}/{gt} = {pct:.1f}%  "
          f"(missed {100 - pct:.1f}%)")
    if g["backward_vtids"] and not (set(l["vtids"]) & set(g["backward_vtids"])):
        print("thread-local MISSED the backward/autograd thread(s): "
              f"{', '.join(g['backward_vtids'])}")
    return {"global": g, "local": l, "capture_pct": pct}


def main(argv):
    want_json = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    if len(argv) >= 3 and argv[0] == "--compare":
        res = compare(argv[1], argv[2])
        if want_json:
            print(json.dumps(res, indent=2))
        return
    if len(argv) != 1:
        sys.exit(__doc__)
    a = analyze(argv[0])
    if want_json:
        print(json.dumps(a, indent=2))
    else:
        print_report(a)


if __name__ == "__main__":
    main(sys.argv[1:])
