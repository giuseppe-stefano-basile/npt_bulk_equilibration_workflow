#!/usr/bin/env python3
"""Static validation for R20 NPBC v3 U0/U1/U2 coefficient files."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

NL = 81
ACTIVE_FIRST = 68
ACTIVE_LAST = 79
SCALAR_EDGE_DELTA = -13.0


def read_field(path: Path):
    values = {}
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 2:
            raise ValueError(f"{path}:{lineno}: expected 2 columns, got {len(fields)}")
        k = int(fields[0])
        v = float(fields[1])
        if k in values:
            raise ValueError(f"{path}:{lineno}: duplicate index {k}")
        if not math.isfinite(v):
            raise ValueError(f"{path}:{lineno}: non-finite value")
        values[k] = v
    if sorted(values) != list(range(NL)):
        missing = sorted(set(range(NL)) - set(values))
        extra = sorted(set(values) - set(range(NL)))
        raise ValueError(f"{path}: indices must be exactly 0..80; missing={missing}, extra={extra}")
    return values


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--u0", type=Path, required=True)
    ap.add_argument("--u1", type=Path, required=True)
    ap.add_argument("--u2", type=Path, required=True)
    ap.add_argument("--require-u1-zero", action="store_true")
    args = ap.parse_args()

    u0 = read_field(args.u0)
    u1 = read_field(args.u1)
    u2 = read_field(args.u2)

    failures = []

    scalar_delta = u0[80] - u0[79]
    if abs(scalar_delta - SCALAR_EDGE_DELTA) > 1e-8:
        failures.append(
            f"U0 ghost condition failed: a80-a79={scalar_delta:.12g}, expected {SCALAR_EDGE_DELTA}"
        )

    if abs(u1[80] - u1[79]) > 1e-12:
        failures.append("U1 ghost condition failed: b1[80] != b1[79]")
    if abs(u2[80] - u2[79]) > 1e-12:
        failures.append("U2 ghost condition failed: b2[80] != b2[79]")

    for name, field in (("U1", u1), ("U2", u2)):
        bad = [k for k in range(ACTIVE_FIRST) if abs(field[k]) > 1e-12]
        if bad:
            failures.append(f"{name} has nonzero coefficients below 17 A: {bad[:10]}")

    if args.require_u1_zero:
        bad = [k for k, value in u1.items() if abs(value) > 1e-12]
        if bad:
            failures.append(f"U1 seed expected identically zero, nonzero indices={bad}")

    print("NPBC v3 R20 field validation")
    print(f"  U0: {args.u0}")
    print(f"  U1: {args.u1}")
    print(f"  U2: {args.u2}")
    print(f"  layers: {NL} (physical 0..79, ghost 80)")
    print(f"  angular active coefficients: {ACTIVE_FIRST}..{ACTIVE_LAST}")
    print(f"  U0 edge delta: {scalar_delta:.12g}")
    print(f"  U1 ghost delta: {u1[80]-u1[79]:.12g}")
    print(f"  U2 ghost delta: {u2[80]-u2[79]:.12g}")

    if failures:
        print("FAIL")
        for item in failures:
            print(f"  - {item}")
        return 2

    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
