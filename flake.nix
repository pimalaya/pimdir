{
  description = "The pimdir store format";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-25.11";
    };
  };

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      eachSystem = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The canonical files alone, so an edit to the prose rebuilds nothing.
      format = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./migrations
          ./queries
          ./vectors
        ];
      };

      # The canonical files with the documents that name them.
      standard = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./migrations
          ./queries
          ./vectors
          ./OVERVIEW.md
          ./STORAGE.md
          ./SYNC.md
          ./SEARCH.md
          ./GUIDE.md
          ./README.md
        ];
      };

      python = pkgs: pkgs.python3.withPackages (ps: [ ps.blake3 ]);
    in
    {
      checks = eachSystem (pkgs: {
        schema = pkgs.runCommand "pimdir-schema" { nativeBuildInputs = [ pkgs.sqlite ]; } ''
          bash ${./checks/schema.sh} ${format} | tee $out
        '';

        invariants = pkgs.runCommand "pimdir-invariants" { nativeBuildInputs = [ pkgs.sqlite ]; } ''
          bash ${./checks/invariants.sh} ${format} | tee $out
        '';

        names = pkgs.runCommand "pimdir-names" { nativeBuildInputs = [ pkgs.sqlite ]; } ''
          bash ${./checks/names.sh} ${standard} | tee $out
        '';

        vectors = pkgs.runCommand "pimdir-vectors" { } ''
          ${python pkgs}/bin/python3 ${./checks/vectors.py} ${format} | tee $out
        '';
      });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.sqlite
            (python pkgs)
          ];
        };
      });
    };
}
