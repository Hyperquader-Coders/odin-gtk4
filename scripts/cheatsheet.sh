#!/bin/sh
# Fails when docs/CHEATSHEET.md names a procedure, type or constant that the API.md of its
# package does not declare: the sheet is a reading of the API, and a rename there must reach it.
# Canonical: the same bytes in every binding (amber-house scripts/binding/cheatsheet.sh, copied
# by scripts/binding-sync). Everything that differs between repos is in scripts/api.conf.
# Usage: scripts/cheatsheet.sh [API.md] [CHEATSHEET.md]
# ALIASES (api.conf) are the import aliases the sheet writes, "alias=package" ("jsc" is package
# javascriptcore); a package without one is written as itself. EXTERNAL_ALIASES and EXTERNAL_API
# do the same for another binding's API.md (gtk4's sheet names glib, gobj and gio), skipped with a
# note when that file is absent.
set -eu
export LC_ALL=C
dir=$(dirname "$0")
PACKAGES='' ALIASES='' EXTERNAL_ALIASES='' EXTERNAL_API=''
# shellcheck source=/dev/null
. "$dir/api.conf"
api=${1:-docs/API.md}
sheet=${2:-docs/CHEATSHEET.md}
if [ -z "$ALIASES" ]; then
	for p in $PACKAGES; do ALIASES="$ALIASES $p=$p"; done
fi
# "alias name" for every declaration in an API.md: a package header "## collection:pkg" (or
# "## pkg"), then each "\t\tname :: ", "\t\tname := " or "\t\tname: " line under it. A package
# with no alias is not on the sheet.
decls_of() {
	awk -v aliases="$2" '
		BEGIN { n = split(aliases, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); alias[kv[2]] = kv[1] } }
		/^## / { pkg = $2; sub(/^.*:/, "", pkg); pkg = alias[pkg]; next }
		/^\t\t[A-Za-z_][A-Za-z0-9_]*( :?:|:)/ { sub(/^\t\t/, ""); sub(/:$/, "", $1); print pkg " " $1 }
	' "$1"
}
decls=$(decls_of "$api" "$ALIASES")
all=$ALIASES
if [ -n "$EXTERNAL_ALIASES" ]; then
	all="$all $EXTERNAL_ALIASES"
	if [ -f "$EXTERNAL_API" ]; then
		decls="$decls
$(decls_of "$EXTERNAL_API" "$EXTERNAL_ALIASES")"
		EXTERNAL_ALIASES=
	else
		echo "cheatsheet: $EXTERNAL_API not found, its names are not checked"
	fi
fi
alt=$(printf '%s\n' "$all" | tr ' ' '\n' | grep . | sed -e 's/=.*//' | paste -sd'|')
status=0
# Every "alias.name" the sheet writes, in code or prose, except the head of a dotted string
# ("vte.container.name" is a property name, not a declaration) and a file name (name.md).
refs=$(grep -oE "\\b($alt)\\.[A-Za-z_][A-Za-z0-9_]*(\\.[a-z])?" "$sheet" | sort -u)
for ref in $refs; do
	case $ref in *.?) continue ;; esac
	pkg=${ref%%.*}
	name=${ref#*.}
	case $name in js | css | html | md | odin) continue ;; esac
	if [ -n "$EXTERNAL_ALIASES" ]; then
		case " $EXTERNAL_ALIASES " in *" $pkg="*) continue ;; esac
	fi
	if ! printf '%s\n' "$decls" | grep -qx "$pkg $name"; then
		echo "cheatsheet: $ref is not in the API"
		status=1
	fi
done
[ $status -eq 0 ] && echo "docs/CHEATSHEET.md: every name is in the API"
exit $status
