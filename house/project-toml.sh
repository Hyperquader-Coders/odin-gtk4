#!/bin/sh
# project-toml.sh: house-rules scripts/binding/project-toml.sh, the same in every repository.
# The reader of project.toml for make and the shell (docs/PROJECT_TOML.md); every other program
# reads it through amber-lib's amber_project, and both give the answers tests/project-toml holds.
#
#   project-toml.sh check [<file>]        the file is in the layout: exit 0, else exit 2 and why
#   project-toml.sh get <table> <key>     a key's value as written, empty when it is not there
#   project-toml.sh steps                 [project] steps, else the kind's
#   project-toml.sh tiers                 the tiers' names, in the file's order
#   project-toml.sh packages              this repository's [build] and [test] packages, then the
#                                         [build] packages of every sibling the walk reaches, sorted, once
#   project-toml.sh runtime               [runtime] packages, this repository's and every sibling's
#                                         the walk reaches, sorted, once: what a program built on
#                                         them needs at run time, never in packages
#   project-toml.sh siblings              every sibling the walk reaches: <ROOT> <name> <url>
#   project-toml.sh collections [<tier>]  -collection:<name>=<dir> for this repository and every
#                                         Odin library the walk reaches, or a tier's alone
#   project-toml.sh clone                 clones each sibling that is missing, then walks on to its
#                                         own (`make init-siblings`)
#
# A sibling is $<ROOT>/<name>, <name> the URL's last part, or $<NAME>_DIR where that is set
# (ODIN_WEB_DIR for odin-web), as a worktree is. house-rules and unauthed-kubernetes, which no
# library builds on, are cloned and listed where they are named and never walked; a sibling on
# the way to itself ends that branch. A sibling not there stops the walk with exit 1, as does one
# with no project.toml: nothing is guessed. Run from the repository's top, as make runs it.
set -eu

SCHEMA=amber-project-1
KINDS="binding lib web-app desktop bundle site go-app other"
# The kinds with settings of their own, in a table named after the kind.
TABLED="web-app desktop bundle site go-app"
# The contributor licence agreements a repository can require.
CLAS="amber"
# The master texts are in house-rules.
script_dir=$(cd "$(dirname "$0")" && pwd)
case $script_dir in */scripts/binding) MASTERS=${script_dir%/scripts/binding} ;; *) MASTERS= ;; esac
# The siblings that are no libraries, which nothing builds on: not walked.
LEFT_OUT="house-rules unauthed-kubernetes"

fail() {
	echo "project-toml: $2" >&2
	exit "$1"
}

# The file a checkout describes itself in: project.toml, else none.
file_of() {
	if [ "$1" = . ]; then at=; else at=$1/; fi
	if [ -f "$1/project.toml" ]; then
		echo "${at}project.toml"
	fi
}

# check <file>: the layout; a license that is what the LICENSE beside the file says, and that
# file word for word the master text where the license is ours (its copyright line is the
# master's); a cla whose CLA beside the file is the master text word for word, and no CLA without.
check() {
	layout "$1" || return 2
	dir=$(dirname "$1")
	licensed=$(get "$1" project license)
	if [ -n "$licensed" ]; then
		lfile=$dir/LICENSE
		[ -f "$lfile" ] || fail 2 "$1:0: license \"$licensed\" but there is no LICENSE file"
		first=$(grep -m1 '[^[:space:]]' "$lfile" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
		case $first in
		*"$licensed"*) ;;
		*)
			# A GNU licence may open with a preamble (libgit2's does): its title on a line of its
			# own anywhere in LICENSE counts.
			gnu=
			case $licensed in
			GPL-*) gnu="GNU GENERAL PUBLIC LICENSE" ;;
			LGPL-*) gnu="GNU LESSER GENERAL PUBLIC LICENSE" ;;
			esac
			[ -z "$gnu" ] || ! grep -qx "[[:space:]]*${gnu}[[:space:]]*" "$lfile" || first=$gnu
			case $licensed:$first in
			"BSD-3-Clause:BSD 3-Clause License"* | "MIT:MIT License"* | "MPL-2.0:Mozilla Public License Version 2.0"*) ;;
			"ASL-1.0:Amber Source License (ASL) 1.0"*) ;;
			"Apache-2.0:Apache License"*) ;;
			GPL-*:*"GNU GENERAL PUBLIC LICENSE"* | LGPL-*:*"GNU LESSER GENERAL PUBLIC LICENSE"*) ;;
			*) fail 2 "$1:0: license \"$licensed\" is not what LICENSE says: $first" ;;
			esac
			;;
		esac
		master=$MASTERS/licenses/$licensed.txt
		if [ -n "$MASTERS" ] && [ -f "$master" ] && grep -qxF "$(grep -m1 '^Copyright' "$master")" "$lfile"; then
			cmp -s "$lfile" "$master" || fail 2 "$1:0: LICENSE is not the master text of $licensed word for word"
		fi
	fi
	agreed=$(get "$1" project cla)
	if [ -n "$agreed" ]; then
		[ -f "$dir/CLA" ] || fail 2 "$1:0: cla \"$agreed\" but there is no CLA file"
		[ -z "$MASTERS" ] || cmp -s "$dir/CLA" "$MASTERS/cla/$agreed" || fail 2 "$1:0: CLA is not the master text of $agreed word for word"
	elif [ -f "$dir/CLA" ]; then
		fail 2 "$1:0: CLA but [project] names no cla"
	fi
	return 0
}

# layout <file>: the layout of docs/PROJECT_TOML.md, A and B; prints why and exits 2 when not.
layout() {
	awk -v schema="$SCHEMA" -v kinds=" $KINDS " -v clas=" $CLAS " -v TABLED="$TABLED" -v file="$1" '
	BEGIN {
		kind_keys["web-app"] = "app link-extra package-dirs shots-tests deb-examples container-debs"
		kind_keys["desktop"] = "main bin own-libs"
		kind_keys["bundle"] = "version source sha256 commit build-system options build-flags"
		kind_keys["site"] = "port"
		kind_keys["go-app"] = "main bin version-var"
	}
	function bad(why) { printf "project-toml: %s:%d: %s\n", file, NR, why > "/dev/stderr"; failed = 1; exit 2 }
	function rank_of(t) {
		if (t == "project") return 0
		if (t ~ /^siblings\./) return 1
		if (t == "build") return 2
		if (t == "test") return 3
		if (t == "runtime") return 4
		if (t ~ /^tiers\./) return 5
		if (t == "debian") return 7
		if (t == "flatpak") return 8
		return 6
	}
	# A reverse-DNS name: two parts or more, each a letter, then letters, digits, _ or -.
	function rdns(v) { return v ~ /^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z][A-Za-z0-9_-]*)+$/ }
	# The words of v that do not match re, blank-separated; empty when every one does.
	function wrong_words(v, re,    n, i, w, out) {
		n = split(v, w, " ")
		out = ""
		for (i = 1; i <= n; i++) if (w[i] !~ re) out = out (out == "" ? "" : " ") w[i]
		return out
	}
	# The keys that hold a list; every other key holds one value.
	function listy(t, k) {
		if (t == "project") return k == "steps" || k == "tags"
		if (t == "build" || t == "test") return k == "packages" || k == "lib"
		if (t == "runtime") return k == "packages"
		if (t ~ /^tiers\./) return k == "lib" || k == "uses"
		if (t == "debian") return k ~ /^(depends|recommends|suggests|provides|conflicts|replaces)$/
		if (t == "flatpak") return k ~ /^(sdk-extensions|finish-args|cleanup)$/
		if (t == "web-app") return k ~ /^(link-extra|package-dirs|shots-tests|deb-examples|container-debs)$/
		if (t == "desktop") return k == "own-libs"
		if (t == "bundle") return k == "options" || k == "build-flags"
		return 0
	}
	# Inside key = [: an item a line, until ] alone.
	list != "" {
		# A blank or comment line is wrong inside a list, or the list was never closed: the next
		# line that is neither tells which.
		if ($0 == "" || $0 ~ /^#/ || $0 ~ /^[[:space:]]+#/) {
			if (!gap) gap = NR
			next
		}
		if ($0 ~ /^\[/ || $0 ~ /^[a-z0-9-]+ = /) { NR = list_at; bad(list " = [ has no ] alone on a line to close it") }
		if (gap) { NR = gap; bad("a list holds one item a line, two spaces in, quoted, with a comma after it, and no blank or comment line: \"<item>\",") }
		if ($0 == "]") {
			done = NR
			NR = list_at
			take(list, items, 1)
			NR = done
			list = ""
			next
		}
		if ($0 ~ /^  "[^"\\# ]+",$/ && $0 !~ /[[:cntrl:]]/) {
			items = items (items == "" ? "" : " ") substr($0, 4, length($0) - 5)
			next
		}
		bad("a list holds one item a line, two spaces in, quoted, with a comma after it, and no blank or comment line: \"<item>\",")
	}
	/^$/ { next }
	/^#/ {
		if (index($0, " = ")) bad("a comment holds \" = \", which make would read as a key")
		next
	}
	/^\[/ {
		if ($0 !~ /^\[[a-z0-9_.A-Z-]+\]$/) bad("a table header is [name] alone on its line")
		t = substr($0, 2, length($0) - 2)
		if (tables == 0 && t != "project") bad("the first table is [project]")
		if (t ~ /^siblings\./) {
			if (t !~ /^siblings\.[A-Z][A-Z_]*_ROOT$/) bad("[" t "] does not name a root variable ([siblings.AMBER_ROOT])")
		} else if (t ~ /^tiers\./) {
			if (t !~ /^tiers\.[a-z0-9-]+$/) bad("[" t "]: a tier is [tiers.<name>], the name [a-z0-9-]+")
			# A tier is above every table after its own.
			if (tier != "") tier_seen[tier] = 1
			tier = substr(t, 7)
		} else if (t != "project" && t != "build" && t != "test" && t != "runtime" && t != "debian" && t != "flatpak" && !(t == kind && index(" " TABLED " ", " " kind " "))) {
			bad("[" t "] is no table of this layout" (index(" " TABLED " ", " " kind " ") ? ", nor this kind'\''s, [" kind "]" : ""))
		}
		if (seen_table[t]++) bad("[" t "] is there twice")
		r = rank_of(t)
		if (r < rank) bad("[" t "] comes before the tables above it: [project], [siblings.*], [build], [test], [runtime], [tiers.*], the kind'\''s, [debian], then [flatpak]")
		rank = r
		table = t
		tables++
		keys = 0
		next
	}
	{
		if (table == "") bad("a key outside a table")
		key = $0
		sub(/ = .*/, "", key)
		if ($0 ~ /^[a-z0-9-]+ = \[$/) { list = key; list_at = NR; items = ""; next }
		if ($0 ~ /^[a-z0-9-]+ = \[\]$/) { take(key, "", 1); next }
		if ($0 ~ /^[a-z0-9-]+ = \[/) bad("write " key " as a list, one item per line")
		if ($0 !~ /^[a-z0-9-]+ = "[^"\\#]*"$/ || $0 ~ /[[:cntrl:]]/) bad("a line is key = \"value\" or key = [ starting a list: the key [a-z0-9-]+, no \", \\, # or control character in the value, nothing after it")
		value = $0
		sub(/^[^=]* = "/, "", value)
		sub(/"$/, "", value)
		take(key, value, 0)
	}
	# A key and its value, the items of a list joined with a blank.
	function take(key, value, is_list) {
		if (seen_key[table, key]++) bad(key " is in [" table "] twice")
		keys++
		if (is_list && !listy(table, key)) bad(key " is one value, key = \"value\", not a list")
		if (!is_list && listy(table, key)) bad(key " is a list: " key " = [ alone on its line, then one item a line, then ] alone")
		if (table == "project") {
			if (keys == 1 && key != "schema") bad("[project]'\''s first key is schema = \"" schema "\"")
			if (key == "schema" && value != schema) bad("schema \"" value "\" is not one this reader knows (" schema ")")
			if (key == "kind") {
				if (index(kinds, " " value " ") == 0) bad("kind \"" value "\" is not one of" kinds)
				kind = value
			} else if (key == "collection") {
				if (value !~ /^[a-z0-9_-]+$/) bad("collection \"" value "\" is no collection name")
			} else if (key == "app-id") {
				if (!rdns(value)) bad("app-id \"" value "\" is no reverse-DNS name (org.amberlinux.Pinax)")
				app_id = value
			} else if (key == "name") {
				if (value !~ /^[a-z0-9][a-z0-9.-]*$/) bad("name \"" value "\" is no repository name")
			named = value
			} else if (key == "license") {
				if (value == "" || wrong_words(value, "^([A-Za-z0-9][A-Za-z0-9.+-]*|OR|AND|WITH)$") != "") bad("license \"" value "\" is no SPDX expression")
			} else if (key == "cla") {
				if (index(clas, " " value " ") == 0) bad("cla \"" value "\" is not one this reader knows (" substr(clas, 2, length(clas) - 2) ")")
			} else if (key == "summary") {
				# As a Debian synopsis: one line, short, no full stop, not opening with the name.
				if (value == "") bad("summary is empty")
				if (length(value) > 80) bad("summary is " length(value) " characters, more than 80")
				if (value ~ /\.$/) bad("summary ends with a full stop")
				summary = value
				summary_at = NR
			} else if (key == "tags") {
				n = split(value, tg, " ")
				if (n < 1 || n > 20) bad("tags holds " n " tags, not 1 to 20")
				wrong = ""
				for (i = 1; i <= n; i++) if (tg[i] !~ /^[a-z0-9]+(-[a-z0-9]+)*$/ || length(tg[i]) > 50) wrong = wrong (wrong == "" ? "" : " ") tg[i]
				if (wrong != "") bad("tags holds what is not a tag, lowercase words joined by -, at most 50 characters: " wrong)
				split("", tag_seen)
				for (i = 1; i <= n; i++) if (tag_seen[tg[i]]++) bad("tags holds " tg[i] " twice")
			} else if (key != "schema" && key != "steps") {
				bad("[project] holds schema, name, kind, summary, tags, collection, steps, app-id, license and cla, not " key)
			}
		} else if (table ~ /^siblings\./) {
			if (value !~ /^https:\/\/github\.com\/[A-Za-z0-9_][A-Za-z0-9_.-]*\/[A-Za-z0-9_][A-Za-z0-9_.-]*$/) bad("\"" value "\" for " key " is not https://github.com/<owner>/<name>")
			name = value
			sub(/.*\//, "", name)
			sub(/\.git$/, "", name)
			if (name != key) bad(key " is not the URL'\''s last part, " name)
			if (sibling[key]++) bad("the sibling " key " is there twice")
		} else if (table == "build" || table == "test" || table == "runtime") {
			if (key != "packages" && (table == "runtime" || key != "lib")) bad("[" table "] holds " (table == "runtime" ? "packages" : "packages and lib") ", not " key)
			if (key == "packages") {
				wrong = wrong_words(value, "^[a-z0-9][a-z0-9+.-]+$")
				if (wrong != "") bad("packages holds what is not a package name: " wrong)
			} else {
				wrong = wrong_words(value, "^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$")
				if (wrong != "") bad("lib holds what is not a package folder: " wrong)
			}
		} else if (table == "debian") {
			if (key == "section") {
				if (value !~ /^[a-z0-9][a-z0-9\/-]*$/) bad("section \"" value "\" is no Debian section")
			} else if (key == "architecture") {
				if (value != "amd64" && value != "all") bad("architecture is amd64 or all, not " value)
			} else if (key == "homepage") {
				if (value !~ /^https:\/\/[^ ]+$/) bad("homepage \"" value "\" is no https:// URL")
			} else if (key ~ /^(depends|recommends|suggests|provides|conflicts|replaces)$/) {
				wrong = wrong_words(value, "^[a-z0-9][a-z0-9+.-]+(>=[0-9][A-Za-z0-9.+~:-]*)?$")
				if (wrong != "") bad(key " holds what is not a package or package>=version: " wrong)
			} else {
				bad("[debian] holds section, architecture, homepage, depends, recommends, suggests, provides, conflicts and replaces, not " key)
			}
		} else if (table == "flatpak") {
			if (key == "runtime" || key == "sdk") {
				if (!rdns(value)) bad(key " \"" value "\" is no reverse-DNS name")
			} else if (key == "sdk-extensions") {
				n = split(value, pk, " ")
				wrong = ""
				for (i = 1; i <= n; i++) if (!rdns(pk[i])) wrong = wrong (wrong == "" ? "" : " ") pk[i]
				if (wrong != "") bad("sdk-extensions holds what is not a reverse-DNS name: " wrong)
			} else if (key == "finish-args") {
				wrong = wrong_words(value, "^--[a-z]")
				if (wrong != "") bad("finish-args holds what is not one flag: " wrong)
			} else if (key == "cleanup") {
				wrong = wrong_words(value, "^/")
				if (wrong != "") bad("cleanup holds what is not a path under /app: " wrong)
			} else if (key == "runtime-version" || key == "command" || key == "branch") {
				if (value !~ /^[A-Za-z0-9._-]+$/) bad(key " \"" value "\" is not [A-Za-z0-9._-]+")
			} else {
				bad("[flatpak] holds runtime, runtime-version, sdk, sdk-extensions, finish-args, command, branch and cleanup, not " key)
			}
		} else if (table == kind) {
			holds = kind_keys[kind]
			if (index(" " holds " ", " " key " ") == 0) { gsub(/ /, ", ", holds); sub(/, [^,]*$/, " and &", holds); sub(/ and , /, " and ", holds); bad("[" kind "] holds " holds ", not " key) }
		} else if (table ~ /^tiers\./) {
			if (key == "extends") {
				if (value !~ /^[a-z0-9-]+$/) bad("a tier extends one tier")
				if (!(value in tier_seen)) bad("[" table "] extends " value ", no tier above it")
			} else if (key == "uses") {
				n = split(value, used, " ")
				for (i = 1; i <= n; i++) if (!(used[i] in sibling)) bad("[" table "] uses " used[i] ", which no [siblings.*] table names")
			} else if (key == "lib") {
				n = split(value, pk, " ")
				for (i = 1; i <= n; i++) if (pk[i] in in_tier) bad("the package " pk[i] " is in [tiers." in_tier[pk[i]] "] and [" table "]"); else in_tier[pk[i]] = tier
			} else {
				bad("a tier holds lib, uses and extends, not " key)
			}
		}
	}
	END {
		if (failed) exit 2
		if (list != "") { NR = list_at; bad(list " = [ has no ] alone on a line to close it") }
		if (!seen_table["project"]) { NR = 0; bad("no [project] table, whose first key is schema = \"" schema "\"") }
		if (kind == "") { NR = 0; bad("[project] names no kind") }
		if (summary == "") { NR = 0; bad("[project] names no summary, the one line saying what it is") }
		if (!seen_key["project", "tags"]) { NR = 0; bad("[project] names no tags") }
		if (named == "") { NR = 0; bad("[project] names no name, the repository'\''s") }
		if (!seen_key["project", "license"]) { NR = 0; bad("[project] names no license, its LICENSE as an SPDX expression") }
		# The first word, less a comma, colon or semicolon after it, is not the name.
		first_word = summary
		sub(/ .*/, "", first_word)
		sub(/[,:;]$/, "", first_word)
		if (named != "" && tolower(first_word) == named) { NR = summary_at; bad("summary starts with the repository'\''s name, " named) }
		NR = 0
		if (seen_table["debian"]) {
			if (!seen_key["debian", "section"]) bad("[debian] names no section")
		}
		if (seen_table["flatpak"]) {
			if (app_id == "") bad("[flatpak] needs [project] app-id")
			if (!seen_key["flatpak", "runtime"]) bad("[flatpak] names no runtime")
			if (!seen_key["flatpak", "runtime-version"]) bad("[flatpak] names no runtime-version")
			if (!seen_key["flatpak", "sdk"]) bad("[flatpak] names no sdk")
			if (!seen_key["flatpak", "finish-args"]) bad("[flatpak] names no finish-args")
		}
	}' "$1"
}

# get <file> <table> <key>: the value as written, a list one item a line, nothing when it is
# not there. Only on a file check has passed, so a list out of the layout is never read short.
get() {
	awk -v want="$2" -v key="$3" '
		list && $0 == "]" { exit }
		list { print substr($0, 4, length($0) - 5); next }
		/^\[/ { table = substr($0, 2, length($0) - 2); next }
		table != want { next }
		$0 == key " = [" { list = 1; next }
		$0 == key " = []" { exit }
		index($0, key " = \"") == 1 { v = substr($0, length(key) + 5); sub(/"$/, "", v); print v; exit }' "$1"
}

# system <file> <phase>: a phase's system packages, [<phase>] packages.
system() { get "$1" "$2" packages; }

# The siblings a file names, one <ROOT> <name> <url> a line.
siblings_in() {
	awk -F' = ' '/^\[siblings\./ {root = substr($0, 11, length($0) - 11); next}
		/^\[/ {root = ""}
		root != "" && NF == 2 {gsub(/"/, "", $2); print root, $1, $2}' "$1"
}

# A sibling's checkout: $<NAME>_DIR where it is set, else $<ROOT>/<name>.
dir_of() {
	over=$(printf '%s_DIR' "$2" | tr 'a-z-' 'A-Z_')
	if eval "[ -n \"\${$over:-}\" ]"; then
		eval "printf %s \"\${$over}\""
		return
	fi
	case $1 in
	*[!A-Z_]* | _ROOT) fail 2 "[siblings.$1] does not name a root variable ([siblings.AMBER_ROOT])" ;;
	?*_ROOT) ;;
	*) fail 2 "[siblings.$1] does not name a root variable ([siblings.AMBER_ROOT])" ;;
	esac
	eval "[ -n \"\${$1:-}\" ]" || fail 2 "$1 is not set: it names the root $2 goes in (a desk's shell sets it; a workflow sets it to a folder above its workspace)"
	dir=$(eval "printf %s \"\${$1}\"")
	printf '%s/%s' "${dir%/}" "$2"
}

# walk <checkout> <mode> <path>: mode siblings prints each sibling, packages each one's [build]
# packages, runtime each one's [runtime] packages, clone clones the missing; <path> the siblings
# on the way here, so two that name each other end the walk.
walk() {
	file=$(file_of "$1")
	check "$file" || exit 2
	siblings_in "$file" | while read -r root name url; do
		name=${url##*/}
		name=${name%.git}
		dir=$(dir_of "$root" "$name") || exit $?
		case " $3 " in *" $dir "*) continue ;; esac
		if [ "$2" = clone ]; then
			if [ -e "$dir" ]; then
				echo "init-siblings: $name is there, $dir"
			else
				echo "init-siblings: cloning $name into $dir"
				git clone -q -- "$url" "$dir" || exit 1
			fi
		elif [ "$2" = siblings ]; then
			echo "$root $name $url"
		fi
		case " $LEFT_OUT " in *" $name "*) continue ;; esac
		[ -d "$dir" ] || fail 1 "$name is not at $dir: run make init-siblings"
		sfile=$(file_of "$dir")
		[ -n "$sfile" ] || fail 1 "$dir has no project.toml"
		[ "$2" != packages ] || system "$sfile" build
		[ "$2" != runtime ] || system "$sfile" runtime
		walk "$dir" "$2" "$3 $dir" || exit $?
	done
}

# libraries <checkout> <path> [<name>...]: <collection> <dir> for each Odin library reached from
# the named siblings of <checkout>, all of them when none is named.
libraries() {
	top=$1 path=$2
	shift 2
	only=" $* "
	siblings_in "$top/project.toml" | while read -r root name url; do
		name=${url##*/}
		name=${name%.git}
		[ "$only" = "  " ] || case $only in *" $name "*) ;; *) continue ;; esac
		case " $LEFT_OUT " in *" $name "*) continue ;; esac
		dir=$(dir_of "$root" "$name") || exit $?
		case " $path " in *" $dir "*) continue ;; esac
		[ -d "$dir" ] || fail 1 "$name is not at $dir: run make init-siblings"
		[ -f "$dir/project.toml" ] || fail 1 "$dir has no project.toml, so its collection is not known: it moves before the repositories that use it"
		check "$dir/project.toml" || exit 2
		case $(get "$dir/project.toml" project kind) in
		lib | binding) ;;
		*) continue ;;
		esac
		echo "$(collection_of "$dir" "$name") $dir"
		# A subshell, as the call sets top, path and only again.
		(libraries "$dir" "$path $dir") || exit $?
	done
}

# A library's collection: [project] collection, else its name, else its folder's.
collection_of() {
	c=$(get "$1/project.toml" project collection)
	[ -n "$c" ] || c=$(get "$1/project.toml" project name)
	echo "${c:-$2}"
}

# The repository's own name: its main checkout's folder, from a worktree too; the folder's own
# name where it is no checkout's top.
own_name() {
	top=$(git rev-parse --show-toplevel 2>/dev/null) || top=
	if [ "$top" != "$PWD" ]; then
		basename "$PWD"
		return
	fi
	common=$(cd "$(git rev-parse --git-common-dir)" && pwd)
	basename "$(dirname "$common")"
}

# The tier and every tier it extends, one a line, the tier first.
chain() {
	t=$1 n=0
	while [ -n "$t" ]; do
		grep -qx "\[tiers\.$t\]" project.toml || fail 2 "project.toml has no [tiers.$t]"
		echo "$t"
		t=$(get project.toml "tiers.$t" extends)
		n=$((n + 1))
		[ $n -lt 100 ] || fail 2 "[tiers.$1] extends in a circle"
	done
}

here() {
	[ -f project.toml ] || fail 2 "no project.toml in $PWD"
	check project.toml || exit 2
	named=$(get project.toml project name)
	[ -z "$named" ] || [ "$named" = "$(own_name)" ] || fail 2 "project.toml:0: name \"$named\" is not the repository's name, $(own_name)"
	# Without a name, the repository's own is the one the summary may not open with.
	own=$(own_name)
	opens=$(get project.toml project summary | sed 's/ .*//; s/[,:;]$//' | tr 'A-Z' 'a-z')
	[ "$opens" != "$own" ] || fail 2 "project.toml:$(grep -n '^summary = ' project.toml | cut -d: -f1): summary starts with the repository's name, $own"
}

cmd=${1:-}
[ $# -eq 0 ] || shift
case $cmd in
check)
	if [ $# -eq 0 ]; then
		here
	else
		[ -f "$1" ] || fail 2 "no $1"
		check "$1"
	fi
	;;
get)
	[ $# -eq 2 ] || fail 2 "usage: project-toml.sh get <table> <key>"
	here
	get project.toml "$1" "$2"
	;;
tiers)
	here
	sed -n 's/^\[tiers\.\([a-z0-9-]*\)\]$/\1/p' project.toml
	;;
steps)
	here
	s=$(get project.toml project steps)
	if [ -z "$s" ]; then
		case $(get project.toml project kind) in
		binding | lib) s="init-modules check-no-agent-files lint check test" ;;
		web-app) s="init-modules check-fmt check-no-agent-files check test test-asan smoke lint" ;;
		desktop) s="init-modules check-fmt check-no-agent-files lint check test build" ;;
		bundle) s="init-modules check-fmt check-no-agent-files lint check check-lintian" ;;
		site) s="init-modules check-fmt check-no-agent-files lint build test" ;;
		go-app) s="init-modules check-fmt check-no-agent-files lint check test" ;;
		*) fail 2 "kind $(get project.toml project kind) has no steps of its own: [project] steps names them" ;;
		esac
	fi
	# shellcheck disable=SC2086 # a list one item a line, on one line
	echo $s
	;;
packages)
	f=$(file_of .)
	[ -n "$f" ] || fail 2 "no project.toml in $PWD"
	check "$f" || exit 2
	# The list is gathered first: a walk that stops fails the script, which a pipeline would hide.
	list=$({
		system "$f" build
		system "$f" test
		walk . packages ""
	}) || exit $?
	printf '%s\n' "$list" | tr ' ' '\n' | grep . | sort -u || true
	;;
runtime)
	here
	list=$({
		get project.toml runtime packages
		walk . runtime ""
	}) || exit $?
	printf '%s\n' "$list" | tr ' ' '\n' | grep . | sort -u || true
	;;
siblings)
	[ -n "$(file_of .)" ] || fail 2 "no project.toml in $PWD"
	list=$(walk . siblings "") || exit $?
	printf '%s\n' "$list" | grep . | sort -u || true
	;;
clone)
	[ -n "$(file_of .)" ] || fail 2 "no project.toml in $PWD"
	walk . clone ""
	;;
collections)
	here
	if [ $# -gt 0 ]; then
		tiers=$(chain "$1") || exit $?
		uses=
		for t in $tiers; do uses="$uses $(get project.toml "tiers.$t" uses)"; done
		# A tier that uses nothing gets this repository's collection alone.
		[ -n "$(echo "$uses" | tr -d ' ')" ] || uses=-
	else
		uses=
	fi
	# shellcheck disable=SC2086 # the tier's siblings, one word each
	list=$(libraries "$PWD" "$PWD" $uses) || exit $?
	case $(get project.toml project kind) in
	lib | binding) list=$(printf '%s\n%s %s' "$list" "$(collection_of . "$(own_name)")" "$PWD") ;;
	esac
	printf '%s\n' "$list" | grep . | sort -u | awk '$1 in dir && dir[$1] != $2 { print "project-toml: the collection " $1 " is both " dir[$1] " and " $2 > "/dev/stderr"; exit 2 }
		!($1 in dir) { dir[$1] = $2 }' || exit 2
	printf '%s\n' "$list" | grep . | sort -u | awk '!seen[$1]++ { print "-collection:" $1 "=" $2 }'
	;;
-h | --help | '')
	sed -n '2,27s/^# \{0,1\}//p' "$0"
	;;
*)
	fail 2 "no command $cmd: check, get, steps, tiers, packages, runtime, siblings, collections or clone"
	;;
esac
