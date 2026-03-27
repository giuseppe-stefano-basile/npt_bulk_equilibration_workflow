#!/usr/bin/env python3
"""
Analyze NPT convergence from LAMMPS log files.

Purpose:
  - Extract density/pressure/temperature timeseries from log
  - Compute running averages
  - Assess convergence in production phase
  - Generate diagnostic plots
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from collections import defaultdict


def parse_lammps_log(log_file: Path) -> dict[str, list[float]]:
    """Extract thermodynamic data from LAMMPS log file."""
    data = defaultdict(list)
    
    # Pattern: "Step Temp Press Density Volume"
    thermo_pattern = re.compile(r"^\s*(\d+)\s+([\d.E+-]+)\s+([\d.E+-]+)\s+([\d.E+-]+)\s+([\d.E+-]+)")
    
    in_thermo = False
    with open(log_file) as f:
        for line in f:
            if line.strip() == "Step Temp Press Density Volume" or \
               re.search(r"Step.*Temp.*Press.*Density.*Volume", line):
                in_thermo = True
                continue
            
            if in_thermo:
                match = thermo_pattern.match(line)
                if match:
                    step, temp, press, dens, vol = match.groups()
                    data["step"].append(int(step))
                    data["temp"].append(float(temp))
                    data["press"].append(float(press))
                    data["density"].append(float(dens))
                    data["volume"].append(float(vol))
                elif not line.strip().startswith(('---', 'Loop', 'Minimization')):
                    # Non-thermo line outside pattern; might end thermo section
                    if len(data["step"]) > 10:
                        in_thermo = False
    
    return dict(data)


def analyze_convergence(data: dict[str, list[float]], window_ps: float = 100.0, 
                       dt_fs: float = 1.0) -> dict:
    """Analyze convergence metrics."""
    if not data["step"]:
        return {}
    
    # Convert time window to steps
    window_steps = int(window_ps * 1000 / dt_fs)
    
    # Use final window
    n = len(data["step"])
    start_idx = max(0, n - window_steps)
    
    analysis = {
        "n_samples": n,
        "final_step": data["step"][-1],
        "temp_mean": sum(data["temp"][start_idx:]) / (n - start_idx),
        "temp_std": (sum((x - sum(data["temp"][start_idx:])/(n-start_idx))**2 
                         for x in data["temp"][start_idx:]) / (n - start_idx)) ** 0.5,
        "press_mean": sum(data["press"][start_idx:]) / (n - start_idx),
        "press_std": (sum((x - sum(data["press"][start_idx:])/(n-start_idx))**2 
                          for x in data["press"][start_idx:]) / (n - start_idx)) ** 0.5,
        "dens_mean": sum(data["density"][start_idx:]) / (n - start_idx),
        "dens_std": (sum((x - sum(data["density"][start_idx:])/(n-start_idx))**2 
                         for x in data["density"][start_idx:]) / (n - start_idx)) ** 0.5,
    }
    
    return analysis


def main():
    parser = argparse.ArgumentParser(
        description="Analyze NPT convergence from LAMMPS log"
    )
    parser.add_argument("log_file", help="LAMMPS log file")
    parser.add_argument("--phase", choices=["eq", "prod"], default="prod",
                       help="Phase being analyzed")
    parser.add_argument("--window-ps", type=float, default=100.0,
                       help="Window for final statistics (ps)")
    parser.add_argument("--dt-fs", type=float, default=1.0,
                       help="Timestep (fs)")
    args = parser.parse_args()
    
    log_path = Path(args.log_file)
    if not log_path.exists():
        print(f"Error: {log_path} not found")
        return
    
    print(f"Parsing {log_path}...")
    data = parse_lammps_log(log_path)
    
    if not data["step"]:
        print("No thermodynamic data found in log")
        return
    
    analysis = analyze_convergence(data, args.window_ps, args.dt_fs)
    
    print(f"\n=== NPT {args.phase.upper()} Convergence Analysis ===")
    print(f"Total samples: {analysis['n_samples']}")
    print(f"Final step: {analysis['final_step']}")
    print(f"Window: last {args.window_ps} ps ({args.window_ps/args.dt_fs:.0f} steps)\n")
    
    print(f"Temperature (K):")
    print(f"  Mean: {analysis['temp_mean']:.2f}")
    print(f"  Std:  {analysis['temp_std']:.2f}")
    print(f"  Error: ±{analysis['temp_std']/analysis['temp_mean']*100:.2f}%\n")
    
    print(f"Pressure (atm):")
    print(f"  Mean: {analysis['press_mean']:.2f}")
    print(f"  Std:  {analysis['press_std']:.2f}\n")
    
    print(f"Density (g/cm³):")
    print(f"  Mean: {analysis['dens_mean']:.6f}")
    print(f"  Std:  {analysis['dens_std']:.6f}")
    print(f"  Rel Std: {analysis['dens_std']/analysis['dens_mean']*100:.3f}%\n")
    
    # Interpretation
    print("=== Interpretation ===")
    if analysis['temp_std'] / analysis['temp_mean'] < 0.01:
        print("✓ Temperature well-controlled (<1% variation)")
    else:
        print("⚠ Temperature fluctuating (>1% variation)")
    
    if analysis['press_std'] < 100:
        print("✓ Pressure stable (<100 atm std)")
    else:
        print("⚠ Pressure unstable (>100 atm std)")
    
    if analysis['dens_std'] / analysis['dens_mean'] < 0.005:
        print("✓ Density converged (<0.5% variation)")
    else:
        print("⚠ Density not converged (>0.5% variation)")


if __name__ == "__main__":
    main()
