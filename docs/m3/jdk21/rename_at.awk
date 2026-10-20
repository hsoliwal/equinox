# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 text-lane recipe, collision pass: javac --release 21 reports "variable unusedK is already defined" where a
# name given by unnamed_to_named.awk shadows an enclosing one (nested lambdas, an existing `unused`). The renamed
# variables were unnamed, so nothing refers to them: renaming the declaration at the reported line is safe.
# Usage: awk -v BINMODE=3 -v LINE=<n> -v NAME=<unusedK> -f rename_at.awk File.java > File.java.new
# The first standalone NAME in code on line LINE becomes the smallest `unusedN` (N >= 2) that the file does not
# contain anywhere. Strings, char literals and comments on that line are masked. Every other byte is unchanged.
function idch(c) { return c ~ /[A-Za-z0-9_$]/ || c > "\177" }
FNR == NR { # pass 1: collect the unusedN names already in the file
	t = $0
	while (match(t, /unused[0-9]*/)) { seen[substr(t, RSTART, RLENGTH)] = 1; t = substr(t, RSTART + RLENGTH) }
	next
}
FNR == 1 { for (k = 2; ("unused" k) in seen; k++); FRESH = "unused" k }
FNR != LINE { printf "%s%s", $0, RT; next }
{
	line = $0; n = length(line); L = length(NAME); i = 1; out = ""; done = 0
	while (i <= n) {
		c = substr(line, i, 1)
		if (!done && substr(line, i, 2) == "//") { out = out substr(line, i); i = n + 1; break }
		if (!done && (c == "\"" || c == "'")) {
			q = c; out = out c; i++
			while (i <= n) { d = substr(line, i, 1); if (d == "\\") { out = out substr(line, i, 2); i += 2; continue }
				out = out d; i++; if (d == q) break }
			continue
		}
		if (!done && substr(line, i, L) == NAME && (i == 1 || !idch(substr(line, i - 1, 1))) && !idch(substr(line, i + L, 1))) {
			out = out FRESH; i += L; done = 1; continue
		}
		out = out c; i++
	}
	if (!done) { print "rename_at: " NAME " not found at line " LINE > "/dev/stderr"; exit_code = 1 }
	printf "%s%s", out, RT
}
END { exit exit_code }
