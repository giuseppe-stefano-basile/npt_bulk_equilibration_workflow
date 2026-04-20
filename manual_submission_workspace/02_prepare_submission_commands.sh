#!/bin/bash
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "${WORKSPACE_DIR}/.." && pwd)"
STATUS_FILE="${WORKSPACE_DIR}/.pre_submission_status.env"
SUBMISSION_ENV="${WORKSPACE_DIR}/submission.env"
OUT_FILE="${WORKSPACE_DIR}/03_submission_commands.txt"

if [[ ! -f "${SUBMISSION_ENV}" ]]; then
    echo "ERROR: Missing ${SUBMISSION_ENV}"
    exit 1
fi

source "${SUBMISSION_ENV}"

if [[ -f "${STATUS_FILE}" ]]; then
    source "${STATUS_FILE}"
else
    echo "WARN: ${STATUS_FILE} not found; NPBC readiness will be treated as 'no'."
    NPBC_READY="no"
fi

ACCOUNT="${ACCOUNT:-INF26_biophys}"
PARTITION="${PARTITION:-boost_usr_prod}"
GRES="${GRES:-gpu:1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-16}"
NPT_TIME="${NPT_TIME:-08:00:00}"
NPBC_TIME="${NPBC_TIME:-08:00:00}"
PBC_TIME="${PBC_TIME:-08:00:00}"
MAIL="${MAIL:-}"
MAIL_TYPE="${MAIL_TYPE:-END,FAIL}"

MAIL_BLOCK_NOTE="# No email notifications (MAIL is empty in submission.env)"
if [[ -n "${MAIL}" ]]; then
    MAIL_BLOCK_NOTE="# Email notifications enabled for ${MAIL} (${MAIL_TYPE})"
fi

{
    echo "# Manual submission commands"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "# Workflow: ${WORKFLOW_DIR}"
    echo "#"
    echo "# Run these commands manually from: ${WORKFLOW_DIR}"
    echo "# Commands are ordered and include dependencies."
    echo ""
    echo "cd \"${WORKFLOW_DIR}\""
    echo ""
    echo "# Parameters copied from manual_submission_workspace/submission.env"
    echo "ACCOUNT=\"${ACCOUNT}\""
    echo "PARTITION=\"${PARTITION}\""
    echo "GRES=\"${GRES}\""
    echo "CPUS_PER_TASK=\"${CPUS_PER_TASK}\""
    echo "NPT_TIME=\"${NPT_TIME}\""
    echo "NPBC_TIME=\"${NPBC_TIME}\""
    echo "PBC_TIME=\"${PBC_TIME}\""
    echo "MAIL=\"${MAIL}\""
    echo "MAIL_TYPE=\"${MAIL_TYPE}\""
    echo "${MAIL_BLOCK_NOTE}"
    echo ""
    echo "# 1) Submit NPT workflow"
    echo "NPT_JOB=\$(sbatch \\"
    echo "  --job-name=npt_bulk_ala2 \\"
    echo "  --time=\"\${NPT_TIME}\" \\"
    echo "  --gres=\"\${GRES}\" \\"
    echo "  --cpus-per-task=\"\${CPUS_PER_TASK}\" \\"
    echo "  --partition=\"\${PARTITION}\" \\"
    echo "  --account=\"\${ACCOUNT}\" \\"
    if [[ -n "${MAIL}" ]]; then
        echo "  --mail-user=\"\${MAIL}\" \\"
        echo "  --mail-type=\"\${MAIL_TYPE}\" \\"
    fi
    echo "  --output=\"${WORKFLOW_DIR}/runs/logs/npt_bulk_%j.log\" \\"
    echo "  --parsable \\"
    echo "  \"${WORKFLOW_DIR}/run_workflow.sh\")"
    echo "echo \"NPT job id: \${NPT_JOB}\""
    echo ""
    if [[ "${NPBC_READY}" == "yes" ]]; then
        echo "# 2) Submit NPBC pipeline (depends on NPT)"
        echo "NPBC_JOB=\$(sbatch \\"
        echo "  --job-name=npbc_prod_ala2 \\"
        echo "  --time=\"\${NPBC_TIME}\" \\"
        echo "  --gres=\"\${GRES}\" \\"
        echo "  --cpus-per-task=\"\${CPUS_PER_TASK}\" \\"
        echo "  --partition=\"\${PARTITION}\" \\"
        echo "  --account=\"\${ACCOUNT}\" \\"
        if [[ -n "${MAIL}" ]]; then
            echo "  --mail-user=\"\${MAIL}\" \\"
            echo "  --mail-type=\"\${MAIL_TYPE}\" \\"
        fi
        echo "  --dependency=afterok:\${NPT_JOB} \\"
        echo "  --output=\"${WORKFLOW_DIR}/npbc_production/logs/npbc_prod_%j.log\" \\"
        echo "  --parsable \\"
        echo "  \"${WORKFLOW_DIR}/npbc_production/submit_npbc_leonardo.sh\")"
        echo "echo \"NPBC job id: \${NPBC_JOB}\""
        echo ""
    else
        echo "# 2) NPBC submission skipped (bias files not ready)"
        echo "#    Set NPBC_VDWPARM_FILE and NPBC_GAU_FILE in configs/config_npt_bulk.env,"
        echo "#    then rerun:"
        echo "#    bash manual_submission_workspace/01_pre_submission_checks.sh"
        echo "#    bash manual_submission_workspace/02_prepare_submission_commands.sh"
        echo ""
    fi
    echo "# 3) Submit PBC pipeline (depends on NPT)"
    echo "PBC_JOB=\$(sbatch \\"
    echo "  --job-name=pbc_prod_ala2 \\"
    echo "  --time=\"\${PBC_TIME}\" \\"
    echo "  --gres=\"\${GRES}\" \\"
    echo "  --cpus-per-task=\"\${CPUS_PER_TASK}\" \\"
    echo "  --partition=\"\${PARTITION}\" \\"
    echo "  --account=\"\${ACCOUNT}\" \\"
    if [[ -n "${MAIL}" ]]; then
        echo "  --mail-user=\"\${MAIL}\" \\"
        echo "  --mail-type=\"\${MAIL_TYPE}\" \\"
    fi
    echo "  --dependency=afterok:\${NPT_JOB} \\"
    echo "  --output=\"${WORKFLOW_DIR}/pbc_production/logs/pbc_prod_%j.log\" \\"
    echo "  --parsable \\"
    echo "  \"${WORKFLOW_DIR}/pbc_production/submit_pbc_leonardo.sh\")"
    echo "echo \"PBC job id: \${PBC_JOB}\""
    echo ""
    if [[ "${NPBC_READY}" == "yes" ]]; then
        echo "# 4) Monitor all jobs"
        echo "squeue -j \${NPT_JOB},\${NPBC_JOB},\${PBC_JOB}"
    else
        echo "# 4) Monitor jobs"
        echo "squeue -j \${NPT_JOB},\${PBC_JOB}"
    fi
} > "${OUT_FILE}"

echo "Created: ${OUT_FILE}"
echo "Review and run commands manually (copy/paste one block at a time)."
