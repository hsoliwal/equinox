#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 text-lane recipe: make the bundles of an Eclipse fork that declare Java 22+ build and run on JDK 21
# (M3JDK21). Per bundle directory listed in $2 (one path per line, relative to the worktree $1):
#   1. META-INF/MANIFEST.MF  Bundle-RequiredExecutionEnvironment: JavaSE-2x -> JavaSE-21
#   2. .classpath            JRE_CONTAINER .../JavaSE-2x               -> JavaSE-21
#   3. .settings/org.eclipse.jdt.core.prefs compiler.{codegen.targetPlatform,compliance,source}=2x -> 21
#   4. build.properties      jre.compilation.profile = JavaSE-2x        -> JavaSE-21
#   5. every *.java          unnamed variables `_` -> `unused`, `unused2`, ... (unnamed_to_named.awk)
# Only lines that match change; line endings and every other byte stay. Prints one TSV row per changed file:
#   step <TAB> path <TAB> changed-lines
# Fixed point: a second run prints nothing.
set -euo pipefail
WT="$1"; LIST="$2"; HERE=$(cd "$(dirname "$0")" && pwd)
export LC_ALL=C
edit() { # edit <step> <file> <sed-expr>
	local f="$1/$2" tmp
	[ -f "$f" ] || return 0
	tmp="$f.jdk21.tmp"; sed -b -E "$3" "$f" > "$tmp"
	if cmp -s "$f" "$tmp"; then rm -f "$tmp"; else
		printf '%s\t%s\t%s\n' "$4" "${f#$WT/}" "$(diff "$f" "$tmp" | grep -c '^>')"; cat "$tmp" > "$f"; rm -f "$tmp"; fi
}
while IFS= read -r b || [ -n "$b" ]; do
	b="${b%$'\r'}"; [ -n "$b" ] || continue
	edit "$WT/$b" META-INF/MANIFEST.MF '/^Bundle-RequiredExecutionEnvironment:/ s/JavaSE-2[2-9]/JavaSE-21/' manifest
	edit "$WT/$b" .classpath '/JRE_CONTAINER/ s/JavaSE-2[2-9]"/JavaSE-21"/' classpath
	edit "$WT/$b" .settings/org.eclipse.jdt.core.prefs \
		's/^(org\.eclipse\.jdt\.core\.compiler\.(codegen\.targetPlatform|compliance|source))=2[2-9]/\1=21/' prefs
	edit "$WT/$b" build.properties 's/^(jre\.compilation\.profile[ \t]*=[ \t]*)JavaSE-2[2-9]/\1JavaSE-21/' buildprops
	find "$WT/$b" -name '*.java' -type f -print0 | while IFS= read -r -d '' j; do
		grep -q '_' "$j" || continue
		awk -v BINMODE=3 -f "$HERE/unnamed_to_named.awk" "$j" > "$j.jdk21.tmp"
		if cmp -s "$j" "$j.jdk21.tmp"; then rm -f "$j.jdk21.tmp"; else
			printf 'java\t%s\t%s\n' "${j#$WT/}" "$(diff "$j" "$j.jdk21.tmp" | grep -c '^>')"; cat "$j.jdk21.tmp" > "$j"; rm -f "$j.jdk21.tmp"; fi
	done
done < "$LIST"
