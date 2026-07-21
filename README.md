# pre-commit-hooks

Local policy hooks shared across Marc-commits' bioinformatics repos, consumed
via `pre-commit`'s remote-hook resolution.

## Usage

```yaml
- repo: https://github.com/Marc-commits/pre-commit-hooks
  rev: v0.3.0
  hooks:
    - id: readme-url-check
    - id: sh-strict-mode
    # ... any other id from .pre-commit-hooks.yaml
```

## Hooks

- **Repo/config**: `version-sync`, `validate-config`
- **README**: `readme-no-local-paths`, `readme-url-check`
- **R**: `r-script-shebang`, `r-script-runnable`, `r-script-stdin-stdout`,
  `r-metadata`, `r-script-startup-banner`, `r-script-quiet-banner`,
  `r-script-no-pkg-startup`, `r-script-session-info`
- **Python**: `py-shebang`, `py-marimo-check`, `py-help-version`, `py-metadata`
- **Shell**: `sh-bash-shebang`, `sh-usage-banner`, `sh-strict-mode`,
  `sh-help-version`, `sh-metadata`
- **Docker**: `docker-build-check`, `docker-metadata`
- **Snakemake/conda**: `snakemake-lint`, `workflow-sh-strict-mode`,
  `conda-env-validate`, `snakemake-rulegraph`

Full hook definitions live in `.pre-commit-hooks.yaml`.

### `readme-url-check` and private GitHub repos

By default this hook only confirms URLs are reachable anonymously. To also
confirm private-repo URLs are valid (rather than just flagging them as
unreachable), export `GITHUB_TOKEN_PC_CHECK_README_URLS` with a token that can
see those repos before running pre-commit. The variable is intentionally
*not* named `GITHUB_TOKEN`/`GH_TOKEN` — those names are read by the `gh` CLI
itself, and exporting a token under those names silently overrides `gh auth
login`'s stored credentials wherever it's set.
