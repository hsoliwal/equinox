#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 compile gate (BLLSE), release-readiness variant of S:/m3-scratch/jdk21/compile_gate.sh: same javac run
# (attribution + flow only, no class files) over every source root of the listed bundles, against the newest jar
# of every bundle in the p2 pool; worktree, bundle list, output directory and javac are parameters.
# Usage: compile_gate.sh <worktree> <bundle-list> <release> <out-prefix>   -> <out-prefix>.tsv (path TAB line TAB msg)
#   env: JAVAC (default F:/m3-scratch/jdks/jdk-25.0.4.1+1/bin/javac), POOL_CP (default the 2026-10-20 pool list)
set -euo pipefail
W="$1"; L="$2"; REL="$3"; O="$4"
JAVAC="${JAVAC:-F:/m3-scratch/jdks/jdk-25.0.4.1+1/bin/javac}"; CP="${POOL_CP:-S:/m3-scratch/jdk21/gate/pool.cp}"
mkdir -p "$(dirname "$O")"
ROOTS=$O.roots
while IFS= read -r b || [ -n "$b" ]; do
	b="${b%$'\r'}"; [ -n "$b" ] || continue; bp="$W/$b/build.properties"
	if [ -f "$bp" ]; then
		awk 'BEGIN{c=0} /^[ \t]*source\.[^=]*=/ {c=1; sub(/^[^=]*=/,"")} c { line=$0; c=(line ~ /\\[ \t\r]*$/); gsub(/\\[ \t\r]*$/,"",line); gsub(/\r/,"",line); n=split(line, a, ","); for(i=1;i<=n;i++){ gsub(/^[ \t]+|[ \t]+$/,"",a[i]); if(a[i]!="") print a[i] } }' "$bp" \
			| sed "s|^|$W/$b/|; s|/$||"
	else echo "$W/$b/src"; fi
done < "$L" | sort -u | while read -r r; do if [ -d "$r" ]; then echo "$r"; fi; done > "$ROOTS"
SRC=$O.sources
# sources a bundle pom keeps out of the Tycho build (tycho-compiler-plugin <excludes>, exact root-relative paths)
XL=$O.excluded; : > "$XL"
while IFS= read -r b || [ -n "$b" ]; do
	b="${b%$'\r'}"; p="$W/$b/pom.xml"; [ -n "$b" ] && [ -f "$p" ] && grep -q 'tycho-compiler-plugin' "$p" || continue
	tr -d '\r' < "$p" | sed -n 's|.*<exclude>\([^<*]*\)</exclude>.*|\1|p' | while read -r x; do
		grep -F "$W/$b/" "$ROOTS" | sed "s|\$|/$x|"; done >> "$XL"
done < "$L"
while read -r r; do find "$r" -name '*.java' -type f; done < "$ROOTS" | grep -v -x -F -f "$XL" | sed 's|^|"|; s|$|"|' > "$SRC" || true
{ echo "-cp"; echo "\"$(tr '\n' ';' < "$CP")\""; echo "-sourcepath"; echo "\"$(tr '\n' ';' < "$ROOTS")\""; } > "$O.args"
LOG=$O.log
"$JAVAC" -J-Xmx6g --release "$REL" -encoding UTF-8 -proc:none -nowarn -Xmaxerrs 1000000 -Xmaxwarns 0 -implicit:none \
	-XDshould-stop.ifError=FLOW -XDshould-stop.ifNoError=FLOW @"$O.args" @"$SRC" > "$LOG" 2>&1 || true
WN=$(cygpath -w "$W" | tr '\\' '/')
{ grep -a -E '^[A-Za-z]:[^:]*\.java:[0-9]+: error: ' "$LOG" || true; } | tr '\\' '/' | sed "s|^$W/||; s|^$WN/||" \
	| sed -E 's/^(.*\.java):([0-9]+): error: (.*)$/\1\t\2\t\3/' | tr -d '\r' | sort -u > "$O.tsv"
echo "$(basename "$O") --release $REL: $(wc -l < "$SRC") files, $(wc -l < "$ROOTS") roots, $(wc -l < "$O.tsv") errors"
