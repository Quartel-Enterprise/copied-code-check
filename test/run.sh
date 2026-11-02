#!/bin/bash

# Runs the check on small projects built here, through the consumer wrapper, as a project runs it.
set -euo pipefail

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." > /dev/null && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Why: a fresh copy, as a project gets it, so the first run installs jscpd like a release's first run does.
export CPD_RUNNER_DIR="$WORK/runner"
mkdir -p "$CPD_RUNNER_DIR/jscpd"
cp -R "$HERE/scripts" "$CPD_RUNNER_DIR/"
cp "$HERE/jscpd/package.json" "$HERE/jscpd/package-lock.json" "$CPD_RUNNER_DIR/jscpd/"

failures=0
OUTPUT=""

# A Kotlin function long enough for jscpd's 70 tokens and for 5 lines of code.
kotlin_copy() {
    cat << 'KT'
fun total(prices: List<Int>, discount: Int, taxRate: Double): Double {
    val subtotal = prices.filter { it > 0 }.sum()
    val discounted = if (subtotal > discount) subtotal - discount else 0
    val taxes = discounted * taxRate
    val rounded = Math.round((discounted + taxes) * 100.0) / 100.0
    println("subtotal=$subtotal discounted=$discounted taxes=$taxes")
    return if (rounded < 0.0) 0.0 else rounded
}
KT
}

new_project() {
    PROJECT="$WORK/$1"
    mkdir -p "$PROJECT/scripts" "$PROJECT/src"
    cp "$HERE/consumer/cpd.sh" "$PROJECT/scripts/cpd.sh"
    cat > "$PROJECT/.jscpd.json" << 'JSON'
{
  "path": ["src"],
  "format": ["kotlin", "swift", "tsx"],
  "formatsExts": { "tsx": ["ts", "tsx"] },
  "minTokens": 70,
  "gitignore": false,
  "silent": true
}
JSON
}

# Runs the check in $PROJECT with $@, and keeps its output and exit code.
run() {
    local code=0
    OUTPUT="$(cd "$PROJECT" && ./scripts/cpd.sh "$@" 2>&1)" || code=$?
    STATUS=$code
}

expect() {
    local name="$1" status="$2" text="$3"
    if [ "$STATUS" != "$status" ] || ! grep -qF -- "$text" <<< "$OUTPUT"; then
        echo "❌ $name: expected exit $status and \"$text\", got exit $STATUS:"
        while IFS= read -r line; do echo "   $line"; done <<< "$OUTPUT"
        failures=$((failures + 1))
    else
        echo "✅ $name"
    fi
}

new_project kotlin
{ echo "package a"; echo; kotlin_copy; } > "$PROJECT/src/First.kt"
{ echo "package b"; echo; kotlin_copy; } > "$PROJECT/src/Second.kt"

run
expect "copied code the baseline doesn't list fails" 1 "New copied code in src/First.kt: 8 lines where the baseline lists 0"

run --update-baseline
expect "the baseline takes no new copied code without --allow-new" 1 "only takes more copied code in with --allow-new"

run --update-baseline --allow-new
expect "--allow-new writes the baseline" 0 "copied lines in 2 files"

run
expect "copied code the baseline lists passes" 0 "No new copied code (16 copied lines in 2 files"

echo '{}' > "$WORK/empty-baseline.json"
run --base ../empty-baseline.json
expect "a relative --base warns about copied code the baseline takes in" 0 "::warning file=.jscpd-baseline.json::The baseline takes in copied code in 2 files"

mkdir -p "$PROJECT/src/nonIos"
mv "$PROJECT/src/Second.kt" "$PROJECT/src/nonIos/Second.nonIos.kt"
run
expect "a move with the copied code fails until the baseline is updated" 1 "Moved with its copied code (8 lines): src/Second.kt → src/nonIos/Second.nonIos.kt"

run --update-baseline
expect "the baseline takes a move in without --allow-new" 0 "copied lines in 2 files"

mv "$PROJECT/src/nonIos/Second.nonIos.kt" "$PROJECT/src/Renamed.kt"
run --update-baseline
expect "a rename is new copied code" 1 "New copied code in src/Renamed.kt"

run --update-baseline --allow-new
{ echo "package b"; echo; echo "fun other() = 1"; } > "$PROJECT/src/Renamed.kt"
run
expect "removed copied code fails until the baseline is updated" 1 "Less copied code than the baseline lists (0 of 8 lines): src/First.kt"

run --update-baseline
expect "the baseline takes removed copied code out" 0 "0 copied lines in 0 files"

new_project typescript
for name in first second; do
    {
        echo "import {"
        echo "    alpha, beta, gamma, delta, epsilon, zeta, eta, theta, iota, kappa, lambda, mu, nu, xi, omicron,"
        echo "    pi, rho, sigma, tau, upsilon, phi, chi, psi, omega, one, two, three, four, five, six, seven,"
        echo "    eight, nine, ten, eleven, twelve, thirteen, fourteen, fifteen, sixteen, seventeen, eighteen,"
        echo "} from \"./letters\";"
        echo "export const $name = () => alpha;"
    } > "$PROJECT/src/$name.ts"
done
run
expect "jscpd finds the imports copied between TypeScript files" 0 "Found 1 exact clones"
expect "imports copied between TypeScript files aren't copied code" 0 "No new copied code (0 copied lines in 0 files"

new_project no-config
rm "$PROJECT/.jscpd.json"
run
expect "a project without .jscpd.json fails" 1 "No .jscpd.json"

new_project unpinned
unset CPD_RUNNER_DIR
mkdir -p "$PROJECT/.github/workflows"
printf 'steps:\n  - uses: Quartel-Enterprise/copied-code-check@main\n' > "$PROJECT/.github/workflows/a.yml"
run
expect "the wrapper refuses a branch" 1 "have to use one release of the check"
printf 'steps:\n  - uses: Quartel-Enterprise/copied-code-check@1.0.0\n' > "$PROJECT/.github/workflows/a.yml"
printf 'steps:\n  - uses: Quartel-Enterprise/copied-code-check@1.0.1\n' > "$PROJECT/.github/workflows/b.yml"
run
expect "the wrapper refuses two releases" 1 "Found: '1.0.0 1.0.1'"

printf 'steps:\n  - run: echo no pin\n' > "$PROJECT/.github/workflows/a.yml"
rm "$PROJECT/.github/workflows/b.yml"
run
expect "the wrapper explains a missing pin" 1 "have to use one release of the check"
rm -rf "$PROJECT/.github"
run
expect "the wrapper explains a project without workflows" 1 "have to use one release of the check"

# The download path, as a developer and release.yml run it: a release tarball, cached once, by runs started together.
new_project downloaded
{ echo "package a"; echo; kotlin_copy; } > "$PROJECT/src/First.kt"
{ echo "package b"; echo; kotlin_copy; } > "$PROJECT/src/Second.kt"
mkdir -p "$PROJECT/.github/workflows" "$WORK/releases" "$WORK/release/copied-code-check-9.9.9"
cat > "$PROJECT/.github/workflows/duplication.yml" << 'YML'
# Pinned below, not here: Quartel-Enterprise/copied-code-check@0.0.1
jobs:
  duplication:
    steps:
      # - uses: Quartel-Enterprise/copied-code-check@0.0.2
      - uses: 'Quartel-Enterprise/copied-code-check@9.9.9'
YML
cp -R "$HERE/scripts" "$HERE/jscpd" "$WORK/release/copied-code-check-9.9.9/"
rm -rf "$WORK/release/copied-code-check-9.9.9/jscpd/node_modules" "$WORK/release/copied-code-check-9.9.9/jscpd/".install*
tar -czf "$WORK/releases/9.9.9" -C "$WORK/release" copied-code-check-9.9.9
export CPD_DOWNLOAD_URL="file://$WORK/releases" CPD_CACHE_DIR="$WORK/cache"
(code=0; cd "$PROJECT" && ./scripts/cpd.sh > "$WORK/first.log" 2>&1 || code=$?; echo "$code" > "$WORK/first.status") &
(code=0; cd "$PROJECT" && ./scripts/cpd.sh > "$WORK/second.log" 2>&1 || code=$?; echo "$code" > "$WORK/second.status") &
wait
for log in first second; do
    STATUS="$(cat "$WORK/$log.status")"
    OUTPUT="$(cat "$WORK/$log.log")"
    expect "two runs caching a release at once both check ($log)" 1 "New copied code in src/First.kt"
done
STATUS=0
OUTPUT="$(find "$WORK/cache" -mindepth 1 -maxdepth 1; find -L "$WORK/cache/9.9.9/jscpd" -mindepth 1 -maxdepth 1 -name '.install*')"
expect "the cache keeps one copy of the release" 0 "$WORK/cache/9.9.9"
if [ "$(find "$WORK/cache" -mindepth 1 -maxdepth 1 | wc -l)" -ne 2 ] \
    || [ "$(find -L "$WORK/cache/9.9.9/jscpd" -mindepth 1 -maxdepth 1 -name '.install*' | wc -l)" -ne 2 ]; then
    echo "❌ the cache holds a leftover copy:"
    echo "$OUTPUT"
    failures=$((failures + 1))
fi
rm "$WORK/cache/9.9.9/scripts/cpd.sh"
run
expect "a cached release missing its runner is downloaded again" 1 "New copied code in src/First.kt"

if [ "$failures" -gt 0 ]; then
    echo "❌ $failures failed"
    exit 1
fi
echo "✅ All passed"
