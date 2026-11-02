#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Fails when a part changed after its tag without a bump (AGENTS.md §2). For
# each part, the version its Status line states names a git tag once the user
# made it; the part's document and the files it owns are then the tag's, byte
# for byte, none added and none removed. A version no tag names yet passes,
# its files moving freely until tagged. The files a part owns: its migrations,
# statements and vectors with their schemas, STORAGE the payload schemas too,
# and the fixtures its vectors name (a fixture no vector names being
# STORAGE's); vectors/manifest.json, which lists every part's, is none's.
#
# Needs git and the repository's history and tags, so it runs outside the nix
# sandbox, in .github/workflows/tests.yml on a checkout with its tags.
set -euo pipefail

root="${1:-$PWD}"
cd "$root"
failures=0

# fixtures <vector file...>: the fixtures the files name, as paths.
fixtures() {
    grep -oh '"fixtures/[^"]*"' "$@" | tr -d '"' | sed 's|^|vectors/|' | sort -u
}

# part <document> <path...>: the document and the paths, compared with the
# tag its Status line names.
part() {
    local document="$1" version changed
    shift
    version="$(sed -n 's/^Status: \([a-z]*-\(draft-[0-9]*\|v[0-9][0-9.]*\)\),.*/\1/p' "$document")"
    if [ -z "$version" ]; then
        echo "$document: no version on its Status line" >&2
        failures=$((failures + 1))
        return
    fi
    if ! git rev-parse -q --verify "refs/tags/$version^{commit}" > /dev/null; then
        echo "$document: $version, no tag yet"
        return
    fi
    changed="$( { git diff --name-only "$version" -- "$document" "$@"
                  git ls-files --others --exclude-standard -- "$document" "$@"; } | sort -u)"
    if [ -n "$changed" ]; then
        echo "$document: changed after its tag $version without a bump:" $changed >&2
        failures=$((failures + 1))
    else
        echo "$document: identical to its tag $version"
    fi
}

named="$(fixtures vectors/summaries.json vectors/sync/*.json vectors/search/store.json)"
unnamed="$(comm -23 <(find vectors/fixtures -type f | sort) <(echo "$named"))"

part STORAGE.md migrations/storage queries/storage payloads vectors/objects.json vectors/summaries.json \
    vectors/payloads.json vectors/schema/objects.schema.json vectors/schema/summaries.schema.json \
    vectors/schema/payloads.schema.json $(fixtures vectors/summaries.json) $unnamed
part SYNC.md vectors/sync vectors/schema/sync.schema.json $(fixtures vectors/sync/*.json)
part SEARCH.md migrations/search queries/search vectors/search vectors/schema/search-store.schema.json \
    vectors/schema/search-queries.schema.json vectors/schema/search-chunks.schema.json \
    $(fixtures vectors/search/store.json)
part conventions/gtd.md conventions/gtd

if [ "$failures" -gt 0 ]; then
    echo "$failures part(s) changed after their tag; bump the version on the Status line, README and AGENTS.md" >&2
    exit 1
fi
