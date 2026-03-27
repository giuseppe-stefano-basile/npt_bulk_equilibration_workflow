#!/usr/bin/env python3
"""
Extract 15 Å sphere and equivalent-volume cube from NPT final frame.

Purpose:
  1. Extract 15 Å NPBC sphere around solute COM
  2. Extract equiv-volume cube around solute COM for PBC comparison
  3. Write corresponding LAMMPS .data files ready for production

Features:
  - Center on alanine COM (solute molecule ID 1)
  - NPBC sphere: cavity/reflect boundary
  - PBC cube: periodic boundaries with solute COM at center
  - Both inherit frozen solute from NPT run
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from collections import defaultdict


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract sphere and cube systems from NPT final frame"
    )
    parser.add_argument("--npt-data", default="bulk_water_alanine_npt_final.data", 
                       help="NPT final .data file")
    parser.add_argument("--sphere-r", type=float, default=15.0, help="Sphere radius (Å)")
    parser.add_argument("--cube-edge", type=float, default=24.2, help="Cube edge length (Å)")
    parser.add_argument("--sphere-out", default="alanine_cavity_R15_from_npt.data",
                       help="Output sphere .data file for NPBC")
    parser.add_argument("--cube-out", default="alanine_pbc_from_npt.data",
                       help="Output cube .data file for PBC")
    parser.add_argument("--padding", type=float, default=1.0, help="Extra clearance for bounds (Å)")
    parser.add_argument("--verbose", action="store_true", help="Debug output")
    return parser.parse_args()


def read_data_file(path: Path) -> tuple[dict, list[dict], list[dict], dict]:
    """
    Read LAMMPS .data file.
    Returns: (box_dict, atoms_list, molecules_list, masses_dict)
    """
    box = {}
    atoms = []
    masses = {}
    
    with open(path) as f:
        lines = f.readlines()
    
    mode = None
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        
        # Parse box dimensions
        if "xlo xhi" in line:
            parts = line.split()
            box["xlo"] = float(parts[0])
            box["xhi"] = float(parts[1])
        elif "ylo yhi" in line:
            parts = line.split()
            box["ylo"] = float(parts[0])
            box["yhi"] = float(parts[1])
        elif "zlo zhi" in line:
            parts = line.split()
            box["zlo"] = float(parts[0])
            box["zhi"] = float(parts[1])
        
        # Parse atoms — handle both 'Atoms' and 'Atoms # molecular'
        elif line.startswith("Atoms"):
            mode = "atoms"
            continue
        elif line == "Masses":
            mode = "masses"
            continue
        
        if mode == "atoms" and len(line.split()) >= 6:
            try:
                parts = line.split()
                atom_id = int(parts[0])
                mol_id = int(parts[1])
                atom_type = int(parts[2])
                # atom_style molecular: id mol type x y z [ix iy iz]
                # atom_style full:      id mol type charge x y z [ix iy iz]
                # Detect by trying to parse parts[3] as float:
                # if parts[3] looks like a coordinate (large magnitude), it's molecular
                test_val = float(parts[3])
                if len(parts) >= 7 and abs(test_val) < 10.0:
                    # Likely 'full' style with charge
                    x = float(parts[4])
                    y = float(parts[5])
                    z = float(parts[6])
                else:
                    # 'molecular' style — no charge column
                    x = float(parts[3])
                    y = float(parts[4])
                    z = float(parts[5])
                atoms.append({
                    "id": atom_id,
                    "mol": mol_id,
                    "type": atom_type,
                    "x": x,
                    "y": y,
                    "z": z,
                })
            except (ValueError, IndexError):
                pass
        
        elif mode == "masses" and len(line.split()) >= 2:
            try:
                parts = line.split()
                atom_type = int(parts[0])
                mass = float(parts[1])
                masses[atom_type] = mass
            except (ValueError, IndexError):
                pass
    
    # Build molecules (grouped by mol_id)
    molecules = defaultdict(list)
    for atom in atoms:
        molecules[atom["mol"]].append(atom["id"])
    
    return box, atoms, dict(molecules), masses


def get_solute_com(atoms: list[dict], masses: dict) -> tuple[float, float, float]:
    """Get mass-weighted center of mass of solute (molecule ID 1)."""
    solute_atoms = [a for a in atoms if a["mol"] == 1]
    if not solute_atoms:
        raise ValueError("No solute atoms found (mol_id=1)")
    
    total_mass = sum(masses.get(a["type"], 1.0) for a in solute_atoms)
    cx = sum(masses.get(a["type"], 1.0) * a["x"] for a in solute_atoms) / total_mass
    cy = sum(masses.get(a["type"], 1.0) * a["y"] for a in solute_atoms) / total_mass
    cz = sum(masses.get(a["type"], 1.0) * a["z"] for a in solute_atoms) / total_mass
    return cx, cy, cz


def extract_sphere(atoms: list[dict], center: tuple[float, float, float], 
                   radius: float) -> list[dict]:
    """Extract atoms within sphere of given radius centered at center."""
    cx, cy, cz = center
    extracted = []
    
    for atom in atoms:
        dx = atom["x"] - cx
        dy = atom["y"] - cy
        dz = atom["z"] - cz
        dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        if dist <= radius:
            extracted.append(atom)
    
    return extracted


def extract_cube(atoms: list[dict], center: tuple[float, float, float], 
                 edge: float) -> list[dict]:
    """Extract atoms within cube of given edge length centered at center."""
    cx, cy, cz = center
    half_edge = edge / 2
    extracted = []
    
    for atom in atoms:
        dx = abs(atom["x"] - cx)
        dy = abs(atom["y"] - cy)
        dz = abs(atom["z"] - cz)
        
        if dx <= half_edge and dy <= half_edge and dz <= half_edge:
            extracted.append(atom)
    
    return extracted


def renumber_atoms(atoms: list[dict]) -> list[dict]:
    """Renumber atom IDs sequentially starting from 1."""
    old_to_new = {}
    for i, atom in enumerate(atoms, 1):
        old_to_new[atom["id"]] = i
        atom["id"] = i
    return atoms


def get_unique_mols(atoms: list[dict]) -> set[int]:
    """Get unique molecule IDs."""
    return set(a["mol"] for a in atoms)


def write_data_file(path: Path, atoms: list[dict], box: dict, masses: dict, 
                    is_periodic: bool = False, periodic_edge: float = None,
                    sphere_r: float = None):
    """Write LAMMPS .data file in atom_style molecular format (matching reference)."""
    
    # Count atom types and molecules
    n_atoms = len(atoms)
    n_types = max(a["type"] for a in atoms) if atoms else 1
    
    with open(path, "w") as f:
        if is_periodic:
            f.write(f"LAMMPS data file: PBC cube extraction (edge={periodic_edge:.2f} Å) (atom_style molecular)\n")
        else:
            f.write(f"LAMMPS data file: ACE-ALA-NME in spherical water cavity (atom_style molecular)\n")
        f.write(f"# Type order: 1=C  2=N  3=O  4=H\n\n")
        
        f.write(f"{n_atoms:>12} atoms\n")
        f.write(f"{0:>12} bonds\n")
        f.write(f"{0:>12} angles\n")
        f.write(f"{0:>12} dihedrals\n")
        f.write(f"{0:>12} impropers\n\n")
        f.write(f"{n_types:>12} atom types\n\n")
        
        # Box dimensions
        if is_periodic and periodic_edge:
            half = periodic_edge / 2
            f.write(f"{-half:20.10f} {half:20.10f} xlo xhi\n")
            f.write(f"{-half:20.10f} {half:20.10f} ylo yhi\n")
            f.write(f"{-half:20.10f} {half:20.10f} zlo zhi\n\n")
        else:
            # NPBC sphere: box = ±20 Å (matching reference)
            box_half = 20.0 if sphere_r is None else max(20.0, sphere_r + 5.0)
            f.write(f"{-box_half:20.10f} {box_half:20.10f} xlo xhi\n")
            f.write(f"{-box_half:20.10f} {box_half:20.10f} ylo yhi\n")
            f.write(f"{-box_half:20.10f} {box_half:20.10f} zlo zhi\n\n")
        
        # Masses — always write all 4 types (1=C, 2=N, 3=O, 4=H)
        f.write("Masses\n\n")
        for atype in range(1, n_types + 1):
            mass = masses.get(atype, 1.0)
            f.write(f"{atype:>3} {mass:10.6f}\n")
        f.write("\n")
        
        # Atoms — molecular style: id mol type x y z ix iy iz
        f.write("Atoms # molecular\n\n")
        for atom in atoms:
            f.write(f"{atom['id']:>6} {atom['mol']:>3} {atom['type']:>2} "
                   f"{atom['x']:>15.8f} {atom['y']:>15.8f} {atom['z']:>15.8f} 0 0 0\n")


def main():
    args = parse_args()
    
    print("[1/4] Reading NPT final frame...")
    npt_path = Path(args.npt_data)
    if not npt_path.exists():
        raise FileNotFoundError(f"NPT data file not found: {npt_path}")
    
    box, atoms, molecules, masses = read_data_file(npt_path)
    print(f"  Loaded {len(atoms)} atoms in {len(molecules)} molecules")
    
    print("[2/4] Computing solute COM...")
    solute_com = get_solute_com(atoms, masses)
    print(f"  Solute COM: ({solute_com[0]:.3f}, {solute_com[1]:.3f}, {solute_com[2]:.3f}) Å")
    
    print(f"[3/4] Extracting sphere (R={args.sphere_r} Å, NPBC)...")
    sphere_atoms = extract_sphere(atoms, solute_com, args.sphere_r)
    sphere_atoms = renumber_atoms(sphere_atoms)
    n_waters_sphere = len([a for a in sphere_atoms if a["mol"] > 1])
    print(f"  Extracted {len(sphere_atoms)} atoms ({n_waters_sphere} water molecules)")
    
    print(f"[4/4] Extracting cube (edge={args.cube_edge} Å, PBC)...")
    cube_atoms = extract_cube(atoms, solute_com, args.cube_edge)
    cube_atoms = renumber_atoms(cube_atoms)
    n_waters_cube = len([a for a in cube_atoms if a["mol"] > 1])
    print(f"  Extracted {len(cube_atoms)} atoms ({n_waters_cube} water molecules)")
    
    print(f"\nWriting output files...")
    sphere_path = Path(args.sphere_out)
    write_data_file(sphere_path, sphere_atoms, box, masses, is_periodic=False,
                   sphere_r=args.sphere_r)
    print(f"  ✓ {sphere_path}")
    
    cube_path = Path(args.cube_out)
    write_data_file(cube_path, cube_atoms, box, masses, is_periodic=True, 
                   periodic_edge=args.cube_edge)
    print(f"  ✓ {cube_path}")
    
    print("\n=== Extraction Summary ===")
    print(f"NPT system: {len(atoms)} atoms")
    print(f"Solute COM: {solute_com}")
    print(f"Sphere (R={args.sphere_r} Å): {len(sphere_atoms)} atoms, {n_waters_sphere} waters")
    print(f"Cube (edge={args.cube_edge} Å): {len(cube_atoms)} atoms, {n_waters_cube} waters")
    print(f"Density match: sphere={n_waters_sphere/(4/3*math.pi*args.sphere_r**3):.6f}, "
          f"cube={n_waters_cube/(args.cube_edge**3):.6f} (mol/Å³)")


if __name__ == "__main__":
    main()
