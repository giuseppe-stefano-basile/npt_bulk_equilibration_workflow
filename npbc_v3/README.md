# NPBC v3 execution guide

This directory contains the R20 v3 templates. They are intentionally separate from the current production NPBC path until `cavity/meanfield/v3` passes force and ensemble validation.

## 1. Validate the seed fields

From the repository root:

```bash
python3 scripts/validate_npbc_v3_fields.py \
  --u0 npbc_production/bias/gau_R20_v3_U0_seed_update80.dat \
  --u1 npbc_production/bias/gau1_R20_v3_U1_zero.dat \
  --u2 npbc_production/bias/gau2_R20_v3_U2_seed_update80.dat \
  --require-u1-zero
```

Expected: `PASS`.

## 2. Archive the active Leonardo custom source before editing

```bash
bash scripts/archive_leonardo_npbc_sources_for_v3.sh "$PWD"
```

Keep the resulting tarball immutable. The v2 and COM-wall sources are currently untracked custom files in the Leonardo LAMMPS source tree, so this step is mandatory for provenance.

## 3. Implement and build `cavity/meanfield/v3`

Use `docs/NPBC_V3_L012.md` as the source contract. The new style should be implemented as separate `fix_cavity_meanfield_v3.{h,cpp}` files rather than modifying v2 in place. This keeps the stationary-validated v2 executable/source path available as a control.

Before building, add the new source files to the same LAMMPS source tree that contains the validated `fix_cavity_meanfield_v2.*` and `fix_cavity_reflect_com.*` files.

## 4. Fill the optimizer template

Copy:

```bash
cp npbc_v3/run_R20_v3_jointopt.mace.template run_R20_v3_jointopt.mace
```

Replace:

- `__MODEL_FILE__`
- `__VDWPARM_FILE__`
- `__U0_FILE__`
- `__U1_FILE__`
- `__U2_FILE__`
- `__RESTART_UPDATE80__`

For the first R20 pilot the coefficient files should be writable working copies of the three seed files, not the seed files themselves.

## 5. Required gates before a response update

Run in this order:

1. `run 0` parser test.
2. One-water finite-difference force test for pure U1, pure U2, and mixed U1+U2.
3. Short frozen NVE conservation test.
4. Frozen 10-ps NVT test from the update-80 restart with U1=0. This must reproduce v2 behavior within sampling noise.
5. Only then enable `opt yes` and run the first 100-ps response window.

## 6. First response pilot

The supplied optimizer template runs ten 100-ps windows plus 10 ps after the tenth update. For the first build, it is safer to edit `opt_steps` to `110000` and inspect one update before committing to the ten-window run.

Record separately after each response update:

- `chi2_rho`
- `chi2_p1`
- `chi2_p2`
- `max|delta U0|`
- `max|delta U1|`
- `max|delta U2|`
- P1 and P2 in 19-20 A and 19.75-20 A
- density in 19-20 A and 19-19.5 A
- response-matrix rank/condition diagnostics if available.

## 7. Freeze and validate

After convergence, switch to `run_R20_v3_frozen.mace.template`, run a stationary 1 ns trajectory, and repeat the exact v2 validation suite. Do not judge v3 from adaptive windows alone.

## Production handoff

Do not replace `npbc_production/run_npbc_{equilibration,production}.mace` until the frozen v3 R20 validation passes. Once it does, add a production mode using water O/H types appropriate to the alanine topology (currently O=3, H=4 in that workflow) and frozen U0/U1/U2 files.
