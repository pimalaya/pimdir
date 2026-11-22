#!/usr/bin/env bash
# Runs io-pimdir, checked out at the revision checks/io-pimdir.rev names,
# over this tree's store migrations, vectors and payloads. The statements,
# the index schema and the generator are io-pimdir's own and stay as that
# revision holds them. Fails first when that revision still lists a vector
# case as pending (tests/pending_vectors.txt, a case a line, comments aside):
# a suite passing beside cases it is allowed to fail is no gate.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
crate=$(cd "${1:?usage: checks/implementation.sh <io-pimdir checkout>}" && pwd)

want=$(tr -d '[:space:]' < "$root/checks/io-pimdir.rev")
have=$(git -C "$crate" rev-parse HEAD)
if [ "$have" != "$want" ]; then
  echo "io-pimdir is at $have, checks/io-pimdir.rev names $want" >&2
  exit 1
fi

pending="$crate/tests/pending_vectors.txt"
if [ -f "$pending" ] && grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$pending" >&2; then
  echo "io-pimdir at $have lists the vector cases above as pending: the gate needs the list empty" >&2
  exit 1
fi

for dir in migrations/storage vectors payloads; do
  rm -rf "${crate:?}/spec/$dir"
  mkdir -p "$(dirname "$crate/spec/$dir")"
  cp -r "$root/$dir" "$crate/spec/$dir"
done

cd "$crate"
nix develop --command cargo test --all-features --no-fail-fast
