# talys-nix

A [Nix](https://nixos.org/) flake that packages [TALYS](https://github.com/arjankoning1/talys),
a code for the simulation of nuclear reactions below 200 MeV.

The source is the **frozen TALYS-2.2 distribution** (December 2025) from the
[IAEA](https://nds.iaea.org/talys/) — the same code that lives in the
`arjankoning1/talys` GitHub repository, but the fixed `talys.tar` snapshot
rather than the rolling `main` beta branch. It is fetched by a fixed
`sha256` hash, so builds are reproducible and will not silently change if the
IAEA tarball is updated.

TALYS is based on state-of-the-art nuclear structure and reaction models. See
the [TALYS tutorial](https://github.com/arjankoning1/talys/blob/main/doc/talys.pdf)
for the full description of the code and its options.

> Arjan Koning, Stéphanie Hilaire and Stéphanie Goriely, *TALYS: modeling of
> nuclear reactions*, European Physical Journal A59 (6), 131 (2023).

## Usage

TALYS reads its input file from standard input and writes its results to
standard output. The nuclear-structure database (`structure/`) is bundled with
the package and located automatically at run time, so no environment
variables are needed to run a calculation.

A minimal input file, for example `talys.inp`:

```
projectile n
element fe
mass 56
energy 14.
filetotal y
```

### Run a calculation

```
nix run github:ewtodd/talys-nix -- < talys.inp > talys.out
```

or, from a checkout of this repository:

```
nix run . -- < talys.inp > talys.out
```

### Build the package

```
nix build                 # builds the default package
```

### Develop against a local checkout

```
nix develop
```

The shell provides `gfortran` and `make`, and sets `TALYS_DIR`, `PATH`, and
`TALYS_USER`. You can then build and run TALYS yourself the usual way:

```
make -C source            # build bin/talys
make -C source check      # run the sample cases (~1 hour)
```

### Smoke test

```
nix flake check
```

(or `nix build .#checks`) runs one short calculation — a neutron on Fe-56 at
14 MeV — and checks that the executable finds and reads the `structure`
database. The full sample suite (`make -C source check`) takes about an hour
and is far too long for a flake check.

## Supported systems

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

## How it is built

- The frozen `talys.tar` is fetched from the IAEA by hash.
- A separate `talys-structure` derivation packages the `structure/` database.
- The main derivation compiles `source/` with `gfortran` using the same flags
  the TALYS Makefile applies by default (`-w -O3 -ffp-contract=off`), and
  installs only the `bin/talys` executable.
- During the build, `codedir` in `source/machine.f90` is set to the store path
  of `structure/` (what `path_change.bash` does for a manual install), and
  `path_change.bash` is stubbed out so the Makefile's `change` target does not
  override it.

## License

This repository (the flake) is licensed under the [MIT License](LICENSE). The
TALYS code itself is distributed under its own terms — see the `LICENSE` file
in the [upstream repository](https://github.com/arjankoning1/talys) and in the
frozen distribution.
