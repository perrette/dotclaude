#!/usr/bin/env bash
# Autonomous roadmap executor (generic).
#
# Usage:
#   run_roadmap.sh <workflow-dir>
# or, from within the workflow dir:
#   run_roadmap.sh
#
# The workflow dir must contain `roadmap.md` and (optionally) `progress.md`.
# The script invokes Claude Code once per iteration. On each iteration:
#   - the agent reads roadmap.md and progress.md from the workflow dir,
#   - picks the next pending item, executes it, appends progress.md,
#   - and creates one commit in the surrounding git repo.
#
# Loop stops on:
#   - last line of progress.md is `STATUS: COMPLETE`     (success)
#   - STOP.md appears in the workflow dir                 (agent-requested halt)
#   - MAX_ITERATIONS reached                              (safety cap)

set -uo pipefail

# Ctrl+C inside a foreground pipeline kills the pipeline, but without a
# trap bash falls through to the next iteration of the for-loop. Catch
# SIGINT so a single Ctrl+C reliably stops the whole loop. The agent's
# natural-recovery guard (progress.md is updated last, so an interrupted
# iteration leaves it unchanged) means re-running the script later will
# resume cleanly from the same pending item.
trap 'printf "\n\n[run_roadmap] Interrupted (SIGINT). Halting loop.\n" >&2; exit 130' INT

# ---------- Resolve paths ----------

WORKFLOW_DIR="${1:-$PWD}"
WORKFLOW_DIR="$(cd "$WORKFLOW_DIR" 2>/dev/null && pwd)" \
    || { echo "Error: workflow directory not found: ${1:-$PWD}" >&2; exit 1; }

PROJECT_ROOT="$(cd "$WORKFLOW_DIR" && git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "Error: $WORKFLOW_DIR is not inside a git repository" >&2; exit 1; }

cd "$PROJECT_ROOT"

TEMPLATE_DIR="$HOME/.claude/templates/autonomous-roadmap"
PROMPT_TEMPLATE="$TEMPLATE_DIR/agent_prompt.md"

ROADMAP="$WORKFLOW_DIR/roadmap.md"
PROGRESS="$WORKFLOW_DIR/progress.md"
STOP="$WORKFLOW_DIR/STOP.md"
LOG_DIR="$WORKFLOW_DIR/logs"

# ---------- Pre-flight ----------

command -v claude >/dev/null 2>&1 || { echo "Error: 'claude' CLI not found in PATH." >&2; exit 1; }
[[ -f "$PROMPT_TEMPLATE" ]] || { echo "Missing template: $PROMPT_TEMPLATE" >&2; exit 1; }
[[ -f "$ROADMAP"         ]] || { echo "Missing $ROADMAP"         >&2; exit 1; }
[[ -f "$PROGRESS"        ]] || : > "$PROGRESS"

if [[ -f "$STOP" ]]; then
    echo "Refusing to start: $STOP already exists. Inspect and delete it before retrying." >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

MAX_ITERATIONS="${MAX_ITERATIONS:-20}"

DEFAULT_MODEL="sonnet"
DEFAULT_EFFORT="medium"
HINT_FILE="$WORKFLOW_DIR/next_run.env"

# Read a KEY=VALUE pair from a file, falling back to a default.
hint_get() {
    local key="$1" file="$2" default="$3" val=""
    [[ -f "$file" ]] && val=$(awk -F= -v k="$key" '$1==k{v=$0; sub("^[^=]*=", "", v); print v}' "$file" | tail -1)
    printf '%s' "${val:-$default}"
}

# ---------- Prompt substitution ----------
# The agent_prompt template uses {{WORKFLOW_DIR}} as a placeholder.
# Substitute with the absolute path so Read calls work unambiguously.

PROMPT="$(sed "s|{{WORKFLOW_DIR}}|$WORKFLOW_DIR|g" "$PROMPT_TEMPLATE")"

# ---------- Persistent iteration counter ----------
# The iteration number is global across all invocations of this script for
# this workflow. We derive it from the highest existing log filename in
# $LOG_DIR so the counter survives separate invocations (e.g. running with
# MAX_ITERATIONS=1 repeatedly). Logs are always named iter-NN[-...].log so
# the prefix is searchable; the optional "-item-MM[-halt]" suffix records
# what each iteration did.

LAST_ITER=$(ls "$LOG_DIR" 2>/dev/null \
            | grep -oE '^iter[-_][0-9]+' \
            | grep -oE '[0-9]+' \
            | sort -n | tail -1)
# Force base-10 interpretation: printf '%02d' pads to "08"/"09", and bash's
# arithmetic mode would treat those as octal — failing on digits ≥ 8.
LAST_ITER=$((10#${LAST_ITER:-0}))
START=$((LAST_ITER + 1))
END=$((LAST_ITER + MAX_ITERATIONS))

# ---------- Main loop ----------

for i in $(seq "$START" "$END"); do
    CALL=$((i - LAST_ITER))

    # Determine model/effort for this iteration.
    # Priority: env var (set in parent shell) > hint file > default.
    ITER_MODEL="${MODEL:-$(hint_get MODEL "$HINT_FILE" "$DEFAULT_MODEL")}"
    ITER_EFFORT="${EFFORT:-$(hint_get EFFORT "$HINT_FILE" "$DEFAULT_EFFORT")}"

    printf '\n=== Iteration %d (call %d/%d) [model=%s effort=%s] — %s ===\n' \
        "$i" "$CALL" "$MAX_ITERATIONS" "$ITER_MODEL" "$ITER_EFFORT" "$(date -Is)"

    # Snapshot progress.md size so we can detect what this iteration appended.
    PROGRESS_LINES_BEFORE=$(wc -l < "$PROGRESS" 2>/dev/null | tr -d ' ')
    PROGRESS_LINES_BEFORE="${PROGRESS_LINES_BEFORE:-0}"

    LOG="$LOG_DIR/iter-$(printf '%02d' "$i").log"
    RAW_LOG="${LOG%.log}.jsonl"

    # Use stream-json so every tool call, message, and result is captured.
    # The raw JSONL is preserved alongside the human-readable .log for
    # forensics; format_stream.py extracts the readable bits.
    claude --permission-mode bypassPermissions --verbose \
           --model "$ITER_MODEL" --effort "$ITER_EFFORT" \
           --output-format stream-json -p "$PROMPT" 2>&1 \
        | tee "$RAW_LOG" \
        | python3 "$TEMPLATE_DIR/format_stream.py" \
        | tee "$LOG"

    # Inspect what this iteration appended to progress.md to decorate the
    # log filename: -item-MM if a specific item was acted on, -halt if a
    # STOP.md was written.
    APPENDED=$(tail -n +$((PROGRESS_LINES_BEFORE + 1)) "$PROGRESS" 2>/dev/null)
    NEW_ITEM=$(printf '%s\n' "$APPENDED" | grep -m1 -oE '^## Item [0-9]+' | grep -oE '[0-9]+')

    SUFFIX=""
    [[ -n "${NEW_ITEM:-}" ]] && SUFFIX="-item-$(printf '%02d' "$NEW_ITEM")"
    [[ -f "$STOP"         ]] && SUFFIX="${SUFFIX}-halt"

    if [[ -n "$SUFFIX" ]]; then
        RENAMED="$LOG_DIR/iter-$(printf '%02d' "$i")${SUFFIX}.log"
        RENAMED_RAW="${RENAMED%.log}.jsonl"
        mv -f "$LOG"     "$RENAMED"
        [[ -f "$RAW_LOG" ]] && mv -f "$RAW_LOG" "$RENAMED_RAW"
        LOG="$RENAMED"
        RAW_LOG="$RENAMED_RAW"
        echo "  log: $LOG"
    fi

    # ---------- Stop conditions ----------

    if [[ -f "$STOP" ]]; then
        echo
        echo "Halted: $STOP was written during iteration $i."
        echo "------ STOP.md ------"
        cat "$STOP"
        echo "---------------------"
        exit 1
    fi

    if tail -n 1 "$PROGRESS" 2>/dev/null | grep -q '^STATUS: COMPLETE'; then
        echo
        echo "Roadmap complete after iteration $i."
        exit 0
    fi
done

echo
echo "Reached MAX_ITERATIONS=$MAX_ITERATIONS without completion." >&2
echo "Inspect $PROGRESS to see how far the loop got." >&2
exit 1
