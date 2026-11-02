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
          ./payloads
          ./vectors
        ];
      };

      # The canonical files with the documents that name them, and the
      # scenarios, whose capability names checks/names.sh reads.
      standard = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./migrations
          ./queries
          ./payloads
          ./vectors
          ./checks/invariants.sh
          ./OVERVIEW.md
          ./STORAGE.md
          ./SYNC.md
          ./SEARCH.md
          ./GUIDE.md
          ./conventions
          ./README.md
        ];
      };

      python = pkgs: pkgs.python3.withPackages (ps: [
        ps.blake3
        ps.jsonschema
      ]);

      # The oldest SQLite the store schema loads on (STORAGE.md §4.1): 3.18.2,
      # the platform SQLite of Android 8.0 (API 26), built with the flags of
      # AOSP external/sqlite dist/Android.mk on oreo-release, as the Android
      # app's flake builds it:
      # https://android.googlesource.com/platform/external/sqlite/+/refs/heads/oreo-release/dist/Android.mk
      # sqlite.org has no 3.18.2 amalgamation zip, so the sources come from the
      # autoconf tarball. The shell alone is installed.
      sqliteFloor = pkgs: pkgs.stdenv.mkDerivation {
        pname = "sqlite-floor";
        version = "3.18.2";
        src = pkgs.fetchurl {
          url = "https://www.sqlite.org/2017/sqlite-autoconf-3180200.tar.gz";
          sha256 = "1fn188cpk8rl5n6f1jslyz2zbvvhap44m6ai1icmk98qm0p24h0d";
        };
        buildInputs = [ pkgs.icu ];
        dontConfigure = true;
        buildPhase = ''
          flags="-DNDEBUG=1 -DHAVE_USLEEP=1 -DSQLITE_HAVE_ISNAN \
            -DSQLITE_DEFAULT_JOURNAL_SIZE_LIMIT=1048576 -DSQLITE_THREADSAFE=2 \
            -DSQLITE_TEMP_STORE=3 -DSQLITE_POWERSAFE_OVERWRITE=1 \
            -DSQLITE_DEFAULT_FILE_FORMAT=4 -DSQLITE_DEFAULT_AUTOVACUUM=1 \
            -DSQLITE_ENABLE_MEMORY_MANAGEMENT=1 -DSQLITE_ENABLE_FTS3 \
            -DSQLITE_ENABLE_FTS3_BACKWARDS -DSQLITE_ENABLE_FTS4 \
            -DSQLITE_OMIT_BUILTIN_TEST -DSQLITE_OMIT_COMPILEOPTION_DIAGS \
            -DSQLITE_OMIT_LOAD_EXTENSION \
            -DSQLITE_DEFAULT_FILE_PERMISSIONS=0600 -DSQLITE_SECURE_DELETE \
            -DSQLITE_ENABLE_ICU -DUSE_PREAD64 -Dfdatasync=fdatasync \
            -DHAVE_MALLOC_H=1 -DHAVE_MALLOC_USABLE_SIZE \
            -DHAVE_POSIX_FALLOCATE=1 -O2 -fPIC -I."
          libs="-licui18n -licuuc -ldl -lpthread -lm"

          $CC $flags -c sqlite3.c -o sqlite3.o
          $CC $flags shell.c sqlite3.o -o sqlite3 $libs
        '';
        installPhase = ''
          install -Dm755 sqlite3 $out/bin/sqlite3
        '';
        doInstallCheck = true;
        installCheckPhase = ''
          test "$($out/bin/sqlite3 :memory: 'SELECT sqlite_version();')" = 3.18.2
        '';
      };
    in
    {
      checks = eachSystem (pkgs: {
        schema = pkgs.runCommand "pimdir-schema" { nativeBuildInputs = [ pkgs.sqlite ]; } ''
          bash ${./checks/schema.sh} ${format} | tee $out
        '';

        invariants = pkgs.runCommand "pimdir-invariants" { nativeBuildInputs = [ pkgs.sqlite ]; } ''
          bash ${./checks/invariants.sh} ${format} ${./checks/waivers.txt} | tee $out
        '';

        names = pkgs.runCommand "pimdir-names" { nativeBuildInputs = [ pkgs.sqlite ]; } ''
          bash ${./checks/names.sh} ${standard} | tee $out
        '';

        vectors = pkgs.runCommand "pimdir-vectors" { } ''
          ${python pkgs}/bin/python3 ${./checks/vectors.py} ${standard} | tee $out
        '';

        # Every markdown file outside cairn/, and every file a link names, so
        # the whole source rather than a fileset.
        references = pkgs.runCommand "pimdir-references" { nativeBuildInputs = [ pkgs.perl ]; } ''
          perl ${./checks/references.pl} ${./.} | tee $out
        '';
      } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        # Android's flags build on Linux alone (malloc.h, fdatasync).
        floor = pkgs.runCommand "pimdir-floor" { nativeBuildInputs = [ pkgs.sqlite ]; } ''
          bash ${./checks/floor.sh} ${format} ${sqliteFloor pkgs}/bin/sqlite3 | tee $out
        '';
      });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.sqlite
            pkgs.perl
            (python pkgs)
          ];
        };
      });
    };
}
