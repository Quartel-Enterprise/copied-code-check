# copied-code-check

Stops new copied code from merging. Each pull request is checked with [jscpd](https://github.com/kucherenko/jscpd)
against a baseline of the copies the project already has, and that baseline can only shrink. The check runs the
same way on a developer machine (`./scripts/cpd.sh`) and in CI (a GitHub Action).

It was built for Kotlin Multiplatform apps with Swift and TypeScript UIs, and works on any language jscpd knows.

## How it works

`.jscpd-baseline.json` lists, per file, how many of its lines of code are in a copy today:

```json
{
  "feature/day/src/commonMain/kotlin/DayViewModel.kt": 12,
  "feature/plan/src/commonMain/kotlin/PlanViewModel.kt": 12
}
```

The check runs jscpd, counts the same thing, and compares:

- **A file with more copied lines than the baseline lists fails.** That is new copied code: extract it into one
  place the callers share. When a copy is on purpose, the author takes it into the baseline with `--allow-new`, and
  the pull request shows it to the reviewer.
- **A file with fewer fails too**, until `--update-baseline` writes the lower number. Removed copies are recorded,
  so they can't come back unnoticed.

A failure lists both copies of each clone:

```
❌ New copied code in src/First.kt: 8 lines where the baseline lists 0
   src/First.kt:3-10
   src/Second.kt:3-10

Extract the copied code into one place the callers share. Only when the copy is on purpose,
run ./scripts/cpd.sh --update-baseline --allow-new and say why in the pull request.
```

## Requirements

- macOS or Linux with `bash`, `curl` and `tar` (Windows only through WSL).
- Node.js 18 or later.
- A GitHub repository with Actions, for the CI check.

## Setup

Run these from the root of the repository, in this order: the script reads the release to run from the workflow.

**1. The workflow.** Add `.github/workflows/duplication.yml`:

```yaml
name: duplication
on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  duplication:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: Quartel-Enterprise/copied-code-check@1.0.3
```

The action fetches the pull request's base branch to compare baselines, with the credentials `actions/checkout`
keeps by default: on a private repository, don't set `persist-credentials: false`.

**2. The script.** It is a small wrapper you never edit. It runs the release your workflow pins, so a local run
always matches CI:

```bash
mkdir -p scripts
curl -fsSLo scripts/cpd.sh \
  https://raw.githubusercontent.com/Quartel-Enterprise/copied-code-check/refs/tags/1.0.3/consumer/cpd.sh
chmod +x scripts/cpd.sh
```

**3. What to scan.** Add `.jscpd.json` with your own source folders, languages and the files to leave out:

```json
{
  "path": ["shared/src", "androidApp/src", "iosApp", "webApp/src"],
  "format": ["kotlin", "swift", "tsx"],
  "formatsExts": { "tsx": ["ts", "tsx"] },
  "minTokens": 70,
  "ignore": ["**/build/**", "**/node_modules/**", "**/*Test.kt", "**/*Tests.swift", "**/*.test.ts"],
  "gitignore": true
}
```

These are jscpd's [config file options](https://github.com/kucherenko/jscpd/blob/master/docs/rust.md), and
`format` takes any of its [supported formats](https://github.com/kucherenko/jscpd/blob/master/FORMATS.md). Every
folder in `path` has to exist, or jscpd stops with "path does not exist". Leave tests and generated code out: copies there are rarely worth extracting. `minTokens` is the smallest clone jscpd
reports; 70 skips short look-alikes such as a few similar calls. Leave out `reporters`, `output` and `absolute`: the
check sets them itself.

**4. The first baseline.** The copies the project has today aren't in any baseline yet, so take them all in once:

```bash
./scripts/cpd.sh --update-baseline --allow-new
```

The first run downloads the release into `~/.cache/copied-code-check` and installs jscpd there, which takes a few
seconds. It writes `.jscpd-baseline.json`.

**5. Commit** the workflow, `scripts/cpd.sh`, `.jscpd.json` and `.jscpd-baseline.json`. From then on, the check only
lets the baseline shrink.

### Optional

- **New releases through Dependabot.** The `uses:` line is the only place the release is pinned: CI runs that
  release, and `./scripts/cpd.sh` reads the same line. A bump of the line moves both:

  ```yaml
  # .github/dependabot.yml
  version: 2
  updates:
    - package-ecosystem: github-actions
      directory: /
      schedule:
        interval: weekly
      allow:
        - dependency-name: Quartel-Enterprise/copied-code-check
  ```

  If several workflows use the action, they have to pin the same release, or the script refuses to run.
- **A required check.** To block merges on it, add `duplication` to the required status checks of the branch's
  ruleset or branch protection. Keep the workflow without a `paths` filter then: a pull request the filter skips
  never reports the check, and GitHub holds its merge forever.

## Usage

```bash
./scripts/cpd.sh                                # check: what CI runs
./scripts/cpd.sh --update-baseline              # write the lower numbers after copied code was removed, or a file moved
./scripts/cpd.sh --update-baseline --allow-new  # also take new copied code in, only when the copy is on purpose
```

The script runs from any directory of the repository. Without `--allow-new`, `--update-baseline` refuses any file
whose copied lines grew, even when copies removed elsewhere keep the total down.

In CI, the action compares the baseline with the one on the pull request's base branch. When the pull request takes
copied code in (`--allow-new`, or a moved file), the check still passes, since that was the author's call, but it
raises a warning and lists each file in the job summary, so the reviewer sees it.

### What counts

- **Lines of a file, not clones.** With the same code in three files, which pairs jscpd reports depends on the
  order it reads them, and an edit inside a long clone can split it into two shorter ones. The lines a file has in
  any clone don't change with either.
- **Only code.** Blank lines and comments are left out, and so are `package` lines and imports in Kotlin, Swift and
  TypeScript, where many files start the same way. In other languages imports count as code. A clone with fewer
  than 5 lines of code left is not counted.
- **One language at a time.** jscpd only compares files of the same language, so a screen drawn once with Compose
  and once with SwiftUI is never a clone.
- **Moved files.** A file moved with its copied code is a new path with the same copied lines as a listed path that
  is gone, and the same name: the part before the first dot plus the extension. So `Foo.android.kt` moved to
  `Foo.nonIos.kt` is a move, but `Foo.kt` to `Bar.kt` or `Foo.swift` isn't. The check fails until
  `--update-baseline` records the move. A renamed file counts as new copied code and needs `--allow-new`.

### Action inputs

| Input | Default | |
| --- | --- | --- |
| `script` | `./scripts/cpd.sh` | Where the wrapper is |
| `base-branch` | The pull request's base, else the default branch | The branch whose baseline the warning compares with |

### Environment

| Variable | |
| --- | --- |
| `CPD_CACHE_DIR` | Where releases are cached, `~/.cache/copied-code-check` by default |
| `CPD_RUNNER_DIR` | A checkout of this repository to run instead of the pinned release, to try a change |

## Development

```bash
./test/run.sh       # the check on small projects, through the wrapper
./scripts/lint.sh   # shellcheck, node --check and actionlint, as CI runs them
```

To try a change in a project before a release:

```bash
CPD_RUNNER_DIR=~/path/to/copied-code-check ./scripts/cpd.sh
```

To release, point the README's examples at the new version on `main`, then publish a GitHub release whose tag is the
bare version (`1.2.3`) from that commit. Releases are immutable: a published tag never moves, so a fix is a new
version.

## License

[Apache License 2.0](LICENSE)
