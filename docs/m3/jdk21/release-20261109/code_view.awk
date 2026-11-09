# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
#
# Code view of a Java file (SFA): string and char literals, text blocks and comments become blanks, so a regex census
# over the view sees only code. Same lexer states as recipe/unnamed_to_named.awk. Line count and columns are kept.
# Usage: awk -v BINMODE=3 -f code_view.awk File.java
BEGIN { inBlock = 0; inText = 0 }
function blank(s) { gsub(/[^\r]/, " ", s); return s }
{
	line = $0; out = ""; n = length(line); i = 1
	while (i <= n) {
		c = substr(line, i, 1); c2 = substr(line, i, 2); c3 = substr(line, i, 3)
		if (inBlock) { if (c2 == "*/") { out = out "  "; i += 2; inBlock = 0 } else { out = out blank(c); i++ }; continue }
		if (inText) {
			if (c == "\\") { out = out blank(c2); i += 2; continue }
			if (c3 == "\"\"\"") { out = out "   "; i += 3; inText = 0 } else { out = out blank(c); i++ }
			continue
		}
		if (c2 == "//") { out = out blank(substr(line, i)); break }
		if (c2 == "/*") { out = out "  "; i += 2; inBlock = 1; continue }
		if (c3 == "\"\"\"") { out = out "   "; i += 3; inText = 1; continue }
		if (c == "\"" || c == "'") {
			q = c; out = out " "; i++
			while (i <= n) { d = substr(line, i, 1)
				if (d == "\\") { out = out blank(substr(line, i, 2)); i += 2; continue }
				out = out " "; i++; if (d == q) break }
			continue
		}
		out = out c; i++
	}
	printf "%s%s", out, RT
}
