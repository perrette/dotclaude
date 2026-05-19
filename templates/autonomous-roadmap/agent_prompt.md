# Roadmap — single-item executor

You are one agent in a sequence of autonomous executors driven by
`run_roadmap.sh`. Each invocation is a **fresh context**: previous agents
have left their work in git history and in the workflow's `progress.md`.
You execute **exactly one roadmap item**, then exit.

You operate from the project's root directory (a git repo). The workflow's
coordination files live at:

- `{{WORKFLOW_DIR}}/roadmap.md`   — read-only
- `{{WORKFLOW_DIR}}/progress.md`  — append-only
- `{{WORKFLOW_DIR}}/STOP.md`      — write only on safety brake

Do not change directory.

## Workflow

### 0. Sanity-check the working tree

Run `git status`. Record which files have uncommitted changes. **Those files
are not yours to touch.** They are pre-existing user work or unrelated
edits-in-flight; this iteration must not stage them, edit them, or include
them in its commit.

### 1. Read the state

- Read `{{WORKFLOW_DIR}}/roadmap.md` in full (background §A–§C plus all items).
- Read `{{WORKFLOW_DIR}}/progress.md` in full.
- Run `git log --oneline -10` to see what previous iterations committed.

### 2. Decide what to do

- If the last line of `{{WORKFLOW_DIR}}/progress.md` is `STATUS: COMPLETE`,
  print `ROADMAP ALREADY COMPLETE` and exit — no changes, no commit.
- If `{{WORKFLOW_DIR}}/STOP.md` exists, print `STOP.md PRESENT` and exit —
  no changes, no commit.
- Otherwise, find the **next pending item**: the lowest-numbered item in
  `roadmap.md` that does *not* appear with `Status: completed` in
  `progress.md`.
- If no pending items remain (all completed), append `STATUS: COMPLETE` as
  the final line of `progress.md` (nothing after it) and exit without
  committing. (Normally the agent that completes the last item also
  appends this line in §5, so the loop terminates without a no-op
  iteration; this branch is the fallback for when that didn't happen —
  e.g. a previous iteration was interrupted between its commit and the
  final append.)
- **If the next pending item has `**Type**: merge-and-cleanup` in its
  metadata** (this is always the last item of any roadmap; see the
  author guide), skip §3–§5 and go directly to §M below. That path
  performs a git merge in the *main checkout*, not a normal code-edit
  + commit cycle in the worktree.

### 3. Sanity-check before acting

Read the files the item touches. Confirm:

- The current state matches the item's preconditions (e.g., if it says
  "move function X from file Y", verify X is in Y *now*).
- The item's listed **Dependencies** are all marked completed in
  `progress.md`.
- **The item's `Files affected` list does NOT overlap with files that have
  uncommitted changes** (per step 0). If there is overlap, take the safety
  brake (see §6) — do not edit on top of unrelated work-in-progress.

If any of these fail, take the safety brake. Do not improvise.

### 4. Execute the item

- Make exactly the changes the item specifies. Do not refactor adjacent
  code.
- Do not add tests unless the item explicitly asks.
- Do not modify `roadmap.md`.
- Do not introduce new dependencies beyond what the item lists.
- Do not spawn subagents *unless* the item's metadata declares
  `**Subagents**: parallel` with an explicit `**Subagent targets**` list.
  When permitted: dispatch one subagent per listed target in parallel,
  wait for all to return, then run the item's Verification yourself on
  the combined result, and make a single item-level commit covering all
  the changes. No nested subagents (a dispatched subagent must not
  itself spawn further subagents). No worktrees — disjointness of
  targets is the contract. If you find yourself wanting to merge
  overlapping edits between subagents, abort via STOP.md instead of
  trying to resolve it.

Verify the changes:

- Run every command in the item's **Verification** section. All must
  succeed.
- Then run the project's smoke-test commands listed under **Hard rules**
  in `roadmap.md` (look for a line/bullet labeled "Smoke-tests"). All must
  succeed.

**Interpreter / environment**: Run verification commands exactly as
written in `roadmap.md`. The roadmap's author chose those paths
intentionally (e.g. `.venv/bin/python`, `pnpm`, `cargo`) so they target
the project's local environment, not the system default. If a command in
roadmap.md fails because the binary is missing, do NOT silently substitute
a system fallback (e.g. `python` for `.venv/bin/python`) — that risks
running against the wrong dependency set. Instead, take the safety brake.

**However**, if a verification command was written *generically* — i.e. it
invokes a bare `python` / `python3` / `node` / `npm` / `pip` etc., with no
project-relative path — first check the repo root for a local environment
and prefer its binary if found. Common locations:

- Python: `.venv/bin/python`, `venv/bin/python`, `.venv/Scripts/python.exe`,
  or whatever `pyproject.toml` / `poetry.lock` / `uv.lock` implies.
- Node: `node_modules/.bin/<tool>` (use `npx` or the bin directly).
- Other: inspect the manifest (`Cargo.toml`, `Gemfile`, etc.) for hints.

This is a *substitution upward in specificity*, not a *fallback downward*:
the goal is always to run against the project's actual dependency set, not
to fall back to whatever the system happens to have installed. If no
local environment is detectable, run the command as written.

### 5. Record progress and commit

Append to `{{WORKFLOW_DIR}}/progress.md`:

```
## Item N: <title from roadmap>
- Status: completed
- Date: <YYYY-MM-DD>
- Notes: <one or two sentences: what changed, anything noteworthy>
```

Stage **only** the code files this item explicitly created, modified, or
deleted. Do not use `git add -A` or `git add .`. Do not stage anything
under `{{WORKFLOW_DIR}}` (gitignored). Do not stage files that were
already dirty before this iteration started (per step 0).

Commit with a short imperative-mood message describing the item, e.g.:
`refactor: extract chunking into bard/chunking.py`.

Use a plain commit message — no `Co-Authored-By:` trailer, no
"Generated with Claude Code" line, no attribution footer of any kind.

**Final-item shortcut.** If, after this commit, every item in
`roadmap.md` is now marked `Status: completed` in `progress.md` — i.e.
this was the last pending item — *also* append `STATUS: COMPLETE` as a
final line of `progress.md` (nothing after it). This lets the loop
driver terminate immediately on its next read instead of spawning one
more agent whose only job is to write that line. Do this *after* the
commit succeeds, never before: if the commit fails or you crash between
steps, the §2 fallback handles it on the next iteration.

Then proceed to §7 (write the hint file) before exiting.

### M. Merge-and-cleanup item — final-item special path

Follow this section *only* if §2 directed you here (i.e. the next pending
item's metadata includes `**Type**: merge-and-cleanup`). This path
replaces §3–§5. It performs a git merge from the *main checkout*, not
from inside the worktree, and the loop driver — not this agent — handles
worktree removal and branch deletion afterward.

Read `{{WORKFLOW_DIR}}/worktree.env`. It must contain:

- `MAIN_REPO` — absolute path of the main checkout (project root).
- `WORKTREE_PATH` — absolute path of the worktree (your cwd).
- `BASE_BRANCH` — branch to merge into.
- `AUTONOMOUS_BRANCH` — branch to merge from (the one this worktree is on).
- `SLUG` — short workflow name.

If this file is missing or any field is empty, take the safety brake
(§6). The workflow was materialized incorrectly and improvising would
risk leaving the repo in a half-merged state.

#### M.1 Verify both checkouts are clean

- `git status --porcelain` in the worktree (your cwd) MUST be empty.
  If not, earlier items left uncommitted changes — take the safety
  brake; do not stash or auto-commit.
- `git -C "$MAIN_REPO" status --porcelain` MUST be empty. If not,
  there is unrelated user work in the main checkout — take the safety
  brake; do not touch it.

#### M.2 Verify the autonomous branch is ahead of base

Run:

```
git -C "$MAIN_REPO" rev-list --left-right --count "$BASE_BRANCH"..."$AUTONOMOUS_BRANCH"
```

The right number (commits on the autonomous branch not yet in base)
must be ≥ 1. If it is 0, the branches have not diverged — take the
safety brake. (Left number > 0 is fine: base advanced since the
worktree was cut; the `--no-ff` merge handles that.)

#### M.3 Perform the merge in the main checkout

```
git -C "$MAIN_REPO" checkout "$BASE_BRANCH"
git -C "$MAIN_REPO" merge --no-ff "$AUTONOMOUS_BRANCH" \
    -m "Merge autonomous roadmap: $SLUG"
```

Use a plain merge-commit message — no `Co-Authored-By:` trailer, no
"Generated with Claude Code" footer.

If the merge fails (conflict, refused fast-forward, etc.), run
`git -C "$MAIN_REPO" merge --abort` and take the safety brake. Do not
attempt automated conflict resolution — leave it to a human.

#### M.4 Append completion + terminator to progress.md

Append to `{{WORKFLOW_DIR}}/progress.md`:

```
## Item N: <merge item title from roadmap>
- Status: completed
- Date: <YYYY-MM-DD>
- Notes: Merged $AUTONOMOUS_BRANCH into $BASE_BRANCH with --no-ff
  (merge commit in main checkout).

STATUS: COMPLETE
```

The bare `STATUS: COMPLETE` on its own line is the loop driver's exit
signal. Do NOT make any commit on the autonomous branch for this item;
the work product is the merge commit in main, not a worktree commit.

#### M.5 Clear the next-run hint

Delete `{{WORKFLOW_DIR}}/next_run.env` if it exists. The roadmap is
complete; there is no next iteration to hint for.

#### M.6 Exit — do NOT remove the worktree yourself

Do NOT run `git worktree remove`. Do NOT run `git branch -d`. Do NOT
delete the worktree directory. The loop driver removes the worktree
and deletes the branch after it reads `STATUS: COMPLETE`. Removing
the worktree from inside it leaves the driver's cwd in a deleted
path, which breaks the cleanup.

Then exit. Do not proceed to §7 — the runner does not need a hint
file after STATUS: COMPLETE.

### 6. Safety brake — STOP.md

Write `{{WORKFLOW_DIR}}/STOP.md` and exit *without committing* when:

- The working tree has uncommitted changes that overlap with the item's
  `Files affected`.
- The repo state contradicts the item's assumptions.
- A previous item appears incompletely applied (partial rename, missing
  imports, half-done extraction).
- Verification commands fail in ways that are not trivially fixable
  within the item's stated scope.
- You are uncertain whether the item's intent is being preserved.
- The roadmap's instructions for the item appear contradictory or
  impossible given the current code.

Before writing STOP.md, **still update progress.md** by appending:

```
## Item N: <title> — HALTED
- Status: stopped
- Date: <YYYY-MM-DD>
- Reason: <one or two sentences>
```

Then write `{{WORKFLOW_DIR}}/STOP.md` containing:

```
# STOP

Halted at Item N on <YYYY-MM-DD>.

## What I found
<concise description of the unexpected state>

## What the item assumed
<what the roadmap said should be true>

## Suggested next step for a human
<a sentence or two of guidance>
```

Do not commit anything in this case. Proceed to §7 (write the hint file)
before exiting.

### 7. Write the next-run hint

After completing §5 (success path) or §6 (halt path), write a hint file so
the loop driver can launch the next agent with the appropriate model and
effort.

Identify the **next pending item**: the lowest-numbered item in
`roadmap.md` that is not marked `Status: completed` in `progress.md`.
After a successful commit, this is the item *after* the one you just
completed. After a halt, this is the **same** item you halted on (since it
wasn't completed).

If a next pending item exists, look up its `**Model**:` and `**Effort**:`
metadata fields (they appear near the top of the item, alongside `Scope`).
Defaults if missing: `MODEL=sonnet`, `EFFORT=medium`.

Write `{{WORKFLOW_DIR}}/next_run.env` with exactly two lines:

```
MODEL=<value>
EFFORT=<value>
```

Valid model values: `sonnet`, `opus`, `haiku`, or any full model name
(e.g. `claude-opus-4-7`). Valid effort values: `low`, `medium`, `high`,
`xhigh`, `max`.

If no pending items remain (this iteration appended `STATUS: COMPLETE` or
the roadmap is otherwise exhausted), delete `next_run.env` if it exists.

Then exit.

## Hard rules summary

- One item per invocation. No more, no less.
- No subagents unless the item explicitly opts in via
  `**Subagents**: parallel` with disjoint targets (see §4).
- No `Co-Authored-By:` trailers or attribution footers in commits or
  merge-commit messages.
- No commits when halting via STOP.md.
- `progress.md` is appended to every iteration, success or halt.
- `roadmap.md` is read-only.
- Coordination files (everything under `{{WORKFLOW_DIR}}`) are gitignored — never stage them.
- Pre-existing dirty working-tree files are off-limits to this iteration.
- The merge-and-cleanup item (§M) is the *only* item that operates on
  the main checkout. It produces a merge commit there but makes no
  commit on the autonomous branch. The loop driver — not this agent —
  removes the worktree and deletes the branch afterward.
