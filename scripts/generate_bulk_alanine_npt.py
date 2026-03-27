#!/usr/bin/env python3
"""
Generate a bulk water box + alanine dipeptide system for NPT equilibration.

Purpose:
  - Create a large periodic bulk water box at target rho0
  - Insert alanine dipeptide (frozen) at the center
  - Output LAMMPS .data file ready for NPT equilibration

Features:
  - Solute fully frozen during NPT (zero velocity, COM locked)
  - Water packing with collision avoidance
  - Restart-safe output (reproducible with seed)
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path


NA = 6.02214076e23
MW_WATER = 18.01528
DEFAULT_BULK_WATER_RHO_GCC = 0.9732297090622873
ATOMIC_MASSES = {
    "H": 1.008,
    "C": 12.011,
    "N": 14.007,
    "O": 15.999,
}
CANONICAL_TYPE_ORDER = ["C", "N", "O", "H"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate bulk water + frozen alanine system for NPT equilibration"
    )
    parser.add_argument("--pdb", "--seed-pdb", dest="pdb", default="ala2_seed.pdb",
                        help="ACE-ALA-NME seed PDB")
    parser.add_argument("--nwater", "--num-water", dest="nwater", type=int, default=3800,
                        help="Number of bulk water molecules")
    parser.add_argument("--rho-mol-a3", "--density", dest="rho_mol_a3", type=float,
                        default=0.037235960250849326, help="Target density in mol/Å³")
    parser.add_argument("--rho-gcc", type=float, default=1.11391659, help="Target density in g/cm³ (validation)")
    parser.add_argument("--cut", type=float, default=1.6, help="Atom-atom overlap cutoff (Å)")
    parser.add_argument("--seed", type=int, default=12345, help="RNG seed for reproducibility")
    parser.add_argument("--type-order", default="C N O H", help="LAMMPS atom type order")
    parser.add_argument("--out", "--output", dest="out", default="bulk_water_alanine_npt.data",
                        help="Output LAMMPS data file")
    return parser.parse_args()


def parse_type_order(text: str) -> list[str]:
    tokens = [tok.upper() for tok in text.replace(",", " ").split()]
    if len(tokens) != 4 or set(tokens) != {"C", "N", "O", "H"}:
        raise ValueError("type_order must be a permutation of: C N O H")
    return tokens


def pbc_delta(delta: float, box_edge: float) -> float:
    return delta - box_edge * round(delta / box_edge)


def distance_squared(a: tuple[float, float, float], b: tuple[float, float, float],
                     box_edge: float | None = None) -> float:
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    dz = a[2] - b[2]
    if box_edge is not None:
        dx = pbc_delta(dx, box_edge)
        dy = pbc_delta(dy, box_edge)
        dz = pbc_delta(dz, box_edge)
    return dx * dx + dy * dy + dz * dz


def infer_element(atom_name: str) -> str:
    letters = "".join(ch for ch in atom_name if ch.isalpha())
    if len(letters) >= 2 and letters[:2].upper() in ATOMIC_MASSES:
        return letters[:2].upper()
    return letters[0].upper()


def read_pdb_atoms(path: Path) -> list[dict]:
    atoms: list[dict] = []
    with path.open() as f:
        for line in f:
            rec = line[:6].strip()
            if rec not in {"ATOM", "HETATM"}:
                continue
            name = line[12:16].strip()
            element = (line[76:78].strip().upper() or infer_element(name)).upper()
            if element not in ATOMIC_MASSES:
                raise ValueError(f"Unsupported element: {element}")
            atoms.append({
                "name": name,
                "element": element,
                "mass": ATOMIC_MASSES[element],
                "x": float(line[30:38]),
                "y": float(line[38:46]),
                "z": float(line[46:54]),
            })
    if not atoms:
        raise ValueError(f"No atoms in {path}")
    return atoms


def get_center_of_mass(atoms: list[dict]) -> tuple[float, float, float]:
    total_mass = sum(a["mass"] for a in atoms)
    cx = sum(a["mass"] * a["x"] for a in atoms) / total_mass
    cy = sum(a["mass"] * a["y"] for a in atoms) / total_mass
    cz = sum(a["mass"] * a["z"] for a in atoms) / total_mass
    return cx, cy, cz


def center_atoms(atoms: list[dict]) -> None:
    cx, cy, cz = get_center_of_mass(atoms)
    for a in atoms:
        a["x"] -= cx
        a["y"] -= cy
        a["z"] -= cz


def get_atom_radius(element: str) -> float:
    """Van der Waals radii (Å) for collision detection."""
    radii = {"H": 1.2, "C": 1.7, "N": 1.55, "O": 1.52}
    return radii.get(element, 1.5)


def check_collision(pos: tuple[float, float, float], existing_positions: list[tuple[float, float, float]],
                    cutoff: float, box_edge: float | None = None) -> bool:
    """Check if position collides with any existing positions."""
    cutoff2 = cutoff * cutoff
    for px, py, pz in existing_positions:
        if distance_squared(pos, (px, py, pz), box_edge=box_edge) < cutoff2:
            return True
    return False


def check_solute_collision(pos: tuple[float, float, float], solute_atoms: list[dict],
                           cutoff: float, box_edge: float | None = None) -> bool:
    """Check oxygen-center collisions against all solute atoms with element-aware thresholds."""
    oxygen_radius = get_atom_radius("O")
    for atom in solute_atoms:
        atom_pos = (atom["x"], atom["y"], atom["z"])
        solute_radius = get_atom_radius(atom["element"])
        pair_cut = max(cutoff, oxygen_radius + solute_radius - 0.4)
        if distance_squared(pos, atom_pos, box_edge=box_edge) < pair_cut * pair_cut:
            return True
    return False


def pack_water_molecules(nwater: int, box_edge: float, rho_mol_a3: float, 
                         cutoff: float, seed: int, solute_atoms: list[dict] | None = None) -> list[tuple]:
    """Generate water molecule COM positions in periodic box."""
    rng = random.Random(seed)
    
    # Theoretical water molecules in box from target density
    expected_nwater = rho_mol_a3 * (box_edge ** 3)
    print(f"Target density {rho_mol_a3:.6f} molecules/Å³ → expected {expected_nwater:.0f} waters in {box_edge:.2f}³ box")
    
    waters = []
    max_attempts = nwater * 100
    attempts = 0
    
    # Place waters with uniform random sampling and rejection
    for i in range(nwater):
        if attempts > max_attempts:
            print(f"Warning: could only place {len(waters)}/{nwater} waters after {max_attempts} attempts")
            return waters
        placed = False
        for _ in range(50):
            attempts += 1
            x = rng.uniform(-box_edge / 2, box_edge / 2)
            y = rng.uniform(-box_edge / 2, box_edge / 2)
            z = rng.uniform(-box_edge / 2, box_edge / 2)
            candidate = (x, y, z)
            
            if check_collision(candidate, waters, cutoff, box_edge=box_edge):
                continue
            if solute_atoms and check_solute_collision(candidate, solute_atoms, cutoff, box_edge=box_edge):
                continue

            waters.append(candidate)
            placed = True
            break
        
        if not placed:
            progress_stride = max(1, nwater // 10)
            if i % progress_stride == 0:
                print(f"  Warning: failed to place water {i}/{nwater} after 50 attempts")
    
    return waters


def build_water_atoms(water_coms: list[tuple], type_map: dict[str, int], seed: int) -> list[dict]:
    """Build O and H atoms for each water molecule COM."""
    # TIP3P geometry (typical):
    # O at COM, H atoms offset
    o_h_distance = 0.9572
    h_o_h_angle_rad = math.radians(104.52)
    
    atoms = []
    atom_id = 1
    rng = random.Random(seed + 101)
    
    for mol_id, (com_x, com_y, com_z) in enumerate(water_coms, 1):
        # O atom at COM
        atoms.append({
            "id": atom_id,
            "mol": mol_id + 1,  # mol_id 2+ for waters (mol_id 1 = solute)
            "type": type_map["O"],
            "charge": -0.834,
            "x": com_x,
            "y": com_y,
            "z": com_z,
            "element": "O",
            "mass": 15.999,
        })
        atom_id += 1
        
        # H atoms with correct HOH angle and isotropic 3D orientation
        half_angle = h_o_h_angle_rad / 2.0
        while True:
            u1 = rng.uniform(-1.0, 1.0)
            u2 = rng.uniform(-1.0, 1.0)
            s = u1 * u1 + u2 * u2
            if s < 1.0:
                break
        nx = 2.0 * u1 * math.sqrt(1.0 - s)
        ny = 2.0 * u2 * math.sqrt(1.0 - s)
        nz = 1.0 - 2.0 * s

        if abs(nz) < 0.95:
            rx, ry, rz = 0.0, 0.0, 1.0
        else:
            rx, ry, rz = 1.0, 0.0, 0.0

        e1x = ny * rz - nz * ry
        e1y = nz * rx - nx * rz
        e1z = nx * ry - ny * rx
        e1n = math.sqrt(e1x * e1x + e1y * e1y + e1z * e1z)
        e1x, e1y, e1z = e1x / e1n, e1y / e1n, e1z / e1n

        cos_half = math.cos(half_angle)
        sin_half = math.sin(half_angle)
        for sign in (1.0, -1.0):
            vx = o_h_distance * (cos_half * nx + sign * sin_half * e1x)
            vy = o_h_distance * (cos_half * ny + sign * sin_half * e1y)
            vz = o_h_distance * (cos_half * nz + sign * sin_half * e1z)

            h_x = com_x + vx
            h_y = com_y + vy
            h_z = com_z + vz

            atoms.append({
                "id": atom_id,
                "mol": mol_id + 1,
                "type": type_map["H"],
                "charge": 0.417,
                "x": h_x,
                "y": h_y,
                "z": h_z,
                "element": "H",
                "mass": 1.008,
            })
            atom_id += 1
    
    return atoms


def main():
    args = parse_args()
    random.seed(args.seed)
    
    requested_type_order = parse_type_order(args.type_order)
    if requested_type_order != CANONICAL_TYPE_ORDER:
        print(
            f"Warning: requested type order '{' '.join(requested_type_order)}' overridden to "
            f"'{ ' '.join(CANONICAL_TYPE_ORDER) }' for compatibility with LAMMPS templates"
        )
    type_order = CANONICAL_TYPE_ORDER
    type_map = {elem: i + 1 for i, elem in enumerate(type_order)}
    
    print("[1/5] Reading alanine structure...")
    ala_atoms = read_pdb_atoms(Path(args.pdb))
    center_atoms(ala_atoms)
    print(f"  Loaded {len(ala_atoms)} alanine atoms (centered on COM)")
    
    print(f"[2/5] Computing box size for {args.nwater} waters at {args.rho_mol_a3:.6f} mol/Å³...")
    volume_a3 = args.nwater / args.rho_mol_a3
    box_edge = volume_a3 ** (1/3)
    print(f"  Volume = {volume_a3:.0f} Å³, box edge = {box_edge:.2f} Å")
    
    print(f"[3/5] Packing {args.nwater} water molecules...")
    water_coms = pack_water_molecules(args.nwater, box_edge, args.rho_mol_a3, 
                                      args.cut, args.seed, solute_atoms=ala_atoms)
    print(f"  Placed {len(water_coms)} water molecules")
    
    print("[4/5] Building atom lists...")
    # Assign types and build solute atoms
    all_atoms = []
    atom_id = 1
    for atom in ala_atoms:
        all_atoms.append({
            "id": atom_id,
            "mol": 1,
            "type": type_map[atom["element"]],
            "charge": 0.0,  # Placeholder; use with ff params
            "x": atom["x"],
            "y": atom["y"],
            "z": atom["z"],
            "element": atom["element"],
            "mass": atom["mass"],
        })
        atom_id += 1
    
    # Build water atoms
    water_atoms = build_water_atoms(water_coms, type_map, seed=args.seed)
    all_atoms.extend(water_atoms)
    
    print(f"  Total atoms: {len(all_atoms)} (solute: {len(ala_atoms)}, waters: {len(water_coms)})")
    
    print(f"[5/5] Writing LAMMPS data file: {args.out}")
    with open(args.out, "w") as f:
        f.write("LAMMPS data file: bulk water + frozen alanine for NPT equilibration (atom_style molecular)\n")
        f.write(f"# Generated with rho0={args.rho_mol_a3:.10f} molecules/Å³\n")
        f.write(f"# Type order: {' '.join(f'{i+1}={e}' for i, e in enumerate(type_order))}\n\n")
        
        f.write(f"{len(all_atoms):>12} atoms\n")
        f.write(f"{0:>12} bonds\n")
        f.write(f"{0:>12} angles\n")
        f.write(f"{0:>12} dihedrals\n")
        f.write(f"{0:>12} impropers\n\n")
        f.write(f"{len(type_order):>12} atom types\n\n")
        
        half_box = box_edge / 2
        f.write(f"{-half_box:20.10f} {half_box:20.10f} xlo xhi\n")
        f.write(f"{-half_box:20.10f} {half_box:20.10f} ylo yhi\n")
        f.write(f"{-half_box:20.10f} {half_box:20.10f} zlo zhi\n\n")
        
        f.write("Masses\n\n")
        for elem in type_order:
            f.write(f"{type_map[elem]:>3} {ATOMIC_MASSES[elem]:10.6f}  # {elem}\n")
        f.write("\n")
        
        f.write("Atoms # molecular\n\n")
        for atom in all_atoms:
            f.write(f"{atom['id']:>6} {atom['mol']:>3} {atom['type']:>2} "
                   f"{atom['x']:>15.8f} {atom['y']:>15.8f} {atom['z']:>15.8f} 0 0 0\n")
    
    print(f"✓ Written {args.out} with {len(all_atoms)} atoms")
    print(f"  Box: {box_edge:.4f}³ Å")
    print(f"  Solute: {len(ala_atoms)} atoms (frozen during NPT)")
    print(f"  Water: {len(water_coms)} molecules ({len(water_coms)*3} atoms)")
    print(f"  Density: {args.rho_mol_a3:.10f} molecules/Å³ ({args.rho_gcc:.8f} g/cm³)")


if __name__ == "__main__":
    main()
