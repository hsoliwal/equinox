# Pass 3 helper: for the line numbers in -v want="12,45,...", print "line<TAB>enclosing-method" using the nearest
# preceding method-like declaration (works for anonymous classes and lambdas' enclosing methods; approximate).
BEGIN { n = split(want, w, ","); for (i = 1; i <= n; i++) need[w[i]] = 1; m = "-" }
{
  line = $0
  if (line ~ /^[ \t]*((public|protected|private|static|final|synchronized|abstract|default|native)[ \t]+)*[A-Za-z_$][A-Za-z0-9_$<>,.? \[\]]*[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\(/ && line !~ /;[ \t]*$/ && line !~ /^[ \t]*(if|for|while|switch|catch|return|new|else|throw|do|try|synchronized[ \t]*\()/) {
    s = line; sub(/\(.*/, "", s); sub(/[ \t]+$/, "", s); k = split(s, t, /[ \t]+/); m = t[k]
  } else if (line ~ /^[ \t]*(public|protected|private)[ \t]+[A-Z][A-Za-z0-9_$]*[ \t]*\(/) {
    s = line; sub(/\(.*/, "", s); sub(/[ \t]+$/, "", s); k = split(s, t, /[ \t]+/); m = t[k]
  }
  if (NR in need) print NR "\t" m
}
