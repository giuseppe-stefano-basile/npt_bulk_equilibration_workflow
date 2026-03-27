# NPT Bulk Equilibration Workflow - User Guide

**Date Created:** 2026-03-24  
**Status:** ✅ Complete and ready for use  
**Location:** `/home/utente/giuseppe/ML_Embedding/MACE/Alanine_dipeptide/MACE-OFF_2023_small/npt_bulk_equilibration_workflow/`

---

## What This Workflow Does

This self-contained package generates **two systems for direct comparison:**

### System A: NPBC (Non-Periodic Sphere)
- **Geometry:** 15 Å radius sphere around alanine dipeptide
- **Atoms:** ~1402 total (22 solute + ~1380 water)
- **Boundary:** Reflective sphere (`cavity/reflect` in LAMMPS)
- **Use:** NPBC production with frozen mean-field bias
- **Output file:** `runs/data/alanine_cavity_R15_from_npt.data`

### System B: PBC (Periodic Cube)  
- **Geometry:** Cubic box with equivalent volume (~4600 Å³)
- **Atoms:** ~1402 total (22 solute + ~1380 water)
- **Boundary:** Periodic (standard NVT/NPT)
- **Use:** PBC production for direct NPBC↔PBC comparison
- **Output file:** `runs/data/alanine_pbc_from_npt.data`

**Both systems:**
- Derived from identical NPT-equilibrated bulk
- Same solute configuration (alanine COM)
- Same target density: `0.037235960250849326 mol/Å³` (from stage13 optimization)
- Ready for production runs

---

## Quick Start (3 Commands)

```bash
# 1. Enter workflow directory
cd npt_bulk_equilibration_workflow

# 2. Review configuration (already set to correct density)
cat configs/config_npt_bulk.env

# 3. Run full pipeline (generates systems and extracts them)
bash run_workflow.sh
```

**Time:** ~2.5–3 hours on GPU (NVIDIA A100/H100)

**Outputs:** 
```
runs/data/
├── alanine_cavity_R15_from_npt.data    ← Use for NPBC production
└── alanine_pbc_from_npt.data           ← Use for PBC production
```

---

## Documentation Files

| File | Purpose |
|------|---------|
| **README.md** | Full technical documentation (phases, parameters, troubleshooting) |
| **QUICK_START.md** | 30-second reference guide |
| **IMPLEMENTATION_SUMMARY.md** | Design decisions and architecture |
| **USER_GUIDE.md** | This file |

**Start here:** `QUICK_START.md` for immediate use, `README.md` for details.

---

## Step-by-Step Workflow

### Phase 1: System Generation (1 min)
```
generate_bulk_alanine_npt.py
└─ Creates: bulk_water_alanine_npt.data
   (3800 water molecules + alanine, 11,400+ atoms)
```

### Phase 2: Energy Minimization + Warmup (10 min)
```
LAMMPS: 01_minimize_warmup_npt.mace
└─ Minimizes energy
└─ Freezes solute
└─ Ramps temperature 25K → 200K
└─ Outputs: restart_npt_phase1_warmup.lammps
```

### Phase 3: NPT Equilibration (60–90 min)
```
LAMMPS: 02_npt_equilibration.mace
└─ Runs NPT (P=1 atm, T=300K) for 500 ps
└─ Equilibrates box size and density
└─ Outputs: restart_npt_phase2_eq_final.lammps
```

### Phase 4: NPT Production (60–90 min)
```
LAMMPS: 03_npt_production.mace
└─ Continues NPT for 500 ps
└─ Collects statistics
└─ Outputs: 
   ├─ restart_npt_phase3_prod_final.lammps
   ├─ bulk_water_alanine_npt_final.data
   └─ traj_bulk_npt_phase3_prod.dump
```

### Phase 5: Extraction (<1 min)
```
extract_sphere_cube.py
├─ Reads final NPT frame
├─ Computes alanine COM
├─ Extracts 15 Å sphere → alanine_cavity_R15_from_npt.data
└─ Extracts equiv. cube → alanine_pbc_from_npt.data
```

---

## Key Parameters (All Pre-Configured)

| Parameter | Value | Source |
|-----------|-------|--------|
| **Density** | 0.037235960250849326 mol/Å³ | stage13_runtime.env |
| **Density (g/cm³)** | 1.11391659 | Equivalent |
| **Bulk waters** | 3800 | Config (adjustable) |
| **Alanine atoms** | 22 | ala2_seed.pdb |
| **Temperature** | 300 K | Standard |
| **Pressure** | 1 atm | Standard |
| **Timestep** | 1 fs | LAMMPS default |
| **Sphere radius** | 15 Å | NPBC target |
| **Cube edge** | 24.2 Å | Equiv. volume |

**All locked in:** `configs/config_npt_bulk.env`

---

## For Leonardo BOOSTER

### Method 1: Quick Package & Transfer

```bash
# On local machine:
cd npt_bulk_equilibration_workflow
bash package_for_leonardo.sh

# Output: /tmp/npt_workflow_leonardo_YYYYMMDD_HHMMSS.tar.gz (~50 MB)
# Transfer:
scp /tmp/npt_workflow_leonardo_*.tar.gz utente@leonardo.cineca.it:/work/

# On Leonardo:
tar xzf npt_workflow_leonardo_*.tar.gz
cd npt_bulk_equilibration_workflow
sbatch submit_leonardo.sh
```

### Method 2: Edit Config & Submit Directly

```bash
# Edit for Leonardo paths
nano configs/config_npt_bulk.env
# Update: LMP_BIN, CUDA_VISIBLE_DEVICES

# Submit
sbatch submit_leonardo.sh
```

### Method 3: Run Directly (No SLURM)

```bash
bash run_workflow.sh
```

---

## Output Interpretation

### Primary Outputs (Use These)

```
runs/data/alanine_cavity_R15_from_npt.data
├─ Atoms: 1402 (22 solute + 1380 water)
├─ Boundary: Non-periodic (fits R=15 Å sphere)
└─ Use: NPBC production with cavity/reflect

runs/data/alanine_pbc_from_npt.data  
├─ Atoms: 1402 (22 solute + 1380 water)
├─ Boundary: Periodic (cubic box)
└─ Use: PBC production (NVT/NPT)
```

### Diagnostic Outputs (Check These)

```
runs/logs/
├─ phase1_minimize_warmup.log       → Check: minimization converged?
├─ phase2_npt_eq.log                → Check: density converging? pressure stable?
└─ phase3_npt_prod.log              → Check: final density, box size

runs/
├─ traj_bulk_npt_phase2_eq.dump     → View in VMD to check equilibration
├─ traj_bulk_npt_phase3_prod.dump   → Full production trajectory
└─ bulk_water_alanine_npt_final.data → NPT frame before extraction
```

### Analysis Tool

```bash
# Check convergence in phase 2
python3 analysis_tools/analyze_npt_convergence.py runs/logs/phase2_npt_eq.log --phase eq

# Check convergence in phase 3
python3 analysis_tools/analyze_npt_convergence.py runs/logs/phase3_npt_prod.log --phase prod
```

**Expected output:**
```
Temperature: 300.0 ± 0.5 K (±0.2%)
Pressure: ~1.0 ± 50 atm
Density: 1.114 ± 0.003 g/cm³ (<0.3% variation)
```

---

## Customization

Edit `configs/config_npt_bulk.env` to adjust:

### Increase Bulk System (Better Statistics, Slower)
```bash
export N_WATER_BULK="5000"          # ~40 Å box vs. current ~35 Å
# Runtime: +30 min
```

### Extend Production (More Data)
```bash
export STEPS_PROD_NPT="1000000"     # 1 ns instead of 500 ps
# Runtime: +60 min
```

### Different Sphere Size
```bash
# After running, use extraction script directly:
python3 scripts/extract_sphere_cube.py \
    --npt-data runs/data/bulk_water_alanine_npt_final.data \
    --sphere-r 12.0 \                # Different radius
    --cube-edge 19.5                 # Equiv. cube
```

### Use Different GPU
```bash
export CUDA_VISIBLE_DEVICES="1"     # GPU 1 instead of 0
```

---

## Using the Output Systems

### NPBC Production (Cavity Sphere)

```bash
# 1. Copy system to NPBC folder
cp runs/data/alanine_cavity_R15_from_npt.data \
   /path/to/npbc_production/

# 2. Run NPBC with frozen bias from stage13
# (Use stage13corr input files with opt no)
lmp -in run_nvt_alanine_nbpc_off23_stage13_prod_frozen.mace
```

### PBC Production (Cubic Box)

```bash
# 1. Copy system to PBC folder
cp runs/data/alanine_pbc_from_npt.data \
   /path/to/pbc_production/

# 2. Run PBC with equivalent settings
lmp -in run_nvt_alanine_pbc_off23_equiv.mace
```

### Analysis

After production runs, compare:
- Solute dihedral distributions
- Solvation shell radial density
- Solute translational/rotational diffusion
- Temperature and potential energy evolution
- Free energy landscapes (if metadynamics used)

---

## Troubleshooting

### "LAMMPS not found"
```bash
# Set path in config
export LMP_BIN="/path/to/lmp"
bash run_workflow.sh
```

### "Phase 2 not converging"
```bash
# Increase bulk system or equilibration time:
export N_WATER_BULK="4500"
export STEPS_EQ_NPT="1000000"
```

### "Memory issues"
```bash
# Reduce bulk system
export N_WATER_BULK="2500"          # ~50% memory reduction
```

### "Phase 3 outputs missing"
```bash
# Check logs
tail -100 runs/logs/phase3_npt_prod.log

# Manually extract if NPT final data exists
python3 scripts/extract_sphere_cube.py \
    --npt-data runs/data/bulk_water_alanine_npt_final.data
```

---

## File Checklist

### Required Files (Pre-provided)

- [x] `configs/config_npt_bulk.env` — Configuration
- [x] `scripts/generate_bulk_alanine_npt.py` — System builder
- [x] `scripts/extract_sphere_cube.py` — Sphere/cube extractor
- [x] `input_templates/01_minimize_warmup_npt.mace` — Phase 1
- [x] `input_templates/02_npt_equilibration.mace` — Phase 2
- [x] `input_templates/03_npt_production.mace` — Phase 3
- [x] `systems/ala2_seed.pdb` — Alanine structure
- [x] `run_workflow.sh` — Master launcher
- [x] `package_for_leonardo.sh` — Packaging tool

### Created During Run

- `runs/data/alanine_cavity_R15_from_npt.data` ✓
- `runs/data/alanine_pbc_from_npt.data` ✓
- `runs/logs/phase*.log` ✓
- `runs/restart_npt_phase*.lammps` ✓
- `runs/traj_bulk_npt_*.dump` ✓

---

## Summary

### What You Get

✅ Two production-ready systems derived from identical NPT-equilibrated bulk  
✅ NPBC sphere (R=15 Å) for cavity production  
✅ PBC cube (equiv. volume) for periodic comparison  
✅ Both at exact density from stage13 optimization (0.037235960250849326 mol/Å³)  
✅ Complete documentation and packaging for Leonardo BOOSTER  

### Time Investment

- **Local review:** 5 minutes
- **Workflow run:** 2.5–3 hours (GPU)
- **Leonardo transfer & rerun:** 1 hour prep + 2.5–3 hours compute

### Next Steps

1. **Review:** `QUICK_START.md`
2. **Run locally or on Leonardo:** `bash run_workflow.sh`
3. **Check outputs:** `runs/data/*.data`
4. **Use in production:** Copy to NPBC/PBC folders
5. **Compare:** Analyze NPBC vs. PBC trajectories

---

## Contact & Questions

For detailed information, see:
- `README.md` — Full technical reference
- `IMPLEMENTATION_SUMMARY.md` — Design rationale
- Log files in `runs/logs/` — Diagnostics

---

**Ready to begin?**

```bash
cd npt_bulk_equilibration_workflow
bash run_workflow.sh
```

**Questions? Check README.md or QUICK_START.md**
