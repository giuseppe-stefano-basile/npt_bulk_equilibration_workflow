#!/bin/bash
# Package NPT workflow for transfer to Leonardo BOOSTER
# Creates a self-contained tar.gz with all inputs, scripts, and docs

set -e

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "${WORKFLOW_DIR}")"
PACKAGE_DIR="/tmp/npt_workflow_package_$(date +%Y%m%d_%H%M%S)"

echo "========================================"
echo "NPT Workflow Packaging for Leonardo"
echo "========================================"
echo "Source: ${WORKFLOW_DIR}"
echo "Package: ${PACKAGE_DIR}"
echo ""

# Create package structure
mkdir -p "${PACKAGE_DIR}/npt_bulk_equilibration_workflow"
cd "${PACKAGE_DIR}"

# Copy all necessary files
echo "[1/4] Copying workflow files..."
cp -r "${WORKFLOW_DIR}/configs" npt_bulk_equilibration_workflow/
cp -r "${WORKFLOW_DIR}/scripts" npt_bulk_equilibration_workflow/
cp -r "${WORKFLOW_DIR}/input_templates" npt_bulk_equilibration_workflow/
cp -r "${WORKFLOW_DIR}/analysis_tools" npt_bulk_equilibration_workflow/
cp -r "${WORKFLOW_DIR}/systems" npt_bulk_equilibration_workflow/
cp -r "${WORKFLOW_DIR}/npbc_production" npt_bulk_equilibration_workflow/
cp -r "${WORKFLOW_DIR}/pbc_production" npt_bulk_equilibration_workflow/
cp "${WORKFLOW_DIR}/run_workflow.sh" npt_bulk_equilibration_workflow/
cp "${WORKFLOW_DIR}/run_all_leonardo.sh" npt_bulk_equilibration_workflow/
cp "${WORKFLOW_DIR}/submit_all_leonardo.sh" npt_bulk_equilibration_workflow/
cp "${WORKFLOW_DIR}/README.md" npt_bulk_equilibration_workflow/
cp "${WORKFLOW_DIR}/README_PRODUCTION.md" npt_bulk_equilibration_workflow/

echo "✓ Workflow structure copied (including production folders)"

# Create runs directories
echo "[2/4] Creating run directories..."
mkdir -p npt_bulk_equilibration_workflow/runs/{data,logs}
touch npt_bulk_equilibration_workflow/runs/data/.gitkeep
touch npt_bulk_equilibration_workflow/runs/logs/.gitkeep
echo "✓ Run directories created"

# Create Leonardo-specific submission script
echo "[3/4] Creating Leonardo submission script..."
cat > npt_bulk_equilibration_workflow/submit_leonardo.sh << 'EOF'
#!/bin/bash
# Example SLURM submission script for Leonardo BOOSTER
# Adjust --time, --gres, --cpus-per-task as needed

#SBATCH --job-name=npt_bulk_ala2
#SBATCH --time=10:00:00
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --partition=boost_usr_prod
#SBATCH --account=<YOUR_ACCOUNT>
#SBATCH --mail-type=END,FAIL

set -euo pipefail

cd $SLURM_SUBMIT_DIR
export WORKFLOW_DIR="$PWD/npt_bulk_equilibration_workflow"
source "$WORKFLOW_DIR/configs/config_npt_bulk.env"
source "$WORKFLOW_DIR/scripts/leonardo_env.sh"
setup_leonardo_environment
check_lammps_runtime "$LMP_BIN"

echo "Starting NPT workflow on $(date)"
echo "GPU: $CUDA_VISIBLE_DEVICES"
bash "$WORKFLOW_DIR/run_workflow.sh"
echo "Completed on $(date)"
EOF

chmod +x npt_bulk_equilibration_workflow/submit_leonardo.sh
echo "✓ Leonardo submission script created"

# Create manifest
echo "[4/4] Creating manifest..."
cat > MANIFEST.txt << EOF
NPT Bulk Equilibration Workflow Package
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Source: ${WORKFLOW_DIR}

=== CONTENTS ===

1. npt_bulk_equilibration_workflow/
   ├── README.md                          Main documentation
   ├── run_workflow.sh                    Master launcher script
   ├── submit_leonardo.sh                 SLURM submission script (Leonardo)
   
   ├── configs/
   │   └── config_npt_bulk.env            Configuration file (edit for Leonardo)
   │
   ├── scripts/
   │   ├── generate_bulk_alanine_npt.py   Build bulk system
   │   ├── extract_sphere_cube.py         Extract sphere/cube from NPT
   │   └── run_workflow.sh (symlink)
   │
   ├── input_templates/
   │   ├── 01_minimize_warmup_npt.mace    Phase 1: minimize + warmup
   │   ├── 02_npt_equilibration.mace      Phase 2: NPT eq (500 ps)
   │   └── 03_npt_production.mace         Phase 3: NPT prod (500 ps)
   │
   ├── analysis_tools/
   │   └── analyze_npt_convergence.py     Parse LAMMPS logs
   │
   ├── systems/
   │   └── ala2_seed.pdb                  Alanine dipeptide structure
   │
   └── runs/ (created during workflow)
       ├── data/                          Output .data files
       ├── logs/                          LAMMPS log files
       └── *.mace, restart_*.lammps       Runtime files (temporary)

=== QUICK START (Leonardo) ===

1. Transfer package:
   scp -r npt_bulk_equilibration_workflow/ \
       utente@leonardo.cineca.it:/path/to/

2. Prepare environment:
   cd npt_bulk_equilibration_workflow
   # Environment is loaded by scripts/leonardo_env.sh from config_npt_bulk.env

3. Verify/update config:
   cat configs/config_npt_bulk.env
   # Edit if needed: MACE_VENV_PATH, PYLIBDIR, PLUMED_ROOT, LAMMPS_ROOT, LMP_BIN

4. Submit job:
   sbatch submit_leonardo.sh
   # Or run directly: bash run_workflow.sh

5. Monitor:
   tail -f runs/logs/phase*.log

=== OUTPUT FILES ===

After successful workflow:
  - runs/data/alanine_cavity_R20_from_npt.data      (NPBC 20 Å sphere)
  - runs/data/alanine_pbc_cube40_from_npt.data       (PBC 40 Å cube)
  - runs/logs/phase{1,2,3}_*.log                    (diagnostics)
  - runs/traj_bulk_npt_*.dump                       (trajectories)
  - runs/restart_npt_phase*.lammps                  (checkpoints)

=== KEY PARAMETERS ===

Target density (from stage13):
  rho0 = 0.037235960250849326 mol/Å³
  rho_gcc = 1.11391659 g/cm³

System size:
  Bulk waters: 3800
  Alanine: 22 atoms (frozen during NPT)
  Total atoms: ~11,422

Extraction targets:
  NPBC sphere: R = 20 Å
  PBC cube: edge = 40 Å (encloses 20 Å sphere)

Runtime (GPU):
  Phase 1 (minimize + warmup): ~10 min
  Phase 2 (NPT eq): ~60–90 min
  Phase 3 (NPT prod): ~60–90 min
  Extraction: <1 min
  Total: ~2.5–3 hours

=== SUPPORT ===

Check README.md for detailed documentation.
For Leonardo-specific issues, see submit_leonardo.sh comments.

EOF

echo "✓ Manifest created"
echo ""

# Create checksums
echo "Computing file checksums..."
find npt_bulk_equilibration_workflow -type f -not -path "*/.*" | sort | xargs md5sum > CHECKSUMS.md5
echo "✓ Checksums saved"

# Create tarball
echo ""
TARNAME="npt_workflow_leonardo_$(date +%Y%m%d_%H%M%S).tar.gz"
echo "Creating archive: ${TARNAME}"
tar czf "${TARNAME}" \
    npt_bulk_equilibration_workflow/ \
    MANIFEST.txt \
    CHECKSUMS.md5

SIZE=$(du -h "${TARNAME}" | cut -f1)
echo "✓ Archive created: ${SIZE}"
echo ""

# Final summary
echo "========================================"
echo "Packaging Complete!"
echo "========================================"
echo ""
echo "Package location: ${PACKAGE_DIR}/${TARNAME}"
echo "Size: ${SIZE}"
echo ""
echo "To transfer to Leonardo:"
echo "  scp ${PACKAGE_DIR}/${TARNAME} utente@leonardo.cineca.it:/path/to/"
echo ""
echo "Then on Leonardo:"
echo "  tar xzf ${TARNAME}"
echo "  cd npt_bulk_equilibration_workflow"
echo "  sbatch submit_leonardo.sh"
echo ""
echo "Files ready in: ${PACKAGE_DIR}/"
echo ""
