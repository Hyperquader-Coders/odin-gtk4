#!/bin/sh
# Writes the public API of every package of a binding, from `odin doc`, to stdout: docs/API.md.
# odin doc's source positions and the path of this checkout are left out; the names odin doc
# omits because they only alias a procedure (TYPE_FOO class types) are added from the sources.
# Canonical: the same bytes in every binding (amber-house scripts/binding/api.sh, copied by
# scripts/binding-sync). Everything that differs between repos is in scripts/api.conf.
# Usage: scripts/api.sh [COLLECTION_FLAGS...]
#   COLLECTION_FLAGS are passed to `odin doc` (the Makefile passes $(COLLECTIONS)); with none,
#   DOC_COLLECTIONS from api.conf is used. $ODIN is the compiler, default odin.
set -eu
export LC_ALL=C
dir=$(dirname "$0")
REPO='' PACKAGES='' COLLECTION='' DOC_COLLECTIONS='' INTRO='' PROC_ALIASES='' HIDE='' DEDUP=''
# shellcheck source=/dev/null
. "$dir/api.conf"
if [ -z "$REPO" ] || [ -z "$PACKAGES" ]; then
	echo "api.sh: $dir/api.conf must set REPO and PACKAGES" >&2
	exit 2
fi
if [ $# -eq 0 ]; then
	# shellcheck disable=SC2086 # DOC_COLLECTIONS is a list of flags
	set -- $DOC_COLLECTIONS
fi
odin=${ODIN:-odin}
printf '# %s API\n\n' "$REPO"
# shellcheck disable=SC2016 # the backticks are markdown
printf 'Every public declaration of every package, generated from the source by `make api`; do not\n'
printf 'edit. %s\n' "$INTRO"
for p in $PACKAGES; do
	# a package with no .odin file yet (before the first generate) is skipped
	ls "$p"/*.odin >/dev/null 2>&1 || continue
	if [ -n "$COLLECTION" ]; then
		printf '\n## %s:%s\n\n```text\n' "$COLLECTION" "$p"
	else
		printf '\n## %s\n\n```text\n' "$p"
	fi
	"$odin" doc "$p" "$@" -no-entry-point |
		sed -e 's| */\* [0-9]*![0-9]* \*/||' |
		awk -v hide="$HIDE" -v dedup="$DEDUP" '
			/^\tfullpath:$/ { getline; next } # the path of this checkout, different on every machine
			/^\t\/[^ ]*$/ { next }
			hide != "" && /^\t\t[A-Za-z]/ { skip = ($0 ~ ("^\t\t(" hide ")")) }
			/^\t?[^\t]/ || /^$/ { skip = 0 }
			!skip { if (dedup != 1 || $0 != prev) print; prev = $0 }
		' |
		sed -e 's/[[:space:]]*$//' | cat -s
	if [ -n "$PROC_ALIASES" ]; then
		# odin doc omits a name that only aliases a procedure: TYPE_FOO :: foo_get_type.
		aliases=$(grep -hE '^[A-Z][A-Z0-9_]+ :: [a-z][a-z0-9_]+[[:space:]]*$' "$p"/*.odin | sed -e 's/[[:space:]]*$//' | sort -u || true)
		if [ -n "$aliases" ]; then
			printf '\n\taliases of procedures: %s\n\n' "$PROC_ALIASES"
			printf '%s\n' "$aliases" | sed -e 's/^/\t\t/'
		fi
	fi
	printf '```\n'
done
