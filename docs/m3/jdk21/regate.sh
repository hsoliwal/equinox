#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
# JDK21 fix-and-regate loop for one fork: recipe again (fixed point), collision pass on the residue, gate
# --release 21, residue = errors(21) - errors(25 baseline) - rows of files javac rejects for a UTF-8 BOM in the
# baseline (javac refuses a BOM, ECJ accepts it, and parser recovery after it differs between source levels).
# Up to 3 rounds; stops when no collision is left. Usage: regate.sh <repo>
set -euo pipefail
R="$1"; D=S:/m3-scratch/jdk21; W=S:/m3-scratch/worktrees/jdk21-$R; cd "$D"
residue() { # (the BOM list is read in BEGIN: an empty first file would make NR == FNR true for every row)
	grep -F "illegal character: '/ufeff'" "gate/$R.base25.tsv" | cut -f1 | sort -u > "gate/$R.bom" || true
	comm -23 "gate/$R.jdk21.tsv" "gate/$R.base25.tsv" \
	| awk -F'\t' -v bf="gate/$R.bom" 'BEGIN { while ((getline l < bf) > 0) bom[l] = 1 } !($1 in bom)' > "gate/$R.residue.tsv"
}
residue
for round in 1 2 3; do
	bash recipe/apply_jdk21.sh "$W" "bundles-$R.txt" >> "gate/$R.recipe2.tsv"
	n=$(bash recipe/fix_collisions.sh "$W" "gate/$R.residue.tsv" | tee -a "gate/$R.collisions.tsv" | wc -l)
	echo "$R round $round: $n collisions fixed"
	[ "$n" -gt 0 ] || break
	./compile_gate.sh "$R" 21 jdk21; residue
done
echo "$R residue: $(wc -l < "gate/$R.residue.tsv") errors"
