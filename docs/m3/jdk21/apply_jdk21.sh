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
#   5. *.java holding a standalone `_` token: unnamed variables -> `unused`, `unused2`, ... (unnamed_to_named.awk)
# Only lines that match change; line endings and every other byte stay (sed -b, awk BINMODE=3: Git Bash tools
# otherwise drop CR bytes). A failing tool never overwrites a file, and an output whose line count differs from
# the input is refused. Prints one TSV row per changed file:  step <TAB> path <TAB> changed-lines
# Fixed point: a second run prints nothing.
set -euo pipefail
WT="$1"; LIST="$2"; HERE=$(cd "$(dirname "$0")" && pwd)
export LC_ALL=C
replace() { # replace <step> <file> <tmp>: install tmp over file when it differs and keeps the line count
	local f="$2" tmp="$3"
	if cmp -s "$f" "$tmp"; then rm -f "$tmp"; return 0; fi
	if [ "$(wc -l < "$tmp")" -ne "$(wc -l < "$f")" ]; then
		echo "REFUSED $1 ${f#$WT/}: line count changed" >&2; rm -f "$tmp"; return 0; fi
	printf '%s\t%s\t%s\n' "$1" "${f#$WT/}" "$(diff "$f" "$tmp" | grep -c '^>' || true)"; cat "$tmp" > "$f"; rm -f "$tmp"
}
edit() { # edit <dir> <file> <sed-expr> <step>
	local f="$1/$2"
	[ -f "$f" ] || return 0
	if sed -b -E "$3" "$f" > "$f.jdk21.tmp"; then replace "$4" "$f" "$f.jdk21.tmp"; else rm -f "$f.jdk21.tmp"; echo "FAILED sed $f" >&2; fi
}
while IFS= read -r b || [ -n "$b" ]; do
	b="${b%$'\r'}"; [ -n "$b" ] || continue
	edit "$WT/$b" META-INF/MANIFEST.MF '/^Bundle-RequiredExecutionEnvironment:/ s/JavaSE-2[2-9]/JavaSE-21/' manifest
	edit "$WT/$b" .classpath '/JRE_CONTAINER/ s/JavaSE-2[2-9]"/JavaSE-21"/' classpath
	edit "$WT/$b" .settings/org.eclipse.jdt.core.prefs \
		's/^(org\.eclipse\.jdt\.core\.compiler\.(codegen\.targetPlatform|compliance|source))=2[2-9]/\1=21/' prefs
	edit "$WT/$b" build.properties 's/^(jre\.compilation\.profile[ \t]*=[ \t]*)JavaSE-2[2-9]/\1JavaSE-21/' buildprops
	# one grep per bundle selects the files with a standalone `_` (in code, strings or comments); awk decides
	# (no match is grep status 1: `|| true` keeps pipefail + set -e from ending the run at this bundle)
	{ grep -r -l -Z -E --include='*.java' '(^|[^A-Za-z0-9_$])_([^A-Za-z0-9_$]|$)' "$WT/$b" 2>/dev/null || true; } \
	| while IFS= read -r -d '' j; do
		if awk -v BINMODE=3 -f "$HERE/unnamed_to_named.awk" "$j" > "$j.jdk21.tmp"; then replace java "$j" "$j.jdk21.tmp"
		else rm -f "$j.jdk21.tmp"; echo "FAILED awk $j" >&2; fi
	done
done < "$LIST"
