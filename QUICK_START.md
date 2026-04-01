# NPT Bulk Equilibration Workflow - QUICK START

**Date:** 2026-03-24  
**Status:** Complete implementation with all inputs for Leonardo BOOSTER transfer

---

## What You Have

A complete, self-contained workflow to:
1. **Generate** bulk water (3800 molecules) + alanine system at target density
2. **Run** 3-phase NPT protocol (100 ps warmup + 500 ps eq + 500 ps prod)
3. **Extract** 20 Å NPBC sphere and 40 Å PBC cube
4. **Package** everything for Leonardo BOOSTER

---

## Workflow Structure

```
npt_bulk_equilibration_workflow/
├── README.md                              Full documentation
├── QUICK_START.md                         This file
├── run_workflow.sh                        Master launcher
├── package_for_leonardo.sh                Packaging script
│
├── configs/
│   └── config_npt_bulk.env               Edit for Leonardo paths
│
├── scripts/
│   ├── generate_bulk_alanine_npt.py      Build system (3800 waters + ala)
│   └── extract_sphere_cube.py            Cut sphere/cube from NPT final frame
│
├── input_templates/
│   ├── 01_minimize_warmup_npt.mace       Phase 1 (100 ps)
│   ├── 02_npt_equilibration.mace         Phase 2 NPT eq (500 ps)
│   └── 03_npt_production.mace            Phase 3 NPT prod (500 ps)
│
├── analysis_tools/
│   └── analyze_npt_convergence.py        Parse LAMMPS logs for diagnostics
│
├── systems/
│   └── ala2_seed.pdb                     Alanine dipeptide structure
│
└── runs/ (created on first run)
    ├── data/                              Output .data files
    └── logs/                              LAMMPS logs & diagnostics
```

---

## 30-Second Start (Local)

```bash
cd npt_bulk_equilibration_workflow

# 1. Review config (density is already set to 0.037235960250849326 mol/Å³)
cat configs/config_npt_bulk.env

# 2. Run full workflow (REQUIRES LAMMPS + MACE)
bash run_workflow.sh

# 3. Check outputs
ls -lh runs/data/
# alanine_cavity_R20_from_npt.data     (NPBC sphere)
# alanine_pbc_cube40_from_npt.data     (PBC cube)
```

**Total time:** ~2.5–3 hours on GPU

---

## For Leonardo BOOSTER

### Step 1: Package

```bash
cd npt_bulk_equilibration_workflow
bash package_for_leonardo.sh

# Creates: /tmp/npt_workflow_leonardo_*.tar.gz
```

### Step 2: Transfer

```bash
scp /tmp/npt_workflow_leonardo_*.tar.gz utente@leonardo.cineca.it:/path/to/work/
```

### Step 3: On Leonardo, Extract & Run

```bash
cd /path/to/work/
tar xzf npt_workflow_leonardo_*.tar.gz
cd npt_bulk_equilibration_workflow

# Edit config if needed (LAMMPS path, GPU ID)
nano configs/config_npt_bulk.env

# Submit job
sbatch submit_leonardo.sh
```

### Step 4: Monitor

```bash
# Watch logs
tail -f runs/logs/phase*.log

# Check final density
grep "Final density" runs/logs/phase3_npt_prod.log
```

---

## Key Parameters

| Parameter | Value | Source |
|-----------|-------|--------|
| Target density | 0.037235960250849326 mol/Å³ | stage13 optimization |
| Bulk waters | 3800 | ~35 Å box for statistics |
| Alanine | 22 atoms (FROZEN) | ala2_seed.pdb |
| Temperature | 300 K | Standard |
| Pressure | 1 atm (NPT) | Standard |
| Sphere R | 20 Å | NPBC extraction |
| Cube edge | 40 Å | Encloses 20 Å sphere |

---

## Output Files (After Workflow)

```
runs/data/
├── alanine_cavity_R20_from_npt.data      ← Use for NPBC production
├── alanine_pbc_cube40_from_npt.data      ← Use for PBC production
└── bulk_water_alanine_npt_final.data     (Final NPT frame, for reference)

runs/logs/
├── phase1_minimize_warmup.log
├── phase2_npt_eq.log
└── phase3_npt_prod.log

runs/
├── traj_bulk_npt_phase2_eq.dump          (Trajectory for analysis)
├── traj_bulk_npt_phase3_prod.dump
└── restart_npt_phase*.lammps             (Restart points)
```

---

## Customization

Edit `configs/config_npt_bulk.env`:

```bash
# Increase/decrease bulk system size
export N_WATER_BULK="5000"              # Larger = better, slower

# Change production duration
export STEPS_PROD_NPT="1000000"         # Longer = more statistics

# Adjust GPU
export CUDA_VISIBLE_DEVICES="1"         # Different GPU ID

# For Leonardo
export LMP_BIN="/path/to/leonardo/lmp"
export CUDA_VISIBLE_DEVICES="0"
```

---

## Troubleshooting

### "Cannot find LAMMPS binary"
```bash
export LMP_BIN="/path/to/lmp"
bash run_workflow.sh
```

### "Phase 2 density not converging"
- Increase `N_WATER_BULK` to 4500–5000
- Extend `STEPS_EQ_NPT` to 1,000,000

### "High memory usage"
- Reduce `N_WATER_BULK` to 2500 (~50% reduction)

### "Phase 3 completed but outputs missing"
```bash
cd runs
grep "Final density" logs/phase3_npt_prod.log
ls -la *.data *.lammps
```

---

## What Next?

Once you have `alanine_cavity_R20_from_npt.data` and `alanine_pbc_cube40_from_npt.data`:

### NPBC Production

```bash
# Copy sphere to NPBC folder
cp runs/data/alanine_cavity_R20_from_npt.data /path/to/npbc_production/

# Run with frozen bias from stage13
lmp -in run_nvt_alanine_nbpc_off23_stage13_prod_frozen.mace
```

### PBC Production

```bash
# Copy cube to PBC folder
cp runs/data/alanine_pbc_cube40_from_npt.data /path/to/pbc_production/

# Run with equivalent settings
lmp -in run_nvt_alanine_pbc_off23_equiv.mace
```

### Analysis

Compare NPBC vs. PBC trajectories for:
- Solute conformational distributions
- First solvation shell structure
- Radial distribution functions (RDF)
- Solute translational/rotational diffusion
- Free energy landscapes

---

## Files Included

✓ **Scripts (Python)**
  - `generate_bulk_alanine_npt.py` - Build bulk system (3800 + ala)
  - `extract_sphere_cube.py` - Extract sphere/cube from NPT frame
  - `analyze_npt_convergence.py` - Parse LAMMPS logs

✓ **LAMMPS Inputs (.mace)**
  - 3-phase NPT protocol (minimize → warmup → eq → prod)
  - All with MACE-OFF23 potential pre-configured
  - Alanine frozen during NPT

✓ **Config & Docs**
  - `config_npt_bulk.env` - All parameters
  - `README.md` - Full documentation
  - `QUICK_START.md` - This file

✓ **Helper Scripts**
  - `run_workflow.sh` - Master launcher
  - `package_for_leonardo.sh` - Create tar.gz for transfer
  - `submit_leonardo.sh` - SLURM submission template

✓ **Systems**
  - `ala2_seed.pdb` - Alanine dipeptide structure

---

## Contact & Questions

See `README.md` for detailed documentation and troubleshooting.

Key resources:
- `configs/config_npt_bulk.env` - All tuneable parameters
- `input_templates/*.mace` - LAMMPS input structure
- `runs/logs/` - Diagnostics after workflow runs

---

**Ready to start?**

```bash
# Local run
cd npt_bulk_equilibration_workflow && bash run_workflow.sh

# Leonardo packaging
bash package_for_leonardo.sh
```
