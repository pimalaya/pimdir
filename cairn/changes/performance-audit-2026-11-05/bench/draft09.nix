# SPDX-License-Identifier: MIT OR Apache-2.0
#
# bench/draft09.c built against SQLite 3.18.2 (the floor, as flake.nix's
# sqliteFloor builds it) and the pinned nixpkgs' SQLite, both with the AOSP
# flags of Android 8.0, so the two differ by their version alone.
#
# Usage: nix-build draft09.nix
{ pkgs ? import (builtins.getFlake (toString ../../../..)).inputs.nixpkgs { } }:
let
  flags = "-DNDEBUG=1 -DHAVE_USLEEP=1 -DSQLITE_HAVE_ISNAN -DSQLITE_DEFAULT_JOURNAL_SIZE_LIMIT=1048576 -DSQLITE_THREADSAFE=2 -DSQLITE_TEMP_STORE=3 -DSQLITE_POWERSAFE_OVERWRITE=1 -DSQLITE_DEFAULT_FILE_FORMAT=4 -DSQLITE_DEFAULT_AUTOVACUUM=1 -DSQLITE_ENABLE_MEMORY_MANAGEMENT=1 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_BACKWARDS -DSQLITE_ENABLE_FTS4 -DSQLITE_OMIT_BUILTIN_TEST -DSQLITE_OMIT_COMPILEOPTION_DIAGS -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DEFAULT_FILE_PERMISSIONS=0600 -DSQLITE_SECURE_DELETE -DUSE_PREAD64 -Dfdatasync=fdatasync -DHAVE_MALLOC_H=1 -DHAVE_MALLOC_USABLE_SIZE -DHAVE_POSIX_FALLOCATE=1 -O2";
  build = version: src: pkgs.stdenv.mkDerivation {
    pname = "draft09-bench";
    inherit version src;
    dontConfigure = true;
    buildPhase = ''
      $CC ${flags} -I. -c sqlite3.c -o sqlite3.o
      $CC ${flags} -I. ${./draft09.c} sqlite3.o -o draft09 -lpthread -lm -ldl
    '';
    installPhase = "install -Dm755 draft09 $out/bin/draft09-${version}";
  };
in
pkgs.symlinkJoin {
  name = "draft09-bench";
  paths = [
    (build "3.18.2" (pkgs.fetchurl {
      url = "https://www.sqlite.org/2017/sqlite-autoconf-3180200.tar.gz";
      sha256 = "1fn188cpk8rl5n6f1jslyz2zbvvhap44m6ai1icmk98qm0p24h0d";
    }))
    (build pkgs.sqlite.version pkgs.sqlite.src)
  ];
}
