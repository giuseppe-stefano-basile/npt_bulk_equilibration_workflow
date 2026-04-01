#!/bin/bash
# NPBC Production Launcher for Leonardo BOOSTER
# Three-stage pipeline: minimize → equilibration → production
# 20 Å sphere cavity with frozen mean-field bias
# Date: 2026-04-01

set -e

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NPBC_DIR="${WORKFLOW_DIR}/npbc_production"

# Source config
if [[ -f "${WORKFLOW_DIR}/configs/config_npt_bulk.env" ]]; then
    source "${WORKFLOW_DIR}/configs/config_npt_bulk.env"
fi

echo "========================================"
echo "NPBC Pipeline (minimize → eq → prod)"
echo "========================================"
echo "Workflow: ${WORKFLOW_DIR}"
echo "Run dir: ${NPBC_DIR}"
echo ""

# ── NPBC bias preflight ──────────────────────────────────────────────────────
# The 20 Å bias files are MANDATORY.  Fail fast if unset or missing.
fail_bias() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "ERROR: R20 bias files required for NPBC but not available."
    echo ""
    echo "  NPBC_VDWPARM_FILE = '${NPBC_VDWPARM_FILE:-<unset>}'"
    echo "  NPBC_GAU_FILE     = '${NPBC_GAU_FILE:-<unset>}'"
    echo ""
    echo "Set both variables in configs/config_npt_bulk.env to valid paths"
    echo "pointing to 20 Å optimised bias files, then re-run."
    echo "════════════════════════════════════════════════════════════════════"
    exit 1
}

[[ -z "${NPBC_VDWPARM_FILE}" ]] && fail_bias
[[ -z "${NPBC_GAU_FILE}" ]]     && fail_bias
[[ ! -f "${NPBC_DIR}/${NPBC_VDWPARM_FILE}" ]] && [[ ! -f "${NPBC_VDWPARM_FILE}" ]] && fail_bias
[[ ! -f "${NPBC_DIR}/${NPBC_GAU_FILE}" ]]     && [[ ! -f "${NPBC_GAU_FILE}" ]]     && fail_bias

# Resolve to paths usable from NPBC_DIR
if [[ -f "${NPBC_DIR}/${NPBC_VDWPARM_FILE}" ]]; then
    VDWPARM_RESOLVED="${NPBC_VDWPARM_FILE}"
else
    VDWPARM_RESOLVED="${NPBC_VDWPARM_FILE}"
fi
if [[ -f "${NPBC_DIR}/${NPBC_GAU_FILE}" ]]; then
    GAU_RESOLVED="${NPBC_GAU_FILE}"
else
    GAU_RESOLVED="${NPBC_GAU_FILE}"
fi

echo "✓ R20 bias files validated"
echo "  VDWPARM: ${VDWPARM_RESOLVED}"
echo "  GAU:     ${GAU_RESOLVED}"
echo ""

# Check extracted data
if [ ! -f "${WORKFLOW_DIR}/runs/data/alanine_cavity_R20_from_npt.data" ]; then
    echo "ERROR: NPT extraction not found!"
    echo "  Expected: ${WORKFLOW_DIR}/runs/data/alanine_cavity_R20_from_npt.data"
    echo ""
    echo "Run NPT workflow first: cd ${WORKFLOW_DIR} && bash run_workflow.sh"
    exit 1
fi

cd "${NPBC_DIR}"

# Kokkos GPU flags
KOKKOS_ARGS="-k on g 1 -sf kk -pk kokkos neigh half newton on"
export OMP_NUM_THREADS=1
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
LMP="${LMP_BIN:-lmp}"
echo "LAMMPS: ${LMP}  (GPU $CUDA_VISIBLE_DEVICES)"

echo "[1/5] Checking files..."
[ -f "run_npbc_minimize.mace" ]       || { echo "Missing run_npbc_minimize.mace"; exit 1; }
[ -f "run_npbc_equilibration.mace" ]  || { echo "Missing run_npbc_equilibration.mace"; exit 1; }
[ -f "run_npbc_production.mace" ]     || { echo "Missing run_npbc_production.mace"; exit 1; }
[ -f "MACE-OFF23_small.model-mliap_lammps_float32.pt" ] || { echo "Missing MACE model"; exit 1; }
echo "✓ All files present"
echo ""

# ── Stage 1: Minimization ────────────────────────────────────────────────────
echo "[2/5] NPBC minimization (solvent relaxation around fixed alanine)..."
mkdir -p logs
$LMP $KOKKOS_ARGS -in run_npbc_minimize.mace 2>&1 | tee -a logs/npbc_minimize.log
echo "✓ Minimization complete"
echo ""

# ── Stage 2: NVT Equilibration ───────────────────────────────────────────────
echo "[3/5] NPBC NVT equilibration (100 ps, R=20 Å, frozen bias)..."

# Patch bias paths into the equilibration input
sed \
    -e "s|__NPBC_VDWPARM_FILE__|${VDWPARM_RESOLVED}|g" \
    -e "s|__NPBC_GAU_FILE__|${GAU_RESOLVED}|g" \
    run_npbc_equilibration.mace > _run_npbc_equilibration_patched.mace

$LMP $KOKKOS_ARGS -in _run_npbc_equilibration_patched.mace 2>&1 | tee -a logs/npbc_eq.log
echo "✓ Equilibration complete"
echo ""

# ── Stage 3: Production ──────────────────────────────────────────────────────
echo "[4/5] NPBC production (5 ns, R=20 Å, frozen bias)..."

# Patch bias paths into the production input
sed \
    -e "s|__NPBC_VDWPARM_FILE__|${VDWPARM_RESOLVED}|g" \
    -e "s|__NPBC_GAU_FILE__|${GAU_RESOLVED}|g" \
    run_npbc_production.mace > _run_npbc_production_patched.mace

$LMP $KOKKOS_ARGS -in _run_npbc_production_patched.mace 2>&1 | tee -a logs/npbc_prod.log

echo "[5/5] Verifying outputs..."
[ -f "traj_alanine_nbpc_prod.dump" ] && echo "✓ Trajectory: traj_alanine_nbpc_prod.dump"
[ -f "dens_shells_alanine_nbpc_prod.dat" ] && echo "✓ Density shells: dens_shells_alanine_nbpc_prod.dat"
[ -f "alanine_nbpc_prod_final.data" ] && echo "✓ Final data: alanine_nbpc_prod_final.data"
echo ""

echo "========================================"
echo "NPBC Pipeline Complete!"
echo "========================================"
echo "Outputs in: ${NPBC_DIR}/"
echo ""
