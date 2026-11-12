#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Holds the bytes a release froze (README.md, Status): every line of
# checks/frozen.sha256 names a file, or one row of queries/signatures.json,
# and the SHA-256 it had when its part was released; the check fails when one
# is gone or holds other bytes. The list is empty while every part is a
# draft, and the check then passes on nothing.
#
# Usage: frozen.sh <repository root> [list]
#        frozen.sh <repository root> --digest <target>...
#
# The second form prints the lines to add at a release, a target being a
# path, `path#name` for one signature row, or `path#prefix*` for every row
# whose name begins with the prefix.
set -euo pipefail

root="${1:-$PWD}"
shift || true

# row <file> <name>: the line of queries/signatures.json stating a
# statement's name, its trailing comma dropped, so a row keeps its digest
# whatever follows it.
row() {
    grep -F "{\"name\": \"$2\"," "$root/$1" | sed 's/,$//'
}

digest() {
    local target="$1" path name
    path="${target%%#*}"
    [ -f "$root/$path" ] || return 1
    if [ "$path" = "$target" ]; then
        sha256sum < "$root/$path" | cut -d' ' -f1
    else
        name="${target#*#}"
        [ -n "$(row "$path" "$name")" ] || return 1
        row "$path" "$name" | sha256sum | cut -d' ' -f1
    fi
}

if [ "${1:-}" = "--digest" ]; then
    shift
    for target in "$@"; do
        if [[ "$target" == *"#"*"*" ]]; then
            path="${target%%#*}"
            prefix="${target#*#}"
            grep -o "{\"name\": \"${prefix%\*}[^\"]*\"" "$root/$path" | cut -d'"' -f4 | while read -r name; do
                echo "$(digest "$path#$name")  $path#$name"
            done
        else
            echo "$(digest "$target")  $target"
        fi
    done
    exit 0
fi

list="${1:-$root/checks/frozen.sha256}"
failures=0
frozen=0
while read -r want target; do
    case "$want" in '' | '#'*) continue ;; esac
    frozen=$((frozen + 1))
    if ! grep -qxE '[0-9a-f]{64}' <<< "$want" || [ -z "$target" ]; then
        echo "frozen: a line states a SHA-256 and a path: $want $target" >&2
        failures=$((failures + 1))
    elif ! have="$(digest "$target")"; then
        echo "$target: frozen by a release, and gone" >&2
        failures=$((failures + 1))
    elif [ "$have" != "$want" ]; then
        echo "$target: frozen by a release at $want, now $have" >&2
        failures=$((failures + 1))
    fi
done < "$list"

if [ "$failures" -gt 0 ]; then
    echo "$failures frozen file(s) or row(s) moved: a released byte changes only by a new file, a new row or a new version" >&2
    exit 1
fi
echo "$frozen frozen files and rows hold the bytes their release froze"
