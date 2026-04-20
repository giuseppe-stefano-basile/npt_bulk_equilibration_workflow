# Manual Submission Workspace

This subfolder is for preparing everything up to job submission without auto-submitting anything.

## What it does

1. `01_pre_submission_checks.sh`
   - Validates workflow files and creates required log/data directories.
   - Checks whether NPBC bias files are configured and reachable.
2. `02_prepare_submission_commands.sh`
   - Reads `submission.env`.
   - Generates `03_submission_commands.txt` with the exact `sbatch` commands to run manually.

No script in this folder calls `sbatch`.

## Quick usage

```bash
cd /home/utente/giuseppe/npt_bulk_equilibration_workflow

# 1) Run pre-checks
bash manual_submission_workspace/01_pre_submission_checks.sh

# 2) Edit submission parameters
nano manual_submission_workspace/submission.env

# 3) Generate manual commands
bash manual_submission_workspace/02_prepare_submission_commands.sh

# 4) Submit manually, command by command
cat manual_submission_workspace/03_submission_commands.txt
```

## Notes

- NPBC submission commands are generated only if NPBC bias files are valid in `configs/config_npt_bulk.env`.
- If NPBC is not ready, the generated file still includes NPT + PBC manual submission commands.
