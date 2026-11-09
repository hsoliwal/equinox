#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# Writes the release-readiness evidence of one fork into its clone (CPU only, from the gate outputs):
#   docs/m3/jdk21/release-20261109/{BUNDLES.txt,CENSUS.tsv,RECIPE_CHANGES.tsv,GATE_RESIDUE.tsv,GATE_SUMMARY.tsv,META.tsv,
#                                   gate_master.sh,compile_gate.sh,meta_check.sh,readiness.sh}
#   docs/m3/release/RELEASE_READINESS.md
# Usage: readiness.sh <repo> <master-sha> [extra-notes-file]
set -euo pipefail
R="$1"; MSHA="$2"; NOTES="${3:-}"; W=F:/m3-scratch/rel21/forks/$R; G=F:/m3-scratch/rel21/gate/$R; T=F:/m3-scratch/rel21/tools
E=docs/m3/jdk21/release-20261109; mkdir -p "$W/$E" "$W/docs/m3/release"
cp "$G.bundles" "$W/$E/BUNDLES.txt"; cp "$G.census.tsv" "$W/$E/CENSUS.tsv"; cp "$G.recipe.tsv" "$W/$E/RECIPE_CHANGES.tsv"
cp "$G.residue.tsv" "$W/$E/GATE_RESIDUE.tsv"; cp "$G.meta.tsv" "$W/$E/META.tsv"
[ -f "$G.residue.master.tsv" ] && cp "$G.residue.master.tsv" "$W/$E/GATE_RESIDUE_MASTER.tsv"
[ -f "$G.fill.tsv" ] && cp "$G.fill.tsv" "$W/$E/FILL_CHANGES.tsv"
[ -f "$G.parse.tsv" ] && cp "$G.parse.tsv" "$W/$E/PARSE_GATE.tsv"
[ -f "$G.parse.master.tsv" ] && cp "$G.parse.master.tsv" "$W/$E/PARSE_GATE_MASTER.tsv"
[ -s "$G.census.exempt.tsv" ] && cp "$G.census.exempt.tsv" "$W/$E/CENSUS_EXEMPT.tsv" && cp "$T/exempt-$R.tsv" "$W/$E/EXEMPT.tsv"
[ -s "$G.census.masked.tsv" ] && cp "$G.census.masked.tsv" "$W/$E/CENSUS_MASKED.tsv"  # regex hits inside strings/comments
cp "$T/gate_master.sh" "$T/compile_gate.sh" "$T/meta_check.sh" "$T/readiness.sh" "$W/$E/"
n() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
c() { awk -F'\t' -v k="$1" '$1==k' "$G.census.tsv" | wc -l | tr -d ' '; }
files=$(n "$G.jdk21.sources"); roots=$(n "$G.jdk21.roots"); b25=$(n "$G.base25.tsv"); j21=$(n "$G.jdk21.tsv")
res=$(n "$G.residue.tsv"); resm=$(if [ -f "$G.residue.master.tsv" ]; then n "$G.residue.master.tsv"; else echo "$res"; fi); rec=$(n "$G.recipe.tsv"); meta=$(n "$G.meta.tsv"); bun=$(n "$G.bundles")
pf=$(n "$G.parse.sources"); pe=$(n "$G.parse.tsv"); pem=$(if [ -f "$G.parse.master.tsv" ]; then n "$G.parse.master.tsv"; else echo "$pe"; fi); ex=$(n "$G.census.exempt.tsv")
bree=$(c bree); pin=$(c pin); un=$(( $(c unnamed_lambda) + $(c unnamed_decl) + $(c unnamed_pattern) )); im=$(c import_module)
printf 'metric\tvalue\nmaster\t%s\nupstream_master\t%s\ngated_bundles\t%s\nfiles\t%s\nroots\t%s\nbase25_errors\t%s\njdk21_errors\t%s\nresidue\t%s\nrecipe_files_changed\t%s\nmeta_rows\t%s\ncensus_bree\t%s\ncensus_pins\t%s\ncensus_unnamed\t%s\ncensus_import_module\t%s\n' \
	"$MSHA" "$(git -C "$W" rev-parse upstream/master)" "$bun" "$files" "$roots" "$b25" "$j21" "$res" "$rec" "$meta" "$bree" "$pin" "$un" "$im" > "$W/$E/GATE_SUMMARY.tsv"
v() { if [ "$1" = 0 ]; then echo PASS; else echo "$2"; fi; }
g1=$( [ $((bree + pin + un + im)) = 0 ] && echo PASS || echo "FAIL on master (fixed by RECIPE_CHANGES.tsv in this PR: $rec files)")
[ "$ex" = 0 ] || g1="$g1; $ex exempt rows (EXEMPT.tsv, CENSUS_EXEMPT.tsv)"
{
cat <<EOF
# Release readiness for M3JDK21 (Java 21): $R

Measured on 2026-11-09 against fork master \`$MSHA\` (upstream master \`$(git -C "$W" rev-parse --short=12 upstream/master)\`).
Tools and raw evidence: [\`$E\`](../jdk21/release-20261109/). Every gate ran locally on CPU; fork CI runs are not counted
(startup failures and queue starvation on this account, 2026-11).

| # | Gate | Verdict | Evidence |
| --- | --- | --- | --- |
| G1 | No Java 22+ requirement on master: BREE above JavaSE-21 ($bree), build/IDE pins above 21 ($pin), unnamed \`_\` ($un), \`import module\` ($im) | $g1 | CENSUS.tsv (code view; hits inside strings, text blocks and comments: CENSUS_MASKED.tsv) |
| G2 | Java-21 compile gate: JDK 25 javac \`--release 21\` minus \`--release 25\` over $bun bundles ($files files, $roots roots); $b25 baseline rows cancel | $(if [ "$resm" = "$res" ]; then v "$res" "FAIL"; else echo "FAIL on master (residue $resm, GATE_RESIDUE_MASTER.tsv); $(v "$res" FAIL) with this PR"; fi) (residue $res) | GATE_RESIDUE.tsv, GATE_SUMMARY.tsv |
| G2b | Parse gate: every tracked Java source ($pf files, test bundles included, test-input folders excluded), JDK 25 javac \`--release 21\` stopped after parsing | $(if [ "$pem" = "$pe" ]; then v "$pe" "FAIL: $pe rows"; else echo "FAIL on master ($pem rows, PARSE_GATE_MASTER.tsv); $(v "$pe" FAIL) with this PR"; fi) | PARSE_GATE.tsv |
| G3 | Recipe fixed point (\`apply_jdk21.sh\` + \`apply_jdk21_pins.sh\` change nothing on master) | $(v "$rec" "FIXED in this PR ($rec files)") | RECIPE_CHANGES.tsv |
| G4 | Metadata consistent: Tycho bundle/feature versions match their pom, no EE above 21 in a Java-21 bundle | $(v "$meta" "FAIL: $meta rows") | META.tsv |
| G5 | Full Tycho build of this repository on JDK 21 | PENDING | not run locally (disk and time budget); the javac gate G2 covers language level and API |
| G6 | Eclipse SDK product build and launch on JDK 21 | PENDING | aggregator verdict, eclipse.platform.releng.aggregator docs/m3/release/RELEASE_READINESS.md |
EOF
[ -n "$NOTES" ] && [ -f "$NOTES" ] && { echo; cat "$NOTES"; }
cat <<EOF

## Re-run

\`\`\`bash
git clone --depth 1 https://github.com/hsoliwal/$R.git && git -C $R remote add upstream <upstream>
git -C $R fetch --depth 1 --filter=blob:none upstream master:refs/remotes/upstream/master
bash $E/gate_master.sh $R    # paths at the top of the script; JAVAC = JDK 25 javac
bash $E/meta_check.sh $R > META.tsv
\`\`\`

The gate compiles every bundle that upstream master declares JavaSE-22 or newer, plus the 2026-10-20 list, against the
newest jar of every bundle in a p2 pool. Errors in both runs are classpath noise (APIs newer than the pool); what remains
after \`--release 21\` is the Java 22+ residue and must be empty.
EOF
} > "$W/docs/m3/release/RELEASE_READINESS.md"
echo "$R readiness: G1=$g1 G2=residue $res G3=recipe $rec G4=meta $meta"
