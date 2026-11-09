#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# G5: full Tycho build of one fork clone on JDK 21 (tests skipped: the fork's GitHub CI runs no Maven build),
# shared local repository F:/m3-scratch/m2-eclipse, Maven Central asked first (settings-central-first.xml), nothing written to C:. BLLSE: [ERROR] rows -> <repo>.errors.tsv.
# Refuses to start below MIN_FREE_GB free on F: (HOLD). Removes the fork's target/ directories afterwards.
# Usage: build_fork.sh <repo> [extra mvn args...]   -> F:/m3-scratch/rel21/build/<repo>.{log,errors.tsv,result.tsv}
set -uo pipefail
R="$1"; shift; W=F:/m3-scratch/rel21/forks/$R; B=F:/m3-scratch/rel21/build; mkdir -p "$B"
MIN_FREE_GB=${MIN_FREE_GB:-3}; M2=F:/m3-scratch/m2-eclipse
free_gb() { df -BG /f | awk 'NR==2 { sub(/G/, "", $4); print $4 }'; }
f0=$(free_gb)
if [ "$f0" -lt "$MIN_FREE_GB" ]; then
	printf 'repo\tstatus\trc\tseconds\tmodules\tsuccess\tfailure\terror_rows\tfree_before_gb\tfree_after_gb\n%s\tHOLD\t-\t0\t0\t0\t0\t0\t%s\t%s\n' \
		"$R" "$f0" "$f0" | tee "$B/$R.result.tsv"; echo "$R HOLD: F: free $f0 GB < $MIN_FREE_GB GB"; exit 2; fi
export JAVA_HOME="C:/Program Files/Java/jdk-21" TEMP=F:/m3-scratch/tmp TMP=F:/m3-scratch/tmp
export PATH="$(cygpath -u "$JAVA_HOME")/bin:$PATH" MAVEN_OPTS="-Xmx4g -Djava.io.tmpdir=F:/m3-scratch/tmp"
MVN=C:/ProgramData/chocolatey/lib/maven/apache-maven-3.9.14/bin/mvn
t0=$(date +%s); echo "$(date +%T) $R build start (F: free ${f0} GB, $(java -version 2>&1 | head -1))"
( cd "$W" && "$MVN" -B -s F:/m3-scratch/rel21/tools/settings-central-first.xml clean verify -DskipTests -Dmaven.repo.local="$M2" -Djava.io.tmpdir=F:/m3-scratch/tmp "$@" ) > "$B/$R.log" 2>&1
rc=$?; t1=$(date +%s); f1=$(free_gb)
grep -a -E '^\[ERROR\]' "$B/$R.log" | sed -E 's/^\[ERROR\] *//' | tr -d '\r' | awk '!seen[$0]++' > "$B/$R.errors.tsv"
st=$(grep -a -o -E 'BUILD (SUCCESS|FAILURE)' "$B/$R.log" | tail -1)
mods=$(grep -a -c -E '^\[INFO\] .* (SUCCESS|FAILURE|SKIPPED) \[' "$B/$R.log")
ok=$(grep -a -c -E '^\[INFO\] .* SUCCESS \[' "$B/$R.log"); bad=$(grep -a -c -E '^\[INFO\] .* FAILURE \[' "$B/$R.log")
printf 'repo\tstatus\trc\tseconds\tmodules\tsuccess\tfailure\terror_rows\tfree_before_gb\tfree_after_gb\n%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
	"$R" "${st:-NO_RESULT}" "$rc" "$((t1 - t0))" "$mods" "$ok" "$bad" "$(wc -l < "$B/$R.errors.tsv")" "$f0" "$f1" > "$B/$R.result.tsv"
gzip -c "$B/$R.log" > "$B/$R.log.gz"
# build outputs only: untracked target/ directories next to a pom or a pomless bundle
git -C "$W" ls-files --others --ignored --exclude-standard --directory 2>/dev/null | grep -E '(^|/)target/$' | while read -r d; do rm -rf "${W:?}/$d"; done
echo "$(date +%T) $R build ${st:-NO_RESULT} rc=$rc in $((t1 - t0)) s; F: free $f0 -> $f1 GB (after cleanup $(free_gb) GB)"
