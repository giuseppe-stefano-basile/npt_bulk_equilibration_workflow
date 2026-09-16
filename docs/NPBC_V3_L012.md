# NPBC v3: coupled l=0,1,2 symmetry-channel mean field

## Status

This branch introduces the workflow and interface for a third-generation NPBC mean field

\[
U_B(r,\theta)=U_0(r)+U_1(r)P_1(\cos\theta)+U_2(r)P_2(\cos\theta),
\]

with

\[
P_1(c)=c,\qquad P_2(c)=\frac{3c^2-1}{2}.
\]

The validated v2 update-80 scalar and l=2 fields are retained as the initial v3 state. The l=1 field starts from zero.

The custom LAMMPS v2 source is not part of this repository; on Leonardo it lives in the untracked custom source tree under `lammps-glob-dev/src`. Therefore this repository defines the v3 runtime contract, inputs, seed fields, validation, and source-patch specification. The C++ `cavity/meanfield/v3` style must be built into the custom Leonardo LAMMPS tree before the v3 inputs are runnable.

## Physical convention

For each water molecule, define

- molecular COM position `R`, with `r=|R|` and `n=R/r`;
- water bisector `q=(H1+H2)/2-O`;
- molecular orientation `u=q/|q|`;
- `c=u.n`.

The v3 field is

\[
U=U_0(r)+U_1(r)c+U_2(r)\frac{3c^2-1}{2}.
\]

The l=0 channel controls the radial number-density mode, l=1 controls signed/polar orientational order, and l=2 controls apolar/nematic orientational order.

## R20 basis and active coefficients

R20 uses

- `R = 20 A`
- `dr = 0.25 A`
- `nl = 81`
- physical layers `k=0..79`
- control/ghost layer `k=80`
- angular active interval `17 <= r < 20 A`, corresponding to `k=68..79`.

Boundary policies:

- scalar: `a[80] = a[79] - 13`, preserving the validated scalar edge condition;
- l=1: `b1[80] = b1[79]`;
- l=2: `b2[80] = b2[79]`.

The angular copy condition is an even/Neumann-like continuation intended to avoid adding an artificial sharp radial angular force exactly at the wall.

## Seed state

v3 starts from the stationary-validated v2 update-80 state:

- `bias/gau_R20_v3_U0_seed_update80.dat`
- `bias/gau1_R20_v3_U1_zero.dat`
- `bias/gau2_R20_v3_U2_seed_update80.dat`

The U0 and U2 source SHA-256 values are recorded in the files themselves.

## Fully coupled response problem

Use additive density-normalized angular observables, not conditional-angle means, so every observable remains canonical-response compatible.

Observables:

- 43 density observables;
- 12 l=1 observables `sum P1/(rho0 Vg)`;
- 12 l=2 observables `sum P2/(rho0 Vg)`.

Total: 67 observables.

Adjustable coefficients:

- 42 scalar U0 coefficients (same scalar response parameterization as v2);
- 12 U1 coefficients (`k=68..79`);
- 12 U2 coefficients (`k=68..79`).

Total: 66 parameters.

The response matrix must be the full matrix

\[
R_{ij}=-\beta\,\mathrm{Cov}\left(x_i,\frac{\partial U}{\partial\theta_j}\right),
\]

including all density/l=1/l=2 cross-blocks. Do not solve three independent response systems.

Targets are

- density: bulk target used by the scalar optimizer;
- l=1: zero;
- l=2: zero.

For a Gaussian radial basis `phi_k(r)`, parameter derivatives are

\[
\frac{\partial U}{\partial a_k}=\phi_k(r),
\]

\[
\frac{\partial U}{\partial b_{1k}}=\phi_k(r)P_1(c),
\]

\[
\frac{\partial U}{\partial b_{2k}}=\phi_k(r)P_2(c).
\]

## Exact conservative derivatives

Let

\[
A(r,c)=U_1(r)+3cU_2(r).
\]

Because

\[
\nabla_R c=\frac{u-cn}{r},
\]

the molecular-COM contribution of the angular channels is

\[
F_{COM}^{ang}=-\left[U_1'(r)c+U_2'(r)P_2(c)\right]n
-\frac{A(r,c)}{r}(u-cn).
\]

The scalar contribution remains `-U0'(r)n`.

For orientation,

\[
\frac{\partial U}{\partial u}=A(r,c)n.
\]

With `u=q/|q|`,

\[
g_q=\frac{I-uu^T}{|q|}A(r,c)n.
\]

The internal orientational forces are

- `F_H1 = -0.5 g_q`
- `F_H2 = -0.5 g_q`
- `F_O  = +g_q`

and therefore sum exactly to zero.

The COM force must be distributed to the atoms with the same mass-weighted COM convention used by the validated v2 implementation. This preserves the molecular translational force while the internal angular force carries zero net force.

The v3 finite-difference force test must cover pure U1, pure U2, and mixed U1+U2 cases and should reproduce the v2-level numerical agreement before production use.

## Proposed LAMMPS v3 interface

The new style should be separate during development:

```text
FixStyle(cavity/meanfield/v3,FixCavityMeanfieldV3)
```

Suggested interface:

```text
fix mf water cavity/meanfield/v3 sphere 0 0 0 ${R} ${rho0} ${dr} ${nl} &
    vdwparm ${vdwparm_file} &
    gaufile ${gaufile_u0} &
    vdw_scale ${vdw_scale} &
    opt yes &
    update response &
    p1 yes &
    p1_otype 1 &
    p1_htype 2 &
    p1_rmin 17.0 &
    p1_scale ${vdw_scale} &
    p1file ${gaufile_u1} &
    p1out ${p1out_file} &
    p1_eta 0.05 &
    p1_lambda_l2 0.002 &
    p1_lambda_smooth 1.0 &
    p1_delta_max 1.0 &
    p1_ghost copy &
    p2 yes &
    p2_otype 1 &
    p2_htype 2 &
    p2_rmin 17.0 &
    p2_scale ${vdw_scale} &
    p2file ${gaufile_u2} &
    p2out ${p2out_file} &
    p2_eta 0.05 &
    p2_lambda_l2 0.002 &
    p2_lambda_smooth 1.0 &
    p2_delta_max 1.0 &
    p2_ghost copy &
    response_temp 300 &
    response_sample_every 500 &
    response_update_every 100000 &
    response_eta 0.05 &
    response_lambda_l2 0.002 &
    response_lambda_smooth 1.0 &
    response_density_floor_rel 0.02 &
    response_p1_floor 0.02 &
    response_p2_floor 0.02 &
    response_weight_mode sem &
    response_sem_lag1 yes &
    response_delta_max 1.50
```

The exact parser names are part of the v3 contract defined by this branch; they are intentionally not overloaded onto the v2 `orient_*` namespace.

For alanine production, the same style is used with water O/H atom types corresponding to the alanine system (`O=3`, `H=4`).

## Initial optimization policy

Retain the validated v2 response cadence initially:

- sample every 500 steps = 0.5 ps;
- update every 100000 steps = 100 ps;
- 200 raw samples per response solve.

This gives 200 samples for 66 parameters before regularization. The first v3 pilot should keep conservative trust limits, especially for U1, because the frozen-v2 virtual l=1 response showed an unfavorable density cross-response when U1 was optimized in isolation.

Recommended first-pilot caps:

- U0: 1.5
- U1: 1.0
- U2: 1.0

with eta 0.05 and L2/smooth regularization 0.002/1.0. These are pilot values, not universal constants.

## Required validation sequence

1. Static file validation (`scripts/validate_npbc_v3_fields.py`).
2. Compile the new v3 style in the Leonardo custom LAMMPS tree.
3. `run 0` parse test.
4. Deterministic one-water finite-difference force test:
   - U1 only;
   - U2 only;
   - U1+U2;
   - radial and tangential perturbations.
5. Short NVE test with frozen U0/U1/U2.
6. 100-ps response smoke from the validated v2 update-80 restart with U1 initially zero.
7. Inspect separate `chi2_rho`, `chi2_p1`, `chi2_p2`, all max coefficient changes, and the full response conditioning.
8. Continue optimization only if all three channels behave stably.
9. Freeze the final v3 field and repeat the 1-ns validation used for v2: density, P1, P2, RDF, H-bond network, tetrahedral order, global COM and anisotropy.

## Interpretation guardrail

The v2 frozen validation showed that correcting P2 did not materially recover near-wall H-bond/tetrahedral structure. v3 should therefore be evaluated as a symmetry-resolved one-body boundary PMF, not assumed to reconstruct all many-body bulk-network observables. If density/P1/P2 are corrected while H-bond topology remains surface-like, that is a representational limitation to report, not a reason to hide the diagnostic.
