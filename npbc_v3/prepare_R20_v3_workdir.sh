#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_PARENT="${1:-$PWD}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$OUT_PARENT/R20_v3_l012_pilot_${STAMP}"

: "${V3_MODEL_FILE:=/leonardo/home/userexternal/gbasile0/water_npbc_R20_OPT/R20_flatbias_latest_edge_opt/MACE-OFF23_small_2.model-mliap_lammps.pt}"
: "${V3_VDWPARM_FILE:=/leonardo/home/userexternal/gbasile0/water_npbc_R20_OPT/R20_flatbias_latest_edge_opt/bias/vdw_parameter_step25000_flat_edge_m13.dat}"
: "${V3_RESTART_UPDATE80:=/leonardo/home/userexternal/gbasile0/water_npbc_R20_OPT/R20_flatbias_latest_edge_opt/restart_R20_v2_frozen_u80_1ns_final.lammps}"

for f in "$V3_MODEL_FILE" "$V3_VDWPARM_FILE" "$V3_RESTART_UPDATE80"; do
  test -s "$f" || { echo "ERROR: missing required file $f" >&2; exit 2; }
done

mkdir -p "$OUT/bias"

cp -a "$REPO_ROOT/npbc_production/bias/gau_R20_v3_U0_seed_update80.dat" "$OUT/bias/U0_seed_immutable.dat"
cp -a "$REPO_ROOT/npbc_production/bias/gau1_R20_v3_U1_zero.dat" "$OUT/bias/U1_seed_immutable.dat"
cp -a "$REPO_ROOT/npbc_production/bias/gau2_R20_v3_U2_seed_update80.dat" "$OUT/bias/U2_seed_immutable.dat"
chmod 444 "$OUT"/bias/*_seed_immutable.dat

cp -a "$OUT/bias/U0_seed_immutable.dat" "$OUT/bias/U0_work.dat"
cp -a "$OUT/bias/U1_seed_immutable.dat" "$OUT/bias/U1_work.dat"
cp -a "$OUT/bias/U2_seed_immutable.dat" "$OUT/bias/U2_work.dat"
chmod 644 "$OUT"/bias/*_work.dat

cp "$REPO_ROOT/npbc_v3/run_R20_v3_jointopt.mace.template" "$OUT/run_R20_v3_jointopt.mace"

python3 - "$OUT/run_R20_v3_jointopt.mace" "$V3_MODEL_FILE" "$V3_VDWPARM_FILE" "$V3_RESTART_UPDATE80" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
repl={
    "__MODEL_FILE__":sys.argv[2],
    "__VDWPARM_FILE__":sys.argv[3],
    "__U0_FILE__":"./bias/U0_work.dat",
    "__U1_FILE__":"./bias/U1_work.dat",
    "__U2_FILE__":"./bias/U2_work.dat",
    "__RESTART_UPDATE80__":sys.argv[4],
}
for old,new in repl.items():
    if old not in s:
        raise SystemExit(f"missing template token {old}")
    s=s.replace(old,new)
p.write_text(s)
PY

python3 "$REPO_ROOT/scripts/validate_npbc_v3_fields.py" \
  --u0 "$OUT/bias/U0_work.dat" \
  --u1 "$OUT/bias/U1_work.dat" \
  --u2 "$OUT/bias/U2_work.dat" \
  --require-u1-zero

{
  echo "created=$(date --iso-8601=seconds)"
  echo "repo=$REPO_ROOT"
  echo "model=$V3_MODEL_FILE"
  echo "vdwparm=$V3_VDWPARM_FILE"
  echo "restart=$V3_RESTART_UPDATE80"
} > "$OUT/PROVENANCE.txt"

(
  cd "$OUT"
  sha256sum bias/*_seed_immutable.dat > SEED_SHA256.txt
)

printf 'R20 v3 pilot workdir: %s\ninput: %s\n' "$OUT" "$OUT/run_R20_v3_jointopt.mace"
