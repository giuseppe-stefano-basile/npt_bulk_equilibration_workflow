#!/bin/bash
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "${WORKSPACE_DIR}/.." && pwd)"
CONFIG_FILE="${WORKFLOW_DIR}/configs/config_npt_bulk.env"
STATUS_FILE="${WORKSPACE_DIR}/.pre_submission_status.env"

echo "========================================"
echo "Pre-Submission Checks"
echo "========================================"
echo "Workflow: ${WORKFLOW_DIR}"
echo ""

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Missing config file: ${CONFIG_FILE}"
    exit 1
fi
source "${CONFIG_FILE}"

missing_required=0

if [[ -f "${WORKFLOW_DIR}/scripts/leonardo_env.sh" ]]; then
    source "${WORKFLOW_DIR}/scripts/leonardo_env.sh"
    setup_leonardo_environment
else
    echo "  [MISSING] scripts/leonardo_env.sh"
    missing_required=1
fi

check_file() {
    local path="$1"
    if [[ -f "${path}" ]]; then
        echo "  [OK] ${path#${WORKFLOW_DIR}/}"
    else
        echo "  [MISSING] ${path#${WORKFLOW_DIR}/}"
        missing_required=1
    fi
}

echo "[1/5] Checking required files..."
check_file "${WORKFLOW_DIR}/run_workflow.sh"
check_file "${WORKFLOW_DIR}/configs/config_npt_bulk.env"
check_file "${WORKFLOW_DIR}/scripts/leonardo_env.sh"
check_file "${WORKFLOW_DIR}/scripts/generate_bulk_alanine_npt.py"
check_file "${WORKFLOW_DIR}/scripts/extract_sphere_cube.py"
check_file "${WORKFLOW_DIR}/npbc_production/launch_npbc.sh"
check_file "${WORKFLOW_DIR}/npbc_production/submit_npbc_leonardo.sh"
check_file "${WORKFLOW_DIR}/pbc_production/launch_pbc.sh"
check_file "${WORKFLOW_DIR}/pbc_production/submit_pbc_leonardo.sh"
check_file "${WORKFLOW_DIR}/input_templates/01_minimize_warmup_npt.mace"
check_file "${WORKFLOW_DIR}/input_templates/02_npt_equilibration.mace"
check_file "${WORKFLOW_DIR}/input_templates/03_npt_production.mace"
check_file "${WORKFLOW_DIR}/npbc_production/run_npbc_minimize.mace"
check_file "${WORKFLOW_DIR}/npbc_production/run_npbc_equilibration.mace"
check_file "${WORKFLOW_DIR}/npbc_production/run_npbc_production.mace"
check_file "${WORKFLOW_DIR}/pbc_production/run_pbc_minimize.mace"
check_file "${WORKFLOW_DIR}/pbc_production/run_pbc_equilibration.mace"
check_file "${WORKFLOW_DIR}/pbc_production/run_pbc_production.mace"
check_file "${WORKFLOW_DIR}/npbc_production/${MODEL_FILE}"
check_file "${WORKFLOW_DIR}/pbc_production/${MODEL_FILE}"
echo ""

echo "[2/5] Validating Python syntax..."
if [[ -z "${PYTHON_BIN:-}" ]]; then
    echo "  [MISSING] No python/python3 interpreter available"
    missing_required=1
else
    if "${PYTHON_BIN}" -m py_compile \
        "${WORKFLOW_DIR}/scripts/generate_bulk_alanine_npt.py" \
        "${WORKFLOW_DIR}/scripts/extract_sphere_cube.py"; then
        echo "  [OK] Python scripts compile"
    else
        echo "  [MISSING] Python syntax check failed"
        missing_required=1
    fi
fi
echo ""

echo "[3/5] Validating LAMMPS runtime..."
if ! type check_lammps_runtime >/dev/null 2>&1; then
    echo "  [MISSING] Leonardo environment helper not loaded"
    missing_required=1
elif check_lammps_runtime "${LMP_BIN:-}"; then
    echo "  [OK] LMP_BIN executable: ${LMP_BIN}"
    echo "  [OK] LAMMPS shared libraries resolve"
else
    echo "  [MISSING] LAMMPS runtime validation failed"
    missing_required=1
fi
echo ""

echo "[4/5] Ensuring output directories exist..."
mkdir -p "${WORKFLOW_DIR}/runs/logs" "${WORKFLOW_DIR}/runs/data"
mkdir -p "${WORKFLOW_DIR}/npbc_production/logs"
mkdir -p "${WORKFLOW_DIR}/pbc_production/logs"
echo "  [OK] runs/logs"
echo "  [OK] runs/data"
echo "  [OK] npbc_production/logs"
echo "  [OK] pbc_production/logs"
echo ""

resolve_bias_path() {
    local raw_path="$1"
    if [[ "${raw_path}" = /* ]]; then
        printf "%s" "${raw_path}"
        return
    fi
    if [[ -f "${WORKFLOW_DIR}/npbc_production/${raw_path}" ]]; then
        printf "%s" "${WORKFLOW_DIR}/npbc_production/${raw_path}"
        return
    fi
    if [[ -f "${WORKFLOW_DIR}/${raw_path}" ]]; then
        printf "%s" "${WORKFLOW_DIR}/${raw_path}"
        return
    fi
    printf "%s" "${WORKFLOW_DIR}/npbc_production/${raw_path}"
}

echo "[5/5] Validating NPBC bias readiness..."
NPBC_READY="no"
NPBC_VDWPARM_RESOLVED=""
NPBC_GAU_RESOLVED=""

if [[ -n "${NPBC_VDWPARM_FILE:-}" ]] && [[ -n "${NPBC_GAU_FILE:-}" ]]; then
    NPBC_VDWPARM_RESOLVED="$(resolve_bias_path "${NPBC_VDWPARM_FILE}")"
    NPBC_GAU_RESOLVED="$(resolve_bias_path "${NPBC_GAU_FILE}")"
    if [[ -f "${NPBC_VDWPARM_RESOLVED}" ]] && [[ -f "${NPBC_GAU_RESOLVED}" ]]; then
        NPBC_READY="yes"
        echo "  [OK] NPBC bias files found"
        echo "       VDWPARM: ${NPBC_VDWPARM_RESOLVED}"
        echo "       GAU:     ${NPBC_GAU_RESOLVED}"
    else
        echo "  [WARN] NPBC bias variables are set, but at least one file is missing"
        echo "       VDWPARM: ${NPBC_VDWPARM_RESOLVED}"
        echo "       GAU:     ${NPBC_GAU_RESOLVED}"
    fi
else
    echo "  [WARN] NPBC bias variables are not set in config_npt_bulk.env"
    echo "         NPBC manual submission block will be skipped."
fi
echo ""

cat > "${STATUS_FILE}" << EOF
export WORKFLOW_DIR="${WORKFLOW_DIR}"
export NPBC_READY="${NPBC_READY}"
export NPBC_VDWPARM_RESOLVED="${NPBC_VDWPARM_RESOLVED}"
export NPBC_GAU_RESOLVED="${NPBC_GAU_RESOLVED}"
EOF

if [[ "${missing_required}" -ne 0 ]]; then
    echo "ERROR: Missing required files. Fix these before preparing submission commands."
    exit 1
fi

echo "========================================"
echo "Checks complete"
echo "========================================"
echo "Status file: ${STATUS_FILE}"
echo "Next step: bash ${WORKSPACE_DIR}/02_prepare_submission_commands.sh"
