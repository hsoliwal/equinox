#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# Parse gate (BLLSE) over every tracked Java source of a fork, test bundles included, test-input folders excluded:
# JDK 25 javac --release 21, stop after parsing (no classpath needed). Upstream sources parse, so every row here is a
# Java 22+ construct or a fork-made syntax break (for example an anchor after an opening text-block delimiter).
# Usage: parse_gate.sh <repo> [tag]   -> F:/m3-scratch/rel21/gate/<repo>.parse<tag>.tsv (path TAB line TAB message)
set -euo pipefail
R="$1"; TAG="${2:-}"; W=F:/m3-scratch/rel21/forks/$R; O=F:/m3-scratch/rel21/gate/$R.parse$TAG
JAVAC="${JAVAC:-F:/m3-scratch/jdks/jdk-25.0.4.1+1/bin/javac}"; export LC_ALL=C
git -C "$W" ls-files -- '*.java' ':(exclude)*/testresources/*' ':(exclude)*/testResources/*' ':(exclude)*/resources/*' \
	':(exclude)*/workspace/*' ':(exclude)*/test-data/*' ':(exclude)*/testdata/*' ':(exclude)*/testData/*' ':(exclude)*/testfiles/*' \
	':(exclude)*/test-resources/*' ':(exclude)*/testsrc/*' ':(exclude)*/testcases/*' ':(exclude)*/workspaces/*' \
	':(exclude)*/preview/*' ':(exclude)*/converterJclMin*' ':(exclude)*/JCL/*' ':(exclude)*/compliance/*' ':(exclude)docs/*' \
	| sed "s|^|\"$W/|; s|$|\"|" > "$O.sources"
"$JAVAC" -J-Xmx6g --release 21 -encoding UTF-8 -proc:none -nowarn -Xmaxerrs 1000000 -Xmaxwarns 0 -implicit:none \
	-XDshould-stop.ifError=PARSE -XDshould-stop.ifNoError=PARSE -d "F:/m3-scratch/tmp/parse-$R" @"$O.sources" > "$O.log" 2>&1 || true
WN=$(cygpath -w "$W" | tr '\\' '/')
{ grep -a -E '^[A-Za-z]:[^:]*\.java:[0-9]+: error: ' "$O.log" || true; } | tr '\\' '/' | sed "s|^$W/||; s|^$WN/||" \
	| sed -E 's/^(.*\.java):([0-9]+): error: (.*)$/\1\t\2\t\3/' | tr -d '\r' | sort -u > "$O.tsv"
echo "$R parse$TAG --release 21: $(wc -l < "$O.sources") files, $(wc -l < "$O.tsv") syntax errors in $(cut -f1 "$O.tsv" | sort -u | wc -l) files"
