# NPT Bulk Equilibration + Sphere/Cube Extraction Workflow

**Date:** 2026-03-24  
**Purpose:** Generate representative NPT-equilibrated bulk water system, then extract both NPBC (20 Å sphere) and PBC (40 Å cube) systems for production runs.

---

## Overview

This workflow implements a robust protocol for preparing comparison systems:

1. **Phase 1 (100 ps):** Energy minimization + gentle temperature ramp (25K → 200K)
2. **Phase 2 (500 ps):** NPT equilibration at P=1 atm, T=300K (extract density target)
3. **Phase 3 (500 ps):** NPT production run (statistics collection)
4. **Extraction:** From final frame, cut 20 Å NPBC sphere and 40 Å PBC cube

### Key Design Choices

- **Target density:** `rho0 = 0.037235960250849326 mol/Å³` (from stage13 optimization .env)
- **Bulk system:** 3800 water molecules in ~35 Å box (larger than final systems for better bulk representation)
- **Alanine dipeptide:** Solute forces are zeroed during NPT, and the extracted systems are explicitly recentered for comparison-ready production runs
- **Extraction:** Both sphere and cube are written with the solute COM at the origin; the 40 Å cube encloses the 20 Å sphere
- **PBC production:** Periodic comparison run uses a weak tether to keep alanine at the cube center

---

## Folder Structure

```
npt_bulk_equilibration_workflow/
├── configs/
│   └── config_npt_bulk.env              # All parameters (rho0, box size, runtime)
├── scripts/
│   ├── generate_bulk_alanine_npt.py     # Build bulk system
│   ├── extract_sphere_cube.py           # Extract NPBC sphere + PBC cube
│   └── run_workflow.sh                  # Master launcher
├── input_templates/
│   ├── 01_minimize_warmup_npt.mace      # Minimization + warmup
│   ├── 02_npt_equilibration.mace        # NPT equilibration (500 ps)
│   └── 03_npt_production.mace           # NPT production (500 ps)
├── analysis_tools/
│   └── (reserved for post-processing scripts)
├── systems/
│   └── (output .data files during workflow)
├── runs/
│   ├── data/                            # .data files
│   ├── logs/                            # Log files
│   └── *.mace, restart_*.lammps         # Runtime files
└── README.md                            # This file

```

---

## Quick Start

### 1. Review Configuration

```bash
cd npt_bulk_equilibration_workflow
cat configs/config_npt_bulk.env
```

Key parameters:
- `RHO0_MOL_A3`: Target density (mol/Å³)
- `RHO_GCC`: Density in g/cm³ (validation)
- `N_WATER_BULK`: Number of waters (~3800)
- `TEMP_K`: Temperature (300 K)
- `PRESS_ATM`: Pressure (1 atm)
- `DT_FS`: Timestep (1 fs)

### 2. Prepare Input PDB

```bash
# Ensure ala2_seed.pdb is available
# Default: looks in current directory
# Or modify config_npt_bulk.env: ALANINE_PDB=/path/to/ala2_seed.pdb
```

### 3. Run Full Workflow

```bash
bash run_workflow.sh
```

This will:
1. Generate bulk system (~3800 waters + alanine)
2. Run minimize + warmup (Phase 1)
3. Run NPT equilibration (Phase 2)
4. Run NPT production (Phase 3)
5. Extract sphere and cube from final frame

**Total runtime:** ~2–4 hours on GPU (NVIDIA A100/H100)

### 4. Check Output

```bash
ls -la runs/data/
# alanine_cavity_R20_from_npt.data     (NPBC, ~4500 atoms)
# alanine_pbc_cube40_from_npt.data     (PBC, ~6000 atoms)

tail -20 runs/logs/phase3_npt_prod.log
# Check final density and box size
```

---

## Detailed Workflow Steps

### Phase 1: Minimize + Warmup (100 ps)

**Input:** `bulk_water_alanine_npt.data`  
**Output:** `restart_npt_phase1_warmup.lammps`

Steps:
1. Energy minimization (10,000 steps, max 100,000)
2. Freeze solute (alanine, mol_id=1)
3. Warmup at T=25K (50,000 steps = 50 ps)
4. Ramp 25K → 200K (100,000 steps = 100 ps)

**Check:** 
- Minimization converged? Check log for "Minimization complete"
- Temperature stabilized at 200K? Check final .log

### Phase 2: NPT Equilibration (500 ps)

**Input:** `restart_npt_phase1_warmup.lammps`  
**Output:** `restart_npt_phase2_eq_final.lammps`, `traj_bulk_npt_phase2_eq.dump`

Steps:
1. Initialize velocities at 300K
2. Apply NPT barostat (isotropic, P=1 atm)
3. Thermostat: Langevin at T=300K
4. Output density every 1 ps
5. Save restarts every 50k steps for resumability

**Check:**
- Box equilibrated? Pressure should fluctuate around 1 atm
- Density converging? Compare first 100 ps vs. final 100 ps
- Temperature stable at 300K?

### Phase 3: NPT Production (500 ps)

**Input:** `restart_npt_phase2_eq_final.lammps`  
**Output:** `restart_npt_phase3_prod_final.lammps`, `bulk_water_alanine_npt_final.data`, `traj_bulk_npt_phase3_prod.dump`

Steps:
1. Continue NPT from equilibrated state
2. Collect statistics (output every 0.5 ps)
3. Full trajectory dump every 500 steps
4. Final restart and .data file for extraction

**Check:**
- Final density logged
- Box size stable
- Trajectory written (can be large ~100 MB)

### Extraction: Sphere + Cube

**Input:** `bulk_water_alanine_npt_final.data`  
**Output:** 
- `alanine_cavity_R20_from_npt.data` (NPBC sphere, R=20 Å)
- `alanine_pbc_cube40_from_npt.data` (PBC cube, edge=40 Å)

Process:
1. Read final NPT frame
2. Compute solute COM (alanine, mol_id=1)
3. Extract all atoms within 20 Å sphere → NPBC system
4. Extract all atoms within 40 Å cube bounds → PBC system
5. Renumber atoms sequentially
6. Write .data files with correct headers

**Verification:**
- Sphere atoms: ~1400 total (~1380 water atoms)
- Cube atoms: ~1400 total (~1380 water atoms)
- Solute (alanine): 22 atoms in both
- Check density ratio: `N_water / volume ≈ 0.0333 mol/Å³`

---

## Configuration Options

Edit `configs/config_npt_bulk.env` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `RHO0_MOL_A3` | 0.037235960250849326 | Target bulk density (mol/Å³) |
| `RHO_GCC` | 1.11391659 | Density validation (g/cm³) |
| `N_WATER_BULK` | 3800 | Bulk waters (larger = better, slower) |
| `SPHERE_R_A` | 20.0 | NPBC sphere radius (Å) |
| `CUBE_EDGE_A` | 40.0 | PBC cube edge (Å) |
| `TEMP_K` | 300.0 | Temperature (K) |
| `PRESS_ATM` | 1.0 | Pressure (atm) |
| `DT_FS` | 1.0 | Timestep (fs) |
| `STEPS_PROD_NPT` | 500000 | Production duration (steps) |
| `CUDA_VISIBLE_DEVICES` | 0 | GPU ID for Leonardo |

### Density Target Justification

The target density `0.037235960250849326 mol/Å³` (= 1.11391659 g/cm³) comes directly from the stage13 optimization:

```
# From: npbc_stage13_rho_tunable_scale5e4/stage13_runtime.env
export RHO0="0.037235960250849326"
export RHO_GCC="1.11391659"
```

This ensures the NPT-generated systems match the density used in all subsequent NPBC/PBC production runs.

---

## Running on Leonardo BOOSTER

### Preparation

1. **Copy workflow to Leonardo:**
   ```bash
   tar czf npt_workflow.tar.gz npt_bulk_equilibration_workflow/
   scp npt_workflow.tar.gz utente@leonardo.cineca.it:/path/to/
   tar xzf npt_workflow.tar.gz
   ```

2. **Ensure LAMMPS binary available:**
   ```bash
   module load LAMMPS  # or compile locally
   export LMP_BIN=/path/to/lmp
   ```

3. **Update config for Leonardo GPUs:**
   ```bash
   # Edit configs/config_npt_bulk.env
   export CUDA_VISIBLE_DEVICES="0"  # Adjust for your allocation
   export LMP_BIN="/global/software/lammps/build_plumed_embed/lmp"
   ```

### Submission Script Example (SLURM)

Create `submit_npt.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=npt_bulk
#SBATCH --time=08:00:00
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --partition=gpu
#SBATCH -A <account>

cd $SLURM_SUBMIT_DIR
bash npt_bulk_equilibration_workflow/run_workflow.sh
```

Submit:
```bash
sbatch submit_npt.sh
```

### Performance Notes

- **Phase 1 (minimize + warmup):** ~10 min (GPU)
- **Phase 2 (NPT eq, 500k steps):** ~60–90 min (GPU)
- **Phase 3 (NPT prod, 500k steps):** ~60–90 min (GPU)
- **Total:** ~2.5–3 hours

Use multiple GPUs via MPI if available (edit LAMMPS input `-sf kk -pk kokkos` flags).

---

## Output Files

After successful workflow run:

### Systems (for production use)

| File | Size | Use |
|------|------|-----|
| `alanine_cavity_R20_from_npt.data` | ~150 KB | NPBC production (cavity/reflect + frozen bias) |
| `alanine_pbc_cube40_from_npt.data` | ~200 KB | PBC production (periodic, 40 Å cube, alanine centered) |

### Diagnostics (saved in runs/)

| File | Purpose |
|------|---------|
| `traj_bulk_npt_phase2_eq.dump` | Equilibration trajectory (use for density check) |
| `traj_bulk_npt_phase3_prod.dump` | Production trajectory (use for statistics) |
| `logs/phase*_*.log` | LAMMPS log files (check convergence) |
| `restart_npt_phase*.lammps` | Restart files (for resuming) |

---

## Next Steps: Production Runs

### NPBC Production (From Sphere)

Copy `alanine_cavity_R20_from_npt.data` to your NPBC production folder and run:

```bash
# With frozen bias from stage13 (opt no)
lmp -in run_nvt_alanine_nbpc_off23_stage13_prod_frozen.mace
```

### PBC Production (From Cube)

Copy `alanine_pbc_cube40_from_npt.data` to your PBC production folder and run:

```bash
# With equivalent density and a weak center tether on alanine
lmp -in run_nvt_alanine_pbc_off23_equiv.mace
```

### Comparison

Analyze:
- Solute conformational distributions (dihedrals, distances)
- First solvation shell density
- Radial distribution functions (RDF)
- Solute diffusion rates
- Free energy surfaces

---

## Troubleshooting

### Problem: "Cannot read PDB file"

**Solution:** Check `ALANINE_PDB` in config. Default expects `ala2_seed.pdb` in current directory.

```bash
# Copy from source
cp ../ala2_seed.pdb .
# Or update config
export ALANINE_PDB="../ala2_seed.pdb"
```

### Problem: "Phase 1 restart not found"

**Solution:** Phase 1 minimization likely crashed. Check:

```bash
tail -50 runs/logs/phase1_minimize_warmup.log
# Look for ERROR, segfault, or CUDA issues
```

### Problem: Density not converging in Phase 2

**Solution:** Box was too small or barostat not properly equilibrated. Try:

1. Increase `N_WATER_BULK` to 4500–5000 (larger box)
2. Extend Phase 2 equilibration: change `STEPS_EQ_NPT` to 1,000,000
3. Check barostat timescale: reduce `BAROSTAT_PDAMP` to 0.5 ps

### Problem: High memory usage

**Solution:** Reduce number of waters or output frequency:

```bash
export N_WATER_BULK="2500"  # ~25 Å box instead of 35 Å
# Reduces memory by ~50%
```

---

## References

- LAMMPS NPT documentation: https://docs.lammps.org/fix_npt.html
- MACE-OFF model: https://github.com/ACEsuit/mace
- Stage13 density target: `npbc_stage13_rho_tunable_scale5e4/stage13_runtime.env`

---

## Contact & Support

For issues with this workflow, check:
1. Logs in `runs/logs/`
2. Stage13 context: `RUN_CONTEXT_OFF23.md` in parent directory
3. Configuration consistency: ensure density matches stage13 target

---

**End of README**
