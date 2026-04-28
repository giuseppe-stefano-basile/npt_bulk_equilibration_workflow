#!/bin/bash
# Shared Leonardo BOOSTER runtime setup for MACE/LAMMPS workflows.
# Source this after configs/config_npt_bulk.env.

prepend_path() {
    local value="$1"
    local current="${2:-}"

    if [[ -z "${value}" ]]; then
        printf "%s" "${current}"
    elif [[ -z "${current}" ]]; then
        printf "%s" "${value}"
    else
        printf "%s:%s" "${value}" "${current}"
    fi
}

load_leonardo_modules() {
    if ! type module >/dev/null 2>&1 && [[ -f /etc/profile.d/modules.sh ]]; then
        source /etc/profile.d/modules.sh
    fi

    if ! type module >/dev/null 2>&1; then
        return 0
    fi

    if [[ "${LEONARDO_MODULE_PURGE:-1}" == "1" ]]; then
        module purge
    fi

    local mod
    for mod in \
        "${MKL_MODULE:-}" \
        "${GSL_MODULE:-}" \
        "${MPI_MODULE:-}" \
        "${CMAKE_MODULE:-}" \
        "${CUDA_MODULE:-}" \
        "${PYTHON_MODULE:-}"
    do
        [[ -n "${mod}" ]] && module load "${mod}"
    done
}

activate_mace_environment() {
    if [[ -n "${MACE_VENV_PATH:-}" ]]; then
        if [[ -f "${MACE_VENV_PATH}/bin/activate" ]]; then
            source "${MACE_VENV_PATH}/bin/activate"
        else
            echo "WARN: MACE_VENV_PATH set but activate script not found: ${MACE_VENV_PATH}/bin/activate"
        fi
    fi
}

configure_runtime_paths() {
    if [[ -n "${PLUMED_ROOT:-}" ]]; then
        export PLUMED_ROOT
        export PATH="$(prepend_path "${PLUMED_ROOT}/bin" "${PATH:-}")"
        export LD_LIBRARY_PATH="$(prepend_path "${PLUMED_ROOT}/lib" "${LD_LIBRARY_PATH:-}")"
        export PKG_CONFIG_PATH="$(prepend_path "${PLUMED_ROOT}/lib/pkgconfig" "${PKG_CONFIG_PATH:-}")"
    fi

    if [[ -n "${LAMMPS_ROOT:-}" ]]; then
        [[ -d "${LAMMPS_ROOT}/bin" ]] && export PATH="$(prepend_path "${LAMMPS_ROOT}/bin" "${PATH:-}")"
        [[ -d "${LAMMPS_ROOT}/lib" ]] && export LD_LIBRARY_PATH="$(prepend_path "${LAMMPS_ROOT}/lib" "${LD_LIBRARY_PATH:-}")"
        [[ -d "${LAMMPS_ROOT}/lib64" ]] && export LD_LIBRARY_PATH="$(prepend_path "${LAMMPS_ROOT}/lib64" "${LD_LIBRARY_PATH:-}")"
    fi

    local candidate old_ifs
    if [[ -n "${LMP_LIBRARY_PATH:-}" ]]; then
        old_ifs="${IFS}"
        IFS=":"
        for candidate in ${LMP_LIBRARY_PATH}; do
            [[ -d "${candidate}" ]] && export LD_LIBRARY_PATH="$(prepend_path "${candidate}" "${LD_LIBRARY_PATH:-}")"
        done
        IFS="${old_ifs}"
    fi

    if [[ -n "${PYLIBDIR:-}" ]]; then
        export LD_LIBRARY_PATH="$(prepend_path "${PYLIBDIR}" "${LD_LIBRARY_PATH:-}")"
    fi

    export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
    export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
}

add_lammps_binary_prefix_paths() {
    local lmp_bin="${1:-${LMP_BIN:-}}"
    [[ -z "${lmp_bin}" ]] && return 0

    local lmp_real lmp_dir lmp_prefix
    lmp_real="$(readlink -f "${lmp_bin}" 2>/dev/null || printf "%s" "${lmp_bin}")"
    lmp_dir="$(cd "$(dirname "${lmp_real}")" 2>/dev/null && pwd || true)"
    [[ -z "${lmp_dir}" ]] && return 0
    lmp_prefix="$(cd "${lmp_dir}/.." 2>/dev/null && pwd || true)"
    [[ -z "${lmp_prefix}" ]] && return 0

    [[ -d "${lmp_prefix}/lib" ]] && export LD_LIBRARY_PATH="$(prepend_path "${lmp_prefix}/lib" "${LD_LIBRARY_PATH:-}")"
    [[ -d "${lmp_prefix}/lib64" ]] && export LD_LIBRARY_PATH="$(prepend_path "${lmp_prefix}/lib64" "${LD_LIBRARY_PATH:-}")"
}

resolve_python_bin() {
    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    else
        echo "ERROR: No Python interpreter available after environment setup"
        return 1
    fi

    export PYTHON_BIN
}

setup_leonardo_environment() {
    load_leonardo_modules
    activate_mace_environment
    configure_runtime_paths
    add_lammps_binary_prefix_paths "${LMP_BIN:-}"
    resolve_python_bin
}

check_lammps_runtime() {
    local lmp_bin="${1:-${LMP_BIN:-}}"
    if [[ -z "${lmp_bin}" ]]; then
        echo "ERROR: LMP_BIN is not set"
        return 1
    fi

    if [[ ! -x "${lmp_bin}" ]]; then
        echo "ERROR: LMP_BIN not executable: ${lmp_bin}"
        return 1
    fi

    add_lammps_binary_prefix_paths "${lmp_bin}"

    if command -v ldd >/dev/null 2>&1; then
        local ldd_output
        ldd_output="$(ldd "${lmp_bin}" 2>&1 || true)"
        if grep -q "libmpi.so.40 => not found" <<< "${ldd_output}"; then
            echo "ERROR: MPI runtime missing for LAMMPS (${lmp_bin})"
            echo "       Tried module: ${MPI_MODULE:-none}"
            return 1
        fi
        if grep -q "libplumedKernel" <<< "${ldd_output}" && grep -q "libplumedKernel.*not found" <<< "${ldd_output}"; then
            echo "ERROR: PLUMED runtime missing for LAMMPS (${lmp_bin})"
            echo "       Set PLUMED_ROOT in configs/config_npt_bulk.env"
            return 1
        fi
        if grep -q "not found" <<< "${ldd_output}"; then
            echo "ERROR: LAMMPS runtime libraries missing for ${lmp_bin}"
            grep "not found" <<< "${ldd_output}"
            echo "       Check LAMMPS_ROOT and LMP_LIBRARY_PATH in configs/config_npt_bulk.env"
            return 1
        fi
    fi
}
