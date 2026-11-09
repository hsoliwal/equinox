#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 fill, FFM -> JNA: a bundle that upstream moved from JNA to java.lang.foreign (final only in Java 22)
# goes back to the JNA form of the upstream commit before the move, without deleting tracked files:
#   1. every Java file the FFM commit modified or removed is restored from <pre-ffm-rev> (upstream, byte for byte)
#   2. every Java file the FFM commit added stays tracked but leaves the build:
#        pom.xml    tycho-compiler-plugin <excludes> (Tycho)      .classpath  src entry excluding= (JDT/PDE IDE)
#   3. MANIFEST.MF gets back the Require-Bundle / Import-Package lines the FFM commit removed (BREE stays 21)
# Usage: fill_ffm_to_jna.sh <worktree> <bundle-dir> <pre-ffm-rev> <ffm-rev>
#   both revisions must be present in the clone (git fetch --depth 1 --filter=blob:none upstream <sha>).
# Prints one TSV row per changed file: step TAB path. Fixed point: a second run prints nothing.
set -euo pipefail
W="$1"; B="$2"; PRE="$3"; FFM="$4"; export LC_ALL=C
cd "$W"
row() { printf '%s\t%s\n' "$1" "$2"; }
# 1. restore modified/removed Java files (status M or D in PRE..FFM)
git diff --name-status "$PRE" "$FFM" -- "$B" | awk -F'\t' '$1 ~ /^[MD]$/ && $2 ~ /\.java$/ {print $2}' | while read -r f; do
	mkdir -p "$(dirname "$f")"
	if ! git show "$PRE:$f" | cmp -s - "$f" 2>/dev/null; then git show "$PRE:$f" > "$f"; row restore "$f"; fi
done
# 2. FFM-only Java files: exclude from compilation (relative to their source root, here the first path segment after $B)
ADDED=$(git diff --name-status "$PRE" "$FFM" -- "$B" | awk -F'\t' '$1 == "A" && $2 ~ /\.java$/ {print $2}')
if [ -n "$ADDED" ]; then
	REL=$(echo "$ADDED" | sed "s|^$B/[^/]*/||")
	POM="$B/pom.xml"
	if [ -f "$POM" ] && ! grep -q 'tycho-compiler-plugin' "$POM"; then
		X=$(echo "$REL" | sed 's|^|              <exclude>|; s|$|</exclude>|')
		awk -v BINMODE=3 -v x="$X" '
			!done && /^[ \t]*<plugins>[ \t\r]*$/ { print; cr = ($0 ~ /\r$/) ? "\r" : ""
				n = split("      <plugin>|        <groupId>org.eclipse.tycho</groupId>|        <artifactId>tycho-compiler-plugin</artifactId>|        <configuration>|          <!-- M3JDK21: java.lang.foreign sources (Java 22+) stay in the tree but out of the Java 21 build -->|          <excludes>", h, "|")
				for (i = 1; i <= n; i++) print h[i] cr
				m = split(x, e, "\n"); for (i = 1; i <= m; i++) print e[i] cr
				print "          </excludes>" cr; print "        </configuration>" cr; print "      </plugin>" cr
				done = 1; next }
			{ print }' "$POM" > "$POM.fill.tmp" && mv "$POM.fill.tmp" "$POM" && row pom "$POM"
	fi
	CP="$B/.classpath"
	if [ -f "$CP" ] && ! grep -q 'excluding=' "$CP"; then
		EX=$(echo "$REL" | paste -sd'|' -)
		sed -b -E -i "s#(<classpathentry kind=\"src\" )(path=\"src/?\")#\1excluding=\"$EX\" \2#" "$CP" && row classpath "$CP"
	fi
fi
# 3. MANIFEST headers the FFM commit removed (Require-Bundle / Import-Package lines), appended once
M="$B/META-INF/MANIFEST.MF"
git diff "$PRE" "$FFM" -- "$M" | sed -n 's/^-\(\(Require-Bundle\|Import-Package\): .*\)$/\1/p' | while read -r h; do
	h=${h%$'\r'}  # the pre-FFM manifest may be CRLF; the line ending follows the current file
	if ! tr -d '\r' < "$M" | grep -q -F "$h"; then
		cr=""; [ "$(head -1 "$M" | tr -dc '\r' | wc -c)" -gt 0 ] && cr=$'\r'  # (MSYS grep cannot match a CR)
		# a manifest ends with a newline; the header goes before any trailing blank line
		awk -v BINMODE=3 -v h="$h" -v cr="$cr" '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] ~ /^\r?$/) n--
			for (i = 1; i <= n; i++) print l[i]; print h cr; for (i = n + 1; i <= NR; i++) print l[i] }' "$M" > "$M.fill.tmp"
		mv "$M.fill.tmp" "$M"; row manifest "$M"
	fi
done
