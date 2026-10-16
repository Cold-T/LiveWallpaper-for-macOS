#!/usr/bin/env python3
"""Generate ABI-identical vtable wrappers; never log arguments or media data."""
import re
import sys
from pathlib import Path

source = Path(__file__).with_name("lwmedia-winrt.c")
text = source.read_text() + "\n" + "\n".join(p.read_text() for p in sorted(source.parent.glob("*.inc")))
names = set(re.findall(r"T\((\w+)\)", text))
functions = {}
for result, name, parameters in re.findall(r"static\s+(HRESULT|ULONG)\s+WINAPI\s+(\w+)\s*\(([^)]*)\)\s*\{", text):
    functions[name] = (result, parameters)
lines = ["/* Generated vtable traces. Arguments, media and paths are never logged. */"]
for name in sorted(names):
    if name == "name":
        continue
    if name not in functions:
        raise ValueError(f"vtable function has no explicit WINAPI definition: {name}")
    result, parameters = functions[name]
    arguments = [re.search(r"(\w+)\s*$", p.strip()).group(1) for p in parameters.split(",") if p.strip() != "void"]
    returned = "lwmedia_trace_return_value" if result == "HRESULT" else "S_OK"
    lines.append(f'static {result} WINAPI traced_{name}({parameters}) {{ {result} lwmedia_trace_return_value={name}({",".join(arguments)}); trace_result("{name}",{returned}); return lwmedia_trace_return_value; }}')
Path(sys.argv[1]).write_text("\n".join(lines) + "\n")
