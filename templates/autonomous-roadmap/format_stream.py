#!/usr/bin/env python3
"""Convert Claude Code `--output-format=stream-json` to human-readable text.

Reads JSONL events from stdin, writes a compact human-readable stream to
stdout. Designed to be tee'd to a `.log` file while the raw events are
preserved in a parallel `.jsonl` file by the caller.

Defensive: never raises; on any parse/format error, falls back to dumping
a short marker so the pipeline keeps flowing.
"""
import json
import sys

MAX_INPUT = 300
MAX_RESULT_LINES = 8
MAX_RESULT_LINE_CHARS = 240


def truncate(s: str, n: int) -> str:
    """Collapse to a single line and cap length — used for tool inputs."""
    s = str(s).replace("\n", " ")
    return s if len(s) <= n else s[: n - 3] + "..."


def truncate_block(s: str, max_lines: int = MAX_RESULT_LINES,
                   max_chars: int = MAX_RESULT_LINE_CHARS) -> str:
    """Preserve newlines but cap line count and per-line width.
    Used for tool results where newlines are meaningful."""
    lines = str(s).splitlines()
    cropped = lines[:max_lines]
    out = []
    for line in cropped:
        if len(line) > max_chars:
            line = line[: max_chars - 3] + "..."
        out.append(line)
    if len(lines) > max_lines:
        out.append(f"... (+{len(lines) - max_lines} more lines)")
    return "\n".join(out)


def emit(line: str) -> None:
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def extract_tool_result_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for c in content:
            if isinstance(c, dict):
                parts.append(c.get("text") or json.dumps(c, ensure_ascii=False))
            else:
                parts.append(str(c))
        return "\n".join(parts)
    return str(content)


def handle_event(ev: dict) -> None:
    t = ev.get("type")

    if t == "system" and ev.get("subtype") == "init":
        sess = (ev.get("session_id") or "?")[:8]
        model = ev.get("model", "?")
        emit(f"[init] session={sess} model={model}")
        return

    if t == "assistant":
        for block in ev.get("message", {}).get("content", []) or []:
            bt = block.get("type")
            if bt == "text":
                text = (block.get("text") or "").strip()
                if text:
                    emit(text)
            elif bt == "tool_use":
                name = block.get("name", "?")
                inp = json.dumps(block.get("input", {}), ensure_ascii=False)
                emit(f"  → {name}({truncate(inp, MAX_INPUT)})")
            elif bt == "thinking":
                pass  # internal reasoning — skip for readability
        return

    if t == "user":
        for block in ev.get("message", {}).get("content", []) or []:
            if block.get("type") == "tool_result":
                text = extract_tool_result_text(block.get("content", "")).strip()
                if not text:
                    emit("  ← (empty)")
                    continue
                block_text = truncate_block(text)
                lines = block_text.splitlines()
                emit(f"  ← {lines[0]}")
                for line in lines[1:]:
                    emit(f"    {line}")
        return

    if t == "result":
        sub = ev.get("subtype", "")
        result = (ev.get("result") or "").strip()
        emit("")
        emit(f"[result:{sub}]")
        if result:
            emit(result)
        return


def main() -> None:
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            ev = json.loads(raw)
        except Exception:
            emit(f"[unparseable] {truncate(raw, 200)}")
            continue
        try:
            handle_event(ev)
        except Exception as e:
            emit(f"[format-error: {e}] {truncate(raw, 200)}")


if __name__ == "__main__":
    main()
