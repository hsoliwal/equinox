#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 multipass, mechanical pass two: every Java line the recipe changed on the branch, marked with its bundle,
# scope (MAIN/TEST/EXAMPLE), type, enclosing method (enclosing_method.awk, the correction-sites pass 3 helper),
# construct (LAMBDA_PARAM, CATCH_PARAM, TRY_RESOURCE, PATTERN, LOCAL) read from the original line, the names given,
# and a permalink at the branch head. Pass one is the grep census (CENSUS.tsv); the final pass reads this table.
# Usage: jdk21_pass2.sh <worktree> <github-owner/repo> <base-rev> > PASS2_MARKS.tsv
set -euo pipefail
W="$1"; GH="$2"; BASE="$3"; HERE=$(cd "$(dirname "$0")" && pwd); export LC_ALL=C
HEAD=$(git -C "$W" rev-parse HEAD); BL="$W/docs/m3/jdk21/BUNDLES.txt"
printf 'path\tline\tbundle\tscope\ttype\tenclosing_method\tconstruct\tnames\tpermalink\n'
# hunks: "path<TAB>newline<TAB>old-text<TAB>new-text" for one-for-one replaced lines
git -C "$W" diff -U0 --no-color "$BASE" HEAD -- '*.java' ':!docs/*' | awk '
	/^\+\+\+ b\// { path = substr($0, 7); sub(/\t$/, "", path); next }   # git appends a tab to names with spaces
	/^@@ / { split($3, a, ","); nl = substr(a[1], 2) + 0; no = 0; np = 0; delete old; next }
	/^-/ && !/^---/ { t = substr($0, 2); gsub(/\t/, " ", t); old[++no] = t; next }
	/^\+/ { np++; t = substr($0, 2); gsub(/\t/, " ", t); printf "%s\t%d\t%s\t%s\n", path, nl, (np in old ? old[np] : ""), t; nl++; next }
' | tr -d '\r' > "$W/.pass2.rows"
cut -f1 "$W/.pass2.rows" | sort -u | while IFS= read -r p; do
	want=$(awk -F'\t' -v p="$p" '$1 == p { printf "%s%s", s, $2; s = "," }' "$W/.pass2.rows")
	awk -v want="$want" -f "$HERE/enclosing_method.awk" "$W/$p" | sed "s|^|$p\t|"
done > "$W/.pass2.methods"
awk -F'\t' -v OFS='\t' -v GH="$GH" -v HEAD="$HEAD" -v BL="$BL" '
	BEGIN { while ((getline l < BL) > 0) { sub(/\r$/, "", l); if (l != "") b[++nb] = l } }
	FNR == NR { m[$1 "\t" $2] = $3; next }
	{ p = $1; bun = "-"; for (i = 1; i <= nb; i++) if (index(p, b[i] "/") == 1 && (bun == "-" || length(b[i]) > length(bun))) bun = b[i]
	  scope = (p ~ /(^|\/)tests?\// || p ~ /\.tests?(\.[^\/]*)?\//) ? "TEST" : (p ~ /(^|\/)examples?\//) ? "EXAMPLE" : "MAIN"
	  type = p; sub(/^.*\//, "", type); sub(/\.java$/, "", type)
	  o = $3
	  c = (o ~ /catch[ \t]*\(/) ? "CATCH_PARAM" : (o ~ /try[ \t]*\(/) ? "TRY_RESOURCE" : (o ~ /(case|instanceof)[ \t]/) ? "PATTERN" : (o ~ /->/) ? "LAMBDA_PARAM" : "LOCAL"
	  names = ""; t = $4; while (match(t, /unused[0-9]*/)) { names = names (names == "" ? "" : ",") substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH) }
	  print p, $2, bun, scope, type, (($1 "\t" $2) in m ? m[$1 "\t" $2] : "-"), c, names, "https://github.com/" GH "/blob/" HEAD "/" p "#L" $2 }
' "$W/.pass2.methods" "$W/.pass2.rows"
rm -f "$W/.pass2.rows" "$W/.pass2.methods"
