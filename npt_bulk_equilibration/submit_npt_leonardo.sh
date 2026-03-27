#!/bin/bash
#SBATCH --job-name=npt_bulk_eq
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --time=08:00:00
#SBATCH --mem=16GB
#SBATCH --partition=gpu
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# NPT Bulk Equilibration - LEONARDO BOOSTER SLURM Template
# Submits 3-phase NPT protocol for bulk water system generation
#
# Usage: sbatch submit_npt_leonardo.sh

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NPT BULK EQUILIBRATION - LEONARDO BOOSTER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SLURM Job Details:"
echo "  JobID: $SLURM_JOB_ID"
echo "  Nodes: $SLURM_NNODES"
echo "  CPUs per task: $SLURM_CPUS_PER_TASK"
echo "  GPU: $SLURM_GPUS"
echo "  Memory: $SLURM_MEM_PER_NODE MB"
echo ""

# Set up Leonardo environment
echo "Loading Leonardo modules..."
module load profile/deeplrn 2>/dev/null || true
module load gcc/11.3.0 2>/dev/null || true
module load cuda/12.1 2>/dev/null || true
module load cmake/3.27.0 2>/dev/null || true

echo "✓ Environment configured"
echo ""

# Resolve script/workflow directories robustly under sbatch spooled execution
SCRIPT_DIR=""
WORKFLOW_DIR=""

if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
    if [[ -f "${SLURM_SUBMIT_DIR}/launch_npt.sh" ]]; then
        SCRIPT_DIR="${SLURM_SUBMIT_DIR}"
        WORKFLOW_DIR="$(dirname "${SCRIPT_DIR}")"
    elif [[ -f "${SLURM_SUBMIT_DIR}/npt_bulk_equilibration/launch_npt.sh" ]]; then
        WORKFLOW_DIR="${SLURM_SUBMIT_DIR}"
        SCRIPT_DIR="${WORKFLOW_DIR}/npt_bulk_equilibration"
    fi
fi

if [[ -z "${SCRIPT_DIR}" ]]; then
    if [[ -f "${PWD}/launch_npt.sh" ]]; then
        SCRIPT_DIR="${PWD}"
        WORKFLOW_DIR="$(dirname "${SCRIPT_DIR}")"
    elif [[ -f "${PWD}/npt_bulk_equilibration/launch_npt.sh" ]]; then
        WORKFLOW_DIR="${PWD}"
        SCRIPT_DIR="${WORKFLOW_DIR}/npt_bulk_equilibration"
    else
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
    fi
fi

# Run NPT phase
echo "Starting NPT bulk equilibration..."
cd "$SCRIPT_DIR"

if [[ -x "$SCRIPT_DIR/launch_npt.sh" ]]; then
    "$SCRIPT_DIR/launch_npt.sh"
    NPT_STATUS=$?
else
    echo "[!] launch_npt.sh not executable; attempting bash..."
    bash "$SCRIPT_DIR/launch_npt.sh"
    NPT_STATUS=$?
fi

echo ""
if [[ $NPT_STATUS -eq 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ NPT PHASE COMPLETED SUCCESSFULLY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next step: Extract sphere/cube from data/bulk_water_alanine_npt_final.data"
    echo "Command: python3 ../scripts/extract_sphere_cube.py ..."
else
    echo "✗ NPT phase failed with status $NPT_STATUS"
    exit $NPT_STATUS
fi

echo ""
echo "Job completed at: $(date)"
