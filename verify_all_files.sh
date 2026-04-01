#!/bin/bash

# Complete file verification script for LEONARDO package

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERRORS=0
WARNINGS=0

echo "=========================================="
echo "NPT + PRODUCTION WORKFLOW FILE VERIFICATION"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_file() {
    local filepath=$1
    local description=$2
    
    if [[ -f "$filepath" ]]; then
        size=$(du -h "$filepath" | cut -f1)
        echo -e "${GREEN}✓${NC} $description ($size)"
        return 0
    else
        echo -e "${RED}✗${NC} $description - MISSING: $filepath"
        ((ERRORS++))
        return 1
    fi
}

check_dir() {
    local dirpath=$1
    local description=$2
    
    if [[ -d "$dirpath" ]]; then
        count=$(find "$dirpath" -type f | wc -l)
        echo -e "${GREEN}✓${NC} $description ($count files)"
        return 0
    else
        echo -e "${RED}✗${NC} $description - MISSING: $dirpath"
        ((ERRORS++))
        return 1
    fi
}

check_executable() {
    local filepath=$1
    local description=$2
    
    if [[ -x "$filepath" ]]; then
        echo -e "${GREEN}✓${NC} $description (executable)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $description - NOT EXECUTABLE: $filepath"
        ((WARNINGS++))
        return 1
    fi
}

# ===== NPT PHASE =====
echo "═══ NPT BULK EQUILIBRATION ═══"
check_dir "$WORKFLOW_DIR/npt_bulk_equilibration" "NPT folder"
check_file "$WORKFLOW_DIR/npt_bulk_equilibration/minimize_warmup.mace" "NPT minimize/warmup input"
check_file "$WORKFLOW_DIR/npt_bulk_equilibration/equilibration.mace" "NPT equilibration input"
check_file "$WORKFLOW_DIR/npt_bulk_equilibration/production.mace" "NPT production input"
check_file "$WORKFLOW_DIR/npt_bulk_equilibration/launch_npt.sh" "NPT local launcher"
check_executable "$WORKFLOW_DIR/npt_bulk_equilibration/launch_npt.sh" "NPT launcher executable"
check_file "$WORKFLOW_DIR/npt_bulk_equilibration/submit_npt_leonardo.sh" "NPT SLURM template"
check_executable "$WORKFLOW_DIR/npt_bulk_equilibration/submit_npt_leonardo.sh" "NPT SLURM executable"
echo ""

# ===== EXTRACTION =====
echo "═══ EXTRACTION UTILITIES ═══"
check_dir "$WORKFLOW_DIR/scripts" "Scripts folder"
check_file "$WORKFLOW_DIR/scripts/extract_sphere_cube.py" "Extraction script"
echo ""

# ===== NPBC PRODUCTION =====
echo "═══ NPBC PRODUCTION (Self-contained) ═══"
check_dir "$WORKFLOW_DIR/npbc_production" "NPBC production folder"
check_file "$WORKFLOW_DIR/npbc_production/run_npbc_minimize.mace" "NPBC minimize input"
check_file "$WORKFLOW_DIR/npbc_production/run_npbc_equilibration.mace" "NPBC equilibration input"
check_file "$WORKFLOW_DIR/npbc_production/run_npbc_production.mace" "NPBC production input"
check_file "$WORKFLOW_DIR/npbc_production/launch_npbc.sh" "NPBC launcher"
check_executable "$WORKFLOW_DIR/npbc_production/launch_npbc.sh" "NPBC launcher executable"
check_file "$WORKFLOW_DIR/npbc_production/submit_npbc_leonardo.sh" "NPBC SLURM template"
check_executable "$WORKFLOW_DIR/npbc_production/submit_npbc_leonardo.sh" "NPBC SLURM executable"

# NPBC Model
model_file=$(ls "$WORKFLOW_DIR/npbc_production"/MACE-OFF23_small.model-*.pt 2>/dev/null | head -1)
if [[ -f "$model_file" ]]; then
    size=$(du -h "$model_file" | cut -f1)
    echo -e "${GREEN}✓${NC} NPBC MACE model ($size)"
else
    echo -e "${RED}✗${NC} NPBC MACE model - MISSING (should be ~500 MB)"
    ((ERRORS++))
fi

# NPBC Bias files — R20 bias is mandatory but may not be provided yet
echo ""
echo "═══ NPBC BIAS (R20 — must be supplied before running NPBC) ═══"
check_dir "$WORKFLOW_DIR/npbc_production/bias" "NPBC bias folder"
# Source config to check NPBC_VDWPARM_FILE / NPBC_GAU_FILE
if [[ -f "$WORKFLOW_DIR/configs/config_npt_bulk.env" ]]; then
    source "$WORKFLOW_DIR/configs/config_npt_bulk.env"
fi
if [[ -z "${NPBC_VDWPARM_FILE:-}" ]] || [[ -z "${NPBC_GAU_FILE:-}" ]]; then
    echo -e "${YELLOW}⚠${NC} NPBC_VDWPARM_FILE / NPBC_GAU_FILE not set — NPBC blocked until 20 Å bias provided"
    ((WARNINGS++))
else
    if [[ -f "$WORKFLOW_DIR/npbc_production/${NPBC_VDWPARM_FILE}" ]] || [[ -f "${NPBC_VDWPARM_FILE}" ]]; then
        echo -e "${GREEN}✓${NC} NPBC VDWPARM file: ${NPBC_VDWPARM_FILE}"
    else
        echo -e "${RED}✗${NC} NPBC VDWPARM file missing: ${NPBC_VDWPARM_FILE}"
        ((ERRORS++))
    fi
    if [[ -f "$WORKFLOW_DIR/npbc_production/${NPBC_GAU_FILE}" ]] || [[ -f "${NPBC_GAU_FILE}" ]]; then
        echo -e "${GREEN}✓${NC} NPBC GAU file: ${NPBC_GAU_FILE}"
    else
        echo -e "${RED}✗${NC} NPBC GAU file missing: ${NPBC_GAU_FILE}"
        ((ERRORS++))
    fi
fi

# NPBC logs directory
if [[ -d "$WORKFLOW_DIR/npbc_production/logs" ]]; then
    echo -e "${GREEN}✓${NC} NPBC logs directory (ready for outputs)"
else
    echo -e "${YELLOW}⚠${NC} NPBC logs directory - will be created on first run"
    ((WARNINGS++))
fi
echo ""

# ===== PBC PRODUCTION =====
echo "═══ PBC PRODUCTION (Self-contained) ═══"
check_dir "$WORKFLOW_DIR/pbc_production" "PBC production folder"
check_file "$WORKFLOW_DIR/pbc_production/run_pbc_minimize.mace" "PBC minimize input"
check_file "$WORKFLOW_DIR/pbc_production/run_pbc_equilibration.mace" "PBC equilibration input"
check_file "$WORKFLOW_DIR/pbc_production/run_pbc_production.mace" "PBC production input"
check_file "$WORKFLOW_DIR/pbc_production/launch_pbc.sh" "PBC launcher"
check_executable "$WORKFLOW_DIR/pbc_production/launch_pbc.sh" "PBC launcher executable"
check_file "$WORKFLOW_DIR/pbc_production/submit_pbc_leonardo.sh" "PBC SLURM template"
check_executable "$WORKFLOW_DIR/pbc_production/submit_pbc_leonardo.sh" "PBC SLURM executable"

# PBC Model
model_file=$(ls "$WORKFLOW_DIR/pbc_production"/MACE-OFF23_small.model-*.pt 2>/dev/null | head -1)
if [[ -f "$model_file" ]]; then
    size=$(du -h "$model_file" | cut -f1)
    echo -e "${GREEN}✓${NC} PBC MACE model ($size)"
else
    echo -e "${RED}✗${NC} PBC MACE model - MISSING (should be ~500 MB)"
    ((ERRORS++))
fi

# PBC logs directory
if [[ -d "$WORKFLOW_DIR/pbc_production/logs" ]]; then
    echo -e "${GREEN}✓${NC} PBC logs directory (ready for outputs)"
else
    echo -e "${YELLOW}⚠${NC} PBC logs directory - will be created on first run"
    ((WARNINGS++))
fi
echo ""

# ===== MASTER SCRIPTS =====
echo "═══ MASTER ORCHESTRATION ═══"
check_file "$WORKFLOW_DIR/run_all_leonardo.sh" "Sequential bash master script"
check_executable "$WORKFLOW_DIR/run_all_leonardo.sh" "Sequential script executable"
check_file "$WORKFLOW_DIR/submit_all_leonardo.sh" "SLURM batch manager"
check_executable "$WORKFLOW_DIR/submit_all_leonardo.sh" "SLURM batch executable"
echo ""

# ===== DOCUMENTATION =====
echo "═══ DOCUMENTATION ═══"
check_file "$WORKFLOW_DIR/README.md" "Technical README"
check_file "$WORKFLOW_DIR/README_PRODUCTION.md" "Production workflow guide"
check_file "$WORKFLOW_DIR/00_PRODUCTION_START_HERE.md" "Quick start guide"
check_file "$WORKFLOW_DIR/package_for_leonardo.sh" "Packaging script"
echo ""

# ===== CONFIGURATION =====
echo "═══ CONFIGURATION ═══"
check_dir "$WORKFLOW_DIR/configs" "Configuration folder"
check_file "$WORKFLOW_DIR/configs/config_npt_bulk.env" "NPT configuration"
echo ""

# ===== SUMMARY =====
echo "=========================================="
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
    echo "  Ready for packaging and Leonardo execution"
else
    echo -e "${RED}✗ $ERRORS ERROR(S) FOUND${NC}"
    echo "  Package may be incomplete"
fi

if [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}⚠ $WARNINGS WARNING(S)${NC}"
fi

echo "=========================================="
echo ""

# File counts
total_files=$(find "$WORKFLOW_DIR" -type f | wc -l)
total_size=$(du -sh "$WORKFLOW_DIR" | cut -f1)
echo "Package Summary:"
echo "  Total files: $total_files"
echo "  Total size: $total_size"
echo ""

# Recommendations
if [[ $ERRORS -eq 0 ]]; then
    echo "Next steps:"
    echo "  1. Run: ./run_all_leonardo.sh (local testing)"
    echo "  2. Or: ./submit_all_leonardo.sh (Leonardo SLURM batch)"
    echo "  3. Monitor: squeue -u \$USER"
    echo ""
fi

exit $ERRORS
