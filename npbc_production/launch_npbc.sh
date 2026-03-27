#!/bin/bash
# NPBC Production Launcher for Leonardo BOOSTER
# Pre-equilibrated sphere system with frozen mean-field bias
# Date: 2026-03-24

set -e

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NPBC_DIR="${WORKFLOW_DIR}/npbc_production"

echo "========================================"
echo "NPBC Production Launch"
echo "========================================"
echo "Workflow: ${WORKFLOW_DIR}"
echo "Run dir: ${NPBC_DIR}"
echo ""

# Check input data
if [ ! -f "${WORKFLOW_DIR}/runs/data/alanine_cavity_R15_from_npt.data" ]; then
    echo "ERROR: NPT extraction not found!"
    echo "  Expected: ${WORKFLOW_DIR}/runs/data/alanine_cavity_R15_from_npt.data"
    echo ""
    echo "Run NPT workflow first: cd ${WORKFLOW_DIR} && bash run_workflow.sh"
    exit 1
fi

cd "${NPBC_DIR}"

# Kokkos GPU flags (match reference stage13 invocation)
KOKKOS_ARGS="-k on g 1 -sf kk -pk kokkos neigh half newton on"
export OMP_NUM_THREADS=1
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
LMP="${LMP_BIN:-lmp}"
echo "LAMMPS: ${LMP}  (GPU $CUDA_VISIBLE_DEVICES)"

echo "[1/3] Checking files..."
[ -f "run_npbc_production.mace" ] || { echo "Missing run_npbc_production.mace"; exit 1; }
[ -f "MACE-OFF23_small.model-mliap_lammps_float32.pt" ] || { echo "Missing MACE model"; exit 1; }
[ -f "bias/VDWPARM_R15_S0125_step5000_stage13_outerSingles41_60.dat" ] || { echo "Missing VDWPARM"; exit 1; }
[ -f "bias/gau_stage13.dat" ] || { echo "Missing Gaussian bias"; exit 1; }
echo "✓ All files present"
echo ""

echo "[2/3] NPBC production run (5 ns, ~3–4 hours on GPU)..."
mkdir -p logs
$LMP $KOKKOS_ARGS -in run_npbc_production.mace 2>&1 | tee -a logs/npbc_prod.log

echo "[3/3] Verifying outputs..."
[ -f "traj_alanine_nbpc_prod.dump" ] && echo "✓ Trajectory: traj_alanine_nbpc_prod.dump"
[ -f "dens_shells_alanine_nbpc_prod.dat" ] && echo "✓ Density shells: dens_shells_alanine_nbpc_prod.dat"
[ -f "alanine_nbpc_prod_final.data" ] && echo "✓ Final data: alanine_nbpc_prod_final.data"
echo ""

echo "========================================"
echo "NPBC Production Complete!"
echo "========================================"
echo "Outputs in: ${NPBC_DIR}/"
echo ""
