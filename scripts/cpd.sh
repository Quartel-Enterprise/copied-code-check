#!/bin/bash

# Looks for copied code in a project with jscpd (github.com/kucherenko/jscpd) and compares it with the project's
# .jscpd-baseline.json:
#
#   cpd.sh                                check: fails on copied code the baseline doesn't list, and on copied code
#                                         it still lists after it was removed
#   cpd.sh --update-baseline              write the copied code found now to the baseline, when no file has more of
#                                         it than the baseline lists, but a moved one
#   cpd.sh --update-baseline --allow-new  also take more copied code in, only when the copy is on purpose
#   cpd.sh --base <baseline of main>      check, and warn about copied code the baseline takes in (CI)
#
# Consumers don't copy this file: their own scripts/cpd.sh is a small wrapper that runs it from the release they
# pin, so the check and the jscpd it runs always match that release.
#
# Environment:
#   CPD_PROJECT_ROOT  the project to scan (the wrapper sets it; defaults to the current git repository)

set -e

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." > /dev/null && pwd)"

# Why: the check runs from the project root, so a relative --base path is made absolute against where it was called.
args=()
while [ $# -gt 0 ]; do
    if [ "$1" = "--base" ] && [ $# -gt 1 ] && [ "${2#/}" = "$2" ]; then
        args+=("$1" "$PWD/$2")
        shift 2
    else
        args+=("$1")
        shift
    fi
done
set -- "${args[@]}"

cd "${CPD_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"

if [ ! -f .jscpd.json ]; then
    echo "❌ No .jscpd.json in $PWD: it says which paths and languages to scan"
    exit 1
fi

if ! command -v npm > /dev/null || ! command -v node > /dev/null \
    || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)'; then
    echo "❌ jscpd needs Node.js 18 or later (https://nodejs.org)"
    exit 1
fi

# The jscpd release jscpd/package.json pins, with every dependency its lockfile locks. Installed again only when
# the lockfile changed since the last install.
TOOL="$HERE/jscpd"
if ! cmp -s "$TOOL/package-lock.json" "$TOOL/node_modules/.installed-lock.json"; then
    npm ci --prefix "$TOOL" --no-audit --no-fund --loglevel=error
    cp "$TOOL/package-lock.json" "$TOOL/node_modules/.installed-lock.json"
fi

REPORT="$(mktemp -d)"
trap 'rm -rf "$REPORT"' EXIT

# Why: the check reads one JSON report with absolute paths, so the reporter, its directory and the paths are set
# here, whatever the project's .jscpd.json says about them.
if ! "$TOOL/node_modules/.bin/jscpd" --config .jscpd.json --reporters json --output "$REPORT" --absolute; then
    echo "❌ jscpd failed: see its error above, or set \"silent\" to false in .jscpd.json for more"
    exit 1
fi

node "$HERE/scripts/cpd-check.mjs" "$REPORT/jscpd-report.json" .jscpd-baseline.json "$@"
