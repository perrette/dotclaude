# /autonomous-roadmap

Convert a plan that has already been discussed and refined in conversation
into an autonomously-executable roadmap scaffold, materialize it inside a
dedicated git worktree on a fresh branch, and set up the coordination files
so the loop driver at `~/.claude/templates/autonomous-roadmap/run_roadmap.sh`
can pick it up.

This command is the *materialization* step. The investigation and plan-
refinement happen earlier in the conversation, manually. The user should
already have:

- A finalized plan (often the output of an investigation agent: §A
  background, §B current-state audit, §C target architecture).
- A rough list of items the plan implies.

If not, push back and refuse to draft until the plan is in chat.

## Inputs to gather

If any of the following is not already established in the conversation,
ask the user (use AskUserQuestion when there's a clear small set of
answers; otherwise plain prose):

1. **Workflow slug** — short kebab-case directory name
   (e.g. `tts-backends`, `auth-refactor`). Reused as the branch suffix and
   worktree directory name.
2. **Project smoke-test commands** — shell commands that must pass after
   every item (e.g., `python -c "import pkg"`, `npm test`,
   `cargo check`). Multiple commands OK.
3. **Full test suite command(s)** — the heavier suite to run once during
   the finalization item, distinct from the per-item smoke tests
   (e.g., `pytest`, `npm test -- --run`, `cargo test`). If the project has
   no test suite, note that explicitly so the finalization item skips it.
4. **README / docs paths** that the finalization item should refresh
   (typically `README.md`; plus any `docs/` content that references the
   areas changed by this roadmap). If none apply, note that explicitly.
5. **Anything else missing** from §A–§C of the plan, or from the item
   list.

## Step 1: Read the author guide

Read `~/.claude/templates/autonomous-roadmap/roadmap_author_guide.md` for
the required structure (§A–§E), the item template, the sizing rubric, and
— important — the two **required trailing items** (finalization + merge)
that every roadmap must end with. Apply this guide when drafting.

## Step 2: Pre-flight checks (before drafting files)

Verify the repo is in a state that can host a worktree:

1. The current directory is inside a git repo (`git rev-parse --show-toplevel`).
2. HEAD is on a named branch, not detached. Capture that branch name as
   the **base branch** — the autonomous branch will be cut from it and
   merged back into it at the end.
3. The branch `autonomous/<slug>` does NOT already exist
   (`git rev-parse --verify autonomous/<slug>` should fail).
4. The directory `.worktrees/<slug>` does NOT already exist in the project
   root.

If any check fails, stop and report the conflict to the user instead of
clobbering existing state.

## Step 3: Draft `roadmap.md` in chat

Produce the **full** roadmap content (sections §A–§E with all items) and
present it inline in chat — do NOT write any files yet. The item list
MUST end with the two required trailing items described in the author
guide:

- **Item N-1: Finalization** — update README and project docs to reflect
  the new state; run the full test suite. No code changes beyond docs
  and any documentation-only test-fixture tweaks.
- **Item N: Merge `autonomous/<slug>` into `<base>` and clean up** — the
  loop's exit step. Executed specially by the agent (see agent_prompt).

Highlight any sizing decisions the user might want to revisit (items
merged or split).

## Step 4: Wait for approval

The user will respond with approval ("ok", "looks good", "go") or
revisions. Iterate in chat until approved. Do not skip this step — the
user must see the items before they're committed to files.

## Step 5: On approval, materialize files

Perform these actions, in order. The worktree must exist before any
workflow files are written, because the workflow files live *inside*
the worktree so the agent commits and the final merge all happen on
the autonomous branch.

1. **Create the worktree on a new branch.** From the project root:
   ```
   git worktree add .worktrees/<slug> -b autonomous/<slug>
   ```
   This creates `.worktrees/<slug>/` checked out to a new branch
   `autonomous/<slug>` that starts at the current HEAD of the base
   branch.

2. **Update `.gitignore` inside the worktree** (not in the main
   checkout — main stays untouched until the final merge). Check
   whether `workflows/` and `.worktrees/` are already gitignored; for
   any missing entry, append the relevant line(s) from
   `~/.claude/templates/autonomous-roadmap/gitignore_snippet.txt`.
   Create `.gitignore` if it doesn't exist. If both entries were
   already present, skip this step entirely (no empty commit).

3. **Commit the gitignore change** on the autonomous branch only:
   ```
   git -C .worktrees/<slug> add .gitignore
   git -C .worktrees/<slug> commit -m "chore: ignore autonomous-roadmap workflow dirs"
   ```
   Use a plain commit message — no `Co-Authored-By:` trailer, no
   "Generated with Claude Code" footer. Skip this commit if step 2
   was skipped.

4. **Create the workflow directory inside the worktree:**
   `.worktrees/<slug>/workflows/<slug>/` — this is the
   `<workflow_dir>` referenced by the loop driver and agent prompt.

5. **Write the approved roadmap content** to
   `.worktrees/<slug>/workflows/<slug>/roadmap.md`.

6. **Create an empty** `.worktrees/<slug>/workflows/<slug>/progress.md`.

7. **Write** `.worktrees/<slug>/workflows/<slug>/worktree.env` with the
   fixed-format pointer data the agent and runner both consume:
   ```
   MAIN_REPO=<absolute path to the main checkout, i.e. project root>
   WORKTREE_PATH=<absolute path to .worktrees/<slug>>
   BASE_BRANCH=<the branch HEAD was on before materialization>
   AUTONOMOUS_BRANCH=autonomous/<slug>
   SLUG=<slug>
   ```
   Use absolute paths; do not rely on `$PWD`. This file is the single
   source of truth for the merge item and the runner's post-completion
   cleanup.

8. **Write** `.worktrees/<slug>/workflows/<slug>/next_run.env` with
   Item 1's model and effort hints. Read the `**Model**:` and
   `**Effort**:` lines from Item 1 of the roadmap (if present) and
   write them as two lines:
   ```
   MODEL=<value>
   EFFORT=<value>
   ```
   This is required because the runner reads `next_run.env` at the
   start of every iteration, and the executing agent only writes it at
   the END of each iteration (looking ahead to the next pending item).
   Without seeding it here, the first iteration always falls back to
   the runner default (sonnet/medium) — Item 1's hints would never
   take effect, even if it is labelled opus/high. If Item 1 has no
   model/effort hints in the roadmap, skip this step (the runner
   defaults apply).

9. **Report back to the user** with:
   - The worktree path: `.worktrees/<slug>/`.
   - The autonomous branch name: `autonomous/<slug>`.
   - The exact command to run a single sanity-check iteration:
     ```
     (cd .worktrees/<slug> && MAX_ITERATIONS=1 ~/.claude/templates/autonomous-roadmap/run_roadmap.sh workflows/<slug>/)
     ```
   - The exact command to run the full loop:
     ```
     (cd .worktrees/<slug> && ~/.claude/templates/autonomous-roadmap/run_roadmap.sh workflows/<slug>/)
     ```
   - A reminder that the main checkout's working tree should be clean
     before the merge item fires (the final item refuses to merge over
     unrelated work).
   - A note that the loop will, on success, merge `autonomous/<slug>`
     into `<base>` with `--no-ff`, remove the worktree, and delete the
     branch.

## Hard rules

- Do NOT write any files before user approval of the drafted roadmap.
- Do NOT modify `~/.claude/templates/` or `~/.claude/commands/`.
- The generic prompt and runner live in `~/.claude/templates/autonomous-roadmap/`
  and are shared across projects — never copy them into the project.
- All workflow-specific files live ONLY inside the worktree under
  `.worktrees/<slug>/workflows/<slug>/`.
- The main checkout is not modified by materialization — every change
  the workflow introduces lands in main only via the final merge.
