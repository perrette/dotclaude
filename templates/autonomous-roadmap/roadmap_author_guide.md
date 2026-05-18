# How to write a roadmap.md

This guide is read by the agent that authors a `roadmap.md` for an autonomous
execution loop. The roadmap drives a sequence of fresh-context agents, each
executing exactly one item then exiting. Items must be self-contained enough
that an agent with **no prior context** — only `roadmap.md`, `progress.md`,
and the current code — can execute them correctly.

## File structure

```markdown
# <Project> — <change> roadmap

<one paragraph: what this roadmap migrates the project from / to>

> **How to read this document.** §A–§C describe the *starting state* and
> the *target* architecture. File:line citations are accurate at the start
> of the migration but become stale as early items run — trust the item's
> own *Files affected* list over the background section for current
> locations.

## §A. Architectural goal / background

<why this change matters; competitive or landscape context if applicable;
the *what* and *why*, never the *how*>

## §B. Audit of the current architecture (starting state)

<file:line citations into the current code; what's wrong and where; the
implicit contracts and leaked assumptions that the migration is fixing>

## §C. Target architecture

<the design the items will collectively produce: interfaces, contracts,
deps, BC story; high enough level that an agent on item N can orient
itself without reading items 1..N-1>

## §D. Hard rules for the executing agent

- Do not introduce features beyond an item's scope.
- Do not modify items marked complete in progress.md.
- Do not add tests unless an item explicitly asks.
- Do not add `Co-Authored-By:` or attribution trailers to commits.
- **Smoke-tests** (must pass after every item):
  - `<command 1>`
  - `<command 2>`
- **Safety brake**: if the codebase state contradicts an item's
  preconditions, or an item's files overlap with uncommitted changes in the
  working tree, the agent writes STOP.md in the workflow directory and
  exits. The driver script then halts the loop.

## §E. Items

<items 1..N>
```

## Item structure

Every item MUST follow this structure:

```markdown
### Item N: <imperative title>

**Model**: <sonnet | opus | haiku>      (optional; default sonnet)
**Effort**: <low | medium | high | xhigh | max>   (optional; default medium)
**Subagents**: parallel                  (optional; omit for serial in-agent execution)
**Subagent targets**:                    (required if Subagents is set)
- target 1 (one short line)
- target 2

**Scope**: one-line summary of what changes.

**Files affected**:
- path/to/file (create | modify | delete)

**Acceptance criteria**:
- bullet
- bullet

**Verification**:
- command that must succeed (no network calls)
- command that must succeed

**Dependencies**: Items X, Y — or "none".
```

The five sections (Scope, Files affected, Acceptance criteria, Verification,
Dependencies) are non-negotiable. The agent prompt assumes their presence.

`**Model**` and `**Effort**` are optional. Omit for items that fit the
default profile; specify only when the item warrants something different.
The agent at iteration N writes these (or the defaults) into the workflow's
`next_run.env`, which the loop driver reads at iteration N+1 to launch
claude with `--model <m> --effort <e>`. Model selection therefore happens
at agent *launch*, not mid-session.

**When to bump Model/Effort above defaults:**

- Items that integrate an unfamiliar third-party library API (the agent
  has to read and reason about external code structure). → `opus`, `high`.
- Items requiring nontrivial architectural judgment (designing the shape
  of a new abstraction, not just moving code). → `opus`, `high`.
- Items with cross-cutting effects where a wrong call cascades through
  many files. → `opus`, at least `high`.

**When defaults are fine:**

- Pure extractions / renames / moves with tight acceptance criteria.
- Registering a new entry in an existing registry.
- Filename/regex tweaks.

**Parallel subagents (optional, advanced):**

When an item is genuinely homogeneous fan-out across files (or
disjoint regions of files) that don't share editable surface — e.g.
"apply this metadata override across each of N backend modules" — you
may declare it parallelizable:

```
**Subagents**: parallel
**Subagent targets**:
- bard/backends/openai.py — add list_voices_meta() per item N
- bard/backends/kokoro.py — add list_voices_meta() per item N
- bard/backends/piper.py — add list_voices_meta() per item N
- bard/backends/elevenlabs.py — add list_voices_meta() per item N
```

The executing agent will dispatch one subagent per target in parallel,
collect all results, run the item's Verification once on the combined
result, and make a single item-level commit. Use this *only* when:

- Each target is independent of the others.
- Each target operates on files (or non-overlapping regions of files)
  that the others do not touch.
- Sequencing between targets does not matter.
- The work is regular enough that a single Acceptance criteria block
  applies uniformly to every target.

If any of those don't hold, split into separate items instead. The
system deliberately has no worktree/merge machinery: disjointness is
the contract. The executing agent will halt via STOP.md if it finds
itself wanting to merge overlapping edits between subagents.

**Sizing fan-out items.** The standard sizing rubric below (1-3 files,
50-300 lines, "atomic commit") measures *cognitive density*, not raw
size. For fan-out items, apply it *per target* rather than to the item
as a whole — a 4-target item legitimately covers 4 files and 400-800
lines, because each subagent only sees its own target and the reviewer
reads four independent diffs of normal size in one commit. The "one
conceptual change" rule still holds (the concept is "apply this
transformation to each target"). Do not pre-emptively split a fan-out
item back into N sequential items just to satisfy the per-item line
count — that defeats the point. Conversely, if a fan-out item's
*per-target* work would itself violate the rubric (e.g. each target is
its own 500-line refactor), that's a sign the targets aren't
homogeneous enough for one item, and you should split anyway.

**When the overhead doesn't pay off.** Each subagent pays roughly 10K
tokens of setup (system prompt, roadmap read, target file read) before
doing any meaningful work. If the per-target work itself is light —
under ~50 lines of edits — the overhead dominates: you pay ~N× the
tokens for ~N× the wall-clock saving, which is a fair trade in time
but a poor one in cost. For light fan-out, sequence the targets within
a single agent (omit the `Subagents` declaration) instead. The
parallel-subagents declaration is meant for *heavy* fan-out where each
target is substantive enough that the per-subagent setup is amortized
over real work.

The cost trade in the heavy case is paying ~N× tokens to get ~1/N
wall-clock time, with a single item-level commit covering all results.
You lose nothing on bisectability — if you wanted per-target commits,
you wanted N separate items.

## Sizing rubric

Each item should be approximately:

- **1–3 files** created/modified/deleted.
- **50–300 lines** of net edits (estimate by eye).
- **Atomic commit**: a reviewer should understand the whole change in one
  diff without context-switching between layers.
- **One conceptual change**: extract, rename, add-new-module,
  register-in-factory, generalize-existing-special-case, etc. If you find
  yourself writing two "and"s in the title, split it.
- **Verifiable without network**: parse / import / static checks only.
  Real network calls (API tests, deploys) do not belong in Verification.
- **Use the project's local interpreter / toolchain explicitly**. The
  agent runs verification commands literally, so write `.venv/bin/python`,
  `pnpm exec`, `cargo`, `./node_modules/.bin/jest`, etc. — not bare
  `python` / `npm` / `node`, which resolve against the system PATH and
  may run with the wrong dependency set. Determine the right invocation
  by checking the repo (presence of `.venv/`, `pyproject.toml`,
  `package.json`, lockfile choice) before drafting items.

Right-sizing examples:

- ✅ "Extract function X from module A to module B"
- ✅ "Add ABC and registry skeleton (no implementations yet)"
- ✅ "Move concrete implementation Y into the registry"
- ❌ "Add ABC and move all three implementations and rename everything" — too big.
- ❌ "Rename one variable in one file" — too small; fold into adjacent work.

## Ordering rubric

Order items so each commit leaves the project in a working state, roughly:

1. **Foundations first** — abstract base classes, registry skeletons, pure
   helper extractions. No behavior change.
2. **Migrate existing code into the new shape** — behavior still unchanged.
3. **Rename / unify call sites** — once the new shape exists.
4. **Generalize** — handle previously-hardcoded special cases.
5. **Add new instances** — new backends / plugins / etc.
6. **UX polish** — surface the new capabilities to users.

## What to leave out

- Do not include items dedicated solely to writing tests, unless tests are
  explicitly a deliverable. Each item's Verification is its lightweight
  test.
- Do not include CI / deploy / release items unless the user asked.
- Do not include documentation update items unless the user asked.
- Do not include cleanup items for cosmetic things (renaming variables for
  taste, adding type hints, etc.) unless the user asked.

## Final pass before presenting the draft

Once the items are written, do one focused re-read against the bump
rubric in *Item structure* above. The default sonnet/medium profile is
the path of least resistance, and items that warrant `opus`/`high` are
easy to miss on the first pass.

For **each** item, ask:

1. Does this item integrate an unfamiliar third-party library API — i.e.
   the agent has to read and reason about external code structure
   (response shapes, callback signatures, undocumented fields)?
2. Does this item require nontrivial architectural judgment — designing
   the *shape* of a new abstraction, not just moving code into a shape
   that's already decided?
3. Does this item have cross-cutting effects where a wrong call cascades
   through many files?

If the answer to any is "yes", set `**Model**: opus` and
`**Effort**: high` (or higher) on the item. If the answer is "no" for
all three, defaults are fine — but if an item *looks like* it might
qualify and you decided against bumping it, surface that decision when
presenting the draft (e.g. "Item N touches the X SDK but I kept it at
sonnet/medium because the call pattern is already established in
adjacent code — flag if you disagree"). Making the judgment explicit
gives the user a chance to challenge it before the loop runs against
the wrong model.

This pass is cheap (one re-read) and the failure mode it prevents
(sonnet attempting an item it cannot handle, producing a half-working
commit that the next iteration must work around) is expensive.
