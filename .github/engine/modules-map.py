#!/usr/bin/env python3
"""Map Godot engine modules to the classes they register, from a Godot source tree.

    modules-map.py <godot-source> > modules.json

Reads each modules/<name>/config.py: get_doc_classes() lists the classes a module
registers and env.module_add_dependencies(...) lists the modules it needs. The
result feeds detect-features.gd, so the mapping always matches the Godot version
being built.
"""
import ast
import json
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
out = {}
for cfg in sorted((src / "modules").glob("*/config.py")):
    name = cfg.parent.name
    text = cfg.read_text(encoding="utf-8")
    classes = []
    m = re.search(r"def get_doc_classes\(\):\s*return\s*(\[.*?\])", text, re.S)
    if m:
        try:
            classes = ast.literal_eval(m.group(1))
        except (ValueError, SyntaxError):
            classes = re.findall(r'"([A-Za-z0-9_]+)"', m.group(1))
    deps = []
    # Some modules only list their classes as doc_classes/*.xml.
    classes += [p.stem for p in (cfg.parent / "doc_classes").glob("*.xml")]
    for dm in re.finditer(r'module_add_dependencies\(\s*"[^"]+"\s*,\s*\[([^\]]*)\](\s*,\s*True)?', text):
        if dm.group(2):  # optional dependency
            continue
        deps += re.findall(r'"([A-Za-z0-9_]+)"', dm.group(1))
    out[name] = {"classes": sorted(set(classes)), "deps": sorted(set(deps))}

json.dump(out, sys.stdout, indent=1, sort_keys=True)
print()
