#!/bin/bash
# PBC Production Launcher for Leonardo BOOSTER
# Pre-equilibrated cube system with periodic boundaries
# Date: 2026-03-24

set -e

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBC_DIR="${WORKFLOW_DIR}/pbc_production"

echo "========================================"
echo "PBC Production Launch"
echo "========================================"
echo "Workflow: ${WORKFLOW_DIR}"
echo "Run dir: ${PBC_DIR}"
echo ""

# Check input data
if [ ! -f "${WORKFLOW_DIR}/runs/data/alanine_pbc_from_npt.data" ]; then
    echo "ERROR: PBC extraction not found!"
    echo "  Expected: ${WORKFLOW_DIR}/runs/data/alanine_pbc_from_npt.data"
    echo ""
    echo "Run NPT workflow first: cd ${WORKFLOW_DIR} && bash run_workflow.sh"
    exit 1
fi

cd "${PBC_DIR}"

# Kokkos GPU flags (match reference stage13 invocation)
KOKKOS_ARGS="-k on g 1 -sf kk -pk kokkos neigh half newton on"
export OMP_NUM_THREADS=1
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
LMP="${LMP_BIN:-lmp}"
echo "LAMMPS: ${LMP}  (GPU $CUDA_VISIBLE_DEVICES)"

echo "[1/3] Checking files..."
[ -f "run_pbc_production.mace" ] || { echo "Missing run_pbc_production.mace"; exit 1; }
[ -f "MACE-OFF23_small.model-mliap_lammps_float32.pt" ] || { echo "Missing MACE model"; exit 1; }
echo "✓ All files present"
echo ""

echo "[2/3] PBC production run (5 ns, ~3–4 hours on GPU, alanine tethered at cube center)..."
mkdir -p logs
$LMP $KOKKOS_ARGS -in run_pbc_production.mace 2>&1 | tee -a logs/pbc_prod.log

echo "[3/3] Verifying outputs..."
[ -f "traj_alanine_pbc_prod.dump" ] && echo "✓ Trajectory: traj_alanine_pbc_prod.dump"
[ -f "alanine_pbc_prod_final.data" ] && echo "✓ Final data: alanine_pbc_prod_final.data"
echo ""

echo "========================================"
echo "PBC Production Complete!"
echo "========================================"
echo "Outputs in: ${PBC_DIR}/"
echo ""
