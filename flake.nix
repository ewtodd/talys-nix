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

          talys = pkgs.stdenv.mkDerivation {
            pname = "talys";
            inherit version src;
            nativeBuildInputs = [ pkgs.gfortran ];

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

      # One short TALYS run, to check that the executable finds and reads the
      # structure database.  The sample suite (make -C source check) takes
      # about an hour and is far too long for a flake check.
      checks = forAllSystems (pkgs: {
        smoke = pkgs.runCommand "talys-smoke-test" { } ''
          printf '%s\n' "projectile n" "element fe" "mass 56" "energy 14." \
            "filetotal y" > talys.inp

          ${nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.talys} \
            < talys.inp > talys.out

          grep -q "congratulates you with this successful calculation" talys.out
          test -s total.tot

          mkdir -p "$out"
          cp talys.inp talys.out total.tot "$out/"
        '';
      });
    };
}
