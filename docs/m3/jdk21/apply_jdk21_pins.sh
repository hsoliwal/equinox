#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 text-lane recipe, repo-level pins: build and product files that ask for Java 22+.
#   pom.xml   <executionEnvironment>JavaSE-2x</executionEnvironment>  -> JavaSE-21 (Tycho target resolution)
#             <maven.compiler.release|source|target>2x<  <release>2x<   -> 21
#   *.product / *.ini  -Dosgi.requiredJavaVersion=2x                  -> 21 (the launcher refuses older VMs)
# Usage: apply_jdk21_pins.sh <worktree>   Prints: step <TAB> path <TAB> changed-lines. Fixed point. CR bytes kept.
set -euo pipefail
WT="$1"; export LC_ALL=C
pin() { # pin <step> <file> <sed-expr>
	local f="$2" tmp="$2.jdk21.tmp"
	sed -b -E "$3" "$f" > "$tmp"
	if cmp -s "$f" "$tmp"; then rm -f "$tmp"; else
		printf '%s\t%s\t%s\n' "$1" "${f#$WT/}" "$(diff "$f" "$tmp" | grep -c '^>')"; cat "$tmp" > "$f"; rm -f "$tmp"; fi
}
git -C "$WT" ls-files -z -- '*pom.xml' | while IFS= read -r -d '' p; do
	[ -f "$WT/$p" ] || continue
	pin pom "$WT/$p" 's#(<executionEnvironment>)JavaSE-2[2-9](</executionEnvironment>)#\1JavaSE-21\2#; s#(<(maven\.compiler\.(release|source|target)|release)>)2[2-9](<)#\121\4#'
done
git -C "$WT" ls-files -z -- '*.product' '*.ini' | while IFS= read -r -d '' p; do
	[ -f "$WT/$p" ] || continue
	pin product "$WT/$p" 's#(-Dosgi\.requiredJavaVersion=)2[2-9]#\121#g'
done
