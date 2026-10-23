#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
# JDK21 collision pass over a gate residue: every "variable unusedK is already defined" row renames that
# declaration (rename_at.awk). Rows are applied bottom-up per file so line numbers stay valid; one rename per line.
# Usage: fix_collisions.sh <worktree> <residue.tsv>   Prints: collision <TAB> path:line <TAB> old -> new
set -euo pipefail
WT="$1"; RES="$2"; HERE=$(cd "$(dirname "$0")" && pwd); export LC_ALL=C
{ grep -E $'\tvariable unused[0-9]* is already defined' "$RES" || true; } | sort -t$'\t' -k1,1 -k2,2nr -u \
| while IFS=$'\t' read -r path line msg; do
	name=$(printf '%s' "$msg" | sed -E 's/^variable (unused[0-9]*) is already defined.*/\1/')
	f="$WT/$path"; [ -f "$f" ] || { echo "MISSING $path" >&2; continue; }
	if awk -v BINMODE=3 -v LINE="$line" -v NAME="$name" -f "$HERE/rename_at.awk" "$f" "$f" > "$f.jdk21.tmp" \
		&& [ "$(wc -l < "$f.jdk21.tmp")" -eq "$(wc -l < "$f")" ] && ! cmp -s "$f" "$f.jdk21.tmp"; then
		new=$(diff "$f" "$f.jdk21.tmp" | grep -o -E 'unused[0-9]+' | tail -1 || true)
		cat "$f.jdk21.tmp" > "$f"; printf 'collision\t%s:%s\t%s -> %s\n' "$path" "$line" "$name" "$new"
	else echo "REFUSED $path:$line $name" >&2; fi
	rm -f "$f.jdk21.tmp"
done
