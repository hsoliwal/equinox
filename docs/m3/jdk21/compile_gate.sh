#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 compile gate (BLLSE): one javac run over every source root of the fork's Java 22+ bundles, attribution
# and flow analysis only (no class files), against the newest jar of every bundle in the p2 pool.
# Usage: compile_gate.sh <repo> <release> <tag>  -> S:/m3-scratch/jdk21/gate/<repo>.<tag>.tsv
#   rows: path <TAB> line <TAB> message   (sorted, unique; the error key used by the differential)
# The differential errors(--release 21, recipe applied) - errors(--release 25, original) is the Java 22+ residue:
# classpath noise (master APIs newer than the pool jars) appears in both runs and cancels out.
set -euo pipefail
R="$1"; REL="$2"; TAG="$3"; W=S:/m3-scratch/worktrees/jdk21-$R; D=S:/m3-scratch/jdk21; L=$D/bundles-$R.txt
JAVAC="F:/jdks/temurin25/jdk-25.0.4.1+1/bin/javac"; mkdir -p "$D/gate"
CP=$D/gate/pool.cp
if [ ! -s "$CP" ]; then # newest version of every bundle in the pool; directory bundles add their root and jars
	P=$(cygpath -m ~/.p2/pool/plugins)
	ls "$P" | sed -E 's/^([^_]+)_(.*)$/\1\t\2/' | sort -t$'\t' -k1,1 -k2,2V | awk -F'\t' '{last[$1]=$0} END{for(k in last) print last[k]}' \
		| tr '\t' '_' | while read -r e; do
			if [ -d "$P/$e" ]; then echo "$P/$e"; find "$P/$e" -name '*.jar' | sed 's|\\|/|g'; else echo "$P/$e"; fi
		done | sort > "$CP"
fi
ROOTS=$D/gate/$R.roots
while IFS= read -r b || [ -n "$b" ]; do
	b="${b%$'\r'}"; bp="$W/$b/build.properties"
	if [ -f "$bp" ]; then
		awk 'BEGIN{c=0} /^[ \t]*source\.[^=]*=/ {c=1; sub(/^[^=]*=/,"")} c { line=$0; c=(line ~ /\\[ \t\r]*$/); gsub(/\\[ \t\r]*$/,"",line); gsub(/\r/,"",line); n=split(line, a, ","); for(i=1;i<=n;i++){ gsub(/^[ \t]+|[ \t]+$/,"",a[i]); if(a[i]!="") print a[i] } }' "$bp" \
			| sed "s|^|$W/$b/|; s|/$||"
	else echo "$W/$b/src"; fi
done < "$L" | sort -u | while read -r r; do [ -d "$r" ] && echo "$r"; done > "$ROOTS"
SRC=$D/gate/$R.sources; : > "$SRC"
while read -r r; do find "$r" -name '*.java' -type f; done < "$ROOTS" | sed 's|^|"|; s|$|"|' > "$SRC"
{ echo "-cp"; echo "\"$(tr '\n' ';' < "$CP")\""; echo "-sourcepath"; echo "\"$(tr '\n' ';' < "$ROOTS")\""; } > "$D/gate/$R.args"
LOG=$D/gate/$R.$TAG.log
"$JAVAC" -J-Xmx6g --release "$REL" -encoding UTF-8 -proc:none -nowarn -Xmaxerrs 1000000 -Xmaxwarns 0 -implicit:none \
	-XDshould-stop.ifError=FLOW -XDshould-stop.ifNoError=FLOW @"$D/gate/$R.args" @"$SRC" > "$LOG" 2>&1 || true
grep -a -E '^[A-Za-z]:[^:]*\.java:[0-9]+: error: ' "$LOG" | sed "s|^$W/||" \
	| sed -E 's/^(.*\.java):([0-9]+): error: (.*)$/\1\t\2\t\3/' | tr -d '\r' | sort -u > "$D/gate/$R.$TAG.tsv"
echo "$R --release $REL [$TAG]: $(wc -l < "$SRC") files, $(wc -l < "$ROOTS") roots, $(wc -l < "$D/gate/$R.$TAG.tsv") errors"
