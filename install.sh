#!/usr/bin/env bash
# Idempotent installer for dotclaude.
#
# Creates symlinks from ~/.claude/{commands,templates}/ into this repo.
# Commands are linked file-by-file (so unrelated commands from other
# sources can coexist). Templates are linked directory-by-directory
# (one template = one directory).
#
# Existing files/directories at the install destinations are backed up
# with a timestamp suffix (.bak.<unix-time>) before the symlink is made.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST_BASE="$HOME/.claude"

install_symlink() {
    local src="$1" dest="$2"

    if [[ -L "$dest" ]]; then
        local current
        current="$(readlink "$dest")"
        if [[ "$current" == "$src" ]]; then
            echo "  = $dest (already linked)"
            return
        fi
    fi

    if [[ -e "$dest" ]]; then
        local backup="$dest.bak.$(date +%s)"
        echo "  ↩ backing up $dest → $backup"
        mv "$dest" "$backup"
    fi

    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    echo "  + $dest → $src"
}

echo "Installing from $REPO_DIR → $DEST_BASE"

echo
echo "Commands:"
shopt -s nullglob
for f in "$REPO_DIR"/commands/*.md; do
    install_symlink "$f" "$DEST_BASE/commands/$(basename "$f")"
done

echo
echo "Templates:"
for d in "$REPO_DIR"/templates/*/; do
    name="$(basename "${d%/}")"
    install_symlink "${d%/}" "$DEST_BASE/templates/$name"
done

echo
echo "Done."
