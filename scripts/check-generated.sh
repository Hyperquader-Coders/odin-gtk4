#!/usr/bin/env bash
# Fails when one of runic's three known faults is back in the generated output (make lint runs it).
#
#  1. A trailing `va_list` is dropped and the procedure is marked `#c_vararg ..any`: a wrong
#     call. No generated procedure may be `#c_vararg` and bind a C name matching `valist_re`,
#     and none of the names in `removed` (the procedures scripts/postprocess.sh deletes) may
#     be bound at all.
#  2. A pointer parameter whose C name ends in "s" is written `[^]T` whatever its length. The
#     `proc, parameter` lines of scripts/single-object-params.*.txt are the parameters the C
#     headers pass as one `T *`; each must be `^T`, never `[^]`.
#  3. An out-parameter `T **` that returns one pointer is written `[^]^T`. The same lists
#     name those parameters too (`^^T`, or `^cstring` for `char **`), checked the same way,
#     plus the anonymous GtkIMContextClass.get_preedit_string callback type, which a list
#     cannot name (`callback_re`).
#  runic generates with `parameters: declared` (rune.yml), which makes every procedure parameter
#  a single object unless the package's `to.detect.arrays` lists it. This script keeps that
#  true: a procedure parameter typed `[^]` or `[^]^T` must be listed in rune.yml, and one the
#  lists above name must not be.
set -euo pipefail

cd "$(dirname "$0")/.."

generated=(gtk4/gtk4.odin)
lists=(scripts/single-object-params.*.txt)

valist_re='_valist|_va_list|_va$|vprintf|vsnprintf|vsprintf|vasprintf|_vfprintf|_logv|_vscanf'

# Anonymous callback types whose parameters are one pointer each; postprocess.sh rewrites them.
callback_re='attrs: \[\^\]\^pango\.AttrList'

# C names of the procedures removed from the output.
removed='gdk_clipboard_set_valist gsk_gl_shader_format_args_va gtk_cell_area_cell_get_valist gtk_cell_area_cell_set_valist gtk_list_store_set_valist gtk_media_stream_error_valist gtk_tree_model_get_valist gtk_tree_store_set_valist'

fail=0
for f in "${generated[@]}"; do
    [ -f "$f" ] || { echo "check-generated: $f not found" >&2; exit 2; }
    out=$(VALIST_RE="$valist_re" REMOVED="$removed" perl -ne '
        BEGIN { %gone = map { $_ => 1 } split " ", $ENV{REMOVED}; }
        if (/link_name = "(\w+)"/) { $link = $1; next }
        if (/^\s+(\w+) :: proc\(/) {
            my $name = $link // $1; undef $link;
            print "$ARGV:$.: $name is bound but was removed\n" if $gone{$name};
            print "$ARGV:$.: $name is #c_vararg and matches the va_list pattern\n"
                if /#c_vararg/ && $name =~ /$ENV{VALIST_RE}/;
        }
    ' "$f")
    if [ -n "$out" ]; then echo "$out"; fail=1; fi
done

for f in "${generated[@]}"; do
    out=$(grep -nE "#type proc \"c\".*$callback_re" "$f" | sed "s|^|$f:|; s|\$| is [^]^T, want ^^T|" || true)
    if [ -n "$out" ]; then echo "$out"; fail=1; fi
done

for list in "${lists[@]}"; do
    [ -f "$list" ] || continue
    pkg=${list#scripts/single-object-params.}
    pkg=${pkg%.txt}
    f=""
    for g in "${generated[@]}"; do [ "$(basename "$g" .odin)" = "$pkg" ] && f=$g; done
    [ -n "$f" ] || { echo "check-generated: no generated file for $list" >&2; exit 2; }
    out=$(LIST=$list perl -ne '
        BEGIN {
            open my $fh, "<", $ENV{LIST} or die "$ENV{LIST}: $!\n";
            while (<$fh>) { chomp; next if /^\s*(#|$)/; my ($p, $a) = split /,\s*/; $want{$p}{$a} = 1; $todo{"$p, $a"} = 1; }
        }
        if (/^\s+(\w+) :: proc\((.*)\)/ && $want{$1}) {
            my ($name, $args) = ($1, $2);
            for my $a (keys %{ $want{$name} }) {
                next unless $args =~ /\b\Q$a\E: (\S[^,]*)/;
                my $type = $1;
                delete $todo{"$name, $a"};
                print "$ARGV:$.: $name, $a is $type, want a single ^T\n" if $type =~ /^\[\^\]/;
            }
        }
        END { print "$ARGV: listed but not found: $_\n" for sort keys %todo; }
    ' "$f")
    if [ -n "$out" ]; then echo "$out"; fail=1; fi
done

# Every `[^]` procedure parameter must be declared in the package's rune.yml `arrays:`.
for f in "${generated[@]}"; do
    yml="$(dirname "$f")/rune.yml"
    out=$(YML=$yml perl -ne '
        BEGIN {
            open my $fh, "<", $ENV{YML} or die "$ENV{YML}: $!\n";
            my $in;
            while (<$fh>) {
                if (/^    arrays:/) { $in = 1; next }
                if ($in && /^      (\w+): \[(.*)\]\s*$/) { my ($pn, $pl) = ($1, $2); $ok{"$pn, $_"} = 1 for split /,\s*/, $pl; next }
                $in = 0;
            }
        }
        if (/^\s+(\w+) :: proc\((.*)/) {
            my ($name, $rest) = ($1, $2);
            my ($d, $args) = (1, "");
            for my $c (split //, $rest) { $d++ if $c eq "("; $d-- if $c eq ")"; last if $d == 0; $args .= $c }
            ($d, my $cur, my @p) = (0, "");
            for my $c (split //, $args) {
                $d++ if $c =~ /[(\[]/; $d-- if $c =~ /[)\]]/;
                if ($c eq "," && $d == 0) { push @p, $cur; $cur = "" } else { $cur .= $c }
            }
            push @p, $cur if length $cur;
            for (@p) {
                s/^\s+//;
                next unless /^(\w+):\s*(.*)/;
                my ($pn, $pt) = ($1, $2);
                print "$ARGV:$.: $name, $pn is $pt, but rune.yml arrays does not list it\n" if $pt =~ /\[\^\]/ && !$ok{"$name, $pn"};
            }
        }
    ' "$f")
    if [ -n "$out" ]; then echo "$out"; fail=1; fi
done

if [ "$fail" -ne 0 ]; then
    echo "check-generated: a generated file has a fault: check rune.yml (parameters: declared, arrays:) and scripts/postprocess.sh" >&2
    exit 1
fi
echo "check-generated OK"
