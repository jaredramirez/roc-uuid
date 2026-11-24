"""Builds every benchmark, runs each and prints a Markdown table of
nanoseconds per call. Run with `just bench-compare` from the bench profile,
`devenv --profile bench shell`.
"""

import pathlib
import platform
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "bench-out"


def sh(*args, cwd=ROOT):
    return subprocess.run(args, check=True, text=True, cwd=cwd, stdout=subprocess.PIPE).stdout


def build():
    OUT.mkdir(exist_ok=True)
    sh("roc", "build", "--opt=speed", "bench/main.roc", f"--output={OUT}/bench")
    sh("cargo", "build", "--quiet", "--release", "--manifest-path", "bench/compare/rust/Cargo.toml",
       "--target-dir", f"{OUT}/rust")
    sh("go", "build", "-o", f"{OUT}/go", ".", cwd=ROOT / "bench/compare/go")


def parse(output):
    """`operation: NS` lines, with an optional ` ns` suffix, as a dict"""
    rows = {}
    for line in output.splitlines():
        label, ns = line.split(": ", 1)
        rows[label] = float(ns.removesuffix(" ns"))
    return rows


def main():
    build()
    columns = {
        "roc-uuid": parse(sh(f"{OUT}/bench")),
        "Rust `uuid`": parse(sh(f"{OUT}/rust/release/uuid-compare")),
        "Go `google/uuid`": parse(sh(f"{OUT}/go")),
        "Python `uuid`": parse(sh(sys.executable, "bench/compare/python/bench.py")),
    }
    print(f"Nanoseconds per call, lower is better ({platform.machine()}, {platform.system()})\n")
    print("| Operation | " + " | ".join(columns) + " |")
    print("| --- |" + " ---: |" * len(columns))
    for op in columns["roc-uuid"]:
        cells = [f"{c[op]:,.1f}" if op in c else "n/a" for c in columns.values()]
        print(f"| `{op}` | " + " | ".join(cells) + " |")


main()
