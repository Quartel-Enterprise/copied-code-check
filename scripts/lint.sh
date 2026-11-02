#!/bin/bash

# Lints the repository as CI does: shellcheck on the scripts and on the action's run blocks (actionlint only reads
# workflows), node's syntax check on the check, then actionlint on the workflows.
set -euo pipefail
cd "$(dirname "$0")/.."

shellcheck scripts/*.sh consumer/*.sh test/*.sh
node --check scripts/cpd-check.mjs

blocks=$(mktemp -d)
trap 'rm -rf "$blocks"' EXIT
python3 - "$blocks" <<'PY'
import pathlib, re, sys, yaml

out = pathlib.Path(sys.argv[1])
for i, step in enumerate(yaml.safe_load(pathlib.Path("action.yml").read_text())["runs"]["steps"]):
    if "run" in step:
        # An expression stands for a plain word, as GitHub substitutes it before bash runs.
        body = re.sub(r"\$\{\{.*?\}\}", "EXPR", step["run"], flags=re.S)
        (out / f"action-{i}.sh").write_text("#!/bin/bash\n" + body)
PY
shellcheck "$blocks"/*.sh

actionlint
