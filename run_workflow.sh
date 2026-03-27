#!/bin/bash
# NPT Bulk Equilibration Workflow - Master Launcher
# Purpose: Execute full pipeline from bulk generation to sphere/cube extraction
# Date: 2026-03-24

set -e

# Resolve workflow root robustly (works for direct bash and sbatch-spooled execution)
if [[ -n "${SLURM_SUBMIT_DIR:-}" ]] && [[ -f "${SLURM_SUBMIT_DIR}/configs/config_npt_bulk.env" ]]; then
    export WORKFLOW_DIR="${SLURM_SUBMIT_DIR}"
elif [[ -f "${PWD}/configs/config_npt_bulk.env" ]]; then
    export WORKFLOW_DIR="${PWD}"
else
    export WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Load configuration
source "${WORKFLOW_DIR}/configs/config_npt_bulk.env"

setup_python_environment() {
    if ! type module >/dev/null 2>&1 && [[ -f /etc/profile.d/modules.sh ]]; then
        # Ensure the module function exists in non-interactive batch shells.
        source /etc/profile.d/modules.sh
    fi

    if type module >/dev/null 2>&1; then
        module load profile/deeplrn 2>/dev/null || true
        if [[ -n "${GCC_MODULE:-}" ]]; then
            module load "${GCC_MODULE}" 2>/dev/null || true
        else
            module load gcc 2>/dev/null || true
        fi
        if [[ -n "${CUDA_MODULE:-}" ]]; then
            module load "${CUDA_MODULE}" 2>/dev/null || true
        else
            module load cuda 2>/dev/null || true
        fi
        if [[ -n "${CMAKE_MODULE:-}" ]]; then
            module load "${CMAKE_MODULE}" 2>/dev/null || true
        else
            module load cmake 2>/dev/null || true
        fi
        if [[ -n "${MKL_MODULE:-}" ]]; then
            module load "${MKL_MODULE}" 2>/dev/null || true
        fi
        if [[ -n "${GSL_MODULE:-}" ]]; then
            module load "${GSL_MODULE}" 2>/dev/null || true
        fi
        if [[ -n "${MPI_MODULE:-}" ]]; then
            module load "${MPI_MODULE}" 2>/dev/null || true
        fi
        if [[ -n "${PYTHON_MODULE:-}" ]]; then
            module load "${PYTHON_MODULE}" 2>/dev/null || true
        fi
    fi

    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    else
        echo "ERROR: No Python interpreter available after environment setup"
        exit 1
    fi

    export PYTHON_BIN
}

setup_python_environment

if [[ -n "${PLUMED_ROOT:-}" ]]; then
    export PLUMED_ROOT
    export PATH="${PLUMED_ROOT}/bin:${PATH}"
    export LD_LIBRARY_PATH="${PLUMED_ROOT}/lib:${LD_LIBRARY_PATH:-}"
    export PKG_CONFIG_PATH="${PLUMED_ROOT}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi

# Directories
SCRIPTS_DIR="${WORKFLOW_DIR}/scripts"
INPUTS_DIR="${WORKFLOW_DIR}/input_templates"
SYSTEMS_DIR="${WORKFLOW_DIR}/systems"
RUNS_DIR="${WORKFLOW_DIR}/runs"

# Resolve alanine PDB path robustly
if [[ "${ALANINE_PDB}" = /* ]]; then
    ALANINE_PDB_PATH="${ALANINE_PDB}"
elif [[ -f "${WORKFLOW_DIR}/${ALANINE_PDB}" ]]; then
    ALANINE_PDB_PATH="${WORKFLOW_DIR}/${ALANINE_PDB}"
elif [[ -f "${SYSTEMS_DIR}/${ALANINE_PDB}" ]]; then
    ALANINE_PDB_PATH="${SYSTEMS_DIR}/${ALANINE_PDB}"
else
    echo "ERROR: ALANINE_PDB not found: ${ALANINE_PDB}"
    echo "  Checked: ${WORKFLOW_DIR}/${ALANINE_PDB}"
    echo "  Checked: ${SYSTEMS_DIR}/${ALANINE_PDB}"
    exit 1
fi

# Create run directory
mkdir -p "${RUNS_DIR}/logs" "${RUNS_DIR}/data"
cd "${RUNS_DIR}"

# Resolve absolute path to MACE model file (no symlinks - Lustre-safe)
MODEL_PATH=""
for _model_dir in "${WORKFLOW_DIR}/pbc_production" "${WORKFLOW_DIR}/npbc_production" "${WORKFLOW_DIR}/npt_bulk_equilibration"; do
    if [[ -f "${_model_dir}/${MODEL_FILE}" ]]; then
        MODEL_PATH="${_model_dir}/${MODEL_FILE}"
        echo "✓ Model file found: ${MODEL_PATH}"
        break
    fi
done
if [[ -z "${MODEL_PATH}" ]]; then
    echo "ERROR: MACE model file not found: ${MODEL_FILE}"
    echo "  Searched: pbc_production/, npbc_production/, npt_bulk_equilibration/"
    exit 1
fi

echo "========================================"
echo "NPT Bulk Equilibration Workflow"
echo "========================================"
echo "Config: ${WORKFLOW_DIR}/configs/config_npt_bulk.env"
echo "Target density: ${RHO0_MOL_A3} mol/Å³ (${RHO_GCC} g/cm³)"
echo "Bulk waters: ${N_WATER_BULK}"
echo "Sphere radius: ${RADIUS_A} Å"
echo "Cube edge: ${CUBE_EDGE_A} Å"
echo "GCC module: ${GCC_MODULE:-default}"
echo "CUDA module: ${CUDA_MODULE:-default}"
echo "CMake module: ${CMAKE_MODULE:-default}"
echo "MPI module: ${MPI_MODULE:-none}"
echo "Python module: ${PYTHON_MODULE:-none}"
echo "Python bin: ${PYTHON_BIN}"
echo "Python ver: $(${PYTHON_BIN} --version 2>&1)"
echo ""

if [[ ! -x "${LMP_BIN}" ]]; then
    echo "ERROR: LMP_BIN not executable: ${LMP_BIN}"
    exit 1
fi

# Kokkos GPU flags (match reference stage13 invocation)
KOKKOS_ARGS="-k on g 1 -sf kk -pk kokkos neigh half newton on"
export OMP_NUM_THREADS=1
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
echo "Kokkos GPU mode: device $CUDA_VISIBLE_DEVICES"

if command -v ldd >/dev/null 2>&1; then
    if ldd "${LMP_BIN}" | grep -q "libmpi.so.40 => not found"; then
        echo "ERROR: MPI runtime missing for LAMMPS (${LMP_BIN})"
        echo "       Tried module: ${MPI_MODULE:-none}"
        echo "       Set MPI_MODULE in configs/config_npt_bulk.env to your cluster OpenMPI module"
        exit 1
    fi
    if ldd "${LMP_BIN}" | grep -q "libplumedKernel" && ldd "${LMP_BIN}" | grep -q "libplumedKernel.*not found"; then
        echo "ERROR: PLUMED runtime missing for LAMMPS (${LMP_BIN})"
        echo "       Set PLUMED_ROOT in configs/config_npt_bulk.env"
        exit 1
    fi
fi

# ============================================================================
# STEP 1: Generate bulk water + alanine system
# ============================================================================
echo "[STEP 1] Generating bulk water + alanine NPT system..."
if [ ! -f "data/bulk_water_alanine_npt.data" ]; then
    "${PYTHON_BIN}" "${SCRIPTS_DIR}/generate_bulk_alanine_npt.py" \
        --pdb "${ALANINE_PDB_PATH}" \
        --nwater "${N_WATER_BULK}" \
        --rho-mol-a3 "${RHO0_MOL_A3}" \
        --rho-gcc "${RHO_GCC}" \
        --cut "${ATOM_OVERLAP_CUTOFF}" \
        --seed "${RANDOM_SEED}" \
        --type-order "C N O H" \
        --out "data/bulk_water_alanine_npt.data"
    echo "✓ Generated bulk system"
else
    echo "⊘ Bulk system already exists, skipping generation"
fi
echo ""

# ============================================================================
# STEP 2: Phase 1 - Minimize + Warmup
# ============================================================================
echo "[STEP 2] Running Phase 1: Minimize + Warmup (100 ps)..."
cp "${INPUTS_DIR}/01_minimize_warmup_npt.mace" "01_minimize_warmup_npt.mace"

if [ -f "restart_npt_phase1_warmup.lammps" ]; then
    echo "⊘ Phase 1 restart exists, skipping"
else
    "${LMP_BIN}" ${KOKKOS_ARGS} -in 01_minimize_warmup_npt.mace -var model_path "${MODEL_PATH}" | tee "logs/phase1_minimize_warmup.log"
    echo "✓ Phase 1 complete"
fi
echo ""

# ============================================================================
# STEP 3: Phase 2 - NPT Equilibration
# ============================================================================
echo "[STEP 3] Running Phase 2: NPT Equilibration (500 ps)..."
cp "${INPUTS_DIR}/02_npt_equilibration.mace" "02_npt_equilibration.mace"

if [ -f "restart_npt_phase2_eq_final.lammps" ]; then
    echo "⊘ Phase 2 restart exists, skipping"
else
    "${LMP_BIN}" ${KOKKOS_ARGS} -in 02_npt_equilibration.mace -var model_path "${MODEL_PATH}" | tee "logs/phase2_npt_eq.log"
    echo "✓ Phase 2 complete"
fi
echo ""

# ============================================================================
# STEP 4: Phase 3 - NPT Production
# ============================================================================
echo "[STEP 4] Running Phase 3: NPT Production (500 ps)..."
cp "${INPUTS_DIR}/03_npt_production.mace" "03_npt_production.mace"

if [ -f "data/bulk_water_alanine_npt_final.data" ]; then
    echo "⊘ Phase 3 data exists, skipping"
else
    "${LMP_BIN}" ${KOKKOS_ARGS} -in 03_npt_production.mace -var model_path "${MODEL_PATH}" | tee "logs/phase3_npt_prod.log"
    echo "✓ Phase 3 complete"
fi
echo ""

# ============================================================================
# STEP 5: Extract sphere and cube
# ============================================================================
echo "[STEP 5] Extracting sphere (15 Å, NPBC) and cube (PBC)..."
"${PYTHON_BIN}" "${SCRIPTS_DIR}/extract_sphere_cube.py" \
    --npt-data "data/bulk_water_alanine_npt_final.data" \
    --sphere-r "${SPHERE_R_A}" \
    --cube-edge "${CUBE_EDGE_A}" \
    --sphere-out "data/alanine_cavity_R15_from_npt.data" \
    --cube-out "data/alanine_pbc_from_npt.data" \
    --verbose
echo "✓ Extraction complete"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "========================================"
echo "Workflow Complete!"
echo "========================================"
echo "Output files:"
echo "  NPBC sphere: runs/data/alanine_cavity_R15_from_npt.data"
echo "  PBC cube:    runs/data/alanine_pbc_from_npt.data"
echo ""
echo "Next steps:"
echo "  1. Copy data files to production directories"
echo "  2. Launch NPBC production with frozen bias (same as stage13)"
echo "  3. Launch PBC production with equivalent settings"
echo ""
