# NPT Workflow Extended - NPBC & PBC Production Runs

**Date:** 2026-03-24  
**Scope:** Complete workflow from bulk NPT to NPBC/PBC production on Leonardo BOOSTER

---

## What's New

The workflow now includes **full production simulation capabilities**:

### NPBC Production (`npbc_production/`)
- **System:** 15 Å sphere from NPT extraction
- **Boundary:** Non-periodic, reflective sphere (`cavity/reflect`)
- **Bias:** Frozen mean-field from stage13 (`opt no`)
- **Duration:** 5 ns production
- **Output:** Trajectory, density shells, final structure

### PBC Production (`pbc_production/`)
- **System:** Equivalent-volume cube from NPT extraction
- **Boundary:** Periodic cubic box with alanine tethered at box center
- **Bias:** None (direct comparison)
- **Duration:** 5 ns production
- **Output:** Trajectory, final structure

Both production runs use **identical MACE-OFF23 model**, extracted from same NPT frame, same temperature (300K).

---

## Complete Workflow Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│ STEP 1: NPT Bulk Equilibration (1.1 ns, ~2.5–3 hours)      │
├──────────────────────────────────────────────────────────────┤
│ Phase 1: Minimize + warmup (100 ps)                         │
│ Phase 2: NPT equilibration (500 ps)                         │
│ Phase 3: NPT production (500 ps)                            │
│ ↓                                                            │
│ Extract: 15 Å NPBC sphere + equiv. PBC cube                │
└──────────────────────────────────────────────────────────────┘
                         ↓
        ┌────────────────┴────────────────┐
        ↓                                 ↓
┌─────────────────────────┐    ┌──────────────────────┐
│ STEP 2: NPBC Production │    │ STEP 3: PBC Prod.    │
│ (5 ns, ~3–4 hours)      │    │ (5 ns, ~3–4 hours)  │
├─────────────────────────┤    ├──────────────────────┤
│ • Frozen sphere bias    │    │ • Periodic box       │
│ • cavity/reflect        │    │ • No bias            │
│ • Separate thermostats  │    │ • Separate thermosts │
│ → NPBC trajectory       │    │ → PBC trajectory     │
│ → Density shells        │    │                      │
└─────────────────────────┘    └──────────────────────┘
        ↓                                ↓
        └────────────────┬───────────────┘
                         ↓
        ┌────────────────────────────────┐
        │ ANALYSIS: NPBC vs PBC Compare  │
        │ • Conformations (dihedrals)    │
        │ • Solvation structure (RDF)    │
        │ • Dynamics (diffusion)         │
        │ • Free energies                │
        └────────────────────────────────┘
```

---

## File Structure

```
npt_bulk_equilibration_workflow/
├── configs/config_npt_bulk.env              Configuration (density, runtime)
├── scripts/
│   ├── generate_bulk_alanine_npt.py        Build bulk system
│   ├── extract_sphere_cube.py              Extract sphere + cube
│   └── run_workflow.sh                     Master NPT launcher
│
├── input_templates/
│   ├── 01_minimize_warmup_npt.mace         Phase 1
│   ├── 02_npt_equilibration.mace           Phase 2
│   └── 03_npt_production.mace              Phase 3
│
├── npbc_production/                        ← NEW
│   ├── MACE-OFF23_small.model-mliap_lammps_float32.pt  (Model)
│   ├── bias/
│   │   ├── VDWPARM_R15_S0125_step5000_stage13_outerSingles41_60.dat
│   │   └── gau_stage13.dat                 (Frozen bias)
│   ├── run_npbc_production.mace            Input script
│   ├── launch_npbc.sh                      Local launcher
│   ├── submit_npbc_leonardo.sh             SLURM template
│   └── logs/                               (created on run)
│
├── pbc_production/                         ← NEW
│   ├── MACE-OFF23_small.model-mliap_lammps_float32.pt  (Model)
│   ├── run_pbc_production.mace             Input script
│   ├── launch_pbc.sh                       Local launcher
│   ├── submit_pbc_leonardo.sh              SLURM template
│   └── logs/                               (created on run)
│
├── runs/
│   ├── data/
│   │   ├── alanine_cavity_R15_from_npt.data     (NPBC input)
│   │   └── alanine_pbc_from_npt.data            (PBC input)
│   └── logs/                                    (NPT logs)
│
├── run_all_leonardo.sh                     ← NEW: Sequential script
├── submit_all_leonardo.sh                  ← NEW: SLURM batch manager
└── README_PRODUCTION.md                    ← NEW: This file
```

---

## Leonardo BOOSTER Workflow

### Option A: Sequential Submission (Recommended)

Best for managing resources efficiently on Leonardo.

```bash
# 1. Transfer package
scp npt_workflow_leonardo_*.tar.gz utente@leonardo.cineca.it:/work/
tar xzf npt_workflow_leonardo_*.tar.gz
cd npt_bulk_equilibration_workflow

# 2. Run all steps sequentially (direct execution)
export LMP_BIN=/path/to/leonardo/lmp
bash run_all_leonardo.sh
```

**Total time:** 9–11 hours continuous GPU

### Option B: SLURM Batch Submission (Parallel Jobs)

Best for handling job queue and fault recovery.

```bash
# 1. Edit account name in submit_all_leonardo.sh
nano submit_all_leonardo.sh
# Change: ACCOUNT="<YOUR_ACCOUNT>"

# 2. Submit batch
bash submit_all_leonardo.sh

# 3. Monitor
squeue -j <job_id>
tail -f npbc_production/logs/npbc_prod_*.log
tail -f pbc_production/logs/pbc_prod_*.log
```

**Job dependencies:**
- NPT job runs immediately (8 hours)
- NPBC + PBC jobs start after NPT completion (both ~4 hours, parallel)

### Option C: Individual Jobs

Run each phase separately.

```bash
# NPT bulk
cd npt_bulk_equilibration_workflow
bash run_workflow.sh

# NPBC production (after NPT completes)
cd npbc_production
export LMP_BIN=/path/to/lmp
sbatch submit_npbc_leonardo.sh

# PBC production (can run in parallel with NPBC)
cd pbc_production
export LMP_BIN=/path/to/lmp
sbatch submit_pbc_leonardo.sh
```

---

## Detailed Steps

### 1. Prepare Workflow (Local Machine)

```bash
cd npt_bulk_equilibration_workflow
bash package_for_leonardo.sh

# Output: /tmp/npt_workflow_leonardo_*.tar.gz (~150 MB with models)
```

### 2. Transfer to Leonardo

```bash
scp /tmp/npt_workflow_leonardo_*.tar.gz utente@leonardo.cineca.it:/work/
```

### 3. On Leonardo: Extract & Configure

```bash
cd /work/
tar xzf npt_workflow_leonardo_*.tar.gz
cd npt_bulk_equilibration_workflow

# Update LAMMPS path in scripts
export LMP_BIN="/path/to/leonardo/lmp"

# Option: Update SLURM account
nano submit_all_leonardo.sh
# Change: ACCOUNT="your_account"
```

### 4. Execute

**Method 1 (Recommended): Sequential**
```bash
bash run_all_leonardo.sh
```

**Method 2: SLURM Batch**
```bash
bash submit_all_leonardo.sh
```

**Method 3: Individual Steps**
```bash
# Run NPT
bash run_workflow.sh

# After NPT: Run NPBC
cd npbc_production && sbatch submit_npbc_leonardo.sh

# After NPT: Run PBC (parallel with NPBC)
cd pbc_production && sbatch submit_pbc_leonardo.sh
```

### 5. Monitor Progress

```bash
# Check NPBC log
tail -f npbc_production/logs/npbc_prod.log

# Check PBC log
tail -f pbc_production/logs/pbc_prod.log

# Check job status
squeue -u $USER
```

### 6. Retrieve Results

```bash
# Download trajectories
scp utente@leonardo.cineca.it:/work/npt_workflow/npbc_production/traj_*.dump ./

# Download final structures
scp utente@leonardo.cineca.it:/work/npt_workflow/npbc_production/alanine_*_final.data ./
scp utente@leonardo.cineca.it:/work/npt_workflow/pbc_production/alanine_*_final.data ./
```

---

## Output Files

### After NPT (runs/data/)

```
alanine_cavity_R15_from_npt.data         (1402 atoms, NPBC sphere)
alanine_pbc_from_npt.data                (1402 atoms, PBC cube)
bulk_water_alanine_npt_final.data        (NPT frame before extraction)
```

### After NPBC Production (npbc_production/)

```
traj_alanine_nbpc_prod.dump              (5 ns trajectory)
dens_shells_alanine_nbpc_prod.dat        (Density shells every 1 ps)
gau_alanine_nbpc_prod_final.out          (Final Gaussian bias output)
alanine_nbpc_prod_final.data             (Final structure)
restart_alanine_nbpc_prod_final.lammps   (Restart for continuation)
npbc_prod.log                            (LAMMPS output log)
```

### After PBC Production (pbc_production/)

```
traj_alanine_pbc_prod.dump               (5 ns trajectory)
alanine_pbc_prod_final.data              (Final structure)
restart_alanine_pbc_prod_final.lammps    (Restart for continuation)
pbc_prod.log                             (LAMMPS output log)
```

---

## Runtime Estimates

| Phase | Duration | GPU Time | Total for 1 GPU |
|-------|----------|----------|-----------------|
| NPT minimize + warmup | 100 ps | ~10 min | 10 min |
| NPT equilibration | 500 ps | 60–90 min | 60–90 min |
| NPT production | 500 ps | 60–90 min | 60–90 min |
| Extraction | - | <1 min | <1 min |
| **NPBC production** | 5 ns | 3–4 hours | 3–4 hours |
| **PBC production** | 5 ns | 3–4 hours | 3–4 hours |
| | | | |
| **Sequential (1 GPU)** | **11.1 ns** | - | **9–11 hours** |
| **Parallel (2 GPUs)** | **11.1 ns** | - | **6–7 hours** |

---

## Key Differences: NPBC vs PBC

| Aspect | NPBC | PBC |
|--------|------|-----|
| **Boundary** | Non-periodic sphere (R=15 Å) | Periodic cubic box (edge≈24.2 Å) |
| **Model** | MACE-OFF23 | MACE-OFF23 |
| **Bias** | Frozen mean-field (opt no) | None |
| **Thermostat** | NVT, separate solute/solvent | NVT, separate solute/solvent |
| **Anchoring** | Spring tether (k=0.3) | None (periodic) |
| **Solute drift** | Controlled by spring | Periodic image tracking |
| **Density control** | Mean-field sphere + cavity/reflect | Periodic box density |
| **Output** | Trajectory + density shells | Trajectory only |

---

## Analysis After Production

### Comparing NPBC vs PBC

```bash
# Extract conformational properties
python3 analysis/compare_conformations.py \
    npbc_production/traj_alanine_nbpc_prod.dump \
    pbc_production/traj_alanine_pbc_prod.dump

# Compute radial distribution functions
python3 analysis/compute_rdf.py \
    npbc_production/traj_alanine_nbpc_prod.dump \
    pbc_production/traj_alanine_pbc_prod.dump

# Compute solute translational diffusion
python3 analysis/compute_diffusion.py \
    npbc_production/traj_alanine_nbpc_prod.dump \
    pbc_production/traj_alanine_pbc_prod.dump
```

---

## Customization

### Extend Production Time

```bash
# NPBC: Edit npbc_production/run_npbc_production.mace
variable            prod_steps       index 10000000  # 10 ns instead of 5 ns

# PBC: Edit pbc_production/run_pbc_production.mace
variable            prod_steps       index 10000000  # 10 ns instead of 5 ns
```

### Adjust Temperature

```bash
# Edit both production scripts
variable            T                equal 310.0    # 310K instead of 300K
```

### Modify Trajectory Output Stride

```bash
# Default: 500 steps = 0.5 ps between frames
variable            dump_stride      index 250      # 0.25 ps between frames (larger files)
variable            dump_stride      index 1000     # 1.0 ps between frames (smaller files)
```

---

## Troubleshooting

### "LAMMPS not found on Leonardo"

```bash
# Load module or set path
module load lammps
export LMP_BIN=$(which lmp)

# Or: Full path
export LMP_BIN="/global/software/leonardo/lammps/build/lmp"
```

### "Model file not found"

Verify MACE model is copied:
```bash
ls -lh npbc_production/MACE-OFF23_small.model-mliap_lammps_float32.pt
ls -lh pbc_production/MACE-OFF23_small.model-mliap_lammps_float32.pt
```

Both should be ~500 MB.

### "NPT extraction failed"

```bash
# Check NPT logs
tail -100 runs/logs/phase3_npt_prod.log

# Verify extraction script ran
ls -la runs/data/
```

### "Production run not using GPU"

```bash
# Check GPU visibility
nvidia-smi

# Set Leonardo GPU env vars
export CUDA_VISIBLE_DEVICES=0
module load profile/deeplrn cuda
```

---

## Next Steps

1. **Transfer package** to Leonardo
2. **Run full workflow** (Option A/B/C above)
3. **Download trajectories** after completion
4. **Analyze results** (compare NPBC vs PBC)

---

## Support

See main README.md for detailed technical reference and full troubleshooting guide.

**Quick reference files:**
- `00_START_HERE.txt` — Quick overview
- `QUICK_START.md` — 30-second reference
- `USER_GUIDE.md` — Step-by-step
- `README.md` — Full technical details
- `IMPLEMENTATION_SUMMARY.md` — Design rationale

---

**Ready to run on Leonardo? Start with:**

```bash
bash submit_all_leonardo.sh
```

or

```bash
bash run_all_leonardo.sh
```
