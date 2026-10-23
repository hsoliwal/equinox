#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# Multipass marks across all of Eclipse by template matching, streamed with git grep over the bare forks (no
# checkout, no LLM). Pass three: TEMPLATES.tsv (listener and callback families -> enhancement targets, learned
# from the interface each call registers). Pass four: CODE_MAPPING.tsv (Java API usage -> M3 replacements).
# Usage: sweep.sh <catalogue.tsv> <out-dir> <repo>:<rev>...
# Output: <out-dir>/COUNTS.tsv  (repo template target scope sites files)
#         <out-dir>/sites/<repo>.tsv.gz  (template scope path line), one row per matching line, all scopes
set -euo pipefail
CAT="$1"; OUT="$2"; shift 2; F=S:/m3-scratch/forks; export LC_ALL=C GIT_NO_LAZY_FETCH=1
mkdir -p "$OUT/sites"; printf 'repo\ttemplate\ttarget\tscope\tsites\tfiles\n' > "$OUT/COUNTS.tsv"
for rr in "$@"; do
	R="${rr%%:*}"; REV="${rr#*:}"; G="$F/$R.git"
	tail -n +2 "$CAT" | while IFS=$'\t' read -r id re api target rule; do
		git -C "$G" grep -n -I -E -e "$re" "$REV" -- '*.java' ':(exclude).superset/*' 2>/dev/null \
		| awk -v id="$id" -v rev="$REV:" 'BEGIN { OFS = "\t" }
			{ sub("^" rev, ""); p = index($0, ":"); f = substr($0, 1, p - 1); r = substr($0, p + 1); q = index(r, ":"); n = substr(r, 1, q - 1)
			  s = (f ~ /(^|\/)tests?\// || f ~ /\.tests?(\.[^\/]*)?\// || f ~ /\/src\/test\//) ? "TEST" : (f ~ /(^|\/)examples?\//) ? "EXAMPLE" : "MAIN"
			  print id, s, f, n }' || true
	done > "$OUT/sites/$R.tsv"
	awk -F'\t' -v OFS='\t' -v R="$R" 'NR == FNR { if (FNR > 1) t[$1] = $4; next }
		{ k = $1 "\t" $2; c[k]++; if (!((k, $3) in seen)) { seen[k, $3] = 1; fc[k]++ } }
		END { for (k in c) { split(k, a, "\t"); print R, a[1], t[a[1]], a[2], c[k], fc[k] } }' "$CAT" "$OUT/sites/$R.tsv" \
		| sort -t$'\t' -k2,2 -k4,4 >> "$OUT/COUNTS.tsv"
	gzip -9 -f "$OUT/sites/$R.tsv"
	echo "$R: $(zcat "$OUT/sites/$R.tsv.gz" | wc -l) sites" >&2
done
