#!/usr/bin/env bash
# Copyright (c) 2026 Synexia, Hitesh Soliwal (hsoliwal@gmail.com) and others.
# SPDX-License-Identifier: Apache-2.0 OR EPL-2.0
# Self-test of the JDK21 text-lane recipe: expected rewrites, untouched literals/comments, byte-exact line endings,
# fixed point, and the metadata steps. Usage: test/test_recipe.sh   (exit 0 = all cases pass)
set -euo pipefail
RD=$(cd "$(dirname "$0")/../recipe" 2>/dev/null && pwd || true); [ -f "$RD/unnamed_to_named.awk" ] || RD=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; FAIL=0
AWK() { awk -v BINMODE=3 -f "$RD/unnamed_to_named.awk"; }
check() { # check <name> <input> <expected>
	local got; got=$(printf '%b' "$2" | AWK | od -An -c | tr -s ' \n' ' ')
	local want; want=$(printf '%b' "$3" | od -An -c | tr -s ' \n' ' ')
	if [ "$got" = "$want" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "  got:  $got"; echo "  want: $want"; FAIL=1; fi
}
check lambda            'f(_ -> 1);\n'                         'f(unused -> 1);\n'
check lambda-parens     'f((_) -> 1);\n'                       'f((unused) -> 1);\n'
check two-params        'm.forEach((_, v) -> v.run());\n'     'm.forEach((unused, v) -> v.run());\n'
check two-unnamed       'BiConsumer<A,B> c = (_, _) -> {};\n' 'BiConsumer<A,B> c = (unused, unused2) -> {};\n'
check typed-lambda      'l((SelectionChangedEvent _) -> x());\n' 'l((SelectionChangedEvent unused) -> x());\n'
check catch             '} catch (IOException _) {\n'         '} catch (IOException unused) {\n'
check try-var           'try (var _= open()) {\n'              'try (var unused= open()) {\n'
check try-typed         'try (OutputStream _ = out) {\n'       'try (OutputStream unused = out) {\n'
check case-type         'case BooleanLiteral _ -> {}\n'       'case BooleanLiteral unused -> {}\n'
check record-pattern    'case R(_, long l) -> {}\n'           'case R(unused, long l) -> {}\n'
check column-1          '_ -> x\n'                             'unused -> x\n'
check string-kept       's = "_ -> x"; f(_ -> 1);\n'          's = "_ -> x"; f(unused -> 1);\n'
check char-kept         "case '_': f(_ -> 1);\n"              "case '_': f(unused -> 1);\n"
check escaped-quote     's = "\\"_"; t(_ -> 0);\n'            's = "\\"_"; t(unused -> 0);\n'
check line-comment      'f(_ -> 1); // _ -> x\n'              'f(unused -> 1); // _ -> x\n'
check block-comment     '/* _ -> x */ f(_ -> 1);\n'           '/* _ -> x */ f(unused -> 1);\n'
check javadoc-lines     '/**\n * case R(_, _) -> {}\n */\n'   '/**\n * case R(_, _) -> {}\n */\n'
check text-block        's = """\n  _ -> x\n  """; f(_ -> 1);\n' 's = """\n  _ -> x\n  """; f(unused -> 1);\n'
check annotation-string '@Contract("null, _ -> null")\n'      '@Contract("null, _ -> null")\n'
check identifiers       'int MAX_V = a_ + _b + __ + $_ + _$;\n' 'int MAX_V = a_ + _b + __ + $_ + _$;\n'
check crlf              'f(_ -> 1);\r\ng();\r\n'               'f(unused -> 1);\r\ng();\r\n'
check no-final-newline  'f(_ -> 1);'                           'f(unused -> 1);'
check fixed-point       'f(unused -> 1, (unused, unused2) -> 2);\n' 'f(unused -> 1, (unused, unused2) -> 2);\n'
# driver: metadata steps, CR bytes kept, second run prints nothing
mkdir -p "$T/b/META-INF" "$T/b/.settings" "$T/b/src"
printf 'Bundle-RequiredExecutionEnvironment: JavaSE-25\r\nBundle-Version: 1.0.0\r\n' > "$T/b/META-INF/MANIFEST.MF"
printf '<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-25"/>\n' > "$T/b/.classpath"
printf 'org.eclipse.jdt.core.compiler.compliance=25\norg.eclipse.jdt.core.compiler.source=25\norg.eclipse.jdt.core.compiler.codegen.targetPlatform=25\n' > "$T/b/.settings/org.eclipse.jdt.core.prefs"
printf 'jre.compilation.profile = JavaSE-25\n' > "$T/b/build.properties"
printf 'class A { void f() { g(_ -> 1); } }\r\n' > "$T/b/src/A.java"
printf 'class B { int MAX_V = 1; }\n' > "$T/b/src/B.java"
echo b > "$T/list"
first=$(bash "$RD/apply_jdk21.sh" "$T" "$T/list" | cut -f1 | sort | tr '\n' ' ')
second=$(bash "$RD/apply_jdk21.sh" "$T" "$T/list" | wc -l)
[ "$first" = "buildprops classpath java manifest prefs " ] && echo "PASS driver-steps" || { echo "FAIL driver-steps: $first"; FAIL=1; }
[ "$second" -eq 0 ] && echo "PASS driver-fixed-point" || { echo "FAIL driver-fixed-point: $second rows"; FAIL=1; }
[ "$(tr -cd '\r' < "$T/b/META-INF/MANIFEST.MF" | wc -c)" -eq 2 ] && [ "$(tr -cd '\r' < "$T/b/src/A.java" | wc -c)" -eq 1 ] \
	&& echo "PASS driver-crlf" || { echo "FAIL driver-crlf"; FAIL=1; }
grep -q 'JavaSE-21' "$T/b/META-INF/MANIFEST.MF" && grep -q 'compliance=21' "$T/b/.settings/org.eclipse.jdt.core.prefs" \
	&& echo "PASS driver-values" || { echo "FAIL driver-values"; FAIL=1; }
exit $FAIL
