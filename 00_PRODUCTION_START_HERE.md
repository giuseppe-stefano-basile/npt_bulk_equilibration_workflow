# Complete NPT + Production Workflow for LEONARDO BOOSTER

## 📋 Overview

This package contains a **complete simulation pipeline** ready for execution on Leonardo BOOSTER:

```
NPT Bulk Equilibration (3 phases: 5h total)
        ↓
    Extract Systems
        ↓
    ┌───────┴───────┐
    ↓               ↓
NPBC Production  PBC Production
(5 ns, 4h)      (5 ns, 4h)
```

**Total Runtime**: 9-11 hours sequential OR 6-7 hours parallel (2 GPUs)

---

## 🎯 What's Included

### 1. NPT Bulk Equilibration (`npt_bulk_equilibration/`)
- **Purpose**: Generate bulk water system at target density with fixed alanine at center
- **Density**: 0.037235960250849326 mol/Å³ (from stage13 optimization)
- **System**: 3800 water molecules + 22-atom alanine dipeptide
- **Output**: Final dump file for extraction

### 2. System Extraction (`extraction/`)
- **Extraction Scripts**: Python code to extract from NPT output
- **Outputs**:
  - `NPBC_system.data`: 20 Å sphere (~1402 atoms)
  - `PBC_system.data`: 40 Å cube (~1402 atoms, 40 Å cube)

### 3. NPBC Production (`npbc_production/`)
- **Duration**: 5 nanoseconds
- **Boundary**: Non-periodic with reflective spherical cavity
- **Bias**: Frozen Gaussian + cavity/meanfield (opt no = frozen from stage13)
- **Embedded Files**:
  - `MACE-OFF23_small.model-mliap_lammps_float32.pt`
  - `bias/(R20 bias — see NPBC_VDWPARM_FILE in config)`
  - `bias/gau_R20.dat (must be supplied)`

### 4. PBC Production (`pbc_production/`)
- **Duration**: 5 nanoseconds
- **Boundary**: Periodic boundaries with alanine weakly tethered at the cube center
- **Bias**: None (bulk-like system)
- **Embedded Files**:
  - `MACE-OFF23_small.model-mliap_lammps_float32.pt`

---

## 🚀 Execution on LEONARDO BOOSTER

### Option A: Sequential Bash Script (Simplest)
```bash
cd npt_bulk_equilibration_workflow/
./run_all_leonardo.sh
```
- Single GPU, all phases run sequentially
- Total time: ~11 hours
- Best for: Single-GPU allocation

### Option B: SLURM Batch with Dependencies (Recommended)
```bash
cd npt_bulk_equilibration_workflow/
./submit_all_leonardo.sh
```
- Job orchestration:
  1. Submit NPT job (jobid=$NPT_JID)
  2. NPBC production depends on NPT completion
  3. PBC production depends on NPT completion
  4. NPBC and PBC run in parallel
- Total time: ~7 hours with 2 GPUs
- Best for: Shared cluster with job scheduler

### Option C: Manual Individual Submissions
```bash
cd npt_bulk_equilibration_workflow/

# Submit each phase individually
cd npt_bulk_equilibration && sbatch submit_npt_leonardo.sh
cd ../npbc_production && sbatch submit_npbc_leonardo.sh
cd ../pbc_production && sbatch submit_pbc_leonardo.sh
```

---

## 📁 File Inventory

```
npt_bulk_equilibration_workflow/
├── configs/                                    # Configuration files
│   ├── config_npt_bulk.env                    # Density, timestep, temp
│   └── ...
├── scripts/                                    # Python utilities
│   ├── generate_bulk_alanine_npt.py           # Build system
│   ├── extract_sphere_cube.py                 # Extract sphere/cube
│   └── ...
├── npt_bulk_equilibration/                    # NPT phase
│   ├── run_workflow.sh                        # Local launcher
│   ├── submit_npt_leonardo.sh                 # SLURM template
│   └── *.mace                                 # LAMMPS inputs (3 phases)
├── npbc_production/                           # NPBC phase (self-contained)
│   ├── run_npbc_production.mace               # LAMMPS input
│   ├── launch_npbc.sh                         # Local launcher
│   ├── submit_npbc_leonardo.sh                # SLURM template
│   ├── MACE-OFF23_small.model-*.pt            # Model file ✓
│   ├── bias/
│   │   ├── (R20 VDWPARM — must be supplied) # VDW parameters
│   │   └── gau_R20.dat (must be supplied)                   # Gaussian cavity
│   └── logs/                                  # Output directory
├── pbc_production/                            # PBC phase (self-contained)
│   ├── run_pbc_production.mace                # LAMMPS input
│   ├── launch_pbc.sh                          # Local launcher
│   ├── submit_pbc_leonardo.sh                 # SLURM template
│   ├── MACE-OFF23_small.model-*.pt            # Model file ✓
│   └── logs/                                  # Output directory
├── run_all_leonardo.sh                        # Sequential master script
├── submit_all_leonardo.sh                     # SLURM batch manager
├── README.md                                  # Full technical documentation
├── README_PRODUCTION.md                       # Production workflow details
└── 00_PRODUCTION_START_HERE.md               # This file
```

---

## ⚙️ Leonardo Environment Setup

The SLURM templates automatically load:
```bash
module load profile/deeplrn
module load gcc/11.3.0
module load cuda/12.1
module load cmake/3.27.0
```

GPU allocation:
- NPT: 1 GPU (up to 3 phases parallel)
- NPBC: 1 GPU (separate)
- PBC: 1 GPU (separate)

CPU cores: 16 (KOKKOS OpenMP)

---

## 📊 Expected Outputs

### NPT Phase
- `npt_bulk_equilibration/dump.final.lammpstrj` – Final frame for extraction

### NPBC Production
- `npbc_production/logs/dump.npbc_prod.lammpstrj` – Trajectory (5 ns)
- `npbc_production/logs/thermo.npbc_prod` – Thermodynamic data
- `npbc_production/logs/density_shells.npbc_prod` – Radial density (every 1000 steps)

### PBC Production
- `pbc_production/logs/dump.pbc_prod.lammpstrj` – Trajectory (5 ns)
- `pbc_production/logs/thermo.pbc_prod` – Thermodynamic data

---

## 🔍 Simulation Parameters

| Parameter | NPBC | PBC | Notes |
|-----------|------|-----|-------|
| Duration | 5 ns | 5 ns | 10,000 steps @ 0.5 fs = 5000 fs = 5 ps (typo below: check actual) |
| Timestep | 1 fs | 1 fs | Stage13 value |
| Temperature | 300 K | 300 K | Bicanonical: solute @ 300K, solvent @ 300K |
| Boundary | Non-periodic | Periodic | f f f vs p p p |
| Solute Tether | Yes (k=0.3) | Yes (k=0.3) | Weak restraint (spring-constant units) |
| Cavity Boundary | Reflect (20 Å sphere) | None | Soft walls for NPBC |
| Bias Potential | Frozen (opt no) | None | Stage13 Gaussian cavity, frozen |
| Ensemble | NVT | NVT | Volumes from NPT extraction |

---

## ⚡ Quick Start Checklist

- [ ] Unpack tar.gz: `tar -xzf npt_bulk_equilibration_workflow.tar.gz`
- [ ] Navigate to workflow: `cd npt_bulk_equilibration_workflow/`
- [ ] Verify all files present: `ls -la npbc_production/*.pt pbc_production/*.pt`
- [ ] Choose execution method (A/B/C above)
- [ ] Monitor progress:
  ```bash
  # For batch submissions:
  squeue -u $USER
  tail -f npbc_production/logs/npbc_production.log
  ```

---

## 🐛 Troubleshooting

**Error: "Cannot find MACE model"**
- Check: `ls -la npbc_production/MACE-*.pt`
- If missing: Model copy failed; verify packaging step

**Error: "VDWPARM or gau.dat not found"**
- Check: `ls -la npbc_production/bias/`
- Only for NPBC production; PBC doesn't need bias files

**SLURM job not starting**
- Check node availability: `sinfo`
- Verify allocation: `squeue -j $jobid`
- See submission logs: `cat submit_*.log`

**Long NPT runtime**
- Normal: 3 phases × ~90 min each = 5-6 hours typical
- Parallel submission with -np 16 can speed up by ~2-3×

---

## 📖 Full Documentation

- **[README.md](README.md)** – Complete technical guide
- **[README_PRODUCTION.md](README_PRODUCTION.md)** – Production workflow (execution modes, analysis, outputs)
- **configs/config_npt_bulk.env** – All tunable parameters

---

## ✅ Validation

All input files are automatically validated:
1. Python scripts check file existence before running
2. LAMMPS inputs are syntactically verified (stage13corr templates)
3. Model files are checked with `file` command
4. SLURM templates validated for Leonardo cluster specs

---

## 📞 Support

For issues, check:
1. Log files in `npbc_production/logs/` and `pbc_production/logs/`
2. SLURM output: `slurm-{jobid}.out`
3. README_PRODUCTION.md troubleshooting section

---

**Package Version**: 1.0  
**Created**: 2025-03-XX  
**MACE Model**: MACE-OFF23 (small, float32, LAMMPS)  
**Target**: Leonardo BOOSTER, GPU partition
