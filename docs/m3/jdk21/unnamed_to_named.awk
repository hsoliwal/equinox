# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# JDK21 text-lane recipe, Java pass: give every unnamed variable (`_`, Java 22+, JEP 456) a name so the source
# compiles with --release 21. Since Java 9 `_` is never an identifier, so every standalone `_` token in code is an
# unnamed variable or pattern: lambda parameters `_ ->` `(_, x) ->`, catch parameters, try resources `var _ =`,
# locals, `case T _` and record patterns `R(_, y)`. The k-th `_` of a line becomes `unused` (k = 1) or `unusedK`.
# Strings, char literals, text blocks and comments are masked (SFA): `"_"`, `'_'`, `@Contract("_ -> null")` and
# Javadoc examples stay byte for byte. Line endings stay as they are (the CR of a CRLF line is kept in $0).
# Fixed point: a second run changes nothing. A name collision (a nested lambda, an existing `unused`) shows up in
# the --release 21 compile gate and is renamed at that line by rename_at.awk.
# Usage: awk -f unnamed_to_named.awk File.java > File.java.new
BEGIN { inBlock = 0; inText = 0 }
function idch(c) { return c ~ /[A-Za-z0-9_$]/ || c > "\177" }
{
	line = $0; out = ""; n = length(line); i = 1; k = 0
	while (i <= n) {
		c = substr(line, i, 1); c2 = substr(line, i, 2); c3 = substr(line, i, 3)
		if (inBlock) {
			if (c2 == "*/") { out = out c2; i += 2; inBlock = 0 } else { out = out c; i++ }
			continue
		}
		if (inText) {
			if (c == "\\") { out = out c2; i += 2; continue }
			if (c3 == "\"\"\"") { out = out c3; i += 3; inText = 0 } else { out = out c; i++ }
			continue
		}
		if (c2 == "//") { out = out substr(line, i); break }
		if (c2 == "/*") { out = out c2; i += 2; inBlock = 1; continue }
		if (c3 == "\"\"\"") { out = out c3; i += 3; inText = 1; continue }
		if (c == "\"" || c == "'") {
			q = c; out = out c; i++
			while (i <= n) {
				d = substr(line, i, 1)
				if (d == "\\") { out = out substr(line, i, 2); i += 2; continue }
				out = out d; i++
				if (d == q) break
			}
			continue
		}
		# gawk's substr(s, 0, 1) is the first character, not "": column 1 has no predecessor
		if (c == "_" && (i == 1 || !idch(substr(line, i - 1, 1))) && (i == n || !idch(substr(line, i + 1, 1)))) {
			k++; out = out (k == 1 ? "unused" : "unused" k); i++
			# `var _= x` was written without a space before `=`; keep the spacing the author chose
			continue
		}
		out = out c; i++
	}
	# RT (gawk) is the exact terminator read: a last line without a newline stays without one
	printf "%s%s", out, RT
}
