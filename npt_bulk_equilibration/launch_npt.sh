#!/bin/bash
#
# NPT Bulk Equilibration Launcher (Leonardo-compatible)
# Runs 3-phase NPT protocol to generate bulk water system with fixed alanine
#

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NPT BULK EQUILIBRATION LAUNCHER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Source configuration
if [[ -f "$WORKFLOW_DIR/configs/config_npt_bulk.env" ]]; then
    source "$WORKFLOW_DIR/configs/config_npt_bulk.env"
    echo "[✓] Configuration loaded"
else
    echo "[✗] Configuration not found: $WORKFLOW_DIR/configs/config_npt_bulk.env"
    exit 1
fi

if ! type module >/dev/null 2>&1 && [[ -f /etc/profile.d/modules.sh ]]; then
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

if [[ -n "${PLUMED_ROOT:-}" ]]; then
    export PLUMED_ROOT
    export PATH="${PLUMED_ROOT}/bin:${PATH}"
    export LD_LIBRARY_PATH="${PLUMED_ROOT}/lib:${LD_LIBRARY_PATH:-}"
    export PKG_CONFIG_PATH="${PLUMED_ROOT}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi

if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python)"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
else
    echo "[✗] No Python interpreter available after environment setup"
    exit 1
fi

echo "[✓] Python: ${PYTHON_BIN} ($(${PYTHON_BIN} --version 2>&1))"

if [[ -n "${MPI_MODULE:-}" ]]; then
    echo "[✓] MPI module requested: ${MPI_MODULE}"
fi

# Check required files
echo ""
echo "Checking prerequisites..."

required_files=(
    "$WORKFLOW_DIR/scripts/generate_bulk_alanine_npt.py"
    "$SCRIPT_DIR/minimize_warmup.mace"
    "$SCRIPT_DIR/equilibration.mace"
    "$SCRIPT_DIR/production.mace"
    "$WORKFLOW_DIR/systems/ala2_seed.pdb"
)

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  [✓] $(basename "$file")"
    else
        echo "  [✗] Missing: $file"
        exit 1
    fi
done

# Create output directory
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/data"

echo ""
echo "═══════════════════════════════════════════"
echo "PHASE 1: Generate bulk system"
echo "═══════════════════════════════════════════"
echo "Density: $RHO0_MOL_A3 mol/Å³"
echo "System: 3800 water + 22-atom alanine"
echo ""

"${PYTHON_BIN}" "$WORKFLOW_DIR/scripts/generate_bulk_alanine_npt.py" \
    --output "$SCRIPT_DIR/data/bulk_alanine.data" \
    --density "$RHO0_MOL_A3" \
    --seed-pdb "$WORKFLOW_DIR/systems/ala2_seed.pdb" \
    --num-water 3800

echo "[✓] System generated successfully"
echo ""

# Check if LAMMPS is available (use LMP_BIN from config, fall back to PATH)
if [[ -n "${LMP_BIN:-}" ]] && [[ -x "${LMP_BIN}" ]]; then
    LAMMPS_CMD="${LMP_BIN}"
    echo "LAMMPS executable: $LAMMPS_CMD (from LMP_BIN)"
elif command -v lmp &> /dev/null; then
    LAMMPS_CMD="lmp"
    echo "LAMMPS executable: $LAMMPS_CMD"
else
    echo "[⚠] LAMMPS not found. Set LMP_BIN in config or add lmp to PATH."
    exit 1
fi

# Kokkos GPU flags (match reference stage13 invocation)
KOKKOS_ARGS="-k on g 1 -sf kk -pk kokkos neigh half newton on"
export OMP_NUM_THREADS=1
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
echo "Kokkos GPU mode: device $CUDA_VISIBLE_DEVICES"

echo ""
echo "═══════════════════════════════════════════"
echo "PHASE 2: Minimize + Warmup (150 ps)"
echo "═══════════════════════════════════════════"
echo ""

cd "$SCRIPT_DIR"
$LAMMPS_CMD $KOKKOS_ARGS -in minimize_warmup.mace \
    2>&1 | tee -a logs/minimize_warmup_screen.log

if [[ -f "data/restart_npt_phase1_warmup.lammps" ]]; then
    echo "[✓] Minimize/warmup completed"
else
    echo "[✗] Minimize/warmup failed (no restart file produced)"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════"
echo "PHASE 3: NPT equilibration (500 ps)"
echo "═══════════════════════════════════════════"
echo ""

cd "$SCRIPT_DIR"
$LAMMPS_CMD $KOKKOS_ARGS -in equilibration.mace \
    2>&1 | tee -a logs/equilibration_screen.log

if [[ -f "data/restart_npt_phase2_eq_final.lammps" ]]; then
    echo "[✓] NPT equilibration completed"
else
    echo "[✗] NPT equilibration failed (no restart file produced)"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════"
echo "PHASE 4: NPT production (500 ps)"
echo "═══════════════════════════════════════════"
echo ""

cd "$SCRIPT_DIR"
$LAMMPS_CMD $KOKKOS_ARGS -in production.mace \
    2>&1 | tee -a logs/production_screen.log

if [[ -f "data/bulk_water_alanine_npt_final.data" ]]; then
    echo "[✓] NPT production completed"
else
    echo "[✗] NPT production failed (no final .data produced)"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════"
echo "✓ NPT BULK EQUILIBRATION COMPLETE"
echo "═══════════════════════════════════════════"
echo ""
echo "Final .data: $SCRIPT_DIR/data/bulk_water_alanine_npt_final.data"
echo "Ready for sphere/cube extraction"
echo ""
