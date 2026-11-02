# copied-code-check

Looks for copied code with [jscpd](https://github.com/kucherenko/jscpd), locally and in CI, against a baseline
that only shrinks. Shared by the Quare apps (Kotlin, Swift and TypeScript).

A project lists how many lines of code of each file are copied today in `.jscpd-baseline.json`. The check fails
on a file with more of them, so no new copied code merges unnoticed, and on a file with fewer, until the
baseline is updated, so copied code removed can't come back.

## Setup

A project keeps three files and one workflow step:

| File | |
| --- | --- |
| `scripts/cpd.sh` | The wrapper, [`consumer/cpd.sh`](consumer/cpd.sh). It never changes |
| `.jscpd.json` | What jscpd scans: the paths, the languages, `minTokens`, the files it ignores |
| `.jscpd-baseline.json` | The copied lines of each file, written by `./scripts/cpd.sh --update-baseline` |

```bash
mkdir -p scripts
curl -fsSLo scripts/cpd.sh \
  https://raw.githubusercontent.com/Quartel-Enterprise/copied-code-check/refs/tags/1.0.1/consumer/cpd.sh
chmod +x scripts/cpd.sh
```

```json
{
  "path": ["core", "feature", "iosApp", "webApp/src"],
  "format": ["kotlin", "swift", "tsx"],
  "formatsExts": { "tsx": ["ts", "tsx"] },
  "minTokens": 70,
  "ignore": ["**/build/**", "**/node_modules/**", "**/*Test.kt", "**/*Tests.swift", "**/*.test.ts"],
  "gitignore": true,
  "silent": true
}
```

The check sets the reporter, its output directory and absolute paths itself, so `.jscpd.json` leaves them out.

```yaml
# .github/workflows/duplication.yml
name: duplication
on:
  pull_request:

permissions:
  contents: read

jobs:
  duplication:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: Quartel-Enterprise/copied-code-check@1.0.1
```

The `uses:` line is the one place a project pins the release: the wrapper reads it from the workflows under
`.github/workflows`, so a local run and CI always run the same check and the same jscpd. Every workflow that
uses the action has to pin the same release. Releases are immutable, so a tag always means the same code. To let
Dependabot propose new releases:

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

A required check can't have a `paths` filter: a pull request it skips never reports it, and GitHub holds the
merge forever.

## Usage

```bash
./scripts/cpd.sh                                # check (what CI runs)
./scripts/cpd.sh --update-baseline              # write the copied code found now to .jscpd-baseline.json
./scripts/cpd.sh --update-baseline --allow-new  # also take more copied code in, only when the copy is on purpose
```

It needs Node.js 18 or later. The first run of a release also needs `curl`, `tar` and access to github.com: it
downloads the release into `~/.cache/copied-code-check` and installs the jscpd release it locks, with every
dependency. In CI the action runs its own files, so nothing is downloaded.

- **Lines of a file, not clones.** With the same code in three files, which pairs jscpd reports depends on the
  order it reads them, and an edit inside a long clone can split it into two shorter ones. The lines a file has
  in any clone don't change with either.
- **Only code counts.** Blank lines, comments, `package` and imports (Kotlin, Swift, TypeScript imports and
  re-exports) are left out. A clone with fewer than 5 lines of code is a shared header, not copied code.
- **jscpd only compares files of one language**, so a screen drawn by Compose, SwiftUI and React is never a
  clone: what it finds is logic or UI copied within one of them.
- **A moved file** is a new path with the copied lines and the name of a listed path whose file is gone. The
  name is the part before the first dot plus the extension, so `Foo.android.kt` moved to another source set as
  `Foo.nonIos.kt` is a move, `Foo.kt` to `Foo.swift` isn't. `--update-baseline` takes a move in; a file renamed
  with its copied code is new copied code and needs `--allow-new`.
- **In CI**, the action compares the baseline with the one of the pull request's base branch, and warns when the
  baseline takes copied code in (`--allow-new`, or a move): the author's call, so it doesn't fail, but a reviewer
  sees it, once as an annotation and file by file in the job summary.

| Action input | |
| --- | --- |
| `script` | The wrapper. `./scripts/cpd.sh` by default |
| `base-branch` | The branch whose baseline the warning compares with: the pull request's base by default, else the repository's default branch |

## Development

```bash
./test/run.sh       # the check on small projects, through the wrapper
./scripts/lint.sh   # shellcheck, node --check and actionlint, as CI runs them
```

To try a change in a project before a release, point the wrapper at this checkout:

```bash
CPD_RUNNER_DIR=~/path/to/copied-code-check ./scripts/cpd.sh
```

A release is a GitHub release whose tag is the bare version (`1.2.3`). Tag only commits on `main`.

## License

[Apache License 2.0](LICENSE)
