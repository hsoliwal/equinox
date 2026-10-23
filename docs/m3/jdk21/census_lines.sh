#!/usr/bin/env bash
# JDK21 census, pass 1: every line in a fork's main Java sources that uses a Java 22+ language construct.
# Usage: census_lines.sh <bare-repo.git> <rev> > lines.tsv   (columns: repo kind path line text)
# Test sources are excluded: they carry Java 22+ code inside string literals as compiler test data.
set -euo pipefail
G="$1"; REV="${2:-HEAD}"; R=$(basename "$G" .git)
EXCL=(':(exclude)*/tests/*' ':(exclude)*/test/*' ':(exclude)*/testresources/*' ':(exclude)*/workspace/*'
      ':(exclude)*.tests.*/*' ':(exclude)*/test-data/*' ':(exclude)*/resources/*' ':(exclude)*/testdata/*')
q() { GIT_NO_LAZY_FETCH=1 git -C "$G" grep -n -I -P -e "$2" "$REV" -- '*.java' "${EXCL[@]}" 2>/dev/null \
      | awk -v r="$R" -v k="$1" -v rev="$REV:" 'BEGIN{OFS="\t"} {sub("^" rev, ""); p=index($0,":"); f=substr($0,1,p-1);
          rest=substr($0,p+1); p2=index(rest,":"); n=substr(rest,1,p2-1); t=substr(rest,p2+1); gsub(/\t/," ",t);
          print r,k,f,n,t}' || true; }
# unnamed lambda parameter: `_ ->`, `(_) ->`, `(_, x) ->`, `(x, _) ->`
q unnamed_lambda '(?:^|[(,\s])_\s*(?:\)\s*)?->|\(\s*_\s*,|,\s*_\s*\)\s*->'
# unnamed catch parameter / local / for variable: `Type _)` `Type _ =` `Type _ :`
q unnamed_decl '[\w>\]]\s+_\s*(?:\)|=[^=]|:)'
# unnamed pattern in record deconstruction or type pattern: `(_)` `, _)` `case X _` `instanceof X _`
q unnamed_pattern '(?:case|instanceof)\b[^;{]*(?<![\w$])_(?![\w$])'
# module import declarations (Java 25)
q import_module '^\s*import\s+module\s'
