# TODOs

- [ ] `r-script-startup-banner` / `r-script-quiet-banner` hooks: the `entry:`
  grep pattern is built from a backslash-continued multi-line bash string;
  bash doesn't strip the leading YAML indentation on continuation lines, so
  extra literal spaces get baked into the regex (e.g. `"This is .+
  running R"` becomes `"This is .+     running R"`). Real script output
  never has that many consecutive spaces, so the hook fails even when the
  banner is correct. Repro: `Rscript FC_FC_2D_plot.r --version` prints a
  correct banner, but the pinned v0.3.3 hook entry fails on it (blocked a
  commit in FC_FC_2D_plot.r on 2026-08-17, worked around with
  `--no-verify`). Collapse each `entry:` grep pattern onto one line so YAML
  block-scalar indentation can't leak into it. Note the in-progress HEAD
  rewrite of `r-script-startup-banner` in `.pre-commit-hooks.yaml` also
  requires a `"with args:"` section in the banner that older consumers
  like FC_FC_2D_plot.r don't print — check whether that's an intended
  contract change before repinning consumers to a new tag.
