#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# Metadata consistency gate of one fork (CPU only, tracked files of HEAD):
#   version  (Tycho packaging only) MANIFEST.MF Bundle-Version X.Y.Z(.qualifier) == sibling pom.xml project version X.Y.Z(-SNAPSHOT)
#            feature.xml version                          == sibling pom.xml project version
#   bree     no Bundle-RequiredExecutionEnvironment above JavaSE-21
#   ee       .classpath JRE container / jdt prefs compliance / build.properties profile above 21 in a bundle
#            whose BREE is JavaSE-21 or lower
# Usage: meta_check.sh <worktree> > rows.tsv   (kind TAB path TAB expected TAB actual); empty output = PASS
set -uo pipefail
W="$1"; export LC_ALL=C
pomver() { # project version of a pom (the first <version> outside <parent>)
	awk -v BINMODE=3 '{ gsub(/\r/,"") } /<parent>/{p=1} /<\/parent>/{p=0; next} !p && /<version>/ && !done {
		s=$0; sub(/.*<version>/,"",s); sub(/<\/version>.*/,"",s); print s; done=1 }
		/<(dependencies|build|properties|modules|profiles)>/{ exit }' "$1"; }
tycho() { grep -q -E '<packaging>eclipse-(plugin|test-plugin|feature)</packaging>' "$1"; } # only Tycho checks these
git -C "$W" ls-files -- '*META-INF/MANIFEST.MF' | while read -r m; do
	d=${m%META-INF/MANIFEST.MF}; d=${d%/}; f="$W/$m"
	bv=$(tr -d '\r' < "$f" | sed -n 's/^Bundle-Version:[ \t]*//p' | head -1)
	ee=$(tr -d '\r' < "$f" | sed -n 's/^Bundle-RequiredExecutionEnvironment:.*JavaSE-\([0-9]*\).*/\1/p' | head -1)
	if [ -n "$ee" ] && [ "$ee" -gt 21 ]; then printf 'bree\t%s\t<=21\t%s\n' "$m" "$ee"; fi
	if [ -f "$W/${d:+$d/}pom.xml" ] && tycho "$W/${d:+$d/}pom.xml"; then pv=$(pomver "$W/${d:+$d/}pom.xml")
		if [ -n "$pv" ] && [ -n "$bv" ] && [ "${pv%-SNAPSHOT}" != "${bv%.qualifier}" ]; then
			printf 'version\t%s\t%s\t%s\n' "${d:+$d/}pom.xml" "$bv" "$pv"; fi; fi
	if [ -z "$ee" ] || [ "$ee" -le 21 ]; then
		c="$W/${d:+$d/}.classpath"; p="$W/${d:+$d/}.settings/org.eclipse.jdt.core.prefs"; b="$W/${d:+$d/}build.properties"
		[ -f "$c" ] && grep -q -E 'JRE_CONTAINER.*JavaSE-2[2-9]' "$c" && printf 'ee\t%s\t<=21\tclasspath\n' "${d:+$d/}.classpath"
		[ -f "$p" ] && grep -q -E 'compiler\.(compliance|source|codegen\.targetPlatform)=2[2-9]' "$p" && printf 'ee\t%s\t<=21\tprefs\n' "${d:+$d/}.settings/org.eclipse.jdt.core.prefs"
		[ -f "$b" ] && grep -q -E 'jre\.compilation\.profile[ \t]*=[ \t]*JavaSE-2[2-9]' "$b" && printf 'ee\t%s\t<=21\tbuild.properties\n' "${d:+$d/}build.properties"
	fi
done
git -C "$W" ls-files -- '*feature.xml' | while read -r x; do
	d=$(dirname "$x"); [ -f "$W/$d/pom.xml" ] && tycho "$W/$d/pom.xml" || continue
	fv=$(tr -d '\r' < "$W/$x" | tr '\n' ' ' | sed -n 's/.*<feature[^>]*[ \t]version="\([^"]*\)".*/\1/p')
	pv=$(pomver "$W/$d/pom.xml")
	if [ -n "$pv" ] && [ -n "$fv" ] && [ "${pv%-SNAPSHOT}" != "${fv%.qualifier}" ]; then
		printf 'version\t%s\t%s\t%s\n' "$d/pom.xml" "$fv" "$pv"; fi
done
exit 0
