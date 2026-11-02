#!/bin/bash

# Looks for copied code with jscpd (github.com/Quartel-Enterprise/copied-code-check):
#   ./scripts/cpd.sh                                check: fails on copied code .jscpd-baseline.json doesn't list,
#                                                   and on copied code it still lists after it was removed
#   ./scripts/cpd.sh --update-baseline              write the copied code found now to .jscpd-baseline.json, when no
#                                                   file has more of it than the baseline lists, but a moved one
#   ./scripts/cpd.sh --update-baseline --allow-new  also take more copied code in, only when the copy is on purpose
#   ./scripts/cpd.sh --base <baseline of main>      check, and warn about copied code the baseline takes in (CI)
#
# What it scans is in .jscpd.json. This file never changes: the release that the workflows under .github/workflows
# use (Quartel-Enterprise/copied-code-check@X.Y.Z) picks the check and the jscpd it runs, so a local run and CI
# always agree. The release comes from its tag on GitHub, trusted like a GitHub Action pinned to a tag.
#
# Environment:
#   CPD_RUNNER_DIR  a checkout of copied-code-check to run instead of the pinned release (CI, or to try a change)
#   CPD_CACHE_DIR   where releases are cached (default ~/.cache/copied-code-check)

set -eo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." > /dev/null && pwd)"
RUNNER_DIR="$CPD_RUNNER_DIR"

if [ -z "$RUNNER_DIR" ]; then
    VERSIONS="$(grep -rhoE 'Quartel-Enterprise/copied-code-check@[^[:space:]"'\'']+' "$ROOT/.github/workflows" \
        2> /dev/null | sed 's/.*@//' | sort -u)"

    # A release version, never a branch: its files are cached for good, and release tags never move
    if ! [[ "$VERSIONS" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ The workflows under .github/workflows have to use one release of the check, as"
        echo "   uses: Quartel-Enterprise/copied-code-check@X.Y.Z. Found: '$(echo "$VERSIONS" | xargs)'"
        exit 1
    fi

    RUNNER_DIR="${CPD_CACHE_DIR:-$HOME/.cache/copied-code-check}/$VERSIONS"
    if [ ! -f "$RUNNER_DIR/scripts/cpd.sh" ]; then
        mkdir -p "$(dirname "$RUNNER_DIR")"
        TMP="$(mktemp -d "$RUNNER_DIR.XXXXXX")"
        if ! curl -fsSL "https://codeload.github.com/Quartel-Enterprise/copied-code-check/tar.gz/refs/tags/$VERSIONS" \
            | tar -xz --strip-components=1 -C "$TMP"; then
            rm -rf "$TMP"
            echo "❌ Failed to download the copied-code check $VERSIONS"
            exit 1
        fi
        # Why: a concurrent run may have cached the same release first; its copy is as good as this one.
        if [ -e "$RUNNER_DIR" ]; then
            rm -rf "$TMP"
        else
            mv "$TMP" "$RUNNER_DIR"
        fi
    fi
fi

CPD_PROJECT_ROOT="$ROOT" exec bash "$RUNNER_DIR/scripts/cpd.sh" "$@"
