# Agent context for current NPBC/PBC workflow and bias provenance

## What this file is for
Use this as the **single handoff note** for an agent that needs to understand:
1. the **current repository-facing keywords and contracts** for the new extracted-system workflow, and
2. the **latest authoritative optimized bias actually used in the simulation campaign**.

The critical distinction is:
- the **repository workflow has moved to a 20 Å sphere / 40 Å cube interface**, with mandatory explicit R20 bias variables for NPBC;
- the **latest optimized bias already available from the simulation history is still an R=15 Å stage13 bias**, frozen from the `s991000` handoff, and it must **not** be silently reused for the new R20 workflow.

---

## Source-of-truth hierarchy
When there is a conflict, use this priority:
1. **Current repo launch/config contract** for the extracted-system workflow.
2. **Locked simulation context** for the latest optimized bias provenance and physical settings.
3. Older docs in the repo are secondary, because several top-level markdown files still contain stale `R15` / `24.2 Å` / equivalent-volume wording.

The repo homepage and config reflect the newer geometry, while some README-style files still contain legacy wording. The active repo view shows the workflow purpose as extraction of a **20 Å NPBC sphere** and **40 Å PBC cube**. citeturn942789view0turn817313view0turn299524view0turn299524view1

---

## Part A — Current repository-facing workflow keywords

### Geometry and extracted-system contract
These are the **new keywords and filenames** the agent should treat as active for the repository workflow:

- `SPHERE_R_A=20.0`
- `CUBE_EDGE_A=40.0`
- `STEPS_EQ_EXTRACTED=100000`
- `STEPS_PROD_EXTRACTED=5000000`
- `NPBC_VDWPARM_FILE`
- `NPBC_GAU_FILE`
- extracted NPBC data: `runs/data/alanine_cavity_R20_from_npt.data`
- extracted PBC data: `runs/data/alanine_pbc_cube40_from_npt.data`

These names appear in the implementation plan and in the live config file. The config also keeps the density target at `RHO0_MOL_A3=0.037235960250849326` and `RHO_GCC=1.11391659`. fileciteturn1file2 citeturn817313view0turn490425view0turn135882view4

### New extracted-system stage names
The extracted systems are no longer supposed to be launched as a single one-shot production step. The current contract is:

- NPBC stages:
  - `run_npbc_minimize.mace`
  - `run_npbc_equilibration.mace`
  - `run_npbc_production.mace`
- PBC stages:
  - `run_pbc_minimize.mace`
  - `run_pbc_equilibration.mace`
  - `run_pbc_production.mace`

The launchers explicitly check for those filenames and run them in order as a **three-stage pipeline: minimize → equilibration → production**. fileciteturn1file2 citeturn135882view2turn135882view3

### NPBC bias contract in the repo
For the repository workflow, NPBC is treated as requiring **explicit R20 bias paths**:

- `NPBC_VDWPARM_FILE`
- `NPBC_GAU_FILE`

`launch_npbc.sh` now fails fast if they are unset or missing, with the explicit message:
- `ERROR: R20 bias files required for NPBC but not available.`
- `Set both variables in configs/config_npt_bulk.env to valid paths pointing to 20 Å optimised bias files, then re-run.` citeturn135882view0turn135882view1

Important nuance:
- **local NPBC launcher**: fail fast if R20 bias is unavailable. citeturn135882view0
- **master SLURM submit script**: it may **skip** the NPBC job if the variables are unset, while still submitting NPT + PBC. citeturn490425view3turn490425view4

### Current orchestration semantics
The current orchestration expects:
- NPT bulk workflow first,
- then extracted data verification,
- then NPBC 3-stage pipeline,
- then PBC 3-stage pipeline. citeturn490425view0turn490425view1turn490425view2

### Practical repo-side keywords the agent should use
If the agent edits or reasons about the repo, these are the exact strings it should look for and preserve:

```text
SPHERE_R_A
CUBE_EDGE_A
STEPS_EQ_EXTRACTED
STEPS_PROD_EXTRACTED
NPBC_VDWPARM_FILE
NPBC_GAU_FILE
alanine_cavity_R20_from_npt.data
alanine_pbc_cube40_from_npt.data
run_npbc_minimize.mace
run_npbc_equilibration.mace
run_npbc_production.mace
run_pbc_minimize.mace
run_pbc_equilibration.mace
run_pbc_production.mace
R20 bias files required for NPBC but not available
minimize → equilibration → production
```

---

## Part B — Latest authoritative optimized bias from the simulation campaign

### What the latest usable optimized bias is
The **latest authoritative optimized bias actually frozen and handed off into corrected-density alanine runs** is:

- source handoff step: `991000`
- bias source file: `npbc_stage13_rho_tunable_scale5e4/branch_flat/gau_stage13.dat`
- VDWPARM source file: `npbc_stage13_rho_tunable_scale5e4/VDWPARM_R15_S0125_step5000_stage13_outerSingles41_60.dat`
- resulting corrected-density lane: `stage13_alanine_prepared/stage13corr_s991000_20260319_194116` fileciteturn0file0 fileciteturn1file0 citeturn817313view0

This is the bias that was frozen after the user-approved handoff despite the strict stability gate not fully passing. The context explicitly records that the stage13 optimization was stopped and frozen at the best available bias at step `991000`, and that this was used to create the corrected-density alanine lane. fileciteturn0file0 fileciteturn2file18

### Physical settings associated with that latest optimized R15 bias
Treat the following as the **authoritative physical deployment settings** tied to the latest optimized stage13 bias:

- `R = 15 Å`
- `rho0 = 0.037235960250849326 mol/A^3`
- `rho_gcc = 1.11391659`
- `dr = 0.25 Å`
- `nl = 61`
- `vdw_scale = 5e-4`
- `NLAYER_STEP = 5000`
- chunk run length `nsteps = 5001`
- deployment mode in alanine NPBC runs: `opt no` (frozen bias)
- selected optimization branch: `branch_flat` fileciteturn0file0 fileciteturn2file15 fileciteturn2file18

The R15 corrected-density NPBC protocol is recorded as using `fix cavity/reflect` with `R=15 Å`, frozen `fix cavity/meanfield` with `rho0=0.037235960250849326`, `dr=0.25`, `nl=61`, `vdw_scale=5e-4`, and `gau=stage13 optimized bias`. fileciteturn2file15

### Associated corrected-density alanine deployment
The corrected-density alanine lane built from that bias is:

- folder: `stage13_alanine_prepared/stage13corr_s991000_20260319_194116`
- builder: `prepare_stage13_corrected_density_alanine.py`
- matched water count: `Nwater = 516`
- total atoms: `1570`
- density settings:
  - `rho* = 1.11391659 g/cc`
  - `rho0 = 0.037235960250849326 A^-3`
  - `R = 15`
  - `cut = 1.6` fileciteturn2file18

### Stable optimization conventions that led to this bias
These conventions matter if the agent needs to reason about how the bias was produced:

- `VDWPARM_R15_S0125_step5000_stage13_outerSingles41_60.dat` is the final step-5000 optimizer layout. fileciteturn1file9
- `vdw_scale=1` was unstable and crashed; `vdw_scale=0.001` ran but was noisier; `vdw_scale=5e-4` is the stable choice that was kept. fileciteturn1file12 fileciteturn1file15
- The `gau` explicit indexing bug was fixed: LAMMPS expects explicit `k` in `0..nlayers-1`, not 1-based indexing. fileciteturn2file13
- The step-5000 rollout was important: branch inputs were corrected from the older step-2500 VDWPARM to the step-5000 file. fileciteturn2file2
- The later accepted workflow was unsmoothed/frozen relative to the problematic smoothing experiments; `GAU_SMOOTH_ALPHA=0.0` became the safe default after rollback. fileciteturn1file6

### Current status of older bias variants
The agent should distinguish these bias variants:

1. **Current authoritative bias for corrected-density runs**
   - `stage13corr_s991000_20260319_194116`
   - frozen from `branch_flat/gau_stage13.dat` at step `991000`.

2. **Older frozen bias used in historical stage13postopt runs**
   - `stage13postopt_s1901000_20260316_001735/bias/gau_stage13postopt_s1901000.dat`
   - legacy, still useful only for old-bias retests. fileciteturn2file3

3. **Old-bias retest lane**
   - `stage13corr_oldbias_retest_20260327_165250`
   - uses old `gau_stage13postopt_s1901000.dat` on the corrected-density start,
   - not the main current bias. fileciteturn2file7

So, if the agent is asked “what is the latest optimized bias?”, the answer should be:
- **the R15 stage13 `branch_flat` bias frozen at handoff step `991000`, deployed in `stage13corr_s991000_20260319_194116`**. fileciteturn2file18

---

## Part C — Optimization and diagnostics keywords worth preserving

### Mean-field optimization keywords from the simulation campaign
These are the exact keywords/values the agent should know when reading or patching the optimization workflow:

```text
vdw_scale = 5e-4
NLAYER_STEP = 5000
nsteps = 5001
opt yes            # during optimization
opt no             # after freezing for deployment
gau_stage13.dat
VDWPARM_R15_S0125_step5000_stage13_outerSingles41_60.dat
branch_flat
rho0 = 0.037235960250849326
dr = 0.25
nl = 61
k = 0..60          # explicit gau indexing
```

### Grouping / shell structure
The most recent grouped optimizer structure used for the R15 campaign was:

- `1-20`
- `21-35`
- `36-40`
- `41-44`
- `45-52`
- `53-60` fileciteturn0file0

### Current optimizer redesign direction
If the agent is meant to continue optimization work in the LAMMPS mean-field code, the currently desired redesign is **not** uniform `+/-1` updates per group. The locked context says the next priority is a physically weighted intra-group update such as:

- `delta_g_i = -eta_group * w_i * (rho_i-rho0)/rho0`
- reliability weights based on occupancy / `N_eff` / SEM
- damp or freeze very sparse layers
- preserve the special handling of the last boundary layer
- optimize in VDW/RO order (inner → outer), while mapping `dens_shell` only at the interfaces because its native order is outer → inner. fileciteturn2file5 fileciteturn0file0

### Mandatory NPBC diagnostics baseline
For any NPBC run, the current policy is that these diagnostics are mandatory:

- `01_density_vs_radius.png`
- `01b_density_vs_radius_outer_shells.png`
- `02_grouped_density_latest.png`
- `03_group_rel_error_heatmap.png`
- `06_group_occupancy_heatmap.png`
- `08_density_vs_radius_grouped_core_uncertainty.png`
- `09_density_vs_radius_traj_lastN.png`
- `10_orientation_vs_radius_traj_lastN.png`
- `11_outer_orientation_timeseries.png`
- `07_bias_profiles.png`
- `04_dgau_timeseries.png`
- `05_thermo_timeseries.png`
- `reports/summary.txt` with density, shape, and orientation scalars. fileciteturn2file12

---

## Part D — Hard guardrails for the agent

### Guardrail 1: do not mix repository R20 workflow with the existing R15 bias
The most important rule is:

- **Do not reuse** `gau_stage13.dat` + `VDWPARM_R15_S0125_step5000_stage13_outerSingles41_60.dat` as if they were valid R20 inputs for the new repository workflow.
- The implementation plan explicitly says the R20 workflow is blocked until matching R20 bias files are supplied. fileciteturn1file2

### Guardrail 2: repo-side NPBC must use explicit bias variables
For repo execution logic, the agent should preserve:

- `NPBC_VDWPARM_FILE`
- `NPBC_GAU_FILE`
- error semantics around “R20 bias files required for NPBC but not available.” citeturn135882view0turn135882view1

### Guardrail 3: corrected-density comparison logic
For scientific comparisons in the current simulation campaign:

- PBC CV/FES analyses must be **periodicity-aware / wrapped-corrected**.
- Radial density around the solute must use **molecule-whole COM handling** for water in PBC.
- Water count, density, temperature protocol, and tether policy must be aligned or explicitly reported when NPBC and PBC are compared. fileciteturn0file0

---

## Part E — Short answer the agent should give if asked directly

### “What are the new keywords I need?”
Use:
- `SPHERE_R_A=20.0`
- `CUBE_EDGE_A=40.0`
- `STEPS_EQ_EXTRACTED=100000`
- `STEPS_PROD_EXTRACTED=5000000`
- `NPBC_VDWPARM_FILE`
- `NPBC_GAU_FILE`
- `run_npbc_minimize.mace`
- `run_npbc_equilibration.mace`
- `run_npbc_production.mace`
- `run_pbc_minimize.mace`
- `run_pbc_equilibration.mace`
- `run_pbc_production.mace`
- `runs/data/alanine_cavity_R20_from_npt.data`
- `runs/data/alanine_pbc_cube40_from_npt.data` fileciteturn1file2 citeturn817313view0turn135882view2turn135882view3turn135882view4

### “What is the latest optimized bias in the simulations?”
It is:
- the **R15** stage13 `branch_flat` bias,
- frozen at handoff step **`991000`**,
- from `npbc_stage13_rho_tunable_scale5e4/branch_flat/gau_stage13.dat`,
- with `VDWPARM_R15_S0125_step5000_stage13_outerSingles41_60.dat`,
- used to create `stage13_alanine_prepared/stage13corr_s991000_20260319_194116`,
- with `rho0=0.037235960250849326`, `dr=0.25`, `nl=61`, `vdw_scale=5e-4`, `R=15`, and frozen deployment mode `opt no`. fileciteturn2file18 fileciteturn2file15

### “Can I use that bias for the new R20 repo workflow?”
No.
The repo-side R20 workflow explicitly requires **new 20 Å bias files** via `NPBC_VDWPARM_FILE` and `NPBC_GAU_FILE`, and the plan explicitly says **do not fall back** to the old R15 assets. fileciteturn1file2 citeturn135882view0turn135882view1

---

## Quick provenance links
- Locked working context: fileciteturn0file0
- Repo implementation plan: fileciteturn0file1
- Repo URL: fileciteturn0file2
