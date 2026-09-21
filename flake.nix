{
  description = "TALYS: simulation of nuclear reactions below 200 MeV";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      version = "2.2";

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Flags the TALYS Makefile applies by default for gfortran.
      fflags = "-w -O3 -ffp-contract=off";
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          src = pkgs.fetchurl {
            url = "https://nds.iaea.org/talys/codes/talys.tar";
            hash = "sha256-pB6TWkVkmnmyxLT2GNdx5LVPEnXfnY/hCVNo0dBG0LQ=";
          };

          talys-structure = pkgs.stdenv.mkDerivation {
            pname = "talys-structure";
            inherit version src;
            dontBuild = true;
            dontFixup = true;
            installPhase = ''
              mkdir -p "$out"
              cp -r structure "$out/structure"
            '';
          };

          # Real part of the Atomki-V2 alpha-nucleus potential (alphaomp 9),
          # tabulated for Z = 26-83, from the supplementary material of
          #   P. Mohr, Zs. Fülöp, Gy. Gyürky, G.G. Kiss, T. Szücs,
          #   At. Data Nucl. Data Tables 142, 101453 (2021).
          # One file per target, share/talys/atomki-v2/zZZZaAAAa_talys_alphaomp9real.gnu.
          talys-atomki-v2-potentials = pkgs.stdenv.mkDerivation {
            pname = "talys-atomki-v2-potentials";
            version = "2021";
            src = pkgs.fetchurl {
              url = "https://ars.els-cdn.com/content/image/1-s2.0-S0092640X2100036X-mmc1.zip";
              hash = "sha256-OeD1565wmXuBPBOShcEz0eEo868l8GTlrYINwVPZ2jI=";
            };
            nativeBuildInputs = [ pkgs.unzip ];
            dontUnpack = true;
            dontFixup = true;
            installPhase = ''
              mkdir -p "$out/share/talys/atomki-v2"
              unzip -p "$src" Atomki-V2_potentials.tgz \
                | tar -xz -C "$out/share/talys/atomki-v2"
              chmod 644 "$out"/share/talys/atomki-v2/*.gnu
            '';
          };

          talys = pkgs.stdenv.mkDerivation {
            pname = "talys";
            inherit version src;
            nativeBuildInputs = [ pkgs.gfortran ];

            # Adds "alphaomp 9": the Atomki-V2 alpha OMP of Mohr et al. (2021),
            # ported from the TALYS-1.8 sources in the paper's supplementary
            # material.  The real potential is read from alphaomp9real.gnu in
            # the working directory (see talys-atomki-v2-potentials).
            patches = [ ./patches/atomki-v2.patch ];

            postPatch = ''
              # Do what path_change.bash does, but with the store path.
              sed -i "s|^  codedir.*|  codedir = '${talys-structure}/'|" source/machine.f90
              grep -n "codedir =" source/machine.f90   # sanity check in the log
              # The Makefile's `change` target would put /build/talys/ back.
              printf '#!/bin/sh\n' > path_change.bash
            '';

            buildPhase = ''
              runHook preBuild
              make -C source FC="''${FC:-gfortran}" FFLAGS="${fflags}"
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 bin/talys "$out/bin/talys"
              runHook postInstall
            '';
          };
        in
        {
          default = talys;
          inherit talys talys-structure talys-atomki-v2-potentials;
        }
      );

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.talys;
        };
      });

      # nix develop: build in the checkout the way the README describes,
      #   make -C source   (or ./install_talys.bash)
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.gfortran
            pkgs.gnumake
          ];

          shellHook = ''
            export TALYS_DIR="''${TALYS_DIR:-$PWD}"
            export PATH="$TALYS_DIR/bin:$PATH"
            export TALYS_USER="''${TALYS_USER:-$(id -un)}"

            echo "TALYS dev shell: TALYS_DIR=$TALYS_DIR"
            echo "  make -C source        build bin/talys with ${fflags}"
            echo "  make -C source check  run the sample cases (~1 hour)"
          '';
        };
      });

      # Short TALYS runs, to check that the executable finds and reads the
      # structure database.  The sample suite (make -C source check) takes
      # about an hour and is far too long for a flake check.
      checks = forAllSystems (
        pkgs:
        let
          talys = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.talys;
          potentials = self.packages.${pkgs.stdenv.hostPlatform.system}.talys-atomki-v2-potentials;
        in
        {
          smoke = pkgs.runCommand "talys-smoke-test" { } ''
            printf '%s\n' "projectile n" "element fe" "mass 56" "energy 14." \
              "filetotal y" > talys.inp

            ${talys} < talys.inp > talys.out

            grep -q "congratulates you with this successful calculation" talys.out
            test -s total.tot

            mkdir -p "$out"
            cp talys.inp talys.out total.tot "$out/"
          '';

          # alpha + Ni-58 with the Atomki-V2 potential (alphaomp 9).
          atomki-v2 = pkgs.runCommand "talys-atomki-v2-test" { } ''
            printf '%s\n' "projectile a" "element ni" "mass 58" "energy 10." \
              "alphaomp 9" "filetotal y" > talys.inp
            ln -s ${potentials}/share/talys/atomki-v2/z028a058a_talys_alphaomp9real.gnu \
              alphaomp9real.gnu

            ${talys} < talys.inp > talys.out

            grep -q "congratulates you with this successful calculation" talys.out
            grep -q "alphaomp            9" talys.out
            test -s total.tot

            mkdir -p "$out"
            cp talys.inp talys.out total.tot "$out/"
          '';
        }
      );
    };
}
