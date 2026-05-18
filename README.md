# dotclaude

Personal customizations for [Claude Code](https://claude.com/claude-code) —
slash commands and supporting templates, installed via symlinks so this
repo is the live source of truth for `~/.claude/commands/` and
`~/.claude/templates/`.

## Layout

```
dotclaude/
├── README.md
├── install.sh                                   # idempotent symlink installer
├── commands/                                    # → ~/.claude/commands/
│   └── autonomous-roadmap.md
└── templates/                                   # → ~/.claude/templates/
    └── autonomous-roadmap/
        ├── agent_prompt.md
        ├── run_roadmap.sh
        ├── format_stream.py
        ├── roadmap_author_guide.md
        └── gitignore_snippet.txt
```

## Slash commands

### `/autonomous-roadmap`

Converts a plan already discussed in conversation into an autonomously-
executable migration roadmap under `workflows/<slug>/` in the current
project. Sets up `roadmap.md`, an empty `progress.md`, and gitignore
entries; the driver script `templates/autonomous-roadmap/run_roadmap.sh`
then invokes a fresh-context Claude Code agent per iteration, each
executing exactly one roadmap item then exiting. Includes:

- Per-item `Model` / `Effort` selection via a `next_run.env` hint file the
  agent writes for the next iteration.
- Streaming tool-call logs via `--output-format=stream-json` piped through
  `format_stream.py` for human-readable output + a raw `.jsonl` alongside.
- Iteration counter persistent across invocations (derived from log files).
- SIGINT trap so Ctrl+C halts the loop cleanly instead of falling through
  to the next iteration.
- Safety brake via `STOP.md` for divergence or pre-existing dirty files
  that overlap with an item's scope.

See `templates/autonomous-roadmap/roadmap_author_guide.md` for the
roadmap structure and item-sizing rubric.

## Install

On a fresh machine:

```bash
git clone https://github.com/perrette/dotclaude.git ~/Projects/dotclaude
cd ~/Projects/dotclaude
./install.sh
```

The installer creates symlinks from `~/.claude/commands/` and
`~/.claude/templates/` into this repo. Existing files at the install
destinations are backed up with a timestamp suffix
(`.bak.<unix-timestamp>`) before symlinks are created.

Edits in the repo are immediately visible to Claude Code; edits made in
`~/.claude/...` (which is the repo via the symlink) are immediately
visible to git. Commit and push from this repo to share/sync across
machines.
