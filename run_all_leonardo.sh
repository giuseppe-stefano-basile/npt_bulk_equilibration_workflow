#!/bin/bash
#SBATCH --nodes=1 #numero di nodi
#SBATCH --ntasks-per-node=8 #numero di processi per nodo
#SBATCH --cpus-per-task=16 #numero di processori per processi
#SBATCH --error job.err     # nome del std-error file
#SBATCH --output job.out    # nome del std-output file
#SBATCH --mem=8GB #memoria ram richiesta
#SBATCH --gpus-per-node=1  # numero di gpu per nodo richiesto       
#SBATCH --time=24:00:00 # tempo richiesto (massimo 24 h)
#SBATCH --job-name=glob_lammps # nome del lavoro
#SBATCH --account=INF26_biophys # nome del progetto con budget ore
#SBATCH --partition=boost_usr_prod  # nome partizione  
#SBATCH --mail-type=END 
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=simone.grandinetti@sns.it # mail per messaggio di fine lavoro o errore

set -e

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==============================================="
echo "COMPLETE NPT + EXTRACTION + PRODUCTION WORKFLOW"
echo "  20 Å sphere (NPBC) / 40 Å cube (PBC)"
echo "==============================================="
echo "Location: ${WORKFLOW_DIR}"
echo "Timestamp: $(date)"
echo ""

# Module environment (Leonardo)
module load profile/deeplrn
module load gcc cuda cmake

# Source config for LMP_BIN and environment variables
if [[ -f "${WORKFLOW_DIR}/configs/config_npt_bulk.env" ]]; then
    source "${WORKFLOW_DIR}/configs/config_npt_bulk.env"
    echo "✓ Configuration loaded"
fi

# Verify LAMMPS available
if [ -z "${LMP_BIN}" ]; then
    echo "ERROR: LMP_BIN not set"
    echo "  Set via: export LMP_BIN=/path/to/lmp"
    exit 1
fi
echo "LAMMPS: ${LMP_BIN}"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo ""

# ============================================================================
# STEP 1: NPT Bulk Equilibration + Extraction
# ============================================================================
echo "==============================================="
echo "STEP 1/3: NPT Bulk Equilibration + Extraction"
echo "==============================================="
cd "${WORKFLOW_DIR}"
bash run_workflow.sh

# Verify extraction
if [ ! -f "runs/data/alanine_cavity_R20_from_npt.data" ] || \
   [ ! -f "runs/data/alanine_pbc_cube40_from_npt.data" ]; then
    echo "ERROR: NPT extraction failed"
    exit 1
fi
echo "✓ Systems extracted successfully (20 Å sphere, 40 Å cube)"
echo ""

# ============================================================================
# STEP 2: NPBC Production
# ============================================================================
echo "==============================================="
echo "STEP 2/3: NPBC Pipeline (minimize → eq → prod)"
echo "==============================================="
cd "${WORKFLOW_DIR}/npbc_production"
export LMP_BIN="${LMP_BIN}"
bash launch_npbc.sh

# Verify NPBC outputs
if [ ! -f "traj_alanine_nbpc_prod.dump" ]; then
    echo "WARNING: NPBC trajectory not found"
else
    echo "✓ NPBC production successful"
fi
echo ""

# ============================================================================
# STEP 3: PBC Production
# ============================================================================
echo "==============================================="
echo "STEP 3/3: PBC Pipeline (minimize → eq → prod)"
echo "==============================================="
cd "${WORKFLOW_DIR}/pbc_production"
export LMP_BIN="${LMP_BIN}"
bash launch_pbc.sh

# Verify PBC outputs
if [ ! -f "traj_alanine_pbc_prod.dump" ]; then
    echo "WARNING: PBC trajectory not found"
else
    echo "✓ PBC production successful"
fi
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "==============================================="
echo "COMPLETE WORKFLOW FINISHED!"
echo "==============================================="
echo "Completed: $(date)"
echo ""
echo "Generated systems and trajectories:"
echo "  NPT bulk: runs/data/"
echo "    ├─ alanine_cavity_R20_from_npt.data       (NPBC 20 Å sphere)"
echo "    └─ alanine_pbc_cube40_from_npt.data       (PBC 40 Å cube)"
echo ""
echo "  NPBC production: npbc_production/"
echo "    ├─ traj_alanine_nbpc_prod.dump           (5 ns trajectory)"
echo "    ├─ dens_shells_alanine_nbpc_prod.dat      (density shells)"
echo "    └─ alanine_nbpc_prod_final.data           (final structure)"
echo ""
echo "  PBC production: pbc_production/"
echo "    ├─ traj_alanine_pbc_prod.dump            (5 ns trajectory)"
echo "    └─ alanine_pbc_prod_final.data            (final structure)"
echo ""
echo "Next: Analyze NPBC vs PBC comparison"
echo "==============================================="
