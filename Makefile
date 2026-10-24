# odin-gtk4: Odin bindings for GTK 4, GDK and GSK. Consumed via -collection:gtk4=/path/to/odin-gtk4
# Each entry is a package directory at the repo root; one with no .odin file yet is skipped.
PACKAGES = $(foreach p,gtk4,$(if $(wildcard $(p)/*.odin),$(p)))
# AMBER_ROOT is the Amber tree, the folder holding the suite's checkouts: mise sets it on a
# development machine and the workflow sets it to its workspace. Unset, it is the folder holding
# this checkout: that fallback is for people outside the house, who clone the bindings side by side.
AMBER_ROOT ?= $(abspath $(CURDIR)/..)
# amber-house: the suite's shared checks; `make lint` runs its check-example-hosts where it is
# there. It is private, so a clone outside the house and the public runner go without it.
HOUSE ?= $(AMBER_ROOT)/amber-house
# runic: github.com/Hyperquader-Coders/runic on branch amber-patched, built by its amber-build.sh; see odin-glib/docs/DECISIONS.md §2.
RUNIC ?= $(AMBER_ROOT)/runic/build/runic
BRANCH ?= main
REMOTE ?= origin
ROOT_COMMIT_MSG ?= Initial odin-gtk4
GLIB ?= $(AMBER_ROOT)/odin-glib
CAIRO ?= $(AMBER_ROOT)/odin-cairo
PANGO ?= $(AMBER_ROOT)/odin-pango
GRAPHENE ?= $(AMBER_ROOT)/odin-graphene
PIXBUF ?= $(AMBER_ROOT)/odin-gdk-pixbuf
# A test that leaks or frees badly fails, rather than only warning. `make test ASAN=1` runs
# the tests under AddressSanitizer as well.
ASAN ?=
# The GTK the binding is generated from and tested against is the suite's bundle, amber-gtk4
# (libgtk-4 4.16.13, from amber-gtk4-dev), in its own folder off the linker's path: a test links
# it from there and runs it through the run path, as every program built on the binding does.
# The distro's 4.14.5 is the floor a program may load; the tests load the bundle, so the version
# test is exact (GTK_BUNDLE_EXPECTED).
GTK_LIB = /usr/lib/amber-gtk4
GTK_LINK = -extra-linker-flags:"-L$(GTK_LIB) -Wl,-rpath,$(GTK_LIB)"
TEST_ENV = GTK_BUNDLE_EXPECTED=1
# The suite's names for the compiler flags, in this order. COLLECTIONS is every collection the
# packages import, this repo's own first; sibling paths are `?=` variables above. ODIN_FLAGS is
# what every odin command takes. ODIN_TEST_FLAGS adds what only a test run takes, and a binding
# whose tests link a staged library adds its link flags there. A recipe adds only what its own
# command needs (`-no-entry-point`, `-out:`) and types no `-collection:` flag.
# -vet -strict-style matter beyond this repo: odin test compiles the #+test files of every
# imported package with the consumer's flags, so a vet error here breaks every program that
# tests against it. One test thread in every binding: GTK and GObject type registration is not
# thread-safe, and two tests that first touch a type on different threads collide and hang the
# runner.
COLLECTIONS ?= -collection:gtk4=. -collection:glib=$(GLIB) -collection:cairo=$(CAIRO) -collection:pango=$(PANGO) -collection:graphene=$(GRAPHENE) -collection:pixbuf=$(PIXBUF)
ODIN_FLAGS = $(COLLECTIONS) -vet -strict-style
ODIN_TEST_FLAGS = $(ODIN_FLAGS) $(GTK_LINK) -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true $(if $(ASAN),-debug -sanitize:address)

# The system packages, one list for a desk and for CI: the library the binding is generated from
# and tested against, and the tools the targets call (shellcheck in lint, shfmt in fmt-sh).
# `make init-packages` installs it; a package missing on the runner is added here, and the
# workflow names none.
DEPS := amber-gtk4-dev shellcheck shfmt

.PHONY: help setup init-packages init-modules init-workstation check-toolchain ols generate check test ci clean push force-push lint api check-api check-generated check-no-agent-files check-test-tag fmt check-fmt fmt-sh check-fmt-sh fmt-tools

check: check-test-tag ## type-check every package with -vet -strict-style
	@for p in $(PACKAGES); do echo "== check $$p =="; odin check $$p $(ODIN_FLAGS) -no-entry-point || exit 1; done

test: ## run every package's tests (ASAN=1 adds AddressSanitizer)
	@mkdir -p build
	@for p in $(PACKAGES); do echo "== test $$p =="; env -u DISPLAY -u WAYLAND_DISPLAY $(TEST_ENV) odin test $$p $(ODIN_TEST_FLAGS) -out:build/$${p}_test || exit 1; done

# Everything a push has to pass; CI (.github/workflows/ci.yml) runs the same.
ci: init-modules check test check-no-agent-files lint ## everything a push has to pass
	@echo 'CI OK'

generate: ## run runic over every package's rune.yml, then the post-processing rules
	@test -x $(RUNIC) || { echo "runic not found at $(RUNIC): clone github.com/Hyperquader-Coders/runic beside this repo on branch amber-patched and run its amber-build.sh"; exit 2; }
	RUNIC=$(abspath $(RUNIC)) GTK_INCLUDE=$(GTK_LIB)/include scripts/generate.sh

clean: ## remove build/
	rm -rf build

push: ## push the branch
	git push "$(REMOTE)" "$(BRANCH)"

# Agent files are never published. Two ways they get in: already tracked, or
# present-and-unignored when `git add -A` below sweeps the whole tree. Both are
# checked here, because a squashed history shows no file being added: a stray
# path appears in the root commit like any other file.
check-no-agent-files: ## refuse agent files that are tracked or not ignored
	@bad=$$(git ls-files | grep -E '(^|/)(\.mcp\.json|\.claude/|\.claude-amber/)' || true); \
	if [ -n "$$bad" ]; then \
		echo "agent files are tracked and must not be published:"; \
		printf '  %s\n' $$bad; \
		echo "fix: git rm -r --cached <path>, then add it to .gitignore"; \
		exit 2; \
	fi
	@for p in .mcp.json .claude .claude-amber; do \
		if [ -e "$$p" ] && ! git check-ignore -q "$$p"; then \
			echo "$$p exists and is not gitignored: 'git add -A' would publish it"; \
			echo "fix: add $$p to .gitignore"; \
			exit 2; \
		fi; \
	done
	@echo "no agent files staged for publication"

force-push: test check-no-agent-files ## squash history into one signed root commit and force-push
	@test -z "$$(git status --porcelain)" || { \
		echo "Working tree is dirty. Commit, stash, or revert changes first."; \
		exit 2; \
	}
	@set -e; \
	orig_branch="$$(git branch --show-current)"; \
	test -n "$$orig_branch" || { echo "force-push: detached HEAD, check out a branch first"; exit 1; }; \
	tmp_branch="root-squash-$$(date +%s)"; \
	step="starting"; ok=0; \
	trap 'if [ "$$ok" != 1 ]; then echo "force-push FAILED while: $$step. Local history is intact on $$orig_branch; $(REMOTE)/$(BRANCH) was not replaced." >&2; git checkout -f "$$orig_branch" >/dev/null 2>&1 || true; git branch -D "$$tmp_branch" >/dev/null 2>&1 || true; exit 1; fi' EXIT; \
	step="creating the orphan branch"; git checkout --orphan "$$tmp_branch"; \
	step="staging the tree"; git add -A; \
	step="signing the root commit"; git commit -S -m "$(ROOT_COMMIT_MSG)"; \
	step="pushing to $(REMOTE)/$(BRANCH) (refused or unreachable)"; git push --force "$(REMOTE)" "$$tmp_branch:$(BRANCH)"; \
	step="verifying $(REMOTE)/$(BRANCH) equals the new commit"; \
	remote_sha="$$(git ls-remote "$(REMOTE)" "refs/heads/$(BRANCH)" | cut -f1)"; \
	test -n "$$remote_sha" && test "$$remote_sha" = "$$(git rev-parse HEAD)"; \
	ok=1; \
	other_wt="$$(git worktree list --porcelain | awk -v b="branch refs/heads/$(BRANCH)" '/^worktree /{w=substr($$0, 10)} $$0 == b {print w}')"; \
	if [ -n "$$other_wt" ] && [ "$$other_wt" != "$$(git rev-parse --show-toplevel)" ]; then \
		git fetch "$(REMOTE)" "$(BRANCH)" >/dev/null 2>&1 || true; \
		git checkout -q --detach; git branch -D "$$tmp_branch" >/dev/null; \
		echo "Rewrote $$orig_branch as signed root commit on $(REMOTE)/$(BRANCH)."; \
		echo "$(BRANCH) is checked out in $$other_wt; once it is clean: git -C $$other_wt fetch && git -C $$other_wt reset --keep $(REMOTE)/$(BRANCH)"; \
	else \
		git branch -M "$$tmp_branch" "$(BRANCH)"; \
		git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null 2>&1 || { git fetch "$(REMOTE)" "$(BRANCH)" >/dev/null 2>&1 && git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null; } || echo "warning: could not set upstream"; \
		echo "Rewrote $$orig_branch as signed root commit on $(REMOTE)/$(BRANCH)."; \
	fi

lint: ## shellcheck the shell scripts; API, cheat sheet and generated-output checks
	@$(MAKE) --no-print-directory check-generated
	@$(MAKE) --no-print-directory check-api
	@scripts/cheatsheet.sh
	@if [ -x "$(HOUSE)/scripts/check-example-hosts" ]; then "$(HOUSE)/scripts/check-example-hosts" "$(CURDIR)"; \
	else echo "check-example-hosts not found in $(HOUSE)/scripts: skipping (amber-house is private; AMBER_ROOT or HOUSE finds it)"; fi
	@if command -v shellcheck >/dev/null; then \
		git ls-files | while read -r f; do \
			case "$$f" in *.sh|*.bash) echo "$$f";; \
			*) head -1 "$$f" 2>/dev/null | grep -q '^#!.*sh' && echo "$$f";; esac; \
		done | xargs -r shellcheck --severity=warning && echo "shellcheck OK"; \
	elif [ "$$GITHUB_ACTIONS" = true ]; then echo "shellcheck is not installed on this runner; it is in DEPS"; exit 1; \
	else echo "shellcheck not installed: skipping (apt install shellcheck)"; fi

check-generated: ## fail when runic's va_list, [^]T or [^]^T faults are back in the output
	@scripts/check-generated.sh

# docs/API.md: every public declaration, from odin doc. check-api (in lint) fails when it is stale.
api: ## regenerate docs/API.md
	scripts/api.sh $(ODIN_FLAGS) > docs/API.md

check-api: ## fail when docs/API.md is stale
	@mkdir -p build
	@scripts/api.sh $(ODIN_FLAGS) > build/API.md
	@cmp -s build/API.md docs/API.md || { echo 'docs/API.md is stale: run make api'; exit 1; }
	@echo "docs/API.md: current"

# `odin build` compiles a package's _test.odin files like any other file unless they
# start with #+test, so a test's imports and @(init) procs would ship in every program
# that imports the package.
check-test-tag: ## refuse _test.odin files without #+test
	@bad=$$(git ls-files --cached --others --exclude-standard '*_test.odin' | grep -Ev '(^|/)tests/' | xargs -r grep -L '^#+test' || true); \
	if [ -n "$$bad" ]; then \
		echo "test files without #+test, which odin build compiles into programs:"; \
		printf '  %s\n' $$bad; \
		exit 2; \
	fi

help: ## this list
	@awk 'BEGIN {FS = ":.*## "} \
	    /^##@ / {printf "\n%s\n", substr($$0, 5)} \
	    /^[a-z][a-z0-9-]*:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- siblings: amber-house scripts/binding/siblings.mk, the same in every repository with a siblings.txt ---
# siblings.txt names the repositories this one needs beside it, one a line, as
# `<ROOT_VARIABLE>,https://github.com/<owner>/<name>`; `#` starts a comment and blank lines are
# skipped. `make init-siblings` clones each one that is missing, from the URL as written, into
# `$(<ROOT_VARIABLE>)/<name>`, <name> being the URL's last part without `.git`. A checkout
# already there is left as it is: no pull, no reset, no checkout. Each variable is set in the
# environment or on the command line: mise at a desk, the workflow in CI, each to a folder above
# its workspace. It is part of `setup` (the rule below adds it, first, when this block stands
# above the `setup` rule) and never of `ci`.
SIBLING_ROOTS = $(foreach v,$(filter %_ROOT,$(.VARIABLES)),$(if $(filter environment% command%,$(origin $(v))),$(v)))
.PHONY: init-siblings
init-siblings: ## clone the repositories siblings.txt names that are missing from their roots; one already there is left as it is
	@sed 's/#.*//' siblings.txt | tr -d ' \t\r' | while IFS= read -r line; do \
		[ -n "$$line" ] || continue; \
		var=$${line%%,*}; url=$${line#*,}; \
		printf '%s\n' "$$var" | grep -Eqx '[A-Z_]+_ROOT' && [ "$$var" != "$$line" ] || \
			{ echo "init-siblings: '$$line' in siblings.txt does not start with a root variable and a comma (AMBER_ROOT,https://github.com/<owner>/<name>)" >&2; exit 2; }; \
		printf '%s\n' "$$url" | grep -Eqx 'https://github\.com/[A-Za-z0-9_][A-Za-z0-9_.-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*' || \
			{ echo "init-siblings: '$$url' in siblings.txt is not https://github.com/<owner>/<name>" >&2; exit 2; }; \
		name=$${url##*/}; name=$${name%.git}; \
		case " $(SIBLING_ROOTS) " in *" $$var "*) ;; \
		*) echo "init-siblings: $$var is not set: it names the root $$name goes in (mise sets it at a desk; a workflow sets it to a folder above its workspace)" >&2; exit 2 ;; esac; \
		root=$$(printenv "$$var") || root=; root=$${root%/}; \
		[ -n "$$root" ] || { echo "init-siblings: $$var is empty" >&2; exit 2; }; \
		dest=$$root/$$name; \
		if [ -e "$$dest" ]; then echo "init-siblings: $$name is there, $$dest"; continue; fi; \
		echo "init-siblings: cloning $$name into $$dest"; \
		git clone -q "$$url" "$$dest" || exit 1; \
	done

setup: init-siblings

# --- setup: amber-house scripts/binding/setup.mk, the same in every binding ---
# `make init-packages` installs DEPS, the list above. CI runs `sudo apt-get update && make
# init-packages APT_FLAGS=-y`, then `make ci`; at a desk apt asks before it installs.
APT_FLAGS ?=

init-packages: ## install the system packages (sudo apt)
	sudo apt-get install $(APT_FLAGS) --no-install-recommends $(DEPS)

# A binding has no language packages: the libraries it imports are sibling checkouts. `ci`
# depends on it all the same, as in every repository.
init-modules: ## install the language packages from the lock: none here (the libraries are sibling checkouts)

# What apt does not bring is reported and never installed: the Odin compiler, runic (Amber's
# fork, which `make generate` runs) and odinfmt (which `make fmt` runs).
check-toolchain: ## check the toolchain and report anything missing
	@ok=true; \
	if command -v odin >/dev/null; then echo "odin: $$(odin version)"; \
	else echo "missing: odin (https://odin-lang.org/docs/install)"; ok=false; fi; \
	if test -x $(RUNIC); then echo "runic: $(RUNIC)"; \
	else echo "missing: runic at $(RUNIC) (clone github.com/Hyperquader-Coders/runic beside this repo, check out amber-patched and run its amber-build.sh)"; ok=false; fi; \
	if command -v $(ODINFMT) >/dev/null; then echo "odinfmt: $$(command -v $(ODINFMT))"; \
	else echo "missing: odinfmt (apt install amber-ols)"; ok=false; fi; \
	$$ok

# ols.json is the Odin language server's settings, which an editor reads for completion and
# go-to-definition. It names the same collections as the build and takes a path as written, with
# no variables: so it is written from the build's collections, with absolute paths, and is not
# tracked. Run it again after a collection moves.
OLS_COLLECTIONS = $(sort $(filter -collection:%,$(COLLECTIONS)))
ols: ## write ols.json, the editor's settings, from the build's collections
	@{ printf '{\n\t"collections": [\n'; sep=''; \
	for c in $(patsubst -collection:%,%,$(OLS_COLLECTIONS)); do \
		printf '%b\t\t{ "name": "%s", "path": "%s" }' "$$sep" "$${c%%=*}" "$$(realpath -m "$${c#*=}")"; sep=',\n'; \
	done; \
	printf '\n\t],\n\t"enable_semantic_tokens": false,\n\t"enable_hover": true,\n\t"enable_snippets": false\n}\n'; } > ols.json
	@echo "ols: wrote ols.json, $(words $(OLS_COLLECTIONS)) collections"

init-workstation: ols check-toolchain ## set up a desk: ols.json and the toolchain report

# The one command after a fresh clone, the same in every repository.
setup: init-packages init-modules init-workstation ## everything a fresh clone needs: packages (sudo apt), ols.json, the toolchain report

# --- formatting: amber-house scripts/binding/fmt.mk, the same in every binding ---
# Hand-written Odin goes through odinfmt (amber-ols; odinfmt.json is amber-house's). What runic
# writes (each rune.yml's `out:`) and type_casts.odin are generated and stay as generated. Shell
# scripts go through shfmt, with tabs.
ODINFMT ?= odinfmt
ODIN_FMT ?= $(HOUSE)/scripts/odin-fmt
GENERATED = $(foreach y,$(wildcard */rune.yml),$(dir $(y))$(shell awk '$$1 == "out:" {print $$2}' $(y))) $(wildcard */type_casts.odin)
ODIN_SOURCES = git ls-files --cached --others --exclude-standard '*.odin' $(foreach g,$(GENERATED),':!$(g)')
# apt's shfmt, the one a CI runner has, before any other on the PATH: versions differ in layout.
SHFMT ?= $(firstword $(wildcard /usr/bin/shfmt) shfmt)
SHFMT_FLAGS = -i 0
SH_SOURCES = git ls-files -z --cached --others --exclude-standard | grep -zv '/$$' | xargs -0 -r $(SHFMT) -f

fmt: fmt-sh ## format the hand-written Odin and the shell scripts in place
	@$(ODIN_SOURCES) | ODINFMT=$(ODINFMT) $(ODIN_FMT)

check-fmt: check-fmt-sh ## fail when hand-written Odin or a shell script is not as make fmt leaves it
	@if ! command -v $(ODINFMT) >/dev/null; then if [ "$$GITHUB_ACTIONS" = true ]; then echo "odinfmt is not installed on this runner; the workflow asks for it (ols: true)"; exit 1; fi; echo "odinfmt not installed: skipping (apt install amber-ols)"; exit 0; fi; \
	bad=0; \
	for f in $$($(ODIN_SOURCES)); do \
		$(ODINFMT) -stdin < "$$f" | cmp -s - "$$f" || { echo "not formatted: $$f"; bad=1; }; \
	done; \
	if [ $$bad = 1 ]; then echo "fix: make fmt"; exit 1; fi; \
	echo "odinfmt OK"

fmt-sh: ## lay the shell scripts out in place
	@$(SH_SOURCES) | xargs -r -d '\n' $(SHFMT) $(SHFMT_FLAGS) -w

check-fmt-sh: ## fail when a shell script is not as make fmt-sh leaves it
	@if ! command -v $(SHFMT) >/dev/null; then \
		if [ "$$GITHUB_ACTIONS" = true ]; then echo "shfmt is not installed on this runner; the workflow installs it"; exit 1; fi; \
		echo "shfmt not installed: skipping (sudo apt install shfmt)"; exit 0; \
	fi; \
	bad=$$($(SH_SOURCES) | xargs -r -d '\n' $(SHFMT) $(SHFMT_FLAGS) -l 2>&1) || true; \
	if [ -n "$$bad" ]; then echo "not formatted:"; echo "$$bad"; echo "fix: make fmt"; exit 1; fi; \
	echo "shfmt OK"

fmt-tools: ## name a formatter that is missing
	@command -v $(SHFMT) >/dev/null || echo "missing: shfmt (apt install shfmt)"
	@command -v $(ODINFMT) >/dev/null || echo "missing: odinfmt (apt install amber-ols)"

init-workstation: fmt-tools
lint: check-fmt
