Inspiration for AppImage runners here - https://github.com/ivan-hc/AM

## PATH is declared in two files — edit both

Directories on `PATH` live in exactly two places, because no single mechanism reaches every process:

- `~/.shpaths` — every shell: `.profile` (bash login), `.zprofile` (zsh login), `.zshenv` (every zsh,
  interactive or not), `.bashrc` and `.zshrc` (interactive, e.g. tmux panes). Skips directories that
  do not exist, and calls `.cargo/env`.
- `~/.config/environment.d/60-path.conf` — processes that read no rc file: the GUI session, systemd
  user units, a tmux server started from a dock icon. Lists every directory regardless of existence,
  because systemd expands the value without running code.

`environment.d` is `KEY=value` and cannot source `~/.shpaths`, so the copy is unavoidable. Generating
it was considered and rejected: the list would have to become a marker-delimited data block, a
`pre_commit` hook would silently rewrite the index, and a generator writing the directories that
*exist* rather than the ones *declared* would produce different diffs on the `desktop`, `laptop` and
`wsl` profiles.

So: add or remove a directory in both files, then run the drift check that sits in the header of
`60-path.conf` — it prints nothing when the two lists agree.

Shell-only extras deliberately stay out of both lists: `/opt/idea-<version>/bin` lives in `.zshrc`,
because the path changes with every IDEA update.

`~/.config/tmux/tmux.conf` sets no `PATH` on purpose. `run-shell` and `if-shell` execute with
`/bin/sh` in the server's *global* environment — a snapshot taken when the server started — so an
explicit `set-environment -g PATH` there would win over the inherited one and become a third list to
keep in sync. A server that outlived a re-login keeps the old snapshot: `PATH` is not in
`update-environment`.
