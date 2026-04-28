#!/bin/bash
# PBC Production Launcher for Leonardo BOOSTER
# Three-stage pipeline: minimize → equilibration → production
# 40 Å periodic cube (encloses 20 Å sphere)
# Date: 2026-04-01

set -euo pipefail

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBC_DIR="${WORKFLOW_DIR}/pbc_production"

if [[ -f "${WORKFLOW_DIR}/configs/config_npt_bulk.env" ]]; then
    source "${WORKFLOW_DIR}/configs/config_npt_bulk.env"
fi
source "${WORKFLOW_DIR}/scripts/leonardo_env.sh"
setup_leonardo_environment

echo "========================================"
echo "PBC Pipeline (minimize → eq → prod)"
echo "========================================"
echo "Workflow: ${WORKFLOW_DIR}"
echo "Run dir: ${PBC_DIR}"
echo ""

# Check input data
if [ ! -f "${WORKFLOW_DIR}/runs/data/alanine_pbc_cube40_from_npt.data" ]; then
    echo "ERROR: PBC extraction not found!"
    echo "  Expected: ${WORKFLOW_DIR}/runs/data/alanine_pbc_cube40_from_npt.data"
    echo ""
    echo "Run NPT workflow first: cd ${WORKFLOW_DIR} && bash run_workflow.sh"
    exit 1
fi

cd "${PBC_DIR}"

# Kokkos GPU flags
KOKKOS_ARGS="-k on g 1 -sf kk -pk kokkos neigh half newton on"
export OMP_NUM_THREADS=1
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
LMP="${LMP_BIN:-lmp}"
check_lammps_runtime "${LMP}"
echo "LAMMPS: ${LMP}  (GPU $CUDA_VISIBLE_DEVICES)"

echo "[1/5] Checking files..."
[ -f "run_pbc_minimize.mace" ]       || { echo "Missing run_pbc_minimize.mace"; exit 1; }
[ -f "run_pbc_equilibration.mace" ]  || { echo "Missing run_pbc_equilibration.mace"; exit 1; }
[ -f "run_pbc_production.mace" ]     || { echo "Missing run_pbc_production.mace"; exit 1; }
[ -f "MACE-OFF23_small.model-mliap_lammps_float32.pt" ] || { echo "Missing MACE model"; exit 1; }
echo "✓ All files present"
echo ""

# ── Stage 1: Minimization ────────────────────────────────────────────────────
echo "[2/5] PBC minimization (solvent relaxation around fixed alanine)..."
mkdir -p logs
"${LMP}" ${KOKKOS_ARGS} -in run_pbc_minimize.mace 2>&1 | tee -a logs/pbc_minimize.log
echo "✓ Minimization complete"
echo ""

# ── Stage 2: NVT Equilibration ───────────────────────────────────────────────
echo "[3/5] PBC NVT equilibration (100 ps, 40 Å cube, fixed box)..."
"${LMP}" ${KOKKOS_ARGS} -in run_pbc_equilibration.mace 2>&1 | tee -a logs/pbc_eq.log
echo "✓ Equilibration complete"
echo ""

# ── Stage 3: Production ──────────────────────────────────────────────────────
echo "[4/5] PBC production (5 ns, 40 Å cube, NVT)..."
"${LMP}" ${KOKKOS_ARGS} -in run_pbc_production.mace 2>&1 | tee -a logs/pbc_prod.log

echo "[5/5] Verifying outputs..."
[ -f "traj_alanine_pbc_prod.dump" ] && echo "✓ Trajectory: traj_alanine_pbc_prod.dump"
[ -f "alanine_pbc_prod_final.data" ] && echo "✓ Final data: alanine_pbc_prod_final.data"
echo ""

echo "========================================"
echo "PBC Pipeline Complete!"
echo "========================================"
echo "Outputs in: ${PBC_DIR}/"
echo ""
