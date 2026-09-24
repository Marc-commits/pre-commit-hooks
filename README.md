# pre-commit-hooks

Local policy hooks shared across Marc-commits' bioinformatics repos, consumed
via `pre-commit`'s remote-hook resolution.

## Usage

```yaml
- repo: https://github.com/Marc-commits/pre-commit-hooks
  rev: v0.5.0
  hooks:
    - id: readme-url-check
    - id: sh-strict-mode
    # ... any other id from .pre-commit-hooks.yaml
```

## Hooks

- **Repo/config**: `version-sync`, `validate-config`
- **README**: `readme-no-local-paths`, `readme-url-check`
- **R**: `r-script-shebang`, `r-script-runnable`, `r-script-tldr`,
  `r-script-help-defaults`, `r-script-stdin-stdout`, `r-metadata`,
  `r-script-startup-banner`, `r-script-quiet-banner`, `r-script-no-pkg-startup`,
  `r-script-session-info`
- **Python**: `py-shebang`, `py-marimo-check`, `py-help-version`, `py-tldr`,
  `py-help-defaults`, `py-metadata`
- **Shell**: `sh-bash-shebang`, `sh-usage-banner`, `sh-strict-mode`,
  `sh-help-version`, `sh-tldr`, `sh-help-defaults`, `sh-metadata`
- **Docker**: `docker-build-check`, `docker-metadata`
- **Snakemake/conda**: `snakemake-lint`, `workflow-sh-strict-mode`,
  `conda-env-validate`, `snakemake-rulegraph`

Full hook definitions live in `.pre-commit-hooks.yaml`.

### `*-help-defaults`: pastable defaults one-liner

`r-script-help-defaults`, `py-help-defaults` and `sh-help-defaults` require
each executable script's `--help` output to contain a `Defaults:` section. The
section's next line must be indented and start with the script's basename.
That line should invoke the script with every default made explicit, so it
can be pasted and edited:

```text
Defaults:
  barplot.r INPUT --output barplot.svg --sep auto --x x --y y
```

Required arguments without a default appear as uppercase placeholders. The
check lives in `scripts/check-help-defaults.sh`. Write the line by deriving it
from the argument parser (argparse actions, docopt `[default: ...]` tags, or
the shell script's default variables) rather than hard-coding it, so it can't
drift from the real defaults.

### `readme-url-check` and private GitHub repos

By default this hook only confirms URLs are reachable anonymously. To also
confirm private-repo URLs are valid (rather than just flagging them as
unreachable), export `GITHUB_TOKEN_PC_CHECK_README_URLS` with a token that can
see those repos before running pre-commit. The variable is intentionally
*not* named `GITHUB_TOKEN`/`GH_TOKEN` — those names are read by the `gh` CLI
itself, and exporting a token under those names silently overrides `gh auth
login`'s stored credentials wherever it's set.
