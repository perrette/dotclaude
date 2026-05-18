# /autonomous-roadmap

Convert a plan that has already been discussed and refined in conversation
into an autonomously-executable roadmap scaffold under `workflows/<slug>/`
in the current project, then set up the coordination files so the loop
driver at `~/.claude/templates/autonomous-roadmap/run_roadmap.sh` can pick
it up.

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
   (e.g. `tts-backends`, `auth-refactor`).
2. **Project smoke-test commands** — shell commands that must pass after
   every item (e.g., `python -c "import pkg"`, `npm test`,
   `cargo check`). Multiple commands OK.
3. **Anything else missing** from §A–§C of the plan, or from the item
   list.

## Step 1: Read the author guide

Read `~/.claude/templates/autonomous-roadmap/roadmap_author_guide.md` for
the required structure (§A–§E), the item template, and the sizing rubric.
Apply this guide when drafting.

## Step 2: Draft `roadmap.md` in chat

Produce the **full** roadmap content (sections §A–§E with all items) and
present it inline in chat — do NOT write any files yet. Highlight any
sizing decisions the user might want to revisit (items merged or split).

## Step 3: Wait for approval

The user will respond with approval ("ok", "looks good", "go") or
revisions. Iterate in chat until approved. Do not skip this step — the
user must see the items before they're committed to files.

## Step 4: On approval, materialize files

Perform these actions:

1. Create `workflows/<slug>/` in the project root.
2. Write the approved roadmap content to `workflows/<slug>/roadmap.md`.
3. Create an empty `workflows/<slug>/progress.md`.
4. Append `~/.claude/templates/autonomous-roadmap/gitignore_snippet.txt`
   to `.gitignore` at the project root, but only if `workflows/` is not
   already gitignored (check first to avoid duplicate lines). Create
   `.gitignore` if it doesn't exist.
5. Report back to the user with:
   - The path of the workflow directory.
   - The exact command to run a single sanity-check iteration:
     ```
     MAX_ITERATIONS=1 ~/.claude/templates/autonomous-roadmap/run_roadmap.sh workflows/<slug>/
     ```
   - The exact command to run the full loop:
     ```
     ~/.claude/templates/autonomous-roadmap/run_roadmap.sh workflows/<slug>/
     ```
   - A reminder to ensure the working tree is clean (no overlapping
     uncommitted changes) before running.

## Hard rules

- Do NOT write any files before user approval of the drafted roadmap.
- Do NOT modify `~/.claude/templates/` or `~/.claude/commands/`.
- The generic prompt and runner live in `~/.claude/templates/autonomous-roadmap/`
  and are shared across projects — never copy them into the project.
- All workflow-specific files live ONLY under `workflows/<slug>/`.
- Use `bard/workflows/tts-backends/` (if present) as a reference for what
  a finished scaffold looks like.
