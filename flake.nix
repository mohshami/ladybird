{
  description = "Ladybird browser, packaged for NixOS without vcpkg";

  # Usage:
  #
  #   nix build .#ladybird     # build the browser
  #   nix run .#ladybird       # run it
  #   nix develop .#           # a development shell with everything the build needs
  #   nix flake check          # build the checks
  #
  # The browser is built from the source of this flake. To build the working
  # tree, including uncommitted changes, use:
  #
  #   nix build "path:$PWD#ladybird"
  #
  # To install it in a NixOS system, use the module:
  #
  #   programs.ladybird.enable = true;
  #   programs.ladybird.package = self.packages.${pkgs.stdenv.hostPlatform.system}.ladybird;
  #
  # The build does not use vcpkg, but Nixpkgs' packages for the third-party
  # dependencies, the way Nixpkgs' own ladybird package does.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          llvm-libc-headers = pkgs.callPackage ./nix/llvm-libc-headers.nix { };
        in
        rec {
          inherit llvm-libc-headers;

          ladybird = pkgs.callPackage ./nix/ladybird.nix {
            # The flake's own source, without the files that only the flake
            # needs, so that a change to them does not rebuild the browser.
            # To build the working tree, including uncommitted changes, use
            # `nix build "path:$PWD#ladybird"`.
            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.difference ./. (
                lib.fileset.unions [
                  ./flake.lock
                  ./flake.nix
                  ./nix
                ]
              );
            };
            inherit llvm-libc-headers;
          };

          default = ladybird;
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "ladybird-shell";

          # Everything the build needs, so that the tree can be built with
          # CMake and Ninja inside the shell.
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.ladybird ];

          # The build system of Ladybird expects the libraries that its vcpkg
          # ports install. `nix run .#prepare-tree` changes the tree so that
          # it builds against the system libraries instead.
          shellHook = ''
            echo "Run 'nix run .#prepare-tree' before configuring the tree with CMake."
          '';

          packages = [
            pkgs.cargo
            pkgs.cargo-audit
            pkgs.ccache
            pkgs.clippy
            pkgs.clang-tools
            pkgs.cmake
            pkgs.dejavu_fonts
            pkgs.glslang
            pkgs.liberation_ttf
            pkgs.ninja
            pkgs.perl
            pkgs.pkg-config
            pkgs.python3
            pkgs.qt6Packages.qtbase
            pkgs.qt6Packages.qttools
            pkgs.rustc
            pkgs.rustfmt
          ];

          # Without ICU_ROOT, CMake cannot locate the ICU headers, and without
          # a font configuration the browser crashes with SIGILL on startup,
          # because its font fallback lists require fonts that a default NixOS
          # installation does not have.
          ICU_ROOT = "${pkgs.icu78.dev}";

          FONTCONFIG_FILE = pkgs.makeFontsConf {
            fontDirectories = [
              pkgs.dejavu_fonts
              pkgs.liberation_ttf
            ];
          };

          NIX_LDFLAGS = "-lGL -lfontconfig";
        };
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.ladybird}/bin/Ladybird";
        };
        js = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.ladybird}/bin/js";
        };

        # Makes a tree ready for a build against system libraries, for a
        # development shell.
        prepare-tree = {
          type = "app";
          program =
            let
              script = pkgs.writeShellApplication {
                name = "prepare-tree";
                runtimeInputs = [ pkgs.patch ];
                text = ''
                  export PDFJS_DIR="${pkgs.pdfjs}/share/pdf.js"
                  exec sh ${./nix/prepare-tree.sh} "$@"
                '';
              };
            in
            "${script}/bin/prepare-tree";
        };
      });

      checks = forAllSystems (pkgs: {
        # The browser itself.
        ladybird = self.packages.${pkgs.stdenv.hostPlatform.system}.ladybird;

        # The JavaScript engine, which is the cheapest way to check that the
        # build works.
        js =
          pkgs.runCommand "ladybird-js-check"
            {
              nativeBuildInputs = [ self.packages.${pkgs.stdenv.hostPlatform.system}.ladybird ];
            }
            ''
              js --evaluate 'console.log(6 * 7)' | grep -q 42
              touch $out
            '';
      });

      nixosModules = {
        ladybird = import ./nix/module.nix;
        default = self.nixosModules.ladybird;
      };

      # nixfmt-tree only formats the Nix files of the tree, unlike nixfmt,
      # which tries to parse every file it is given.
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
