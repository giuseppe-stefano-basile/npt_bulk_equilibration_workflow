#!/bin/bash
# SLURM submission script for PBC 3-stage pipeline on Leonardo BOOSTER
# Stages: minimize → equilibration (100 ps) → production (5 ns) in 40 Å cube
#SBATCH --job-name=pbc_prod_ala2
#SBATCH --time=08:00:00
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --partition=boost_usr_prod
#SBATCH --account=<YOUR_ACCOUNT>
#SBATCH --mail-type=END,FAIL
#SBATCH --output=logs/pbc_prod_%j.log

module load profile/deeplrn
module load gcc cuda cmake

# Source config for LMP_BIN and environment variables
WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
if [[ -f "${WORKFLOW_DIR}/configs/config_npt_bulk.env" ]]; then
    source "${WORKFLOW_DIR}/configs/config_npt_bulk.env"
fi

echo "Starting PBC 3-stage pipeline (minimize → eq → prod) on GPU $CUDA_VISIBLE_DEVICES"
echo "Job ID: $SLURM_JOB_ID"
echo "Time: $(date)"
echo ""

cd "${WORKFLOW_DIR}/pbc_production"
bash launch_pbc.sh

echo ""
echo "Completed: $(date)"
