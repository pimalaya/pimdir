#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Holds the bytes a release froze (README.md, Status): every line of
# checks/frozen.sha256 names a file and the SHA-256 it had when its part was
# released; the check fails when one is gone or holds other bytes. The list
# is empty while every part is a draft, and the check then passes on nothing.
# A line naming lists after its path freezes a case file to a prefix, which
# checks/appended.py holds, and is skipped here.
#
# Usage: frozen.sh <repository root> [list]
#        frozen.sh <repository root> --digest <path>...
#
# The second form prints the lines to add at a release.
set -euo pipefail

root="${1:-$PWD}"
shift || true

digest() {
    [ -f "$root/$1" ] || return 1
    sha256sum < "$root/$1" | cut -d' ' -f1
}

if [ "${1:-}" = "--digest" ]; then
    shift
    for path in "$@"; do
        echo "$(digest "$path")  $path"
    done
    exit 0
fi

list="${1:-$root/checks/frozen.sha256}"
failures=0
frozen=0
while read -r want path lists; do
    case "$want" in '' | '#'*) continue ;; esac
    [ -z "$lists" ] || continue
    frozen=$((frozen + 1))
    if ! grep -qxE '[0-9a-f]{64}' <<< "$want" || [ -z "$path" ]; then
        echo "frozen: a line states a SHA-256 and a path: $want $path" >&2
        failures=$((failures + 1))
    elif ! have="$(digest "$path")"; then
        echo "$path: frozen by a release, and gone" >&2
        failures=$((failures + 1))
    elif [ "$have" != "$want" ]; then
        echo "$path: frozen by a release at $want, now $have" >&2
        failures=$((failures + 1))
    fi
done < "$list"

if [ "$failures" -gt 0 ]; then
    echo "$failures frozen file(s) moved: a released byte changes only by a new file or a new version" >&2
    exit 1
fi
echo "$frozen frozen files hold the bytes their release froze"
