#!/usr/bin/env bash
set -euo pipefail

LMP_ROOT="${LMP_ROOT:-/leonardo/home/userexternal/gbasile0/lammps-glob-dev}"
OUT_PARENT="${1:-$PWD}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$OUT_PARENT/lammps_npbc_v2_source_for_v3_${STAMP}"

mkdir -p "$OUT"

required=(
  fix_cavity_meanfield_v2.cpp
  fix_cavity_meanfield_v2.h
  fix_cavity_reflect_com.cpp
  fix_cavity_reflect_com.h
)

for f in "${required[@]}"; do
  test -s "$LMP_ROOT/src/$f" || {
    echo "ERROR: missing $LMP_ROOT/src/$f" >&2
    exit 2
  }
  cp -a "$LMP_ROOT/src/$f" "$OUT/"
done

for f in fix_cavity_meanfield.cpp fix_cavity_meanfield.h fix_cavity_reflect.cpp fix_cavity_reflect.h; do
  [[ -f "$LMP_ROOT/src/$f" ]] && cp -a "$LMP_ROOT/src/$f" "$OUT/"
done

{
  echo "timestamp=$(date --iso-8601=seconds)"
  echo "hostname=$(hostname -f 2>/dev/null || hostname)"
  echo "lmp_root=$LMP_ROOT"
  echo "binary=$LMP_ROOT/build-MOL/lmp"
  echo
  if [[ -d "$LMP_ROOT/.git" ]]; then
    echo "git_head=$(git -C "$LMP_ROOT" rev-parse HEAD 2>/dev/null || true)"
    echo "--- git status ---"
    git -C "$LMP_ROOT" status --short --branch || true
  fi
} > "$OUT/PROVENANCE.txt"

(
  cd "$OUT"
  sha256sum fix_cavity* > SOURCE_SHA256.txt
)

if [[ -f "$LMP_ROOT/build-MOL/lmp" ]]; then
  sha256sum "$LMP_ROOT/build-MOL/lmp" > "$OUT/LAMMPS_BINARY_SHA256.txt"
fi

TARBALL="${OUT}.tar.gz"
tar -C "$(dirname "$OUT")" -czf "$TARBALL" "$(basename "$OUT")"

printf 'source_dir=%s\narchive=%s\n' "$OUT" "$TARBALL"
