#!/bin/bash
# Master SLURM job for complete Leonardo workflow
# ─────────────────────────────────────────────────
# Submits:  NPT bulk eq → NPBC 3-stage → PBC 3-stage
# Geometry: 20 Å sphere (NPBC)  /  40 Å cube (PBC)
# Each extracted-system pipeline: minimize → equilibration → production
#
# NOTE: NPBC requires R=20 bias files.  If NPBC_VDWPARM_FILE or
#       NPBC_GAU_FILE are unset/empty in config, the NPBC job is
#       SKIPPED and only NPT + PBC are submitted.
# ─────────────────────────────────────────────────

set -euo pipefail

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT="INF26_biophys"  # Update with Leonardo account
MAIL="your.mail@provider.com"
MAIL_TYPE="END,FAIL"

# Source config for bias file settings
if [[ -f "${WORKFLOW_DIR}/configs/config_npt_bulk.env" ]]; then
    source "${WORKFLOW_DIR}/configs/config_npt_bulk.env"
fi

MAIL_FLAGS=()
if [[ -n "${MAIL:-}" ]] && [[ "${MAIL}" != "your.mail@provider.com" ]]; then
    MAIL_FLAGS+=(--mail-user="${MAIL}")
    MAIL_FLAGS+=(--mail-type="${MAIL_TYPE}")
fi

# Check environment
if [ -z "$ACCOUNT" ]; then
    echo "ERROR: Set ACCOUNT variable"
    exit 1
fi

# --- Bias preflight for NPBC -------------------------------------------------
SUBMIT_NPBC=true
if [[ -z "${NPBC_VDWPARM_FILE:-}" ]] || [[ -z "${NPBC_GAU_FILE:-}" ]]; then
    SUBMIT_NPBC=false
    echo "⚠  NPBC bias files not configured — NPBC job will be SKIPPED."
    echo "   Set NPBC_VDWPARM_FILE and NPBC_GAU_FILE in configs/config_npt_bulk.env"
    echo "   when the R=20 bias files are available, then resubmit."
    echo ""
fi

echo "Submitting Leonardo workflow..."
echo "Account: $ACCOUNT"
echo "Mail   : $MAIL"
echo ""

# ============================================================================
# NPT Job: 3 phases (minimize/warmup → equilibration → production) + extraction
# ============================================================================
NPT_JOB=$(sbatch \
    --job-name=npt_bulk_ala2 \
    --time=08:00:00 \
    --gres=gpu:1 \
    --cpus-per-task=16 \
    --partition=boost_usr_prod \
    --account=$ACCOUNT \
    "${MAIL_FLAGS[@]}" \
    --output="${WORKFLOW_DIR}/runs/logs/npt_bulk_%j.log" \
    --parsable \
    "${WORKFLOW_DIR}/run_workflow.sh")

echo "✓ NPT job submitted: $NPT_JOB"
echo ""

# ============================================================================
# NPBC Job: 3-stage (minimize → equilibration → production) in 20 Å cavity
#           Depends on NPT; SKIPPED if bias files not set.
# ============================================================================
NPBC_JOB=""
if $SUBMIT_NPBC; then
    NPBC_JOB=$(sbatch \
        --job-name=npbc_prod_ala2 \
        --time=08:00:00 \
        --gres=gpu:1 \
        --cpus-per-task=16 \
        --partition=boost_usr_prod \
        --account=$ACCOUNT \
        "${MAIL_FLAGS[@]}" \
        --dependency=afterok:$NPT_JOB \
        --output="${WORKFLOW_DIR}/npbc_production/logs/npbc_prod_%j.log" \
        --parsable \
        "${WORKFLOW_DIR}/npbc_production/submit_npbc_leonardo.sh")

    echo "✓ NPBC job submitted: $NPBC_JOB (depends on NPT: $NPT_JOB)"
else
    echo "⊘ NPBC job SKIPPED (no bias files)"
fi
echo ""

# ============================================================================
# PBC Job: 3-stage (minimize → equilibration → production) in 40 Å cube
#          Depends on NPT completion (independent of NPBC)
# ============================================================================
PBC_JOB=$(sbatch \
    --job-name=pbc_prod_ala2 \
    --time=08:00:00 \
    --gres=gpu:1 \
    --cpus-per-task=16 \
    --partition=boost_usr_prod \
    --account=$ACCOUNT \
    "${MAIL_FLAGS[@]}" \
    --dependency=afterok:$NPT_JOB \
    --output="${WORKFLOW_DIR}/pbc_production/logs/pbc_prod_%j.log" \
    --parsable \
    "${WORKFLOW_DIR}/pbc_production/submit_pbc_leonardo.sh")

echo "✓ PBC job submitted: $PBC_JOB (depends on NPT: $NPT_JOB)"
echo ""

# Summary
echo "========================================"
echo "Job Summary"
echo "========================================"
echo "NPT:  $NPT_JOB (runs immediately)"
if $SUBMIT_NPBC; then
    echo "NPBC: $NPBC_JOB (after NPT — 3-stage: minimize → eq → prod)"
else
    echo "NPBC: SKIPPED (bias files not configured)"
fi
echo "PBC:  $PBC_JOB (after NPT — 3-stage: minimize → eq → prod)"
echo ""
echo "Monitor with:"
if $SUBMIT_NPBC; then
    echo "  squeue -j $NPT_JOB,$NPBC_JOB,$PBC_JOB"
else
    echo "  squeue -j $NPT_JOB,$PBC_JOB"
fi
echo ""
