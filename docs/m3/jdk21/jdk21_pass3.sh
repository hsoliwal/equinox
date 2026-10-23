#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
# JDK21 multipass, pass three: template matching of the pass-two sites. Each site's line (and, for a lambda that
# opens its own line, the line before) is matched against TEMPLATES.tsv then CODE_MAPPING.tsv in order; the first
# hit names the enhancement target the site feeds (listener family learned from the interface it registers, or
# the M3 mapping). One awk process, file lines cached per file.
# Usage: jdk21_pass3.sh <worktree> <PASS2_MARKS.tsv> <TEMPLATES.tsv> <CODE_MAPPING.tsv> > PASS3_MARKS.tsv
set -euo pipefail
W="$1"; P2="$2"; T3="$3"; T4="$4"; export LC_ALL=C
awk -F'\t' -v OFS='\t' -v W="$W" '
	FILENAME != ARGV[ARGC - 1] { if (FNR > 1) { n++; id[n] = $1; re[n] = $2; tg[n] = $4 } next }
	FNR == 1 { print "path", "line", "bundle", "scope", "construct", "template", "enhance_target", "permalink"; next }
	{
		path = $1; ln = $2 + 0
		if (path != cached) { delete L; m = 0; f = W "/" path; while ((getline s < f) > 0) { sub(/\r$/, "", s); L[++m] = s }; close(f); cached = path }
		cur = L[ln]; prev = (ln > 1) ? L[ln - 1] : ""
		hid = "T00"; htg = "OTHER_CALLBACK"
		for (i = 1; i <= n; i++) {
			if (cur ~ re[i] || ($7 == "LAMBDA_PARAM" && cur ~ /^[ \t]*\(?unused/ && prev ~ re[i])) { hid = id[i]; htg = tg[i]; break }
		}
		print path, ln, $3, $4, $7, hid, htg, $9
	}' "$T3" "$T4" "$P2"
