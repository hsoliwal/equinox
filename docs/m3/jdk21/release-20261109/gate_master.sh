#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# Release-readiness gate of one Eclipse fork for M3JDK21 (Java 21), run on a depth-1 clone of fork master.
#   1. bundle list  = old Java 22+ list (2026-10-20) + bundles upstream master declares JavaSE-22+ + bundles fork
#                     master still declares JavaSE-22+   -> <G>.bundles
#   2. census       = Java 22+ language lines (unnamed `_`, import module) in main sources + 22+ pins -> <G>.census.tsv
#   3. base25       = javac --release 25 on the master tree
#   4. recipe       = apply_jdk21.sh (bundles) + apply_jdk21_pins.sh (repo) on the same tree -> <G>.recipe.tsv
#   5. jdk21        = javac --release 21 on the recipe output; residue = jdk21 - base25 - BOM-file rows
# Usage: gate_master.sh <repo>     (clone F:/m3-scratch/rel21/forks/<repo>, outputs F:/m3-scratch/rel21/gate/<repo>.*)
set -euo pipefail
R="$1"; W=F:/m3-scratch/rel21/forks/$R; G=F:/m3-scratch/rel21/gate/$R; T=F:/m3-scratch/rel21/tools
REC=S:/m3-scratch/jdk21/recipe; OLD=S:/m3-scratch/jdk21/bundles-$R.txt; export LC_ALL=C
EXCL=(':(exclude)*/tests/*' ':(exclude)*/test/*' ':(exclude)*/testresources/*' ':(exclude)*/testResources/*' ':(exclude)*/workspace/*'
      ':(exclude)*.tests.*/*' ':(exclude)*/test-data/*' ':(exclude)*/resources/*' ':(exclude)*/testdata/*'
      ':(exclude)*/src/test/*' ':(exclude)docs/*')
BREE='Bundle-RequiredExecutionEnvironment:.*JavaSE-2[2-9]'
# exemptions: pathspec globs whose Java level is intentional (compiler test data, CI tooling): tools/exempt-<repo>.tsv
XEX=(); XIN=()
if [ -f "$T/exempt-$R.tsv" ]; then while IFS=$'	' read -r g why; do [ -n "$g" ] && XEX+=(":(exclude)$g") && XIN+=("$g"); done < "$T/exempt-$R.tsv"; fi
{ if [ -f "$OLD" ]; then tr -d '\r' < "$OLD"; echo; fi
  git -C "$W" diff -U0 master upstream/master -- '*MANIFEST.MF' \
	| awk -v re="^\\\\+$BREE" '/^\+\+\+ b\//{f=substr($0,7)} $0 ~ re {print f}' | sed 's|/\?META-INF/MANIFEST.MF$||'
  { git -C "$W" grep -l -P "$BREE" master -- '*MANIFEST.MF' || true; } | sed 's|^master:||; s|/\?META-INF/MANIFEST.MF$||'
  # bundles whose IDE/PDE metadata alone asks for 22+ (.classpath, jdt prefs, build.properties profile)
  { git -C "$W" grep -l -P 'JRE_CONTAINER.*JavaSE-2[2-9]|compiler\.(compliance|source|codegen\.targetPlatform)=2[2-9]|jre\.compilation\.profile\s*=\s*JavaSE-2[2-9]' master \
	-- '*.classpath' '*org.eclipse.jdt.core.prefs' '*build.properties' ':(exclude)docs/*' "${XEX[@]}" || true; } \
	| sed 's|^master:||; s#/\?\(\.classpath\|\.settings/org\.eclipse\.jdt\.core\.prefs\|build\.properties\)$##' | sed '/^$/d'
} | sed '/^$/d' | sort -u | while read -r b; do if [ -d "$W/$b" ]; then echo "$b"; fi; done > "$G.bundles"
q() { git -C "$W" grep -n -I -P -e "$2" master -- "${@:3}" | sed 's|^master:||' | awk -v k="$1" 'BEGIN{OFS="\t"}{print k,$0}' || true; }
qc() { # language census on the code view (code_view.awk): a hit inside a string, text block or comment is not code
	q "$@" | while IFS=$'\t' read -r k rest; do
		f=${rest%%:*}; r2=${rest#*:}; ln=${r2%%:*}
		if git -C "$W" show "master:$f" | awk -v BINMODE=3 -f "$T/code_view.awk" | sed -n "${ln}p" | LC_ALL=C.UTF-8 grep -q -P -e "$2"
		then printf '%s\t%s\n' "$k" "$rest"; else printf '%s\t%s\n' "$k" "$rest" >> "$G.census.masked.tsv"; fi
	done; }
: > "$G.census.masked.tsv"
{ q bree "$BREE" '*MANIFEST.MF'
  q pin '<(maven\.compiler\.(release|source|target)|release|java\.version|javaVersion|tycho\.compiler\.release)>2[2-9]<|<executionEnvironment>JavaSE-2[2-9]<|requiredJavaVersion=2[2-9]|jre\.compilation\.profile\s*=\s*JavaSE-2[2-9]|JRE_CONTAINER.*JavaSE-2[2-9]|compiler\.(compliance|source|codegen\.targetPlatform)=2[2-9]' \
	'*pom.xml' '*.ini' '*.product' '*build.properties' '*.classpath' '*org.eclipse.jdt.core.prefs' ':(exclude)docs/*' "${XEX[@]}"
  qc unnamed_lambda '(?:^|[(,\s])_\s*(?:\)\s*)?->|\(\s*_\s*,|,\s*_\s*\)\s*->' '*.java' "${EXCL[@]}" "${XEX[@]}"
  qc unnamed_decl '[\w>\]]\s+_\s*(?:\)|=[^=]|:)' '*.java' "${EXCL[@]}" "${XEX[@]}"
  qc unnamed_pattern '(?:case|instanceof)\b[^;{]*(?<![\w$'"'"'"])_(?![\w$'"'"'"])' '*.java' "${EXCL[@]}" "${XEX[@]}"
  qc import_module '^\s*import\s+module\s' '*.java' "${EXCL[@]}" "${XEX[@]}"
} > "$G.census.tsv"
# exempt rows, recorded with their reason (pins and unnamed variables inside the exempt globs)
: > "$G.census.exempt.tsv"
if [ ${#XIN[@]} -gt 0 ]; then
	{ git -C "$W" grep -n -I -P -e 'JavaSE-2[2-9]|=2[2-9]$|(?:^|[(,\s])_\s*(?:\)\s*)?->|import\s+module\s' master -- "${XIN[@]}" || true; } 		| sed 's|^master:||' | awk 'BEGIN{OFS="	"}{print "exempt",$0}' > "$G.census.exempt.tsv"
fi
echo "$R $(git -C "$W" rev-parse --short=12 master): $(wc -l < "$G.bundles") gated bundles; census $(cut -f1 "$G.census.tsv" | sort | uniq -c | tr -s ' \n' ' ')"
[ -z "${CENSUS_ONLY:-}" ] || exit 0
# baseline once per (master tree, bundle list); bundle list and census read the local branch master, so a re-run
# on the fix branch keeps both and compiles only the working tree at --release 21
if ! cmp -s "$G.bundles" "$G.base25.bundles" 2>/dev/null || [ ! -f "$G.base25.tsv" ]; then
	bash "$T/compile_gate.sh" "$W" "$G.bundles" 25 "$G.base25"; cp "$G.bundles" "$G.base25.bundles"; fi
{ bash "$REC/apply_jdk21.sh" "$W" "$G.bundles"; bash "$REC/apply_jdk21_pins.sh" "$W"; } > "$G.recipe.run.tsv"
cat "$G.recipe.run.tsv" >> "$G.recipe.tsv"  # every run appends; a fixed point appends nothing
echo "$R recipe: $(wc -l < "$G.recipe.run.tsv") files changed this run ($(cut -f1 "$G.recipe.run.tsv" | sort | uniq -c | tr -s ' \n' ' '))"
bash "$T/compile_gate.sh" "$W" "$G.bundles" 21 "$G.jdk21"
grep -F "illegal character: '/ufeff'" "$G.base25.tsv" | cut -f1 | sort -u > "$G.bom" || true
comm -23 "$G.jdk21.tsv" "$G.base25.tsv" \
	| awk -F'\t' -v bf="$G.bom" 'BEGIN { while ((getline l < bf) > 0) bom[l] = 1 } !($1 in bom)' > "$G.residue.tsv"
echo "$R residue: $(wc -l < "$G.residue.tsv") errors"
