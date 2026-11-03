#!/usr/bin/env bash
# Runs io-pimdir, checked out at the revision checks/io-pimdir.rev names,
# over this tree's migrations, statements, vectors and payloads.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
crate=$(cd "${1:?usage: checks/implementation.sh <io-pimdir checkout>}" && pwd)

want=$(tr -d '[:space:]' < "$root/checks/io-pimdir.rev")
have=$(git -C "$crate" rev-parse HEAD)
if [ "$have" != "$want" ]; then
  echo "io-pimdir is at $have, checks/io-pimdir.rev names $want" >&2
  exit 1
fi

for dir in migrations queries vectors payloads; do
  rm -rf "${crate:?}/spec/$dir"
  cp -r "$root/$dir" "$crate/spec/$dir"
done

cd "$crate"
nix develop --command cargo test --all-features --no-fail-fast
