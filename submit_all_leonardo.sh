#!/bin/bash
# Master SLURM job for complete Leonardo workflow
# Submits: NPT batch → NPBC GPU job → PBC GPU job
# (Sequential to ensure proper resource use)

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT="INF26_biophys"  # Update with Leonardo account
MAIL="your.mail@provider.com"
MAIL_TYPE="END,FAIL"

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

echo "Submitting Leonardo workflow..."
echo "Account: $ACCOUNT"
echo "Mail : $MAIL"
echo ""

# ============================================================================
# NPT Job: CPU-friendly, runs all 3 phases + extraction
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
# NPBC Job: Depends on NPT completion
# ============================================================================
NPBC_JOB=$(sbatch \
    --job-name=npbc_prod_ala2 \
    --time=05:00:00 \
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
echo ""

# ============================================================================
# PBC Job: Depends on NPT completion (independent of NPBC)
# ============================================================================
PBC_JOB=$(sbatch \
    --job-name=pbc_prod_ala2 \
    --time=05:00:00 \
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
echo "NPBC: $NPBC_JOB (after NPT)"
echo "PBC:  $PBC_JOB (after NPT, parallel with NPBC)"
echo ""
echo "Monitor with:"
echo "  squeue -j $NPT_JOB,$NPBC_JOB,$PBC_JOB"
echo ""
