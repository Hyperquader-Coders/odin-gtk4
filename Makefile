# odin-gtk4: Odin bindings for GTK 4, GDK and GSK. Consumed via -collection:gtk4=/path/to/odin-gtk4
# Each entry is a package directory at the repo root; one with no .odin file yet is skipped.
PACKAGES = $(foreach p,gtk4,$(if $(wildcard $(p)/*.odin),$(p)))
# runic: github.com/Hyperquader-Coders/runic on branch amber-patched, built by its amber-build.sh; see odin-glib/docs/DECISIONS.md §2.
RUNIC ?= ../runic/build/runic
BRANCH ?= main
REMOTE ?= origin
ROOT_COMMIT_MSG ?= Initial odin-gtk4
GTK_STAGE ?= ../amber-gtk4/build/gtk/stage
GLIB ?= ../odin-glib
CAIRO ?= ../odin-cairo
PANGO ?= ../odin-pango
GRAPHENE ?= ../odin-graphene
PIXBUF ?= ../odin-gdk-pixbuf
# A test that leaks or frees badly fails, rather than only warning. `make test ASAN=1` runs
# the tests under AddressSanitizer as well.
ASAN ?=
# amber-gtk4's bundle (libgtk-4 4.16.13), when built, is the library the tests load; the
# distro's 4.14.5 is the floor. With the bundle present the version test is exact.
GTK_BUNDLE = $(GTK_STAGE)/usr/lib/amber-gtk4
TEST_ENV = $(if $(wildcard $(GTK_BUNDLE)/libgtk-4.so.1),LD_LIBRARY_PATH=$(abspath $(GTK_BUNDLE)) GTK_BUNDLE_EXPECTED=1)
# The test binary carries the bundle's folder as its run path too: LD_LIBRARY_PATH alone is lost
# where `odin` is a wrapper that sets its own (a mise shim does), and the system's GTK is loaded.
comma := ,
TEST_LINK = $(if $(wildcard $(GTK_BUNDLE)/libgtk-4.so.1),-extra-linker-flags:"-Wl$(comma)-rpath$(comma)$(abspath $(GTK_BUNDLE))")
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
ODIN_TEST_FLAGS = $(ODIN_FLAGS) $(TEST_LINK) -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true $(if $(ASAN),-debug -sanitize:address)

# The system packages, one list for a desk and for CI: the library the binding is generated from
# and tested against, and the tools the targets call (shellcheck in lint, shfmt in fmt-sh). `make
# deps` installs it; a package missing on the runner is added here, and the workflow names none.
DEPS := libgtk-4-dev shellcheck shfmt

.PHONY: help init deps check-toolchain ols generate check test ci clean push force-push lint api check-api check-generated check-no-agent-files check-test-tag fmt check-fmt fmt-sh check-fmt-sh

check: check-test-tag ## type-check every package with -vet -strict-style
	@for p in $(PACKAGES); do echo "== check $$p =="; odin check $$p $(ODIN_FLAGS) -no-entry-point || exit 1; done

test: ## run every package's tests (ASAN=1 adds AddressSanitizer)
	@mkdir -p build
	@for p in $(PACKAGES); do echo "== test $$p =="; env -u DISPLAY -u WAYLAND_DISPLAY $(TEST_ENV) odin test $$p $(ODIN_TEST_FLAGS) -out:build/$${p}_test || exit 1; done

# Everything a push has to pass; CI (.github/workflows/ci.yml) runs the same.
ci: check test check-no-agent-files lint ## everything a push has to pass
	@echo 'CI OK'

generate: ## run runic over every package's rune.yml, then the post-processing rules
	@test -x $(RUNIC) || { echo "runic not found at $(RUNIC): clone github.com/Hyperquader-Coders/runic beside this repo on branch amber-patched and run its amber-build.sh"; exit 2; }
	RUNIC=$(abspath $(RUNIC)) GTK_STAGE=$(GTK_STAGE) scripts/generate.sh

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
	@if command -v shellcheck >/dev/null; then \
		git ls-files | while read -r f; do \
			case "$$f" in *.sh|*.bash) echo "$$f";; \
			*) head -1 "$$f" 2>/dev/null | grep -q '^#!.*sh' && echo "$$f";; esac; \
		done | xargs -r shellcheck --severity=warning && echo "shellcheck OK"; \
	else echo "shellcheck not installed, skipping (apt install shellcheck)"; fi

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

# --- setup: amber-house scripts/binding/setup.mk, the same in every binding ---
# `make deps` installs DEPS, the list above. CI runs `sudo apt-get update && make deps
# APT_FLAGS=-y`; at a desk apt asks before it installs.
APT_FLAGS ?=

deps: ## install the system dependencies (sudo apt)
	sudo apt-get install $(APT_FLAGS) --no-install-recommends $(DEPS)

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

# The one command after a fresh clone, the same in every repository: `deps` first, which CI
# calls on its own, then what this checkout needs.
init: deps ols check-toolchain ## everything a fresh clone needs: deps, then ols and the toolchain report

# --- formatting: amber-house scripts/binding/fmt.mk, the same in every binding ---
# Hand-written Odin goes through odinfmt (amber-ols; odinfmt.json is amber-house's). What runic
# writes (each rune.yml's `out:`) and type_casts.odin are generated and stay as generated. Shell
# scripts go through shfmt, with tabs.
ODINFMT ?= odinfmt
ODIN_FMT ?= ../amber-house/scripts/odin-fmt
GENERATED = $(foreach y,$(wildcard */rune.yml),$(dir $(y))$(shell awk '$$1 == "out:" {print $$2}' $(y))) $(wildcard */type_casts.odin)
ODIN_SOURCES = git ls-files --cached --others --exclude-standard '*.odin' $(foreach g,$(GENERATED),':!$(g)')
# apt's shfmt, the one a CI runner has, before any other on the PATH: versions differ in layout.
SHFMT ?= $(firstword $(wildcard /usr/bin/shfmt) shfmt)
SHFMT_FLAGS = -i 0
SH_SOURCES = git ls-files -z --cached --others --exclude-standard | grep -zv '/$$' | xargs -0 -r $(SHFMT) -f

fmt: fmt-sh ## format the hand-written Odin and the shell scripts in place
	@$(ODIN_SOURCES) | ODINFMT=$(ODINFMT) $(ODIN_FMT)

check-fmt: check-fmt-sh ## fail when hand-written Odin or a shell script is not as make fmt leaves it
	@if ! command -v $(ODINFMT) >/dev/null; then if [ "$$GITHUB_ACTIONS" = true ]; then echo "odinfmt is not installed on this runner; the workflow asks for it (ols: true)"; exit 1; fi; echo "odinfmt not installed, skipping (apt install amber-ols)"; exit 0; fi; \
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
		echo "shfmt not installed, skipping (sudo apt install shfmt)"; exit 0; \
	fi; \
	bad=$$($(SH_SOURCES) | xargs -r -d '\n' $(SHFMT) $(SHFMT_FLAGS) -l 2>&1) || true; \
	if [ -n "$$bad" ]; then echo "not formatted:"; echo "$$bad"; echo "fix: make fmt"; exit 1; fi; \
	echo "shfmt OK"

lint: check-fmt
