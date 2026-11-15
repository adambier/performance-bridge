#!/usr/bin/env python3
"""Read-only. List the parameters each installed Arturia VST3 gives a host -> <out>/<plugin>.json.
<out> is the folder "arturia-params" beside this script's folder, or the ARTURIA_PARAMS_OUT environment variable.
No audio, no windows. Each plugin loads in its own process, so one that hangs or crashes is skipped.
Each file records the plugin's version (from the bundle's Info.plist) and the date; INDEX.tsv lists them all.
Usage: arturia_params.py              load every plugin again (about 3 s each)
       arturia_params.py --stamp      only add versions to the files already there, and write INDEX.tsv (instant)
       arturia_params.py --tsv <dir>  write the short lists (name, value as loaded, values it can take) from the files there
       arturia_params.py --one "<path.vst3>" <out.json>   (internal)
Needs Pedalboard (pip install pedalboard). macOS paths."""
import datetime, json, os, plistlib, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("ARTURIA_PARAMS_OUT") or os.path.join(os.path.dirname(HERE), "arturia-params")
VST3 = "/Library/Audio/Plug-Ins/VST3"
LIB = "/Library/Arturia"

def version(path):
    try:
        with open(os.path.join(path, "Contents", "Info.plist"), "rb") as f: d = plistlib.load(f)
        return d.get("CFBundleShortVersionString") or d.get("CFBundleVersion") or "?"
    except Exception:
        return "?"

def index():
    rows = []
    for f in sorted(os.listdir(OUT)):
        if not f.endswith(".json"): continue
        d = json.load(open(os.path.join(OUT, f)))
        rows.append((f[:-5], d.get("version", "?"), str(len(d["parameters"])), d.get("surveyed", "?"), d.get("pedalboard", "?")))
    with open(os.path.join(OUT, "INDEX.tsv"), "w") as f:
        f.write("plugin\tversion\tparameters\tsurveyed\tpedalboard\n")
        for r in rows: f.write("\t".join(r) + "\n")
    print(f"INDEX.tsv: {len(rows)} plugins")

def tsv(dest):
    os.makedirs(dest, exist_ok=True)
    clean = lambda s: str(s).replace("\t", " ").replace("\n", " ")
    for f in sorted(os.listdir(OUT)):
        if not f.endswith(".json"): continue
        d = json.load(open(os.path.join(OUT, f)))
        with open(os.path.join(dest, f[:-5] + ".tsv"), "w") as o:
            o.write(f"# {f[:-5]} {d.get('version', '?')} (VST3), read {d.get('surveyed', '?')}\n")
            o.write("parameter\tvalue as loaded\tvalues it can take\n")
            for r in d["parameters"]:
                vv = r.get("valid_values") or []
                row = [clean(r.get("name", r["key"])), clean(r.get("string_value", "")),
                       " | ".join(map(clean, vv)) if len(vv) <= 30 else ""]
                o.write("\t".join(row).rstrip() + "\n")  # no tab left hanging where there is no list
    index()
    with open(os.path.join(OUT, "INDEX.tsv")) as a, open(os.path.join(dest, "INDEX.tsv"), "w") as b: b.write(a.read())
    print(f"short lists written to {dest}")

def one(path, dest):
    from pedalboard import load_plugin
    t = time.time(); p = load_plugin(path); rows = []
    for key, prm in p.parameters.items():
        r = {"key": key}
        for a in ("name", "string_value", "raw_value", "is_discrete", "is_boolean", "num_steps", "label"):
            try:
                v = getattr(prm, a)
                r[a] = v if isinstance(v, (int, float, str, bool, type(None))) else str(v)
            except Exception:
                pass
        try:
            vv = prm.valid_values
            if vv is not None and len(vv) <= 60: r["valid_values"] = [str(x) for x in vv]
        except Exception:
            pass
        rows.append(r)
    import pedalboard
    json.dump({"plugin": path, "version": version(path), "surveyed": datetime.date.today().isoformat(),
               "pedalboard": getattr(pedalboard, "__version__", "?"), "format": "VST3",
               "load_s": round(time.time() - t, 2), "parameters": rows}, open(dest, "w"), indent=1)

if len(sys.argv) == 4 and sys.argv[1] == "--one":
    one(sys.argv[2], sys.argv[3]); sys.exit(0)

os.makedirs(OUT, exist_ok=True)
if len(sys.argv) == 3 and sys.argv[1] == "--tsv":
    tsv(sys.argv[2]); sys.exit(0)
if len(sys.argv) == 2 and sys.argv[1] == "--stamp":
    try:
        import pedalboard; pb = getattr(pedalboard, "__version__", "?")
    except Exception:
        pb = "?"
    for f in sorted(os.listdir(OUT)):
        if not f.endswith(".json"): continue
        q = os.path.join(OUT, f); d = json.load(open(q))
        day = datetime.date.fromtimestamp(os.path.getmtime(q)).isoformat()
        new = {"plugin": d["plugin"], "version": version(d["plugin"]), "surveyed": d.get("surveyed", day),
               "pedalboard": d.get("pedalboard", pb), "format": "VST3", "load_s": d.get("load_s"), "parameters": d["parameters"]}
        json.dump(new, open(q, "w"), indent=1)
    index(); sys.exit(0)
names = sorted(os.listdir(LIB)) if os.path.isdir(LIB) else []
found = [n for n in names if os.path.exists(os.path.join(VST3, n + ".vst3"))]
print(f"{len(found)} Arturia plugins found as VST3; no VST3 for: {', '.join(n for n in names if n not in found) or 'none'}")
ok = 0
for n in found:
    dest = os.path.join(OUT, n + ".json")
    try:
        r = subprocess.run([sys.executable, os.path.abspath(__file__), "--one", os.path.join(VST3, n + ".vst3"), dest],
                           capture_output=True, text=True, timeout=120)
        if r.returncode == 0:
            k = len(json.load(open(dest))["parameters"]); ok += 1
            print(f"  {n}: {k} parameters")
        else:
            print(f"  {n}: FAILED ({(r.stderr.strip().splitlines() or ['no message'])[-1][:120]})")
    except subprocess.TimeoutExpired:
        print(f"  {n}: SKIPPED (over 120 s)")
print(f"done: {ok} of {len(found)} saved in {OUT}")
index()
