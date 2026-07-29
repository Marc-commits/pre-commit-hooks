# Changelog

## v0.3.3

- Fixed `conda-env-validate`: `conda env create --dry-run -f "$f"` with no
  `--name`/`--prefix` errors out (`CondaEnvException: Unable to create
  environment`) on current conda for any env yaml lacking an internal `name:`
  field — the norm for Snakemake-managed envs, which generate their own hashed
  env names and ignore `name:` anyway. Now creates a disposable `--prefix` per
  check, so no env yaml needs a `name:` field to pass.

## v0.3.2

- Fixed `snakemake-lint`: it ran `snakemake --lint --snakefile "$f"` once per
  matched file (`pass_filenames: true`), which fails on any included `.smk`
  rule module since those aren't standalone Snakefiles and can't resolve
  names/config outside the top-level Snakefile's include graph. Now runs
  `snakemake --lint` once from the repo root (`pass_filenames: false`),
  matching how consuming repos' own hand-rolled equivalents already did it.
- `snakemake-lint` now forwards extra `args:` (e.g. `--configfile path.yaml`,
  `--snakefile path/to/Snakefile`) to `snakemake --lint`, for repos whose
  Snakefile can't resolve a default config/entry point on its own.

## v0.3.1

- Added `snakedeploy-pin-conda-envs` hook.

## v0.3.0

- **Breaking:** `readme-url-check` now reads `GITHUB_TOKEN_PC_CHECK_README_URLS`
  instead of `GITHUB_TOKEN` for private-repo URL checks. `GITHUB_TOKEN`/`GH_TOKEN`
  are read by the `gh` CLI itself, so exporting a token under those names (e.g.
  via a shared `.env`) silently overrode `gh auth login`'s stored credentials in
  every consuming repo. Rename any exported token accordingly.
- Added README.md and CHANGELOG.md for this repo.

## v0.2.1

- Added `validate-config` hook.
- Merged hook definitions into a single `.pre-commit-hooks.yaml`.

## v0.2.0

- `readme-url-check` gained support for confirming private-repo URLs via the
  GitHub API when a token is present.

## v0.1.4

- Fixed missing `PYTHONHASHSEED=0` in `snakemake-rulegraph`.
- Fixed `yamllint --strict` violations across hook definition files.

## v0.1.3

- `version-sync` also checks the root/docker `build.sh`'s `VERSION=` string.

## v0.1.2

- Narrowed `version-sync` scope; fixed false positives in `readme-no-local-paths`.

## v0.1.1

- Fixed missing executable bit on `check-readme-urls.sh`.

## v0.1.0

- Initial release: `version-sync`, `readme-no-local-paths`, `readme-url-check`,
  and the R/Python/shell/Docker/Snakemake local policy hooks.
